# TASK-019: Китайский и английский текст на экране, поздний перевод настроек (сессия s5, 2026-09-26)

Дорожная карта: [ROADMAP.md](ROADMAP.md), этап 7 (покрытие перевода). Предыдущие: [TASK-012](TASK-012-translation-coverage.md) (StringDbGaps), [TASK-017](TASK-017-glossary-pack1.md) (конвейер `ru-translator` / `translate-chunk`).

Статус: **исполнен 2026-09-27 (v3.0.3-RU в репозитории, не опубликован), ждёт проверки в игре и данных проб для R2 (allowlist) и R6.**

## Симптом
Пользователь, v3.0.1-RU в игре (v3.0.2-RU из TASK-017 в репозитории, не опубликован), `absoluteru_dev.lua` с `TextFit = "cap"`:
1. местами на экране остаётся китайский текст;
2. местами — английский (из CPDD или из самой игры);
3. при открытии настроек текст «переводится с заметной задержкой».

Конкретные места и скриншоты пользователь не приложил: в запросе остался шаблон «[перечислить / приложить скриншоты]». Поэтому анализ целиком построен на логах.

## Данные
- Сессия `sid = 20260926-190040` (слот s5, 19:00:40–20:23:26), сбор: `tools\CollectDiagLogs.ps1 -Session 20260926-190040` → `reference/logs/2026-09-26_2031/` (отчёты в `report/`: `untranslated.md/.csv`, `late.md`, `fit.md`, `REPORT.md`).
- `tools\StringDbGaps.ps1 -Report -Logs reference\logs\2026-09-26_2031 -Sid 20260926-190040 -Csv temp\t019_stringdb_gaps.csv` (CSV в `temp/`, при необходимости пересоздать той же командой).
- Непереведённого по отчёту: виджеты и данные — 2232 уникальных, StringDB — 7594 строки.
- Сейчас в игре `absoluteru_dev.lua` с `Enabled = false`: для проверки его нужно включить снова.

## Разбор непереведённого

### Сводка по источникам (без скрытых `vis=False` и идентификаторов данных)

| src | CJK | латиница без кириллицы | из них ложные | к переводу (б) | баг рантайма/ключа (а) |
|---|---:|---:|---|---:|---:|
| widget (видимые) | 237 | 244 | ~400: мусор `KGTextBlock: …` 154, ники/чат/гильдии, латиница по дизайну | 85 | 51 |
| data | 607 | 699 | ~1090: пузыри чата Gossip, ники, пути к ассетам, звуки, сокеты, служебные `Desc` | ~250 | 8 («Шут棋局» и т. п.) |
| stringdb | 7594 строк (module\|row) | | 772: `service` 533, `technical` 239 (+6 `clipped`) | ≈6800 | 14 (`alias_case` 10, `alias_tags` 4) |

Классификация сделана скриптом по `untranslated.csv` (CJK = `[㐀-鿿]`, LAT = нет CJK и кириллицы).

### Ложные срабатывания (не переводить)
- **Пользовательский контент (~715 записей)**: ники, чат, гильдии, рейтинги, «Моменты», титулы над головой, дуэли в напоминаниях, пузыри Gossip над игроками (`GossipSystem.PlayBubbleByEidOrUid.argument2` — это сообщения игроков), `SECRET_PARTNER_FOLLOW` «Следует за <ник>», список лайков «<ник>,<ник> и еще N чел.», имена персонажей на выборе роли (`WBP_CreateRoleChooseItem`), имена игроков в Автошахматах (`AutoChess_Hud_Panel/Text_Name`, count 512). Шаблоны вокруг ников уже переведены.
- **Латиница по дизайну**: декоративные английские подписи (`Text_Leon`, `Text_ContentEN`, `Text_DescEN`, `Text_DecFont*`: «LORD OF MYSTERIOUS», «POTION RECIPE», «FADE AWAY», «trading area»), клавиши `ESC`/`TAB`, пиньинь-заглушки Blueprint (`wodezhanji`, `xuanzhong`, `chengyuan`, `didianmingzi`, `rucurhauyu`), `cpdd`/`ypdd` в чате, `ABCDEFG`, заглушки `首字放大`/`路线名`. Все пять строк «ключ отличается регистром» из виджетов (`FADE`, `AWAY`, `TAB`, `area`, `root`) тоже ложные: алиасы для них **не** добавлять.
- **Техническое**: пути `/Game/…`, звуки, сокеты, `DropAll`, `Type2_1`, `OnTrigger(…)`, служебные `Desc` вида `【自走棋】-血蚊-普攻` (в UI не показываются).
- **Мусор диагностики**: 154 записи с текстом `KGTextBlock: 00007FF4… Text 0000…` / `KGRichTextBlock: …`. Это баг рантайма, см. (а1).

### (а) Перевод есть в батчах, но не доходит до экрана — первопричины

**а1. `translateTextWidget` принимает дочерний виджет за текст** (`Init.lua:4434-4444`). Если у виджета нет `GetText`, берётся `tostring(widget.Text)`. У UserWidget (`WBP_SetSwitchItem1`, `WBP_Settings_*_Item`, `WBP_RankingList_Text`, `WBP_ItemTagText`, `WBP_KeyboardShortcut_*`, `WBP_Task_SubTitle_Item`…) `Text` — это дочерний `KGTextBlock`, поэтому получается строка `KGTextBlock: <адрес> Text <адрес>`. Она проходит весь `translateVisibleText`, в конце кэшируется в `visibleTextCache` (`Init.lua:3674`, новый ключ на каждый адрес), а через `d.OnTextWidget` (`Init.lua:4606`) попадает в отчёт. Итог: 154 ложные записи и лишняя работа во всех проходах, в том числе в настройках. Сама диагностика так не читает (`AbsruDiagnostics.lua:1525-1537`, только `GetText`), то есть ошибка в `Init.lua`.

