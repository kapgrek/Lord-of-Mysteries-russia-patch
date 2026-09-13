using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

public class MergeTranslated
{
    static readonly Regex ItemRegex = new Regex(
        @"(?<prefix>\{\s*""id""\s*:\s*""(?<id>[^""]+)""\s*,\s*""source_cn""\s*:\s*""(?<cn>(?:\\.|[^""\\])*)""\s*,\s*""ref_en""\s*:\s*""(?<en>(?:\\.|[^""\\])*)""\s*,\s*""target_ru""\s*:\s*"")(?<ru>(?:\\.|[^""\\])*)(?<suffix>""\s*\})",
        RegexOptions.Compiled
    );

    static readonly Regex TagRegex = new Regex(@"<(?!\/)([A-Za-z0-9_]+)[^>]*>", RegexOptions.Compiled);
    static readonly Regex CloseTagRegex = new Regex(@"<\/>", RegexOptions.Compiled);
    static readonly Regex SpecRegex = new Regex(@"%[-+0-9\.]*[sdfeEgGcxX]", RegexOptions.Compiled);
    static readonly Regex PosArgRegex = new Regex(@"\{[0-9]+\}", RegexOptions.Compiled);
    static readonly Regex PuzzleRegex = new Regex(@"#CanMove_[^#]+#", RegexOptions.Compiled);
    static readonly Regex ImgTagRegex = new Regex(@"<[iI]mg\s+[^>]*\/?>", RegexOptions.Compiled);
    static readonly Regex PathRegex = new Regex(@"(?:Texture2D''[^'']+''|/Game/[^\s''""]+)", RegexOptions.Compiled);
    static readonly Regex MacroRegex = new Regex(@"(?:spellfielddisc|buffdisc|skilldisc|auradisc|passivedisc|trapdisc|bulletdisc|spellagent|spellfieldname|buffname|skillname|auraname|passivename|trapname)\s*\(", RegexOptions.Compiled);
    static readonly Regex MacroCapRegex = new Regex(@"(?:Spellfielddisc|Buffdisc|Skilldisc|Auradisc|Passivedisc|Trapdisc|Bulletdisc|Spellagent|Spellfieldname|Buffname|Skillname|Auraname|Passivename|Trapname)\s*\(", RegexOptions.Compiled);
    static readonly Regex StarRegex = new Regex(@"\{CheckStar\(", RegexOptions.Compiled);
    static readonly Regex StarBrokenRegex = new Regex(@"\{?\s*C(?:heckSta\s+r|heckS\s+tar|h\s+eckStar|heckStar\s*\(Type=\\""seal\""\)|heckStar\s*\(Type=\\""sealed\""[^}]*?\s+[=,])", RegexOptions.Compiled);

    public static string Unescape(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        var sb = new StringBuilder(s.Length);
        for (int i = 0; i < s.Length; i++)
        {
            if (s[i] == '\\' && i + 1 < s.Length)
            {
                char next = s[i + 1];
                switch (next)
                {
                    case 'n': sb.Append('\n'); i++; break;
                    case 'r': sb.Append('\r'); i++; break;
                    case 't': sb.Append('\t'); i++; break;
                    case '"': sb.Append('"'); i++; break;
                    case '\\': sb.Append('\\'); i++; break;
                    case '/': sb.Append('/'); i++; break;
                    default: sb.Append(s[i]); break;
                }
            }
            else sb.Append(s[i]);
        }
        return sb.ToString();
    }

    public static string EscapeJson(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        var sb = new StringBuilder(s.Length + 16);
        for (int i = 0; i < s.Length; i++)
        {
            char c = s[i];
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default: sb.Append(c); break;
            }
        }
        return sb.ToString();
    }

    public static bool ValidateTranslation(string refText, string ru, out string reason)
    {
        reason = null;
        if (string.IsNullOrWhiteSpace(ru)) { reason = "Empty translation"; return false; }
        if (string.IsNullOrWhiteSpace(refText) || refText == "BakedText/KeepEmpty") { reason = "Empty reference"; return false; }

        var refTags = TagRegex.Matches(refText);
        var ruTags = TagRegex.Matches(ru);
        var refTagNames = new HashSet<string>();
        foreach (Match m in refTags) refTagNames.Add(m.Groups[1].Value);
        var ruTagNames = new HashSet<string>();
        foreach (Match m in ruTags) ruTagNames.Add(m.Groups[1].Value);
        foreach (var tag in refTagNames)
        {
            if (!ruTagNames.Contains(tag)) { reason = "Missing tag <" + tag + ">"; return false; }
        }

        int refClose = CloseTagRegex.Matches(refText).Count;
        int ruClose = CloseTagRegex.Matches(ru).Count;
        if (refClose != ruClose)
        {
            reason = string.Format("Closing tag count mismatch (ref: {0}, ru: {1})", refClose, ruClose);
            return false;
        }

        var refSpecs = new List<string>();
        foreach (Match m in SpecRegex.Matches(refText)) if (m.Value != "%%") refSpecs.Add(m.Value);
        var ruSpecs = new List<string>();
        foreach (Match m in SpecRegex.Matches(ru)) if (m.Value != "%%") ruSpecs.Add(m.Value);
        if (refSpecs.Count != ruSpecs.Count)
        {
            reason = string.Format("Specifier count mismatch (ref: {0}, ru: {1})", refSpecs.Count, ruSpecs.Count);
            return false;
        }
        for (int i = 0; i < refSpecs.Count; i++)
        {
            char refType = refSpecs[i][refSpecs[i].Length - 1];
            char ruType = ruSpecs[i][ruSpecs[i].Length - 1];
            bool refIsNumeric = "dfeEgGcxXiou".IndexOf(refType) >= 0;
            bool ruIsNumeric = "dfeEgGcxXiou".IndexOf(ruType) >= 0;
            if ((refType == 's' && ruIsNumeric) || (refIsNumeric && ruType == 's'))
            {
                reason = string.Format("Specifier #{0} type incompatible: {1} vs {2}", i + 1, refSpecs[i], ruSpecs[i]);
                return false;
            }
        }

        int refPos = PosArgRegex.Matches(refText).Count;
        int ruPos = PosArgRegex.Matches(ru).Count;
        if (refPos != ruPos)
        {
            reason = string.Format("Positional arg count mismatch (ref: {0}, ru: {1})", refPos, ruPos);
            return false;
        }

        if (PuzzleRegex.Matches(refText).Count != PuzzleRegex.Matches(ru).Count)
        {
            reason = "Letter puzzle marker mismatch";
            return false;
        }

        var refImgs = ImgTagRegex.Matches(refText);
        var ruImgs = ImgTagRegex.Matches(ru);
        if (refImgs.Count != ruImgs.Count)
        {
            reason = "Image tag count mismatch";
            return false;
        }
        for (int idx = 0; idx < refImgs.Count; idx++)
        {
            if (refImgs[idx].Value != ruImgs[idx].Value)
            {
                reason = "Image tag attributes modified";
                return false;
            }
        }

        foreach (Match m in PathRegex.Matches(refText))
        {
            if (!ru.Contains(m.Value))
            {
                reason = "Missing asset path " + m.Value;
                return false;
            }
        }

        if (MacroRegex.Matches(refText).Count != MacroRegex.Matches(ru).Count)
        {
            reason = "Formula macro count mismatch";
            return false;
        }
        if (MacroCapRegex.IsMatch(ru))
        {
            reason = "Capitalized formula macro found in RU";
            return false;
        }
        if (StarRegex.Matches(refText).Count != StarRegex.Matches(ru).Count)
        {
            reason = "CheckStar token count mismatch";
            return false;
        }
        if (StarBrokenRegex.IsMatch(ru))
        {
            reason = "Broken CheckStar token found in RU";
            return false;
        }

        return true;
    }

    public class ChunkEntry
    {
        public string id;
        public int batch;
        public string source_cn;
        public string ref_en;
        public string current_ru;
        public string target_ru;
    }

    public static void Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        string root = @"d:\gameDev\AbsoluteRU";
        string batchesDir = Path.Combine(root, "source", "translation_batches");
        string translatedDir = Path.Combine(root, "temp", "translated");

        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("================================================================");
        Console.WriteLine("  AbsoluteRU — Сборщик и слияние переведённых чанков в батчи");
        Console.WriteLine("================================================================");
        Console.ResetColor();

        if (!Directory.Exists(translatedDir))
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("Папка с переведёнными чанками не найдена: " + translatedDir);
            Console.ResetColor();
            return;
        }

        string[] chunkFiles = Directory.GetFiles(translatedDir, "chunk_*_translated.json");
        Array.Sort(chunkFiles);
        Console.WriteLine("Найдено файлов чанков: " + chunkFiles.Length);

        // Map: batchNumber -> (id -> ChunkEntry)
        var batchEntries = new Dictionary<int, Dictionary<string, ChunkEntry>>();
        int totalFound = 0;
        int totalValid = 0;
        int totalInvalid = 0;

        // Simple JSON extractor for translated chunk entries
        var entryRegex = new Regex(
            @"\{\s*""id""\s*:\s*""(?<id>[^""]+)""\s*,\s*""batch""\s*:\s*(?<batch>\d+)\s*," +
            @"(?:[^}]*?)""source_cn""\s*:\s*""(?<cn>(?:\\.|[^""\\])*)""\s*,\s*""ref_en""\s*:\s*""(?<en>(?:\\.|[^""\\])*)""\s*," +
            @"(?:[^}]*?)""target_ru""\s*:\s*""(?<ru>(?:\\.|[^""\\])*)""\s*\}",
            RegexOptions.Compiled
        );

        foreach (string cf in chunkFiles)
        {
            string content = File.ReadAllText(cf, Encoding.UTF8);
            var matches = entryRegex.Matches(content);
            int inChunk = 0;
            foreach (Match m in matches)
            {
                string id = m.Groups["id"].Value;
                int batch = int.Parse(m.Groups["batch"].Value);
                string cn = Unescape(m.Groups["cn"].Value);
                string en = Unescape(m.Groups["en"].Value);
                string ru = Unescape(m.Groups["ru"].Value);

                if (string.IsNullOrWhiteSpace(ru)) continue;

                totalFound++;
                inChunk++;

                string refText = !string.IsNullOrEmpty(cn) ? cn : en;
                string reason;
                if (!ValidateTranslation(refText, ru, out reason))
                {
                    // If validation failed against CN, try against EN
                    if (!string.IsNullOrEmpty(en) && ValidateTranslation(en, ru, out reason))
                    {
                        // Valid against EN
                    }
                    else
                    {
                        totalInvalid++;
                        continue;
                    }
                }

                totalValid++;
                if (!batchEntries.ContainsKey(batch))
                    batchEntries[batch] = new Dictionary<string, ChunkEntry>(StringComparer.Ordinal);

                batchEntries[batch][id] = new ChunkEntry { id = id, batch = batch, source_cn = cn, ref_en = en, target_ru = ru };
            }
            Console.WriteLine(string.Format("  {0,-30} : {1} валидных переводов", Path.GetFileName(cf), inChunk));
        }

        Console.WriteLine();
        Console.WriteLine(string.Format("Всего найдено target_ru: {0} | Валидных: {1} | Отклонено валидатором: {2}", totalFound, totalValid, totalInvalid));
        Console.WriteLine("----------------------------------------------------------------");

        int totalBatchesModified = 0;
        int totalStringsUpdated = 0;

        foreach (var kvp in batchEntries)
        {
            int bNum = kvp.Key;
            var transMap = kvp.Value;

            string bFile = Path.Combine(batchesDir, string.Format("batch_{0:D3}.json", bNum));
            if (!File.Exists(bFile))
            {
                Console.WriteLine(string.Format("  Батч {0:D3} не найден, пропуск!", bNum));
                continue;
            }

            string original = File.ReadAllText(bFile, Encoding.UTF8);
            int updatedInFile = 0;

            string updated = ItemRegex.Replace(original, m =>
            {
                string prefix = m.Groups["prefix"].Value;
                string id = m.Groups["id"].Value;
                string suffix = m.Groups["suffix"].Value;

                ChunkEntry entry;
                if (transMap.TryGetValue(id, out entry))
                {
                    updatedInFile++;
                    return prefix + EscapeJson(entry.target_ru) + suffix;
                }
                return m.Value;
            });

            if (updatedInFile > 0)
            {
                File.WriteAllText(bFile, updated, new UTF8Encoding(false));
                totalBatchesModified++;
                totalStringsUpdated += updatedInFile;
                Console.WriteLine(string.Format("  [OK] batch_{0:D3}.json : обновлено {1} строк", bNum, updatedInFile));
            }
        }

        Console.WriteLine("----------------------------------------------------------------");
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine(string.Format("ИТОГО: Обновлено {0} строк в {1} батчах!", totalStringsUpdated, totalBatchesModified));
        Console.ResetColor();

        // Run ShardCompiler
        string shardCompilerExe = Path.Combine(root, "tools", "ShardCompiler.exe");
        if (File.Exists(shardCompilerExe))
        {
            Console.WriteLine();
            Console.WriteLine("Запуск ShardCompiler для обновления шардов...");
            var psi = new System.Diagnostics.ProcessStartInfo(shardCompilerExe);
            psi.WorkingDirectory = Path.Combine(root, "tools");
            psi.UseShellExecute = false;
            var proc = System.Diagnostics.Process.Start(psi);
            proc.WaitForExit();
            Console.WriteLine("ShardCompiler завершил работу с кодом " + proc.ExitCode);
        }
    }
}
