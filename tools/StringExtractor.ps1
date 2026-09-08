# StringExtractor.ps1 — Экстрактор строк из английского патча в структурированные батчи
param(
    [string]$SourceShardsDir = '..\patch_payload\Saved\Mods\lua\mods\cpdd_runtime_fixes',
    [string]$OutputDir = '..\source\translation_batches',
    [int]$BatchSize = 5000
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lord of the Mysteries: String Extractor ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$shards = Get-ChildItem -Path $SourceShardsDir -Filter "RuntimeTextGemini_*.lua"
Write-Host "Найдено $($shards.Count) файлов шардов."

$allEntries = [System.Collections.Generic.List[object]]::new()
$regex = [regex]'\[\"((?:\\\"|[^\"])+)\"\]\s*=\s*\"((?:\\\"|[^\"])*)\"'

$processed = 0
foreach ($shard in $shards) {
    $text = [System.IO.File]::ReadAllText($shard.FullName, [System.Text.Encoding]::UTF8)
    $matches = $regex.Matches($text)
    foreach ($m in $matches) {
        $cn = $m.Groups[1].Value.Replace('\"', '"').Replace('\\\\', '\')
        $en = $m.Groups[2].Value.Replace('\"', '"').Replace('\\\\', '\')
        $allEntries.Add(@{
            source_cn = $cn
            ref_en = $en
            target_ru = ""
        })
    }
    $processed++
    if ($processed % 100 -eq 0) {
        Write-Host "Обработано $processed / $($shards.Count) шардов... ($($allEntries.Count) строк)"
    }
}

Write-Host "Всего извлечено строк: $($allEntries.Count)" -ForegroundColor Green

# Экспорт в батчи
$batchIndex = 1
for ($i = 0; $i -lt $allEntries.Count; $i += $BatchSize) {
    $take = [Math]::Min($BatchSize, $allEntries.Count - $i)
    $batch = $allEntries.GetRange($i, $take)
    $batchFile = Join-Path $OutputDir ("batch_{0:D3}.json" -f $batchIndex)
    $json = $batch | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($batchFile, $json, [System.Text.Encoding]::UTF8)
    Write-Host "Сохранен батч $batchIndex ($take строк) -> $batchFile"
    $batchIndex++
}

Write-Host "Экспорт завершен успешно! Файлы готовы для параллельного перевода." -ForegroundColor Green
