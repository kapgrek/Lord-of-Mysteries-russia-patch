# GlossaryCheck.ps1 - сверка target_ru с глоссарием боевых характеристик (source/glossary/combat_stats.json), без ИИ
#   -Report   [-Terms 穿刺,破防]   таблица корзин по батчам + temp/glossary_report.md (+ .json со сводкой)
#   -FixShort                     корзина A: короткая подпись = канон (печатает «было → стало»)
#   -Export   [-Count 50]         корзины B + C чанками в temp/glossary_chunk_NNN.json
#   -Import   <файл>              ответ { "batch_005:020853": "новый target_ru" } с проверкой канона и разметки
#   -BuildDoc                     пересобрать docs/GLOSSARY.md из source/glossary/*.json
# Корзины: ok — канон есть, запрещённых вариантов нет; A — короткая подпись, которую можно заменить каноном целиком;
# B — есть известный неверный вариант; C — ни канона, ни варианта; S — служебный ключ или пустой ref_en;
# E — перевода нет (target_ru пуст); X — термин только внутри cn_exclude (ложное совпадение).
param(
    [switch]$Report,
    [switch]$FixShort,
    [switch]$Export,
    [string]$Import = '',
    [switch]$BuildDoc,
    [string[]]$Terms = @(),
    [int]$Count = 50,
    [string]$ReportFile = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$batchesDir = Join-Path $root 'source\translation_batches'
$glossaryDir = Join-Path $root 'source\glossary'
$tempDir = Join-Path $root 'temp'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)   # батчи и JSON: UTF-8 без BOM, LF (AGENTS.md §5)
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
$Terms = @($Terms | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$ro = [System.Text.RegularExpressions.RegexOptions]
$ic = $ro::IgnoreCase -bor $ro::CultureInvariant
$itemRegex = [regex]::new('\{\s*"id"\s*:\s*"(?<id>[^"]+)"\s*,\s*"source_cn"\s*:\s*"(?<cn>(?:\\.|[^"\\])*)"\s*,\s*"ref_en"\s*:\s*"(?<en>(?:\\.|[^"\\])*)"\s*,\s*"target_ru"\s*:\s*"(?<ru>(?:\\.|[^"\\])*)"\s*\}', $ro::Compiled)
$unescapeRegex = [regex]::new('\\(u[0-9a-fA-F]{4}|.)', $ro::Compiled)
# Разметка, которую маскируем перед поиском терминов в target_ru: теги (с атрибутами) и {…}-вставки
$markupRegex = [regex]::new('<[^<>]*>|\{[^{}]*\}', $ro::Compiled)
$serviceRegex = [regex]::new('_(数值|百分比|值)|[A-Za-z0-9]_[A-Za-z0-9]', $ro::Compiled)
$punctRegex = [regex]::new('[\p{P}\p{S}\s\d]', $ro::Compiled)

function ConvertFrom-JsonString([string]$raw) {
    if ($raw.IndexOf('\') -lt 0) { return $raw }
    return $unescapeRegex.Replace($raw, {
        param($m)
        $c = $m.Groups[1].Value
        switch -CaseSensitive ($c) {
            'n' { "`n" } 'r' { "`r" } 't' { "`t" } 'b' { [string][char]8 } 'f' { [string][char]12 }
            default { if ($c.Length -eq 5) { [string][char][Convert]::ToInt32($c.Substring(1), 16) } else { $c } }
        }
    })
}
function ConvertTo-JsonString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '\' { [void]$sb.Append('\\') } '"' { [void]$sb.Append('\"') }
            "`n" { [void]$sb.Append('\n') } "`r" { [void]$sb.Append('\r') } "`t" { [void]$sb.Append('\t') }
            default { if ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
        }
    }
    return $sb.ToString()
}
function Read-Text([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF).Replace("`r`n", "`n")
}

# --- Глоссарий ---
$glossary = (Read-Text (Join-Path $glossaryDir 'combat_stats.json')) | ConvertFrom-Json
$entries = @()
foreach ($t in $glossary.terms) {
    $parent = if ($t.parent) { [string]$t.parent } else { [string]$t.cn }
    $entries += [PSCustomObject]@{
        cn = [string]$t.cn; parent = $parent; isBase = -not $t.parent
        ru = [string]$t.ru; ru_short = if ($t.ru_short) { [string]$t.ru_short } else { [string]$t.ru }
        match = if ($t.ru_match) { [regex]::new([string]$t.ru_match, $ic) } else { $null }
        forbidden = @($t.forbidden | Where-Object { $_ } | ForEach-Object { [regex]::new([string]$_, $ic) })
        forbiddenText = @($t.forbidden | Where-Object { $_ })
        exclude = @($t.cn_exclude | Where-Object { $_ })
        note = [string]$t.note
    }
}
$baseEntries = @($entries | Where-Object { $_.isBase })
$byCn = @{}; foreach ($e in $entries) { $byCn[$e.cn] = $e }
if ($Terms.Count) {
    foreach ($t in $Terms) { if (-not $byCn.ContainsKey($t) -or -not $byCn[$t].isBase) { throw "Термина $t нет среди базовых в combat_stats.json" } }
    $baseEntries = @($baseEntries | Where-Object { $Terms -contains $_.cn })
}

# --- Классификация строки ---
# Возвращает объект: базовые термины строки с корзинами, все найденные записи (для чанка), признак подписи
function Test-Row([string]$cn, [string]$en, [string]$ru) {
    $cnPlain = $markupRegex.Replace($cn, '')
    $ruMasked = $markupRegex.Replace($ru, ' ')
    $isService = $serviceRegex.IsMatch($cnPlain) -or [string]::IsNullOrWhiteSpace($en)
    $found = @{}   # base cn -> cn с вырезанными исключениями
    foreach ($b in $baseEntries) {
        if (-not $cnPlain.Contains($b.cn)) { continue }
        $cut = $cnPlain
        foreach ($x in $b.exclude) { $cut = $cut.Replace($x, '') }
        $found[$b.cn] = $cut
    }
    $result = @()
    foreach ($b in $baseEntries) {
        if (-not $found.ContainsKey($b.cn)) { continue }
        $bucket = $null
        if (-not $found[$b.cn].Contains($b.cn)) { $bucket = 'X' }
        elseif ($isService) { $bucket = 'S' }
        elseif ([string]::IsNullOrWhiteSpace($ru)) { $bucket = 'E' }
        # канон других терминов этой строки не должен считаться запрещённым вариантом (破甲 «пробивание брони» в строке с 穿刺)
        $masked = $ruMasked
        foreach ($o in $baseEntries) {
            if ($o.cn -ne $b.cn -and $found.ContainsKey($o.cn) -and $o.match) { $masked = $o.match.Replace($masked, ' ') }
        }
        $bad = @($b.forbidden | Where-Object { $_.IsMatch($masked) } | ForEach-Object { $_.Match($masked).Value })
        $hasCanon = $b.match.IsMatch($ruMasked)
        if (-not $bucket) {
            if ($hasCanon -and $bad.Count -eq 0) { $bucket = 'ok' }
            elseif (Test-ShortLabel $cnPlain $ru $b $bad) { $bucket = 'A' }
            elseif ($bad.Count) { $bucket = 'B' }
            else { $bucket = 'C' }
        }
        $result += [PSCustomObject]@{ term = $b.cn; bucket = $bucket; bad = ($bad -join ', ') }
    }
    return $result
}
# Короткая подпись, которую можно заменить каноном целиком: cn = ровно запись глоссария, перевод пуст или 1–4 слова с неверным вариантом
function Get-LabelEntry([string]$cnPlain) {
    $core = $cnPlain.Trim().TrimEnd([char]0xFF1A, ':').Trim()
    if ($byCn.ContainsKey($core)) { return $byCn[$core] }
    return $null
}
function Test-ShortLabel([string]$cnPlain, [string]$ru, $base, [string[]]$bad) {
    $e = Get-LabelEntry $cnPlain
    if (-not $e -or $e.parent -ne $base.cn) { return $false }
    if ([string]::IsNullOrWhiteSpace($ru)) { return $true }
    $words = @($ru.Trim() -split '\s+').Count
    return ($words -le 4 -and $bad.Count -gt 0)
}
function Get-CanonLabel([string]$cnPlain, [string]$oldRu) {
    $e = Get-LabelEntry $cnPlain
    $new = if ($oldRu.Contains('.')) { $e.ru_short } else { $e.ru }
    $new = $new.Substring(0, 1).ToUpper() + $new.Substring(1)
    if ($oldRu.TrimEnd().EndsWith(':') -or $cnPlain.TrimEnd().EndsWith([string][char]0xFF1A)) { $new += ':' }
    return $new
}

# --- Чтение всех батчей ---
function Get-Rows {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($f in Get-ChildItem $batchesDir -Filter 'batch_*.json' | Sort-Object Name) {
        $prefix = $f.BaseName.Substring(0, 9)
        $text = Read-Text $f.FullName
        foreach ($m in $itemRegex.Matches($text)) {
            $cnRaw = $m.Groups['cn'].Value
            $hit = $false
            foreach ($b in $baseEntries) { if ($cnRaw.Contains($b.cn)) { $hit = $true; break } }
            if (-not $hit) { continue }
            $cn = ConvertFrom-JsonString $cnRaw
            $en = ConvertFrom-JsonString $m.Groups['en'].Value
            $ru = ConvertFrom-JsonString $m.Groups['ru'].Value
            $rowTerms = @(Test-Row $cn $en $ru)
            if ($rowTerms.Count -eq 0) { continue }
            $rows.Add([PSCustomObject]@{ key = "${prefix}:$($m.Groups['id'].Value)"; file = $f.FullName; id = $m.Groups['id'].Value
                cn = $cn; en = $en; ru = $ru; terms = $rowTerms })
        }
    }
    return $rows
}
function Get-Worst($row) {
    $order = @('B', 'C', 'A', 'E', 'ok', 'S', 'X')
    foreach ($o in $order) { if (@($row.terms | Where-Object { $_.bucket -eq $o }).Count) { return $o } }
    return 'ok'
}

# --- Запись в батч: target_ru по id, остальное побайтно как было ---
function Write-BatchChanges([hashtable]$changesByFile) {
    foreach ($file in $changesByFile.Keys) {
        $map = $changesByFile[$file]
        $text = Read-Text $file
        $text = $itemRegex.Replace($text, {
            param($m)
            $id = $m.Groups['id'].Value
            if (-not $map.ContainsKey($id)) { return $m.Value }
            $g = $m.Groups['ru']
            $off = $g.Index - $m.Index
            return $m.Value.Substring(0, $off) + (ConvertTo-JsonString $map[$id]) + $m.Value.Substring($off + $g.Length)
        })
        [System.IO.File]::WriteAllText($file, $text, $utf8NoBom)
        Write-Host ("  {0}: {1} строк" -f [System.IO.Path]::GetFileName($file), $map.Count) -ForegroundColor DarkGray
    }
}

# --- Разметка: число вставок должно сохраниться ---
$tokenRegexes = [ordered]@{
    'printf'  = [regex]::new('%[-+0-9.]*[sdfeEgGcxX]')
    'star'    = [regex]::new('\*\.?\d*[df]')
    'pos'     = [regex]::new('\{\d+\}')
    'formula' = [regex]::new('\{\*[a-z]+,[^}]*\}')
    'brace'   = [regex]::new('\{[^{}]*\}')
    'tag'     = [regex]::new('<(?!/)[A-Za-z_][A-Za-z0-9_]*')
    'close'   = [regex]::new('</>')
    'newline' = [regex]::new('\n|\\n')
}
function Get-TokenSig([string]$s, [string]$kind) {
    $list = @($tokenRegexes[$kind].Matches($s) | ForEach-Object { if ($kind -in 'formula', 'pos', 'tag') { $_.Value } else { 'x' } })
    return (($list | Sort-Object) -join '|')
}
function Test-Markup([string]$cn, [string]$old, [string]$new) {
    $errs = @()
    foreach ($k in $tokenRegexes.Keys) {
        $n = Get-TokenSig $new $k
        if ($n -ne (Get-TokenSig $cn $k) -and $n -ne (Get-TokenSig $old $k)) { $errs += $k }
    }
    return $errs
}

# ============ -Report ============
if ($Report) {
    $rows = Get-Rows
    $buckets = @('ok', 'A', 'B', 'C', 'S', 'E', 'X')
    $stats = [ordered]@{}
    foreach ($b in $baseEntries) { $stats[$b.cn] = [ordered]@{ ru = $b.ru; total = 0 }; foreach ($k in $buckets) { $stats[$b.cn][$k] = 0 } }
    foreach ($r in $rows) { foreach ($t in $r.terms) { $stats[$t.term].total++; $stats[$t.term][$t.bucket]++ } }

    Write-Host ("{0,-6} {1,-18} {2,6} {3,5} {4,4} {5,4} {6,4} {7,4} {8,4} {9,4}" -f 'Термин', 'Канон', 'Строк', 'ok', 'A', 'B', 'C', 'S', 'E', 'X') -ForegroundColor Cyan
    $sum = @{}; foreach ($k in $buckets + 'total') { $sum[$k] = 0 }
    foreach ($cn in $stats.Keys) {
        $s = $stats[$cn]
        Write-Host ("{0,-6} {1,-18} {2,6} {3,5} {4,4} {5,4} {6,4} {7,4} {8,4} {9,4}" -f $cn, $s.ru, $s.total, $s.ok, $s.A, $s.B, $s.C, $s.S, $s.E, $s.X)
        foreach ($k in $buckets + 'total') { $sum[$k] += $s[$k] }
    }
    Write-Host ("{0,-6} {1,-18} {2,6} {3,5} {4,4} {5,4} {6,4} {7,4} {8,4} {9,4}" -f 'Итого', '', $sum.total, $sum.ok, $sum.A, $sum.B, $sum.C, $sum.S, $sum.E, $sum.X) -ForegroundColor Green

    $out = if ($ReportFile) { $ReportFile } else { Join-Path $tempDir 'glossary_report.md' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# GlossaryCheck -Report ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))`n")
    [void]$sb.AppendLine('| Термин | Канон | Строк | ok | A | B | C | S | E | X |')
    [void]$sb.AppendLine('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|')
    foreach ($cn in $stats.Keys) { $s = $stats[$cn]; [void]$sb.AppendLine("| $cn | $($s.ru) | $($s.total) | $($s.ok) | $($s.A) | $($s.B) | $($s.C) | $($s.S) | $($s.E) | $($s.X) |") }
    foreach ($k in 'A', 'B', 'C', 'S', 'E', 'X') {
        [void]$sb.AppendLine("`n## Корзина $k`n")
        foreach ($r in $rows) {
            foreach ($t in @($r.terms | Where-Object { $_.bucket -eq $k })) {
                $cnShort = $r.cn.Replace("`n", ' '); if ($cnShort.Length -gt 90) { $cnShort = $cnShort.Substring(0, 90) + '…' }
                $ruShort = $r.ru.Replace("`n", ' '); if ($ruShort.Length -gt 160) { $ruShort = $ruShort.Substring(0, 160) + '…' }
                $bad = if ($t.bad) { " **[$($t.bad)]**" } else { '' }
                [void]$sb.AppendLine("- ``$($r.key)`` $($t.term)$bad — $cnShort → $ruShort")
            }
        }
    }
    [System.IO.File]::WriteAllText($out, $sb.ToString(), $utf8NoBom)
    [System.IO.File]::WriteAllText([System.IO.Path]::ChangeExtension($out, '.json'), ($stats | ConvertTo-Json -Depth 3), $utf8NoBom)
    Write-Host "Список строк по корзинам: $out" -ForegroundColor Green
    exit 0
}

# ============ -FixShort ============
if ($FixShort) {
    $rows = Get-Rows
    $changes = @{}; $n = 0
    foreach ($r in $rows) {
        if (@($r.terms | Where-Object { $_.bucket -eq 'A' }).Count -eq 0) { continue }
        $new = Get-CanonLabel ($markupRegex.Replace($r.cn, '')) $r.ru
        if ($new -ceq $r.ru) { continue }
        if (-not $changes.ContainsKey($r.file)) { $changes[$r.file] = @{} }
        $changes[$r.file][$r.id] = $new
        $n++
        Write-Host ("{0}  {1}: «{2}» → «{3}»" -f $r.key, $r.cn, $r.ru, $new)
    }
    if ($n) { Write-BatchChanges $changes }
    Write-Host "Заменено коротких подписей: $n" -ForegroundColor Green
    exit 0
}

# ============ -Export ============
if ($Export) {
    $rows = Get-Rows
    Get-ChildItem $tempDir -Filter 'glossary_chunk_*.json' -ErrorAction SilentlyContinue | Remove-Item -Force
    $list = @($rows | Where-Object { (Get-Worst $_) -in 'B', 'C' })
    $chunkNo = 0
    for ($i = 0; $i -lt $list.Count; $i += $Count) {
        $chunkNo++
        $items = @()
        foreach ($r in $list[$i..([Math]::Min($i + $Count, $list.Count) - 1)]) {
            $cnPlain = $markupRegex.Replace($r.cn, '')
            $chunkTerms = @()
            foreach ($e in $entries) {
                if (-not $cnPlain.Contains($e.cn)) { continue }
                $bt = @($r.terms | Where-Object { $_.term -eq $e.parent })
                if ($bt.Count -eq 0 -or $bt[0].bucket -in 'S', 'X', 'E') { continue }
                $bf = $byCn[$e.parent]
                $chunkTerms += [ordered]@{ cn = $e.cn; ru = $e.ru; ru_short = $e.ru_short; must_match = $bf.match.ToString(); forbidden = @($bf.forbiddenText); note = if ($e.note) { $e.note } else { $bf.note } }
            }
            $items += [ordered]@{ key = $r.key; source_cn = $r.cn; ref_en = $r.en; target_ru = $r.ru; terms = $chunkTerms }
        }
        $path = Join-Path $tempDir ('glossary_chunk_{0:D3}.json' -f $chunkNo)
        $json = (ConvertTo-Json -InputObject $items -Depth 6) -replace '\\u003c', '<' -replace '\\u003e', '>' -replace '\\u0026', '&' -replace '\\u0027', "'"
        [System.IO.File]::WriteAllText($path, $json.Replace("`r`n", "`n"), $utf8NoBom)
        Write-Host ("{0}: {1} строк" -f $path, $items.Count)
    }
    Write-Host "Выгружено строк B+C: $($list.Count), чанков: $chunkNo" -ForegroundColor Green
    exit 0
}

# ============ -Import ============
if ($Import) {
    if (-not (Test-Path $Import)) { throw "Файл $Import не найден" }
    $content = (Read-Text $Import).Trim()
    $content = [regex]::Replace($content, '^```(?:json)?\s*|\s*```$', '')
    $answer = $content | ConvertFrom-Json
    $files = @{}
    foreach ($f in Get-ChildItem $batchesDir -Filter 'batch_*.json') { $files[$f.BaseName.Substring(0, 9)] = $f.FullName }
    # Текущие строки нужных батчей
    $want = @{}
    foreach ($p in $answer.PSObject.Properties) {
        $prefix, $id = $p.Name.Split(':', 2)
        if (-not $files.ContainsKey($prefix)) { continue }
        if (-not $want.ContainsKey($files[$prefix])) { $want[$files[$prefix]] = @{} }
        $want[$files[$prefix]][$id] = [string]$p.Value
    }
    $current = @{}
    foreach ($file in $want.Keys) {
        foreach ($m in $itemRegex.Matches((Read-Text $file))) {
            if ($want[$file].ContainsKey($m.Groups['id'].Value)) {
                $current["$file|$($m.Groups['id'].Value)"] = @((ConvertFrom-JsonString $m.Groups['cn'].Value), (ConvertFrom-JsonString $m.Groups['en'].Value), (ConvertFrom-JsonString $m.Groups['ru'].Value))
            }
        }
    }
    $changes = @{}; $accepted = 0; $same = 0; $rejected = @()
    foreach ($p in $answer.PSObject.Properties) {
        $key = $p.Name; $new = ([string]$p.Value).Replace("`r`n", "`n")
        $prefix, $id = $key.Split(':', 2)
        if (-not $files.ContainsKey($prefix)) { $rejected += "$key — нет батча $prefix"; continue }
        $file = $files[$prefix]
        $cur = $current["$file|$id"]
        if (-not $cur) { $rejected += "$key — id не найден"; continue }
        $cn, $en, $old = $cur
        if ([string]::IsNullOrWhiteSpace($new)) { $rejected += "$key — пустая строка"; continue }
        if ($new -ceq $old) { $same++; continue }
        $markup = @(Test-Markup $cn $old $new)
        if ($markup.Count) { $rejected += "$key — разметка: $($markup -join ', ')"; continue }
        $bad = @(Test-Row $cn $en $new | Where-Object { $_.bucket -notin 'ok', 'S', 'X', 'E' })
        if ($bad.Count) { $rejected += "$key — нет канона: $(($bad | ForEach-Object { "$($_.term) ($($_.bucket)$(if ($_.bad) { ": $($_.bad)" }))" }) -join '; ') → $new"; continue }
        if (-not $changes.ContainsKey($file)) { $changes[$file] = @{} }
        $changes[$file][$id] = $new
        $accepted++
    }
    if ($accepted) { Write-BatchChanges $changes }
    Write-Host "Принято: $accepted, без изменений: $same, отклонено: $($rejected.Count)" -ForegroundColor Green
    foreach ($r in $rejected) { Write-Host "  ОТКАЗ $r" -ForegroundColor Yellow }
    exit 0
}

# ============ -BuildDoc ============
if ($BuildDoc) {
    $j = @{}
    foreach ($n in 'combat_stats', 'terms_and_items', 'characters_and_factions', 'locations_and_geography', 'pathways_and_sequences') {
        $j[$n] = (Read-Text (Join-Path $glossaryDir "$n.json")) | ConvertFrom-Json
    }
    $sb = New-Object System.Text.StringBuilder
    function Add([string]$s = '') { [void]$sb.AppendLine($s) }
    function Add-Table($list, [string[]]$extra = @()) {
        Add ('| Русский | English | 中文 |' + (($extra | ForEach-Object { " $_ |" }) -join ''))
        Add ('|---|---|---|' + (($extra | ForEach-Object { '---|' }) -join ''))
        foreach ($x in $list) { Add ("| **$($x.ru)** | $($x.en) | $($x.cn) |" + (($extra | ForEach-Object { " $($x.$_) |" }) -join '')) }
        Add
    }
    Add '# Глоссарий Lord of the Mysteries (C7)'
    Add
    Add 'Файл собирается командой `tools\GlossaryCheck.ps1 -BuildDoc` из `source/glossary/*.json` — правьте JSON, а не этот файл. Сверка батчей с боевыми характеристиками: `tools\GlossaryCheck.ps1 -Report` (см. [TRANSLATION_GUIDE.md](TRANSLATION_GUIDE.md) §7).'
    Add
    Add '**Канон перевода новеллы** — перевод Цитруса на RanobeLib: <https://ranobelib.me/ru/book/20818--lord-of-the-mysteries?section=chapters>. По нему сверяются имена, пути, места и организации (пачка 2 и далее, TASK-017). Игровые характеристики — свои короткие термины (раздел 1).'
    Add
    Add '## 1. Боевые характеристики'
    Add
    Add 'В подписях — короткая форма, в тексте — полная с согласованием падежа («повышает Пронзание на 50», «прорыва защиты»). Подтермины (Физ./Маг./Особ.) строятся от базового термина.'
    Add
    Add '| 中文 | Русский | Подпись | English | Неверные варианты | Примечание |'
    Add '|---|---|---|---|---|---|'
    foreach ($t in $j.combat_stats.terms) {
        $bad = if ($t.forbidden) { (@($t.forbidden) | ForEach-Object { '`' + ($_ -replace '\|', '\|') + '`' }) -join ', ' } else { '' }
        $short = if ($t.ru_short) { $t.ru_short } else { $t.ru }
        $name = if ($t.parent) { "&nbsp;&nbsp;$($t.cn)" } else { "**$($t.cn)**" }
        Add "| $name | $($t.ru) | $short | $($t.en) | $bad | $($t.note) |"
    }
    Add
    Add '## 2. Пути и последовательности'
    Add
    Add '| Путь | Группа | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |'
    Add '|---|---|---|---|---|---|---|---|---|---|---|---|'
    foreach ($p in $j.pathways_and_sequences.pathways) {
        $seq = @($p.sequences | Sort-Object { - [int]$_.seq } | ForEach-Object { $_.name_ru })
        Add ("| **$($p.name_ru)** ($($p.name_cn)) | $($p.group) | " + ($seq -join ' | ') + ' |')
    }
    Add
    Add '## 3. Клуб Таро и персонажи'
    Add
    Add-Table $j.characters_and_factions.tarot_club @('card')
    Add-Table $j.characters_and_factions.major_characters @('note')
    Add '## 4. Церкви и организации'
    Add
    Add-Table $j.characters_and_factions.churches_and_factions
    Add '## 5. Места'
    Add
    foreach ($k in $j.locations_and_geography.PSObject.Properties) { Add-Table $k.Value @('note') }
    Add '## 6. Понятия мира'
    Add
    Add-Table $j.terms_and_items.magic_and_power @('note')
    Add '## 7. Игровые механики'
    Add
    Add-Table $j.terms_and_items.game_mechanics
    Add '## 8. Магазины и события'
    Add
    Add-Table $j.terms_and_items.shop_and_events
    $docPath = Join-Path $root 'docs\GLOSSARY.md'
    [System.IO.File]::WriteAllText($docPath, $sb.ToString().Replace("`r`n", "`n").TrimEnd() + "`n", $utf8NoBom)
    Write-Host "Собран $docPath" -ForegroundColor Green
    exit 0
}

Write-Host 'Укажите режим: -Report, -FixShort, -Export, -Import <файл> или -BuildDoc' -ForegroundColor Yellow
