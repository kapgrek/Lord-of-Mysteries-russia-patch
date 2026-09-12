param (
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrEmpty($OutDir)) {
    $OutDir = $projectRoot
}

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $csc)) {
    throw "csc.exe not found!"
}

$manifest = "$projectRoot\installer\app.manifest"
$icon = "$projectRoot\installer\app.ico"
$outputExe = "$OutDir\Lord-of-Mysteries-Diagnostic-Tool.exe"

$refs = "System.dll,System.Windows.Forms.dll,System.Drawing.dll,System.IO.Compression.dll,System.IO.Compression.FileSystem.dll"

Write-Host "=== Compiling Lord-of-Mysteries-Diagnostic-Tool.exe ===" -ForegroundColor Cyan

$cmdArgs = @(
    "/target:winexe",
    "/optimize+",
    "/platform:anycpu",
    "/highentropyva+",
    "/r:$refs",
    "/win32manifest:`"$manifest`"",
    "/win32icon:`"$icon`"",
    "/out:`"$outputExe`"",
    "`"$PSScriptRoot\LotmDiagnosticTool.cs`""
)

$proc = Start-Process -FilePath $csc -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "Compilation failed with exit code $($proc.ExitCode)"
}

Write-Host "Compilation SUCCESS: $outputExe ($((Get-Item $outputExe).Length) bytes)" -ForegroundColor Green

$v = (Get-Item $outputExe).VersionInfo
Write-Host "`nBinary info:" -ForegroundColor Yellow
Write-Host "  File:   $outputExe"
Write-Host "  SHA256: $((Get-FileHash $outputExe -Algorithm SHA256).Hash.ToLower())"
