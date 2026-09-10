# VerifyBatch.ps1 - Validates translation batch integrity and engine safety
param(
    [int]$Batch = 0, # 0 = all batches
    [string]$BatchesDir = '..\source\translation_batches'
)

$ErrorActionPreference = 'Stop'
$resolvedDir = Resolve-Path (Join-Path $PSScriptRoot $BatchesDir)

Write-Host "=== Translation Batch Validator (Lord of the Mysteries v2.6-RU) ===" -ForegroundColor Cyan

$files = if ($Batch -gt 0) {
    @((Join-Path $resolvedDir ("batch_{0:D3}.json" -f $Batch)))
} else {
    Get-ChildItem -Path $resolvedDir -Filter "batch_*.json" | Sort-Object Name | ForEach-Object { $_.FullName }
}

$tagRegex = [System.Text.RegularExpressions.Regex]::new('<(?!\/)([A-Za-z0-9_]+)[^>]*>', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$closeTagRegex = [System.Text.RegularExpressions.Regex]::new('<\/>', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$specRegex = [System.Text.RegularExpressions.Regex]::new('%[-+0-9\.]*[sdfeEgGcxX]', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$puzzleRegex = [System.Text.RegularExpressions.Regex]::new('#CanMove_[^#]+#', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$imgTagRegex = [System.Text.RegularExpressions.Regex]::new('<[iI]mg\s+[^>]*\/?>', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$cyrillicRegex = [System.Text.RegularExpressions.Regex]::new('[\p{IsCyrillic}]', [System.Text.RegularExpressions.RegexOptions]::Compiled)

# Regex to extract batch items
$itemRegex = [System.Text.RegularExpressions.Regex]::new(
    '\{\s*"id"\s*:\s*"(?<id>[^"]+)"\s*,\s*"source_cn"\s*:\s*"(?<cn>(?:\\.|[^"\\])*)"\s*,\s*"ref_en"\s*:\s*"(?<en>(?:\\.|[^"\\])*)"\s*,\s*"target_ru"\s*:\s*"(?<ru>(?:\\.|[^"\\])*)"\s*\}',
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)

$totalChecked = 0
$totalTranslated = 0
$totalErrors = 0
$totalWarnings = 0

foreach ($file in $files) {
    $fileName = [System.IO.Path]::GetFileName($file)
    $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
    $itemMatches = $itemRegex.Matches($text)

    $fileTranslated = 0
    $fileErrors = 0
    $fileWarnings = 0

    foreach ($m in $itemMatches) {
        $id = $m.Groups['id'].Value
        $cn = $m.Groups['cn'].Value
        $en = $m.Groups['en'].Value
        $ru = $m.Groups['ru'].Value

        $totalChecked++
        if ([string]::IsNullOrEmpty($ru)) { continue }

        $fileTranslated++
        $totalTranslated++

        # 1. Check UMG RichText tags
        $refText = if (-not [string]::IsNullOrEmpty($cn)) { $cn } else { $en }
        $refTags = $tagRegex.Matches($refText) | ForEach-Object { $_.Groups[1].Value }
        $ruTags = $tagRegex.Matches($ru) | ForEach-Object { $_.Groups[1].Value }

        foreach ($rt in $refTags) {
            if ($ruTags -notcontains $rt) {
                Write-Host "  [ERR $fileName ID:$id] Missing or broken tag <$rt> in Russian translation!" -ForegroundColor Red
                $fileErrors++
            }
        }

        # Check closing tags </>
        $refCloseCount = $closeTagRegex.Matches($refText).Count
        $ruCloseCount = $closeTagRegex.Matches($ru).Count
        if ($refCloseCount -ne $ruCloseCount) {
            Write-Host "  [WARN $fileName ID:$id] Closing tag count mismatch: ref=$refCloseCount, ru=$ruCloseCount" -ForegroundColor Yellow
            $fileWarnings++
        }

        # 2. Check format specifiers %s, %d, etc.
        $refSpecs = $specRegex.Matches($refText) | ForEach-Object { $_.Value }
        $ruSpecs = $specRegex.Matches($ru) | ForEach-Object { $_.Value }

        if ($refSpecs.Count -ne $ruSpecs.Count) {
            Write-Host "  [ERR $fileName ID:$id] Format specifier count mismatch (ref: $($refSpecs.Count), ru: $($ruSpecs.Count))!" -ForegroundColor Red
            Write-Host "       Ref: $refText" -ForegroundColor Gray
            Write-Host "       RU:  $ru" -ForegroundColor Gray
            $fileErrors++
        }

        # 3. Check puzzle tokens #CanMove_...#
        $refPuzzles = $puzzleRegex.Matches($refText) | ForEach-Object { $_.Value }
        $ruPuzzles = $puzzleRegex.Matches($ru) | ForEach-Object { $_.Value }
        if ($refPuzzles.Count -ne $ruPuzzles.Count) {
            Write-Host "  [ERR $fileName ID:$id] Broken puzzle marker #CanMove#!" -ForegroundColor Red
            $fileErrors++
        }

        # 4. Check inline image tags <img .../> and <Img .../>
        $refImgs = $imgTagRegex.Matches($refText) | ForEach-Object { $_.Value }
        $ruImgs = $imgTagRegex.Matches($ru) | ForEach-Object { $_.Value }
        if ($refImgs.Count -ne $ruImgs.Count) {
            Write-Host "  [ERR $fileName ID:$id] Inline image tag count mismatch (ref: $($refImgs.Count), ru: $($ruImgs.Count))! Do not replace images with text!" -ForegroundColor Red
            $fileErrors++
        } else {
            for ($idx = 0; $idx -lt $refImgs.Count; $idx++) {
                if ($refImgs[$idx] -ne $ruImgs[$idx]) {
                    Write-Host "  [ERR $fileName ID:$id] Inline image tag modified! Expected '$($refImgs[$idx])', found '$($ruImgs[$idx])'. Do not translate image IDs or attributes!" -ForegroundColor Red
                    $fileErrors++
                }
            }
        }

        # 5. Check empty English reference (BakedText collision protection)
        if ([string]::IsNullOrWhiteSpace($en) -and -not [string]::IsNullOrWhiteSpace($ru)) {
            Write-Host "  [WARN $fileName ID:$id] Text translated where ref_en is empty! May cause text overlay on BakedText images." -ForegroundColor Yellow
            $fileWarnings++
        }

        # 6. Check technical asset paths and engine logs
        $pathRegex = [System.Text.RegularExpressions.Regex]::new('(?:Texture2D''[^'']+''|/Game/[^\s''"]+)', [System.Text.RegularExpressions.RegexOptions]::Compiled)
        $refPaths = $pathRegex.Matches($refText) | ForEach-Object { $_.Value }
        foreach ($p in $refPaths) {
            if (-not $ru.Contains($p)) {
                Write-Host "  [ERR $fileName ID:$id] Technical asset path '$p' was modified or missing in Russian translation!" -ForegroundColor Red
                $fileErrors++
            }
        }
        if ($refText -match '^\[UIFrame\s*:' -and $cyrillicRegex.IsMatch($ru)) {
            Write-Host "  [ERR $fileName ID:$id] Internal engine diagnostic log should not be translated!" -ForegroundColor Red
            $fileErrors++
        }
    }

    $statusColor = if ($fileErrors -gt 0) { "Red" } elseif ($fileWarnings -gt 0) { "Yellow" } else { "Green" }
    Write-Host ("{0,-16} : {1,5} total, {2,5} translated, {3,3} errors, {4,3} warnings" -f $fileName, $itemMatches.Count, $fileTranslated, $fileErrors, $fileWarnings) -ForegroundColor $statusColor
    $totalErrors += $fileErrors
    $totalWarnings += $fileWarnings
}

Write-Host "`nTotal checked: $totalChecked lines (translated: $totalTranslated)"
if ($totalErrors -eq 0) {
    Write-Host "[SUCCESS] All translated lines are valid and safe for UE5 engine!" -ForegroundColor Green
} else {
    Write-Host "[FAILURE] Found $totalErrors critical error(s). Please fix before compiling!" -ForegroundColor Red
}
