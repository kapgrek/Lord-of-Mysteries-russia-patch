# TASK-030: «много не переведено» в сессии 2026-10-10 (v3.0.10)

## Симптом
Сессия 2026-10-10 06:14–07:35 (`reference/logs/2026-10-10_0736`, sid `20261010-061421`, слот 2, dev-диагностика включена). Пользователь: «там много не переведено».

## Первопричина

### 1. В игре старая сборка: v3.0.11 не выпущен (главная причина)
- `C7.log` 06:14:47: `[CPDDRuntimeFix] v3.0.10-RU active hooks_installed=26`. Последний тег в git — `v3.0.9-RU`, релиз v3.0.10 — коммит `e8c7b000` (2026-10-02).
- После него в `main` лежат, но в игру не попали: TASK-027 (`030ffd6f` буквица, `67a5b6bf` пачка 1 → `batch_043_t027`), TASK-028 (`d5c02a2a` R1–R3, `1436b7e3` пачка → `batch_044_t028`), TASK-029 (`c72eb7e2` глоссарий резонансов, FixShort).
- `report/untranslated.md → «перевод есть, не применился»` (13 видимых): 10 строк из `batch_044_t028` (`秘偶名字` ×256, 9 описаний навыков `SkillDisc` из `GetSkillDataNewRow`) и 4 из `batch_043_t027`. Перевод готов, он просто не установлен.
- `Home Coin` / `Aesthetic` (`HomePage_Panel`, `batch_034`) — тот же случай, что TASK-028 §2. Проба `walk_exact` (TASK-028 R3) есть только в `main`, в v3.0.10 её нет, поэтому данных для выбора исправления пока нет.

### 2. Аргумент `%s` в напоминании не переводится (баг рантайма, подтверждён)
- `untranslated.csv`: `WidgetText / RTB_Content` → `Вы инициировали подбор игроков 愚者棋局.` Шаблон переведён (`batch_015`, ~7013: `You initiated %s matchmaking.` → `Вы инициировали подбор игроков %s.`), а название режима подставлено китайским. Ключ при этом есть: `batch_013:060132` `愚者棋局` → «Гамбит Шута» (канон `docs/GLOSSARY.md`).
- Перевод хвоста делает `runtimeFixes.translateMixedFragments` (`Init.lua:3765`), но виджет `WBP_ReminderMsgNormal` входит в `runtimeFixes.UserContentWidgetPatterns` (`Init.lua:3817-3821`, `"remindermsgnormal"`), и фрагменты в нём не переводятся. Сделано это намеренно (TASK-019 а3′): в тех же напоминаниях приходят ники (`Запрос на добавление в друзья отправлен на 笑灬奈何.`, та же сессия).
- Значит, нужен узкий список игровых терминов, которые переводятся и в пользовательских виджетах, а не снятие запрета целиком.

### 3. Новые строки игры (ключей в батчах нет)
Из 744 строк «нет в батчах» настоящих строк игры 13; остальное — контент игроков (ники в `Manor_Order*`, `AutoChess_Hud_Panel/Text_Name`, `WBP_ManorList_Item`, `CreateRoleChooseItem`, чат и пузыри `GossipSystem.PlayBubbleByEidOrUid`, «Моменты», `GuildInside_Panel`, `MANOR_ORDER_TIPS_GOTO_OTHER_HOME … <ник>`, `Замок игрока <ник>`), пути ресурсов, идентификаторы (`*_N`, `*_P`, `MODULE_LOCK_*`) и внутренние описания навыков `【自走棋】…` (`GetSkillDataNewRow/Desc`, на экран не выводятся). Это не переводим.

| поле / виджет | текст | где видно |
|---|---|---|
| `GetTrainStrategyCardDataRow/CardDescText` ×5 | `如果下一站<LightHighlight>是【酒庄】</>…-75%…`, `…是【食铺】</>…+125%…`, `…是【食铺】</>…【珍品迷雾香槟】…150%…-40%`, `每4个<LightHighlight>艺术品、酒类</>…【冰鲜雪贝薄片】`, `每4个<LightHighlight>艺术品、食品</>…【珍品迷雾香槟】` | `TrainTradeCard_Panel … RichText_Dec` (карточки стратегии поезда) |
| `GetItemNewDataRow/funcRep` ×3 | варианты `…<Highlight>64装等</>或<Highlight>65装等</>…` (сундуки снаряжения: «冒险倾向 … 灰雾尘埃», «交易之契 …», «每<Highlight>20进度</>…») | `WBP_Lib_MainText/Text_TipsContent_lua` (подсказка предмета) |
| `GetSkillDataNewRow/SkillCastDesc` | `前方10格矩形` | подсказка навыка (дальность) |
| `AutoChess_TalentCard_Item/RichText_Description` | `获得<HighLight>1个侍女</>。其技能强化为：<HighLight>连续斩击，获得基于最大生命值的短时护盾</>。` | Автошахматы, выбор таланта (хук `ac-class` сработал, ключа нет; как TASK-029 R3) |
| `TrainTradePrepare_Panel … WBP_ComFirstBigText` | `路线名` | подготовка поезда, выбор маршрута |
| `WorkShop_UpgradePopup_Panel/Click_Text` | `Click blank area to close` | всплывающее окно улучшения в мастерской (английский из Blueprint) |

