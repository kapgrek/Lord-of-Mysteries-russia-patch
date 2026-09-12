using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

public class FixCapitalization {
    static readonly Regex ItemRegex = new Regex(
        @"(\{\s*""id""\s*:\s*""(?<id>[^""]+)""\s*,\s*""source_cn""\s*:\s*""(?<cn>(?:\\.|[^""\\])*)""\s*,\s*""ref_en""\s*:\s*""(?<en>(?:\\.|[^""\\])*)""\s*,\s*""target_ru""\s*:\s*"")(?<ru>(?:\\.|[^""\\])*)(""\s*\})",
        RegexOptions.Compiled
    );

    static readonly Dictionary<string, string> TermReplacements = new Dictionary<string, string>() {
        // Cities & Geography
        { @"(?<!\p{L})тинген(а|у|ом|е)?(?!\p{L})", "Тинген$1" },
        { @"(?<!\p{L})бэкланд(а|у|ом|е)?(?!\p{L})", "Бэкланд$1" },
        { @"(?<!\p{L})байам(а|у|ом|е)?(?!\p{L})", "Байам$1" },
        { @"(?<!\p{L})лоэн(а|у|ом|е)?(?!\p{L})", "Лоэн$1" },
        { @"(?<!\p{L})интис(а|у|ом|е)?(?!\p{L})", "Интис$1" },
        { @"(?<!\p{L})фейсак(а|у|ом|е)?(?!\p{L})", "Фейсак$1" },
        { @"(?<!\p{L})рунбург(а|у|ом|е)?(?!\p{L})", "Рунбург$1" },

        // Characters
        { @"(?<!\p{L})амон(а|у|ом|е)?(?!\p{L})", "Амон$1" },
        { @"(?<!\p{L})адам(а|у|ом|е)?(?!\p{L})", "Адам$1" },
        { @"(?<!\p{L})леонард(а|у|ом|е)?(?!\p{L})", "Леонард$1" },
        { @"(?<!\p{L})клейн(а|у|ом|е)?(?!\p{L})", "Клейн$1" },
        { @"(?<!\p{L})моретти(?!\p{L})", "Моретти" },
        { @"(?<!\p{L})одри(?!\p{L})", "Одри" },
        { @"(?<!\p{L})дэйли(?!\p{L})", "Дэйли" },
        { @"(?<!\p{L})дайли(?!\p{L})", "Дайли" },

        // Factions & Organizations
        { @"(?<!\p{L})ночные ястребы(?!\p{L})", "Ночные Ястребы" },
        { @"(?<!\p{L})ночных ястребов(?!\p{L})", "Ночных Ястребов" },
        { @"(?<!\p{L})ночным ястребам(?!\p{L})", "Ночным Ястребам" },
        { @"(?<!\p{L})ночными ястребами(?!\p{L})", "Ночными Ястребами" },
        { @"(?<!\p{L})ночных ястребах(?!\p{L})", "Ночных Ястребах" },
        { @"(?<!\p{L})ночной ястреб(?!\p{L})", "Ночной Ястреб" },
        { @"(?<!\p{L})ночного ястреба(?!\p{L})", "Ночного Ястреба" },
        { @"(?<!\p{L})ночному ястребу(?!\p{L})", "Ночному Ястребу" },
        { @"(?<!\p{L})ночным ястребом(?!\p{L})", "Ночным Ястребом" },
        { @"(?<!\p{L})ночном ястребе(?!\p{L})", "Ночном Ястребе" },

        { @"(?<!\p{L})клуб таро(?!\p{L})", "Клуб Таро" },
        { @"(?<!\p{L})клуба таро(?!\p{L})", "Клуба Таро" },
        { @"(?<!\p{L})клубу таро(?!\p{L})", "Клубу Таро" },
        { @"(?<!\p{L})клубом таро(?!\p{L})", "Клубом Таро" },
        { @"(?<!\p{L})клубе таро(?!\p{L})", "Клубе Таро" },

        { @"(?<!\p{L})орден авроры(?!\p{L})", "Орден Авроры" },
        { @"(?<!\p{L})ордена авроры(?!\p{L})", "Ордена Авроры" },
        { @"(?<!\p{L})ордену авроры(?!\p{L})", "Ордену Авроры" },
        { @"(?<!\p{L})орденом авроры(?!\p{L})", "Орденом Авроры" },
        { @"(?<!\p{L})ордене авроры(?!\p{L})", "Ордене Авроры" },

        { @"(?<!\p{L})тайный орден(?!\p{L})", "Тайный Орден" },
        { @"(?<!\p{L})тайного ордена(?!\p{L})", "Тайного Ордена" },
        { @"(?<!\p{L})тайному ордену(?!\p{L})", "Тайному Ордену" },
        { @"(?<!\p{L})тайным орденом(?!\p{L})", "Тайным Орденом" },
        { @"(?<!\p{L})тайном ордене(?!\p{L})", "Тайном Ордене" },

        // LOTM Core Concepts
        { @"(?<!\p{L})запечатанный артефакт(?!\p{L})", "Запечатанный Артефакт" },
        { @"(?<!\p{L})запечатанного артефакта(?!\p{L})", "Запечатанного Артефакта" },
        { @"(?<!\p{L})запечатанному артефакту(?!\p{L})", "Запечатанному Артефакту" },
        { @"(?<!\p{L})запечатанным артефактом(?!\p{L})", "Запечатанным Артефактом" },
        { @"(?<!\p{L})запечатанном артефакте(?!\p{L})", "Запечатанном Артефакте" },
        { @"(?<!\p{L})запечатанные артефакты(?!\p{L})", "Запечатанные Артефакты" },
        { @"(?<!\p{L})запечатанных артефактов(?!\p{L})", "Запечатанных Артефактов" },
        { @"(?<!\p{L})запечатанным артефактам(?!\p{L})", "Запечатанным Артефактам" },
        { @"(?<!\p{L})запечатанными артефактами(?!\p{L})", "Запечатанными Артефактами" },
        { @"(?<!\p{L})запечатанных артефактах(?!\p{L})", "Запечатанных Артефактах" },

        { @"(?<!\p{L})мир духов(?!\p{L})", "Мир Духов" },
        { @"(?<!\p{L})мира духов(?!\p{L})", "Мира Духов" },
        { @"(?<!\p{L})миру духов(?!\p{L})", "Миру Духов" },
        { @"(?<!\p{L})миром духов(?!\p{L})", "Миром Духов" },
        { @"(?<!\p{L})мире духов(?!\p{L})", "Мире Духов" },

        { @"(?<!\p{L})потеря контроля(?!\p{L})", "Потеря Контроля" },
        { @"(?<!\p{L})потери контроля(?!\p{L})", "Потери Контроля" },
        { @"(?<!\p{L})потере контроля(?!\p{L})", "Потере Контроля" },
        { @"(?<!\p{L})потерю контроля(?!\p{L})", "Потерю Контроля" },
        { @"(?<!\p{L})потерей контроля(?!\p{L})", "Потерей Контроля" },

        { @"(?<!\p{L})метод действия(?!\p{L})", "Метод Действия" },
        { @"(?<!\p{L})метода действия(?!\p{L})", "Метода Действия" },
        { @"(?<!\p{L})методу действия(?!\p{L})", "Методу Действия" },
        { @"(?<!\p{L})методом действия(?!\p{L})", "Методом Действия" },
        { @"(?<!\p{L})методе действия(?!\p{L})", "Методе Действия" },

        { @"(?<!\p{L})потусторонняя характеристика(?!\p{L})", "Потусторонняя Характеристика" },
        { @"(?<!\p{L})потусторонней характеристики(?!\p{L})", "Потусторонней Характеристики" },
        { @"(?<!\p{L})потусторонней характеристике(?!\p{L})", "Потусторонней Характеристике" },
        { @"(?<!\p{L})потустороннюю характеристику(?!\p{L})", "Потустороннюю Характеристику" },
        { @"(?<!\p{L})потусторонней характеристикой(?!\p{L})", "Потусторонней Характеристикой" },
        { @"(?<!\p{L})потусторонние характеристики(?!\p{L})", "Потусторонние Характеристики" },
        { @"(?<!\p{L})потусторонних характеристик(?!\p{L})", "Потусторонних Характеристик" },

        // Pathways
        { @"(?<!\p{L})путь шута(?!\p{L})", "Путь Шута" },
        { @"(?<!\p{L})путь двери(?!\p{L})", "Путь Двери" },
        { @"(?<!\p{L})путь ошибки(?!\p{L})", "Путь Ошибки" },
        { @"(?<!\p{L})путь зрителя(?!\p{L})", "Путь Зрителя" },
        { @"(?<!\p{L})путь моряка(?!\p{L})", "Путь Моряка" },
        { @"(?<!\p{L})путь солнца(?!\p{L})", "Путь Солнца" },
        { @"(?<!\p{L})путь читателя(?!\p{L})", "Путь Читателя" },
        { @"(?<!\p{L})путь бессонного(?!\p{L})", "Путь Бессонного" },
        { @"(?<!\p{L})путь смерти(?!\p{L})", "Путь Смерти" },
        { @"(?<!\p{L})путь воина(?!\p{L})", "Путь Воина" },
        { @"(?<!\p{L})путь охотника(?!\p{L})", "Путь Охотника" },
        { @"(?<!\p{L})путь убийцы(?!\p{L})", "Путь Убийцы" },

        // Sequences e.g. "последовательность 7", "последовательности 9"
        { @"(?<!\p{L})последовательност(ь|и|ью)\s+([0-9])(?!\p{L})", "Последовательност$1 $2" }
    };

