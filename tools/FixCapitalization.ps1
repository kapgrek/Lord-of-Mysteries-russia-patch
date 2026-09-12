# FixCapitalization.ps1 - Compiles and runs FixCapitalization utility
param(
    [switch]$Apply,
    [int]$Batch = 0,
    [string]$BatchesDir = '..\source\translation_batches'
)

$ErrorActionPreference = 'Stop'
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $csc)) {
    throw "csc.exe not found!"
}

$sourceFile = Join-Path $PSScriptRoot "FixCapitalization.cs"
$exeFile = Join-Path $PSScriptRoot "FixCapitalization.exe"

# Recompile if exe does not exist or source is newer
if (-not (Test-Path $exeFile) -or ((Get-Item $sourceFile).LastWriteTime -gt (Get-Item $exeFile).LastWriteTime)) {
    Write-Host "Compiling FixCapitalization.exe..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $csc -ArgumentList "/nologo /optimize+ /platform:anycpu /out:`"$exeFile`" `"$sourceFile`"" -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Compilation failed with exit code $($proc.ExitCode)"
    }
}

$resolvedBatches = Resolve-Path (Join-Path $PSScriptRoot $BatchesDir)
$cmdArgs = [System.Collections.Generic.List[string]]::new()
$cmdArgs.Add("`"$resolvedBatches`"")

if ($Apply) {
    $cmdArgs.Add("-Apply")
}
if ($Batch -gt 0) {
    $cmdArgs.Add("-Batch")
    $cmdArgs.Add($Batch.ToString())
}

& $exeFile @cmdArgs