**а2. Таблицы «Железнодорожного магната» (铁路大亨, TrainTrade) не проходят через ремонт строк.** Описания товаров и названия станций приходят на экран китайскими, хотя переводы в батчах есть:
- `多年前，名叫于勒的船员…` → `batch_016.json:1762`; `经典窖藏红酒…` → `batch_012.json:14800`;
- станции `食铺` → `batch_007.json:25654`, `商行` → `batch_008.json:2152`, `酒庄` → `batch_009.json:8062`, `始发站` → `batch_008.json:27718` (все четыре ключа есть в шардах).

На экране получается смесь: `RichText_Content` = «<китайское описание>\n Станция покупки: <LightHighlight>Продуктовая лавка</>…», «Достигнут 食铺.» (`WBP_ReminderTrainTrade_Widget`), «食铺<DarkHighlight>x5</>», «食铺 Количество станций <DarkHighlight> Максимум </>» (`StringConst TRAIN_TRADE_FUTURE_TIPS_NEXT_TYPE`), выпадающий список маршрутов `新手线路/普通线路/进阶线路/困难线路/挑战线路` (`UIComDropDown.Refresh.argument1.N.name`), разбитый заголовок «挑» + «战线路» (`WBP_ComFirstBigText`). Всего 34 записи.
Почему так: шаблоны берутся из StringDB и переводятся (`GetLangStr` → `repairLiveString`, `Init.lua:5669-5709`). Поля описаний и названий берутся из KSBC-таблицы режима, а ремонт строк KSBC ставится только на хелперы из `generatedRowRepairAllowlist` (`Init.lua:5794-5831`), где TrainTrade нет. Промахов StringDB с этими текстами в сессии нет (`t019_stringdb_gaps.csv`: 0 совпадений), значит, текст приходит не из StringDB. Имя хелпера (`Game.TableData.Get<…>DataRow`) по логам не установить — нужна проба (план, шаг R0).
Дополнительно: `StringConst.Get` (`Init.lua:6566-6583`) переводит только готовую строку после форматирования. Китайские аргументы (`%s` = название станции) не переводятся, и составная строка не находится в шардах.

**а3. Подстрочная замена `愚者 → Шут` портит составные строки и ники** (`Init.lua:1221`; применяется к любой строке с CJK без точного перевода в `Init.lua:3668-3675`, результат кэшируется). Через `repairLiveString` (`Init.lua:5201-5216`, `partialKnown`) это попадает и в данные. Примеры из сессии: «Вы инициировали подбор игроков Шут棋局.» (`愚者棋局` = «Гамбит Шута», `batch_013.json:796`), в данных `GetItemNewDataRow.funcRep` «参加Шут棋局玩法可获得…», хэштег игрока `#赞美Шут#`. Строка «Шут棋局» не лучше исходной «愚者棋局»: она сохраняет CJK и выглядит как баг.

**а3′. Односимвольные ключи шардов переводят куски ников.** В шардах есть ключи из одного иероглифа или слова: `["安"] = "Энн"` (`RuntimeTextGemini_238.lua:122`), `["岚"] = "Лань"` (`_08c:72`), `["梦"] = "Мечтать"` (`_3c1:216`), `["Dream"] = "Мечтать"` (`_152:248`). В сессии это дало «晚Энн» (титул над головой, `WBP_AppellationInfo_Lv1`), «格Лань» (`WBP_Manor_Order_Sell_Trader_Item`), «烟雨楼Мечтать» (гильдия в рейтинге). Как ник дробится на части перед поиском, по логам не установлено: виджет получает уже склеенную строку. Эмблемы гильдий (`UIComGuildIcon/Text_Title`) — ровно один иероглиф ника гильдии, и при совпадении с таким ключом эмблема тоже переведётся. Лечится исключением виджетов пользовательского контента в R4. Если дробление найдётся (шаблон `%s` + часть ника), то запретом поиска односимвольных CJK-ключей в этих виджетах.

**а4. Четыре строки с точным ключом в шардах, которые видит только обход диагностики** (`scope = panel:<uid>:walk`: наш проход их не видел или текст выставлен после него):
| Текст | Панель / путь | Перевод | Причина |
|---|---|---|---|
| `欢迎您回到俱乐部！` | `P_NPCTalk … WBP_NPCTalk_Text / RTB_TalkContent` | `RuntimeTextGemini_1b2` | `translateTextWidget` намеренно пропускает `talkcontent` (`Init.lua:4454`), а диалоговый хук эту реплику не перевёл |
| `Upgrade Content` | `WorkshopUp_Panel / Text_Up` | `_1cc` (`batch_012:058831`) | Open (13 виджетов) и delayed (113) — 0 изменений у этой подписи: текст выставлен позже 0,10 с |
| `Plot Overview` | `TaskBoardPanel … WBP_Task_StoryBtn / Text_Name` | `_1d8` (`batch_002:005911`) | то же, кнопка вкладки сюжета |
| `装配` | `FellowMain_Panel … WBP_FellowPage / WBP_PartnerSkill / KGTextBlock_52` | `_2f6` (`batch_020`) | то же, вложенная страница Fellow (`nested:FellowMain_Panel/FellowPage:Open` — `NO_EFFECT`) |

По LESSONS «хуки на уровне класса» чинить хуком `Refresh`/`OnRefresh` класса-владельца, а не таймингами.

**а5. Ключ StringDB отличается регистром, пробелами или тегами** (14 строк, `StringDbGaps` категории `alias_case`/`alias_tags`): «Happy birthday!» / «Happy Birthday!», «Reimbursement form», «State identity», «Sincere persuasion», «Kind comfort», «A Sacrifice», «Steam above!», пролог с отступами `　　` (row 510312176438016), `【猎龙奇谭】` с лишними пробелами, клейма `<CostRed>` против `<Highlight>` (row 440152275039488, 440152275040256), `<HyperLink>` в середине (row 1156760589065730), `暴击叠加伤害` против `<HighLight>…</>`. Лечится `StringDbGaps.ps1 -Aliases` (TRANSLATION_GUIDE §8, шаг 2).

