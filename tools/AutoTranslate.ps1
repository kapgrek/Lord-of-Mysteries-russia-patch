# AutoTranslate.ps1 - Machine translation of batches via Google Translate or DeepL Free API
# Usage examples:
#   .\AutoTranslate.ps1 -Batch 5 -Count 200
#   .\AutoTranslate.ps1 -Batch 5 -Count 500 -BatchSize 30
#   .\AutoTranslate.ps1 -Batch 5 -Count 200 -Engine DeepL -DeepLKey "your-key-here:fx"
#   .\AutoTranslate.ps1 -Batch 5 -Count 200 -From en
#   .\AutoTranslate.ps1 -Batch 5 -Count 50 -DryRun
#   .\AutoTranslate.ps1 -Batch 5 -Count 500 -NoVerify   # skip post-run check (verify manually later)
param(
    [Parameter(Mandatory=$true)]
    [int]$Batch,

    [int]$Count     = 500,          # Strings to process per run
    [int]$Skip      = 0,            # Skip N untranslated strings (for resuming)
    [int]$BatchSize = 30,           # Number of strings per HTTP request (batch optimization)

    [ValidateSet('Google','DeepL')]
    [string]$Engine = 'Google',     # Translation engine

    [string]$DeepLKey = '',         # Required for -Engine DeepL

    [ValidateSet('cn','en')]
    [string]$From = 'cn',           # Source language: cn=source_cn, en=ref_en

    [int]$DelayMs   = 1200,         # Delay between batch requests (ms) - rate limit protection
    [switch]$DryRun,                # Show translations without saving
    [switch]$NoVerify               # Skip VerifyBatch.ps1 at the end
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$batchesDir = Join-Path $PSScriptRoot "..\source\translation_batches"

# ─── CONTEXT DETECTION (mirrors BatchHelper.ps1) ───────────────────────────────
function Get-StringContext([string]$cn, [string]$en) {
    if ($en -match '^\s*$' -and -not [string]::IsNullOrWhiteSpace($cn)) { return 'BakedText/KeepEmpty' }
    if ($cn -match '^\[UIFrame')                                         { return 'EngineLog/DoNotTranslate' }
    if ($cn -match "Texture2D'|/Game/|Atlas_|\.uasset")                  { return 'AssetPath/DoNotTranslate' }
    if ($cn -match '#CanMove')                                           { return 'LetterPuzzle/KeepMarkers' }
    if ($cn -match '%Y.*%m.*%d')                                         { return 'DateTimeFormat' }
    if ($cn -match '<Assistant_Title')                                   { return 'Achievement/QuestTitle' }
    if ($cn -match '<HyperLink')                                         { return 'SkillLink' }
    if ($cn -match '<DecH')                                              { return 'ItemCraftLore' }
    if ($cn -match '<P_Heart')                                           { return 'DialogueEmotion' }
    if ($cn -match '<[iI]mg\s')                                          { return 'InlineIcon' }
    if ($cn.StartsWith([char]0x3010) -and $cn.Contains([char]0x3011))   { return 'ActionMarker' }
    if ($cn -match '^[0-9,\.\s;:-]+$')                                  { return 'TechnicalCoord/Number' }
    if ($cn.EndsWith(':') -or $cn.EndsWith([char]0xFF1A))               { return 'Label' }
    return 'General'
}

# ─── TAG / PLACEHOLDER PROTECTION ──────────────────────────────────────────────
# Replaces UMG tags, %s/%d/{0}, and literal newlines with __T0__, __T1__...
# Returns hashtable: @{ Clean = "..."; Tokens = [List] }
function Protect-Tags([string]$text) {
    $tokens  = [System.Collections.Generic.List[string]]::new()
    # Order matters: longer patterns first. Newline must be protected too.
    $pattern = [System.Text.RegularExpressions.Regex]::new(
        '<[^<>]{0,120}>|#CanMove_[^#]+#|%[-+0-9\.]*[sdfeEgGcxX]|%[sdif%]|\{[0-9]+\}|\n',
        [System.Text.RegularExpressions.RegexOptions]::None
    )
    $matches = $pattern.Matches($text)

    $sb     = [System.Text.StringBuilder]::new($text)
    $offset = 0
    for ($i = 0; $i -lt $matches.Count; $i++) {
        $m     = $matches[$i]
        $token = "__T${i}__"
        $tokens.Add($m.Value) | Out-Null
        $pos = $m.Index + $offset
        $sb.Remove($pos, $m.Length)  | Out-Null
        $sb.Insert($pos, $token)     | Out-Null
        $offset += $token.Length - $m.Length
    }
    return @{ Clean = $sb.ToString(); Tokens = $tokens }
}

function Restore-Tags([string]$text, [System.Collections.Generic.List[string]]$tokens) {
    $result = $text
    for ($i = $tokens.Count - 1; $i -ge 0; $i--) {
        $token = $tokens[$i]
        $exactKey = "__T${i}__"
        if ($result.Contains($exactKey)) {
            $result = $result.Replace($exactKey, $token)
        } else {
            $digitsPattern = ($i.ToString().ToCharArray() | ForEach-Object { [System.Text.RegularExpressions.Regex]::Escape($_) }) -join '\s*'
            $rxToken = [System.Text.RegularExpressions.Regex]::new("(?:_{1,2}\s*[Tt\u0422\u0442]|(?<![\w\u0410-\u044f])[Tt\u0422\u0442])\s*${digitsPattern}\s*_{0,2}(?!\d)")
            if ($rxToken.IsMatch($result)) {
                $result = $rxToken.Replace($result, [System.Text.RegularExpressions.MatchEvaluator]{ return $token }, 1)
            }
        }
    }
    return $result
}

# ─── TRANSLATION ENGINES ────────────────────────────────────────────────────────
function Invoke-GoogleTranslateMobile([string]$combinedText, [string]$srcLang) {
    $encoded = [System.Uri]::EscapeDataString($combinedText)
    $url = "https://translate.google.com/m?sl=$srcLang&tl=ru&q=$encoded"
    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }
    $resp = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 25
    $rx = [System.Text.RegularExpressions.Regex]::new('class="result-container">(?<res>[\s\S]*?)<\/div>')
    $m = $rx.Match($resp.Content)
    if ($m.Success) {
        return [System.Net.WebUtility]::HtmlDecode($m.Groups['res'].Value)
    }
    throw "Google Translate result-container not found"
}

