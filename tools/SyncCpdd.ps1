# SyncCpdd.ps1 - compare a CPDD English patch release with our base and patch_payload, report, apply.
#
#   tools/SyncCpdd.ps1 -Tag v2.6.4 [-SkipDownload]            # report only (writes only under reference/)
#   tools/SyncCpdd.ps1 -Tag v2.6.4 -Components stringdb,state,shards -Apply
#
# Base = vendor/cpdd/BASE.json (the CPDD release patch_payload is built on). Releases live in
# reference/cpdd/<tag>/ (release.json, lom-english-patch-data.zip, unpacked/). Report:
# reference/cpdd/<tag>/SYNC_REPORT.md. Exit code: 0 no upstream changes, 1 changes, 2 conflicts/unknown files.
# Never touches the game folder.
param(
    [string]$Tag = 'latest',
    [string[]]$Components = @('all'),
    [switch]$Apply,
    [switch]$SkipDownload,
    [string]$Repo = 'Lani27/lord-of-mysteries-english-patch',
    [string]$BatchName = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$utf8 = New-Object System.Text.UTF8Encoding $false
$payloadDir = Join-Path $root 'patch_payload'
$vendorDir = Join-Path $root 'vendor\cpdd'
$refRoot = Join-Path $root 'reference\cpdd'
$batchesDir = Join-Path $root 'source\translation_batches'

$verbatimComponents = @('bridge', 'loader', 'stringdb', 'sourceindex', 'bakedtext', 'dps', 'chat', 'engineini', 'schedule', 'widgets')
$allComponents = $verbatimComponents + @('runtime', 'state', 'shards', 'gamestate')
if ($Components -contains 'all') { $Components = $allComponents }
$Components = @($Components | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
foreach ($c in $Components) { if ($allComponents -notcontains $c) { throw "Unknown component '$c'. Known: $($allComponents -join ', ')" } }

function Write-Utf8Lf([string]$path, [string]$text) {
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"), $utf8)
}

function Get-Sha([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

# ---------------------------------------------------------------- releases
function Get-CpddRelease([string]$tag) {
    $dir = Join-Path $refRoot $tag
    $zip = Join-Path $dir 'lom-english-patch-data.zip'
    $rel = Join-Path $dir 'release.json'
    if (-not (Test-Path $zip) -or -not (Test-Path $rel)) {
        if ($SkipDownload) { throw "CPDD $tag is not in $dir and -SkipDownload is set" }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Downloading CPDD $tag release assets into $dir ..." -ForegroundColor Cyan
        & gh release download $tag -R $Repo -D $dir -p 'lom-english-patch-data.zip' -p 'release.json' -p 'release.json.sig' -p 'SHA256SUMS.txt' --clobber
        if ($LASTEXITCODE -ne 0) { throw "gh release download failed for $tag" }
    }
    $release = [IO.File]::ReadAllText($rel, $utf8) | ConvertFrom-Json
    $zipSha = Get-Sha $zip
    if ($release.payload.sha256 -and $zipSha -ne $release.payload.sha256) { throw "$tag payload sha256 mismatch: $zipSha vs release.json $($release.payload.sha256)" }
    $sums = Join-Path $dir 'SHA256SUMS.txt'
    if (Test-Path $sums) {
        $line = Get-Content $sums | Where-Object { $_ -match 'lom-english-patch-data\.zip$' } | Select-Object -First 1
        if ($line -and ($line -split '\s+')[0] -ne $zipSha) { throw "$tag zip sha256 does not match SHA256SUMS.txt" }
    }
    $unpacked = Join-Path $dir 'unpacked'
    if (-not (Test-Path (Join-Path $unpacked 'payload'))) {
        Write-Host "Extracting $zip ..." -ForegroundColor Cyan
        Expand-Archive -LiteralPath $zip -DestinationPath $unpacked -Force
    }
    [pscustomobject]@{ Tag = $tag; Dir = $dir; Release = $release; Game = (Join-Path $unpacked 'payload\bridge\game'); Block = (Join-Path $unpacked 'payload\bridge\LaunchInstance.native-bridge.padded.oodle') }
}

# Relative path (as in patch_payload, '/'-separated) -> absolute path inside a release / patch_payload.
$blockRel = 'bridge/LaunchInstance.native-bridge.padded.oodle'
function Get-FileMap($gameRoot, $blockPath) {
    $map = @{}
    $base = (Resolve-Path $gameRoot).Path
    Get-ChildItem -LiteralPath $base -Recurse -File | ForEach-Object {
        $map[$_.FullName.Substring($base.Length + 1).Replace('\', '/')] = $_.FullName
    }
    if ($blockPath -and (Test-Path $blockPath)) { $map[$blockRel] = $blockPath }
    $map
}

function Get-Component([string]$rel) {
    $name = [IO.Path]::GetFileName($rel)
    if ($rel -eq $blockRel -or $rel -like 'Binaries/*') { return 'bridge' }
    if ($rel -eq 'Saved/Mods/manifest.lua' -or $rel -eq 'Saved/Mods/translation-overrides.lua') { return 'loader' }
    if ($rel -eq 'Saved/Mods/bootstrap.lua') { return 'runtime' }
    if ($rel -eq 'Saved/Mods/translation-overrides.state.json') { return 'state' }
    if ($rel -like 'Saved/Mods/lua/cpdd_translation/*') { return 'stringdb' }
    if ($rel -like 'Saved/Mods/BakedText/*') { return 'bakedtext' }
    if ($rel -like 'Saved/Mods/ExternalDpsMeter/*') { return 'dps' }
    if ($rel -like 'Saved/Mods/lua/mods/cpdd_runtime_fixes/*') {
        if ($name -like 'RuntimeTextGemini_*') { return 'shards' }
        if ($name -like 'LanguageSourceIndex_*') { return 'sourceindex' }
        switch ($name) {
            'Init.lua' { return 'runtime' }
            'DpsMeter.lua' { return 'dps' }
            'DpsTelemetry.lua' { return 'dps' }
            'DesktopChat.lua' { return 'chat' }
            'EngineIniBridge.lua' { return 'engineini' }
            'ServerScheduleFix.lua' { return 'schedule' }
            'WidgetNameIndex.lua' { return 'widgets' }
        }
    }
    'unknown'
}

function Get-OursPath([string]$rel) { Join-Path $payloadDir ($rel.Replace('/', '\')) }

# ---------------------------------------------------------------- shards / batches
function Expand-LuaString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($ch -ne '\' -or $i + 1 -ge $s.Length) { [void]$sb.Append($ch); continue }
        $i++; $n = $s[$i]
        switch -CaseSensitive ($n) {
            'n' { [void]$sb.Append("`n") }
            't' { [void]$sb.Append("`t") }
            'r' { [void]$sb.Append("`r") }
            default {
                if ($n -match '\d') {
                    $digits = $s.Substring($i, [Math]::Min(3, $s.Length - $i)) -replace '\D.*$', ''
                    [void]$sb.Append([char][int]$digits); $i += $digits.Length - 1
                } else { [void]$sb.Append($n) }
            }
        }
    }
    $sb.ToString()
}

$shardLine = [regex]'^\s*\["((?:\\.|[^"\\])*)"\]\s*=\s*"((?:\\.|[^"\\])*)",?\s*$'
function Read-Shard([string]$path) {
    $d = @{}
    foreach ($line in [IO.File]::ReadAllLines($path, $utf8)) {
        $m = $shardLine.Match($line)
        if ($m.Success) { $d[(Expand-LuaString $m.Groups[1].Value)] = (Expand-LuaString $m.Groups[2].Value) }
    }
    $d
}

$batchItem = [regex]'\{\s*"id"\s*:\s*"(?<id>[^"]+)"\s*,\s*"source_cn"\s*:\s*"(?<cn>(?:\\.|[^"\\])*)"\s*,\s*"ref_en"\s*:\s*"(?<en>(?:\\.|[^"\\])*)"\s*,\s*"target_ru"\s*:\s*"(?<ru>(?:\\.|[^"\\])*)"\s*\}'
function Read-Batches {
    $cn = @{}; $maxId = 0
    foreach ($f in Get-ChildItem $batchesDir -Filter 'batch_*.json' | Sort-Object Name) {
        foreach ($m in $batchItem.Matches([IO.File]::ReadAllText($f.FullName, $utf8))) {
            $key = [regex]::Unescape($m.Groups['cn'].Value)
            if (-not $cn.ContainsKey($key)) { $cn[$key] = [pscustomobject]@{ File = $f.Name; Id = $m.Groups['id'].Value; En = [regex]::Unescape($m.Groups['en'].Value) } }
            $idNum = 0
            if ([int]::TryParse($m.Groups['id'].Value, [ref]$idNum) -and $idNum -gt $maxId) { $maxId = $idNum }
        }
    }
    [pscustomobject]@{ Cn = $cn; MaxId = $maxId }
}

function ConvertTo-JsonString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default { if ([int]$ch -lt 0x20) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
        }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}

function Write-BatchFile([string]$path, $items) {
    $parts = foreach ($it in $items) {
        "  {`n    `"id`": $(ConvertTo-JsonString $it.id),`n    `"source_cn`": $(ConvertTo-JsonString $it.source_cn),`n    `"ref_en`": $(ConvertTo-JsonString $it.ref_en),`n    `"target_ru`": $(ConvertTo-JsonString $it.target_ru)`n  }"
    }
    Write-Utf8Lf $path ("[`n" + ($parts -join ",`n") + "`n]`n")
}

# ---------------------------------------------------------------- state.json
function Convert-StateToRussian([string]$text) {
    $text = [regex]::Replace($text, '("(?:translationReleaseId|installerReleaseId|signedDataReleaseId)"\s*:\s*")c7-en-', '${1}c7-ru-')
    [regex]::Replace($text, '("displayVersion"\s*:\s*")([0-9][0-9.]*)[^"]*"', '${1}${2} Russian localization update (AbsoluteRU)"')
}

# ---------------------------------------------------------------- compare
$baseInfo = [IO.File]::ReadAllText((Join-Path $vendorDir 'BASE.json'), $utf8) | ConvertFrom-Json
if ($Tag -eq 'latest') {
    $Tag = (& gh release view -R $Repo --json tagName --jq '.tagName').Trim()
    if (-not $Tag) { throw 'Cannot resolve the latest CPDD release tag' }
}
Write-Host "=== SyncCpdd: base $($baseInfo.tag) -> $Tag ===" -ForegroundColor Cyan
$vendorBase = Join-Path $vendorDir $baseInfo.tag
if ((Get-Sha (Join-Path $vendorBase 'release.json')) -ne $baseInfo.release_json_sha256) { throw "vendor/cpdd/$($baseInfo.tag)/release.json does not match BASE.json" }

$base = Get-CpddRelease $baseInfo.tag
$theirs = Get-CpddRelease $Tag
$baseMap = Get-FileMap $base.Game $base.Block
$theirsMap = Get-FileMap $theirs.Game $theirs.Block

$rows = New-Object System.Collections.Generic.List[object]
foreach ($rel in (@($baseMap.Keys) + @($theirsMap.Keys) | Sort-Object -Unique)) {
    $comp = Get-Component $rel
    $bSha = if ($baseMap.ContainsKey($rel)) { Get-Sha $baseMap[$rel] } else { $null }
    $tSha = if ($theirsMap.ContainsKey($rel)) { Get-Sha $theirsMap[$rel] } else { $null }
    $oSha = if ($comp -eq 'shards') { $null } else { Get-Sha (Get-OursPath $rel) }
    $upstream = if ($bSha -eq $tSha) { 'same' } elseif (-not $bSha) { 'added' } elseif (-not $tSha) { 'removed' } else { 'changed' }
    $note = ''
    if ($comp -eq 'unknown') { $note = 'no sync rule for this path' }
    elseif ($verbatimComponents -contains $comp -and $bSha -and $oSha -ne $bSha -and $oSha -ne $tSha) { $note = 'ours differs from CPDD base (local edit of a verbatim file)' }
    $rows.Add([pscustomobject]@{ Rel = $rel; Component = $comp; Upstream = $upstream; Base = $bSha; Theirs = $tSha; Ours = $oSha; Note = $note })
}

# merge3 dry run for the runtime files
$merge = @{}
foreach ($r in $rows | Where-Object { $_.Component -eq 'runtime' -and $_.Upstream -ne 'same' }) {
    $vendorFile = Join-Path $vendorBase ([IO.Path]::GetFileName($r.Rel))
    if ((Get-Sha $vendorFile) -ne $r.Base) { $r.Note = 'vendor base copy does not match CPDD base'; continue }
    $out = Join-Path $theirs.Dir ('sync\' + [IO.Path]::GetFileName($r.Rel) + '.merged')
    New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
    $merged = & git merge-file -p -L ours -L "cpdd-$($baseInfo.tag)" -L "cpdd-$Tag" (Get-OursPath $r.Rel) $vendorFile $theirsMap[$r.Rel]
    $conflicts = $LASTEXITCODE
    [IO.File]::WriteAllText($out, (($merged -join "`n") + "`n"), $utf8)
    $merge[$r.Rel] = [pscustomobject]@{ Conflicts = $conflicts; Output = $out }
    if ($conflicts -ne 0) { $r.Note = "merge conflicts: $conflicts (see $out)" }
}

# shard diff (CN -> EN) between base and theirs
$shardAdded = New-Object System.Collections.Generic.List[object]
$shardChanged = New-Object System.Collections.Generic.List[object]
$shardRemoved = New-Object System.Collections.Generic.List[object]
foreach ($r in $rows | Where-Object { $_.Component -eq 'shards' -and $_.Upstream -ne 'same' }) {
    $b = if ($r.Base) { Read-Shard $baseMap[$r.Rel] } else { @{} }
    $t = if ($r.Theirs) { Read-Shard $theirsMap[$r.Rel] } else { @{} }
    foreach ($k in $t.Keys) {
        if (-not $b.ContainsKey($k)) { $shardAdded.Add([pscustomobject]@{ Cn = $k; En = $t[$k] }) }
        elseif ($b[$k] -ne $t[$k]) { $shardChanged.Add([pscustomobject]@{ Cn = $k; OldEn = $b[$k]; En = $t[$k] }) }
    }
    foreach ($k in $b.Keys) { if (-not $t.ContainsKey($k)) { $shardRemoved.Add([pscustomobject]@{ Cn = $k; En = $b[$k] }) } }
}
$batches = $null
if ($shardAdded.Count + $shardChanged.Count + $shardRemoved.Count -gt 0) { $batches = Read-Batches }
$shardNew = @($shardAdded | Where-Object { -not $batches.Cn.ContainsKey($_.Cn) })

# release metadata
$metaKeys = @('supported_base_paks', 'minimum_patcher_version', 'bootstrap_protocol', 'patch_method')
$bridgeKeys = @('launch_block', 'combat_meter', 'loader_version', 'runtime_version', 'runtime_text_entries', 'source_index_entries')
$metaDiff = New-Object System.Collections.Generic.List[object]
foreach ($k in $metaKeys) {
    $x = $base.Release.$k | ConvertTo-Json -Compress -Depth 6; $y = $theirs.Release.$k | ConvertTo-Json -Compress -Depth 6
    if ($x -ne $y) { $metaDiff.Add([pscustomobject]@{ Key = $k; Base = $x; Theirs = $y }) }
}
foreach ($k in $bridgeKeys) {
    $x = $base.Release.external_bridge.$k | ConvertTo-Json -Compress -Depth 6; $y = $theirs.Release.external_bridge.$k | ConvertTo-Json -Compress -Depth 6
    if ($x -ne $y) { $metaDiff.Add([pscustomobject]@{ Key = "external_bridge.$k"; Base = $x; Theirs = $y }) }
}

# supported_game.json expected content (gamestate component)
function Get-SupportedGameJson($release, [string]$tag) {
    $lb = $release.external_bridge.launch_block
    $paks = @($release.supported_base_paks)
    $build = if ($paks.Count -gt 0 -and $paks[0].name -match '(\d+\.\d+\.\d+)\s*$') { $Matches[1] } else { '' }
    $pakLines = foreach ($p in $paks) { "    { `"name`": $(ConvertTo-JsonString $p.name), `"sha256`": `"$($p.sha256)`", `"size`": $($p.size) }" }
    @"
{
  "source": "CPDD $tag release.json",
  "game_build": "$build",
  "supported_base_paks": [
$($pakLines -join ",`n")
  ],
  "launch_block": {
    "pak_relative_path": "$($lb.pak_relative_path)",
    "offset": $($lb.offset),
    "size": $($lb.size),
    "clean_sha256": "$($lb.clean_sha256)",
    "installed_sha256": "$($lb.installed_sha256)",
    "installed_pak_sha256": "$($lb.installed_pak_sha256)",
    "installed_pak_size": $($lb.installed_pak_size)
  }
}
"@ -replace "`r`n", "`n"
}
$supportedPath = Join-Path $root 'installer\supported_game.json'
$supportedWanted = (Get-SupportedGameJson $theirs.Release $Tag) + "`n"
$supportedCurrent = if (Test-Path $supportedPath) { [IO.File]::ReadAllText($supportedPath, $utf8) } else { '' }
$gamestateChanged = ($supportedCurrent -replace '"source":[^\n]*', '') -ne ($supportedWanted -replace '"source":[^\n]*', '')

# ---------------------------------------------------------------- report
$changedRows = @($rows | Where-Object { $_.Upstream -ne 'same' -and $_.Component -ne 'shards' })
$problemRows = @($rows | Where-Object { $_.Note })
$byComp = $rows | Group-Object Component | Sort-Object Name
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# CPDD sync report: $($baseInfo.tag) -> $Tag")
[void]$md.AppendLine('')
[void]$md.AppendLine("Generated by tools/SyncCpdd.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Changelog $($Tag):")
foreach ($c in @($theirs.Release.changelog)) { [void]$md.AppendLine("- $c") }
[void]$md.AppendLine('')
[void]$md.AppendLine('| Component | Files | Upstream changed | Ours = base | Action |')
[void]$md.AppendLine('|---|---|---|---|---|')
foreach ($g in $byComp) {
    $ch = @($g.Group | Where-Object { $_.Upstream -ne 'same' }).Count
    $oursEq = if ($g.Name -eq 'shards') { 'n/a (generated)' } else { "$(@($g.Group | Where-Object { $_.Ours -eq $_.Base }).Count)/$($g.Count)" }
    $action = if ($ch -eq 0) { '-' } elseif ($g.Name -eq 'runtime') { 'merge3' } elseif ($g.Name -eq 'state') { 'regenerate (RU ids)' } elseif ($g.Name -eq 'shards') { 'new batch entries' } elseif ($g.Name -eq 'unknown') { 'STOP: add a rule' } else { 'copy verbatim' }
    [void]$md.AppendLine("| $($g.Name) | $($g.Count) | $ch | $oursEq | $action |")
}
[void]$md.AppendLine("| gamestate | installer/supported_game.json | $(if ($gamestateChanged) { 'yes' } else { 'no' }) | | $(if ($gamestateChanged) { 'regenerate' } else { '-' }) |")
[void]$md.AppendLine('')
if ($changedRows.Count) {
    [void]$md.AppendLine('## Changed files (without shards)')
    foreach ($r in $changedRows) { [void]$md.AppendLine("- ``$($r.Rel)`` [$($r.Component)] $($r.Upstream) $($r.Base) -> $($r.Theirs)") }
    [void]$md.AppendLine('')
}
if ($problemRows.Count) {
    [void]$md.AppendLine('## Conflicts and warnings')
    foreach ($r in $problemRows) { [void]$md.AppendLine("- ``$($r.Rel)`` [$($r.Component)]: $($r.Note)") }
    [void]$md.AppendLine('')
}
[void]$md.AppendLine("## Shards (CN -> EN)")
[void]$md.AppendLine("Added $($shardAdded.Count) (not in our batches: $($shardNew.Count)), changed EN $($shardChanged.Count), removed $($shardRemoved.Count).")
foreach ($s in $shardNew) { [void]$md.AppendLine("- NEW ``$($s.Cn)`` = ``$($s.En)``") }
foreach ($s in $shardChanged) { $where = if ($batches.Cn.ContainsKey($s.Cn)) { "$($batches.Cn[$s.Cn].File)#$($batches.Cn[$s.Cn].Id)" } else { 'not in batches' }; [void]$md.AppendLine("- CHANGED ($where) ``$($s.Cn)``: ``$($s.OldEn)`` -> ``$($s.En)``") }
foreach ($s in $shardRemoved) { [void]$md.AppendLine("- REMOVED ``$($s.Cn)``") }
[void]$md.AppendLine('')
[void]$md.AppendLine('## release.json metadata')
if ($metaDiff.Count -eq 0) { [void]$md.AppendLine('No changes in supported_base_paks, launch_block, combat_meter, loader/runtime versions.') }
foreach ($m in $metaDiff) { [void]$md.AppendLine("- ``$($m.Key)``: ``$($m.Base)`` -> ``$($m.Theirs)``") }
$reportPath = Join-Path $theirs.Dir 'SYNC_REPORT.md'
Write-Utf8Lf $reportPath $md.ToString()

$upstreamCount = $changedRows.Count + $shardAdded.Count + $shardChanged.Count + $shardRemoved.Count + $(if ($gamestateChanged) { 1 } else { 0 })
$hasProblems = @($rows | Where-Object { $_.Component -eq 'unknown' -or $_.Note -like 'merge conflicts*' -or $_.Note -like 'vendor*' }).Count -gt 0
Write-Host $md.ToString()
Write-Host "Report: $reportPath" -ForegroundColor Green

# ---------------------------------------------------------------- apply
if ($Apply) {
    Write-Host "`n=== Applying components: $($Components -join ', ') ===" -ForegroundColor Cyan
    $pending = New-Object System.Collections.Generic.List[string]
    foreach ($r in $rows | Where-Object { $_.Upstream -ne 'same' }) {
        if ($Components -notcontains $r.Component -or $r.Component -eq 'unknown') { if ($r.Component -ne 'shards') { $pending.Add($r.Rel) }; continue }
        $ours = Get-OursPath $r.Rel
        if ($verbatimComponents -contains $r.Component) {
            if ($r.Note) { $pending.Add($r.Rel); Write-Warning "Skipped $($r.Rel): $($r.Note)"; continue }
            if ($r.Upstream -eq 'removed') { Remove-Item -LiteralPath $ours -Force -ErrorAction SilentlyContinue; Write-Host "  deleted  $($r.Rel)" }
            else {
                New-Item -ItemType Directory -Path (Split-Path $ours) -Force | Out-Null
                Copy-Item -LiteralPath $theirsMap[$r.Rel] -Destination $ours -Force
                if ((Get-Sha $ours) -ne $r.Theirs) { throw "Copy verification failed for $($r.Rel)" }
                Write-Host "  copied   $($r.Rel)"
            }
        } elseif ($r.Component -eq 'runtime') {
            $m = $merge[$r.Rel]
            if (-not $m -or $m.Conflicts -ne 0) { $pending.Add($r.Rel); Write-Warning "Not merged $($r.Rel): $($r.Note)"; continue }
            Copy-Item -LiteralPath $m.Output -Destination $ours -Force
            Write-Host "  merged   $($r.Rel)"
        } elseif ($r.Component -eq 'state') {
            Write-Utf8Lf $ours (Convert-StateToRussian ([IO.File]::ReadAllText($theirsMap[$r.Rel], $utf8)))
            Write-Host "  state    $($r.Rel) (RU ids)"
        }
    }

    if ($Components -contains 'shards' -and $shardNew.Count -gt 0) {
        if (-not $BatchName) {
            $last = Get-ChildItem $batchesDir -Filter 'batch_*.json' | ForEach-Object { if ($_.Name -match '^batch_(\d+)') { [int]$Matches[1] } } | Measure-Object -Maximum
            $BatchName = 'batch_{0:D3}_cpdd_{1}.json' -f ($last.Maximum + 1), ($Tag.TrimStart('v') -replace '\.', '')
        }
        $batchPath = Join-Path $batchesDir $BatchName
        $items = New-Object System.Collections.Generic.List[object]
        $known = @{}
        if (Test-Path $batchPath) {
            foreach ($m in $batchItem.Matches([IO.File]::ReadAllText($batchPath, $utf8))) {
                $cn = [regex]::Unescape($m.Groups['cn'].Value); $known[$cn] = $true
                $items.Add([pscustomobject]@{ id = $m.Groups['id'].Value; source_cn = $cn; ref_en = [regex]::Unescape($m.Groups['en'].Value); target_ru = [regex]::Unescape($m.Groups['ru'].Value) })
            }
        }
        $nextId = $batches.MaxId
        foreach ($s in $shardNew | Sort-Object Cn) {
            if ($known.ContainsKey($s.Cn)) { continue }
            $nextId++
            $items.Add([pscustomobject]@{ id = "$nextId"; source_cn = $s.Cn; ref_en = $s.En; target_ru = '' })
        }
        Write-BatchFile $batchPath $items
        Write-Host "  batch    source/translation_batches/$BatchName ($($items.Count) entries, target_ru to translate)"
        $compiler = Join-Path $root 'tools\ShardCompiler.exe'
        if (Test-Path $compiler) { & $compiler -Root $root | Out-Null; Write-Host "  ShardCompiler exit $LASTEXITCODE" }
    }
    if ($shardChanged.Count -gt 0) { Write-Warning "$($shardChanged.Count) existing CN keys got a new EN in CPDD: review ref_en manually (see report)" }

    if ($Components -contains 'gamestate' -and $gamestateChanged) {
        Write-Utf8Lf $supportedPath $supportedWanted
        Write-Host "  gamestate installer/supported_game.json"
    } elseif ($gamestateChanged) { $pending.Add('installer/supported_game.json') }

    if ($pending.Count -eq 0 -and -not $hasProblems) {
        # Everything upstream is applied: CPDD $Tag becomes the new base.
        $newVendor = Join-Path $vendorDir $Tag
        New-Item -ItemType Directory -Path $newVendor -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $theirs.Dir 'release.json') -Destination $newVendor -Force
        foreach ($rel in 'Saved/Mods/bootstrap.lua', 'Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua', 'Saved/Mods/translation-overrides.state.json') {
            Copy-Item -LiteralPath $theirsMap[$rel] -Destination $newVendor -Force
        }
        $relSha = Get-Sha (Join-Path $newVendor 'release.json')
        Write-Utf8Lf (Join-Path $vendorDir 'BASE.json') "{`n  `"tag`": `"$Tag`",`n  `"release_json_sha256`": `"$relSha`",`n  `"note`": `"CPDD release that patch_payload is based on. Updated by tools/SyncCpdd.ps1 -Apply.`"`n}`n"
        if ($baseInfo.tag -ne $Tag) { Remove-Item -LiteralPath $vendorBase -Recurse -Force }
        Write-Host "  base     vendor/cpdd -> $Tag" -ForegroundColor Green
    } else {
        Write-Warning "Base stays $($baseInfo.tag): not applied: $($pending -join ', ')"
    }
}

if ($hasProblems) { exit 2 }
if ($upstreamCount -gt 0) { exit 1 }
exit 0