**а6 (инструмент).** `StringDbGaps` отмечает `on_screen` только при полном совпадении текста виджета с `cn`/`en` (`tools/StringDbGaps.ps1:243-277`). Составные строки («Daily Login（1/1）», «Consume 400 Vitality（280/400）», «Achieve 1st place in a match（1/1）») на экране есть, но видимыми не считаются. Поэтому «на экране: 91» — это нижняя оценка.

### (б) Перевода нет в батчах совсем — объём

**StringDB** (промахи `src=stringdb`: CPDD дал английский, русского нет; `cn` есть почти у всех):

| Категория | Строк | На экране (нижняя оценка) | Примеры |
|---|---:|---:|---|
| ui | 2260 | 66 | настройки «Players Only», «Offensive Stance Lockable Types», «Lock-on Line and Box Thickness», «Interface Status Effect Display Settings», «Expand Settings», «Strategic Skill»; Активности «Phase 4», «Hourglass of History», «Time Sand Progress», «Unlocks on October 1»; «Special Duty», «Corrupted Will», таро «Tarot Card: Death», «Squid's Blessing · Potion» |
| text | 2001 | 12 | «Complete the quest to gain 200 Hunt progress…», описания подземелий, «%s Quest will unlock on %s/%s» |
| skill | 679 | 12 | описания баффов «Gain 15% Max Health Shield, lasts 5 seconds» |
| npc | 610 | 0 | реплики |
| buff | 390 | 0 | |
| assistant | 283 | 0 | справка `<Assistant_*>` |
| item | 207 | 0 | |
| mail | 147 | 0 | |
| quest | 139 | 1 | «Talk to <h>Richard</>» (HUD задания) |
| equip | 40 | 0 | |
| autochess | 29 | 0 | |
| loading | 10 | 0 | |
| formula | 7 | 0 | |
| **итого** | **≈6800** | **91** | |

Промахи сессии — это все загруженные строки StringDB, а не только показанные. Реально на экране были 91 строка плюс составные строки (а6).

**Данные KSBC без StringDB** (китайский в полях, `src=data`, ≈250 записей). Это новый контент последнего обновления игры, которого нет и у CPDD:
- Автошахматы: `GetSkillDataNewRow.BriefDescription` 68, `SkillDisc` 29, `Name` 6. Часть — **изменённые обновлением строки**: в батче есть старая версия, новая не совпадает. Примеры: `血焰横扫周围，技能结束后提升自身攻速。` против `batch_033` «血焰横扫周围，提升自身攻速。»; талант `…每回合开始时再获得<HighLight>8金币</>` против `batch_031:886` «每个阶段开始时…6金币»; синергия «魔女» `…魅惑至多<HighLight>1</>个` против `batch_031:766`. Сюда же подсказка загрузки `集齐相同共鸣的棋子…`, `前往使用`, `阶段任务` (`WBP_ActivityAutoChess_Content`).
- Предметы: `GetItemNewDataRow.funcRep` 24, `itemDes` 22, `itemName` 14 (карты таро, эмоции, «Особый рейс: коробка для билетов», украшения).
- Баффы: `BuffName` 10, `BuffName1` 2, `BuffDisc` 18 (англ.).
- Маршруты «Магната» `新手线路…挑战线路` (5): после а2 они придут в ремонт строк, но отдельных переводов этих названий в батчах нет (есть только «新手线路(城堡1级解锁)» и формулировки заданий).

**Английский из виджетов, которого нет ни в StringDB, ни в батчах** (Blueprint/CPDD): «Skip» (`NewbieGuide_MainPanel/Text2`), «Member List» (`GuildInside_Panel/Text_Tab`), «Aesthetic», «Home Coin» (`HomePage_Panel`), «Listed in 2 days» (`Shops_Panel/Text_Lock`), «Team-up Platform». Около 10 строк, добавить в UI-батч с `source_cn` = английский текст (как алиасы `batch_032_stringdb_ui`).

**Замечено попутно:** переключатель «Выкл.» в настройках переведён как «Выключенный» (`Settings_Panel/Text_Off`, 30 записей overflow, размер 21→20). Это правка перевода (короткая подпись), а не баг рантайма.

### Предлагаемый порядок пачек перевода (сначала то, что видно)
1. **Пачка 1 — «видно на экране» (~200 строк):** 91 строка `on_screen` из StringDB, английский из виджетов (≈10), изменённые и новые строки Автошахмат, видимые в сессии (талант, синергия «魔女», подсказка фигуры, подсказка загрузки, `WBP_ActivityAutoChess_Content`), маршруты «Магната», «Выключенный» → «Выкл.». Сюда же алиасы а5 (без ИИ).
2. **Пачка 2 — новый контент KSBC (~250):** навыки Автошахмат (`BriefDescription`, `SkillDisc`, `Name`), предметы (`funcRep`, `itemDes`, `itemName`), баффы.
3. **Пачка 3 — `ui` целиком (≈2200) + `autochess`, `formula`, `loading`, `equip`, `quest` (≈230):** короткие подписи, большая часть в меню и списках.
4. **Пачка 4 — `skill`, `buff`, `mail`, `item`, `assistant` (≈1700).**
5. **Пачка 5 — `text` и `npc` (≈2600):** длинные тексты и реплики, наименьший приоритет.

После каждой пачки — `ShardCompiler.exe`, `VerifyBatch.ps1`, `GlossaryCheck.ps1 -Report`, сборка и проверка в игре пользователем.

## Задержка перевода в настройках (`Settings_Panel`)

