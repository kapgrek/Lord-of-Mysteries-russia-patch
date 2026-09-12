using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

public class FastShardCompiler {
    public class TextItem {
        public string id { get; set; }
        public string source_cn { get; set; }
        public string ref_en { get; set; }
        public string target_ru { get; set; }
    }

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

    public static void Main(string[] args) {
        Console.OutputEncoding = Encoding.UTF8;
        string root = @"d:\gameDev\AbsoluteRU";
        string batchesDir = Path.Combine(root, "source", "translation_batches");
        string shardsDir = Path.Combine(root, "patch_payload", "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes");

        if (args.Length > 0 && Directory.Exists(args[0])) {
            batchesDir = args[0];
        }

        Console.WriteLine("=== Lord of the Mysteries: Shard Compiler v2.6-RU ===");
        Console.WriteLine("Чтение батчей из: " + batchesDir);
        Console.WriteLine("Целевая папка шардов: " + shardsDir);

        string[] batchFiles = Directory.GetFiles(batchesDir, "batch_*.json");
        Console.WriteLine("Найдено файлов батчей: " + batchFiles.Length);

        Dictionary<string, Dictionary<string, string>> shardMap = new Dictionary<string, Dictionary<string, string>>();
        int totalLoaded = 0;
        int translatedCount = 0;
        int enMappedCount = 0;

        Regex itemRegex = new Regex(@"""source_cn""\s*:\s*""((?:\\""|[^""])*)""\s*,\s*""ref_en""\s*:\s*""((?:\\""|[^""])*)""\s*,\s*""target_ru""\s*:\s*""((?:\\""|[^""])*)""", RegexOptions.Compiled);

        foreach (string bFile in batchFiles) {
            string content = File.ReadAllText(bFile, Encoding.UTF8);
            MatchCollection matches = itemRegex.Matches(content);
            foreach (Match m in matches) {
                string cn = UnescapeJson(m.Groups[1].Value);
                string en = UnescapeJson(m.Groups[2].Value);
                string ru = UnescapeJson(m.Groups[3].Value);

                string finalVal = !string.IsNullOrEmpty(ru) ? ru : en;
                if (!string.IsNullOrEmpty(ru)) translatedCount++;

                if (!string.IsNullOrEmpty(cn)) {
                    string keyCn = ComputeSourceKey(cn);
                    string shardCn = GetShardPrefix(keyCn);

                    if (!shardMap.ContainsKey(shardCn)) {
                        shardMap[shardCn] = new Dictionary<string, string>();
                    }
                    shardMap[shardCn][cn] = finalVal;
                    totalLoaded++;
                }

                // Also map English reference to Russian translation so text rendered
                // from CPDD English overlays or baked text gets translated to Russian
                if (!string.IsNullOrEmpty(en) && en != cn && !string.IsNullOrEmpty(ru) && ru != en) {
                    string keyEn = ComputeSourceKey(en);
                    string shardEn = GetShardPrefix(keyEn);

                    if (!shardMap.ContainsKey(shardEn)) {
                        shardMap[shardEn] = new Dictionary<string, string>();
                    }
                    if (!shardMap[shardEn].ContainsKey(en)) {
                        shardMap[shardEn][en] = ru;
                        enMappedCount++;
                    }
                }
            }
        }

        Console.WriteLine("Загружено строк: " + totalLoaded + " (переведено на русский: " + translatedCount + ", EN->RU алиасов: " + enMappedCount + ")");
        Console.WriteLine("Запись в 1024 Lua-шарда...");

        UTF8Encoding utf8 = new UTF8Encoding(true);
        for (int s = 0; s < 1024; s++) {
            string shardName = s.ToString("x3");
            string fileName = "RuntimeTextGemini_" + shardName + ".lua";
            string filePath = Path.Combine(shardsDir, fileName);

            StringBuilder sb = new StringBuilder();
            sb.AppendLine("-- Generated for Lord of the Mysteries Russian Translation (v2.6-RU)");
            sb.AppendLine("-- Lazy exact-text shard " + shardName + "/3ff.");
            sb.AppendLine("return {");

            if (shardMap.ContainsKey(shardName)) {
                foreach (KeyValuePair<string, string> kvp in shardMap[shardName]) {
                    sb.AppendLine("    [\"" + EscapeLua(kvp.Key) + "\"] = \"" + EscapeLua(kvp.Value) + "\",");
                }
            }

            sb.AppendLine("}");
            File.WriteAllText(filePath, sb.ToString(), utf8);
        }

        Console.WriteLine("Все 1024 шарда успешно обновлены!");
    }

    private static string UnescapeJson(string s) {
        if (string.IsNullOrEmpty(s)) return "";
        return s.Replace(@"\""", @"""")
                .Replace(@"\\", @"\")
                .Replace(@"\r", "\r")
                .Replace(@"\n", "\n")
                .Replace(@"\t", "\t");
    }

    private static string EscapeLua(string s) {
        if (s == null) return "";
        return s.Replace(@"\", @"\\")
                .Replace(@"""", @"\""")
                .Replace("\r", @"\r")
                .Replace("\n", @"\n");
    }
}
