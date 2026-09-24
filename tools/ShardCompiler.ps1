# ShardCompiler.ps1 — Компилятор и распределитель строк по 1024 шардов RuntimeText
# Полный эквивалент алгоритма хеширования FNV-1a из Init.lua игры Lord of the Mysteries

param(
    [string]$InputJson = '',
    [string]$PayloadDir = '..\\patch_payload\\Saved\\Mods\\lua\\mods\\cpdd_runtime_fixes',
    [switch]$RebuildAll
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Text;

public static class LomHash {
    public static string ComputeSourceKey(string text) {
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        uint hash = 2166136261u;
        for (int i = 0; i < bytes.Length; i++) {
            hash ^= bytes[i];
            hash = (uint)((int)hash + ((int)hash << 1) + ((int)hash << 4) + ((int)hash << 7) + ((int)hash << 8) + ((int)hash << 24));
        }
        return bytes.Length.ToString() + ":" + hash.ToString("x8");
    }

    public static string GetShardPrefix(string sourceKey) {
        int colon = sourceKey.IndexOf(':');
        if (colon < 0 || colon + 3 >= sourceKey.Length) return "000";
        string hex3 = sourceKey.Substring(colon + 1, 3);
        int val = Convert.ToInt32(hex3, 16);
        int shard = val / 4;
        return shard.ToString("x3");
    }

    public static string EscapeLua(string s) {
        if (s == null) return "";
        return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
    }
}
'@

Write-Host "=== Lord of the Mysteries: Shard Compiler v2.6-RU ===" -ForegroundColor Cyan
Write-Host "Алгоритм хеширования: FNV-1a 32-bit (LuaJIT / Init.lua parity)"

if ([string]::IsNullOrEmpty($InputJson)) {
    Write-Host "Использование: .\\ShardCompiler.ps1 -InputJson <путь_к_файлу_перевода.json>"
    Write-Host "Пример тестового вычисления ключа:"
    $sample = "<Assistant_Title1>战斗新手·三</Assistant_Title1>"
    $key = [LomHash]::ComputeSourceKey($sample)
    $shard = [LomHash]::GetShardPrefix($key)
    Write-Host "  Строка: $sample"
    Write-Host "  Ключ:   $key"
    Write-Host "  Шард:   RuntimeTextGemini_$shard.lua"
    exit 0
}

if (-not (Test-Path $InputJson)) {
    Write-Error "Файл $InputJson не найден!"
    exit 1
}

Write-Host "Чтение данных из $InputJson..."
$jsonContent = [System.IO.File]::ReadAllText($InputJson, [System.Text.Encoding]::UTF8)
$entries = $jsonContent | ConvertFrom-Json

$shardMap = @{}
$count = 0

foreach ($item in $entries) {
    $cn = $item.source_cn
    $ru = if ($item.target_ru) { $item.target_ru } else { $item.ref_en }
    if ([string]::IsNullOrEmpty($cn) -or [string]::IsNullOrEmpty($ru)) { continue }

    $key = [LomHash]::ComputeSourceKey($cn)
    $shard = [LomHash]::GetShardPrefix($key)

    if (-not $shardMap.ContainsKey($shard)) {
        $shardMap[$shard] = [System.Collections.Generic.List[object]]::new()
    }
    $shardMap[$shard].Add(@{ Key = $cn; Value = $ru })
    $count++
}

Write-Host "Распределено $count строк по $($shardMap.Keys.Count) шардам."

$targetPayloadDir = Resolve-Path $PayloadDir
Write-Host "Запись шардов в $targetPayloadDir..."

foreach ($shardKey in $shardMap.Keys) {
    $fileName = "RuntimeTextGemini_$shardKey.lua"
    $filePath = Join-Path $targetPayloadDir $fileName

    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine("-- Generated for Lord of the Mysteries Russian Translation (v2.6-RU)") | Out-Null
    $sb.AppendLine("-- Shard $shardKey/3ff") | Out-Null
    $sb.AppendLine("return {") | Out-Null

    foreach ($entry in $shardMap[$shardKey]) {
        $k = [LomHash]::EscapeLua($entry.Key)
        $v = [LomHash]::EscapeLua($entry.Value)
        $sb.AppendLine("    [\"$k\"] = \"$v\", ") | Out-Null
    }

    $sb.AppendLine("}") | Out-Null
    [System.IO.File]::WriteAllText($filePath, $sb.ToString(), [System.Text.Encoding]::UTF8)
}

Write-Host "Компиляция успешно завершена!" -ForegroundColor Green