**Что показывают логи** (C7.log, `hooks.json → panels`):
```
20:13:01.707 请求打开面板 Settings_Panel
20:13:01.824 面板 Settings_Panel 打开成功                         (+117 мс, 3 кадра)
20:13:01.984 slow panel repair uid=Settings_Panel reason=delayed elapsed_ms=34.00 widgets=1006 labels=0   (+160 мс от «打开成功»)
20:22:33.388 请求打开面板 Settings_Panel
20:22:33.491 面板 Settings_Panel 打开成功                         (+103 мс)
20:22:33.686 slow panel repair … reason=delayed elapsed_ms=61.00 widgets=1006 labels=0            (+195 мс)
panel:Settings_Panel:Open    runs=3 labels=0 widgets=147  ms_max=4
panel:Settings_Panel:delayed runs=3 labels=0 widgets=3023 ms_max=61
```
- **Панель:** `Settings_Panel`, пункты — UserWidget-и `WBP_Settings_Option_Item`, `_Switch_Item`, `_DoubleSwitch_Item`, `_Slider_Item`, `_Button_Item`, `_Title_Item`, `_DoubleKeyBoard_Item`.
- **Какой хук переводит:** наши проходы текст **не переводят** (`labels = 0` в обоих). Русский в подписях настроек приходит на уровне данных: StringDB переводится при загрузке (`Loader.TranslateDatabaseString`, `Init.lua:11586-11629`) или при вызове `GetLangStr` (`Init.lua:5669`). В `late.md` и `fit.md` у `Settings_Panel` нет ни одной записи, вложенных `nested:Settings_Panel/*` нет. Хук `Settings_Option_Item.Refresh` (`Init.lua:9207-9225`) только сжимает строку пресетов графики.
- **Что меняется с задержкой:** проход `delayed` (`panelTextRepair:Queue`, 0,10 с, `Init.lua:10650-10673`; в логе +160…195 мс из-за длинных кадров открытия) обходит 1006–3023 виджетов. В каждом виджете `translateTextWidget` выставляет стиль legacy/cap: размер (авторский + 2 и пороги по длине), `SetFont`, `SynchronizeProperties` (`Init.lua:4508-4605`, на всех текстах, даже без изменения строки). Размер действительно меняется: `overflow.csv`, `Settings_Panel/Text_Off` «Выключенный» — `size_pre 21 → size 20`. Проход занимает 30–61 мс в одном кадре. Весь список настроек **перестраивается** через ~0,2 с после появления и с фризом. Скорее всего, это и выглядит как «перевод с задержкой».
- **Почему не срабатывает ранний перевод:** на момент `Open` пунктов ещё нет (обход `Open` видит 147 виджетов против 1006 у `delayed`): список заполняется после `Open`. Пункты — не UIComponent со своим `Open`/`Refresh` через базовый класс, поэтому ранний перевод вложенных (`RepairNestedEarly`, `Init.lua:10612-10648`) для них не вызывается: записей `nested:Settings_Panel/*` 0. Для пунктов с английским текстом (промахи StringDB, (б)) ранний перевод всё равно ничего бы не дал.
- **Уверенность:** то, что наши проходы в настройках не меняют текст, а только стиль, и что `delayed` стоит 30–61 мс, подтверждено логом. То, что пользователь видит именно перестройку размера, а не смену языка, — **гипотеза**: скриншотов нет, а замены стиля диагностика не считает. Шаг R0 проверяет её пробой, до правки.

## План

### R0. Пробы (только при `DiagnosticsMode` / `absoluteru_dev.lua`, AGENTS §4)
1. **TableData TrainTrade.** В `after_main` (и повторно при первом `Open` любой `TrainTrade*`-панели) перечислить ключи `Game.TableData`, где имя содержит `TrainTrade`/`Station`/`Route`/`Train`. Для каждого `Get*Row`-хелпера записать имя и поля первой строки (строковые с CJK — первые 60 символов). Вывод: `session.json → probes.traintrade_tabledata` и одна строка C7.log `[AbsruDiag] probe traintrade helpers=<имена>`.
2. **Стиль в проходах панели.** В `translateTextWidget` при `runtimeFixes.Diag` считать `style_changes`: `font.Size`, typeface или перенос после стилизации отличаются от значений до неё. Писать счётчик в `panels[]` рядом с `text_changes` и отдельно в `fit`-подобную запись с `panel`, `widget`, `size_pre → size`, `reason` (`Open`/`delayed`/…). В `late.md` добавить колонку `style_changes`.
3. **Таймлайн настроек.** Для `Settings_Panel` писать в `session.json → probes.settings[]` время `Open`, первого и последнего вызова `Refresh` класса пункта (`Settings_*_Item`, хук класса как у Автошахмат: методы у экземпляра при `UIComponent.Open`), `delayed`, `style_changes`, `ms`.
4. Сборка dev, пользователь открывает «Магнат» (любой товар, станцию, список маршрутов) и настройки (3 вкладки), остальное как обычно. Решения R2 и R6 принимать **по результатам** пробы.

### R1. Чтение текста виджета (`Init.lua:4434-4444`)
Принимать `widget.Text` только если это строка или FText: `tostring` не совпадает с `^%w+: %x+ ` и у значения нет `GetText`/`GetName` (это UWidget). Иначе `currentText = nil` (стиль не трогать, `d.OnTextWidget` не звать с мусором). Ожидаемо: 0 записей `KGTextBlock:` в `untranslated.md`, меньше работы в проходах.

### R2. Ремонт строк TrainTrade (после R0.1)
Добавить найденные хелперы TrainTrade в `generatedRowRepairAllowlist` (`Init.lua:5794`). `repairLiveValue` переведёт описания и названия по точному ключу. Если названия станций всё же приходят аргументами в `StringConst.Get` мимо таблиц, в `StringConst.Get` (`Init.lua:6566`) переводить строковые аргументы с CJK **точным** поиском (`lookupGeminiText`, без `visibleTextReplacements`) только для ключей из белого списка (`TRAIN_TRADE_*`). Никогда не переводить аргументы `SECRET_PARTNER_FOLLOW` и других ключей, куда подставляются ники.

