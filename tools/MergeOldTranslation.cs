using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

public class MergeOldTranslation
{
    // Regex to match batch items in JSON
    static readonly Regex ItemRegex = new Regex(
        @"(?<prefix>\{\s*""id""\s*:\s*""(?<id>[^""]+)""\s*,\s*""source_cn""\s*:\s*""(?<cn>(?:\\.|[^""\\])*)""\s*,\s*""ref_en""\s*:\s*""(?<en>(?:\\.|[^""\\])*)""\s*,\s*""target_ru""\s*:\s*"")(?<ru>(?:\\.|[^""\\])*)(?<suffix>""\s*\})",
        RegexOptions.Compiled
    );

    // Validation regexes matching UE5 safety rules from VerifyBatch.ps1
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
    static readonly Regex CyrillicRegex = new Regex(@"[\p{IsCyrillic}]", RegexOptions.Compiled);
    static readonly Regex UIFrameRegex = new Regex(@"^\[UIFrame\s*:", RegexOptions.Compiled);

    public class ReplacementSample
    {
        public string Id { get; set; }
        public string MatchSource { get; set; }
        public string RefEn { get; set; }
        public string OldTranslation { get; set; }
        public string NewTranslation { get; set; }
    }

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
                    default:
                        sb.Append(s[i]);
                        break;
                }
            }
            else
            {
                sb.Append(s[i]);
            }
        }
        return sb.ToString();
    }

    public static string EscapeJson(string s)
    {
        if (s == null) return "";
        return s.Replace(@"\", @"\\")
                .Replace(@"""", @"\""")
                .Replace("\r", @"\r")
                .Replace("\n", @"\n")
                .Replace("\t", @"\t");
    }

    public static bool ValidateTranslation(string refText, string ru, out string reason)
    {
        reason = null;
        if (string.IsNullOrWhiteSpace(ru))
        {
            reason = "Empty or whitespace Russian string";
            return false;
        }

        // 1. BakedText protection: never translate if reference text is empty or marked KeepEmpty
        if (string.IsNullOrWhiteSpace(refText) || refText == "BakedText/KeepEmpty")
        {
            reason = "Reference text is empty or BakedText/KeepEmpty";
            return false;
        }

        // 2. Internal engine diagnostic logs should not be translated
        if (UIFrameRegex.IsMatch(refText) && CyrillicRegex.IsMatch(ru))
        {
            reason = "Internal engine diagnostic log should not be translated";
            return false;
        }

        // 2. UMG RichText tags
        var refTags = TagRegex.Matches(refText);
        var ruTags = TagRegex.Matches(ru);
        var ruTagNames = new HashSet<string>();
        foreach (Match m in ruTags) ruTagNames.Add(m.Groups[1].Value);
        foreach (Match m in refTags)
        {
            if (!ruTagNames.Contains(m.Groups[1].Value))
            {
                reason = "Missing tag <" + m.Groups[1].Value + ">";
                return false;
            }
        }

        int refClose = CloseTagRegex.Matches(refText).Count;
        int ruClose = CloseTagRegex.Matches(ru).Count;
        if (refClose != ruClose)
        {
            reason = string.Format("Closing tag count mismatch: ref={0}, ru={1}", refClose, ruClose);
            return false;
        }

        // 3. Format specifiers %s, %d, %f, etc.
        var refSpecs = new List<string>();
        foreach (Match m in SpecRegex.Matches(refText))
            if (m.Value != "%%") refSpecs.Add(m.Value);

        var ruSpecs = new List<string>();
        foreach (Match m in SpecRegex.Matches(ru))
            if (m.Value != "%%") ruSpecs.Add(m.Value);

        if (refSpecs.Count != ruSpecs.Count)
        {
            reason = string.Format("Specifier count mismatch: ref={0}, ru={1}", refSpecs.Count, ruSpecs.Count);
            return false;
        }

        for (int i = 0; i < refSpecs.Count; i++)
        {
            char refType = refSpecs[i][refSpecs[i].Length - 1];
            char ruType = ruSpecs[i][ruSpecs[i].Length - 1];
            bool refNum = "dfeEgGcxXiou".IndexOf(refType) >= 0;
            bool ruNum = "dfeEgGcxXiou".IndexOf(ruType) >= 0;
            if ((refType == 's' && ruNum) || (refNum && ruType == 's'))
            {
                reason = string.Format("Specifier type mismatch at #{0}: {1} vs {2}", i + 1, refSpecs[i], ruSpecs[i]);
                return false;
            }
        }

        // 4. Positional args {0}, {1}, etc.
        var refPos = PosArgRegex.Matches(refText);
        var ruPos = PosArgRegex.Matches(ru);
        if (refPos.Count != ruPos.Count)
        {
            reason = string.Format("Positional args count mismatch: ref={0}, ru={1}", refPos.Count, ruPos.Count);
            return false;
        }

        // 5. Puzzle markers #CanMove_...#
        int refPuzzles = PuzzleRegex.Matches(refText).Count;
        int ruPuzzles = PuzzleRegex.Matches(ru).Count;
        if (refPuzzles != ruPuzzles)
        {
            reason = "Puzzle marker count mismatch";
            return false;
        }

        // 6. Inline images <img .../>
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

        // 7. Technical asset paths
        foreach (Match m in PathRegex.Matches(refText))
        {
            if (!ru.Contains(m.Value))
            {
                reason = "Missing asset path " + m.Value;
                return false;
            }
        }

        // 8. Formula macros and CheckStar tokens
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

    public static Dictionary<string, string> LoadMasterDictionary(string luaPath)
    {
        var dict = new Dictionary<string, string>(265000, StringComparer.Ordinal);
        var sw = System.Diagnostics.Stopwatch.StartNew();

        using (var sr = new StreamReader(luaPath, Encoding.UTF8))
        {
            string line;
            while ((line = sr.ReadLine()) != null)
            {
                line = line.Trim();
                if (!line.StartsWith("[\"") || !line.EndsWith("\",")) continue;
                int mid = line.IndexOf("\"] = \"");
                if (mid < 0) continue;
                string rawKey = line.Substring(2, mid - 2);
                string rawVal = line.Substring(mid + 6, line.Length - 6 - mid - 2);
                dict[Unescape(rawKey)] = Unescape(rawVal);
            }
        }

        sw.Stop();
        Console.WriteLine(string.Format("Master dictionary loaded: {0:N0} entries in {1:N0} ms", dict.Count, sw.ElapsedMilliseconds));
        return dict;
    }

    public static void Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;

        bool apply = false;
        int targetBatch = 0;
        int startBatch = 6;
        int endBatch = 27;
        int sampleCount = 10;
        string luaPath = @"D:\gameDev\translate lotm\RuntimeTextRussian.lua";
        string batchesDir = @"source\translation_batches";

        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            if (arg.Equals("-Apply", StringComparison.OrdinalIgnoreCase) || arg.Equals("/Apply", StringComparison.OrdinalIgnoreCase))
            {
                apply = true;
            }
            else if (arg.Equals("-Batch", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                int.TryParse(args[++i], out targetBatch);
            }
            else if (arg.Equals("-StartBatch", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                int.TryParse(args[++i], out startBatch);
            }
            else if (arg.Equals("-EndBatch", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                int.TryParse(args[++i], out endBatch);
            }
            else if (arg.Equals("-Samples", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                int.TryParse(args[++i], out sampleCount);
            }
            else if (arg.Equals("-LuaPath", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                luaPath = args[++i];
            }
            else if (arg.Equals("-BatchesDir", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
            {
                batchesDir = args[++i];
            }
            else if (Directory.Exists(arg))
            {
                batchesDir = arg;
            }
            else if (File.Exists(arg) && arg.EndsWith(".lua", StringComparison.OrdinalIgnoreCase))
            {
                luaPath = arg;
            }
        }

        Console.WriteLine("===============================================================================");
        Console.WriteLine("  AbsoluteRU - Merge Old Master Translation Tool (v1.0)");
        Console.WriteLine("===============================================================================");
        Console.WriteLine("Mode:         " + (apply ? "APPLY (Writing changes to JSON files)" : "DRY-RUN (Preview only, no file modifications)"));
        Console.WriteLine("Master Lua:   " + luaPath);
        Console.WriteLine("Batches Dir:  " + batchesDir);

        if (targetBatch > 0)
        {
            startBatch = targetBatch;
            endBatch = targetBatch;
            Console.WriteLine("Target Batch: " + string.Format("batch_{0:D3}.json", targetBatch));
        }
        else
        {
            Console.WriteLine(string.Format("Batch Range:  batch_{0:D3}.json - batch_{1:D3}.json (Batches 001-005 protected)", startBatch, endBatch));
        }
        Console.WriteLine("-------------------------------------------------------------------------------");

        if (!File.Exists(luaPath))
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("ERROR: Master translation file not found: " + luaPath);
            Console.ResetColor();
            return;
        }

        if (!Directory.Exists(batchesDir))
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("ERROR: Batches directory not found: " + batchesDir);
            Console.ResetColor();
            return;
        }

        var dict = LoadMasterDictionary(luaPath);

        int totalItemsScanned = 0;
        int totalUpdated = 0;
        int totalAlreadySame = 0;
        int totalValidationFailed = 0;
        int totalNotFound = 0;
        int totalMatchedCn = 0;
        int totalMatchedEn = 0;
        int totalFilesModified = 0;

        var allSamples = new List<ReplacementSample>();

        for (int b = startBatch; b <= endBatch; b++)
        {
            string fileName = string.Format("batch_{0:D3}.json", b);
            string filePath = Path.Combine(batchesDir, fileName);

            if (!File.Exists(filePath))
            {
                Console.WriteLine(string.Format("  Skipping {0} (file not found)", fileName));
                continue;
            }

            string originalContent = File.ReadAllText(filePath, Encoding.UTF8);

            int fileItems = 0;
            int fileUpdated = 0;
            int fileAlreadySame = 0;
            int fileValidationFailed = 0;
            int fileNotFound = 0;
            int fileMatchedCn = 0;
            int fileMatchedEn = 0;

            string updatedContent = ItemRegex.Replace(originalContent, match =>
            {
                fileItems++;
                string prefix = match.Groups["prefix"].Value;
                string id = match.Groups["id"].Value;
                string cn = Unescape(match.Groups["cn"].Value);
                string en = Unescape(match.Groups["en"].Value);
                string curRu = Unescape(match.Groups["ru"].Value);
                string suffix = match.Groups["suffix"].Value;

                // BakedText & empty reference guard: if English reference or current translation is intentionally empty, preserve it
                if (string.IsNullOrWhiteSpace(en) || en == "BakedText/KeepEmpty" || string.IsNullOrWhiteSpace(curRu) || curRu == "BakedText/KeepEmpty")
                {
                    fileAlreadySame++;
                    return match.Value;
                }

                string candidateRu = null;
                string matchSource = null;

                if (dict.TryGetValue(cn, out candidateRu))
                {
                    matchSource = "CN";
                    fileMatchedCn++;
                }
                else if (!string.IsNullOrEmpty(en) && dict.TryGetValue(en, out candidateRu))
                {
                    matchSource = "EN";
                    fileMatchedEn++;
                }

                if (candidateRu == null)
                {
                    fileNotFound++;
                    return match.Value;
                }

                string refText = !string.IsNullOrEmpty(cn) ? cn : en;
                string reason;
                if (!ValidateTranslation(refText, candidateRu, out reason))
                {
                    fileValidationFailed++;
                    return match.Value;
                }

                if (candidateRu == curRu)
                {
                    fileAlreadySame++;
                    return match.Value;
                }

                fileUpdated++;
                if (allSamples.Count < sampleCount)
                {
                    allSamples.Add(new ReplacementSample
                    {
                        Id = id,
                        MatchSource = matchSource,
                        RefEn = en,
                        OldTranslation = curRu,
                        NewTranslation = candidateRu
                    });
                }

                return prefix + EscapeJson(candidateRu) + suffix;
            });

            totalItemsScanned += fileItems;
            totalUpdated += fileUpdated;
            totalAlreadySame += fileAlreadySame;
            totalValidationFailed += fileValidationFailed;
            totalNotFound += fileNotFound;
            totalMatchedCn += fileMatchedCn;
            totalMatchedEn += fileMatchedEn;

            Console.WriteLine(string.Format("  {0,-16} : Total: {1,5} | Updated: {2,5} | Already Same: {3,4} | Rejected: {4,3} | Not Found: {5,4} (CN: {6,5}, EN: {7,3})",
                fileName, fileItems, fileUpdated, fileAlreadySame, fileValidationFailed, fileNotFound, fileMatchedCn, fileMatchedEn));

            if (fileUpdated > 0 && apply)
            {
                File.WriteAllText(filePath, updatedContent, new UTF8Encoding(false));
                totalFilesModified++;
            }
        }

        Console.WriteLine("-------------------------------------------------------------------------------");
        Console.WriteLine("Summary Statistics:");
        Console.WriteLine("  Total strings scanned:     " + totalItemsScanned);
        Console.WriteLine("  Total strings updated:     " + totalUpdated);
        Console.WriteLine("  Total already identical:   " + totalAlreadySame);
        Console.WriteLine("  Total rejected by rules:   " + totalValidationFailed + " (kept existing safe translations)");
        Console.WriteLine("  Total not found in master: " + totalNotFound);
        Console.WriteLine("  Total matched via CN:      " + totalMatchedCn);
        Console.WriteLine("  Total matched via EN:      " + totalMatchedEn);
        if (apply)
        {
            Console.WriteLine("  Files saved to disk:       " + totalFilesModified);
        }
        Console.WriteLine("-------------------------------------------------------------------------------");

        if (allSamples.Count > 0)
        {
            Console.WriteLine("\nReplacement Samples Preview:");
            Console.WriteLine("===============================================================================");
            for (int i = 0; i < allSamples.Count; i++)
            {
                var s = allSamples[i];
                Console.WriteLine(string.Format("[Sample #{0}] ID: {1} (Matched by {2})", i + 1, s.Id, s.MatchSource));
                Console.WriteLine("  EN Ref: " + s.RefEn);
                Console.WriteLine("  WAS:    " + s.OldTranslation);
                Console.WriteLine("  NOW:    " + s.NewTranslation);
                Console.WriteLine("-------------------------------------------------------------------------------");
            }
        }

        if (!apply)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("\n[DRY-RUN COMPLETE] No files were modified. To write changes to disk, pass -Apply.");
            Console.ResetColor();
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("\n[SUCCESS] Batch files successfully updated with quality master translation!");
            Console.ResetColor();
        }
    }
}
