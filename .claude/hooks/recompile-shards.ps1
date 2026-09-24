# Stop hook: if source/translation_batches/batch_*.json changed since the last run,
# recompile RuntimeTextGemini shards (tools/ShardCompiler.exe) and validate batches (tools/VerifyBatch.ps1).
# On validation failure Claude is sent back to fix the batch (once per stop cycle).
$ErrorActionPreference = 'Stop'

try { $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { $payload = $null }

$root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$batchesDir = Join-Path $root 'source\translation_batches'
$tempDir = Join-Path $root 'temp'
$stamp = Join-Path $tempDir '.shard_compile_stamp'

$batches = @(Get-ChildItem -Path $batchesDir -Filter 'batch_*.json' -File -ErrorAction SilentlyContinue)
if ($batches.Count -eq 0) { exit 0 }
$newest = ($batches | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum

$ErrorActionPreference = 'Continue'
$dirty = @(git -C $root status --porcelain -- 'source/translation_batches/batch_*.json' 2>$null)
$ErrorActionPreference = 'Stop'
if (Test-Path $stamp) {
    $since = (Get-Item $stamp).LastWriteTimeUtc
    if ($newest -le $since) { exit 0 }
    $changed = @($batches | Where-Object { $_.LastWriteTimeUtc -gt $since })
} elseif ($dirty.Count -gt 0) {
    $changed = @($dirty | ForEach-Object { Get-Item (Join-Path $root ($_.Substring(3).Trim('"'))) -ErrorAction SilentlyContinue } | Where-Object { $_ })
} else {
    # First run with a clean tree: nothing to do, just remember the current state.
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    Set-Content -Path $stamp -Value '' -Encoding ASCII
    exit 0
}

$compiler = Join-Path $root 'tools\ShardCompiler.exe'
if (-not (Test-Path $compiler)) {
    & (Join-Path $root 'tools\BuildTools.ps1') -Only ShardCompiler | Out-Null
}
$compileOut = & $compiler 2>&1 | Out-String
$compileCode = $LASTEXITCODE
# Validate only the changed batches: a full VerifyBatch run takes ~3 minutes.
$verifyOut = ''
foreach ($f in $changed) {
    if ($f.Name -match '^batch_(\d+)') {
        $verifyOut += & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\VerifyBatch.ps1') -Batch ([int]$Matches[1]) 2>&1 | Out-String
    }
}

$failed = ($compileCode -ne 0) -or ($verifyOut -match '\[FAILURE\]')
if (-not $failed) {
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    Set-Content -Path $stamp -Value '' -Encoding ASCII
    $names = ($changed | ForEach-Object { $_.Name }) -join ', '
    @{ systemMessage = "Batches changed ($names): shards recompiled (ShardCompiler) and VerifyBatch passed." } | ConvertTo-Json -Compress
    exit 0
}

$errLines = ($verifyOut -split "`r?`n" | Where-Object { $_ -match '\[ERR|\[FAILURE\]' } | Select-Object -First 30) -join "`n"
$reason = "Batch files changed. ShardCompiler exit=$compileCode. VerifyBatch reported errors:`n$errLines`nFix the batches, then finish again."
if ($payload -and $payload.stop_hook_active) {
    # Already sent back once in this cycle: report without blocking to avoid a loop.
    @{ systemMessage = "VerifyBatch still failing after a retry:`n$errLines" } | ConvertTo-Json -Compress
    exit 0
}
@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
exit 0