### R3. Убрать подстрочную `愚者 → Шут` (`Init.lua:1221`)
Удалить общую замену `{ "愚者", "Шут" }`, оставить `{ "“愚者”：", "«Шут»: " }`. Составные строки с игровым термином-параметром (`愚者棋局` в напоминании) чинить не заменой подстрок, а точным переводом CJK-фрагментов (R4). Проверить `grep` по батчам, что `愚者` в целых строках не держалось на этой замене: такие строки должны находиться в шардах целиком.

### R4. Смешанные строки: перевод CJK-фрагментов (осторожно)
В `translateVisibleText` перед финальным `visibleTextReplacements` (`Init.lua:3668`), если в строке есть и кириллица (или теги), и CJK:
- (а) многострочную строку переводить **построчно** (каждая строка — `translateVisibleText`) и склеивать, если хотя бы одна строка перевелась. Это чинит описание товара «Магната» даже без R2;
- (б) максимальные CJK-фрагменты (с `【】`, длина ≥ 2 символа) заменять **только** при точном попадании `lookupGeminiText(fragment)` без CJK в результате.
Не применять (б) к виджетам пользовательского контента: `Chat*`, `Moments*`, `RankingList*`, `AppellationInfo*`, `HeadInfo*`, `PlayerHonorific*`, `Marquee*`, `ReminderMsgNormal` (дуэли — ники), `*RoleName*`, `GuildInside` (имена/декларации), `UIComGuildIcon`, `Manor_Order*` (`Text_Name` торговцев — ники), `AutoChess_Hud_Panel/Text_Name`. В этих же виджетах не искать в шардах целую строку из **одного** CJK-символа (а3′). Пример из сессии: эмблема гильдии `林`/`原`/`安`. `translateVisibleText` не знает виджета, поэтому (б) делать в `translateTextWidget` (имя и путь известны) отдельной функцией. Тест-лист (офлайн на Lua 5.4 моком шардов, как в LESSONS TASK-018): «Достигнут 食铺.» → «Достигнут Продовольственный магазин.»; «食铺<DarkHighlight>x5</>» → «Продовольственный магазин<DarkHighlight>x5</>»; «君逸 оказался более опытным и выиграл дуэль у 神券.» — **без изменений**; «Следует за 焦虑» — без изменений; «Вы инициировали подбор игроков 愚者棋局.» → «…игроков Гамбит Шута.».
Итоговую строку с оставшимся CJK не класть в `visibleTextCache` (LESSONS «паразитные кэши»; сейчас `Init.lua:3674` кэширует и её, в том числе чат, и кэш растёт без предела).

### R5. Поздние подписи (а4)
По путям из таблицы а4 найти классы-владельцы (`WBP_Task_StoryBtn` → компонент кнопки сюжета `TaskBoardPanel`, `WBP_PartnerSkill` в `FellowPage`, `WorkshopUp_Panel`) и обернуть их `Refresh`/`OnRefresh` на уровне класса (как `installAutoChessClassHooks`, `Init.lua:11259`), с переводом только собственного дерева. Для `P_NPCTalk/RTB_TalkContent` выяснить, почему диалоговый хук (`installDialogueTalkRepair`, `Init.lua:7541`) пропустил реплику клуба (`欢迎您回到俱乐部！`, NPC клуба): текст ставится не через перехваченный метод. Исключение `talkcontent` в `Init.lua:4454` не снимать.

### R6. Настройки (после R0.2–R0.3)
Если проба подтвердит, что `delayed` меняет в `Settings_Panel` только стиль:
- стилизовать пункты сразу после их `Refresh` (хук класса пунктов `Settings_*_Item`, найденных у экземпляров при `UIComponent.Open`; `Settings_Option_Item.Refresh` уже обёрнут, `Init.lua:9217`);
- `Settings_Panel` добавить в `runtimeFixes.SinglePassPanelUids` (`Init.lua:10400`): без 30–61 мс прохода по 1006–3023 виджетам;
- цель: в `late.md` у `Settings_Panel` `style_changes` в `delayed` = 0, строка `slow panel repair uid=Settings_Panel reason=delayed` в C7.log не появляется.
Если проба покажет, что с задержкой меняется **текст** (китайский/английский → русский), то вместо этого найти сайт `SetText` по классу пункта и перевести там, а в TASK записать новую первопричину.

### T. Перевод (б) — конвейер TASK-017, доработанный под новые строки
1. **Алиасы (а5):** `tools\StringDbGaps.ps1 -Aliases batch_030_stringdb_aliases.json -Logs reference\logs\2026-09-26_2031 -Sid 20260926-190040`. Теги сверить (`VerifyBatch`).
2. **Выгрузка новых строк в батч:** новый `batch_034_stringdb_s5.json`.
   - StringDB: `StringDbGaps.ps1 -Emit batch_034_stringdb_s5.json -Category <кат> -Logs … -Sid …` по пачкам из порядка выше. Для пачки 1 нужен фильтр только `on_screen`: добавить в `StringDbGaps.ps1` ключ `-OnScreen` и улучшить `on_screen` (а6): текст виджета начинается с `en`/`cn` и дальше идёт только счётчик `（n/m）`/`(n/m)`, или содержит `en`/`cn` длиной ≥ 6 символов.
   - Данные KSBC (`src=data`, CJK): новый режим `StringDbGaps.ps1 -EmitData <батч> -Fields BriefDescription,SkillDisc,Name,funcRep,itemDes,itemName,BuffName,BuffName1,BuffDisc` → записи `{id, source_cn = text, ref_en = "", target_ru = ""}` из `untranslated-*.jsonl`. Пропускать уже известные ключи, обрезанные (≥ 397 байт, LESSONS TASK-012), модуль `GossipSystem`, `WidgetText`, `StringConst` (ники) и поля `Desc`.
   - Английский из виджетов (≈10 строк, (б)): вручную в тот же батч, `source_cn` = английский текст.
