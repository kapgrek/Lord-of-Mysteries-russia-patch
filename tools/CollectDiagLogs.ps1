# CollectDiagLogs.ps1 — копирует логи диагностики AbsoluteRU из игры и строит отчёты (TASK-005, docs/DIAGNOSTICS.md).
#
# Из игры только ЧИТАЕТ: Saved/Logs/C7.log (+ C7-backup-*.log новее старта сессии), Saved/Mods/logs/absru-*,
# Saved/Mods/absru-* (запасная папка модуля) и Saved/Mods/lua/absoluteru_dev.lua. В игре ничего не создаёт,
# не удаляет и не переименовывает. Все остальные операции идут с копией в reference/logs/<дата>.
#
# Примеры:
#   powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1
#   powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1 -Session all
#   powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1 -NoCopy -Aggregate
param(
    [string]$GameDir,
    [string]$Out,
    [string]$Session = 'latest',   # latest | all | <sid>
    [switch]$Aggregate,            # отчёт по всем папкам reference/logs/*
    [switch]$NoCopy,               # только отчёты по уже скопированному
    [string]$LogsRoot              # по умолчанию reference/logs
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Web.Extensions

$repo = Split-Path $PSScriptRoot -Parent
function Resolve-Full([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
}
$LogsRoot = Resolve-Full $(if ($LogsRoot) { $LogsRoot } else { Join-Path $repo 'reference\logs' })
if (-not $GameDir -and -not $NoCopy -and (Test-Path 'D:\Games\GMZZLauncher\Game\C7')) {
    $GameDir = 'D:\Games\GMZZLauncher\Game\C7'
}
$GameDir = Resolve-Full $GameDir

if ($Out) {
    $Out = Resolve-Full $Out
} elseif ($NoCopy -and $Aggregate) {
    $Out = Join-Path $LogsRoot 'aggregate'
} elseif ($NoCopy) {
    $latest = Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'aggregate' } | Sort-Object Name | Select-Object -Last 1
    if (-not $latest) { throw "В $LogsRoot нет скопированных логов; запустите без -NoCopy" }
    $Out = $latest.FullName
} else {
    $Out = Join-Path $LogsRoot (Get-Date -Format 'yyyy-MM-dd_HHmm')
}

# Никогда не писать в папку игры: -Out и все записи должны быть вне -GameDir.
function Assert-OutsideGame([string]$path) {
    if (-not $GameDir) { return }
    $game = $GameDir.TrimEnd('\') + '\'
    $full = (Resolve-Full $path).TrimEnd('\') + '\'
    if ($full.StartsWith($game, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Запись в папку игры запрещена: $path"
    }
}
Assert-OutsideGame $Out

$utf8 = New-Object System.Text.UTF8Encoding($false)
$json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$json.MaxJsonLength = [int]::MaxValue
$json.RecursionLimit = 256

function Write-Text([string]$path, [string]$text) {
    Assert-OutsideGame $path
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($path, $text.Replace("`r`n", "`n"), $utf8)
}
function Get-V($dict, [string]$key) {
    # PowerShell returns $null for a missing dictionary key.
    if ($dict -is [System.Collections.IDictionary]) { return $dict[$key] }
    return $null
}
function Read-JsonFile([string]$path) {
    return $json.DeserializeObject([IO.File]::ReadAllText($path, $utf8))
}
function Read-Jsonl([string]$path) {
    $lines = [IO.File]::ReadAllLines($path, $utf8) | Where-Object { $_.Trim() -ne '' }
    if (-not $lines) { return ,@() }
    return ,@($json.DeserializeObject('[' + ($lines -join ',') + ']'))
}
function Cell([object]$value) {
    if ($null -eq $value) { return '' }
    return ([string]$value).Replace("`r", ' ').Replace("`n", ' ').Replace('|', '\|')
}
function Num([object]$value) {
    if ($null -eq $value -or $value -eq '') { return 0 }
    return [double]$value
}
function Write-Csv([string]$path, $rows) {
    $rows = @($rows | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { Write-Text $path "`n"; return }
    $csv = $rows | ConvertTo-Csv -NoTypeInformation
    Write-Text $path (($csv -join "`n") + "`n")
}

# 1. Копирование ИЗ игры -------------------------------------------------------------------------
$copied = New-Object System.Collections.Generic.List[string]
if (-not $NoCopy) {
    if (-not $GameDir -or -not (Test-Path -LiteralPath (Join-Path $GameDir 'Saved'))) {
        throw "Папка игры не найдена: '$GameDir'. Укажите -GameDir <...\C7> или -NoCopy."
    }
    $gameSaved = Join-Path $GameDir 'Saved'
    $diagSources = @()
    foreach ($sub in @('Mods\logs', 'Mods')) {
        $dir = Join-Path $gameSaved $sub
        if (Test-Path -LiteralPath $dir) {
            $diagSources += @(Get-ChildItem -LiteralPath $dir -File -Filter 'absru-*')
        }
    }
    foreach ($file in $diagSources) {
        $relative = $file.FullName.Substring($GameDir.TrimEnd('\').Length + 1)
        $target = Join-Path $Out $relative
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
        $copied.Add($relative)
    }

    # Старт самой ранней сессии: C7-backup-*.log старше неё не нужны.
    $sessionStart = $null
    foreach ($file in $diagSources | Where-Object { $_.Name -like 'absru-s*-session.json' }) {
        try {
            $started = Get-V (Read-JsonFile $file.FullName) 'started'
            $parsed = [datetime]::ParseExact([string]$started, 'yyyy-MM-dd HH:mm:ss', $null)
            if ($null -eq $sessionStart -or $parsed -lt $sessionStart) { $sessionStart = $parsed }
        } catch { }
    }
    $logDir = Join-Path $gameSaved 'Logs'
    $logFiles = @()
    if (Test-Path -LiteralPath (Join-Path $logDir 'C7.log')) { $logFiles += Get-Item -LiteralPath (Join-Path $logDir 'C7.log') }
    if ($null -ne $sessionStart -and (Test-Path -LiteralPath $logDir)) {
        $logFiles += @(Get-ChildItem -LiteralPath $logDir -File -Filter 'C7-backup-*.log' |
            Where-Object { $_.LastWriteTime -ge $sessionStart })
    }
    foreach ($file in $logFiles) {
        $target = Join-Path $Out ('Saved\Logs\' + $file.Name)
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
        $copied.Add('Saved\Logs\' + $file.Name)
    }
    $flagsFile = Join-Path $gameSaved 'Mods\lua\absoluteru_dev.lua'
    if (Test-Path -LiteralPath $flagsFile) {
        $target = Join-Path $Out 'Saved\Mods\lua\absoluteru_dev.lua'
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $flagsFile -Destination $target
        $copied.Add('Saved\Mods\lua\absoluteru_dev.lua')
    }
    Write-Host "Скопировано из игры: $($copied.Count) файлов -> $Out"
}

# 2. Загрузка сессий ------------------------------------------------------------------------------
$sourceDirs = @()
if ($Aggregate) {
    $sourceDirs = @(Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'aggregate' } | ForEach-Object { $_.FullName })
    if ($Out -and -not ($sourceDirs -contains $Out) -and (Test-Path $Out) -and -not $NoCopy) { $sourceDirs += $Out }
} else {
    $sourceDirs = @($Out)
}

$sessions = [ordered]@{}   # sid -> @{ Session; Dir; Prefix; Hooks; Fonts }
foreach ($dir in $sourceDirs) {
    foreach ($logsDir in @((Join-Path $dir 'Saved\Mods\logs'), (Join-Path $dir 'Saved\Mods'))) {
        if (-not (Test-Path -LiteralPath $logsDir)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $logsDir -File -Filter 'absru-s*-session.json') {
            $data = Read-JsonFile $file.FullName
            $sid = [string](Get-V $data 'sid')
            if (-not $sid -or $sessions.Contains($sid)) { continue }
            $prefix = $file.Name.Substring(0, $file.Name.Length - 'session.json'.Length)
            $hooksPath = Join-Path $logsDir ($prefix + 'hooks.json')
            $fontsPath = Join-Path $logsDir ($prefix + 'fonts.json')
            $hooks = $null; $fonts = $null
            if (Test-Path -LiteralPath $hooksPath) { $hooks = Read-JsonFile $hooksPath }
            if (Test-Path -LiteralPath $fontsPath) { $fonts = Read-JsonFile $fontsPath }
            $sessions[$sid] = @{
                Session = $data; Dir = $dir; LogsDir = $logsDir; Prefix = $prefix
                Hooks = $(if ($hooks -and [string](Get-V $hooks 'sid') -eq $sid) { $hooks } else { $null })
                Fonts = $(if ($fonts -and [string](Get-V $fonts 'sid') -eq $sid) { $fonts } else { $null })
            }
        }
    }
}
if ($sessions.Count -eq 0) { throw "Сессии диагностики (absru-s*-session.json) не найдены в: $($sourceDirs -join ', ')" }

$allSids = @($sessions.Keys | Sort-Object)
if ($Aggregate -or $Session -eq 'all') {
    $selected = $allSids
} elseif ($Session -eq 'latest') {
    $selected = @($allSids[-1])
} else {
    if (-not $sessions.Contains($Session)) { throw "Сессия $Session не найдена. Есть: $($allSids -join ', ')" }
    $selected = @($Session)
}
$selectedSet = @{}
foreach ($sid in $selected) { $selectedSet[$sid] = $true }

function Read-Stream([string]$name) {
    $rows = New-Object System.Collections.Generic.List[object]
    $seenFiles = @{}
    foreach ($sid in $selected) {
        $s = $sessions[$sid]
        $pattern = $s.Prefix + $name + '-*.jsonl'
        foreach ($file in Get-ChildItem -LiteralPath $s.LogsDir -File -Filter $pattern | Sort-Object Name) {
            if ($seenFiles.ContainsKey($file.FullName)) { continue }
            $seenFiles[$file.FullName] = $true
            foreach ($row in (Read-Jsonl $file.FullName)) {
                $rowSid = [string](Get-V $row 'sid')
                if ($selectedSet.ContainsKey($rowSid)) { $rows.Add($row) }
            }
        }
    }
    return ,$rows
}

$reportDir = Join-Path $Out 'report'
New-Item -ItemType Directory -Force $reportDir | Out-Null
$generated = Get-Date -Format 'yyyy-MM-dd HH:mm'

# 3. Сверка с кодом и батчами ----------------------------------------------------------------------
$initPath = Join-Path $repo 'patch_payload\Saved\Mods\lua\mods\cpdd_runtime_fixes\Init.lua'
$codeHooks = [ordered]@{}   # id -> module
$codeAfterLoad = New-Object System.Collections.Generic.List[string]
if (Test-Path $initPath) {
    $initText = [IO.File]::ReadAllText($initPath, $utf8)
    foreach ($spec in @(@('view', 'viewRepairSpecs'), @('data', 'dataRepairSpecs'), @('exact', 'exactWidgetRepairSpecs'))) {
        $m = [regex]::Match($initText, '(?ms)^local ' + $spec[1] + ' = \{\n(.*?)^\}')
        if (-not $m.Success) { continue }
        foreach ($entry in [regex]::Matches($m.Groups[1].Value, '\{\s*"([\w\.]+)",\s*"(\w+)",\s*\{([^}]*)\}')) {
            foreach ($method in [regex]::Matches($entry.Groups[3].Value, '"(\w+)"')) {
                $id = $spec[0] + ':' + $entry.Groups[2].Value + '.' + $method.Groups[1].Value
                if (-not $codeHooks.Contains($id)) { $codeHooks[$id] = $entry.Groups[1].Value }
            }
        }
    }
    foreach ($m in [regex]::Matches($initText, '"(cpdd\.runtime-fix\.[\w\.-]*[\w-])"')) {
        if (-not $codeAfterLoad.Contains($m.Groups[1].Value)) { $codeAfterLoad.Add($m.Groups[1].Value) }
    }
}

$batchCn = @{}; $batchEn = @{}
foreach ($file in Get-ChildItem -Path (Join-Path $repo 'source\translation_batches') -Filter 'batch_*.json' -ErrorAction SilentlyContinue) {
    foreach ($item in @($json.DeserializeObject([IO.File]::ReadAllText($file.FullName, $utf8)))) {
        $cn = [string](Get-V $item 'source_cn'); $en = [string](Get-V $item 'ref_en'); $ru = [string](Get-V $item 'target_ru')
        $info = @{ ru = $ru; batch = $file.BaseName; id = [string](Get-V $item 'id') }
        if ($cn -and -not $batchCn.ContainsKey($cn.Trim())) { $batchCn[$cn.Trim()] = $info }
        if ($en -and -not $batchEn.ContainsKey($en.Trim())) { $batchEn[$en.Trim()] = $info }
    }
}
function Get-BatchStatus([string[]]$texts) {
    foreach ($text in $texts) {
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $key = $text.Trim()
        $info = $null
        if ($batchCn.ContainsKey($key)) { $info = $batchCn[$key] } elseif ($batchEn.ContainsKey($key)) { $info = $batchEn[$key] }
        if ($info) {
            if ($info.ru) { return @{ status = 'перевод есть, не применился'; batch = $info.batch; ru = $info.ru } }
            return @{ status = 'не переведено в батче'; batch = $info.batch; ru = '' }
        }
    }
    return @{ status = 'нет в батчах'; batch = ''; ru = '' }
}

# 4. REPORT.md -------------------------------------------------------------------------------------
$logLines = New-Object System.Collections.Generic.List[string]
$diagMarkers = New-Object System.Collections.Generic.List[string]
$fixLines = 0
$fixProblems = New-Object System.Collections.Generic.List[string]
$activeLines = New-Object System.Collections.Generic.List[string]
foreach ($dir in $sourceDirs) {
    $logs = Join-Path $dir 'Saved\Logs'
    if (-not (Test-Path -LiteralPath $logs)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $logs -File -Filter 'C7*.log' | Sort-Object LastWriteTime) {
        foreach ($line in [IO.File]::ReadAllLines($file.FullName, $utf8)) {
            if ($line.Contains('[AbsruDiag]')) { $diagMarkers.Add($file.Name + ': ' + $line.Trim()) }
            if ($line.Contains('[CPDDRuntimeFix]')) {
                $fixLines++
                if ($line -match 'active hooks_installed=|cyrillic font mode=|menu button without short label') { $activeLines.Add($file.Name + ': ' + $line.Trim()) }
                if ($line -match '(?i)fail|error|unavailable|protected') { $fixProblems.Add($file.Name + ': ' + $line.Trim()) }
            }
        }
    }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Диагностика AbsoluteRU: отчёт')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Сформирован: $generated. Папка: ``$Out``. Сессии: $($selected -join ', ')$(if ($Aggregate) { ' (агрегат по ' + $sourceDirs.Count + ' папкам)' }).")
if ($copied.Count -gt 0) { [void]$sb.AppendLine("Скопировано из игры: $($copied.Count) файлов.") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Сессии')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| sid | слот | версия | старт | последний сброс | флаги | папка в игре |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|')
foreach ($sid in $selected) {
    $s = $sessions[$sid].Session
    $flags = Get-V $s 'flags'
    $on = @()
    foreach ($k in @('Hooks', 'Untranslated', 'Overflow', 'Fonts', 'Images', 'PanelWalk')) { if ((Get-V $flags $k) -eq $true) { $on += $k } }
    [void]$sb.AppendLine("| $sid | $(Get-V $s 'slot') | $(Get-V $s 'version') | $(Get-V $s 'started') | $(Get-V $s 'last_flush') | $($on -join ', ') FrameBudgetMs=$(Get-V $flags 'FrameBudgetMs') | $(Cell (Get-V $s 'dir')) |")
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Бюджет')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| sid | ticks | tick_ms_max | ms_total | queue_peak | io_ms_max | flush_ms_max | flushes | строки JSONL | dropped (≠0) | errors (≠0) |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|---|---|---|---|')
foreach ($sid in $selected) {
    $s = $sessions[$sid].Session
    $b = Get-V $s 'budget'
    $lines = Get-V $s 'lines'
    $lineText = @(); if ($lines) { foreach ($k in ($lines.Keys | Sort-Object)) { $lineText += "$k=$($lines[$k])" } }
    $dropped = @(); $d = Get-V $s 'dropped'; if ($d) { foreach ($k in ($d.Keys | Sort-Object)) { if ((Num $d[$k]) -ne 0) { $dropped += "$k=$($d[$k])" } } }
    $errs = @(); $e = Get-V $s 'errors'; if ($e) { foreach ($k in ($e.Keys | Sort-Object)) { if ((Num $e[$k]) -ne 0) { $errs += "$k=$($e[$k])" } } }
    [void]$sb.AppendLine(('| {0} | {1} | {2:N2} | {3:N1} | {4} | {5:N2} | {6:N2} | {7} | {8} | {9} | {10} |' -f $sid,
        (Get-V $b 'ticks'), (Num (Get-V $b 'tick_ms_max')), (Num (Get-V $b 'ms_total')), (Get-V $b 'queue_peak'),
        (Num (Get-V $b 'io_ms_max')), (Num (Get-V $b 'flush_ms_max')), (Get-V $b 'flushes'),
        ($lineText -join ', '), ($dropped -join ', '), ($errs -join ', ')))
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| sid | самый тяжёлый элемент | обходы (узлов) | корни view / cache / tree / named | hooks.json записан / без изменений |')
[void]$sb.AppendLine('|---|---|---|---|---|')
foreach ($sid in $selected) {
    $s = $sessions[$sid].Session
    $b = Get-V $s 'budget'; $c = Get-V $s 'counters'
    [void]$sb.AppendLine(('| {0} | {1:N2} мс ({2}) | {3} ({4}) | {5} / {6} / {7} / {8} | {9} / {10} |' -f $sid,
        (Num (Get-V $b 'max_item_ms')), (Get-V $b 'max_item_kind'), (Get-V $c 'walks'), (Get-V $c 'walk_nodes'),
        (Get-V $c 'roots_view'), (Get-V $c 'roots_cache'), (Get-V $c 'roots_tree'), (Get-V $c 'roots_named'),
        (Get-V $c 'hooks_writes'), (Get-V $c 'hooks_unchanged')))
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('`tick_ms_max` больше ~3 мс или ненулевые `dropped` — повод уменьшить нагрузку (флаги `PanelWalk`, `Overflow`, `FrameBudgetMs`). `os.clock` в игре идёт шагами ~1 мс.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## API (пробы при сборе)')
[void]$sb.AppendLine('')
foreach ($sid in $selected) {
    $api = Get-V $sessions[$sid].Session 'api'
    $items = @(); if ($api) { foreach ($k in ($api.Keys | Sort-Object)) { $items += "$k=$($api[$k])" } }
    [void]$sb.AppendLine("- $sid`: $($items -join ', ')")
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## C7.log')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Строк ``[CPDDRuntimeFix]``: $fixLines (при включённом VerboseLog здесь должны быть и строки reportVerbose).")
[void]$sb.AppendLine('')
foreach ($line in $activeLines) { [void]$sb.AppendLine('- ' + (Cell $line)) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine("### Маркеры [AbsruDiag] ($($diagMarkers.Count))")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```')
foreach ($line in ($diagMarkers | Select-Object -First 80)) { [void]$sb.AppendLine($line) }
if ($diagMarkers.Count -gt 80) { [void]$sb.AppendLine("... ещё $($diagMarkers.Count - 80)") }
[void]$sb.AppendLine('```')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("### Ошибки и отказы [CPDDRuntimeFix] ($($fixProblems.Count))")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```')
foreach ($line in ($fixProblems | Select-Object -First 80)) { [void]$sb.AppendLine($line) }
[void]$sb.AppendLine('```')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Отчёты')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- [dead_hooks.md](dead_hooks.md), [hooks.csv](hooks.csv): статусы хуков')
[void]$sb.AppendLine('- [overflow_top.md](overflow_top.md), [overflow.csv](overflow.csv): переполнение текста')
[void]$sb.AppendLine('- [untranslated.md](untranslated.md), [untranslated.csv](untranslated.csv): непереведённое')
[void]$sb.AppendLine('- [fonts.md](fonts.md): шрифты (этап 4)')
[void]$sb.AppendLine('- [textures.md](textures.md), [textures.csv](textures.csv): текстуры (этап 8)')
Write-Text (Join-Path $reportDir 'REPORT.md') $sb.ToString()

# 5. Хуки ------------------------------------------------------------------------------------------
$rank = @{ 'ACTIVE' = 6; 'CALLED' = 5; 'NO_EFFECT' = 4; 'NEVER_CALLED' = 3; 'NOT_INSTALLED' = 2; 'NOT_LOADED' = 1 }
$hookAgg = [ordered]@{}
$panelAgg = [ordered]@{}
$afterAgg = @{}
foreach ($sid in $selected) {
    $h = $sessions[$sid].Hooks
    if (-not $h) { continue }
    foreach ($row in @(Get-V $h 'hooks')) {
        if ($null -eq $row) { continue }
        $id = [string](Get-V $row 'id')
        if (-not $hookAgg.Contains($id)) {
            $hookAgg[$id] = @{ id = $id; kind = Get-V $row 'kind'; module = Get-V $row 'module'; status = 'NOT_LOADED'; sessions = 0
                calls = 0; text_changes = 0; text_writes = 0; data_changes = 0; errors = 0; ms_total = 0.0; ms_max = 0.0; statuses = @() }
        }
        $a = $hookAgg[$id]
        $st = [string](Get-V $row 'status')
        if ($rank[$st] -gt $rank[$a.status]) { $a.status = $st }
        $a.statuses += $st
        if (-not $a.module) { $a.module = Get-V $row 'module' }
        $a.sessions++
        foreach ($k in @('calls', 'text_changes', 'text_writes', 'data_changes', 'errors')) { $a[$k] += [int](Num (Get-V $row $k)) }
        $a.ms_total += Num (Get-V $row 'ms_total')
        $a.ms_max = [Math]::Max($a.ms_max, (Num (Get-V $row 'ms_max')))
    }
    foreach ($row in @(Get-V $h 'panels')) {
        if ($null -eq $row) { continue }
        $id = [string](Get-V $row 'id')
        if (-not $panelAgg.Contains($id)) { $panelAgg[$id] = @{ id = $id; runs = 0; labels = 0; widgets = 0; text_changes = 0; ms_total = 0.0; ms_max = 0.0 } }
        $p = $panelAgg[$id]
        foreach ($k in @('runs', 'labels', 'widgets', 'text_changes')) { $p[$k] += [int](Num (Get-V $row $k)) }
        $p.ms_total += Num (Get-V $row 'ms_total')
        $p.ms_max = [Math]::Max($p.ms_max, (Num (Get-V $row 'ms_max')))
    }
    foreach ($row in @(Get-V $h 'afterload')) {
        if ($null -eq $row) { continue }
        $id = [string](Get-V $row 'id')
        $afterAgg[$id] = [Math]::Max([int](Num $afterAgg[$id]), [int](Num (Get-V $row 'applied')))
    }
}
foreach ($id in $codeHooks.Keys) {
    if (-not $hookAgg.Contains($id)) {
        $hookAgg[$id] = @{ id = $id; kind = ($id -split ':')[0]; module = $codeHooks[$id]; status = 'NOT_LOADED (нет данных)'; sessions = 0
            calls = 0; text_changes = 0; text_writes = 0; data_changes = 0; errors = 0; ms_total = 0.0; ms_max = 0.0; statuses = @() }
    }
}
$deadStatuses = @('NO_EFFECT', 'NEVER_CALLED', 'NOT_INSTALLED', 'NOT_LOADED', 'NOT_LOADED (нет данных)')
$hookRows = foreach ($a in $hookAgg.Values) {
    [pscustomobject]@{
        id = $a.id; kind = $a.kind; status = $a.status; module = $a.module; sessions = $a.sessions
        calls = $a.calls; text_changes = $a.text_changes; text_writes = $a.text_writes; data_changes = $a.data_changes
        errors = $a.errors; ms_total = [Math]::Round($a.ms_total, 2); ms_max = [Math]::Round($a.ms_max, 2)
        in_code = $(if ($a.kind -in @('view', 'data', 'exact')) { $codeHooks.Contains($a.id) } else { '' })
    }
}
$hookRows = @($hookRows | Sort-Object status, id)
Write-Csv (Join-Path $reportDir 'hooks.csv') $hookRows

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Мёртвые хуки')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Сессии: $($selected -join ', '). Хук считается мёртвым, только если он мёртв во всех выбранных сессиях (итоговый статус = лучший по сессиям).")
[void]$sb.AppendLine('Статусы: `NOT_LOADED` — модуль не загружался; `NOT_INSTALLED` — модуль загружался, класс/метод не найден; `NEVER_CALLED`; `NO_EFFECT` — вызывался, но ни text_changes, ни data_changes, ни text_writes; `CALLED` — лёгкий счётчик без замера эффекта.')
[void]$sb.AppendLine('`NOT_LOADED (нет данных)` — спек есть в текущем Init.lua, но ни в одной сессии его нет.')
[void]$sb.AppendLine('')
foreach ($status in $deadStatuses) {
    $group = @($hookRows | Where-Object { $_.status -eq $status })
    if ($group.Count -eq 0) { continue }
    [void]$sb.AppendLine("## $status ($($group.Count))")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| id | kind | module | calls | сессий |')
    [void]$sb.AppendLine('|---|---|---|---|---|')
    foreach ($r in $group) { [void]$sb.AppendLine("| $(Cell $r.id) | $($r.kind) | $(Cell $r.module) | $($r.calls) | $($r.sessions) |") }
    [void]$sb.AppendLine('')
}
$errored = @($hookRows | Where-Object { $_.errors -gt 0 })
if ($errored.Count -gt 0) {
    [void]$sb.AppendLine("## Хуки с ошибками ($($errored.Count))")
    [void]$sb.AppendLine('')
    foreach ($r in $errored) { [void]$sb.AppendLine("- $(Cell $r.id): errors=$($r.errors), calls=$($r.calls)") }
    [void]$sb.AppendLine('')
}
$idlePanels = @($panelAgg.Values | Where-Object { $_.id -match ':(extended-[\d\.]+|delayed)$' -and $_.labels -eq 0 -and $_.runs -gt 0 } | Sort-Object { -$_.ms_total })
[void]$sb.AppendLine("## Отложенные проходы панелей без эффекта ($($idlePanels.Count))")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Кандидаты на урезание `extendedPanelRepairDelays` (Init.lua), но только вместе с `docs/LESSONS.md` «Тайминги repair-очередей».')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| id | runs | labels | widgets | ms_total | ms_max |')
[void]$sb.AppendLine('|---|---|---|---|---|---|')
foreach ($p in $idlePanels) { [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4:N1} | {5:N1} |' -f (Cell $p.id), $p.runs, $p.labels, $p.widgets, $p.ms_total, $p.ms_max)) }
[void]$sb.AppendLine('')
$missingAfter = @($codeAfterLoad | Where-Object { -not $afterAgg.ContainsKey($_) -or $afterAgg[$_] -eq 0 } | Sort-Object)
[void]$sb.AppendLine("## AfterLoad-хуки без применений ($($missingAfter.Count) из $($codeAfterLoad.Count) id в Init.lua)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('`applied = 0` или нет в сессиях: модуль игры ни разу не загрузился (или id строится конкатенацией и сверяется только по сессиям).')
[void]$sb.AppendLine('')
foreach ($id in $missingAfter) { [void]$sb.AppendLine("- $id") }
$sessionOnlyAfter = @($afterAgg.Keys | Where-Object { $afterAgg[$_] -eq 0 -and -not $codeAfterLoad.Contains($_) } | Sort-Object)
if ($sessionOnlyAfter.Count -gt 0) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Из сессий (applied = 0): $($sessionOnlyAfter.Count)")
    [void]$sb.AppendLine('')
    foreach ($id in $sessionOnlyAfter) { [void]$sb.AppendLine("- $id") }
}
Write-Text (Join-Path $reportDir 'dead_hooks.md') $sb.ToString()

# 6. Переполнение ----------------------------------------------------------------------------------
$overflowAgg = [ordered]@{}
foreach ($row in (Read-Stream 'overflow')) {
    $key = [string](Get-V $row 'path') + '|' + [string](Get-V $row 'text')
    $need = @(Get-V $row 'need'); $have = @(Get-V $row 'have')
    $excess = [Math]::Max((Num $need[0]) - (Num $have[0]), (Num $need[1]) - (Num $have[1]))
    if ([string](Get-V $row 'wrap') -eq 'True') { $excess = (Num $need[1]) - (Num $have[1]) }
    $prev = $overflowAgg[$key]
    if ($null -eq $prev -or $excess -gt $prev.excess -or (Num (Get-V $row 'count')) -gt $prev.count) {
        $panel = [string](Get-V $row 'panel')
        if ($prev -and $prev.panel -and $panel -notmatch '_Panel$') { $panel = $prev.panel }
        $overflowAgg[$key] = [pscustomobject]@{
            panel = $panel; widget = Get-V $row 'widget'; text = Get-V $row 'text'; len = Get-V $row 'len'
            excess = [Math]::Round([Math]::Max($excess, $(if ($prev) { $prev.excess } else { 0 })), 1)
            count = [int][Math]::Max((Num (Get-V $row 'count')), $(if ($prev) { $prev.count } else { 0 }))
            kind = Get-V $row 'kind'; need = ($need -join 'x'); have = ($have -join 'x')
            parent = Get-V $row 'parent'; parent_have = (@(Get-V $row 'parent_have') -join 'x')
            font = Get-V $row 'font'; typeface = Get-V $row 'typeface'; size = Get-V $row 'size'; size_pre = Get-V $row 'size_pre'
            ls = Get-V $row 'ls'; ls_pre = Get-V $row 'ls_pre'; ls_negative = Get-V $row 'ls_negative'; wrap = Get-V $row 'wrap'
            path = Get-V $row 'path'
        }
    }
}
$overflowRows = @($overflowAgg.Values | Sort-Object panel, { -$_.excess })
Write-Csv (Join-Path $reportDir 'overflow.csv') $overflowRows
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Переполнение текста')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Сессии: $($selected -join ', '). Уникальных виджетов с переполнением: $($overflowRows.Count). ``excess`` = need − have (px в локальных единицах).")
[void]$sb.AppendLine('Нативные SetText игры без Open панели и без наших хуков сюда не попадают (docs/DIAGNOSTICS.md).')
[void]$sb.AppendLine('')
foreach ($group in ($overflowRows | Group-Object panel | Sort-Object { -(($_.Group | Measure-Object excess -Maximum).Maximum) })) {
    [void]$sb.AppendLine("## $(Cell $group.Name) ($($group.Count))")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| widget | text | excess | need | have | kind | parent | size_pre→size | ls_pre→ls | count |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|---|---|')
    foreach ($r in ($group.Group | Sort-Object { -$_.excess })) {
        [void]$sb.AppendLine("| $(Cell $r.widget) | $(Cell $r.text) | $($r.excess) | $($r.need) | $($r.have) | $($r.kind) | $(Cell $r.parent) $($r.parent_have) | $($r.size_pre)→$($r.size) | $($r.ls_pre)→$($r.ls) | $($r.count) |")
    }
    [void]$sb.AppendLine('')
}
$negative = @($overflowRows | Where-Object { [string]$_.ls_negative -eq 'True' })
[void]$sb.AppendLine("## С отрицательным LetterSpacing ($($negative.Count))")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('LetterSpacing задаёт наш `translateTextWidget` (−120 заголовки / −60 остальное), а не игра.')
[void]$sb.AppendLine('')
foreach ($r in $negative) { [void]$sb.AppendLine("- $(Cell $r.panel) / $(Cell $r.widget): «$(Cell $r.text)» ls $($r.ls_pre)→$($r.ls), excess $($r.excess)") }
[void]$sb.AppendLine('')
$resized = @($overflowRows | Where-Object { $null -ne $_.size_pre -and $null -ne $_.size -and (Num $_.size_pre) -ne (Num $_.size) })
[void]$sb.AppendLine("## Размер шрифта: авторский → наш ($($resized.Count))")
[void]$sb.AppendLine('')
foreach ($grp in ($resized | Group-Object { "$($_.size_pre)→$($_.size)" } | Sort-Object Count -Descending)) {
    [void]$sb.AppendLine("- $($grp.Name): $($grp.Count)")
}
Write-Text (Join-Path $reportDir 'overflow_top.md') $sb.ToString()

# 7. Непереведённое --------------------------------------------------------------------------------
$abbrev = '^(HP|MP|SP|DPS|PvP|PVP|PvE|UID|ID|Lv|LV|VIP|UI|OK|CD|EXP|XP|NPC|AI|x|X)$'
function Test-Noise([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $true }
    if ($text -match '[\u4e00-\u9fff\u3400-\u4dbf]') { return $false }
    $clean = [regex]::Replace($text, '<[^>]*>', ' ')
    $clean = [regex]::Replace($clean, '%[-+ #0]*\d*(\.\d+)?[sdifgxX%]|\{\d+\}|\\n', ' ')
    $words = @([regex]::Matches($clean, '[A-Za-z]{2,}') | ForEach-Object { $_.Value })
    if ($words.Count -eq 0) { return $true }
    return (@($words | Where-Object { $_ -notmatch $abbrev }).Count -eq 0)
}
$untrAgg = [ordered]@{}
$dbRows = New-Object System.Collections.Generic.List[object]
foreach ($row in (Read-Stream 'untranslated')) {
    $src = [string](Get-V $row 'src')
    if ($src -eq 'stringdb') { $dbRows.Add($row); continue }
    $text = [string]$(if ($src -eq 'data') { Get-V $row 'translated' } else { Get-V $row 'text' })
    if (Test-Noise $text) { continue }
    $norm = [string](Get-V $row 'norm')
    $key = $src + '|' + $norm
    $prev = $untrAgg[$key]
    $count = [int](Num (Get-V $row 'count'))
    if ($null -eq $prev) {
        $batch = Get-BatchStatus @($text, [string](Get-V $row 'original'))
        $untrAgg[$key] = [pscustomobject]@{
            src = $src; status = $batch.status; text = $text; norm = $norm
            panel = Get-V $row 'panel'; widget = Get-V $row 'widget'; scope = Get-V $row 'scope'
            module = Get-V $row 'module'; field = Get-V $row 'field'; visible = Get-V $row 'vis'
            count = $count; batch = $batch.batch; target_ru = $batch.ru; path = Get-V $row 'path'
        }
    } else {
        if ($count -gt $prev.count) { $prev.count = $count }
        if ((Get-V $row 'vis') -eq $true) { $prev.visible = $true }
    }
}
$dbAgg = [ordered]@{}
foreach ($row in $dbRows) {
    $key = [string](Get-V $row 'module') + '|' + [string](Get-V $row 'row')
    if ($dbAgg.Contains($key)) { continue }
    $batch = Get-BatchStatus @([string](Get-V $row 'cn'), [string](Get-V $row 'en'))
    $dbAgg[$key] = [pscustomobject]@{
        src = 'stringdb'; status = $batch.status; text = Get-V $row 'en'; norm = ''
        panel = ''; widget = ''; scope = ''; module = Get-V $row 'module'; field = [string](Get-V $row 'row'); visible = ''
        count = 1; batch = $batch.batch; target_ru = $batch.ru; path = ''; cn = Get-V $row 'cn'
    }
}
$untrRows = @($untrAgg.Values | Sort-Object status, { -$_.count })
$csvRows = @($untrRows) + @($dbAgg.Values | ForEach-Object {
    [pscustomobject]@{ src = $_.src; status = $_.status; text = $_.text; norm = $_.cn; panel = ''; widget = ''; scope = ''
        module = $_.module; field = $_.field; visible = ''; count = 1; batch = $_.batch; target_ru = $_.target_ru; path = '' } })
Write-Csv (Join-Path $reportDir 'untranslated.csv') $csvRows
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Непереведённое')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Сессии: $($selected -join ', '). Виджеты и данные: $($untrRows.Count) уникальных (после офлайн-фильтра чисел, плейсхолдеров и аббревиатур). StringDB: $($dbAgg.Count) строк.")
[void]$sb.AppendLine('Сверка с `source/translation_batches`: «перевод есть, не применился» — строка есть в батче с `target_ru`; «не переведено в батче» — есть без перевода; «нет в батчах».')
[void]$sb.AppendLine('')
foreach ($status in @('перевод есть, не применился', 'не переведено в батче', 'нет в батчах')) {
    $group = @($untrRows | Where-Object { $_.status -eq $status })
    [void]$sb.AppendLine("## $status ($($group.Count))")
    [void]$sb.AppendLine('')
    if ($group.Count -eq 0) { continue }
    [void]$sb.AppendLine('| src | text | panel / module | widget / field | vis | count | batch → target_ru |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|')
    foreach ($r in ($group | Select-Object -First 500)) {
        $where = $(if ($r.src -eq 'data') { $r.module } else { $r.panel })
        $what = $(if ($r.src -eq 'data') { $r.field } else { $r.widget })
        $target = $(if ($r.batch) { "$($r.batch) → $(Cell $r.target_ru)" } else { '' })
        [void]$sb.AppendLine("| $($r.src) | $(Cell $r.text) | $(Cell $where) | $(Cell $what) | $($r.visible) | $($r.count) | $target |")
    }
    if ($group.Count -gt 500) { [void]$sb.AppendLine("| … | ещё $($group.Count - 500) в untranslated.csv | | | | | |") }
    [void]$sb.AppendLine('')
}
[void]$sb.AppendLine("## StringDB без русского перевода ($($dbAgg.Count))")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('`Loader.TranslateDatabaseString` вернул nil: в игре остаётся английский текст CPDD.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| module | строк | из них «перевод есть, не применился» | примеры |')
[void]$sb.AppendLine('|---|---|---|---|')
foreach ($group in ($dbAgg.Values | Group-Object module | Sort-Object Count -Descending)) {
    $applied = @($group.Group | Where-Object { $_.status -eq 'перевод есть, не применился' }).Count
    $examples = @($group.Group | Select-Object -First 3 | ForEach-Object { Cell $_.text }) -join ' / '
    [void]$sb.AppendLine("| $(Cell $group.Name) | $($group.Count) | $applied | $examples |")
}
Write-Text (Join-Path $reportDir 'untranslated.md') $sb.ToString()

# 8. Шрифты ----------------------------------------------------------------------------------------
$fontAgg = [ordered]@{}
$standard = @{}
$composite = [ordered]@{}
$cyrillicFont = $null
$titleCyr = [ordered]@{}
foreach ($sid in $selected) {
    $f = $sessions[$sid].Fonts
    if (-not $f) { continue }
    foreach ($row in @(Get-V $f 'title_cyrillic')) {
        if ($null -eq $row) { continue }
        $key = [string](Get-V $row 'panel') + '|' + [string](Get-V $row 'widget') + '|' + [string](Get-V $row 'typeface')
        if (-not $titleCyr.Contains($key)) {
            $titleCyr[$key] = @{ panel = Get-V $row 'panel'; widget = Get-V $row 'widget'; class = Get-V $row 'class'
                typeface = Get-V $row 'typeface'; size = Get-V $row 'size'; styled = $false; rich = [bool](Get-V $row 'rich')
                font_read = [bool](Get-V $row 'font_read'); font_src = Get-V $row 'font_src'; count = 0; text = Get-V $row 'text' }
        }
        $t = $titleCyr[$key]
        $t.count += [int](Num (Get-V $row 'count'))
        if ((Get-V $row 'styled') -eq $true) { $t.styled = $true }
    }
    foreach ($k in @('standard', 'standard_typeface', 'cinematic')) { if (Get-V $f $k) { $standard[$k] = Get-V $f $k } }
    $c = Get-V $f 'composite'
    if ($c) { foreach ($p in $c.Keys) { $composite[$p] = $c[$p] } }
    if (Get-V $f 'cyrillic_font') { $cyrillicFont = Get-V $f 'cyrillic_font' }
    foreach ($row in @(Get-V $f 'fonts')) {
        if ($null -eq $row) { continue }
        $key = [string](Get-V $row 'role') + '|' + [string](Get-V $row 'key')
        if (-not $fontAgg.Contains($key)) {
            $fontAgg[$key] = @{ role = Get-V $row 'role'; path = Get-V $row 'path'; typeface = Get-V $row 'typeface'; count = 0
                cyr = 0; cjk = 0; latin = 0; widgets = New-Object System.Collections.Generic.List[string]
                panels = New-Object System.Collections.Generic.List[string]; sizes = @{} }
        }
        $a = $fontAgg[$key]
        $a.count += [int](Num (Get-V $row 'count'))
        $a.cyr += [int](Num (Get-V $row 'texts_cyrillic')); $a.cjk += [int](Num (Get-V $row 'texts_cjk')); $a.latin += [int](Num (Get-V $row 'texts_latin'))
        foreach ($w in @(Get-V $row 'widgets')) { if ($w -and -not $a.widgets.Contains($w) -and $a.widgets.Count -lt 20) { $a.widgets.Add($w) } }
        foreach ($p in @(Get-V $row 'panels')) { if ($p -and -not $a.panels.Contains($p) -and $a.panels.Count -lt 20) { $a.panels.Add($p) } }
        $sizes = Get-V $row 'sizes'
        if ($sizes) { foreach ($s in $sizes.Keys) { $a.sizes[$s] = [int](Num $a.sizes[$s]) + [int](Num $sizes[$s]) } }
    }
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Шрифты (этап 4)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Сессии: $($selected -join ', '). StandardFontObject: ``$($standard['standard'])``; CinematicFontObject: ``$($standard['cinematic'])``.")
[void]$sb.AppendLine('`pre` — авторский шрифт до нашей замены (снимок в translateTextWidget или виджет, который мы не стилизовали); `post` — после.')
[void]$sb.AppendLine('Какой глиф выбрал Slate (fallback), из Lua не видно: сверять cmap экспортированных шрифтов (U+0400–U+04FF) офлайн.')
[void]$sb.AppendLine('')
if ($cyrillicFont) {
    $parts = @('mode', 'requested', 'title_typeface', 'typefaces', 'face', 'sub', 'cultures', 'previous', 'write', 'via', 'verify', 'flush', 'flush2', 'cyr', 'latin', 'source', 'title_face', 'applied_at', 'reason' | Where-Object { $null -ne (Get-V $cyrillicFont $_) } | ForEach-Object { "$_=$(Get-V $cyrillicFont $_)" })
    [void]$sb.AppendLine("Кириллица (TASK-006): ``$($parts -join ' ')``.")
    [void]$sb.AppendLine('')
}
function Format-Range($r) {
    $low = Get-V $r 'low'; $high = Get-V $r 'high'
    if ($null -eq $low) { return "$(Get-V $r 'raw') ($(Get-V $r 'type'))" }
    return ('U+{0:X4}–U+{1:X4} ({2}/{3})' -f [int]$low, [int]$high, (Get-V $r 'low_type'), (Get-V $r 'high_type'))
}
[void]$sb.AppendLine("## composite ($($composite.Count))")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Структура `UFont.CompositeFont` (проба `AbsruDiagnostics`, только чтение). Диапазоны: границы и тип (0 — Exclusive, 1 — Inclusive, 2 — Open). В режиме `subfont` здесь видна и наша запись U+0400–U+045F.')
[void]$sb.AppendLine('«А / A» — покрывает ли SubTypeface U+0410 (кириллическая А) и U+0041 (латинская A): `да` / `нет` / `?` (диапазоны не прочитаны). «чтение» — способ чтения диапазона: `field` (`LowerBound.Value`), `method` (`GetLowerBoundValue()`), `get` (геттеры из таблицы `.get` метатаблицы), `contains` (`Contains()`), `none`.')
[void]$sb.AppendLine('')
function Format-Covers($value) {
    if ($null -eq $value) { return '?' }
    if ($value -eq $true) { return 'да' }
    return 'нет'
}
[void]$sb.AppendLine('| шрифт | часть | typeface | face | диапазоны / культуры | А / A | чтение | масштаб | loading / hinting |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|---|---|')
foreach ($p in $composite.Keys) {
    $rec = $composite[$p]
    $fontName = ($p -split '[/.]')[-1]
    if (-not (Get-V $rec 'loaded')) {
        [void]$sb.AppendLine("| $(Cell $fontName) | — | — | не загружен $(Cell (Get-V $rec 'error')) | | | | | |")
        continue
    }
    $parts = New-Object System.Collections.Generic.List[object]
    $parts.Add(@('default', @(Get-V $rec 'default'), '', '', '', ''))
    $fb = Get-V $rec 'fallback'
    if ($fb) { $parts.Add(@('fallback', @(Get-V $fb 'fonts'), '', (Get-V $fb 'scaling'), '', '')) }
    $i = 0
    foreach ($sub in @(Get-V $rec 'subs')) {
        if ($null -eq $sub) { continue }
        $ranges = @(@(Get-V $sub 'ranges') | Where-Object { $null -ne $_ } | ForEach-Object { Format-Range $_ }) -join ', '
        $cult = Get-V $sub 'cultures'
        if ($cult) { $ranges = "$ranges; $cult" }
        $covers = "$(Format-Covers (Get-V $sub 'covers_0410')) / $(Format-Covers (Get-V $sub 'covers_0041'))"
        $parts.Add(@("sub#$i", @(Get-V $sub 'fonts'), $ranges, (Get-V $sub 'scaling'), $covers, (Get-V $sub 'range_read')))
        $i++
    }
    if (Get-V $rec 'error') { [void]$sb.AppendLine("| $(Cell $fontName) | ошибка | | $(Cell (Get-V $rec 'error')) | | | | | |") }
    foreach ($part in $parts) {
        $entries = @($part[1] | Where-Object { $null -ne $_ })
        if ($entries.Count -eq 0) {
            [void]$sb.AppendLine("| $(Cell $fontName) | $($part[0]) | — | — | $(Cell $part[2]) | $(Cell $part[4]) | $(Cell $part[5]) | $(Cell $part[3]) | |")
        }
        foreach ($e in $entries) {
            [void]$sb.AppendLine("| $(Cell $fontName) | $($part[0]) | $(Cell (Get-V $e 'name')) | $(Cell (Get-V $e 'face')) | $(Cell $part[2]) | $(Cell $part[4]) | $(Cell $part[5]) | $(Cell $part[3]) | $(Cell (Get-V $e 'loading')) / $(Cell (Get-V $e 'hinting')) |")
        }
    }
}
[void]$sb.AppendLine('')
# Проба FInt32Range (TASK-007): первый диапазон каждого SubTypeface Font_Aleo.
$probeRows = New-Object System.Collections.Generic.List[string]
foreach ($p in $composite.Keys) {
    $i = 0
    foreach ($sub in @(Get-V $composite[$p] 'subs')) {
        if ($null -eq $sub) { continue }
        $probe = Get-V $sub 'range_probe'
        if ($probe) {
            $face = @(@(Get-V $sub 'fonts') | Where-Object { $null -ne $_ } | ForEach-Object { (([string](Get-V $_ 'face')) -split '[/.]')[-1] } | Select-Object -Unique) -join ', '
            $calls = @('GetLowerBoundValue', 'GetUpperBoundValue', 'IsEmpty', 'Contains_0410', 'LowerBound', 'LowerBound_Value', 'LowerBound_Type',
                'get_LowerBound', 'get_LowerBound_Type', 'get_LowerBound_Value', 'get_UpperBound', 'get_UpperBound_Type', 'get_UpperBound_Value', 'clone', 'clone_method' | ForEach-Object {
                $r = Get-V $probe $_
                if ($r) { "$_=$(if ((Get-V $r 'ok') -eq $true) { 'ok' } else { 'err' }):$(Get-V $r 'type'):$(Get-V $r 'value')" }
            }) -join '; '
            $meta = "meta=$(Get-V $probe 'meta') name=$(Get-V $probe 'meta_name') index=$(Get-V $probe 'index') meta_keys=[$(@(Get-V $probe 'meta_keys') -join ',')] index_keys=[$(@(Get-V $probe 'index_keys') -join ',')] .get=[$(@(Get-V $probe 'get_keys') -join ',')] .set=[$(@(Get-V $probe 'set_keys') -join ',')] LowerBound.get=[$(@(Get-V $probe 'get_LowerBound_keys') -join ',')]"
            $probeRows.Add("| $(Cell (($p -split '[/.]')[-1])) | sub#$i | $(Cell $face) | $(Cell $meta) | $(Cell $calls) |")
        }
        $i++
    }
}
if ($probeRows.Count -gt 0) {
    [void]$sb.AppendLine("### Проба FInt32Range ($($probeRows.Count))")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Первый диапазон каждого SubTypeface `Font_Aleo`: метатаблица и результат каждого вызова (`ok`/`err`:тип:значение). Итог по API — в `REPORT.md → API` (`FInt32Range.*`, `import(...)`, `culture.*`).')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| шрифт | часть | face | метатаблица | вызовы |')
    [void]$sb.AppendLine('|---|---|---|---|---|')
    foreach ($line in $probeRows) { [void]$sb.AppendLine($line) }
    [void]$sb.AppendLine('')
}
$titleRows = @($titleCyr.Values | Sort-Object { -($_.count) })
[void]$sb.AppendLine("## Title с кириллицей ($($titleRows.Count))")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Виджеты, у которых кириллицу рисует typeface `Title` шрифта `Font_Aleo` (FZ Mincho 1,0 em), по данным обхода панелей (TASK-007). `styled` — виджет проходил через `translateTextWidget`; `rich` — RichText, шрифт взят из стиля по умолчанию (`override`/`style`/`current`), `шрифт не прочитан` — RichText, чей стиль slua не отдал.')
[void]$sb.AppendLine('')
foreach ($group in @($titleRows | Group-Object { "styled=$($_.styled) rich=$($_.rich)" } | Sort-Object Name)) {
    [void]$sb.AppendLine("### $($group.Name) ($($group.Count))")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| панель | виджет | класс | typeface | размер | шрифт | раз | текст |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|')
    foreach ($r in $group.Group) {
        $src = if ($r.rich -and -not $r.font_read) { 'шрифт не прочитан' } else { $r.font_src }
        [void]$sb.AppendLine("| $(Cell $r.panel) | $(Cell $r.widget) | $(Cell $r.class) | $(Cell $r.typeface) | $(Cell $r.size) | $(Cell $src) | $($r.count) | $(Cell $r.text) |")
    }
    [void]$sb.AppendLine('')
}
foreach ($role in @('pre', 'post')) {
    $rows = @($fontAgg.Values | Where-Object { $_.role -eq $role } | Sort-Object { -($_.cyr) }, { -($_.count) })
    [void]$sb.AppendLine("## $role ($($rows.Count))")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| font | typeface | виджетов-текстов | кириллица | CJK | латиница | размеры | панели |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|')
    foreach ($r in $rows) {
        $sizes = @($r.sizes.Keys | Sort-Object { [double]$_ } | ForEach-Object { "$_×$($r.sizes[$_])" }) -join ', '
        [void]$sb.AppendLine("| $(Cell $r.path) | $(Cell $r.typeface) | $($r.count) | $($r.cyr) | $($r.cjk) | $($r.latin) | $sizes | $(Cell ($r.panels -join ', ')) |")
    }
    [void]$sb.AppendLine('')
}
$exportFonts = @($fontAgg.Values | Where-Object { $_.role -eq 'pre' -and $_.cyr -gt 0 -and $_.path } | ForEach-Object { $_.path } | Sort-Object -Unique)
[void]$sb.AppendLine("## Экспорт для проверки кириллицы ($($exportFonts.Count))")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Авторские шрифты, которыми рисуется кириллица: выгрузить UFont/UFontFace (FModel/CUE4Parse → `reference/fonts/`) и проверить cmap.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```')
foreach ($p in $exportFonts) { [void]$sb.AppendLine($p) }
[void]$sb.AppendLine('```')
Write-Text (Join-Path $reportDir 'fonts.md') $sb.ToString()

# 9. Текстуры --------------------------------------------------------------------------------------
$texAgg = [ordered]@{}
foreach ($row in (Read-Stream 'images')) {
    $resource = [string](Get-V $row 'resource')
    if (-not $texAgg.Contains($resource)) {
        $texAgg[$resource] = @{ resource = $resource; class = Get-V $row 'class'; size = (@(Get-V $row 'size') -join 'x')
            panels = @{}; widgets = New-Object System.Collections.Generic.List[string] }
    }
    $a = $texAgg[$resource]
    $panel = [string](Get-V $row 'panel')
    $a.panels[$panel] = [Math]::Max([int](Num $a.panels[$panel]), [int](Num (Get-V $row 'count')))
    $w = [string](Get-V $row 'widget')
    if ($w -and -not $a.widgets.Contains($w) -and $a.widgets.Count -lt 10) { $a.widgets.Add($w) }
}
$heuristic = '(?i)Text|Title|Word|Font|Name|Label|_CN|Zi'
$texRows = @(foreach ($a in $texAgg.Values) {
    $shows = 0; foreach ($v in $a.panels.Values) { $shows += $v }
    $leaf = ($a.resource -split '[/\.]')[-1]
    $named = $leaf -match $heuristic
    [pscustomobject]@{
        resource = $a.resource; class = $a.class; size = $a.size; panels = $a.panels.Count; shows = $shows
        name_hint = $named; priority = ($a.panels.Count * $shows) * $(if ($named) { 3 } else { 1 })
        panel_list = (@($a.panels.Keys | Sort-Object) -join ', '); widgets = ($a.widgets -join ', ')
    }
}) | Sort-Object { -$_.priority }, resource
Write-Csv (Join-Path $reportDir 'textures.csv') $texRows
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Текстуры (этап 8)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Сессии: $($selected -join ', '). Ресурсов: $(@($texRows).Count). Приоритет = панели × показы, ×3 если имя похоже на текст (``$heuristic``).")
[void]$sb.AppendLine('Риск: в `Content/Paks` есть 8 файлов `.upak`; поддержку в FModel проверить до начала этапа 8.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| priority | resource | class | size | панели | показы | имя | где |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|---|')
foreach ($r in $texRows) {
    [void]$sb.AppendLine("| $($r.priority) | $(Cell $r.resource) | $($r.class) | $($r.size) | $($r.panels) | $($r.shows) | $(if ($r.name_hint) { 'да' }) | $(Cell $r.panel_list) |")
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Пути для экспорта (FModel/CUE4Parse → reference/textures/)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```')
foreach ($r in $texRows) { [void]$sb.AppendLine($r.resource) }
[void]$sb.AppendLine('```')
Write-Text (Join-Path $reportDir 'textures.md') $sb.ToString()

Write-Host "Отчёты: $reportDir"
Write-Host ("  сессий: {0}; хуков: {1} (мёртвых: {2}); переполнений: {3}; непереведённого: {4} + StringDB {5}; текстур: {6}" -f
    $selected.Count, $hookRows.Count, @($hookRows | Where-Object { $deadStatuses -contains $_.status }).Count,
    $overflowRows.Count, $untrRows.Count, $dbAgg.Count, @($texRows).Count)
