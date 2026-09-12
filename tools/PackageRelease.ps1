param (
    [string]$Version = "v2.6-RU"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = Split-Path $PSScriptRoot -Parent
$buildDir = "$projectRoot\build"

Write-Host "=== Lord of the Mysteries: Package Release ($Version) ===" -ForegroundColor Cyan

# 1. Patch validation
Write-Host "`n[1/4] Validating patch components..." -ForegroundColor Cyan
& "$PSScriptRoot\VerifyPatch.ps1" -Root "$projectRoot"

# 2. Compile GUI installer
Write-Host "`n[2/4] Compiling GUI installer..." -ForegroundColor Cyan
& "$projectRoot\installer\build_installer.ps1" -OutDir "$projectRoot\installer"

# 3. Create release archive
Write-Host "`n[3/4] Creating payload zip archive..." -ForegroundColor Cyan
if (-not (Test-Path $buildDir)) { New-Item -ItemType Directory -Path $buildDir -Force | Out-Null }

$zipPath = "$buildDir\lom-russian-patch-data.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$payloadDir = "$projectRoot\patch_payload"
[System.IO.Compression.ZipFile]::CreateFromDirectory($payloadDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false, [System.Text.Encoding]::UTF8)

$zipItem = Get-Item $zipPath
$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
Write-Host "Archive created: $zipPath" -ForegroundColor Green
Write-Host "  Size:   $([math]::Round($zipItem.Length / 1MB, 2)) MB ($($zipItem.Length) bytes)"
Write-Host "  SHA256: $zipHash"

# 4. Generate release.json
Write-Host "`n[4/4] Generating release.json..." -ForegroundColor Cyan
$exePath = "$projectRoot\Lord-of-Mysteries-Russian-Patch.exe"
$exeItem = Get-Item $exePath
$exeHash = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()

$releaseInfo = @{
    release_version = $Version
    release_tag = $Version
    format_version = 2
    patcher_asset = @{
        name = "Lord-of-Mysteries-Russian-Patch.exe"
        sha256 = $exeHash
        size = $exeItem.Length
    }
    payload = @{
        name = "lom-russian-patch-data.zip"
        sha256 = $zipHash
        size = $zipItem.Length
    }
}

$releaseJsonPath = "$buildDir\release.json"
$releaseInfo | ConvertTo-Json -Depth 5 | Set-Content -Path $releaseJsonPath -Encoding UTF8

Write-Host "Release manifest written to $releaseJsonPath" -ForegroundColor Green
Write-Host "`nRelease packaging completed successfully!" -ForegroundColor Green