3. **Экспорт чанков с терминами:** в `GlossaryCheck.ps1` добавить `-ExportNew -BatchFile <батч> [-Count 50]`: строки с пустым `target_ru` → `temp/glossary_chunk_NNN.json` в том же формате, что `-Export`, плюс `"mode": "new"` и `names` — совпадения по `source_cn` из `source/glossary/characters_and_factions.json`, `locations_and_geography.json`, `pathways_and_sequences.json`, `terms_and_items.json` (`{cn, ru}`). `-Import` оставить общим: разметка сверяется с `source_cn` (старый `target_ru` пуст), канон — по `terms` строки.
4. **Агент `ru-translator`:** добавить раздел «Режим new» (`mode = "new"` или пустой `target_ru`): перевод с нуля по `source_cn` (`ref_en` — ориентир), термины `terms` — канон, имена и места из `names` — строго как в глоссарии; UI Budget (TRANSLATION_GUIDE §5) для коротких подписей; разметка символ-в-символ (как правило 6); «Выкл.»/«Вкл.» и подобные подписи переключателей — коротко. Формат ответа тот же `{key: target_ru}`.
5. **Скилл `translate-chunk`:** второй сценарий «Новые строки»: `-ExportNew` → до 4 агентов параллельно → `-Import` → `ShardCompiler.exe` → `VerifyBatch.ps1 -BatchFile batch_034_stringdb_s5.json` → `GlossaryCheck.ps1 -Report` (`B` не растёт). Обновить `TRANSLATION_GUIDE.md` §7–8.
6. В этой задаче перевести **пачку 1** (и 2, если время есть). Остальные пачки — отдельными запусками того же скилла, с проверкой в игре после каждой.

### Документы и релиз
- `docs/DIAGNOSTICS.md`: пробы R0 и колонка `style_changes`; `docs/LESSONS.md`: «`widget.Text` у UserWidget — дочерний виджет, не текст», «подстрочная замена термина портит составные строки и ники», «новые таблицы режимов (TrainTrade) не входят в allowlist ремонта строк: при новом режиме проверять `src=data` и `Game.TableData`». `ROADMAP.md` — строка TASK-019. `PROJECT_MAP.md` — `batch_034`, новые ключи `StringDbGaps`/`GlossaryCheck`.
- Версия: следующая после v3.0.2-RU (**v3.0.3-RU**), по правилу ROADMAP во всех местах. Коммит и push; `PackageRelease.ps1` собрать, публиковать по решению пользователя.

## Проверка
- **Автоматическая:** `VerifyPatch.ps1` (синтаксис `Init.lua`, `AbsruDiagnostics.lua`); мок-тест R1/R4 на Lua 5.4 по тест-листу R4; `ShardCompiler.exe`; `VerifyBatch.ps1` по всем изменённым батчам (0 ERR); `GlossaryCheck.ps1 -Report` (`B` не больше, чем до задачи); `StringDbGaps.ps1 -Report` на тех же логах: `alias_*` = 0, `ui`/`on_screen` уменьшились на размер пачки.
- **Чек-лист для пользователя** (dev-файл с `Enabled = true`, `TextFit = "cap"`, как в s5):
  1. C7.log: `[AbsruDiag] probe traintrade helpers=…` (после R0) — прислать строку.
  2. «Железнодорожный магнат»: описание товара **целиком** по-русски («Много лет назад моряк по имени Жюль…»), станции «Продовольственный магазин»/«Торговая фирма»/«Винодельня» в HUD, в напоминании «Достигнут …» и в подсказке «… Количество станций Максимум»; список маршрутов по-русски.
  3. Автошахматы: напоминание о подборе — «Гамбит Шута», без «Шут棋局»; описания навыков фигур и талантов без китайского.
  4. Настройки: открыть 3 раза и переключить 3 вкладки. Подписи сразу в итоговом размере, без перестройки через ~0,2 с. «Только игроки», «Только монстры», «Все враги», «Типы, которые можно захватить…», «Толщина линии и рамки захвата» по-русски, переключатель «Выкл.». В C7.log нет `slow panel repair uid=Settings_Panel reason=delayed` (после R6).
  5. Активности: «Этап 4», «Песочные часы истории», «Ежедневный вход（1/1）» по-русски.
  6. Чат, ники, гильдии не изменились (ни одного русского слова внутри китайского ника, как «晚Энн» или «格Лань»).
  7. `CollectDiagLogs.ps1`: в `untranslated.md` нет `KGTextBlock:`, в «перевод есть, не применился» 0 видимых строк, в `late.md` у `Settings_Panel` `style_changes = 0` в `delayed`.
- «Исправлено» писать только после проверки пользователем (AGENTS §4).

## Исполнение (чат 2, 2026-09-27, v3.0.3-RU)

