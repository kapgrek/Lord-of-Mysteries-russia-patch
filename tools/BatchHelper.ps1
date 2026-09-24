# BatchHelper.ps1 - Slice chunks for AI translators, import results, and track progress
param(
    [ValidateSet('Export', 'Import', 'Stats', 'Dashboard')]
    [string]$Action = 'Dashboard',
    [int]$Batch = 0,               # 0 = All batches (Dashboard), or 1..27
    [int]$Count = 100,             # Chunk size (strings per chunk)
    [int]$Skip = 0,                # Number of untranslated strings to skip
    [string]$InputFile = '',       # Custom path to translated JSON
    [string]$OutputFile = '',      # Custom path for exported chunk
    [switch]$IncludePrompt         # Include AI translation prompt & rules in export
)

$ErrorActionPreference = 'Stop'
$batchesDir = Join-Path $PSScriptRoot "..\source\translation_batches"
$docsDir = Join-Path $PSScriptRoot "..\docs"
$tempDir = Join-Path $PSScriptRoot "..\temp"

# Safe Russian string helpers for manifest synchronization
$ruWaiting = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xD0,0x9E,0xD0,0xB6,0xD0,0xB8,0xD0,0xB4,0xD0,0xB0,0xD0,0xB5,0xD1,0x82,0x20,0xD0,0xBF,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB2,0xD0,0xBE,0xD0,0xB4,0xD0,0xB0))
$ruDone    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xD0,0x93,0xD0,0xBE,0xD1,0x82,0xD0,0xBE,0xD0,0xB2))
$ruProg    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xD0,0x92,0x20,0xD0,0xBF,0xD1,0x80,0xD0,0xBE,0xD1,0x86,0xD0,0xB5,0xD1,0x81,0xD1,0x81,0xD0,0xB5))
$ruBatch   = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xD0,0x91,0xD0,0xB0,0xD1,0x82,0xD1,0x87))

# Function to infer context category for FNV-1a shuffled strings
function Get-StringContext([string]$cn, [string]$en) {
    if ($en -match '^\s*$' -and -not [string]::IsNullOrWhiteSpace($cn)) { return 'BakedText/KeepEmpty' }
    if ($cn -match '^\[UIFrame') { return 'EngineLog/DoNotTranslate' }
    if ($cn -match "Texture2D'|/Game/|Atlas_|\.uasset") { return 'AssetPath/DoNotTranslate' }
    if ($cn -match '#CanMove') { return 'LetterPuzzle/KeepMarkers' }
    if ($cn -match '%Y.*%m.*%d') { return 'DateTimeFormat' }
    if ($cn -match '<Assistant_Title') { return 'Achievement/QuestTitle' }
    if ($cn -match '<HyperLink') { return 'SkillLink' }
    if ($cn -match '<DecH') { return 'ItemCraftLore' }
    if ($cn -match '<P_Heart') { return 'DialogueEmotion' }
    if ($cn -match '<[iI]mg\s') { return 'InlineIcon' }
    if ($cn.StartsWith([char]0x3010) -and $cn.Contains([char]0x3011)) { return 'ActionMarker' }
    if ($cn -match '^[0-9,\.\s;:-]+$') { return 'TechnicalCoord/Number' }
    if ($cn.EndsWith(':') -or $cn.EndsWith([char]0xFF1A)) { return 'Label' }
    return 'General'
}

# Function to load AI prompt instructions
function Get-TaskPrompt([int]$batchNum, [int]$count, [int]$skip) {
    $promptFile = Join-Path $docsDir "AI_TRANSLATOR_PROMPT.md"
    $basePrompt = ""
    if (Test-Path $promptFile) {
        $baseText = [System.IO.File]::ReadAllText($promptFile, [System.Text.Encoding]::UTF8)
        $match = [System.Text.RegularExpressions.Regex]::Match($baseText, '```(?:text)?\s*([\s\S]*?)```')
        if ($match.Success) {
            $basePrompt = $match.Groups[1].Value.Trim()
        } else {
            $basePrompt = $baseText
        }
    }
    
    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine($basePrompt) | Out-Null
    $sb.AppendLine("`n=======================================================") | Out-Null
    $batchStr = "{0:D3}" -f $batchNum
    $sb.AppendLine("### CURRENT TRANSLATION TASK (Batch $batchStr, chunk: $count strings, skip offset: $skip):") | Out-Null
    $sb.AppendLine("Translate the strings in the array below. Return ONLY a JSON dictionary: { `"ID`": `"Russian translation`" }:") | Out-Null
    return $sb.ToString()
}

