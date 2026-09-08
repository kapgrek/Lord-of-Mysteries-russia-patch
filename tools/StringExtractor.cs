using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

public class FastStringExtractor {
    public class TextItem {
        public string id { get; set; }
        public string source_cn { get; set; }
        public string ref_en { get; set; }
        public string target_ru { get; set; }
    }

    public static void Main(string[] args) {
        Console.OutputEncoding = Encoding.UTF8;
        string root = @"d:\gameDev\AbsoluteRU";
        string shardsDir = Path.Combine(root, "patch_payload", "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes");
        string outDir = Path.Combine(root, "source", "translation_batches");
        Directory.CreateDirectory(outDir);

        Console.WriteLine("Сканирование файлов RuntimeTextGemini_*.lua...");
        string[] shardFiles = Directory.GetFiles(shardsDir, "RuntimeTextGemini_*.lua");
        Console.WriteLine("Найдено файлов шардов: " + shardFiles.Length);

        List<TextItem> items = new List<TextItem>(150000);
        Regex regex = new Regex(@"\[""((?:\\""|[^""])+)""\]\s*=\s*""((?:\\""|[^""])*)""", RegexOptions.Compiled);

        int fileIndex = 0;
        foreach (string file in shardFiles) {
            string text = File.ReadAllText(file, Encoding.UTF8);
            MatchCollection matches = regex.Matches(text);
            foreach (Match m in matches) {
                string cn = m.Groups[1].Value.Replace(@"\""", @"""").Replace(@"\\", @"\");
                string en = m.Groups[2].Value.Replace(@"\""", @"""").Replace(@"\\", @"\");
                items.Add(new TextItem {
                    id = items.Count.ToString("D6"),
                    source_cn = cn,
                    ref_en = en,
                    target_ru = ""
                });
            }
            fileIndex++;
            if (fileIndex % 200 == 0) {
                Console.WriteLine("Прочитано " + fileIndex + " / " + shardFiles.Length + " шардов (" + items.Count + " строк)...");
            }
        }

        Console.WriteLine("\nВсего извлечено строк: " + items.Count);

        int batchSize = 5000;
        int batchCount = (items.Count + batchSize - 1) / batchSize;
        UTF8Encoding utf8 = new UTF8Encoding(true);

        for (int b = 0; b < batchCount; b++) {
            int start = b * batchSize;
            int count = Math.Min(batchSize, items.Count - start);
            List<TextItem> sub = items.GetRange(start, count);

            StringBuilder sb = new StringBuilder();
            sb.AppendLine("[");
            for (int i = 0; i < sub.Count; i++) {
                TextItem it = sub[i];
                sb.AppendLine("  {");
                sb.AppendLine("    \"id\": \"" + it.id + "\",");
                sb.AppendLine("    \"source_cn\": \"" + EscapeJson(it.source_cn) + "\",");
                sb.AppendLine("    \"ref_en\": \"" + EscapeJson(it.ref_en) + "\",");
                sb.AppendLine("    \"target_ru\": \"\"");
                sb.Append("  }");
                if (i < sub.Count - 1) sb.AppendLine(",");
                else sb.AppendLine();
            }
            sb.AppendLine("]");

            string batchPath = Path.Combine(outDir, string.Format("batch_{0:D3}.json", b + 1));
            File.WriteAllText(batchPath, sb.ToString(), utf8);
        }

        Console.WriteLine("Создано " + batchCount + " батчей по " + batchSize + " строк в " + outDir);

        StringBuilder summary = new StringBuilder();
        summary.AppendLine("# Манифест батчей перевода (Lord of Mysteries v2.6-RU)\n");
        summary.AppendLine("Всего извлечено строк рантайма: **" + items.Count + "**");
        summary.AppendLine("Размер каждого батча: **" + batchSize + "** строк");
        summary.AppendLine("Количество файлов батчей: **" + batchCount + "**\n");
        summary.AppendLine("| Батч | Файл | Строки с-по | Статус |");
        summary.AppendLine("|---|---|---|---|");
        for (int b = 0; b < batchCount; b++) {
            int start = b * batchSize + 1;
            int end = Math.Min((b + 1) * batchSize, items.Count);
            summary.AppendLine(string.Format("| Батч {0:D3} | `batch_{0:D3}.json` | {1} — {2} | Ожидает перевода |", b + 1, start, end));
        }
        File.WriteAllText(Path.Combine(outDir, "BATCH_MANIFEST.md"), summary.ToString(), utf8);
        Console.WriteLine("Создан BATCH_MANIFEST.md");

        // Copy source code to tools directory as well
        File.Copy(
            @"C:\Users\yapug\.gemini\antigravity\brain\6833aa0c-b0e3-4a5e-b474-d21649c848cd\scratch\FastStringExtractor.cs",
            Path.Combine(root, "tools", "StringExtractor.cs"),
            true
        );
        Console.WriteLine("Скопирован tools/StringExtractor.cs");
    }

    private static string EscapeJson(string s) {
        if (s == null) return "";
        return s.Replace(@"\", @"\\")
                .Replace(@"""", @"\""")
                .Replace("\r", @"\r")
                .Replace("\n", @"\n")
                .Replace("\t", @"\t");
    }
}