### Рантайм (`Init.lua`)
- **R1.** `translateTextWidget`: `widget.Text` принимается за текст, только если это не UWidget (`GetText` / `GetName`) и `tostring` не вида `^[%w_]+: %x+ `; иначе функция сразу возвращает 0 (дочерний блок переводится, когда до него доходит обход).
- **R3.** Общая замена `{ "愚者", "Шут" }` удалена, `«“愚者”：» → «Шут»: ` оставлена. Батчи: 692 строки с `愚者` лежат в шардах целиком; 3 строки с `<愚者>` внутри находились точным ключом и раньше.
- **R4.** `translateVisibleText`: многострочная смешанная строка (CJK + кириллица или теги) переводится построчно (`runtimeFixes.translateMixedLines`); итог с оставшимся CJK не кладётся в `visibleTextCache`, а идёт в ограниченный кэш промахов `runtimeFixes.VisibleMiss` (4096, при переполнении очищается). `translateTextWidget`: если после перевода остался CJK — в виджетах пользовательского контента (`runtimeFixes.UserContentWidgetPatterns` по пути виджета: чат, «Моменты», рейтинги, титулы, `HeadInfo`, `ReminderMsgNormal`, гильдии, эмблемы, `Manor_Order`, `AutoChess_Hud_Panel…Text_Name`, выбор роли) принимается только полный перевод, строка из одного иероглифа не переводится; в остальных — `translateMixedFragments` (максимальные CJK-фрагменты ≥ 2 символов, `【…】` целиком или внутренность, точный `lookupGeminiText` без CJK в результате). Строки `StringConst` с китайскими аргументами (кроме `TRAIN_TRADE_*`) помечаются как пользовательские (`noteUserContentText`) и фрагментами не переводятся: в шардах `焦虑` = «Тревожный», и «Следует за 焦虑» иначе испортилось бы.
- **R2 (часть без пробы).** `StringConst.Get`: для ключей `TRAIN_TRADE_*` китайские строковые аргументы переводятся точным `lookupGeminiText` до форматирования (лог s5: `module=StringConst field=TRAIN_TRADE_FUTURE_TIPS_NEXT_TYPE`, «食铺 Количество станций»). **Ждёт пробы:** имена хелперов TrainTrade для `generatedRowRepairAllowlist`; до пробы описание товара лечит построчный перевод R4, станции в тексте — фрагменты R4.
- **R5.** `runtimeFixes.installLateLabelClassHooks` (вызов в `UIComponent.Open/Refresh` для не-Автошахмат): для классов `TaskBoardPanel`/`Task_Main_Panel` (`WBP_Task_StoryBtn/Text_Name`), `FellowPage` (`WBP_PartnerSkill/KGTextBlock_52`), `WorkshopUp_Panel` (`Text_Up`) обёрнуты методы уровня класса `Refresh*`/`OnRefresh*`/`Update*`/`Show*`/`Set*`/`Play*`; после вызова переводятся только перечисленные виджеты экземпляра. Реплика клуба: её показывает `P_NPCTalk` (класс `NPCTalkTextComp`, `owner:P_NPCTalk/NPCTalkTextComp` в s5), а `installDialogueTalkRepair` оборачивает только `DialogueTalk` — поэтому она и не переводилась; у `NPCTalkTextComp` те же методы переводят китайские строковые аргументы точным поиском (`talkcontent` в `translateTextWidget` не тронут). Имена классов взяты из `hooks.json` s5; какие методы реально срабатывают — `late-class:*` в `hooks.json` следующей сессии.
- **R6 — не делался.** Ничего из R6 без пробы не обосновано: `Settings_Panel` в `SinglePassPanelUids` не добавлен, стилизация пунктов после их `Refresh` не добавлена.

### Диагностика (R0, только при `absoluteru_dev.lua`)
- `D.ProbeTrainTrade` → `session.json → probes.traintrade_tabledata`, C7.log `[AbsruDiag] probe traintrade stage=… helpers=…` (в `after_main` и при первом `Open` панели `TrainTrade*`).
- `D.StyleSnapshot` / `D.NoteStyle` из `translateTextWidget` → `style_changes` в `panels[]`/`hooks[]`, строки `fit` с `kind = "style"`.
- `D.ProbeSettingsHooks` → `probes.settings[]`: `Open`, первый/последний `Refresh` пунктов `Settings_*_Item` (обёртки класса), проходы панели с `ms`, `widgets`, `style_changes`.
- `CollectDiagLogs.ps1`: колонка `style_changes` в `late.md` (проходы и классы), раздел «Пробы TASK-019» в `late.md`, раздел «Смена стиля без смены текста» в `fit.md`. Прогон на копии s5 без ошибок.

### Инструменты перевода
- `StringDbGaps.ps1`: `-OnScreen` для `-Emit`; `on_screen` засчитывает текст со счётчиком `（n/m）` и вхождение ≥ 6 символов (91 → 108 на s5); `-EmitData <батч> -Fields …` (проверен на временном батче: 159 строк пачки 2, превью `temp/t019/pack2_preview.json`, в батчи не записано).
- `GlossaryCheck.ps1 -ExportNew -BatchFile <батч>`: `mode = "new"`, `terms`, `names` (из `characters_and_factions`, `locations_and_geography`, `terms_and_items`, `pathways_and_sequences`). `-Import`: у строки с пустым старым `target_ru` разметка сверяется только с `source_cn` (раньше пустая старая строка пропускала потерю тегов).
- `.claude/agents/ru-translator.md` — раздел «Режим new»; `.claude/skills/translate-chunk/SKILL.md` — сценарий «Новые строки». Агент правился в этой же сессии, поэтому перевод шёл через `general-purpose` с его инструкцией (LESSONS TASK-017).

### Перевод
- Алиасы а5: 14 строк в `batch_030` (id 132959…132972). У двух `<CostRed>`-клейм перевод ключа был с `<Highlight>` — теги исправлены вручную; у `暴击叠加伤害` сняты теги, которых нет в источнике; в «С днем рождения!» убраны невидимые ZWSP.
- Пачка 1 в `batch_034_stringdb_s5.json` (132 строки, id 132973…133104): 108 строк StringDB `on_screen` (`-Emit … -OnScreen`), 24 вручную — маршруты «Магната» (5), 3 эффекта карт «Магната», описание сложности, строки Автошахмат (навык 血焰, талант 10/8 золота, синергия 魔女 ×3, подсказка загрузки, `前往使用`, `阶段任务`, `参与奖励预览`), английские подписи Blueprint (`Skip`, `Member List`, `Aesthetic`, `Home Coin`, `Listed in 2 days`, `Promote`). Не взяты: `挑` / `战线路` (игра дробит заголовок на первую букву; после перевода маршрута в данных строка придёт русской), заглушка `路线名`. Импорт: 132 принято, 0 отклонено; вручную — единое «Возвращение Императора · Обычный» и «Адвокат» Сио Дереча (как у фигуры Автошахмат в остальных батчах).
- Имя `休·迪尔查` (Xio Derecha) приведено к «Сио Дереча» везде (по решению пользователя): 21 строка в 9 батчах (было «Хью Дилча», «Хью Дирча», «Сью Дирча», «Сью», «Хью», «Хью, Императивный Маг» → «Адвокат» Сио), род в `batch_024:116126` («Сио действовала», «была оправдана», «Форс пришла»), строка бонуса мест Клуба Таро в `Init.lua`, глоссарий («Мисс Суд (Сио Дереча)» вместо «Сио Деррек» и отдельная запись `休·迪尔查` для `names`), `docs/GLOSSARY.md` пересобран.
- «Выключенный» → «Выкл.» (`batch_021:104482`, `关`), попутно `开` «На» → «Вкл.» (`batch_018`, та же пара переключателя).
- Для глоссария (пачка 2): `活力` в старых батчах — «жизненная сила» / «бодрость» / «жизнеспособность»; в пачке 1 — «бодрость».