# 1. ACTION: STATS / DASHBOARD
if ($Action -eq 'Stats' -or $Action -eq 'Dashboard') {
    if ($Batch -eq 0) {
        # Comprehensive Dashboard across all 27 batches
        Write-Host "==========================================================================================" -ForegroundColor Cyan
        Write-Host "           Lord of the Mysteries (v2.6-RU) - Translation Progress Dashboard" -ForegroundColor Cyan
        Write-Host "==========================================================================================" -ForegroundColor Cyan
        Write-Host (" {0,-10} {1,-18} {2,10} {3,12} {4,10} {5,10}  {6,-14}" -f "Batch", "File", "Total", "Translated", "Remaining", "%", "Status")
        Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor Gray

        $batchFiles = Get-ChildItem -Path $batchesDir -Filter "batch_*.json" | Sort-Object Name
        $totalStrings = 0
        $totalDone = 0
        $pattern = '"target_ru"\s*:\s*"(?<ru>(?:\\.|[^"\\])*)"'
        $manifestLines = [System.Collections.Generic.List[string]]::new()

        foreach ($f in $batchFiles) {
            $num = $f.BaseName.Substring(6)
            $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            $matches = [System.Text.RegularExpressions.Regex]::Matches($text, $pattern)
            $count = $matches.Count
            $done = 0
            foreach ($m in $matches) {
                if (-not [string]::IsNullOrWhiteSpace($m.Groups['ru'].Value)) { $done++ }
            }
            $totalStrings += $count
            $totalDone += $done
            $pct = if ($count -gt 0) { [Math]::Round(($done / $count) * 100, 1) } else { 0 }
            $status = if ($done -eq 0) { "Waiting" } elseif ($done -eq $count) { "Complete" } else { "In Progress" }
            $color = if ($done -eq $count) { "Green" } elseif ($done -gt 0) { "Yellow" } else { "DarkGray" }

            Write-Host (" Batch {0,-4} {1,-18} {2,10:N0} {3,12:N0} {4,10:N0} {5,9:N1}%  {6,-14}" -f $num, $f.Name, $count, $done, ($count - $done), $pct, $status) -ForegroundColor $color

            $start = [int]$num * 5000 - 4999
            $end = $start + $count - 1
            $manifestStatus = if ($done -eq 0) { $ruWaiting } elseif ($done -eq $count) { $ruDone } else { "$ruProg ($pct`%)" }
            $manifestLines.Add(("| $ruBatch {0} | ``{1}`` | {2} - {3} | {4} |" -f $num, $f.Name, $start, $end, $manifestStatus))
        }

        Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor Gray
        $totalPct = if ($totalStrings -gt 0) { [Math]::Round(($totalDone / $totalStrings) * 100, 2) } else { 0 }
        Write-Host (" {0,-29} {1,10:N0} {2,12:N0} {3,10:N0} {4,9:N2}%" -f "PROJECT TOTAL:", $totalStrings, $totalDone, ($totalStrings - $totalDone), $totalPct) -ForegroundColor Green
        Write-Host "==========================================================================================" -ForegroundColor Cyan

        # Sync BATCH_MANIFEST.md
        $manifestPath = Join-Path $batchesDir "BATCH_MANIFEST.md"
        $manifestSb = [System.Text.StringBuilder]::new()
        $manifestSb.AppendLine("# Manifest (Lord of the Mysteries v2.6-RU)") | Out-Null
        $manifestSb.AppendLine("`nTotal strings: **$totalStrings** (translated: **$totalDone**, **$totalPct%**)") | Out-Null
        $manifestSb.AppendLine("Batch size: **5000**") | Out-Null
        $manifestSb.AppendLine("Batch count: **$($batchFiles.Count)**`n") | Out-Null
        $manifestSb.AppendLine("| Batch | File | Range | Status |") | Out-Null
        $manifestSb.AppendLine("|---|---|---|---|") | Out-Null
        foreach ($ml in $manifestLines) { $manifestSb.AppendLine($ml) | Out-Null }
        [System.IO.File]::WriteAllText($manifestPath, $manifestSb.ToString(), [System.Text.Encoding]::UTF8)
        Write-Host "[OK] BATCH_MANIFEST.md successfully synchronized with live progress." -ForegroundColor Green
        exit 0
    } else {
        # Statistics for single batch
        $batchNumStr = $Batch.ToString("D3")
        $batchFile = Join-Path $batchesDir "batch_$batchNumStr.json"
        if (-not (Test-Path $batchFile)) {
            Write-Error "Batch file $batchFile not found!"
            exit 1
        }
        Write-Host "=== Statistics for Batch $batchNumStr ===" -ForegroundColor Cyan
        $text = [System.IO.File]::ReadAllText($batchFile, [System.Text.Encoding]::UTF8)
        $pattern = '"target_ru"\s*:\s*"(?<ru>(?:\\.|[^"\\])*)"'
        $matches = [System.Text.RegularExpressions.Regex]::Matches($text, $pattern)
        $total = $matches.Count
        $done = 0
        foreach ($m in $matches) {
            if (-not [string]::IsNullOrWhiteSpace($m.Groups['ru'].Value)) { $done++ }
        }
        $percent = if ($total -gt 0) { [Math]::Round(($done / $total) * 100, 2) } else { 0 }
        Write-Host "Total strings:      $total"
        Write-Host "Translated:         $done ($percent%)" -ForegroundColor Green
        Write-Host "Remaining:          $($total - $done)" -ForegroundColor Yellow
        exit 0
    }
}