function Invoke-GoogleTranslateSingle([string]$text, [string]$srcLang, [int]$maxRetries = 3) {
    $attempt = 0
    while ($attempt -le $maxRetries) {
        try {
            return Invoke-GoogleTranslateMobile -combinedText $text -srcLang $srcLang
        } catch {
            # Try API fallback
            try {
                $encoded = [System.Uri]::EscapeDataString($text)
                $apiUrl = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$srcLang&tl=ru&dt=t&q=$encoded"
                $resp = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 15 -UseBasicParsing
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($seg in $resp[0]) {
                    if ($null -ne $seg[0] -and $seg[0] -ne '') { $parts.Add([string]$seg[0]) | Out-Null }
                }
                return ($parts -join '')
            } catch {}
        }
        $attempt++
        if ($attempt -gt $maxRetries) {
            throw "Google Translate error: all endpoints failed"
        }
        $backoff = $attempt * 3
        Write-Host "    [Google Retry] Backing off for ${backoff}s before retry $attempt/$maxRetries..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds $backoff
    }
}

function Invoke-GoogleTranslateBatch([string[]]$texts, [string]$srcLang, [int]$maxRetries = 3) {
    if ($texts.Length -eq 0) { return @() }
    if ($texts.Length -eq 1) {
        $single = Invoke-GoogleTranslateSingle -text $texts[0] -srcLang $srcLang -maxRetries $maxRetries
        return @($single)
    }

    # Build batch text with indexed delimiters
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $texts.Length; $i++) {
        if ($i -gt 0) {
            [void]$sb.Append("`n`n___IDX_${i}___`n`n")
        }
        [void]$sb.Append($texts[$i])
    }
    $combined = $sb.ToString()

    $attempt = 0
    $fullText = $null
    while ($attempt -le $maxRetries) {
        try {
            $fullText = Invoke-GoogleTranslateMobile -combinedText $combined -srcLang $srcLang
            if ($null -ne $fullText) { break }
        } catch {
            # Try API fallback
            try {
                $encoded = [System.Uri]::EscapeDataString($combined)
                $apiUrl = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$srcLang&tl=ru&dt=t&q=$encoded"
                $resp = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 20 -UseBasicParsing
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($seg in $resp[0]) {
                    if ($null -ne $seg[0] -and $seg[0] -ne '') { $parts.Add([string]$seg[0]) | Out-Null }
                }
                $fullText = ($parts -join '')
                break
            } catch {}
        }

        $attempt++
        if ($attempt -gt $maxRetries) {
            Write-Host "    [Batch Failed] Fallback to single-item translation for this chunk..." -ForegroundColor DarkYellow
            $fallbackResults = [System.Collections.Generic.List[string]]::new()
            foreach ($t in $texts) {
                $res = Invoke-GoogleTranslateSingle -text $t -srcLang $srcLang
                $fallbackResults.Add($res) | Out-Null
            }
            return $fallbackResults.ToArray()
        }
        $backoff = $attempt * 3
        Write-Host "    [Google Retry] Batch failed. Backing off for ${backoff}s before retry $attempt/$maxRetries..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds $backoff
    }

    # Split by delimiter (non-capturing regex returns segments only)
    $splits = [regex]::Split($fullText, '(?:\b|_|\s)*___IDX_\d+___(?:\b|_|\s)*')
    if ($splits.Count -ne $texts.Length) {
        Write-Host "    [Warning] Split count mismatch (got $($splits.Count), expected $($texts.Length)). Fallback to single items..." -ForegroundColor DarkYellow
        $fallbackResults = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $texts) {
            $res = Invoke-GoogleTranslateSingle -text $t -srcLang $srcLang
            $fallbackResults.Add($res) | Out-Null
        }
        return $fallbackResults.ToArray()
    }

    $results = [System.Collections.Generic.List[string]]::new()
    for ($k = 0; $k -lt $splits.Count; $k++) {
        $seg = $splits[$k].Trim()
        $seg = [regex]::Replace($seg, '^_\s+', '')
        $seg = [regex]::Replace($seg, '\s+_$', '')
        if ($seg.StartsWith('_') -and -not $texts[$k].StartsWith('_')) {
            $seg = $seg.TrimStart('_').Trim()
        }
        if ($seg.EndsWith('_') -and -not $texts[$k].EndsWith('_')) {
            $seg = $seg.TrimEnd('_').Trim()
        }
        $results.Add($seg) | Out-Null
    }
    return $results.ToArray()
}