    static readonly List<KeyValuePair<Regex, string>> CompiledReplacements = new List<KeyValuePair<Regex, string>>();

    static FixCapitalization() {
        foreach (var kvp in TermReplacements) {
            CompiledReplacements.Add(new KeyValuePair<Regex, string>(new Regex(kvp.Key, RegexOptions.Compiled), kvp.Value));
        }
    }

    public static int FindFirstLetterIdx(string s) {
        int i = 0;
        int len = s.Length;
        while (i < len) {
            // Skip actual whitespace
            if (char.IsWhiteSpace(s[i])) { i++; continue; }

            // Skip escaped whitespace \n, \r, \t
            if (s[i] == '\\' && i + 1 < len) {
                char next = s[i + 1];
                if (next == 'n' || next == 'r' || next == 't') {
                    i += 2;
                    continue;
                }
                if (next == '"' || next == '\'') {
                    i += 2;
                    continue;
                }
            }

            // Skip tags <...>
            if (s[i] == '<') {
                int closeTag = s.IndexOf('>', i);
                if (closeTag >= 0) {
                    i = closeTag + 1;
                    continue;
                }
            }

            // Skip leading punctuation & brackets
            char c = s[i];
            if (c == '"' || c == '\'' || c == '«' || c == '»' || c == '„' || c == '“' || c == '”' ||
                c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}' ||
                c == '【' || c == '】' || c == '—' || c == '–' || c == '-' || c == '*' ||
                c == '#' || c == '~' || c == '·' || c == '.' || c == ':') {
                i++;
                continue;
            }

            // If format specifier like %s, %d - stop, do not capitalize!
            if (c == '%' && i + 1 < len) {
                return -1;
            }

            if (char.IsLetter(c)) {
                return i;
            }

            // Digit or other symbol (e.g. "1st floor") -> break
            break;
        }
        return -1;
    }

    public static string FixStartCapitalization(string ru, string en) {
        if (string.IsNullOrWhiteSpace(ru) || string.IsNullOrWhiteSpace(en)) return ru;
        if (ru.StartsWith("Texture2D'") || ru.StartsWith("/Game/") || ru.StartsWith("[UIFrame")) return ru;

        int enFirstLetterIdx = FindFirstLetterIdx(en);
        if (enFirstLetterIdx < 0 || !char.IsUpper(en[enFirstLetterIdx])) {
            return ru;
        }

        int ruFirstLetterIdx = FindFirstLetterIdx(ru);
        if (ruFirstLetterIdx < 0) return ru;

        // Ensure not preceded by %
        if (ruFirstLetterIdx > 0 && ru[ruFirstLetterIdx - 1] == '%') return ru;

        if (char.IsLower(ru[ruFirstLetterIdx])) {
            char upperChar = char.ToUpper(ru[ruFirstLetterIdx]);
            return ru.Substring(0, ruFirstLetterIdx) + upperChar + ru.Substring(ruFirstLetterIdx + 1);
        }

        return ru;
    }

    public static string FixTerms(string ru) {
        if (string.IsNullOrWhiteSpace(ru)) return ru;
        foreach (var r in CompiledReplacements) {
            ru = r.Key.Replace(ru, r.Value);
        }
        return ru;
    }

    public static void Main(string[] args) {
        Console.OutputEncoding = Encoding.UTF8;

        bool apply = false;
        int targetBatch = 0;
        string batchesDir = @"source\translation_batches";

        for (int a = 0; a < args.Length; a++) {
            if (args[a].Equals("-Apply", StringComparison.OrdinalIgnoreCase) || args[a].Equals("/Apply", StringComparison.OrdinalIgnoreCase)) {
                apply = true;
            } else if (args[a].Equals("-Batch", StringComparison.OrdinalIgnoreCase) && a + 1 < args.Length) {
                int.TryParse(args[++a], out targetBatch);
            } else if (Directory.Exists(args[a])) {
                batchesDir = args[a];
            }
        }

        Console.WriteLine("===================================================================");
        Console.WriteLine("  AbsoluteRU - Capitalization & Lore Term Fixer (v2.6)");
        Console.WriteLine("===================================================================");
        Console.WriteLine("Mode: " + (apply ? "APPLY (writing changes to disk)" : "DRY-RUN (preview only, no disk writes)"));
        Console.WriteLine("Batches Directory: " + batchesDir);
        if (targetBatch > 0) Console.WriteLine("Target Batch: " + targetBatch);

        string searchPattern = targetBatch > 0 ? string.Format("batch_{0:D3}.json", targetBatch) : "batch_*.json";
        string[] files = Directory.GetFiles(batchesDir, searchPattern);
        Array.Sort(files);

        Console.WriteLine("Found batch files: " + files.Length);

        int totalStrings = 0;
        int totalStartFixed = 0;
        int totalTermsFixed = 0;
        int totalFilesModified = 0;

        foreach (string file in files) {
            string fileName = Path.GetFileName(file);
            string content = File.ReadAllText(file, Encoding.UTF8);

            int fileStartFixed = 0;
            int fileTermsFixed = 0;

            string newContent = ItemRegex.Replace(content, match => {
                totalStrings++;
                string prefix = match.Groups[1].Value;
                string ru = match.Groups["ru"].Value;
                string suffix = match.Groups[3].Value;
                string en = match.Groups["en"].Value;

                if (string.IsNullOrEmpty(ru)) return match.Value;

                string fixedStart = FixStartCapitalization(ru, en);
                if (fixedStart != ru) fileStartFixed++;

                string fixedAll = FixTerms(fixedStart);
                if (fixedAll != fixedStart) fileTermsFixed++;

                if (fixedAll != ru) {
                    return prefix + fixedAll + suffix;
                }
                return match.Value;
            });

            if (fileStartFixed > 0 || fileTermsFixed > 0) {
                totalFilesModified++;
                totalStartFixed += fileStartFixed;
                totalTermsFixed += fileTermsFixed;

                Console.WriteLine(string.Format("  {0,-16} : Start caps fixed: {1,4}, Terms fixed: {2,3}", fileName, fileStartFixed, fileTermsFixed));

                if (apply) {
                    File.WriteAllText(file, newContent, new UTF8Encoding(false));
                }
            }
        }

        Console.WriteLine("-------------------------------------------------------------------");
        Console.WriteLine("Total strings scanned:       " + totalStrings);
        Console.WriteLine("Total start caps fixed:      " + totalStartFixed);
        Console.WriteLine("Total lore terms fixed:      " + totalTermsFixed);
        Console.WriteLine("Files modified:              " + totalFilesModified + " / " + files.Length);
        Console.WriteLine("-------------------------------------------------------------------");

        if (!apply) {
            Console.WriteLine("\n[NOTE] Dry-run completed. To apply changes to files, run with -Apply.");
        } else {
            Console.WriteLine("\n[SUCCESS] All batch files successfully updated!");
        }
    }
}
