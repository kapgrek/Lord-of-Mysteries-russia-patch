# Lord-of-Mysteries-Russian-Patch.ps1 — Интерактивный установщик русского патча
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Lord of the Mysteries — Установщик русской локализации   " -ForegroundColor White
Write-Host "                      Версия 2.6-RU                         " -ForegroundColor Yellow
Write-Host "============================================================`n" -ForegroundColor Cyan

# Автопоиск папки игры
$commonPaths = @(
    "D:\Game\Lord of Mysteries",
    "D:\Games\Lord of Mysteries",
    "D:\Lord of Mysteries",
    "C:\Game\Lord of Mysteries",
    "C:\Program Files\Lord of Mysteries"
)

$gamePath = ''
foreach ($p in $commonPaths) {
    if (Test-Path (Join-Path $p "Content\Paks\pakchunk0-Windows.pak")) {
        $gamePath = $p
        break
    }
}

if ([string]::IsNullOrEmpty($gamePath)) {
    Write-Host "Автоматическое обнаружение не нашло стандартную папку игры." -ForegroundColor Yellow
    Write-Host "Пожалуйста, введите путь к корневой папке игры (где находится Content и Binaries):"
    $gamePath = Read-Host "Путь к игре"
} else {
    Write-Host "Найдена установленная игра: $gamePath" -ForegroundColor Green
    $answer = Read-Host "Установить патч в эту директорию? (Y/n)"
    if ($answer -eq 'n' -or $answer -eq 'N') {
        $gamePath = Read-Host "Введите свой путь к игре"
    }
}

$gamePath = $gamePath.Trim('"').Trim()
if (-not (Test-Path (Join-Path $gamePath "Content\Paks\pakchunk0-Windows.pak"))) {
    Write-Host "`nОШИБКА: По указанному пути не найден файл Content\Paks\pakchunk0-Windows.pak!" -ForegroundColor Red
    Write-Host "Убедитесь, что вы выбрали корневую папку игры Lord of the Mysteries."
    Read-Host "Нажмите Enter для завершения..."
    exit 1
}

# Компиляция движка патчера
$engineCs = Join-Path $PSScriptRoot "PatcherEngine.cs"
$engineExe = Join-Path $PSScriptRoot "PatcherEngine.exe"

if (-not (Test-Path $engineExe) -or (Get-Item $engineCs).LastWriteTime -gt (Get-Item $engineExe).LastWriteTime) {
    Write-Host "Компиляция высокопроизводительного движка патчера..."
    $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (Test-Path $csc) {
        & $csc /nologo /out:$engineExe $engineCs | Out-Null
    }
}

Write-Host "`nВыберите действие:" -ForegroundColor Cyan
Write-Host "  1. Установить русский патч"
Write-Host "  2. Удалить русский патч (Откат к оригинальной игре)"
Write-Host "  0. Выход"
$choice = Read-Host "Ваш выбор (1/2/0)"

if ($choice -eq '1') {
    Write-Host "`nЗапуск процесса установки..." -ForegroundColor Cyan
    & $engineExe $gamePath "install"
} elseif ($choice -eq '2') {
    Write-Host "`nЗапуск процесса удаления патча..." -ForegroundColor Cyan
    & $engineExe $gamePath "uninstall"
} else {
    Write-Host "Выход без изменений."
    exit 0
}

Write-Host "`nНажмите любую клавишу для завершения..."
Read-Host | Out-Null
