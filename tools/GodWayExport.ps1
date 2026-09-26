# GodWayExport.ps1 — сбор выгрузки вкладки «Божий путь» из игры (TASK-018, docs/tasks/TASK-018-godway-export.md).
#
# Из игры только ЧИТАЕТ: Saved/Mods/logs/godway/** (или Saved/Mods/logs/godway-*, если модуль не смог
# создать подпапку), строки [AbsruExport] из Saved/Logs/C7.log и Saved/Mods/lua/absoluteru_dev.lua.
# В папке игры ничего не создаёт, не меняет и не удаляет. Всё пишется в reference/godway_export/.
#
# Сейчас реализован только шаг 0 (-ProbeOnly): копия результатов пробы и сводка по probe.json и PNG.
#
# Примеры:
#   powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1 -ProbeOnly
#   powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1 -ProbeOnly -GameDir temp\fake_game -Out temp\godway_test
param(
    [string]$GameDir,
    [string]$Out,                  # по умолчанию reference/godway_export
    [switch]$ProbeOnly
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Web.Extensions

$repo = Split-Path $PSScriptRoot -Parent
function Resolve-Full([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
}
if (-not $GameDir -and (Test-Path 'D:\Games\GMZZLauncher\Game\C7')) { $GameDir = 'D:\Games\GMZZLauncher\Game\C7' }
$GameDir = Resolve-Full $GameDir
if (-not $GameDir -or -not (Test-Path -LiteralPath (Join-Path $GameDir 'Saved'))) {
    throw "Папка игры не найдена: '$GameDir'. Укажите -GameDir <...\C7>."
}
$Out = Resolve-Full $(if ($Out) { $Out } else { Join-Path $repo 'reference\godway_export' })

# Никогда не писать в папку игры.
function Assert-OutsideGame([string]$path) {
    $game = $GameDir.TrimEnd('\') + '\'
    $full = (Resolve-Full $path).TrimEnd('\') + '\'
    if ($full.StartsWith($game, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Запись в папку игры запрещена: $path"
    }
}
Assert-OutsideGame $Out

if (-not $ProbeOnly) {
    throw "Шаги 1–5 (полная выгрузка и демо) ещё не реализованы: запустите с -ProbeOnly."
}

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
    if ($dict -is [System.Collections.IDictionary]) { return $dict[$key] }
    return $null
}

# 1. Копирование ИЗ игры -------------------------------------------------------------------------
$gameSaved = Join-Path $GameDir 'Saved'
$logsDir = Join-Path $gameSaved 'Mods\logs'
$raw = Join-Path $Out ('raw\' + (Get-Date -Format 'yyyy-MM-dd_HHmm'))
Assert-OutsideGame $raw
$sources = @()
$godwayDir = Join-Path $logsDir 'godway'
if (Test-Path -LiteralPath $godwayDir) {
    $sources += @(Get-ChildItem -LiteralPath $godwayDir -File -Recurse | ForEach-Object {
        [pscustomobject]@{ File = $_; Relative = $_.FullName.Substring($godwayDir.Length + 1) } })
}
if (Test-Path -LiteralPath $logsDir) {
    # Запасной вариант модуля: logs/godway-<имя>.
    $sources += @(Get-ChildItem -LiteralPath $logsDir -File -Filter 'godway-*' | ForEach-Object {
        [pscustomobject]@{ File = $_; Relative = $_.Name.Substring('godway-'.Length) } })
}
if ($sources.Count -eq 0) {
    throw "В '$logsDir' нет godway\ и godway-*: проба не запускалась или не смогла ничего записать. Проверьте строки [AbsruExport] в C7.log."
}
foreach ($source in $sources) {
    $target = Join-Path $raw $source.Relative
    New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $source.File.FullName -Destination $target
}
$c7 = Join-Path $gameSaved 'Logs\C7.log'
$logLines = @()
if (Test-Path -LiteralPath $c7) {
    # Игра держит C7.log открытым: читаем с FileShare.ReadWrite.
    $stream = [IO.File]::Open($c7, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = New-Object IO.StreamReader($stream, $utf8)
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Contains('[AbsruExport]') -or $line.Contains('asset export unavailable')) { $logLines += $line }
        }
    } finally { $stream.Dispose() }
}
Write-Text (Join-Path $raw 'C7_AbsruExport.log') (($logLines -join "`n") + "`n")
$flagsFile = Join-Path $gameSaved 'Mods\lua\absoluteru_dev.lua'
if (Test-Path -LiteralPath $flagsFile) { Copy-Item -LiteralPath $flagsFile -Destination (Join-Path $raw 'absoluteru_dev.lua') }
Write-Host "Скопировано из игры: $($sources.Count) файлов, строк [AbsruExport]: $($logLines.Count) -> $raw"

# 2. Сводка пробы --------------------------------------------------------------------------------
function Get-ImageInfo([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $kind = 'unknown'
    $size = ''
    if ($bytes.Length -ge 24 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) {
        $kind = 'PNG'
        # [int]: -shl on [byte] overflows (512 read as 0).
        $w = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
        $h = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
        $size = "${w}x${h}"
        if ($bytes.Length -ge 26) { $size += " colortype=$($bytes[25])" }
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0x23 -and $bytes[1] -eq 0x3F) {
        $kind = 'HDR (Radiance)'
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D) {
        $kind = 'BMP'
    }
    return [pscustomobject]@{ Kind = $kind; Size = $size; Bytes = $bytes.Length }
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add('# Проба AssetExport (TASK-018, шаг 0)')
$report.Add('')
$report.Add("Источник: ``$GameDir``, копия: ``$raw``")
$report.Add('')
$report.Add('## C7.log')
$report.Add('')
if ($logLines.Count -eq 0) { $report.Add('Строк `[AbsruExport]` нет.') }
foreach ($line in $logLines) { $report.Add('    ' + $line) }
$report.Add('')

$probePath = Join-Path $raw 'probe.json'
if (Test-Path -LiteralPath $probePath) {
    $probe = $json.DeserializeObject([IO.File]::ReadAllText($probePath, $utf8))
    $report.Add('## probe.json')
    $report.Add('')
    $report.Add("- status: ``$(Get-V $probe 'status')``, последняя стадия: ``$(Get-V $probe 'stage')``, rt_format: ``$(Get-V $probe 'rt_format')``")
    $stages = Get-V $probe 'stages'
    if ($stages -is [System.Collections.IDictionary]) {
        foreach ($key in $stages.Keys) { $report.Add("- стадия ``$key``: $($stages[$key])") }
    }
    $mid = Get-V $probe 'mid'
    $draw = Get-V $mid 'draw'
    if ($draw) { $report.Add("- mid_draw: ``$(Get-V $draw 'result')``, animated_samples: ``$(Get-V $mid 'animated_samples')``") }
    $sprite = Get-V $probe 'sprite'
    if ($sprite) { $report.Add("- sprite: ``$((@(Get-V $sprite 'found')) -join ', ')``") }
    $report.Add('')
} else {
    $report.Add('probe.json не найден.')
    $report.Add('')
}

$report.Add('## Файлы')
$report.Add('')
$report.Add('| Файл | Байт | Формат | Размер |')
$report.Add('|---|---|---|---|')
foreach ($file in Get-ChildItem -LiteralPath $raw -File -Recurse | Sort-Object FullName) {
    $relative = $file.FullName.Substring($raw.Length + 1)
    if ($file.Extension -in '.png', '.hdr', '.bmp') {
        $info = Get-ImageInfo $file.FullName
        $report.Add("| $relative | $($info.Bytes) | $($info.Kind) | $($info.Size) |")
    } else {
        $report.Add("| $relative | $($file.Length) | | |")
    }
}
$summary = Join-Path $raw 'probe_summary.md'
Write-Text $summary (($report -join "`n") + "`n")
Write-Host ''
$report | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "Сводка: $summary"
