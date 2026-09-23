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

        // Explicit UI & AutoChess aliases
        var explicitAliases = new Dictionary<string, string> {
            { "Activate Resonance", "Активировать резонанс" },
            { "* Activate Resonance", "* Активировать резонанс" },
            { "Activated Resonance", "Активированный резонанс" },
            { "Spellcraft", "Колдовство" },
            { "Spellcasting", "Колдовство" },
            { "[Spellcasting]", "[Колдовство]" },
            { "All allies gain 10% Attack. [Spellcasting] stacks Attack after each skill cast.", "Все союзники получают 10% атаки. [Колдовство] накапливает атаку после каждого применения навыка." },
            { "[Spellcasting] gains an additional 15% Attack, and each time a skill is cast: self gains 1% Attack.", "[Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки." },
            { "[Spellcasting] gains an additional 35% Attack, and each time a skill is cast: self gains 1.5% Attack.", "[Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки." },
            { "[Spellcasting] gains an additional 55% Attack, and each time a skill is cast: self gains 2% Attack.", "[Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки." },
            { "2 [Spellcasting] gains an additional 15% Attack, and each time a skill is cast: self gains 1% Attack.", "2 [Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки." },
            { "4 [Spellcasting] gains an additional 35% Attack, and each time a skill is cast: self gains 1.5% Attack.", "4 [Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки." },
            { "6 [Spellcasting] gains an additional 55% Attack, and each time a skill is cast: self gains 2% Attack.", "6 [Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки." },
            { "Lawyer", "Юрист" },
            { "Lucky One", "Счастливчик" },
            { "Tarot Club", "Клуб Таро" },
            { "Hunter", "Охотник" },
            { "Giant Dragon Inheritance", "Наследие Дракона" },
            { "Life School of Thought", "Жизненная школа мысли" },
            { "Iron Wall", "Железная стена" },
            { "Evernight Goddess", "Вечная Богиня" },
            { "Forsaken Land of the Gods", "Заброшенная земля богов" },
            { "Aurora Order", "Орден Авроры" },
            { "Seer", "Провидец" },
            { "Rock", "Скала" },
            { "Monster", "Монстр" },
            { "The Great Master", "Великий Мастер" },
            { "[The Great Master]", "[Великий Мастер]" },
            { "For every 1 Resonance activated, all allies gain additional Attack, up to 10 Resonances.", "За каждый 1 активированный резонанс все союзники получают дополнительную атаку, максимум до 10 резонансов." },
            { "Wilderness Monster", "Монстр пустошей" },
            { "[Wilderness Monster]", "[Монстр пустошей]" },
            { "Each unique 3-star piece strengthens all allies. At high tiers, gain 1 random wild monster piece after each player combat.", "Каждая уникальная 3-звёздочная фигура усиливает всех союзников. На высоких ступенях даёт 1 случайную фигуру дикого монстра после каждого боя с игроком." },
            { "Each unique 3-star piece: All allies +3% Attack and 5 Defense.", "Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты." },
            { "2 Each unique 3-star piece: All allies +3% Attack and 5 Defense.", "2 Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты." },
            { "Each unique 3-star piece: All allies +3% Attack and 5 Defense. Gain 1 random wild monster piece after each player combat.", "Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты. Даёт 1 случайную фигуру дикого монстра после каждого боя с игроком." },
            { "3 Each unique 3-star piece: All allies +3% Attack and 5 Defense. Gain 1 random wild monster piece after each player combat.", "3 Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты. Даёт 1 случайную фигуру дикого монстра после каждого боя с игроком." },
            { "Long-Shot", "Дальний выстрел" },
            { "[Long-Shot]", "[Дальний выстрел]" },
            { "Long-Range Strike", "Дальнобойный удар" },
            { "[Long-Range Strike]", "[Дальнобойный удар]" },
            { "[Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage.", "[Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон." },
            { "2 [Long-Shot] [Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage.", "2 [Дальний выстрел] [Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон." },
            { "4 [Long-Shot] [Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage.", "4 [Дальний выстрел] [Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон." },
            { "Arcane", "Тайное знание" },
            { "[Arcane]", "[Тайное знание]" },
            { "All allies recover Mana per second. [Arcane] recovers more.", "Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
            { "2 [Arcane] All allies recover Mana per second. [Arcane] recovers more.", "2 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
            { "4 [Arcane] All allies recover Mana per second. [Arcane] recovers more.", "4 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
            { "Crafted Bulwark", "Искусный оплот" },
            { "Randomly gain 2 pieces of Defensive Fine Equipment.", "Случайным образом даёт 2 предмета добротного защитного снаряжения." },
            { "Critical Hit Amplification", "Усиление критического удара" },
            { "Your pieces gain 15% Critical Hit Rate and 25% Critical Damage.", "Ваши фигуры получают +15% к шансу крит. удара и +25% к крит. урону." },
            { "When a match round is lost, gain 2 Experience . If on a losing streak , gain an additional 1 Experience .", "При поражении в раунде матча даёт 2 ед. опыта. При серии поражений даёт дополнительно 1 ед. опыта." },
            { "When a match round is lost, gain 2 Experience. If on a losing streak, gain an additional 1 Experience.", "При поражении в раунде матча даёт 2 ед. опыта. При серии поражений даёт дополнительно 1 ед. опыта." },
            { "losing streak", "серия поражений" },
            { "Notes on Victory", "Заметки о победах" },
            { "Ranking", "Место" },
            { "Player", "Игрок" },
            { "Piece", "Фигура" },
            { "Pieces", "Фигуры" },
            { "piece", "фигура" },
            { "pieces", "фигуры" },
            { "Highlight Data", "Ключевые данные" },
            { "Total Money", "Всего монет" },
            { "Total Money:", "Всего монет:" },
            { "Total Money: ", "Всего монет: " },
            { "Total Battle Data", "Общая статистика боя" },
            { "Lineup Strategy", "Тактика состава" },
            { "Highest Win Streak: ", "Макс. серия побед: " },
            { "Highest Win Streak:", "Макс. серия побед:" },
            { "Highest Win Streak", "Макс. серия побед" },
            { "Highest Losing Streak: ", "Макс. серия поражений: " },
            { "Highest Losing Streak:", "Макс. серия поражений:" },
            { "Highest Losing Streak", "Макс. серия поражений" },
            { "Current Win Streak", "Текущая серия побед" },
            { "Current Losing Streak", "Текущая серия поражений" },

            // AutoChess piece roles
            { "Ranged Marksman", "Стрелок дальнего боя" },
            { "Melee Support", "Поддержка ближнего боя" },
            { "Ranged Mage", "Маг дальнего боя" },
            { "Melee Warrior", "Воин ближнего боя" },
            { "Frontline Tank", "Передовой танк" },
            { "Melee Tank", "Танк ближнего боя" },
            { "Melee Assassin", "Убийца ближнего боя" },
            { "Ranged Assassin", "Убийца дальнего боя" },
            { "Ranged Support", "Поддержка дальнего боя" },
            { "Frontline Warrior", "Передовой воин" },

            // AutoChess Extraordinary World synergy & tiers
            { "Starts [Extraordinary Quests]. Complete quests to accumulate [Quest Points] and claim fate gifts upon reaching thresholds.", "Начинает [Потусторонние задания]. Выполняйте задания, чтобы накапливать [Очки заданий] и получать дары судьбы по достижении пороговых значений." },
            { "[Extraordinary Quests]", "[Потусторонние задания]" },
            { "[Quest Points]", "[Очки заданий]" },
            { "Start [Extraordinary Quests].", "Начинает [Потусторонние задания]." },
            { "At the start of player combat: Restore 2 Health to the player.", "В начале боя с игроком: восстанавливает 2 ед. здоровья игроку." },
            { "At the start of player combat:\nRestore 2 Health to the player.", "В начале боя с игроком:\nВосстанавливает 2 ед. здоровья игроку." },
            { "At the start of player combat:\r\nRestore 2 Health to the player.", "В начале боя с игроком:\r\nВосстанавливает 2 ед. здоровья игроку." },
            { "At the start of player combat: Restore 2 Health to the player. Gain 50 [Quest Points] upon victory.", "В начале боя с игроком: восстанавливает 2 ед. здоровья игроку. Дает 50 [Очков заданий] при победе." },
            { "At the start of player combat:\nRestore 2 Health to the player. Gain 50 [Quest Points] upon victory.", "В начале боя с игроком:\nВосстанавливает 2 ед. здоровья игроку. Дает 50 [Очков заданий] при победе." },
            { "At the start of player combat:\r\nRestore 2 Health to the player. Gain 50 [Quest Points] upon victory.", "В начале боя с игроком:\r\nВосстанавливает 2 ед. здоровья игроку. Дает 50 [Очков заданий] при победе." },
            { "5 At the start of player combat: Restore 2 Health to the player.", "5 В начале боя с игроком: восстанавливает 2 ед. здоровья игроку." },
            { "5 At the start of player combat:\nRestore 2 Health to the player.", "5 В начале боя с игроком:\nВосстанавливает 2 ед. здоровья игроку." },
            { "5 At the start of player combat:\r\nRestore 2 Health to the player.", "5 В начале боя с игроком:\r\nВосстанавливает 2 ед. здоровья игроку." },
            { "7 At the start of player combat: Restore 2 Health to the player. Gain 50 [Quest Points] upon victory.", "7 В начале боя с игроком: восстанавливает 2 ед. здоровья игроку. Дает 50 [Очков заданий] при победе." },
            { "7 At the start of player combat:\nRestore 2 Health to the player. Gain 50 [Quest Points] upon victory.", "7 В начале боя с игроком:\nВосстанавливает 2 ед. здоровья игроку. Дает 50 [Очков заданий] при победе." },
            { "7 At the start of player combat:\r\nRestore 2 Health to the player. Gain 50 [Quest Points] upon victory.", "7 В начале боя с игроком:\r\nВосстанавливает 2 ед. здоровья игроку. Дает 50 [Очков заданий] при победе." }
        };

        foreach (var kvp in explicitAliases) {
            string keyEn = ComputeSourceKey(kvp.Key);
            string shardEn = GetShardPrefix(keyEn);
            if (!shardMap.ContainsKey(shardEn)) {
                shardMap[shardEn] = new Dictionary<string, string>();
            }
            if (!shardMap[shardEn].ContainsKey(kvp.Key)) {
                shardMap[shardEn][kvp.Key] = kvp.Value;
                enMappedCount++;
            } else {
                shardMap[shardEn][kvp.Key] = kvp.Value;
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
                .Replace(@"\t", "\t")
                .Replace(@"\u003c", "<")
                .Replace(@"\u003e", ">")
                .Replace(@"\u0027", "'")
                .Replace(@"\u0026", "&");
    }

    private static string EscapeLua(string s) {
        if (s == null) return "";
        return s.Replace(@"\", @"\\")
                .Replace(@"""", @"\""")
                .Replace("\r", @"\r")
                .Replace("\n", @"\n");
    }
}
