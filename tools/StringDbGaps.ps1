# StringDbGaps.ps1 — промахи StringDB из логов диагностики -> категории, отчёт и новые записи батчей (TASK-012, A2).
#
# Источник: строки src=stringdb в absru-s*-untranslated-*.jsonl (Diag.OnDbMiss: для строки оверлея CPDD
# Loader.TranslateDatabaseString вернул nil). Уникально по module|row.
# Сверка с батчами повторяет ShardCompiler.cs (тот же разбор JSON, EN-приоритет batch_028, explicitAliases,
# обрезанные ключи) и рантайм (lookupGeminiText + lookupGeminiTextFuzzy). Ключи сравниваются побайтно (Ordinal).
#
# Примеры:
#   powershell -File tools\StringDbGaps.ps1 -Report
#   powershell -File tools\StringDbGaps.ps1 -Report -Logs reference\logs\2026-09-25_1300 -Sid 20260925-125104
#   powershell -File tools\StringDbGaps.ps1 -Aliases batch_030_stringdb_aliases.json
#   powershell -File tools\StringDbGaps.ps1 -Emit batch_031_autochess_stringdb.json -Category autochess,formula
#
# Пишет только внутри репозитория: CSV в temp\, батчи в source\translation_batches\.
param(
    [string[]]$Logs,               # файлы .jsonl или папки; по умолчанию reference\logs\*\Saved\Mods\logs
    [string]$Sid,                  # только одна сессия диагностики
    [switch]$Report,               # сводка по категориям + CSV
    [string]$Emit,                 # имя батча: дописать строки категорий -Category с пустым target_ru
    [string[]]$Category,
    [string]$Aliases,              # имя батча: алиасы для строк, отличающихся от батча регистром/пробелами/тегами
    [string]$Csv                   # по умолчанию temp\stringdb_gaps.csv
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Web.Extensions

$repo = Split-Path $PSScriptRoot -Parent
$batchesDir = Join-Path $repo 'source\translation_batches'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$ordinal = [StringComparer]::Ordinal

# Категории (раздел 4 TASK-012). Порядок проверки задаёт Get-GapCategory.
$categoryInfo = [ordered]@{
    alias_case = 'P0: отличается от батча регистром/пробелами (перевод есть)'
    alias_tags = 'P0: отличается от батча только тегами (перевод есть, теги поправить)'
    autochess  = 'P1: Автошахматы'
    formula    = 'P1: формулы навыков {*d,…}'
    ui         = 'P2: короткие подписи UI, названия'
    quest      = 'P2: задания, цели и шаги (<h>)'
    mail       = 'P2: письма, объявления, награды'
    skill      = 'P3: навыки'
    buff       = 'P3: баффы (_buffdata)'
    assistant  = 'P3: справка ассистента (<Assistant_*>)'
    equip      = 'P3: снаряжение, клейма и комплекты'
    npc        = 'P4: реплики NPC'
    item       = 'P4: предметы (_item*)'
    loading    = 'P4: подсказки загрузки'
    text       = 'P4: прочий текст'
    service    = 'не переводить: служебные имена'
    technical  = 'не переводить: техническое'
    known      = 'уже переводится (ключ есть в шардах)'
    pending    = 'есть в батче без перевода'
}
$neverEmit = @('service', 'technical', 'known', 'pending')

function Resolve-RepoPath([string]$path) {
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
    $root = $repo.TrimEnd('\') + '\'
    if (-not ($full.TrimEnd('\') + '\').StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Путь вне репозитория: $path"
    }
    return $full
}

# --- Батчи с семантикой ShardCompiler.cs -----------------------------------------------------------
function Expand-JsonEscape([string]$s) {
    # Копия FastShardCompiler.UnescapeJson: последовательные Replace, не полноценный JSON.
    if ([string]::IsNullOrEmpty($s)) { return '' }
    return $s.Replace('\"', '"').Replace('\\', '\').Replace('\r', "`r").Replace('\n', "`n").Replace('\t', "`t").
        Replace('\u003c', '<').Replace('\u003e', '>').Replace('\u0027', "'").Replace('\u0026', '&')
}
function Get-TrimmedKey([string]$s) {
    # Lua %s: пробел, \t, \n, \v, \f, \r
    return $s.Trim([char[]]@(' ', "`t", "`n", [char]11, [char]12, "`r"))
}

$shard = New-Object 'System.Collections.Generic.Dictionary[string,string]' ($ordinal)
$batchKeyInfo = New-Object 'System.Collections.Generic.Dictionary[string,object]' ($ordinal)  # ключ -> @{ batch; id; ru }
$trimmedPending = New-Object 'System.Collections.Generic.List[object]'
$maxId = 0
$itemRegex = [regex]'"id"\s*:\s*"([^"]+)"\s*,\s*"source_cn"\s*:\s*"((?:\\"|[^"])*)"\s*,\s*"ref_en"\s*:\s*"((?:\\"|[^"])*)"\s*,\s*"target_ru"\s*:\s*"((?:\\"|[^"])*)"'
foreach ($file in Get-ChildItem -LiteralPath $batchesDir -Filter 'batch_*.json' | Sort-Object Name) {
    $isBatch28 = $file.Name -like 'batch_028*'
    $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    foreach ($m in $itemRegex.Matches($text)) {
        $id = $m.Groups[1].Value
        $cn = Expand-JsonEscape $m.Groups[2].Value
        $en = Expand-JsonEscape $m.Groups[3].Value
        $ru = Expand-JsonEscape $m.Groups[4].Value
        $n = 0; if ([int]::TryParse($id, [ref]$n) -and $n -gt $maxId) { $maxId = $n }
        $info = @{ batch = $file.BaseName; id = $id; ru = $ru }
        if ($cn) {
            $shard[$cn] = $(if ($ru) { $ru } else { $en })
            if (-not $batchKeyInfo.ContainsKey($cn) -or $ru) { $batchKeyInfo[$cn] = $info }
            $t = Get-TrimmedKey $cn
            if ($t -and $t -ne $cn) { $trimmedPending.Add(@($t, $cn)) }
        }
        if ($en -and $ru) {
            if ($isBatch28 -or -not $shard.ContainsKey($en)) { $shard[$en] = $ru }
            if (-not $batchKeyInfo.ContainsKey($en)) { $batchKeyInfo[$en] = $info }
            $t = Get-TrimmedKey $en
            if ($t -and $t -ne $en) { $trimmedPending.Add(@($t, $en)) }
        } elseif ($en -and -not $batchKeyInfo.ContainsKey($en)) {
            $batchKeyInfo[$en] = $info
        }
    }
}
# Обрезанные ключи: только если такой ключ ещё не занят (как в ShardCompiler.cs).
foreach ($pair in $trimmedPending) {
    if (-not $shard.ContainsKey($pair[0]) -and $shard.ContainsKey($pair[1])) {
        $shard[$pair[0]] = Get-TrimmedKey $shard[$pair[1]]
    }
}
# explicitAliases из ShardCompiler.cs
$compilerText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ShardCompiler.cs'), $utf8)
$aliasBlock = [regex]::Match($compilerText, '(?s)var explicitAliases = new Dictionary<string, string> \{(.*?)\n\s*\};')
foreach ($m in [regex]::Matches($aliasBlock.Groups[1].Value, '\{\s*"((?:\\.|[^"\\])*)"\s*,\s*"((?:\\.|[^"\\])*)"\s*\}')) {
    $k = $m.Groups[1].Value.Replace('\"', '"').Replace('\n', "`n").Replace('\r', "`r").Replace('\\', '\')
    $v = $m.Groups[2].Value.Replace('\"', '"').Replace('\n', "`n").Replace('\r', "`r").Replace('\\', '\')
    $shard[$k] = $v
}

# --- Поиск как в рантайме (Init.lua: lookupGeminiText + lookupGeminiTextFuzzy) --------------------
function Find-ShardTranslation([string]$value, [int]$depth = 0) {
    if ([string]::IsNullOrEmpty($value) -or $depth -gt 8) { return $null }
    if ($shard.ContainsKey($value)) { return $shard[$value] }
    if ($value.Contains("`r")) {
        $normalized = $value.Replace("`r`n", "`n").Replace("`r", "`n")
        if ($shard.ContainsKey($normalized)) { return $shard[$normalized] }
        $t = Get-TrimmedKey $normalized
        if ($t -and $shard.ContainsKey($t)) { return $shard[$t] }
    }
    $t = Get-TrimmedKey $value
    if ($t -and $t -ne $value -and $shard.ContainsKey($t)) { return $shard[$t] }
    $m = [regex]::Match($value, '^(<[^>]+>)(.*?)(</>)$', 'Singleline')
    if ($m.Success -and $m.Groups[2].Value) {
        $r = Find-ShardTranslation $m.Groups[2].Value ($depth + 1)
        if ($null -ne $r) { return $m.Groups[1].Value + $r + '</>' }
    }
    $m = [regex]::Match($value, '^(.*?)([:：\-\?\.]+)[ \t\n\r\v\f]*$', 'Singleline')
    if ($m.Success -and $m.Groups[1].Value) {
        $r = Find-ShardTranslation $m.Groups[1].Value ($depth + 1)
        if ($null -ne $r) { return $r + $m.Groups[2].Value }
    }
    $m = [regex]::Match($value, '^([\[\{\(【])(.*?)([\]\}\)】])$', 'Singleline')
    if ($m.Success -and $m.Groups[2].Value) {
        $r = Find-ShardTranslation $m.Groups[2].Value ($depth + 1)
        if ($null -ne $r) { return $m.Groups[1].Value + $r + $m.Groups[3].Value }
    }
    return $null
}

# --- Нормализованные индексы для алиасов ----------------------------------------------------------
$wsRegex = New-Object regex '\s+', 'Compiled'
$tagRegex = New-Object regex '<[^>]*>', 'Compiled'
$cyrRegex = New-Object regex (('[' + [char]0x0400 + '-' + [char]0x04FF + ']'), 'Compiled')
function Get-LooseKey([string]$s) {
    return $wsRegex.Replace($s, ' ').Trim().ToLowerInvariant()
}
function Get-TaglessKey([string]$s) {
    return $wsRegex.Replace($tagRegex.Replace($s, ''), ' ').Trim().ToLowerInvariant()
}
$looseIndex = New-Object 'System.Collections.Generic.Dictionary[string,string]' ($ordinal)
$taglessIndex = New-Object 'System.Collections.Generic.Dictionary[string,string]' ($ordinal)
foreach ($kv in $shard.GetEnumerator()) {
    $key = $kv.Key; $v = $kv.Value
    if (-not $cyrRegex.IsMatch($v)) { continue }   # только ключи с русским переводом
    $lk = $wsRegex.Replace($key, ' ').Trim().ToLowerInvariant()
    if ($lk -and -not $looseIndex.ContainsKey($lk)) { $looseIndex[$lk] = $key }
    $tk = $(if ($key.IndexOf('<') -ge 0) { $wsRegex.Replace($tagRegex.Replace($key, ''), ' ').Trim().ToLowerInvariant() } else { $lk })
    if ($tk -and -not $taglessIndex.ContainsKey($tk)) { $taglessIndex[$tk] = $key }
}

# --- Категории: одна функция, правила по модулю и тексту ------------------------------------------
function Get-GapCategory($row) {
    $cn = $row.cn; $en = $row.en; $module = $row.module
    $text = $(if ($cn) { $cn } else { $en })
    $both = "$cn`n$en"
    $tag = ''
    $mm = [regex]::Match($module, 'StringDB_CN_Data_([A-Za-z0-9_]+)$')
    if ($mm.Success) { $tag = $mm.Groups[1].Value }
    # перевод уже есть под другим ключом: алиас нужен и служебным строкам
    if ($row.alias_kind) { return $row.alias_kind }

    # техническое: base64, числа, id, пути, нет букв
    if ($text -match '^[A-Za-z0-9+/=]{16,}$' -or $text -match '^[\d\s\.,:;/\-_+#%]*$' -or $text -match "Texture2D'|/Game/|\.uasset|^\[UIFrame" -or
        -not ($text -match '[A-Za-z\u3400-\u9fff]')) { return 'technical' }
    # служебные имена
    if ($tag -in @('debug', 'spellfield', 'buffappear')) { return 'service' }
    if ($en -match '(?i)\btest(ing)?\b' -or $cn -match '测试|调试|废弃|备用|占位') { return 'service' }
    if (($text -match '^[^。，！？,!?]*(\s?[-_]\s?[^-_]+){2,}$') -and ($text -notmatch '[。！？]') -and $text.Length -lt 80 -and ($text -match '\s-\s|_')) { return 'service' }

    if ($cn -match '棋子|弈|共鸣|羁绊|棋|阵容|金币' -or $en -match '(?i)\bpieces?\b|resonance|gold coins?|\blineup|chess') { return 'autochess' }
    if ($both.Contains('{*d,')) { return 'formula' }
    if ($both -match '<Assistant_') { return 'assistant' }
    if ($both -match '<CostRed>|<Mark>') { return 'equip' }
    if ($tag -eq 'buffdata') { return 'buff' }
    if ($tag -in @('gossip', 'talkother', 'othertalk', 'tingentalk')) { return 'npc' }
    if ($tag -like 'item*') { return 'item' }
    if ($tag -eq 'loading') { return 'loading' }
    if ($tag -like 'skill*' -or $tag -eq 'monsterskill') { return 'skill' }
    if ($both -match '<h>') { return 'quest' }
    if ($en -match '(?i)\b(damage|deals?|cooldown|attack speed|stun|heal(s|ing)?|shield|knock|seconds?)\b' -or $cn -match '伤害|冷却|眩晕|治疗|护盾|秒') { return 'skill' }
    if ($en -match '(?i)\b(mail|reward|announcement|compensation|event|gift)\b' -or $cn -match '邮件|奖励|公告|补偿|礼包') { return 'mail' }
    $plain = [regex]::Replace($text, '<[^>]*>', '')
    $short = $(if ($cn) { $plain.Length -le 12 } else { $plain.Length -le 40 })
    if ($short -and ($plain -notmatch '[。！？!?]')) { return 'ui' }
    return 'text'
}

# --- Логи ----------------------------------------------------------------------------------------
if (-not $Logs -or $Logs.Count -eq 0) { $Logs = @(Join-Path $repo 'reference\logs') }
$logFiles = New-Object 'System.Collections.Generic.List[string]'
foreach ($p in $Logs) {
    $full = Resolve-RepoPath $p
    if (Test-Path -LiteralPath $full -PathType Container) {
        foreach ($f in Get-ChildItem -LiteralPath $full -Recurse -File -Filter 'absru-s*-untranslated-*.jsonl') { $logFiles.Add($f.FullName) }
    } elseif (Test-Path -LiteralPath $full) { $logFiles.Add($full) }
}
if ($logFiles.Count -eq 0) { throw "Логи untranslated не найдены: $($Logs -join ', ')" }

$json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$json.MaxJsonLength = [int]::MaxValue
$rows = New-Object 'System.Collections.Generic.Dictionary[string,object]' ($ordinal)
$onScreen = New-Object 'System.Collections.Generic.HashSet[string]' ($ordinal)
foreach ($file in $logFiles) {
    foreach ($line in [IO.File]::ReadLines($file, $utf8)) {
        if (-not $line) { continue }
        if ($Sid -and -not $line.Contains('"sid":"' + $Sid + '"')) { continue }
        if (-not $line.Contains('"src":"stringdb"')) {
            if ($line.Contains('"src":"widget"') -or $line.Contains('"src":"data"')) {
                $o = $json.DeserializeObject($line)
                foreach ($k in @('text', 'original', 'translated')) { if ($o[$k]) { [void]$onScreen.Add((Get-TrimmedKey ([string]$o[$k]))) } }
            }
            continue
        }
        $o = $json.DeserializeObject($line)
        $key = [string]$o['module'] + '|' + [string]$o['row']
        if ($rows.ContainsKey($key)) { continue }
        $rows[$key] = [pscustomobject]@{
            module = [string]$o['module']; row = [string]$o['row']; cn = [string]$o['cn']; en = [string]$o['en']
            category = ''; alias_kind = ''; alias_key = ''; ru = ''; on_screen = $false
        }
    }
}

# --- Классификация -------------------------------------------------------------------------------
foreach ($r in $rows.Values) {
    $r.on_screen = ($r.cn -and $onScreen.Contains((Get-TrimmedKey $r.cn))) -or ($r.en -and $onScreen.Contains((Get-TrimmedKey $r.en)))
    $hit = $null
    if ($r.cn) { $hit = Find-ShardTranslation $r.cn }
    if ($null -eq $hit -and $r.en) { $hit = Find-ShardTranslation $r.en }
    if ($null -ne $hit -and $hit -match '[\u0400-\u04FF]') { $r.category = 'known'; $r.ru = $hit; continue }
    if (($r.cn -and $batchKeyInfo.ContainsKey($r.cn)) -or ($r.en -and $batchKeyInfo.ContainsKey($r.en))) { $r.category = 'pending'; continue }
    foreach ($src in @($r.cn, $r.en)) {
        if (-not $src) { continue }
        $lk = Get-LooseKey $src
        if ($looseIndex.ContainsKey($lk)) { $r.alias_kind = 'alias_case'; $r.alias_key = $looseIndex[$lk]; break }
    }
    if (-not $r.alias_kind) {
        foreach ($src in @($r.cn, $r.en)) {
            if (-not $src) { continue }
            $tk = Get-TaglessKey $src
            if ($tk.Length -ge 2 -and $taglessIndex.ContainsKey($tk)) { $r.alias_kind = 'alias_tags'; $r.alias_key = $taglessIndex[$tk]; break }
        }
    }
    if ($r.alias_kind) { $r.ru = $shard[$r.alias_key] }
    $r.category = Get-GapCategory $r
}
$all = @($rows.Values | Sort-Object module, { [decimal]$_.row })

# --- Отчёт ---------------------------------------------------------------------------------------
if ($Report -or (-not $Emit -and -not $Aliases)) {
    $csvPath = $(if ($Csv) { Resolve-RepoPath $Csv } else { Join-Path $repo 'temp\stringdb_gaps.csv' })
    New-Item -ItemType Directory -Force (Split-Path $csvPath -Parent) | Out-Null
    $csvText = ($all | Select-Object category, on_screen, module, row, cn, en, alias_key, ru | ConvertTo-Csv -NoTypeInformation) -join "`n"
    [IO.File]::WriteAllText($csvPath, $csvText + "`n", $utf8)
    $missing = @($all | Where-Object { $_.category -notin @('known') })
    Write-Host ("Логов: {0}, строк StringDB (module|row): {1}, без русского: {2}, на экране: {3}" -f $logFiles.Count, $all.Count, $missing.Count, @($all | Where-Object { $_.on_screen -and $_.category -ne 'known' }).Count)
    Write-Host ''
    Write-Host ('{0,-11} {1,6} {2,6}  {3}' -f 'категория', 'строк', 'экран', 'описание')
    foreach ($c in $categoryInfo.Keys) {
        $g = @($all | Where-Object { $_.category -eq $c })
        if ($g.Count -eq 0) { continue }
        Write-Host ('{0,-11} {1,6} {2,6}  {3}' -f $c, $g.Count, @($g | Where-Object { $_.on_screen }).Count, $categoryInfo[$c])
    }
    Write-Host ''
    Write-Host "CSV: $csvPath"
}

# --- Запись в батч -------------------------------------------------------------------------------
function Format-JsonText([string]$s) {
    # Как JSON.stringify: экранируются только ", \ и управляющие символы.
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            ([char]8) { [void]$sb.Append('\b') }
            ([char]12) { [void]$sb.Append('\f') }
            default {
                if ([int]$ch -lt 0x20) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) }
            }
        }
    }
    return '"' + $sb.ToString() + '"'
}
function Add-BatchRecords([string]$name, $records) {
    if ($name -notmatch '^batch_\d{3}[A-Za-z0-9_]*\.json$') { throw "Имя батча должно быть batch_NNN_*.json: $name" }
    $path = Join-Path $batchesDir $name
    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rec in $records) {
        $parts.Add("  {`n    `"id`": $(Format-JsonText $rec.id),`n    `"source_cn`": $(Format-JsonText $rec.source_cn),`n    `"ref_en`": $(Format-JsonText $rec.ref_en),`n    `"target_ru`": $(Format-JsonText $rec.target_ru)`n  }")
    }
    $body = $parts -join ",`n"
    if (Test-Path -LiteralPath $path) {
        $old = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF).Replace("`r`n", "`n").TrimEnd()
        if (-not $old.EndsWith(']')) { throw "Не JSON-массив: $path" }
        $head = $old.Substring(0, $old.Length - 1).TrimEnd()
        $text = $(if ($head -eq '[') { "[`n" + $body + "`n]`n" } else { $head + ",`n" + $body + "`n]`n" })
    } else {
        $text = "[`n" + $body + "`n]`n"
    }
    [IO.File]::WriteAllText($path, $text, $utf8)
    Write-Host "Записано $($records.Count) строк в $name (id $($records[0].id)…$($records[-1].id))"
}

$nextId = $maxId + 1
$usedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ($ordinal)

if ($Aliases) {
    $recs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($r in $all | Where-Object { $_.category -in @('alias_case', 'alias_tags') }) {
        # alias_case: ключ = текст StringDB как есть (EN, для разделённых модулей cn пуст); alias_tags: ключ CN, если есть
        if ($r.category -eq 'alias_case') {
            $src = $(if ($r.cn -and (Get-LooseKey $r.cn) -eq (Get-LooseKey $r.alias_key)) { $r.cn } else { $r.en })
            $refEn = $src
            if ($src -eq $r.cn) { $refEn = $r.en }
        } else {
            $src = $(if ($r.cn) { $r.cn } else { $r.en }); $refEn = $r.en
        }
        if (-not $src -or $shard.ContainsKey($src) -or -not $usedKeys.Add($src)) { continue }
        $recs.Add([pscustomobject]@{ id = ('{0:D6}' -f $nextId); source_cn = $src; ref_en = $refEn; target_ru = $r.ru })
        $nextId++
    }
    if ($recs.Count -gt 0) { Add-BatchRecords $Aliases $recs } else { Write-Host 'Алиасов для записи нет.' }
}

if ($Emit) {
    if (-not $Category -or $Category.Count -eq 0) { throw 'Для -Emit нужен -Category <категория[,…]>' }
    foreach ($c in $Category) {
        if (-not $categoryInfo.Contains($c)) { throw "Неизвестная категория: $c. Есть: $($categoryInfo.Keys -join ', ')" }
        if ($c -in $neverEmit) { throw "Категорию $c не выгружают" }
    }
    $recs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($r in $all | Where-Object { $_.category -in $Category }) {
        $src = $(if ($r.cn) { $r.cn } else { $r.en })
        if (-not $src -or $shard.ContainsKey($src) -or $batchKeyInfo.ContainsKey($src) -or -not $usedKeys.Add($src)) { continue }
        $recs.Add([pscustomobject]@{ id = ('{0:D6}' -f $nextId); source_cn = $src; ref_en = $r.en; target_ru = '' })
        $nextId++
    }
    if ($recs.Count -gt 0) { Add-BatchRecords $Emit $recs } else { Write-Host 'Новых строк для записи нет.' }
}