function Invoke-DeepLTranslateBatch([string[]]$texts, [string]$srcLang, [string]$apiKey) {
    if ($texts.Length -eq 0) { return @() }
    $url = "https://api-free.deepl.com/v2/translate"
    $bodyParts = [System.Collections.Generic.List[string]]::new()
    $bodyParts.Add("source_lang=$($srcLang.ToUpper())") | Out-Null
    $bodyParts.Add("target_lang=RU") | Out-Null
    foreach ($t in $texts) {
        $bodyParts.Add("text=$([System.Uri]::EscapeDataString($t))") | Out-Null
    }
    $body = $bodyParts -join '&'
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Post -Body $body `
            -Headers @{ 'Authorization' = "DeepL-Auth-Key $apiKey"; 'Content-Type' = 'application/x-www-form-urlencoded' } `
            -TimeoutSec 30 -UseBasicParsing
        $out = [System.Collections.Generic.List[string]]::new()
        foreach ($tr in $resp.translations) {
            $out.Add([string]$tr.text) | Out-Null
        }
        return $out.ToArray()
    } catch {
        throw "DeepL error: $($_.Exception.Message)"
    }
}

function Flush-BatchItems([string]$file, [System.Collections.Generic.Dictionary[string,string]]$res) {
    if ($res.Count -eq 0) { return 0 }
    $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
    $rx = [System.Text.RegularExpressions.Regex]::new(
        '\{\s*"id"\s*:\s*"(?<id>[^"]+)"\s*,\s*"source_cn"\s*:\s*"(?<cn>(?:\\.|[^"\\])*)"\s*,\s*"ref_en"\s*:\s*"(?<en>(?:\\.|[^"\\])*)"\s*,\s*"target_ru"\s*:\s*"(?<ru>(?:\\.|[^"\\])*)"\s*\}',
        [System.Text.RegularExpressions.RegexOptions]::Compiled
    )
    $count = [int[]]::new(1)
    $newText = $rx.Replace($text, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $id = $m.Groups[1].Value
        if ($res.ContainsKey($id)) {
            $val = $res[$id]
            $valClean = $val.Replace("`r`n", "`n").Replace("`r", "`n")
            $bs = [char]92
            $escaped = $valClean.Replace("$bs", "$bs$bs").Replace('"', '\"').Replace("`n", '\n').Replace("`t", '\t')
            $count[0]++
            $prefix = $m.Value.Substring(0, $m.Groups[4].Index - $m.Index)
            $suffix = $m.Value.Substring($m.Groups[4].Index - $m.Index + $m.Groups[4].Length)
            return $prefix + $escaped + $suffix
        }
        return $m.Value
    })
    [System.IO.File]::WriteAllText($file, $newText, [System.Text.Encoding]::UTF8)
    return $count[0]
}

