# GodWayExport.ps1 — сбор выгрузки вкладки «Божий путь» из игры (TASK-018, docs/tasks/TASK-018-godway-export.md).
#
# Из игры только ЧИТАЕТ: Saved/Mods/logs/godway/** (или Saved/Mods/logs/godway-*, если модуль не смог
# создать подпапку), строки [AbsruExport] из Saved/Logs/C7.log и Saved/Mods/lua/absoluteru_dev.lua.
# В папке игры ничего не создаёт, не меняет и не удаляет. Всё пишется в reference/godway_export/.
#
# -ProbeOnly   шаг 0 / проба 4: копия результатов пробы в raw/<дата>/ и probe_summary.md.
# без ключа    шаги 4.1–4.4: копия в raw/<дата>/, нарезка спрайтов из атласов (LockBits, без
#              премультипликации), проверка PNG, textures/ atlases/ calib/ и JSON в корне выгрузки,
#              manifest.json (размеры, sha256) и summary.md. Демо и шейдеры (4.5) — отдельный шаг.
# -FromRaw     собрать заново из уже скопированной папки raw/<дата>/ (игра не нужна).
#
# Примеры:
#   powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1 -ProbeOnly
#   powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1
#   powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1 -GameDir temp\fake_game -Out temp\godway_test
#   powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1 -FromRaw reference\godway_export\raw\2026-09-27_1200
param(
    [string]$GameDir,
    [string]$Out,                  # по умолчанию reference/godway_export
    [string]$FromRaw,
    [switch]$ProbeOnly
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Web.Extensions
Add-Type -AssemblyName System.Drawing

$repo = Split-Path $PSScriptRoot -Parent
function Resolve-Full([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
}
$Out = Resolve-Full $(if ($Out) { $Out } else { Join-Path $repo 'reference\godway_export' })
$FromRaw = Resolve-Full $FromRaw
if (-not $FromRaw) {
    if (-not $GameDir -and (Test-Path 'D:\Games\GMZZLauncher\Game\C7')) { $GameDir = 'D:\Games\GMZZLauncher\Game\C7' }
    $GameDir = Resolve-Full $GameDir
    if (-not $GameDir -or -not (Test-Path -LiteralPath (Join-Path $GameDir 'Saved'))) {
        throw "Папка игры не найдена: '$GameDir'. Укажите -GameDir <...\C7> или -FromRaw <папка raw>."
    }
} elseif (-not (Test-Path -LiteralPath $FromRaw)) {
    throw "Папка -FromRaw не найдена: $FromRaw"
}

# Никогда не писать в папку игры.
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
    if ($dict -is [System.Collections.IDictionary]) { return $dict[$key] }
    return $null
}
# Lua пишет пустой массив как {} (если JsonArray недоступен): считаем такой объект пустым списком.
function Get-List($value) {
    if ($null -eq $value) { return @() }
    if ($value -is [System.Collections.IDictionary]) {
        if ($value.Count -eq 0) { return @() }
        return @($value)
    }
    return @($value)
}
function Read-Json([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return $json.DeserializeObject([IO.File]::ReadAllText($path, $utf8))
}
function Get-Rel([string]$root, [string]$path) {
    return $path.Substring($root.TrimEnd('\').Length + 1).Replace('\', '/')
}

# 1. Копирование ИЗ игры -------------------------------------------------------------------------
$logLines = @()
if ($FromRaw) {
    $raw = $FromRaw
    $c7Copy = Join-Path $raw 'C7_AbsruExport.log'
    if (Test-Path -LiteralPath $c7Copy) { $logLines = @(Get-Content -LiteralPath $c7Copy -Encoding UTF8 | Where-Object { $_ }) }
    Write-Host "Сборка из $raw (игра не читается)"
} else {
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
        # Запасной вариант модуля: logs/godway-<имя> (файлы и подпапки godway-textures\... ).
        foreach ($entry in Get-ChildItem -LiteralPath $logsDir -Filter 'godway-*') {
            $name = $entry.Name.Substring('godway-'.Length)
            if ($entry.PSIsContainer) {
                $sources += @(Get-ChildItem -LiteralPath $entry.FullName -File -Recurse | ForEach-Object {
                    [pscustomobject]@{ File = $_; Relative = $name + '\' + $_.FullName.Substring($entry.FullName.Length + 1) } })
            } else {
                $sources += [pscustomobject]@{ File = $entry; Relative = $name }
            }
        }
    }
    if ($sources.Count -eq 0) {
        throw "В '$logsDir' нет godway\ и godway-*: выгрузка не запускалась или не смогла ничего записать. Проверьте строки [AbsruExport] в C7.log."
    }
    foreach ($source in $sources) {
        # Плоский режим модуля (подпапки не создались): "textures+x.png" -> textures\x.png.
        $target = Join-Path $raw ($source.Relative.Replace('+', '\'))
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $source.File.FullName -Destination $target
    }
    $c7 = Join-Path $gameSaved 'Logs\C7.log'
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
}

function Get-PngInfo([string]$path) {
    $bytes = New-Object byte[] 26
    $stream = [IO.File]::OpenRead($path)
    try { $read = $stream.Read($bytes, 0, 26); $length = $stream.Length } finally { $stream.Dispose() }
    $info = [pscustomobject]@{ Kind = 'unknown'; W = 0; H = 0; ColorType = $null; Bytes = $length }
    if ($read -ge 24 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) {
        $info.Kind = 'PNG'
        # [int]: -shl on [byte] overflows (512 read as 0).
        $info.W = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
        $info.H = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
        if ($read -ge 26) { $info.ColorType = $bytes[25] }
    } elseif ($read -ge 2 -and $bytes[0] -eq 0x23 -and $bytes[1] -eq 0x3F) {
        $info.Kind = 'HDR (Radiance)'
    } elseif ($read -ge 2 -and $bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D) {
        $info.Kind = 'BMP'
    }
    return $info
}

# 2. Сводка пробы (-ProbeOnly) -------------------------------------------------------------------
if ($ProbeOnly) {
    $report = New-Object System.Collections.Generic.List[string]
    $report.Add('# Проба AssetExport (TASK-018)')
    $report.Add('')
    $report.Add("Источник: ``$(if ($GameDir) { $GameDir } else { $raw })``, копия: ``$raw``")
    $report.Add('')
    $report.Add('## C7.log')
    $report.Add('')
    if ($logLines.Count -eq 0) { $report.Add('Строк `[AbsruExport]` нет.') }
    foreach ($line in $logLines) { $report.Add('    ' + $line) }
    $report.Add('')
    foreach ($probeName in 'probe.json', 'probe_retainer.json') {
        $probe = Read-Json (Join-Path $raw $probeName)
        if ($null -eq $probe) { continue }
        $report.Add("## $probeName")
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
        $icon = Get-V $probe 'icon'
        if ($icon) {
            $rt = Get-V $icon 'rt'
            $report.Add("- retainer icon: ``$(Get-V $icon 'result')``, rt: ``$(Get-V $rt 'class') $(Get-V $rt 'w')x$(Get-V $rt 'h') fmt=$(Get-V $rt 'format')``, copy: ``$(Get-V $icon 'copy_format')``, alpha: ``$(Get-V (Get-V $icon 'alpha') 'result')``")
        }
        foreach ($key in 'mid', 'mid_small') {
            $view = Get-V $probe $key
            if ($icon -and $view) { $report.Add("- retainer ${key}: ``$(Get-V $view 'result')``, animated: ``$(Get-V $view 'animated')``") }
        }
        $report.Add('')
    }
    $report.Add('## Файлы')
    $report.Add('')
    $report.Add('| Файл | Байт | Формат | Размер |')
    $report.Add('|---|---|---|---|')
    foreach ($file in Get-ChildItem -LiteralPath $raw -File -Recurse | Sort-Object FullName) {
        $relative = Get-Rel $raw $file.FullName
        if ($file.Extension -in '.png', '.hdr', '.bmp') {
            $info = Get-PngInfo $file.FullName
            $size = if ($info.Kind -eq 'PNG') { "$($info.W)x$($info.H) colortype=$($info.ColorType)" } else { '' }
            $report.Add("| $relative | $($info.Bytes) | $($info.Kind) | $size |")
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
    return
}

# 3. Сборка выгрузки (шаги 4.2–4.4) --------------------------------------------------------------
$state = Read-Json (Join-Path $raw 'export_state.json')
$texturesJson = Read-Json (Join-Path $raw 'textures.json')
$spritesJson = Read-Json (Join-Path $raw 'sprites.json')
$materialsJson = Read-Json (Join-Path $raw 'materials.json')
$timelineJson = Read-Json (Join-Path $raw 'timeline.json')
$layoutIndex = Read-Json (Join-Path $raw 'layout.json')
if ($null -eq $state -and $null -eq $texturesJson) {
    throw "В $raw нет export_state.json и textures.json: это не полная выгрузка (Probe = false). Для пробы запустите с -ProbeOnly."
}

# Производные папки и файлы пересобираются целиком; raw/ и demo/ не трогаются.
foreach ($dir in 'textures', 'atlases', 'calib') {
    $path = Join-Path $Out $dir
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
}
foreach ($file in 'manifest.json', 'summary.md', 'layout.json', 'timeline.json', 'materials.json', 'textures.json', 'sprites.json', 'export_state.json') {
    $path = Join-Path $Out $file
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
New-Item -ItemType Directory -Force $Out | Out-Null

$problems = New-Object System.Collections.Generic.List[string]
foreach ($dir in 'textures', 'atlases', 'calib') {
    $source = Join-Path $raw $dir
    if (Test-Path -LiteralPath $source) {
        Assert-OutsideGame (Join-Path $Out $dir)
        Copy-Item -LiteralPath $source -Destination (Join-Path $Out $dir) -Recurse
    }
}
foreach ($file in 'timeline.json', 'materials.json', 'textures.json', 'sprites.json', 'export_state.json') {
    $source = Join-Path $raw $file
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $Out $file) }
}

# PNG: сигнатура, размер по заголовку и совпадение с JSON.
$pngChecked = 0
function Test-Png([string]$relative, $w, $h, [string]$what) {
    $path = Join-Path $Out ($relative.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path)) { $problems.Add("нет файла ``$relative`` ($what)"); return $null }
    $info = Get-PngInfo $path
    $script:pngChecked++
    if ($info.Kind -ne 'PNG') { $problems.Add("``$relative``: не PNG ($($info.Kind), $($info.Bytes) байт)"); return $info }
    if ($info.W -le 0 -or $info.H -le 0) { $problems.Add("``$relative``: размер 0 в заголовке"); return $info }
    if ($null -ne $w -and $null -ne $h -and ([int]$w -ne $info.W -or [int]$h -ne $info.H)) {
        $problems.Add("``$relative``: $($info.W)x$($info.H), а в $what $([int]$w)x$([int]$h)")
    }
    return $info
}
$textures = @(Get-List (Get-V $texturesJson 'textures'))
foreach ($texture in $textures) {
    foreach ($field in 'file', 'file_linear') {
        $file = Get-V $texture $field
        if ($file -and (Get-V $texture 'status') -eq 'ok') { [void](Test-Png $file (Get-V $texture 'w') (Get-V $texture 'h') 'textures.json') }
    }
}
$atlases = @(Get-List (Get-V $spritesJson 'atlases'))
foreach ($atlas in $atlases) {
    foreach ($field in 'file', 'file_linear') {
        $file = Get-V $atlas $field
        if ($file -and (Get-V $atlas 'status') -eq 'ok') { [void](Test-Png $file (Get-V $atlas 'w') (Get-V $atlas 'h') 'sprites.json') }
    }
}
$calibSeries = @()
$calibDir = Join-Path $Out 'calib'
if (Test-Path -LiteralPath $calibDir) {
    foreach ($framesFile in Get-ChildItem -LiteralPath $calibDir -Filter 'frames.json' -Recurse) {
        $frames = Read-Json $framesFile.FullName
        $size = @(Get-List (Get-V $frames 'size'))
        $list = @(Get-List (Get-V $frames 'frames'))
        $exported = 0
        foreach ($frame in $list) {
            if ((Get-V $frame 'export') -eq 'ok') {
                $exported++
                [void](Test-Png (Get-V $frame 'file') $size[0] $size[1] (Get-Rel $Out $framesFile.FullName))
            }
        }
        $calibSeries += [pscustomobject]@{
            Dir = Get-Rel $Out $framesFile.DirectoryName; Kind = Get-V $frames 'kind'; Status = Get-V $frames 'status'
            Frames = $list.Count; Exported = $exported; Size = ($size -join 'x'); Copy = Get-V $frames 'copy_format'
            Alpha = Get-V $frames 'alpha'
        }
    }
}

# 4.2. Нарезка спрайтов: LockBits Format32bppArgb (прямая альфа), построчное копирование байтов.
function Read-Argb([string]$path) {
    $bitmap = New-Object System.Drawing.Bitmap($path)
    try {
        $rect = New-Object System.Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)
        $data = $bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $stride = $data.Stride
            $bytes = New-Object byte[] ($stride * $bitmap.Height)
            [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        } finally { $bitmap.UnlockBits($data) }
        return [pscustomobject]@{ W = $bitmap.Width; H = $bitmap.Height; Stride = $stride; Bytes = $bytes }
    } finally { $bitmap.Dispose() }
}
function Save-Crop($atlas, [int]$x, [int]$y, [int]$w, [int]$h, [string]$path) {
    $bitmap = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $data = $bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $row = New-Object byte[] ($w * 4)
            for ($line = 0; $line -lt $h; $line++) {
                [Array]::Copy($atlas.Bytes, ($y + $line) * $atlas.Stride + $x * 4, $row, 0, $w * 4)
                [System.Runtime.InteropServices.Marshal]::Copy($row, 0, [IntPtr]($data.Scan0.ToInt64() + $line * $data.Stride), $w * 4)
            }
        } finally { $bitmap.UnlockBits($data) }
        Assert-OutsideGame $path
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
}
$spriteDir = Join-Path $Out 'textures\sprites'
New-Item -ItemType Directory -Force $spriteDir | Out-Null
$atlasByName = @{}
foreach ($atlas in $atlases) { $atlasByName[[string](Get-V $atlas 'name')] = $atlas }
$atlasPixels = @{}
$spritesCut = 0
$spriteNames = @{}
foreach ($sprite in @(Get-List (Get-V $spritesJson 'sprites'))) {
    $name = [string](Get-V $sprite 'sprite')
    $atlas = $atlasByName[[string](Get-V $sprite 'atlas')]
    $file = Get-V $atlas 'file'
    if (-not $atlas -or -not $file -or (Get-V $atlas 'status') -ne 'ok') { $problems.Add("спрайт ``$name``: нет выгруженного атласа ``$(Get-V $sprite 'atlas')``"); continue }
    $atlasPath = Join-Path $Out ($file.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $atlasPath)) { $problems.Add("спрайт ``$name``: нет файла атласа ``$file``"); continue }
    if (-not $atlasPixels.ContainsKey($atlasPath)) { $atlasPixels[$atlasPath] = Read-Argb $atlasPath }
    $pixels = $atlasPixels[$atlasPath]
    $x, $y = [int](Get-V $sprite 'x'), [int](Get-V $sprite 'y')
    $w, $h = [int](Get-V $sprite 'w'), [int](Get-V $sprite 'h')
    if ($w -le 0 -or $h -le 0 -or $x -lt 0 -or $y -lt 0 -or $x + $w -gt $pixels.W -or $y + $h -gt $pixels.H) {
        $problems.Add("спрайт ``$name``: прямоугольник $x,$y ${w}x$h вне атласа $($pixels.W)x$($pixels.H)")
        continue
    }
    $safe = ($name -replace '[^\w\-\.]', '_')
    if ($spriteNames.ContainsKey($safe)) { $safe = $safe + '_' + (($(Get-V $sprite 'atlas')) -replace '[^\w\-\.]', '_') }
    $spriteNames[$safe] = $true
    Save-Crop $pixels $x $y $w $h (Join-Path $spriteDir ($safe + '.png'))
    $spritesCut++
}

# layout.json: индекс снимков + сами снимки (layout_NNN.json) одним файлом, текст снимков без изменений.
$snapshots = @(Get-List (Get-V $layoutIndex 'snapshots'))
$layoutParts = New-Object System.Collections.Generic.List[string]
foreach ($snapshot in $snapshots) {
    $file = Join-Path $raw ([string](Get-V $snapshot 'file'))
    if (Test-Path -LiteralPath $file) { $layoutParts.Add([IO.File]::ReadAllText($file, $utf8).Trim()) }
    else { $problems.Add("нет снимка раскладки ``$(Get-V $snapshot 'file')``") }
}
if ($layoutIndex) {
    $meta = @{}
    foreach ($key in $layoutIndex.Keys) { if ($key -ne 'snapshots') { $meta[$key] = $layoutIndex[$key] } }
    $metaText = $json.Serialize($meta).TrimEnd('}')
    $glue = if ($metaText.Length -gt 1) { ',' } else { '' }
    Write-Text (Join-Path $Out 'layout.json') ($metaText + $glue + '"snapshots":[' + ($layoutParts -join ',') + ']}')
}

# 4.3. manifest.json -------------------------------------------------------------------------------
$assets = New-Object System.Collections.Generic.List[object]
$counts = @{}
foreach ($file in Get-ChildItem -LiteralPath $Out -File -Recurse | Sort-Object FullName) {
    $relative = Get-Rel $Out $file.FullName
    if ($relative -like 'raw/*' -or $relative -like 'demo/*' -or $relative -in 'manifest.json', 'summary.md', 'README.md') { continue }
    $kind = if ($relative -like 'textures/sprites/*') { 'sprite' } elseif ($relative -like 'textures/*') { 'texture' }
        elseif ($relative -like 'atlases/*') { 'atlas' } elseif ($relative -like 'calib/*' -and $file.Extension -eq '.png') { 'calib' }
        elseif ($file.Extension -eq '.json') { 'json' } else { 'other' }
    # Явные типы: значения в PSObject-обёртке JavaScriptSerializer не сериализует.
    $entry = [ordered]@{ path = [string]$relative; kind = [string]$kind; bytes = [long]$file.Length; sha256 = [string](Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    if ($file.Extension -eq '.png') {
        $info = Get-PngInfo $file.FullName
        $entry.w = [int]$info.W
        $entry.h = [int]$info.H
    }
    $assets.Add($entry)
    $counts[[string]$kind] = [int](1 + $(if ($counts.ContainsKey($kind)) { $counts[$kind] } else { 0 }))
}
$manifest = [ordered]@{
    task = 'TASK-018'; built = [string](Get-Date -Format 'yyyy-MM-dd HH:mm'); raw = [string](Get-Rel $repo $raw)
    version = [string](Get-V $state 'version'); counts = $counts; assets = $assets.ToArray()
}
Write-Text (Join-Path $Out 'manifest.json') ($json.Serialize($manifest))

# 4.4. summary.md ----------------------------------------------------------------------------------
$report = New-Object System.Collections.Generic.List[string]
$report.Add('# Выгрузка «Божий путь» (TASK-018)')
$report.Add('')
$report.Add("Сырые данные: ``$(Get-Rel $repo $raw)``, собрано $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Версия патча: ``$(Get-V $state 'version')``, статус выгрузки: ``$(Get-V $state 'status')``.")
$report.Add('')
$report.Add('## Итог')
$report.Add('')
$report.Add('| Тип | Файлов |')
$report.Add('|---|---|')
foreach ($kind in 'texture', 'atlas', 'sprite', 'calib', 'json', 'other') {
    if ($counts.ContainsKey($kind)) { $report.Add("| $kind | $($counts[$kind]) |") }
}
$report.Add('')
$report.Add("- PNG проверено: $pngChecked, спрайтов нарезано: $spritesCut, снимков раскладки: $($snapshots.Count), путей (смен выбранного пути): $(@(Get-List (Get-V $state 'paths')).Count).")
$report.Add("- Дорожка: событий $(Get-V $state 'events'), отброшено $(Get-V $state 'events_dropped'); открытий панели $(Get-V $state 'opens'), лимит: ``$(Get-V $state 'limited')``, файлов $(Get-V $state 'files'), оценка $(Get-V $state 'mb') МБ (несжатый RGBA).")
$rates = Get-V $timelineJson 'rates'
if ($rates) {
    $report.Add("- Частота выборки дорожки: $([math]::Round([double](Get-V $rates 'samples_per_s'), 1)) выборок/с, полных обходов $([math]::Round([double](Get-V $rates 'sweeps_per_s'), 2))/с, активных треков $(Get-V $rates 'active') из $(Get-V $rates 'tracks').")
}
$report.Add('')

$report.Add('## C7.log')
$report.Add('')
$interesting = @($logLines | Where-Object { $_ -match '\[AbsruExport\] (done|limit|error|disabled|full|snapshot)' -or $_ -match 'asset export unavailable' })
if ($interesting.Count -eq 0) { $report.Add('Строк `[AbsruExport] done/limit/error` нет.') }
foreach ($line in $interesting) { $report.Add('    ' + ($line -replace '^.*?\[AbsruExport\]', '[AbsruExport]')) }
$report.Add('')

$report.Add('## Базовые материалы')
$report.Add('')
$bases = Get-V $materialsJson 'bases'
if ($bases -is [System.Collections.IDictionary] -and $bases.Count -gt 0) {
    $report.Add('| Material | MI | MID | Виджетов |')
    $report.Add('|---|---|---|---|')
    foreach ($key in ($bases.Keys | Sort-Object)) {
        $base = $bases[$key]
        $instances = @(Get-List (Get-V $base 'instances'))
        $report.Add("| ``$key`` | $($instances.Count) | $(Get-V $base 'mids') | $(Get-V $base 'widgets') |")
    }
    $report.Add('')
    foreach ($key in ($bases.Keys | Sort-Object)) {
        $names = @((@(Get-List (Get-V $bases[$key] 'instances'))) | ForEach-Object { ($_ -split '[./]')[-1] })
        $report.Add("- ``$(($key -split '[./]')[-1])``: $($names -join ', ')")
    }
} else {
    $report.Add('Нет (materials.json отсутствует или пуст).')
}
$report.Add('')

$report.Add('## Текстуры: стриминг и SRGB')
$report.Add('')
$notStreamed = @($textures + $atlases | Where-Object { (Get-V $_ 'streamed') -ne $true })
$noSrgb = @($textures + $atlases | Where-Object { $null -eq (Get-V $_ 'SRGB') })
$failed = @($textures + $atlases | Where-Object { (Get-V $_ 'status') -ne 'ok' })
if ($notStreamed.Count -eq 0) { $report.Add('- `streamed != true`: нет.') }
else { $report.Add("- ``streamed != true`` ($($notStreamed.Count)):"); foreach ($t in $notStreamed) { $report.Add("  - ``$(Get-V $t 'name')``: $(Get-V $t 'streamed')") } }
if ($noSrgb.Count -eq 0) { $report.Add('- SRGB прочитан у всех.') }
else { $report.Add("- SRGB не прочитался ($($noSrgb.Count), выгружены .srgb.png и .linear.png):"); foreach ($t in $noSrgb) { $report.Add("  - ``$(Get-V $t 'name')``") } }
if ($failed.Count -gt 0) { $report.Add("- Не выгружены ($($failed.Count)):"); foreach ($t in $failed) { $report.Add("  - ``$(Get-V $t 'name')``: $(Get-V $t 'status') $(Get-V $t 'error')") } }
$unknown = @(Get-List (Get-V $texturesJson 'unknown_resources'))
if ($unknown.Count -gt 0) { $report.Add("- Прочие ресурсы кистей без выгрузки ($($unknown.Count)):"); foreach ($u in $unknown) { $report.Add("  - ``$(Get-V $u 'class')`` $(Get-V $u 'path')") } }
$report.Add('')

$report.Add('## Эталонные кадры (calib/)')
$report.Add('')
$calib = Get-V $state 'calib'
if ($calibSeries.Count -eq 0) {
    $report.Add("calib/ нет. Состояние: enabled=``$(Get-V $calib 'enabled')``, available=``$(Get-V $calib 'available')``, stopped=``$(Get-V $calib 'stopped')``.")
} else {
    $report.Add("Альфа retainer: ``$(Get-V $calib 'alpha')``, формат копии: ``$(Get-V $calib 'copy_format')``, available=``$(Get-V $calib 'available')``.")
    $report.Add('')
    $report.Add('| Папка | Вид | Статус | Кадров | Выгружено | Размер | Копия |')
    $report.Add('|---|---|---|---|---|---|---|')
    foreach ($s in ($calibSeries | Sort-Object Dir)) { $report.Add("| $($s.Dir) | $($s.Kind) | $($s.Status) | $($s.Frames) | $($s.Exported) | $($s.Size) | $($s.Copy) |") }
}
$report.Add('')

$report.Add('## Проблемы')
$report.Add('')
if ($problems.Count -eq 0) { $report.Add('Нет.') }
foreach ($problem in $problems) { $report.Add("- $problem") }
$summary = Join-Path $Out 'summary.md'
Write-Text $summary (($report -join "`n") + "`n")
Write-Host ''
$report | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "Выгрузка: $Out"
Write-Host "Сводка: $summary"
