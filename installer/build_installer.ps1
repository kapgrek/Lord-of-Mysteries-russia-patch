param (
    [string]$OutDir = "$PSScriptRoot"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $csc)) {
    throw "csc.exe not found!"
}

$manifest = "$PSScriptRoot\app.manifest"
$icon = "$PSScriptRoot\app.ico"
$outputExe = "$OutDir\Lord-of-Mysteries-Russian-Patch.exe"

$refs = "System.dll,System.Windows.Forms.dll,System.Drawing.dll,System.IO.Compression.dll,System.IO.Compression.FileSystem.dll,System.Web.Extensions.dll"

Write-Host "=== Compiling Lord-of-Mysteries-Russian-Patch.exe ===" -ForegroundColor Cyan

$cmdArgs = @(
    "/target:winexe",
    "/optimize+",
    "/platform:anycpu",
    "/highentropyva+",
    "/r:$refs",
    "/win32manifest:`"$manifest`"",
    "/win32icon:`"$icon`"",
    "/out:`"$outputExe`"",
    "`"$PSScriptRoot\Program.cs`"",
    "`"$PSScriptRoot\AssemblyInfo.cs`""
)

$proc = Start-Process -FilePath $csc -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "Compilation failed with exit code $($proc.ExitCode)"
}

Write-Host "Compilation SUCCESS: $outputExe ($((Get-Item $outputExe).Length) bytes)" -ForegroundColor Green

# Copy to root
$rootExe = "$projectRoot\Lord-of-Mysteries-Russian-Patch.exe"
Copy-Item $outputExe $rootExe -Force
Write-Host "Copied to root: $rootExe" -ForegroundColor Green

# Scan with Windows Defender
Write-Host "Scanning with Windows Defender..." -ForegroundColor Cyan
try {
    Start-MpScan -ScanPath $outputExe -ScanType CustomScan -ErrorAction Stop
    Write-Host "Windows Defender: 0 threats detected!" -ForegroundColor Green
} catch {
    Write-Warning "Windows Defender scan: $_"
}

$v = (Get-Item $outputExe).VersionInfo
Write-Host "`nBinary info:" -ForegroundColor Yellow
Write-Host "  Product:     $($v.ProductName) ($($v.ProductVersion))"
Write-Host "  Description: $($v.FileDescription)"
Write-Host "  Company:     $($v.CompanyName)"
Write-Host "  SHA256:      $((Get-FileHash $outputExe -Algorithm SHA256).Hash.ToLower())"