# ─── VALIDATION ─────────────────────────────────────────────────────────────────
if ($Engine -eq 'DeepL' -and [string]::IsNullOrWhiteSpace($DeepLKey)) {
    Write-Error "DeepL engine requires -DeepLKey <your_free_api_key>  (get one free at https://www.deepl.com/pro#developer)"
    exit 1
}

if ($BatchSize -lt 1) {
    $BatchSize = 1
}

$batchNumStr = $Batch.ToString("D3")
$batchFile   = Join-Path $batchesDir "batch_$batchNumStr.json"
if (-not (Test-Path $batchFile)) {
    Write-Error "Batch file not found: $batchFile"
    exit 1
}

$srcLangGoogle = if ($From -eq 'cn') { 'zh-CN' } else { 'en' }
$srcLangDeepL  = if ($From -eq 'cn') { 'ZH' }    else { 'EN' }

# ─── HEADER ─────────────────────────────────────────────────────────────────────
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  AutoTranslate | Batch $batchNumStr | Engine: $Engine | Source: $From" -ForegroundColor Cyan
Write-Host "  Count: $Count | Skip: $Skip | BatchSize: $BatchSize | Delay: ${DelayMs}ms$(if ($DryRun) { ' | DRY RUN' })" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# ─── LOAD AND PARSE BATCH ───────────────────────────────────────────────────────
$batchText = [System.IO.File]::ReadAllText($batchFile, [System.Text.Encoding]::UTF8)
$itemRegex = [System.Text.RegularExpressions.Regex]::new(
    '\{\s*"id"\s*:\s*"(?<id>[^"]+)"\s*,\s*"source_cn"\s*:\s*"(?<cn>(?:\\.|[^"\\])*)"\s*,\s*"ref_en"\s*:\s*"(?<en>(?:\\.|[^"\\])*)"\s*,\s*"target_ru"\s*:\s*"(?<ru>(?:\\.|[^"\\])*)"\s*\}',
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)

