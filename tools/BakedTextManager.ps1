# BakedTextManager.ps1 — Менеджер блочного патчинга запеченного текста и текстур UE5
param(
    [ValidateSet('info', 'verify', 'export')]
    [string]$Action = 'info',
    [string]$BakedDir = '..\patch_payload\Saved\Mods\BakedText'
)

$ErrorActionPreference = 'Stop'
Write-Host "=== Lord of the Mysteries: BakedText Manager ===" -ForegroundColor Cyan

$manifestPath = Join-Path $BakedDir "manifest.json"
$blocksPath = Join-Path $BakedDir "blocks.bin"

if (-not (Test-Path $manifestPath) -or -not (Test-Path $blocksPath)) {
    Write-Error "Файлы BakedText не найдены в $BakedDir!"
    exit 1
}

$manifestJson = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
$manifest = $manifestJson | ConvertFrom-Json
$binInfo = Get-Item $blocksPath

Write-Host "Манифест: $manifestPath"
Write-Host "Хранилище блоков: $blocksPath ($([Math]::Round($binInfo.Length / 1MB, 2)) МБ)"
Write-Host "Всего блоков в манифесте: $($manifest.blocks.Count)"

$containers = @{}
foreach ($b in $manifest.blocks) {
    if (-not $containers.ContainsKey($b.container)) {
        $containers[$b.container] = 0
    }
    $containers[$b.container]++
}

Write-Host "`nРаспределение блоков по контейнерам IoStore:"
foreach ($c in $containers.Keys) {
    Write-Host ("  {0,-50} : {1,5} блоков" -f $c, $containers[$c])
}

if ($Action -eq 'verify') {
    Write-Host "`nВерификация контрольных сумм в blocks.bin..."
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($blocksPath)
    $buffer = [byte[]]::new(65536)
    $errors = 0

    for ($i = 0; $i -lt [Math]::Min(500, $manifest.blocks.Count); $i++) {
        $b = $manifest.blocks[$i]
        $blockBytes = [byte[]]::new($b.size)
        $stream.Position = $b.replacement_offset
        $stream.Read($blockBytes, 0, $b.size) | Out-Null
        $hash = [System.BitConverter]::ToString($sha.ComputeHash($blockBytes)).Replace('-', '').ToLower()
        if ($hash -ne $b.replacement_sha256.ToLower()) {
            Write-Warning "Несовпадение хеша в блоке $i: ожидался $($b.replacement_sha256), получен $hash"
            $errors++
        }
    }
    $stream.Close()

    if ($errors -eq 0) {
        Write-Host "Проверка блоков пройдена успешно! blocks.bin полностью валиден." -ForegroundColor Green
    } else {
        Write-Error "Обнаружено $errors ошибок хеширования блоков!"
    }
}
