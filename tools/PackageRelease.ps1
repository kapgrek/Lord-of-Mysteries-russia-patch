param (
    [string]$Version = "v2.9.0-RU",
    [switch]$Publish,          # Upload build artifacts as GitHub Release assets (gh CLI)
    [string]$NotesFile = ''    # Release notes for a newly created release
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = Split-Path $PSScriptRoot -Parent
$buildDir = "$projectRoot\build"
$repo = "kapgrek/Lord-of-Mysteries-russia-patch"

Write-Host "=== Lord of the Mysteries: Package Release ($Version) ===" -ForegroundColor Cyan

# 1. Patch validation
Write-Host "`n[1/5] Validating patch components..." -ForegroundColor Cyan
& "$PSScriptRoot\VerifyPatch.ps1" -Root "$projectRoot"

# 2. Compile GUI installer (into build/, binaries are not stored in git)
Write-Host "`n[2/5] Compiling GUI installer..." -ForegroundColor Cyan
if (-not (Test-Path $buildDir)) { New-Item -ItemType Directory -Path $buildDir -Force | Out-Null }
& "$projectRoot\installer\build_installer.ps1" -OutDir $buildDir

# 3. Create release archive
Write-Host "`n[3/5] Creating payload zip archive..." -ForegroundColor Cyan

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
Write-Host "`n[4/5] Generating release.json..." -ForegroundColor Cyan
$exePath = "$buildDir\Lord-of-Mysteries-Russian-Patch.exe"
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
[System.IO.File]::WriteAllText($releaseJsonPath, ($releaseInfo | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
Write-Host "Release manifest written to $releaseJsonPath" -ForegroundColor Green

# 5. Create all-in-one bundle zip
Write-Host "`n[5/5] Creating all-in-one zip bundle..." -ForegroundColor Cyan
$bundleZip = "$buildDir\Lord-of-Mysteries-Russian-Patch-$Version.zip"
if (Test-Path $bundleZip) { Remove-Item $bundleZip -Force }

$tempBundleDir = "$projectRoot\temp\bundle_$Version"
if (Test-Path $tempBundleDir) { Remove-Item $tempBundleDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempBundleDir -Force | Out-Null

Copy-Item $exePath -Destination $tempBundleDir
Copy-Item $zipPath -Destination $tempBundleDir
if (Test-Path "$projectRoot\installer\Install.bat") {
    Copy-Item "$projectRoot\installer\Install.bat" -Destination $tempBundleDir
}
if (Test-Path "$projectRoot\README.txt") {
    Copy-Item "$projectRoot\README.txt" -Destination $tempBundleDir
}

[System.IO.Compression.ZipFile]::CreateFromDirectory($tempBundleDir, $bundleZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item $tempBundleDir -Recurse -Force

$bundleItem = Get-Item $bundleZip
Write-Host "All-in-one bundle created: $bundleZip ($([math]::Round($bundleItem.Length / 1MB, 2)) MB)" -ForegroundColor Green

# Optional: publish as GitHub Release assets (the installer downloads release.json and the payload from there)
if ($Publish) {
    Write-Host "`n[Publish] Uploading assets to GitHub Release $Version..." -ForegroundColor Cyan
    $assets = @($zipPath, $releaseJsonPath, $exePath, $bundleZip)
    gh release view $Version -R $repo *> $null
    if ($LASTEXITCODE -ne 0) {
        $createArgs = @('release', 'create', $Version, '-R', $repo, '--target', 'main', '--title', $Version)
        if ($NotesFile) { $createArgs += @('--notes-file', $NotesFile) } else { $createArgs += @('--notes', '') }
        & gh @createArgs @assets
    } else {
        & gh release upload $Version -R $repo --clobber @assets
    }
    if ($LASTEXITCODE -ne 0) { throw "gh release failed with exit code $LASTEXITCODE" }
    Write-Host "Release assets published." -ForegroundColor Green
}

Write-Host "`nRelease packaging completed successfully!" -ForegroundColor Green
