# VerifyPatch.ps1 — Комплексный валидатор русской локализации Lord of the Mysteries
param(
    [string]$Root = (Join-Path $PSScriptRoot "..")
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Валидатор целостности патча Lord of the Mysteries v2.6-RU ===" -ForegroundColor Cyan

$payload = Join-Path $Root "patch_payload"
$errors = 0

# 1. Проверка моста pakchunk0
$bridge = Join-Path $payload "bridge\LaunchInstance.native-bridge.padded.oodle"
if (Test-Path $bridge) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.IO.File]::ReadAllBytes($bridge)
    $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLower()
    if ($bytes.Length -eq 4660 -and $hash -eq 'c031726986e09358bb18ff8a2b8ee5f0b4e65ce8ae8331eed2d7575c80b7efa9') {
        Write-Host "[OK] Нативный Oodle-блок моста проверен: 4660 байт, SHA-256 валиден." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] Поврежден нативный блок моста: $bridge (размер: $($bytes.Length), хеш: $hash)"
        $errors++
    }
} else {
    Write-Error "[ERROR] Файл моста не найден: $bridge"
    $errors++
}

# 2. Проверка блоков BakedText
$blocksBin = Join-Path $payload "Saved\Mods\BakedText\blocks.bin"
if (Test-Path $blocksBin) {
    $len = (Get-Item $blocksBin).Length
    if ($len -eq 39170464) {
        Write-Host "[OK] blocks.bin проверен: 39 170 464 байт." -ForegroundColor Green
    } else {
        Write-Warning "[WARN] blocks.bin имеет нестандартный размер: $len байт."
    }
} else {
    Write-Error "[ERROR] blocks.bin не найден!"
    $errors++
}

# 3. Проверка шардов рантайма
$shardsDir = Join-Path $payload "Saved\Mods\lua\mods\cpdd_runtime_fixes"
$geminiShards = (Get-ChildItem -Path $shardsDir -Filter "RuntimeTextGemini_*.lua").Count
$indexShards = (Get-ChildItem -Path $shardsDir -Filter "LanguageSourceIndex_*.lua").Count

if ($geminiShards -eq 1024) {
    Write-Host "[OK] Все 1 024 шарда RuntimeText присутствуют в сборе." -ForegroundColor Green
} else {
    Write-Warning "[WARN] Обнаружено $geminiShards / 1024 шардов RuntimeText!"
}

if ($indexShards -eq 256) {
    Write-Host "[OK] Все 256 шардов индексов присутствуют в сборе." -ForegroundColor Green
} else {
    Write-Warning "[WARN] Обнаружено $indexShards / 256 шардов индексов!"
}

# 4. Проверка баз данных Excel
$excelDir = Join-Path $payload "Saved\Mods\lua\cpdd_translation\Data\Excel\LanguageData"
$dbCount = (Get-ChildItem -Path $excelDir -Filter "StringDB_CN_Data*.lua").Count
if ($dbCount -ge 38) {
    Write-Host "[OK] $dbCount локализационных модулей Excel баз данных на месте." -ForegroundColor Green
} else {
    Write-Warning "[WARN] Найдено только $dbCount модулей Excel баз данных!"
}

# 5. Проверка лимита локальных переменных в Init.lua (LUAI_MAXVARS <= 200)
$initLua = Join-Path $payload "Saved\Mods\lua\mods\cpdd_runtime_fixes\Init.lua"
if (Test-Path $initLua) {
    $topLocals = (Get-Content $initLua | Select-String -Pattern '^local ').Count
    $margin = 200 - $topLocals
    if ($topLocals -le 190) {
        Write-Host "[OK] Init.lua проверен: $topLocals локальных переменных верхнего уровня (лимит: 200, запас: $margin)." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] Init.lua превышает безопасный лимит локальных переменных: $topLocals / 200!"
        $errors++
    }
} else {
    Write-Error "[ERROR] Init.lua не найден!"
    $errors++
}

if ($errors -eq 0) {
    Write-Host "`nВсе ключевые компоненты русской локализации успешно проверены и готовы к установке!" -ForegroundColor Green
} else {
    Write-Error "`nПроверка завершилась с ошибками ($errors)!"
}