### Проверка (автоматическая)
- `VerifyPatch.ps1`: OK (Init.lua 179 локальных верхнего уровня, AbsruDiagnostics.lua 142).
- Мок на Lua 5.4 с настоящими шардами: `temp/t019/test_r4.lua` — 26/26 (тест-лист R4, R1, R3, а3′, кэш, R2 `TRAIN_TRADE_*`/`SECRET_PARTNER_FOLLOW`, R5); `temp/t019/test_r0.lua` — 11/11 (пробы, `style_changes`, `session.json`, `hooks.json`, `fit`).
- `ShardCompiler.exe`: 133 074 строки, 1024 шарда. `VerifyBatch.ps1`: 0 ERR по всем батчам.
- `GlossaryCheck.ps1 -Report`: B 0 → 0, C 0 → 0 (строк с терминами 942 → 948, все новые — ok).
- `StringDbGaps.ps1 -Report` (те же логи и sid): без русского 7594 → 7473; на экране 108 (91 по старому правилу) → 1; `alias_case` 10 → 0, `alias_tags` 4 → 0; `ui` 2260 → 2179, `skill` 679 → 666, `text` 2001 → 1988, `quest` 139 → 138. Оставшаяся «на экране» строка — формат префикса чата `<ChatTag_Current>%s</>: %s` (перевод без кириллицы, скрипт считает его `pending`).
## Промпт для чата исполнения
> Исполни `docs/tasks/TASK-019-untranslated-s5.md` (AGENTS.md §3, чат 2). Логи сессии s5 уже лежат в `reference/logs/2026-09-26_2031/`; CSV промахов при необходимости пересоздай: `powershell -ExecutionPolicy Bypass -File tools\StringDbGaps.ps1 -Report -Logs reference\logs\2026-09-26_2031 -Sid 20260926-190040 -Csv temp\t019_stringdb_gaps.csv`.
> Порядок: **R0** (dev-пробы: хелперы `Game.TableData` TrainTrade, счётчик `style_changes`, таймлайн `Settings_Panel` — только при `runtimeFixes.Diag`/DiagnosticsMode), **R1** (`Init.lua:4434-4444`: не принимать дочерний UWidget из `widget.Text` за текст), **R3** (убрать общую замену `愚者→Шут`, `Init.lua:1221`), **R4** (смешанные строки: построчный перевод и точный перевод CJK-фрагментов в `translateTextWidget` с исключением виджетов пользовательского контента; не кэшировать итог с CJK, `Init.lua:3674`; мок-тест на Lua 5.4 по тест-листу из TASK), **R5** (хуки уровня класса для четырёх поздних подписей из таблицы а4). **R2** и **R6** реализуй условно: только те ветки, что можно обосновать без данных пробы. Если нельзя (имя хелпера TrainTrade, стиль против текста в настройках), оставь их выключенными за проверкой пробы и явно перечисли в отчёте, что ждёт сессии пользователя.
> Перевод: алиасы (`StringDbGaps -Aliases batch_030_stringdb_aliases.json`), доработки `StringDbGaps.ps1` (`-OnScreen`, улучшенный `on_screen`, `-EmitData`), `GlossaryCheck.ps1 -ExportNew` с `names` из глоссариев, режим «new» в `.claude/agents/ru-translator.md` и сценарий «Новые строки» в `.claude/skills/translate-chunk/SKILL.md`. Затем **пачка 1** («видно на экране», ~200 строк) в новый `source/translation_batches/batch_034_stringdb_s5.json` через `/translate-chunk` (агент `ru-translator`; если он не подхватился после правки в этой же сессии — `general-purpose` с его инструкцией, LESSONS TASK-017). Включи «Выключенный» → «Выкл.». Ложные срабатывания из раздела TASK (ники, чат, декоративная латиница, `FADE`/`AWAY`/`TAB`/`area`/`root`) не трогать.
> Проверка: `VerifyPatch.ps1`, `ShardCompiler.exe`, `VerifyBatch.ps1` (0 ERR), `GlossaryCheck.ps1 -Report`, `StringDbGaps.ps1 -Report` на тех же логах (сравнить с TASK). `.ps1` с кириллицей — UTF-8 с BOM; Lua/JSON — UTF-8 без BOM, LF. Папку игры не трогать.
> Документы: DIAGNOSTICS.md (пробы, `style_changes`), LESSONS.md (три урока из TASK), ROADMAP.md, PROJECT_MAP.md, TRANSLATION_GUIDE.md §7–8; версия v3.0.3-RU по правилу ROADMAP; раздел «Исполнение» в TASK-019 (что сделано, что ждёт пробы, числа до/после). Коммит, push. Собери релиз `PackageRelease.ps1`, но не публикуй без решения пользователя. В конце дай пользователю чек-лист из раздела «Проверка» TASK-019, в том числе какие строки C7.log прислать после проб.