Похожие строки с другими уровнями (`62/64`, `64/66`) в батчах уже есть (`batch_027` ~3364–3826, `batch_011`, `batch_002`): их переводы брать за образец.

- StringDB: `StringDbGaps -Report` → 719 промахов, **0 на экране** (`service` 481, `technical` 228, `clipped` 6, `known` 4). Ничего не выгружать.
- Ошибок `[CPDDRuntimeFix] … error/failed/exception` в `C7.log` нет.

### 4. Не ошибка
- `TAB` (`PhotographPC_Panel`), `trading` / `area` (`TrainTrade_Hud_Panel/Text_DecFont01/02`), `LORD OF MYSTERIOUS` (`Text_Leon`), `II` — декоративная латиница и названия клавиш (TASK-006, TASK-028 §4).
- `咪` (`GuildInside_Panel/Text_Title`), `猫咪之家` — названия гильдии и усадьбы игроков.

## План

### R1. Термины в пользовательских виджетах (`Init.lua`, чат исполнения)
1. Рядом с `UserContentWidgetPatterns` (`Init.lua:3817`) завести `runtimeFixes.UserContentGameTerms` — множество CN-ключей, которые переводятся и в пользовательских виджетах. Начальный состав: `愚者棋局`. Другие названия режимов добавлять только по логам.
2. Там, где для пользовательского виджета отключается `translateMixedFragments`, вместо полного пропуска перевести только CJK-прогоны, которые **целиком** совпадают с ключом из этого множества, отделены по `isStandaloneCjkRun` (`Init.lua:3743`) и имеют перевод без CJK. Остальной текст (ники) не трогать, проверку `UserContentTexts` (`Init.lua:3769`) не ослаблять.
3. Мок Lua 5.4: `WBP_ReminderMsgNormal/RTB_Content` с текстом `Вы инициировали подбор игроков 愚者棋局.` даёт `… Гамбит Шута.`; `Запрос на добавление в друзья отправлен на 笑灬奈何.` не меняется; ник `愚者棋局` в `Manor_Order…/Text_Name` (без кириллицы) не меняется.
4. В Diag-режиме при замене один раз написать в C7.log `[CPDDRuntimeFix] user-content term <cn>`.

**Итог R1 (чат исполнения).** Механизм уже был в v3.0.10: `runtimeFixes.UserContentTermFragments` + `translateUserContentTerms` (TASK-022 R1, `0e1b6904`), вызов в `Init.lua:4852-4867`. Строка в отчёте ложная: в логе сессии есть только запись `src=data` (`absru-s2-untranslated-002.jsonl`, 06:15:57), которую пишет `repairLiveString` до прохода по терминам. Записи `src=widget` с итоговым текстом виджета (`AbsruDiagnostics.lua:1760`) нет, хотя для ника `笑灬奈何` в том же виджете она есть. Значит, на экране уже было «Гамбит Шута». Исправлено два пункта: голый ник `愚者棋局` без кириллицы больше не переводится (п. 3 плана), добавлена Diag-строка `user-content term <cn>` (п. 4). Мок: `temp/t030/terms_test.lua`, 5/5 ok.

### R2. Пачка перевода (отдельный чат, `/translate-pack`)
Батч `batch_045_t030.json`:
- `StringDbGaps -EmitData batch_045_t030.json -Fields CardDescText,funcRep,SkillCastDesc -Logs reference\logs\2026-10-10_0736\Saved\Mods\logs -Sid 20261010-061421`.
- `-EmitList` (файл в `temp\t030\emit_list.txt`): `获得<HighLight>1个侍女</>。其技能强化为：<HighLight>连续斩击，获得基于最大生命值的短时护盾</>。`, `路线名`, `Click blank area to close` (английская: `source_cn = ref_en`). Если `funcRep` / `CardDescText` не выгрузятся через `-EmitData`, добавить их полные тексты из `report/untranslated.csv` в тот же список.
- Канон: термины поезда — `source/glossary/ui_traintrade.json` (`酒庄`, `食铺`, `珍品迷雾香槟`, `冰鲜雪贝薄片`, `物产`); сундуки — по образцу `batch_027` ~3364/3634 (`装等`, `冒险倾向`, `灰雾尘埃`, `苏勒`, `交易之契`); `侍女` — по батчам Автошахмат (проверить имя фигуры); `路线名` — подпись «Название маршрута»; `Click blank area to close` — как другие такие подписи в батчах («Нажмите на пустое место, чтобы закрыть»: свериться поиском). Теги `<LightHighlight>`, `<HighLight>`, `<HyperLink …>`, `【…】` и числа сохранить.