$untranslated = [System.Collections.Generic.List[object]]::new()
foreach ($m in $itemRegex.Matches($batchText)) {
    if ([string]::IsNullOrWhiteSpace($m.Groups['ru'].Value)) {
        $rawCn  = $m.Groups['cn'].Value
        $rawEn  = $m.Groups['en'].Value
        $cnClean = $rawCn.Replace('\\n', "`n").Replace('\\r', "`r").Replace('\\t', "`t").Replace('\"', '"').Replace('\\', '\')
        $enClean = $rawEn.Replace('\\n', "`n").Replace('\\r', "`r").Replace('\\t', "`t").Replace('\"', '"').Replace('\\', '\')
        $untranslated.Add([PSCustomObject]@{
            id  = $m.Groups['id'].Value
            cn  = $cnClean
            en  = $enClean
            ctx = Get-StringContext -cn $cnClean -en $enClean
        }) | Out-Null
    }
}

$total = $untranslated.Count
Write-Host "Untranslated in batch $batchNumStr`: $total strings." -ForegroundColor Yellow

if ($total -eq 0) {
    Write-Host "Nothing to translate - batch is complete!" -ForegroundColor Green
    exit 0
}

# Apply Skip and Count
$startFrom  = [Math]::Min($Skip, $total)
$takeCount  = [Math]::Min($Count, $total - $startFrom)
$available  = $untranslated.GetRange($startFrom, $takeCount)
Write-Host "Processing $takeCount strings (offset $startFrom) in batches of up to $BatchSize." -ForegroundColor Cyan
Write-Host ""

# ─── TRANSLATE LOOP (BATCHED) ───────────────────────────────────────────────────
$results      = [System.Collections.Generic.Dictionary[string,string]]::new()
$pendingSaves = [System.Collections.Generic.Dictionary[string,string]]::new()
$translated   = 0
$skipped      = 0
$errors       = 0
$totalSaved   = 0
$consecutiveErrors    = 0
$maxConsecutiveErrors = 5

$cursor = 0
$batchIteration = 0

while ($cursor -lt $available.Count) {
    # Collect items for this request: skip DoNotTranslate/empty immediately
    $currentChunk = [System.Collections.Generic.List[object]]::new()
    
    while ($cursor -lt $available.Count -and $currentChunk.Count -lt $BatchSize) {
        $item = $available[$cursor]
        $cursor++

        # DoNotTranslate: copy ref_en verbatim
        if ($item.ctx -like '*DoNotTranslate*') {
            $results[$item.id] = $item.en
            $pendingSaves[$item.id] = $item.en
            $skipped++
            continue
        }

        # BakedText/KeepEmpty: leave empty to avoid UI overlay
        if ($item.ctx -eq 'BakedText/KeepEmpty') {
            $results[$item.id] = ''
            $pendingSaves[$item.id] = ''
            $skipped++
            continue
        }

        # Empty source
        $srcText = if ($From -eq 'en') { $item.en } else { $item.cn }
        if ([string]::IsNullOrWhiteSpace($srcText)) {
            $results[$item.id] = ''
            $pendingSaves[$item.id] = ''
            $skipped++
            continue
        }

        # Needs translation: protect tags
        $prot = Protect-Tags -text $srcText
        $currentChunk.Add([PSCustomObject]@{
            id     = $item.id
            clean  = $prot.Clean
            tokens = $prot.Tokens
            raw    = $srcText
            ctx    = $item.ctx
        }) | Out-Null
    }

    if ($currentChunk.Count -gt 0) {
        $batchIteration++
        $chunkTexts = ($currentChunk | ForEach-Object { $_.clean })
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $translatedBatch = @()
            if ($Engine -eq 'Google') {
                $translatedBatch = Invoke-GoogleTranslateBatch -texts $chunkTexts -srcLang $srcLangGoogle
            } else {
                $translatedBatch = Invoke-DeepLTranslateBatch -texts $chunkTexts -srcLang $srcLangDeepL -apiKey $DeepLKey
            }
            $sw.Stop()

            for ($k = 0; $k -lt $currentChunk.Count; $k++) {
                $cItem = $currentChunk[$k]
                $rawTr = if ($k -lt $translatedBatch.Length) { $translatedBatch[$k] } else { '' }
                $final = Restore-Tags -text $rawTr -tokens $cItem.tokens

                $results[$cItem.id] = $final
                $pendingSaves[$cItem.id] = $final
                $translated++
            }

            $consecutiveErrors = 0
            $firstPreview = $results[$currentChunk[0].id]
            if ($firstPreview.Length -gt 45) { $firstPreview = $firstPreview.Substring(0, 45) + '…' }
            Write-Host "  [Batch $batchIteration] Translated $($currentChunk.Count) items in $($sw.ElapsedMilliseconds)ms | First: '$firstPreview' (Progress: $translated/$takeCount)" -ForegroundColor Green

        } catch {
            $sw.Stop()
            $errors += $currentChunk.Count
            $consecutiveErrors++
            Write-Host "  [Batch $batchIteration] ERROR translating chunk of $($currentChunk.Count) items: $($_.Exception.Message)" -ForegroundColor Red
            if ($consecutiveErrors -ge $maxConsecutiveErrors) {
                Write-Host "`n[STOP] Encountered $maxConsecutiveErrors consecutive batch errors. Halting loop." -ForegroundColor Red
                break
            }
        }
    }

    # Auto-save after each chunk if there are pending saves
    if ($pendingSaves.Count -ge 30 -and -not $DryRun) {
        $savedChunk = Flush-BatchItems -file $batchFile -res $pendingSaves
        $totalSaved += $savedChunk
        $pendingSaves.Clear()
        Write-Host "    --> [AutoSave] Flushed $savedChunk strings to $batchFile (Total saved so far: $totalSaved)" -ForegroundColor Cyan
    }

    # Rate-limit delay between batch HTTP requests
    if ($currentChunk.Count -gt 0 -and $DelayMs -gt 0 -and $cursor -lt $available.Count) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

# ─── SUMMARY ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Translated: $translated  |  Skipped: $skipped  |  Errors: $errors" -ForegroundColor $(if ($errors -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "=================================================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "[DryRun] Changes NOT saved." -ForegroundColor Yellow
    exit 0
}

# ─── FLUSH REMAINING STRINGS ────────────────────────────────────────────────────
if ($pendingSaves.Count -gt 0) {
    $savedChunk = Flush-BatchItems -file $batchFile -res $pendingSaves
    $totalSaved += $savedChunk
    $pendingSaves.Clear()
    Write-Host "[OK] Saved final $savedChunk strings to batch_$batchNumStr.json (Total saved in run: $totalSaved)" -ForegroundColor Green
} elseif ($totalSaved -gt 0) {
    Write-Host "[OK] Total $totalSaved strings saved to batch_$batchNumStr.json" -ForegroundColor Green
} else {
    Write-Host "No results to save." -ForegroundColor Yellow
    exit 0
}

# ─── POST-RUN VERIFICATION ───────────────────────────────────────────────────────
if (-not $NoVerify) {
    $verifyScript = Join-Path $PSScriptRoot "VerifyBatch.ps1"
    if (Test-Path $verifyScript) {
        Write-Host ""
        Write-Host "--- Running VerifyBatch.ps1 for batch $batchNumStr ---" -ForegroundColor Cyan
        & $verifyScript -Batch $Batch
    }
}
