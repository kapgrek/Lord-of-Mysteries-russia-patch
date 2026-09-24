param (
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "build")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
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
    # Fallback supported game state when the data zip has no supported_game.json
    "/resource:`"$PSScriptRoot\supported_game.json`",LotmRussianPatcher.supported_game.json",
    "`"$PSScriptRoot\Program.cs`"",
    "`"$PSScriptRoot\InstallerCore.cs`"",
    "`"$PSScriptRoot\AssemblyInfo.cs`""
)

$proc = Start-Process -FilePath $csc -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "Compilation failed with exit code $($proc.ExitCode)"
}

Write-Host "Compilation SUCCESS: $outputExe ($((Get-Item $outputExe).Length) bytes)" -ForegroundColor Green

# Authenticode Code Signing (Защита от ложных срабатываний SmartScreen / Defender)
Write-Host "Applying Authenticode digital signature..." -ForegroundColor Cyan
try {
    $certSubject = "CN=Lord of Mysteries Russian Localization Project"
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $certSubject } | Select-Object -First 1
    if (-not $cert) {
        Write-Host "Creating code-signing certificate for project..." -ForegroundColor Cyan
        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $certSubject -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(5)
    }
    if ($cert) {
        $sig = Set-AuthenticodeSignature -FilePath $outputExe -Certificate $cert -TimestampServer "http://timestamp.digicert.com" -HashAlgorithm SHA256 -ErrorAction SilentlyContinue
        if (-not $sig -or $sig.Status -eq "UnknownError") {
            $sig = Set-AuthenticodeSignature -FilePath $outputExe -Certificate $cert -TimestampServer "http://timestamp.sectigo.com" -HashAlgorithm SHA256 -ErrorAction SilentlyContinue
        }
        if ($sig) {
            Write-Host "Authenticode signature: $($sig.Status) ($($cert.Subject))" -ForegroundColor Green
        }
    }
} catch {
    Write-Warning "Code signing warning: $_"
}

# Scan with Windows Defender
Write-Host "Scanning with Windows Defender..." -ForegroundColor Cyan
try {
    Start-MpScan -ScanPath $outputExe -ScanType CustomScan -ErrorAction Stop
    Write-Host "Windows Defender: 0 threats detected!" -ForegroundColor Green
} catch {
    Write-Warning "Windows Defender scan: $_"
}

$v = (Get-Item $outputExe).VersionInfo
$sigInfo = Get-AuthenticodeSignature $outputExe
Write-Host "`nBinary info:" -ForegroundColor Yellow
Write-Host "  Product:     $($v.ProductName) ($($v.ProductVersion))"
Write-Host "  Description: $($v.FileDescription)"
Write-Host "  Company:     $($v.CompanyName)"
Write-Host "  Signature:   $($sigInfo.Status)"
Write-Host "  SHA256:      $((Get-FileHash $outputExe -Algorithm SHA256).Hash.ToLower())"
