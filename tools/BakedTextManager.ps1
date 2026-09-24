# BakedTextManager.ps1 — Менеджер блочного патчинга запеченного текста и текстур UE5
param(
    [ValidateSet('info', 'verify', 'export', 'update', 'patch', 'restore')]
    [string]$Action = 'info',
    [string]$BakedDir = (Join-Path $PSScriptRoot "..\patch_payload\Saved\Mods\BakedText"),
    [string]$ExportDir = (Join-Path $PSScriptRoot "..\temp\baked_export"),
    [string]$GameDir = 'D:\Games\GMZZLauncher\Game\C7',
    [string]$ContainerFilter = '*',
    [int]$BlockIndex = -1,
    [string]$InputFile = '',
    [switch]$IncludeOriginal,
    [switch]$FullVerify
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Lord of the Mysteries: BakedText Manager ===" -ForegroundColor Cyan

# Преобразование путей к абсолютным
$BakedDir = [System.IO.Path]::GetFullPath($BakedDir)
$ExportDir = [System.IO.Path]::GetFullPath($ExportDir)

$manifestPath = Join-Path $BakedDir "manifest.json"
$blocksPath = Join-Path $BakedDir "blocks.bin"

if (-not (Test-Path $manifestPath) -or -not (Test-Path $blocksPath)) {
    Write-Error ("Файлы BakedText не найдены в {0}!" -f $BakedDir)
    exit 1
}

$manifestJson = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
$manifest = $manifestJson | ConvertFrom-Json
$binInfo = Get-Item $blocksPath

$sizeMb = [Math]::Round($binInfo.Length / 1MB, 2)
Write-Host ("Манифест: {0}" -f $manifestPath)
Write-Host ("Хранилище блоков: {0} ({1} МБ)" -f $blocksPath, $sizeMb)
Write-Host ("Всего блоков в манифесте: {0}" -f $manifest.blocks.Count)

$containers = @{}
for ($i = 0; $i -lt $manifest.blocks.Count; $i++) {
    $c = $manifest.blocks[$i].container
    if (-not $containers.ContainsKey($c)) {
        $containers[$c] = 0
    }
    $containers[$c]++
}

Write-Host "`nРаспределение блоков по контейнерам IoStore:"
foreach ($c in $containers.Keys) {
    Write-Host ("  {0,-50} : {1,5} блоков" -f $c, $containers[$c])
}

# 16-байтный циклический паттерн паддинга (зашифрованный нулевой блок)
$padPattern = [byte[]]@(0xC8, 0x64, 0x4C, 0x29, 0x33, 0x0A, 0x06, 0x6C, 0xDE, 0x3F, 0xEC, 0xE9, 0xD9, 0x47, 0x0E, 0x84)

# ==============================================================================
# ДЕЙСТВИЕ: VERIFY
# ==============================================================================
if ($Action -eq 'verify') {
    Write-Host "`nВерификация контрольных сумм в blocks.bin..."
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($blocksPath)
    $errors = 0
    $verifiedCount = 0

    $maxCheck = if ($FullVerify) { $manifest.blocks.Count } else { [Math]::Min(500, $manifest.blocks.Count) }
    Write-Host ("Проверка {0} блоков (используйте -FullVerify для всех {1})..." -f $maxCheck, $manifest.blocks.Count)

    for ($i = 0; $i -lt $maxCheck; $i++) {
        $b = $manifest.blocks[$i]
        if ($ContainerFilter -ne '*' -and $b.container -notlike $ContainerFilter) { continue }
        if ($BlockIndex -ge 0 -and $i -ne $BlockIndex) { continue }

        $verifiedCount++

        # Проверка replacement блока
        $blockBytes = New-Object byte[] $b.size
        $stream.Position = $b.replacement_offset
        $stream.Read($blockBytes, 0, $b.size) | Out-Null
        $hash = [System.BitConverter]::ToString($sha.ComputeHash($blockBytes)).Replace('-', '').ToLower()
        if ($hash -ne $b.replacement_sha256.ToLower()) {
            Write-Warning ("Несовпадение REPL хеша в блоке {0}: ожидался {1}, получен {2}" -f $i, $b.replacement_sha256, $hash)
            $errors++
        }

        # Проверка original блока
        $stream.Position = $b.original_offset
        $stream.Read($blockBytes, 0, $b.size) | Out-Null
        $origHash = [System.BitConverter]::ToString($sha.ComputeHash($blockBytes)).Replace('-', '').ToLower()
        if ($origHash -ne $b.original_sha256.ToLower()) {
            Write-Warning ("Несовпадение ORIG хеша в блоке {0}: ожидался {1}, получен {2}" -f $i, $b.original_sha256, $origHash)
            $errors++
        }
    }
    $stream.Close()

    if ($errors -eq 0) {
        Write-Host ("Проверка блоков ({0} блоков) пройдена успешно! blocks.bin полностью валиден." -f $verifiedCount) -ForegroundColor Green
    } else {
        Write-Error ("Обнаружено {0} ошибок хеширования блоков!" -f $errors)
    }
}

# ==============================================================================
# ДЕЙСТВИЕ: EXPORT
# ==============================================================================
if ($Action -eq 'export') {
    Write-Host ("`nЭкспорт блоков в {0}..." -f $ExportDir)
    if (-not (Test-Path $ExportDir)) {
        New-Item -ItemType Directory -Path $ExportDir -Force | Out-Null
    }

    $stream = [System.IO.File]::OpenRead($blocksPath)
    $exportIndex = @()
    $exportedCount = 0

    for ($i = 0; $i -lt $manifest.blocks.Count; $i++) {
        $b = $manifest.blocks[$i]
        if ($ContainerFilter -ne '*' -and $b.container -notlike $ContainerFilter) { continue }
        if ($BlockIndex -ge 0 -and $i -ne $BlockIndex) { continue }

        $cName = [System.IO.Path]::GetFileNameWithoutExtension($b.container)
        $replFile = ("block_{0:D4}_{1}_{2}_{3}.bin" -f $i, $cName, $b.offset, $b.size)
        $replPath = Join-Path $ExportDir $replFile

        # Читаем заменяющий блок
        $replBytes = New-Object byte[] $b.size
        $stream.Position = $b.replacement_offset
        $stream.Read($replBytes, 0, $b.size) | Out-Null
        [System.IO.File]::WriteAllBytes($replPath, $replBytes)

        # Вычисляем размер паддинга
        $padLen = 0
        $pos = $b.size - 16
        while ($pos -ge 0) {
            $isPad = $true
            for ($k = 0; $k -lt 16; $k++) {
                if ($replBytes[$pos + $k] -ne $padPattern[$k]) {
                    $isPad = $false
                    break
                }
            }
            if ($isPad) {
                $padLen += 16
                $pos -= 16
            } else {
                break
            }
        }
        $payloadLen = $b.size - $padLen

        $origFile = $null
        if ($IncludeOriginal) {
            $origFile = ("block_{0:D4}_{1}_{2}_{3}_orig.bin" -f $i, $cName, $b.offset, $b.size)
            $origPath = Join-Path $ExportDir $origFile
            $origBytes = New-Object byte[] $b.size
            $stream.Position = $b.original_offset
            $stream.Read($origBytes, 0, $b.size) | Out-Null
            [System.IO.File]::WriteAllBytes($origPath, $origBytes)
        }

        $exportIndex += [PSCustomObject]@{
            index = $i
            container = $b.container
            offset = [long]$b.offset
            size = [int]$b.size
            payload_len = $payloadLen
            pad_len = $padLen
            replacement_file = $replFile
            original_file = $origFile
            replacement_sha256 = $b.replacement_sha256
            original_sha256 = $b.original_sha256
        }

        $exportedCount++
    }

    $stream.Close()

    # Сохраняем мета-индекс экспорта
    $indexPath = Join-Path $ExportDir "export_index.json"
    $exportIndex | ConvertTo-Json -Depth 5 | Set-Content -Path $indexPath -Encoding UTF8

    Write-Host ("Экспорт завершен успешно! Извлечено блоков: {0}" -f $exportedCount) -ForegroundColor Green
    Write-Host ("Мета-индекс сохранен в: {0}" -f $indexPath)
}

# ==============================================================================
# ДЕЙСТВИЕ: UPDATE
# ==============================================================================
if ($Action -eq 'update') {
    if ($BlockIndex -lt 0 -or $BlockIndex -ge $manifest.blocks.Count) {
        Write-Error ("Укажите корректный -BlockIndex от 0 до {0}!" -f ($manifest.blocks.Count - 1))
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($InputFile) -or -not (Test-Path $InputFile)) {
        Write-Error "Укажите существующий входной файл через -InputFile!"
        exit 1
    }

    $b = $manifest.blocks[$BlockIndex]
    Write-Host ("Обновление блока {0} (Контейнер: {1}, Ожидаемый размер: {2} байт)..." -f $BlockIndex, $b.container, $b.size)

    $rawInput = [System.IO.File]::ReadAllBytes($InputFile)
    Write-Host ("Размер входного файла: {0} байт" -f $rawInput.Length)

    if ($rawInput.Length -gt $b.size) {
        Write-Error ("Размер входного файла ({0} байт) превышает максимальный размер блока ({1} байт)!" -f $rawInput.Length, $b.size)
        exit 1
    }

    $finalBytes = New-Object byte[] $b.size
    [Array]::Copy($rawInput, 0, $finalBytes, 0, $rawInput.Length)

    # Если входной файл меньше размера блока, дополняем циклическим паттерном
    if ($rawInput.Length -lt $b.size) {
        $needed = $b.size - $rawInput.Length
        Write-Host ("Дополнение блока паттерном паддинга на {0} байт..." -f $needed)
        for ($p = 0; $p -lt $needed; $p++) {
            $finalBytes[$rawInput.Length + $p] = $padPattern[$p % 16]
        }
    }

    # Вычисляем новый SHA-256
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $newHash = [System.BitConverter]::ToString($sha.ComputeHash($finalBytes)).Replace('-', '').ToLower()
    Write-Host ("Старый SHA-256: {0}" -f $b.replacement_sha256)
    Write-Host ("Новый SHA-256:  {0}" -f $newHash)

    # Записываем в blocks.bin
    $fs = [System.IO.File]::Open($blocksPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
    $fs.Position = $b.replacement_offset
    $fs.Write($finalBytes, 0, $finalBytes.Length)
    $fs.Flush()
    $fs.Close()

    # Обновляем manifest.json точечной правкой текста: ConvertTo-Json переформатировал бы
    # весь файл (CPDD хранит его с CRLF и отступом 2), и sha манифеста разошёлся бы с CPDD.
    $shaRx = [regex]'"replacement_sha256":\s*"([0-9a-fA-F]{64})"'
    $shaMatches = $shaRx.Matches($manifestJson)
    if ($shaMatches.Count -ne $manifest.blocks.Count) {
        Write-Error ("В манифесте {0} полей replacement_sha256 при {1} блоках, точечная правка невозможна" -f $shaMatches.Count, $manifest.blocks.Count)
        exit 1
    }
    $valueGroup = $shaMatches[$BlockIndex].Groups[1]
    $manifestJson = $manifestJson.Substring(0, $valueGroup.Index) + $newHash + $manifestJson.Substring($valueGroup.Index + $valueGroup.Length)
    # data_sha256 описывает весь blocks.bin
    $dataHash = (Get-FileHash -LiteralPath $blocksPath -Algorithm SHA256).Hash.ToLower()
    $manifestJson = ([regex]'("data_sha256":\s*")[0-9a-fA-F]{64}(")').Replace($manifestJson, "`${1}$dataHash`${2}", 1)
    [System.IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding $false))

    Write-Host ("Блок {0} успешно обновлен в blocks.bin и manifest.json!" -f $BlockIndex) -ForegroundColor Green
}

# ==============================================================================
# ДЕЙСТВИЕ: PATCH (Внедрение блоков в контейнеры игры)
# ==============================================================================
if ($Action -eq 'patch') {
    if ([string]::IsNullOrWhiteSpace($GameDir) -or -not (Test-Path $GameDir)) {
        Write-Error ("Укажите корректную папку игры через -GameDir! (Текущее значение: '{0}')" -f $GameDir)
        exit 1
    }

    $GameDir = [System.IO.Path]::GetFullPath($GameDir)
    Write-Host ("`nВнедрение блоков BakedText в игру: {0}..." -f $GameDir)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $binStream = [System.IO.File]::OpenRead($blocksPath)

    # Группируем блоки по контейнерам
    $blocksByContainer = @{}
    for ($i = 0; $i -lt $manifest.blocks.Count; $i++) {
        $b = $manifest.blocks[$i]
        if ($ContainerFilter -ne '*' -and $b.container -notlike $ContainerFilter) { continue }
        if ($BlockIndex -ge 0 -and $i -ne $BlockIndex) { continue }
        
        if (-not $blocksByContainer.ContainsKey($b.container)) {
            $blocksByContainer[$b.container] = New-Object System.Collections.Generic.List[PSCustomObject]
        }
        $bWithIdx = [PSCustomObject]@{
            index = $i
            block = $b
        }
        $blocksByContainer[$b.container].Add($bWithIdx)
    }

    $totalPatched = 0
    $totalAlreadyPatched = 0
    $totalErrors = 0

    foreach ($cRel in $blocksByContainer.Keys) {
        $cPath = Join-Path $GameDir $cRel
        if (-not (Test-Path $cPath)) {
            Write-Warning ("Контейнер не найден в игре: {0}" -f $cPath)
            continue
        }

        $cName = [System.IO.Path]::GetFileName($cPath)
        $blockList = $blocksByContainer[$cRel]
        Write-Host ("`nПатчинг контейнера {0} ({1} блоков)..." -f $cName, $blockList.Count)

        $fs = [System.IO.File]::Open($cPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
        $cPatched = 0
        $cAlready = 0

        foreach ($entry in $blockList) {
            $idx = $entry.index
            $b = $entry.block

            # Читаем текущие байты из контейнера для проверки
            $currentBytes = New-Object byte[] $b.size
            $fs.Position = $b.offset
            $fs.Read($currentBytes, 0, $b.size) | Out-Null
            $currentHash = [System.BitConverter]::ToString($sha.ComputeHash($currentBytes)).Replace('-', '').ToLower()

            if ($currentHash -eq $b.replacement_sha256.ToLower()) {
                $cAlready++
                $totalAlreadyPatched++
                continue
            }

            if ($currentHash -ne $b.original_sha256.ToLower()) {
                Write-Warning ("Блок {0} (смещение {1}): неизвестный хеш {2} (ожидался оригинал {3})!" -f $idx, $b.offset, $currentHash, $b.original_sha256)
                $totalErrors++
                continue
            }

            # Читаем заменяющие байты из blocks.bin
            $replBytes = New-Object byte[] $b.size
            $binStream.Position = $b.replacement_offset
            $binStream.Read($replBytes, 0, $b.size) | Out-Null

            # Записываем в контейнер
            $fs.Position = $b.offset
            $fs.Write($replBytes, 0, $b.size)
            $cPatched++
            $totalPatched++
        }

        $fs.Flush()
        $fs.Close()
        Write-Host ("  {0}: пропатчено {1}, уже было {2}" -f $cName, $cPatched, $cAlready)
    }

    $binStream.Close()
    Write-Host ("`nПатчинг завершен: успешно записано {0} блоков, уже пропатчено {1}, ошибок {2}." -f $totalPatched, $totalAlreadyPatched, $totalErrors) -ForegroundColor $(if ($totalErrors -eq 0) { "Green" } else { "Yellow" })
}

# ==============================================================================
# ДЕЙСТВИЕ: RESTORE (Восстановление оригинальных блоков в игре)
# ==============================================================================
if ($Action -eq 'restore') {
    if ([string]::IsNullOrWhiteSpace($GameDir) -or -not (Test-Path $GameDir)) {
        Write-Error ("Укажите корректную папку игры через -GameDir! (Текущее значение: '{0}')" -f $GameDir)
        exit 1
    }

    $GameDir = [System.IO.Path]::GetFullPath($GameDir)
    Write-Host ("`nВосстановление оригинальных блоков BakedText в игре: {0}..." -f $GameDir)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $binStream = [System.IO.File]::OpenRead($blocksPath)

    $blocksByContainer = @{}
    for ($i = 0; $i -lt $manifest.blocks.Count; $i++) {
        $b = $manifest.blocks[$i]
        if ($ContainerFilter -ne '*' -and $b.container -notlike $ContainerFilter) { continue }
        if ($BlockIndex -ge 0 -and $i -ne $BlockIndex) { continue }
        
        if (-not $blocksByContainer.ContainsKey($b.container)) {
            $blocksByContainer[$b.container] = New-Object System.Collections.Generic.List[PSCustomObject]
        }
        $bWithIdx = [PSCustomObject]@{
            index = $i
            block = $b
        }
        $blocksByContainer[$b.container].Add($bWithIdx)
    }

    $totalRestored = 0
    $totalAlreadyOrig = 0
    $totalErrors = 0

    foreach ($cRel in $blocksByContainer.Keys) {
        $cPath = Join-Path $GameDir $cRel
        if (-not (Test-Path $cPath)) {
            Write-Warning ("Контейнер не найден в игре: {0}" -f $cPath)
            continue
        }

        $cName = [System.IO.Path]::GetFileName($cPath)
        $blockList = $blocksByContainer[$cRel]
        Write-Host ("`nВосстановление контейнера {0} ({1} блоков)..." -f $cName, $blockList.Count)

        $fs = [System.IO.File]::Open($cPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
        $cRestored = 0
        $cAlready = 0

        foreach ($entry in $blockList) {
            $idx = $entry.index
            $b = $entry.block

            $currentBytes = New-Object byte[] $b.size
            $fs.Position = $b.offset
            $fs.Read($currentBytes, 0, $b.size) | Out-Null
            $currentHash = [System.BitConverter]::ToString($sha.ComputeHash($currentBytes)).Replace('-', '').ToLower()

            if ($currentHash -eq $b.original_sha256.ToLower()) {
                $cAlready++
                $totalAlreadyOrig++
                continue
            }

            if ($currentHash -ne $b.replacement_sha256.ToLower()) {
                Write-Warning ("Блок {0} (смещение {1}): неизвестный хеш {2} (ожидался replacement {3})!" -f $idx, $b.offset, $currentHash, $b.replacement_sha256)
                $totalErrors++
                continue
            }

            # Читаем оригинальные байты из blocks.bin
            $origBytes = New-Object byte[] $b.size
            $binStream.Position = $b.original_offset
            $binStream.Read($origBytes, 0, $b.size) | Out-Null

            # Записываем в контейнер
            $fs.Position = $b.offset
            $fs.Write($origBytes, 0, $b.size)
            $cRestored++
            $totalRestored++
        }

        $fs.Flush()
        $fs.Close()
        Write-Host ("  {0}: восстановлено {1}, уже было оригиналом {2}" -f $cName, $cRestored, $cAlready)
    }

    $binStream.Close()
    Write-Host ("`nВосстановление завершено: восстановлено {0} блоков, уже было оригиналом {1}, ошибок {2}." -f $totalRestored, $totalAlreadyOrig, $totalErrors) -ForegroundColor $(if ($totalErrors -eq 0) { "Green" } else { "Yellow" })
}

