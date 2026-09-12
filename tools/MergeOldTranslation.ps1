# MergeOldTranslation.ps1 - Compiles and runs MergeOldTranslation utility
param(
    [switch]$Apply,
    [int]$Batch = 0,
    [int]$StartBatch = 6,
    [int]$EndBatch = 27,
    [int]$Samples = 10,
    [string]$LuaPath = 'D:\gameDev\translate lotm\RuntimeTextRussian.lua',
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

$sourceFile = Join-Path $PSScriptRoot "MergeOldTranslation.cs"
$exeFile = Join-Path $PSScriptRoot "MergeOldTranslation.exe"

# Recompile if exe does not exist or source is newer
if (-not (Test-Path $exeFile) -or ((Get-Item $sourceFile).LastWriteTime -gt (Get-Item $exeFile).LastWriteTime)) {
    Write-Host "Compiling MergeOldTranslation.exe..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $csc -ArgumentList "/nologo /optimize+ /platform:anycpu /out:`"$exeFile`" `"$sourceFile`"" -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Compilation failed with exit code $($proc.ExitCode)"
    }
}

$resolvedBatches = Resolve-Path (Join-Path $PSScriptRoot $BatchesDir)
$cmdArgs = [System.Collections.Generic.List[string]]::new()
$cmdArgs.Add("-BatchesDir")
$cmdArgs.Add("`"$resolvedBatches`"")
$cmdArgs.Add("-LuaPath")
$cmdArgs.Add("`"$LuaPath`"")

if ($Apply) {
    $cmdArgs.Add("-Apply")
}
if ($Batch -gt 0) {
    $cmdArgs.Add("-Batch")
    $cmdArgs.Add($Batch.ToString())
} else {
    $cmdArgs.Add("-StartBatch")
    $cmdArgs.Add($StartBatch.ToString())
    $cmdArgs.Add("-EndBatch")
    $cmdArgs.Add($EndBatch.ToString())
}
if ($Samples -gt 0) {
    $cmdArgs.Add("-Samples")
    $cmdArgs.Add($Samples.ToString())
}

& $exeFile @cmdArgs
