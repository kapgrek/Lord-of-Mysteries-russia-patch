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
                }

                // Also map English reference to Russian translation so text rendered
                // from CPDD English overlays or baked text gets translated to Russian
                if (!string.IsNullOrEmpty(en) && !string.IsNullOrEmpty(ru)) {
                    string keyEn = ComputeSourceKey(en);
                    string shardEn = GetShardPrefix(keyEn);

                    if (!shardMap.ContainsKey(shardEn)) {
                        shardMap[shardEn] = new Dictionary<string, string>();
                    }
                    if (isBatch28 || !shardMap[shardEn].ContainsKey(en)) {
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
            { "12 seconds after the battle starts<HighLight></>, your pieces gain 35% Damage Deepening<HighLight></>.", "Через 12 сек. после начала боя<HighLight></> ваши фигуры получают 35% к увеличению урона<HighLight></>." },
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
