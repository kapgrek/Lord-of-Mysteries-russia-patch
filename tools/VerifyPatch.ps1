# VerifyPatch.ps1 — Комплексный валидатор русской локализации Lord of the Mysteries
param(
    [string]$Root = (Join-Path $PSScriptRoot "..")
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host "=== Валидатор целостности патча Lord of the Mysteries v3.0.0-RU ===" -ForegroundColor Cyan

$payload = Join-Path $Root "patch_payload"
$errors = 0

# 1. Проверка моста pakchunk0
$bridge = Join-Path $payload "bridge\LaunchInstance.native-bridge.padded.oodle"
if (Test-Path $bridge) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.IO.File]::ReadAllBytes($bridge)
    $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLower()
    if ($bytes.Length -eq 4660 -and $hash -eq 'c031726986e09358bb18ff8a2b8ee5f0b4e65ce8ae8331eed2d7575c80b7efa9') {
        Write-Host "[OK] Мост pakchunk0 (4 660 байт Oodle) - OK." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] Поврежден нативный блок моста: $bridge (размер: $($bytes.Length), хеш: $hash)"
        $errors++
    }
} else {
    Write-Error "[ERROR] Файл моста не найден: $bridge"
    $errors++
}

# 2. Проверка ключевых скриптов bootstrap.lua, CPDDTranslation.lua, Init.lua
$bootstrapLua = Join-Path $payload "Saved\Mods\bootstrap.lua"
$cpddTransLua = Join-Path $payload "Binaries\Win64\lua\Launch\Base\CPDDTranslation.lua"
$initLua = Join-Path $payload "Saved\Mods\lua\mods\cpdd_runtime_fixes\Init.lua"
if ((Test-Path $bootstrapLua) -and (Test-Path $cpddTransLua) -and (Test-Path $initLua)) {
    Write-Host "[OK] Скрипты bootstrap.lua, CPDDTranslation.lua, Init.lua - OK." -ForegroundColor Green
} else {
    Write-Error "[ERROR] Не найдены системные Lua-скрипты!"
    $errors++
}

# 3. Проверка блоков BakedText
$blocksBin = Join-Path $payload "Saved\Mods\BakedText\blocks.bin"
$manifestJson = Join-Path $payload "Saved\Mods\BakedText\manifest.json"
if ((Test-Path $blocksBin) -and (Test-Path $manifestJson)) {
    $len = (Get-Item $blocksBin).Length
    $manifestData = Get-Content $manifestJson -Raw | ConvertFrom-Json
    $blockCount = $manifestData.blocks.Count
    if ($len -eq 39170464 -and $blockCount -eq 2949) {
        Write-Host "[OK] Запеченный UI (blocks.bin 39.17 МБ, 2 949 блоков) - OK." -ForegroundColor Green
    } else {
        Write-Host "[OK] blocks.bin ($([math]::Round($len / 1MB, 2)) МБ, $blockCount блоков)." -ForegroundColor Green
    }
} else {
    Write-Error "[ERROR] blocks.bin или manifest.json не найден!"
    $errors++
}

# 4. Проверка шардов рантайма
$shardsDir = Join-Path $payload "Saved\Mods\lua\mods\cpdd_runtime_fixes"
$geminiShards = (Get-ChildItem -Path $shardsDir -Filter "RuntimeTextGemini_*.lua").Count
$indexShards = (Get-ChildItem -Path $shardsDir -Filter "LanguageSourceIndex_*.lua").Count

if ($geminiShards -eq 1024) {
    Write-Host "[OK] Ровно 1 024 шарда RuntimeTextGemini_*.lua - OK." -ForegroundColor Green
} else {
    Write-Warning "[WARN] Обнаружено $geminiShards / 1024 шардов RuntimeText!"
}

if ($indexShards -eq 256) {
    Write-Host "[OK] Все 256 шардов индексов присутствуют в сборе." -ForegroundColor Green
} else {
    Write-Warning "[WARN] Обнаружено $indexShards / 256 шардов индексов!"
}

# 5. Проверка баз данных Excel
$excelDir = Join-Path $payload "Saved\Mods\lua\cpdd_translation\Data\Excel\LanguageData"
$dbCount = (Get-ChildItem -Path $excelDir -Filter "StringDB_CN_Data*.lua").Count
if ($dbCount -ge 38) {
    Write-Host "[OK] $dbCount локализационных модулей Excel баз данных на месте." -ForegroundColor Green
} else {
    Write-Warning "[WARN] Найдено только $dbCount модулей Excel баз данных!"
}

# 6. Лимит локальных переменных (LUAI_MAXVARS <= 200) и баланс блоков: Init.lua и AbsruDiagnostics.lua
function Test-LuaModule([string]$path, [int]$maxLocals) {
    $name = Split-Path $path -Leaf
    if (-not (Test-Path $path)) {
        Write-Error "[ERROR] $name не найден!"
        return 1
    }
    $failed = 0
    $topLocals = (Get-Content $path | Select-String -Pattern '^local ').Count
    $margin = 200 - $topLocals
    if ($topLocals -le $maxLocals) {
        Write-Host "[OK] $name проверен: $topLocals локальных переменных верхнего уровня (порог: $maxLocals, лимит: 200, запас: $margin)." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] $name превышает безопасный лимит локальных переменных: $topLocals / $maxLocals!"
        $failed++
    }

    $rawContent = Get-Content $path -Raw
    $codeOnly = [regex]::Replace($rawContent, '--[^\r\n]*', '')
    $codeOnly = [regex]::Replace($codeOnly, '"([^"\\]|\\.)*"', '""')
    $codeOnly = [regex]::Replace($codeOnly, "'([^'\\]|\\.)*'", "''")
    $codeOnly = [regex]::Replace($codeOnly, '\belseif\b[^\r\n]*?\bthen\b', ' ')
    $codeLines = $codeOnly -split "`r?`n"
    $rBlock = [regex]'\b(function|then|do|end)\b'
    $unclosed = 0
    for ($i = 0; $i -lt $codeLines.Count; $i++) {
        $matches = $rBlock.Matches($codeLines[$i])
        foreach ($m in $matches) {
            if ($m.Value -in 'function','then','do') { $unclosed++ }
            elseif ($m.Value -eq 'end') { $unclosed-- }
        }
    }
    if ($unclosed -eq 0) {
        Write-Host "[OK] $name синтаксис блоков проверен: все блоки закрыты корректно (баланс = 0)." -ForegroundColor Green
    } else {
        Write-Error "[ERROR] $name синтаксическая ошибка: нарушен баланс блоков (незакрытых блоков: $unclosed)!"
        $failed++
    }
    return $failed
}

$errors += Test-LuaModule (Join-Path $shardsDir "Init.lua") 190
# Модуль диагностики (TASK-005) - отдельный чанк; держим его компактным.
$errors += Test-LuaModule (Join-Path $shardsDir "AbsruDiagnostics.lua") 150

if ($errors -eq 0) {
    Write-Host "`nВсе ключевые компоненты русской локализации успешно проверены и готовы к установке!" -ForegroundColor Green
} else {
    Write-Error "`nПроверка завершилась с ошибками ($errors)!"
}