### R3. Релиз v3.0.11
После R1 и R2: `PackageRelease.ps1 -Publish` → v3.0.11-RU. В сборку входят TASK-027, TASK-028 (R1–R3 + `batch_044`), TASK-029 (глоссарий + FixShort) и TASK-030. Незавершённые TASK-029 R2.2/R3 (корзины B/C, канон 窥秘人) релиз не блокируют. Если пользователь хочет включить их, чат перевода делает их до сборки.

## Проверка
- Автоматическая: мок R1, `VerifyPatch`, `ShardCompiler`, `VerifyBatch` 0 ERR.
- Чек-лист для пользователя (после установки v3.0.11, с `absoluteru_dev.lua`):
  1. `C7.log`: `[CPDDRuntimeFix] v3.0.11-RU active`.
  2. Окно навыков и подсказки: 9 описаний (звёздный песок, луч, гигант, «Палящее солнце», воздушные пули…) по-русски; имя марионетки — «Имя марионетки».
  3. Запустить подбор в «Гамбит Шута»: напоминание «Вы инициировали подбор игроков Гамбит Шута.»; в `C7.log` — `user-content term 愚者棋局`.
  4. Поезд: карточки стратегии (酒庄/食铺/шампанское), подготовка поезда — подпись маршрута по-русски.
  5. Подсказка сундука снаряжения 64/65 и окно улучшения в мастерской («Нажмите…») — по-русски.
  6. Автошахматы, выбор таланта: карточка «служанка…» по-русски.
  7. «Задания», «Усадьба» → главная (`Home Coin`, `Aesthetic`), пробыть 5 с. После выхода снова собрать логи: в `late.md` появится раздел «Пробы TASK-028» (`walk_exact`), по нему следующий аналитический чат решит вопрос с этими подписями.

## Промпты

### Чат исполнения
```
Чат исполнения (AGENTS.md §3). Выполни R1 из docs/tasks/TASK-030-untranslated-v3010-s3.md. Перевод (R2) не делать.
R1: runtimeFixes.UserContentGameTerms = { 愚者棋局 } рядом с UserContentWidgetPatterns (Init.lua:3817). В пользовательских виджетах (remindermsgnormal и т. п.) переводить только CJK-прогоны, целиком равные ключу из этого множества (isStandaloneCjkRun, Init.lua:3743; перевод без CJK). Ники не трогать, проверку UserContentTexts (Init.lua:3769) не ослаблять. В Diag один раз в лог: "user-content term <cn>".
Мок Lua 5.4 на три случая из плана (Гамбит Шута переводится; «Запрос … 笑灬奈何.» и ник 愚者棋局 в Manor_Order без кириллицы не меняются), VerifyPatch. Код читать точечно по ссылкам файл:строка. Коммит и push; релиз (R3) собрать только после коммита пачки R2 — спросить пользователя.
```

### Чат перевода
```
/translate-pack
Пачка: TASK-030 (docs/tasks/TASK-030-untranslated-v3010-s3.md, раздел R2).
Батч: source/translation_batches/batch_045_t030.json — StringDbGaps -EmitData -Fields CardDescText,funcRep,SkillCastDesc -Logs reference\logs\2026-10-10_0736\Saved\Mods\logs -Sid 20261010-061421; плюс -EmitList (temp\t030\emit_list.txt): 获得<HighLight>1个侍女</>。其技能强化为：<HighLight>连续斩击，获得基于最大生命值的短时护盾</>。 / 路线名 / Click blank area to close (английская: source_cn = ref_en). Если funcRep или CardDescText не выгрузились — их полные тексты взять из reference\logs\2026-10-10_0736\report\untranslated.csv в тот же список.
Канон: поезд — source/glossary/ui_traintrade.json; сундуки 64/65 装等 — по образцу batch_027 (~3364, ~3634); 侍女 — как в батчах Автошахмат; 路线名 — «Название маршрута»; теги <LightHighlight>/<HighLight>/<HyperLink …>, 【…】 и числа сохранять.
Код не трогать, файлы не читать — только команды скилла. В конце — коммит и push, короткий итог.
```
