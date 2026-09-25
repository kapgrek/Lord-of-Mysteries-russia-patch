# BuildTools.ps1 - Compile tools/*.exe from their .cs sources (binaries are not stored in git)
param(
    [string[]]$Only = @()   # Tool names to build, e.g. -Only ShardCompiler. Empty = all.
)

$ErrorActionPreference = 'Stop'

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $csc)) {
    throw "csc.exe not found!"
}

$tools = @('ShardCompiler', 'FixCapitalization', 'MergeOldTranslation', 'MergeTranslated', 'InstallerCoreTests')
if ($Only.Count -gt 0) { $tools = $tools | Where-Object { $Only -contains $_ } }

# Extra sources compiled into a tool (paths relative to the repository root)
$extraSources = @{
    'InstallerCoreTests' = @('installer\InstallerCore.cs', 'installer\GameOptions.cs')
}

$root = Split-Path $PSScriptRoot -Parent
$refs = "/r:System.Web.Extensions.dll", "/r:System.IO.Compression.dll", "/r:System.IO.Compression.FileSystem.dll"

foreach ($name in $tools) {
    $src = @(Join-Path $PSScriptRoot "$name.cs")
    if ($extraSources.ContainsKey($name)) { $src += $extraSources[$name] | ForEach-Object { Join-Path $root $_ } }
    $out = Join-Path $PSScriptRoot "$name.exe"
    Write-Host "Compiling $name.exe..." -ForegroundColor Cyan
    & $csc /nologo /optimize+ $refs "/out:$out" $src
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation of $name failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Tools built: $($tools -join ', ')" -ForegroundColor Green
