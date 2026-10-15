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
        // Repository root: -Root <path>, otherwise the parent of the exe folder (tools/).
        string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
        string batchesArg = null;
        string checkResolvedPath = null;
        for (int i = 0; i < args.Length; i++) {
            if (string.Equals(args[i], "-Root", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) {
                root = Path.GetFullPath(args[++i]);
            } else if (string.Equals(args[i], "-CheckResolved", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) {
                checkResolvedPath = Path.GetFullPath(args[++i]);  // reference/stringdb_dump/<build>/resolved.json (TASK-033 2B)
            } else if (batchesArg == null && Directory.Exists(args[i])) {
                batchesArg = args[i];  // legacy positional argument: batches folder
            }
        }
        string batchesDir = batchesArg ?? Path.Combine(root, "source", "translation_batches");
        string shardsDir = Path.Combine(root, "patch_payload", "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes");
        if (!Directory.Exists(shardsDir)) {
            Console.Error.WriteLine("Папка шардов не найдена: " + shardsDir + " (укажите -Root <путь_к_репозиторию>)");
            Environment.Exit(1);
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
        int enSkippedNoLetter = 0;
        int enSkippedMarker = 0;

        Regex itemRegex = new Regex(@"""source_cn""\s*:\s*""((?:\\""|[^""])*)""\s*,\s*""ref_en""\s*:\s*""((?:\\""|[^""])*)""\s*,\s*""target_ru""\s*:\s*""((?:\\""|[^""])*)""", RegexOptions.Compiled);
        // Keys with leading/trailing whitespace: the runtime trims only the looked-up string, not the key (TASK-012 A3).
        List<KeyValuePair<string, string>> trimmedKeys = new List<KeyValuePair<string, string>>();

        foreach (string bFile in batchFiles) {
            bool isBatch28 = bFile.IndexOf("batch_028", StringComparison.OrdinalIgnoreCase) >= 0;
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
                    string trimmedCn = TrimLuaSpace(cn);
                    if (trimmedCn.Length > 0 && trimmedCn != cn) trimmedKeys.Add(new KeyValuePair<string, string>(trimmedCn, cn));
                }

                // Also map English reference to Russian translation so text rendered
                // from CPDD English overlays or baked text gets translated to Russian.
                // Only keys with a letter: "3" from "3个" -> "3 шт." would hit every bare number in UI (TASK-016).
                // Marker strings ("#CanMove我#" with ref_en "I") and single Latin letters would turn
                // key prompts like "I" into "#CanMoveЯ#" (TASK-028 R1).
                if (!string.IsNullOrEmpty(en) && !string.IsNullOrEmpty(ru) && !HasLetter(en)) {
                    enSkippedNoLetter++;
                } else if (!string.IsNullOrEmpty(en) && !string.IsNullOrEmpty(ru) && IsMarkerOrSingleLetterEn(cn, en)) {
                    enSkippedMarker++;
                } else if (!string.IsNullOrEmpty(en) && !string.IsNullOrEmpty(ru)) {
                    string keyEn = ComputeSourceKey(en);
                    string shardEn = GetShardPrefix(keyEn);

                    if (!shardMap.ContainsKey(shardEn)) {
                        shardMap[shardEn] = new Dictionary<string, string>();
                    }
                    if (isBatch28 || !shardMap[shardEn].ContainsKey(en)) {
                        shardMap[shardEn][en] = ru;
                        enMappedCount++;
                    }
                    string trimmedEn = TrimLuaSpace(en);
                    if (trimmedEn.Length > 0 && trimmedEn != en) trimmedKeys.Add(new KeyValuePair<string, string>(trimmedEn, en));
                }
            }
        }

        // Trimmed keys go in only where no real key already sits; the value is trimmed the same way.
        int trimmedCount = 0;
        foreach (KeyValuePair<string, string> kv in trimmedKeys) {
            string shardTrim = GetShardPrefix(ComputeSourceKey(kv.Key));
            if (shardMap.ContainsKey(shardTrim) && shardMap[shardTrim].ContainsKey(kv.Key)) continue;
            string shardOrig = GetShardPrefix(ComputeSourceKey(kv.Value));
            string origVal;
            if (!shardMap.ContainsKey(shardOrig) || !shardMap[shardOrig].TryGetValue(kv.Value, out origVal)) continue;
            if (!shardMap.ContainsKey(shardTrim)) shardMap[shardTrim] = new Dictionary<string, string>();
            shardMap[shardTrim][kv.Key] = TrimLuaSpace(origVal);
            trimmedCount++;
        }

        // Explicit UI & AutoChess aliases
        var explicitAliases = new Dictionary<string, string> {
            { "Activate Resonance", "Активировать резонанс" },
            { "* Activate Resonance", "* Активировать резонанс" },
            { "Activated Resonance", "Активированный резонанс" },
            { "Spellcraft", "Колдовство" },
            { "[Spellcraft]", "[Колдовство]" },
            { "Spellcasting", "Колдовство" },
            { "[Spellcasting]", "[Колдовство]" },
            { "施法", "Колдовство" },
            { "【施法】", "【Колдовство】" },
            { "法术", "Колдовство" },
            { "【法术】", "【Колдовство】" },
            { "All allies gain 10% Attack. [Spellcasting] stacks Attack after each skill cast.", "Все союзники получают 10% атаки. [Колдовство] накапливает атаку после каждого применения навыка." },
            { "[Spellcasting] gains an additional 15% Attack, and each time a skill is cast: self gains 1% Attack.", "[Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки." },
            { "[Spellcasting] gains an additional 35% Attack, and each time a skill is cast: self gains 1.5% Attack.", "[Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки." },
            { "[Spellcasting] gains an additional 55% Attack, and each time a skill is cast: self gains 2% Attack.", "[Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки." },
            { "2 [Spellcasting] gains an additional 15% Attack, and each time a skill is cast: self gains 1% Attack.", "2 [Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки." },
            { "4 [Spellcasting] gains an additional 35% Attack, and each time a skill is cast: self gains 1.5% Attack.", "4 [Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки." },
            { "6 [Spellcasting] gains an additional 55% Attack, and each time a skill is cast: self gains 2% Attack.", "6 [Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки." },
            { "All allies gain <HighLight>10%</> Attack. [Spellcasting] stacks Attack after each skill cast.", "Все союзники получают 10% атаки. [Колдовство] накапливает атаку после каждого применения навыка." },
            { "[Spellcasting] gains an additional <HighLight>15%</> Attack, and each time a skill is cast: self gains <HighLight>1%</> Attack.", "[Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки." },
            { "[Spellcasting] gains an additional <HighLight>35%</> Attack, and each time a skill is cast: self gains <HighLight>1.5%</> Attack.", "[Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки." },
            { "[Spellcasting] gains an additional <HighLight>55%</> Attack, and each time a skill is cast: self gains <HighLight>2%</> Attack.", "[Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки." },
            { "2 [Spellcasting] gains an additional <HighLight>15%</> Attack, and each time a skill is cast: self gains <HighLight>1%</> Attack.", "2 [Колдовство] дает дополнительно 15% атаки, и при каждом применении навыка: сам персонаж получает 1% атаки." },
            { "4 [Spellcasting] gains an additional <HighLight>35%</> Attack, and each time a skill is cast: self gains <HighLight>1.5%</> Attack.", "4 [Колдовство] дает дополнительно 35% атаки, и при каждом применении навыка: сам персонаж получает 1.5% атаки." },
            { "6 [Spellcasting] gains an additional <HighLight>55%</> Attack, and each time a skill is cast: self gains <HighLight>2%</> Attack.", "6 [Колдовство] дает дополнительно 55% атаки, и при каждом применении навыка: сам персонаж получает 2% атаки." },
            { "All allies gain <HighLight>10%</> Attack Speed. [Swift Hunt] stacks Attack Speed with each attack, up to <HighLight>10</> stacks. High tiers gain Damage Reduction.", "Все союзники получают 10% к скорости атаки. [Быстрая охота] накапливает скорость атаки при каждом ударе (до 10 уровней). На высоких рангах дает снижение урона." },
            { "All allies recover <HighLight>4</> Mana per second. [Arcane] recovers more.", "Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
            { "2 [Arcane] All allies recover <HighLight>4</> Mana per second. [Arcane] recovers more.", "2 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
            { "4 [Arcane] All allies recover <HighLight>4</> Mana per second. [Arcane] recovers more.", "4 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
            { "For every <HighLight>1</> Resonance activated, all allies gain additional Attack, up to <HighLight>10</> Resonances.", "За каждый 1 активированный резонанс все союзники получают дополнительную атаку, максимум до 10 резонансов." },
            { "Lawyer", "Юрист" },
            { "[Lawyer]", "[Юрист]" },
            { "律师", "Юрист" },
            { "【律师】", "【Юрист】" },
            { "Lucky One", "Счастливчик" },
            { "[Lucky One]", "[Счастливчик]" },
            { "幸运儿", "Счастливчик" },
            { "【幸运儿】", "【Счастливчик】" },
            { "Tarot Club", "Клуб Таро" },
            { "[Tarot Club]", "[Клуб Таро]" },
            { "塔罗会", "Клуб Таро" },
            { "【塔罗会】", "【Клуб Таро】" },
            { "Hunter", "Охотник" },
            { "[Hunter]", "[Охотник]" },
            { "猎人", "Охотник" },
            { "【猎人】", "【Охотник】" },
            { "Giant Dragon Inheritance", "Наследие Дракона" },
            { "[Giant Dragon Inheritance]", "[Наследие Дракона]" },
            { "巨龙后裔", "Наследие Дракона" },
            { "【巨龙后裔】", "【Наследие Дракона】" },
            { "Life School of Thought", "Школа мысли Жизни" },
            { "[Life School of Thought]", "[Школа мысли Жизни]" },
            { "生命学派", "Школа мысли Жизни" },
            { "【生命学派】", "【Школа мысли Жизни】" },
            { "Iron Wall", "Железная стена" },
            { "[Iron Wall]", "[Железная стена]" },
            { "铁壁", "Железная стена" },
            { "【铁壁】", "【Железная стена】" },
            { "Evernight Goddess", "Богиня Вечной Ночи" },
            { "[Evernight Goddess]", "[Богиня Вечной Ночи]" },
            { "黑夜女神", "Богиня Вечной Ночи" },
            { "【黑夜女神】", "【Богиня Вечной Ночи】" },
            { "Evernight Goddess Church", "Церковь Богини Вечной Ночи" },
            { "[Evernight Goddess Church]", "[Церковь Богини Вечной Ночи]" },
            { "黑夜女神教会", "Церковь Богини Вечной Ночи" },
            { "【黑夜女神教会】", "【Церковь Богини Вечной Ночи】" },
            { "Forsaken Land of the Gods", "Заброшенная земля богов" },
            { "[Forsaken Land of the Gods]", "[Заброшенная земля богов]" },
            { "神弃之地", "Заброшенная земля богов" },
            { "【神弃之地】", "【Заброшенная земля богов】" },
            { "Aurora Order", "Орден Авроры" },
            { "[Aurora Order]", "[Орден Авроры]" },
            { "极光会", "Орден Авроры" },
            { "【极光会】", "【Орден Авроры】" },
            { "Seer", "Провидец" },
            { "[Seer]", "[Провидец]" },
            { "占卜家", "Провидец" },
            { "【占卜家】", "【Провидец】" },
            { "Rock", "Скала" },
            { "[Rock]", "[Скала]" },
            { "岩石", "Скала" },
            { "【岩石】", "【Скала】" },
            { "Monster", "Монстр" },
            { "[Monster]", "[Монстр]" },
            { "怪物", "Монстр" },
            { "【怪物】", "【Монстр】" },
            { "Bulwark", "Оплот" },
            { "[Bulwark]", "[Оплот]" },
            { "坚阵", "Оплот" },
            { "【坚阵】", "【Оплот】" },
            { "Crafted Bulwark", "Искусный оплот" },
            { "[Crafted Bulwark]", "[Искусный оплот]" },
            { "精工壁垒", "Искусный оплот" },
            { "【精工壁垒】", "【Искусный оплот】" },
            { "The Great Master", "Великий Мастер" },
            { "[The Great Master]", "[Великий Мастер]" },
            { "大宗师", "Великий Мастер" },
            { "【大宗师】", "【Великий Мастер】" },
            { "For every 1 Resonance activated, all allies gain additional Attack, up to 10 Resonances.", "За каждый 1 активированный резонанс все союзники получают дополнительную атаку, максимум до 10 резонансов." },
            { "Wilderness Monster", "Монстр пустошей" },
            { "[Wilderness Monster]", "[Монстр пустошей]" },
            { "荒野魔物", "Монстр пустошей" },
            { "【荒野魔物】", "【Монстр пустошей】" },
            { "Each unique 3-star piece strengthens all allies. At high tiers, gain 1 random wild monster piece after each player combat.", "Каждая уникальная 3-звёздочная фигура усиливает всех союзников. На высоких ступенях даёт 1 случайную фигуру дикого монстра после каждого боя с игроком." },
            { "Each unique 3-star piece: All allies +3% Attack and 5 Defense.", "Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты." },
            { "2 Each unique 3-star piece: All allies +3% Attack and 5 Defense.", "2 Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты." },
            { "Each unique 3-star piece: All allies +3% Attack and 5 Defense. Gain 1 random wild monster piece after each player combat.", "Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты. Даёт 1 случайную фигуру дикого монстра после каждого боя с игроком." },
            { "3 Each unique 3-star piece: All allies +3% Attack and 5 Defense. Gain 1 random wild monster piece after each player combat.", "3 Каждая уникальная 3-звёздочная фигура: всем союзникам +3% атаки и 5 защиты. Даёт 1 случайную фигуру дикого монстра после каждого боя с игроком." },
            { "Long-Shot", "Дальний выстрел" },
            { "[Long-Shot]", "[Дальний выстрел]" },
            { "远射", "Дальний выстрел" },
            { "【远射】", "【Дальний выстрел】" },
            { "Long-Range Strike", "Дальнобойный удар" },
            { "[Long-Range Strike]", "[Дальнобойный удар]" },
            { "[Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage.", "[Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон." },
            { "2 [Long-Shot] [Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage.", "2 [Дальний выстрел] [Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон." },
            { "4 [Long-Shot] [Long-Range Strike] Deals additional damage when dealing damage. The further the distance to the target, the higher the additional damage.", "4 [Дальний выстрел] [Дальнобойный удар] Наносит дополнительный урон при атаке. Чем больше дистанция до цели, тем выше дополнительный урон." },
            { "Arcane", "Тайное знание" },
            { "[Arcane]", "[Тайное знание]" },
            { "秘术", "Тайное знание" },
            { "【秘术】", "【Тайное знание】" },
            { "All allies recover Mana per second. [Arcane] recovers more.", "Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
            { "2 [Arcane] All allies recover Mana per second. [Arcane] recovers more.", "2 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
            { "4 [Arcane] All allies recover Mana per second. [Arcane] recovers more.", "4 [Тайное знание] Все союзники восстанавливают ману каждую секунду. [Тайное знание] восстанавливает больше." },
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
            { "Lineup Strategy", "Тактика отряда" },
            { "添加阵容", "Добавить состав" },
            { "添加阵容：", "Добавить состав:" },
            { "阵容思路", "Тактика отряда" },
            { "阵容思路：", "Тактика отряда:" },
            { "弈棋试炼", "Шахматные испытания" },
            { "弈棋试炼：", "Шахматные испытания:" },
            { "弈子列表", "Список фигур" },
            { "弈子列表：", "Список фигур:" },
            { "Add Lineup", "Добавить состав" },
            { "Chess Trials", "Шахматные испытания" },
            { "Chess Trial", "Шахматные испытания" },
            { "Piece List", "Список фигур" },
            { "Pieces List", "Список фигур" },
            { "Chess Piece List", "Список фигур" },
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
            { "Mid-row Support", "Поддержка среднего ряда" },
            { "Frontline Support", "Передовая поддержка" },
            { "Frontline Assassin", "Убийца передовой" },
            { "Backline Marksman", "Стрелок заднего ряда" },
            { "Backline Mage", "Маг заднего ряда" },
            { "Backline Support", "Поддержка заднего ряда" },
            { "Backline Assassin", "Убийца заднего ряда" },
            { "Mid-row Mage", "Маг среднего ряда" },
            { "Mid-row Warrior", "Воин среднего ряда" },
            { "Mid-row Marksman", "Стрелок среднего ряда" },
            { "Mid-row Tank", "Танк среднего ряда" },
            { "Mid-row Assassin", "Убийца среднего ряда" },

            // AutoChess Extraordinary World synergy & tiers
            { "Starts [Extraordinary Quests], increasing the probability of Extraordinary Quests appearing each round; upon completing a quest, gain an [Extraordinary Chest]", "Начинает [Потусторонние задания], увеличивая вероятность появления Потусторонних заданий в каждом раунде; после выполнения задания вы получаете [Потусторонний сундук]" },
            { "3 Starts [Extraordinary Quests], increasing the probability of Extraordinary Quests appearing each round; upon completing a quest, gain an [Extraordinary Chest]", "3 Начинает [Потусторонние задания], увеличивая вероятность появления Потусторонних заданий в каждом раунде; после выполнения задания вы получаете [Потусторонний сундук]" },
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
            { "7 At the start of player combat:\r\nRestore 2 Health to the player. Gain 50 [Quest Points] upon victory.", "7 В начале боя с игроком:\r\nВосстанавливает 2 ед. здоровья игроку. Дает 50 [Очков заданий] при победе." },

            // AutoChess augments, items & UI
            { "Divinity Spread", "Распространение божественности" },
            { "Economy", "Экономика" },
            { "Iron and Blood Badge", "Знак Железа и Крови" },
            { "Mutual Guard", "Взаимная защита" },
            { "Mysticism Page", "Страница мистицизма" },
            { "Rare · Life Crystal Pendant", "Редкий · Кулон кристалла жизни" },
            { "Traction Spirit Pendant", "Кулон притяжения духов" },
            { "12 seconds after the battle starts<HighLight></>, your pieces gain 35% Damage Deepening<HighLight></>.", "Через 12 сек. после начала боя<HighLight></> ваши фигуры получают 35% к усилению урона<HighLight></>." },
            { "Each Basic Attack restores <HighLight>3</> Mana; when dealing a Critical Hit, restore an additional <HighLight>4</> Mana.", "Каждая базовая атака восстанавливает <HighLight>3</> ед. маны; при критическом ударе восстанавливает дополнительно <HighLight>4</> ед. маны." },
            { "Gain <HighLight> two 1-cost chess pieces </>, <HighLight> two 2-cost chess pieces </>, and <HighLight> one 3-cost chess piece </>.", "Получите <HighLight> две фигуры стоимостью 1 </>, <HighLight> две фигуры стоимостью 2 </> и <HighLight> одну фигуру стоимостью 3 </>." },
            { "If there are exactly 2 ally pieces in the first row<HighLight></>, both gain 150 Health<HighLight></> and 20 Defense<HighLight></>.", "Если в первом ряду ровно 2 союзные фигуры<HighLight></>, обе получают 150 ед. здоровья<HighLight></> и 20 ед. защиты<HighLight></>." },
            { "Randomly gain <HighLight> one basic equipment </>, and gain <HighLight> one Fine Equipment Casket </>, <HighLight> one Equipment Reforger </>, and <HighLight> 3 Gold Coins </>.", "Случайным образом получите <HighLight> одно базовое снаряжение </>, а также <HighLight> один ларец с отличным снаряжением </>, <HighLight> один перековщик снаряжения </> и <HighLight> 3 золотые монеты </>." },
            { "保存阵容", "Сохранить состав" },
            { "未编辑保存阵容", "Состав не сохранен" },
            { "编辑阵容", "Изменить состав" },
            { "槽位未解锁", "Ячейка заблокирована" },
            { "卡牌名字七个字", "Имя карты семь букв" },
            { "施法后的<HighLight>5</>秒内，下一次普攻额外造成相当于<HighLight>120%</>攻击的伤害，冷却时间为<HighLight>4</>秒。", "В течение <HighLight>5</> сек. после применения навыка следующая базовая атака дополнительно наносит урон в размере <HighLight>120%</> от атаки, время перезарядки — <HighLight>4</> сек." },
            { "每秒恢复<HighLight>4%</>最大生命值。", "Восстанавливает <HighLight>4%</> от максимального запаса здоровья в секунду." },
            { "获得【铁血】共鸣。每隔<HighLight>2</>秒，对<HighLight>1</>格内至多<HighLight>3</>名敌人造成相当于自身生命值<HighLight>1%</>的伤害。", "Получает резонанс 【Железо и Кровь】. Каждые <HighLight>2</> сек. наносит до <HighLight>3</> врагам в пределах <HighLight>1</> клетки урон, равный <HighLight>1%</> от собственного здоровья." }
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

        Console.WriteLine("Загружено строк: " + totalLoaded + " (переведено на русский: " + translatedCount + ", EN->RU алиасов: " + enMappedCount + ", обрезанных ключей: " + trimmedCount + ", EN-ключей без букв пропущено: " + enSkippedNoLetter + ", enSkippedMarker: " + enSkippedMarker + ")");
        Console.WriteLine("Запись в 1024 Lua-шарда...");

        // UTF-8 without BOM, LF line endings (AGENTS.md §5)
        UTF8Encoding utf8 = new UTF8Encoding(false);
        for (int s = 0; s < 1024; s++) {
            string shardName = s.ToString("x3");
            string fileName = "RuntimeTextGemini_" + shardName + ".lua";
            string filePath = Path.Combine(shardsDir, fileName);

            StringBuilder sb = new StringBuilder();
            sb.Append("-- Generated for Lord of the Mysteries Russian Translation (v2.6-RU)\n");
            sb.Append("-- Lazy exact-text shard " + shardName + "/3ff.\n");
            sb.Append("return {\n");

            if (shardMap.ContainsKey(shardName)) {
                foreach (KeyValuePair<string, string> kvp in shardMap[shardName]) {
                    sb.Append("    [\"" + EscapeLua(kvp.Key) + "\"] = \"" + EscapeLua(kvp.Value) + "\",\n");
                }
            }

            sb.Append("}\n");
            File.WriteAllText(filePath, sb.ToString(), utf8);
        }

        Console.WriteLine("Все 1024 шарда успешно обновлены!");

        int packCode = StringDbPacks.Build(root, shardsDir, shardMap, checkResolvedPath);
        if (packCode != 0) Environment.Exit(packCode);
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

    private static bool IsMarkerOrSingleLetterEn(string cn, string en) {
        if (cn != null && cn.IndexOf("#CanMove", StringComparison.Ordinal) >= 0 && en.IndexOf("#CanMove", StringComparison.Ordinal) < 0) return true;
        string t = en.Trim();
        return t.Length == 1 && ((t[0] >= 'A' && t[0] <= 'Z') || (t[0] >= 'a' && t[0] <= 'z'));
    }

    private static bool HasLetter(string s) {
        foreach (char c in s) {
            if (char.IsLetter(c)) return true;
        }
        return false;
    }

    // Lua %s: space, \t, \n, \v, \f, \r (lookupGeminiTextFuzzy trims exactly these)
    private static string TrimLuaSpace(string s) {
        return s.Trim(' ', '\t', '\n', '\v', '\f', '\r');
    }

    internal static string EscapeLua(string s) {
        if (s == null) return "";
        return s.Replace(@"\", @"\\")
                .Replace(@"""", @"\""")
                .Replace("\r", @"\r")
                .Replace("\n", @"\n");
    }
}

// TASK-033 stage 2B: StringDB packs. For every cn of source/stringdb/stringdb_keys.json the pack holds the result
// of step 3 of Loader.TranslateDatabaseString (lookupGeminiText(cn) or lookupGeminiTextFuzzy(cn), Init.lua) over
// the shards just built: ["cn"] = "ru" or ["cn"] = false. Lua strings are bytes, and the fuzzy patterns match
// single bytes of UTF-8 ("：" and "【】" sit in byte classes), so the port runs on byte strings: one char per byte
// (Latin-1), the same trick as LuaDataCheck.cs. Steps and recursion follow lookupGeminiTextFuzzy line by line.
public static class StringDbPacks {
    const string ModuleMarker = "StringDB_CN_Data";
    static readonly Encoding Latin1 = Encoding.GetEncoding(28591);
    static Dictionary<string, string> exact;  // byte key -> byte value, all shards

    public static string ToBytes(string s) { return Latin1.GetString(Encoding.UTF8.GetBytes(s)); }

    public static string ByteSourceKey(string bytes) {
        uint hash = 2166136261u;
        for (int i = 0; i < bytes.Length; i++) {
            hash ^= (byte)bytes[i];
            hash = (uint)((int)hash + ((int)hash << 1) + ((int)hash << 4) + ((int)hash << 7) + ((int)hash << 8) + ((int)hash << 24));
        }
        return bytes.Length.ToString() + ":" + hash.ToString("x8");
    }

    // Lua %s (LuaJIT lj_char: \t \n \v \f \r and space; bytes >= 0x80 are never spaces or digits)
    static bool IsSpace(char c) { return c == ' ' || (c >= '\t' && c <= '\r'); }
    static bool IsDigit(char c) { return c >= '0' && c <= '9'; }
    // [:：%-%?%.]  ： = EF BC 9A
    static bool IsPunct(char c) { return c == ':' || c == '-' || c == '?' || c == '.' || c == '\xEF' || c == '\xBC' || c == '\x9A'; }
    // [%[%{%(【] and [%]%}%)】]  【 = E3 80 90, 】 = E3 80 91
    static bool IsOpenBracket(char c) { return c == '[' || c == '{' || c == '(' || c == '\xE3' || c == '\x80' || c == '\x90'; }
    static bool IsCloseBracket(char c) { return c == ']' || c == '}' || c == ')' || c == '\xE3' || c == '\x80' || c == '\x91'; }

    // lookupGeminiText: exact shard lookup, "" -> nil
    static string Lookup(string v) {
        if (v.Length == 0) return null;
        string t;
        return exact.TryGetValue(v, out t) ? t : null;
    }

    // value:match("^(%s*)(.-)(%s*)$"): greedy leading spaces, the rest without its trailing spaces
    static void SplitSpace(string v, out string leading, out string trimmed, out string trailing) {
        int a = 0;
        while (a < v.Length && IsSpace(v[a])) a++;
        int b = v.Length;
        while (b > a && IsSpace(v[b - 1])) b--;
        leading = v.Substring(0, a);
        trimmed = v.Substring(a, b - a);
        trailing = v.Substring(b);
    }

    // value:match("^[Ll]...") prefix check helper
    static bool StartsLv(string v, string tail, int at) {
        if (v.Length < at + tail.Length) return false;
        if (v[0] != 'L' && v[0] != 'l') return false;
        return string.CompareOrdinal(v, at, tail, 0, tail.Length) == 0;
    }

    // "%s*(%d+)$" from position p: the digits or null
    static string SpacesDigitsToEnd(string v, int p) {
        while (p < v.Length && IsSpace(v[p])) p++;
        int d = p;
        while (p < v.Length && IsDigit(v[p])) p++;
        if (p == d || p != v.Length) return null;
        return v.Substring(d);
    }

    static readonly string LevelRu = ToBytes("Уровень ");
    static readonly string LvRu = ToBytes("Ур. ");
    static readonly string LvColonRu = ToBytes("Ур: ");

    // runtimeFixes.lookupGeminiTextFuzzy
    static string Fuzzy(string value) {
        if (value.Length == 0) return null;
        string direct = Lookup(value);
        if (direct != null) return direct;

        if (value.IndexOf('\r') >= 0) {
            string normalized = value.Replace("\r\n", "\n").Replace("\r", "\n");
            string normDirect = Lookup(normalized);
            if (normDirect != null) return normDirect;
            string nl, nt, nr;
            SplitSpace(normalized, out nl, out nt, out nr);
            if (nt.Length > 0 && nt != normalized) {
                string t = Lookup(nt);
                if (t != null) return nl + t + nr;
            }
        }

        // 1. trim
        string leading, trimmed, trailing;
        SplitSpace(value, out leading, out trimmed, out trailing);
        if (trimmed.Length > 0 && trimmed != value) {
            string t = Lookup(trimmed);
            if (t != null) return leading + t + trailing;
        }

        // 2. ^(<[^>]+>)(.-)(</>)$  — the tag ends at the first '>' and needs one byte inside
        if (value.Length > 0 && value[0] == '<') {
            int gt = value.IndexOf('>', 1);
            if (gt >= 2 && value.Length >= gt + 1 + 3 && value.EndsWith("</>", StringComparison.Ordinal)) {
                string tagInner = value.Substring(gt + 1, value.Length - (gt + 1) - 3);
                if (tagInner.Length > 0) {
                    string t = Fuzzy(tagInner);
                    if (t != null) return value.Substring(0, gt + 1) + t + "</>";
                }
            }
        }

        // 3. ^(.-)([:：%-%?%.]+)%s*$  — the shortest stem: the whole punctuation run before trailing spaces
        {
            int e = value.Length;
            while (e > 0 && IsSpace(value[e - 1])) e--;
            int s = e;
            while (s > 0 && IsPunct(value[s - 1])) s--;
            if (s < e && s > 0) {
                string t = Fuzzy(value.Substring(0, s));
                if (t != null) return t + value.Substring(s, e - s);
            }
        }

        // 4. ^([%[%{%(【])(.-)([%]%}%)】])$  — one byte each side
        if (value.Length >= 3 && IsOpenBracket(value[0]) && IsCloseBracket(value[value.Length - 1])) {
            string t = Fuzzy(value.Substring(1, value.Length - 2));
            if (t != null) return value.Substring(0, 1) + t + value.Substring(value.Length - 1);
        }

        // 5. ^[Ll]evel%s*(%d+)$, ^[Ll]v%.?%s*(%d+)$, ^[Ll]v%.?[:：]%s*(%d+)$
        if (StartsLv(value, "evel", 1)) {
            string n = SpacesDigitsToEnd(value, 5);
            if (n != null) return LevelRu + n;
        }
        if (StartsLv(value, "v", 1)) {
            int p = 2;
            if (p < value.Length && value[p] == '.') p++;
            string n = SpacesDigitsToEnd(value, p);
            if (n != null) return LvRu + n;
            if (p < value.Length && (value[p] == ':' || value[p] == '\xEF' || value[p] == '\xBC' || value[p] == '\x9A')) {
                n = SpacesDigitsToEnd(value, p + 1);
                if (n != null) return LvColonRu + n;
            }
        }
        return null;
    }

    // runtimeFixes.resolveStringDbText on a byte string
    public static string Resolve(string cnBytes) {
        return Lookup(cnBytes) ?? Fuzzy(cnBytes);
    }

    static object ReadJson(string path) {
        var serializer = new System.Web.Script.Serialization.JavaScriptSerializer();
        serializer.MaxJsonLength = int.MaxValue;
        return serializer.DeserializeObject(File.ReadAllText(path, new UTF8Encoding(false)));
    }

    public static int Build(string root, string shardsDir, Dictionary<string, Dictionary<string, string>> shardMap, string checkResolvedPath) {
        exact = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var shard in shardMap.Values)
            foreach (var kv in shard) exact[ToBytes(kv.Key)] = ToBytes(kv.Value);

        if (checkResolvedPath != null) {
            int code = CheckResolved(checkResolvedPath);
            if (code != 0) return code;
        }

        string keysPath = Path.Combine(root, "source", "stringdb", "stringdb_keys.json");
        var written = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var index = new SortedDictionary<string, string>(StringComparer.Ordinal);  // module -> suffix
        string gameBuild = "";
        if (!File.Exists(keysPath)) {
            Console.WriteLine("ВНИМАНИЕ: нет " + keysPath + " — пакеты StringDB не собраны, StringDB на старте читает все шарды (TASK-033).");
        } else {
            var keysFile = (Dictionary<string, object>)ReadJson(keysPath);
            gameBuild = Convert.ToString(keysFile["game_build"]);
            var modules = (Dictionary<string, object>)keysFile["modules"];
            int totalKeys = 0, totalHits = 0;
            foreach (var mod in modules) {
                string module = mod.Key;
                int marker = module.LastIndexOf(ModuleMarker, StringComparison.Ordinal);
                string suffix = marker < 0 ? null : module.Substring(marker + ModuleMarker.Length);
                if (suffix == null || !Regex.IsMatch(suffix, "^[A-Za-z0-9_]*$")) {
                    Console.WriteLine("ВНИМАНИЕ: модуль без суффикса " + ModuleMarker + " пропущен: " + module);
                    continue;
                }
                var keys = (object[])((Dictionary<string, object>)mod.Value)["keys"];
                var byteKeys = new List<string>(keys.Length);
                foreach (object k in keys) {
                    string cn = Convert.ToString(k);
                    if (!string.IsNullOrEmpty(cn)) byteKeys.Add(ToBytes(cn));
                }
                byteKeys.Sort(StringComparer.Ordinal);
                int hits = 0, misses = 0;
                var body = new StringBuilder(byteKeys.Count * 160);
                string previous = null;
                foreach (string cn in byteKeys) {
                    if (cn == previous) continue;
                    previous = cn;
                    string ru = Resolve(cn);
                    body.Append("    [\"").Append(FastShardCompiler.EscapeLua(cn)).Append("\"] = ");
                    if (ru != null) { body.Append('"').Append(FastShardCompiler.EscapeLua(ru)).Append("\",\n"); hits++; }
                    else { body.Append("false,\n"); misses++; }
                }
                string fileName = "StringDbPack" + suffix + ".lua";
                // Byte strings are written 1:1 (Latin-1), so the file holds the exact UTF-8 bytes the runtime sees.
                string text = "-- StringDB pack " + module + " game_build=" + gameBuild + " keys=" + (hits + misses)
                    + " hits=" + hits + " false=" + misses + "\n"
                    + "-- Generated by tools/ShardCompiler.exe from source/stringdb/stringdb_keys.json (TASK-033).\n"
                    + "return {\n" + body.ToString() + "}\n";
                File.WriteAllText(Path.Combine(shardsDir, fileName), text, Latin1);
                written.Add(fileName);
                index[module] = suffix;
                totalKeys += hits + misses;
                totalHits += hits;
                Console.WriteLine("  " + fileName + ": keys=" + (hits + misses) + " hits=" + hits + " false=" + misses);
            }
            Console.WriteLine("Пакетов StringDB: " + index.Count + " (game_build=" + gameBuild + ", ключей " + totalKeys + ", с переводом " + totalHits + ")");
        }

        // The index is always written: Init.lua loads only listed packs, so a missing pack never logs an error.
        var idx = new StringBuilder();
        idx.Append("-- StringDB pack index game_build=" + gameBuild + " packs=" + index.Count + "\n");
        idx.Append("-- Generated by tools/ShardCompiler.exe (TASK-033): module -> StringDbPack<suffix>.lua.\n");
        idx.Append("return {\n");
        foreach (var kv in index) idx.Append("    [\"" + kv.Key + "\"] = \"" + kv.Value + "\",\n");
        idx.Append("}\n");
        File.WriteAllText(Path.Combine(shardsDir, "StringDbPackIndex.lua"), idx.ToString(), new UTF8Encoding(false));
        written.Add("StringDbPackIndex.lua");

        foreach (string stale in Directory.GetFiles(shardsDir, "StringDbPack*.lua")) {
            if (written.Contains(Path.GetFileName(stale))) continue;
            File.Delete(stale);
            Console.WriteLine("Удалён устаревший пакет: " + Path.GetFileName(stale));
        }
        return 0;
    }

    // sourceKey(resolve(cn)) against res from the game (StringDbGaps -ImportKeys). Valid only while the shards
    // equal the build the dump was made on.
    static int CheckResolved(string path) {
        if (!File.Exists(path)) { Console.Error.WriteLine("-CheckResolved: нет файла " + path); return 2; }
        var resolved = (Dictionary<string, object>)((Dictionary<string, object>)ReadJson(path))["resolved"];
        int total = 0, mismatches = 0, hits = 0;
        foreach (var kv in resolved) {
            if (string.IsNullOrEmpty(kv.Key)) continue;
            total++;
            string ru = Resolve(ToBytes(kv.Key));
            string mine = ru == null ? null : ByteSourceKey(ru);
            string game = kv.Value == null ? null : Convert.ToString(kv.Value);
            if (game != null) hits++;
            if (mine == game) continue;
            mismatches++;
            if (mismatches <= 20) {
                string shown = kv.Key.Length > 120 ? kv.Key.Substring(0, 120) + "…" : kv.Key;
                Console.WriteLine("  расхождение: cn=" + shown.Replace("\n", "\\n").Replace("\r", "\\r")
                    + " game=" + (game ?? "nil") + " port=" + (mine ?? "nil"));
            }
        }
        Console.WriteLine("CheckResolved: cn=" + total + " с переводом в игре=" + hits + " расхождений=" + mismatches);
        return mismatches == 0 ? 0 : 3;
    }
}