# 2. ACTION: EXPORT CHUNK
if ($Action -eq 'Export') {
    if ($Batch -le 0) {
        Write-Error "Please specify a batch number: -Batch 1..27"
        exit 1
    }
    $batchNumStr = $Batch.ToString("D3")
    $batchFile = Join-Path $batchesDir "batch_$batchNumStr.json"
    if (-not (Test-Path $batchFile)) {
        Write-Error "Batch file $batchFile not found!"
        exit 1
    }

    Write-Host "=== Exporting chunk ($Count strings, skip $Skip) from batch $batchNumStr ===" -ForegroundColor Cyan
    $text = [System.IO.File]::ReadAllText($batchFile, [System.Text.Encoding]::UTF8)
    $itemRegex = [System.Text.RegularExpressions.Regex]::new(
        '\{\s*"id"\s*:\s*"(?<id>[^"]+)"\s*,\s*"source_cn"\s*:\s*"(?<cn>(?:\\.|[^"\\])*)"\s*,\s*"ref_en"\s*:\s*"(?<en>(?:\\.|[^"\\])*)"\s*,\s*"target_ru"\s*:\s*"(?<ru>(?:\\.|[^"\\])*)"\s*\}',
        [System.Text.RegularExpressions.RegexOptions]::Compiled
    )

    $chunk = [System.Collections.Generic.List[object]]::new()
    $skipped = 0

    foreach ($m in $itemRegex.Matches($text)) {
        if ([string]::IsNullOrWhiteSpace($m.Groups['ru'].Value)) {
            if ($skipped -lt $Skip) {
                $skipped++
                continue
            }

            $rawCn = $m.Groups['cn'].Value
            $rawEn = $m.Groups['en'].Value

            # Clean up escape sequences so ConvertTo-Json does not double-escape
            $cnClean = $rawCn.Replace('\\n', "`n").Replace('\\r', "`r").Replace('\\t', "`t").Replace('\"', '"').Replace('\\', '\')
            $enClean = $rawEn.Replace('\\n', "`n").Replace('\\r', "`r").Replace('\\t', "`t").Replace('\"', '"').Replace('\\', '\')

            $ctx = Get-StringContext -cn $cnClean -en $enClean

            $chunk.Add([PSCustomObject]@{
                id = $m.Groups['id'].Value
                ctx = $ctx
                cn = $cnClean
                en = $enClean
            })
            if ($chunk.Count -ge $Count) { break }
        }
    }

    if ($chunk.Count -eq 0) {
        Write-Host "No remaining untranslated strings found in batch $batchNumStr with skip $Skip!" -ForegroundColor Yellow
        exit 0
    }

    # Format clean JSON
    $outJson = ($chunk | ConvertTo-Json -Depth 3) `
        -replace '\\u003c', '<' `
        -replace '\\u003e', '>' `
        -replace '\\u0026', '&' `
        -replace '\\u0027', "'"

    $finalExportText = $outJson
    if ($IncludePrompt) {
        $promptHeader = Get-TaskPrompt -batchNum $Batch -count $chunk.Count -skip $Skip
        $finalExportText = $promptHeader + "`n" + $outJson
    }

    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    $targetFile = if (-not [string]::IsNullOrEmpty($OutputFile)) { $OutputFile } else { Join-Path $tempDir "temp_chunk.json" }
    [System.IO.File]::WriteAllText($targetFile, $finalExportText, [System.Text.Encoding]::UTF8)
    Write-Host "Exported $($chunk.Count) strings to $targetFile" -ForegroundColor Green

    exit 0
}

# 3. ACTION: IMPORT TRANSLATIONS
if ($Action -eq 'Import') {
    if ($Batch -le 0) {
        Write-Error "Please specify a batch number: -Batch 1..27"
        exit 1
    }
    $batchNumStr = $Batch.ToString("D3")
    $batchFile = Join-Path $batchesDir "batch_$batchNumStr.json"
    if (-not (Test-Path $batchFile)) {
        Write-Error "Batch file $batchFile not found!"
        exit 1
    }

    Write-Host "=== Importing translations into batch $batchNumStr ===" -ForegroundColor Cyan
    $content = ""

    if (-not [string]::IsNullOrEmpty($InputFile) -and (Test-Path $InputFile)) {
        $content = [System.IO.File]::ReadAllText($InputFile, [System.Text.Encoding]::UTF8)
    } else {
        $tempFile = Join-Path $tempDir "temp_chunk.json"
        if (-not (Test-Path $tempFile)) {
            $legacyTempFile = Join-Path $batchesDir "temp_chunk.json"
            if (Test-Path $legacyTempFile) { $tempFile = $legacyTempFile }
        }
        if (Test-Path $tempFile) {
            $content = [System.IO.File]::ReadAllText($tempFile, [System.Text.Encoding]::UTF8)
        } else {
            Write-Error "Specify -InputFile or provide temp_chunk.json in temp/!"
            exit 1
        }
    }

    # Strip markdown code blocks if AI wrapped output in ```json ... ```
    $content = $content.Trim()
    $fence = [char]96 + [char]96 + [char]96
    if ($content.StartsWith($fence + "json")) { $content = $content.Substring(7) }
    if ($content.StartsWith($fence)) { $content = $content.Substring(3) }
    if ($content.EndsWith($fence)) { $content = $content.Substring(0, $content.Length - 3) }
    $content = $content.Trim()

    $dict = $content | ConvertFrom-Json

    $map = @{}
    if ($dict -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $dict.PSObject.Properties) {
            $map[$prop.Name] = [string]$prop.Value
        }
    } elseif ($dict -is [Array]) {
        foreach ($entry in $dict) {
            $tid = if ($entry.id) { $entry.id } else { $entry.ID }
            $tru = if ($entry.target_ru) { $entry.target_ru } else { $entry.ru }
            if ($tid -and $tru) { $map[$tid] = [string]$tru }
        }
    }

    $batchText = [System.IO.File]::ReadAllText($batchFile, [System.Text.Encoding]::UTF8)
    $updated = 0

    foreach ($k in $map.Keys) {
        $ruVal = $map[$k]
        if ([string]::IsNullOrWhiteSpace($ruVal)) { continue }

        # Normalize escape sequences for batch JSON
        $ruValClean = $ruVal.Replace("`r`n", "`n").Replace("`r", "`n")
        $escaped = $ruValClean.Replace("\", "\\").Replace('"', '\"').Replace("`n", "\n").Replace("`t", "\t")
        $pattern = '("id"\s*:\s*"' + [System.Text.RegularExpressions.Regex]::Escape($k) + '"[\s\S]*?"target_ru"\s*:\s*)"(?:\\.|[^"\\])*"'

        if ([System.Text.RegularExpressions.Regex]::IsMatch($batchText, $pattern)) {
            $batchText = [System.Text.RegularExpressions.Regex]::Replace($batchText, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + '"' + $escaped + '"' })
            $updated++
        }
    }

    [System.IO.File]::WriteAllText($batchFile, $batchText, [System.Text.Encoding]::UTF8)
    Write-Host "[OK] Successfully updated $updated strings in $batchFile!" -ForegroundColor Green

    # Automatically recompile runtime shards so updated translations immediately optimize into the database layer!
    $shardCompiler = Join-Path $PSScriptRoot "ShardCompiler.exe"
    if (-not (Test-Path $shardCompiler)) {
        & (Join-Path $PSScriptRoot "BuildTools.ps1") -Only ShardCompiler
    }
    Write-Host "Recompiling translation shards for instant database-layer optimization..." -ForegroundColor Cyan
    Push-Location $PSScriptRoot
    try { & $shardCompiler } finally { Pop-Location }
    exit 0
}