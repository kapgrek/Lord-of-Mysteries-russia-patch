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
$installerSources = @('InstallerCore.cs', 'GameOptions.cs', 'PayloadSource.cs', 'PatcherBackend.cs', 'AppInfo.cs',
    'Ui\UiKit.cs', 'Ui\MainWindow.cs', 'Ui\HowToPlayWindow.cs', 'Ui\FolderPicker.cs', 'Ui\Links.cs') | ForEach-Object { "installer\$_" }
$extraSources = @{
    'InstallerCoreTests' = $installerSources
}

$root = Split-Path $PSScriptRoot -Parent
$fw = Split-Path $csc -Parent
$refs = "/r:System.Web.Extensions.dll", "/r:System.IO.Compression.dll", "/r:System.IO.Compression.FileSystem.dll"

# InstallerCoreTests also loads the installer windows (XAML) and texts: WPF references and the same resources as the installer.
$extraArgs = @{
    'InstallerCoreTests' = @("/r:$fw\System.Xaml.dll", "/r:$fw\WPF\PresentationFramework.dll", "/r:$fw\WPF\PresentationCore.dll", "/r:$fw\WPF\WindowsBase.dll") + (
        @{ 'links.json' = 'links.json'; 'HowToPlay.md' = 'HowToPlay.md'; 'app.ico' = 'app.ico'; 'Ui\Theme.xaml' = 'Theme.xaml';
           'Ui\MainWindow.xaml' = 'MainWindow.xaml'; 'Ui\HowToPlayWindow.xaml' = 'HowToPlayWindow.xaml'; 'supported_game.json' = 'supported_game.json' }.GetEnumerator() |
        ForEach-Object { "/resource:$root\installer\$($_.Key),LotmRussianPatcher.$($_.Value)" }) + (
        Get-ChildItem "$root\installer\howto\*.png" | ForEach-Object { "/resource:$($_.FullName),LotmRussianPatcher.howto.$($_.Name)" })
}

foreach ($name in $tools) {
    $src = @(Join-Path $PSScriptRoot "$name.cs")
    if ($extraSources.ContainsKey($name)) { $src += $extraSources[$name] | ForEach-Object { Join-Path $root $_ } }
    $extra = if ($extraArgs.ContainsKey($name)) { $extraArgs[$name] } else { @() }
    $out = Join-Path $PSScriptRoot "$name.exe"
    Write-Host "Compiling $name.exe..." -ForegroundColor Cyan
    & $csc /nologo /optimize+ $refs $extra "/out:$out" $src
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation of $name failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Tools built: $($tools -join ', ')" -ForegroundColor Green
