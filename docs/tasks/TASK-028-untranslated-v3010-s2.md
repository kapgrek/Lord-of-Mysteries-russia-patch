# TASK-028: «#CanMoveЯ#» на HUD, английский и китайский после v3.0.10 (сессия 2026-10-03)

## Симптом
v3.0.10-RU, сессия 2026-10-03 13:18–13:44 (`reference/logs/2026-10-03_1423`, sid `20261003-131849`, dev-диагностика включена). Пользователь: «местами английский текст и немного китайского».

Установлен v3.0.10 (`C7.log`: `[CPDDRuntimeFix] v3.0.10-RU active hooks_installed=26`). Коммиты TASK-027 (`030ffd6f` R2 буквица, `67a5b6bf` пачка 1: `大帝重临`, `全套方案`, `誓约值`, `战略金镑`, `神眷牌`) вышли **после** сборки v3.0.10, поэтому эти строки в игре ещё китайские/английские. Они уже исправлены в `main` и войдут в следующий релиз.

## Первопричина

### 1. Подсказка клавиши «I» на HUD показывает `#CanMoveЯ#` (баг данных, подтверждён)
- `fit-*.jsonl`, 13:19:59: `HUD_Panel … WBP_ConstantDisplay_Icon_RightList … WBP_KeyPrompt … text_key_lua`, `text = "#CanMoveЯ#"`, `need_pre = 6.3` (исходный текст — одна узкая буква), `kind = fail` (20 → 12, не помещается). Тот же виджет в `C7.log`: `text fit fail size 20->12 budget=7.3 text=#CanMoveЯ#`.
- Источник: `source/translation_batches/batch_014.json` id `067493` (строка ~14908): `source_cn "#CanMove我#"`, **`ref_en "I"`**, `target_ru "#CanMoveЯ#"`. У всех остальных `#CanMove…#` записей `ref_en` тоже с маркером (`#CanMoveYou#` и т. д.).
- `tools/ShardCompiler.cs:95-110` кладёт `ref_en → target_ru` как ключ, если в `ref_en` есть буква. Получается ключ `"I" → "#CanMoveЯ#"`, и любой виджет с текстом «I» (клавиша инвентаря в `WBP_KeyPrompt`) переводится в мусор.
- Те же EN-ключи есть у названий клавиш (скан батчей): `Enter → Войти` (`batch_003:011395`), `Right → Верно` (`batch_008:038840`), `Home → Дом` (`batch_026:126604`), `Tab → Вкладка`, `Space → Пробел`, `Delete → Удалить`, `End → Конец`, `Up/Down/Left`. В этой сессии на экране не видны, но в `text_key_lua` дали бы тот же класс ошибки.

### 2. Перевод есть, но проходы до виджета не доходят (повтор TASK-027 R4)
`untranslated.md → «перевод есть, не применился»`, все со scope `panel:<uid>:walk` — текст видит **только** обход диагностики, наши проходы — нет:
| текст | ключ | путь |
|---|---|---|
| `Plot Overview` | `batch_002:005911` → «Обзор сюжета» | `TaskBoardPanel … WBP_Task_StoryBtn … Text_Name` |
| `大神推荐` | `batch_007:032569` | `QuickAssembly_PC_Main_Panel … WBP_QuickAssembly_Recommend … Btn_Recommend … Text` |
| `Home Coin`, `Aesthetic` | `batch_034` | `WBP_ManorMessagesPage … WBP_ContentPaper … Text_Title_6 / Text_Title_4` |

- Для `Plot Overview` уже есть late-хук (`Init.lua:11866-11867`, `LateLabelClasses.TaskBoardPanel` / `Task_Main_Panel`, путь `WBP_Task_StoryBtn → Text_Name`). Класс `TaskBoardPanel` — это `Task_Main_Panel`: в `C7.log` только `installed late-label class hook Task_Main_Panel: OnRefresh`, хук `late-class:Task_Main_Panel.OnRefresh` — `calls=5`, `text_changes=0` (`absru-s2-hooks.json`).
- В `probes.text_skip` записей с этими текстами **нет**. `translateTextWidget` пишет `text_skip`, если видит текст с точным ключом и не меняет его (DIAGNOSTICS, TASK-022). Значит, ни `Open`, ни `delayed` (у `TaskBoardPanel` их 32 за сессию, 1400–2850 виджетов), ни late-хук этот виджет с этим текстом **не получали**. Возможны две причины: (а) структура — наш обход и `findLateLabel` не спускаются в дерево вложенного UserWidget без Lua-компонента; (б) время — текст ставится после всех проходов, а обход диагностики (0,5 / 2,0 с) его застаёт. Логи эти варианты не различают, поэтому R3 — проба (AGENTS §4).

### 3. Новые строки (ключей в батчах нет)
Контент игроков (ники, названия команд и усадеб, чат, «Моменты», `猫咪之家`, `PVE sup`, `恶` в значке гильдии) — не перевод, пропускаем.
- `GetSkillDataNewRow/SkillDisc` — 8 описаний навыков (`在目标区域降下星沙…`, `向锁定目标发射光束…`, `手握巨剑旋转挥砍…`, `获得buffdisc(*id)…霸体…挥舞双剑…` ×2, `召唤巨人虚影…`, `在2.7秒内…空气子弹…`, `进入持续*f秒的<HighLight>烈阳</>…`, `施放除普攻外的战斗技能后…足迹…`).
- `LanguageData.StringDB_CN_Data/RawText` — ~16 реплик-пузырей NPC (`妈妈我饿了……`, `谁会想打开一个木桶呢！`, `猫！猫！猫！到处都是猫！`, `嘿！站住！你已经被锁定了！再乱动就击毙！`, `玛格丽特小姐好像还没来…` и т. д.).
- `WidgetText`: `秘偶名字` (`Text_Name`, 64 раза), `非凡方案一二三` (`Text_Content`), `玩家的队伍` (`KText_TeamName`), `分线选择` (`Text_Choose`).
- Английский из Blueprint: `Reset All` (`Talent_Panel/Text_Reset`), `Act` (`SequencePromotion_Panel … WBP_SequenceSliderVertical/Text_Progress_1`).
- `共次数奖励：0/5` (`WBP_GameplayIntegration_DungeonEntrance_Item/Text_Lable`) — числа подставляет игра, шаблона в логах нет (как в TASK-027 R3) → пропустить.
- StringDB: `StringDbGaps -Report` по сессии — 723 промаха, **0 на экране**: `service` 482, `technical` 231 (внутренние имена баффов `_buffappear`/`_buffdata`, тесты), `known` 4 (уже переведены пачкой TASK-027), `clipped` 6. Ничего не выгружать.

### 4. Не ошибка (по решению TASK-006)
Декоративная латиница шрифтом TheLeon (`Font_Mistery`) остаётся английской, как в китайском клиенте: `POTION RECIPE` (`Text_PotionLeon`), `EXTRAORDINARY`, `SEQUENCE` (`TextSequenceEn`), `LORD OF MYSTERIOUS` (`Text_Leon`), подписи `Text_ContentEN` / `Text_DescEN` в окне продвижения последовательности. Обозначения клавиш `ESC`, `TAB` и `SAN` на HUD тоже не переводятся.

## План

### R1. Данные и компилятор: ключ «I» (чат исполнения)
1. `batch_014.json` id `067493`: `ref_en` `"I"` → `"#CanMoveI#"`; `source_cn` и `target_ru` не трогать.
2. `tools/ShardCompiler.cs:98-110`: EN-ключ не создавать, если (а) `source_cn` содержит `#CanMove`, а `ref_en` — нет, или (б) `ref_en` после trim — одна латинская буква. Счётчик `enSkippedMarker`, вывести рядом с `enSkippedNoLetter`.
3. `tools/VerifyBatch.ps1`: WARN на те же два случая, чтобы новые батчи их не приносили.
4. Пересобрать `ShardCompiler.exe` (`tools/BuildTools.ps1`), запустить `ShardCompiler`, `VerifyBatch`. Проверить по шардам, что ключа `"I"` нет, а `"#CanMove我#"` есть.

### R2. Защита подсказок клавиш (`Init.lua`, чат исполнения)
В `translateTextWidget` (`Init.lua:4723`): если имя виджета `text_key_lua` (или путь содержит `WBP_KeyPrompt`), а в тексте нет CJK, текст не переводить и не стилизовать (ранний выход, как у `talkcontent`/`esc`). Китайские подписи клавиш (`空格`) по-прежнему переводятся. Обоснование — п. 1: латинские названия клавиш совпадают с EN-ключами (`Enter`, `Home`, `Right`…).

### R3. Проба «видит только обход» (только при Diag, чат исполнения)
1. `LateLabelClasses.Task_Main_Panel` (`Init.lua:11867`): добавить `probe = "taskstory"` и `methods = { "^Refresh", "^OnRefresh", "^Update", "^Show", "^Set", "^On", "Story", "Tab" }`. `D.ProbeLateMethods` запишет методы класса, `D.NoteLateProbe` — `before` / `after` / `repaired` для `Text_Name`. Нет `before` и `after` значит, что `findLateLabel` не нашёл виджет.
2. `AbsruDiagnostics.lua`, обход панели: если у текста с латиницей или CJK есть точный ключ в шардах с переводом без CJK, а текст не изменён, записать `probes.walk_exact[]` (уникально по «путь|текст», до 100): `t`, `panel`, `path` (≤ 512), `text`, `walk` (0,5 / 2,0 с после `Open`), `seen`. `seen = true`, если этот путь хоть раз приходил в `translateTextWidget`: `Init.lua` в Diag-режиме вызывает `D.NoteSeenPath(path)`, множество до 8192 путей. В C7.log один раз: `[AbsruDiag] probe walkexact n=1`.
3. `CollectDiagLogs.ps1`: вывести `walk_exact` в `late.md → Пробы TASK-028` (колонки `seen`, `walk`, `panel`, `text`).
4. `docs/DIAGNOSTICS.md`: раздел «Проба TASK-028».
По результату следующий аналитический чат выбирает исправление. `seen = false` — расширить обход вложенных UserWidget или добавить late-хук с путём. `seen = true` — текст ставится позже, нужен late-хук класса или extended-задержки.

### R4. Пачка перевода (отдельный чат, `/translate-pack`)
Батч `batch_044_t028.json`:
- `StringDbGaps -EmitData batch_044_t028.json -Fields SkillDisc,RawText -Logs reference\logs\2026-10-03_1423\Saved\Mods\logs -Sid 20261003-131849`. Если `RawText` не выгрузится (модуль `LanguageData.StringDB_CN_Data`), добавить эти реплики в `-EmitList`.
- `-EmitList`: `秘偶名字`, `非凡方案一二三`, `玩家的队伍`, `分线选择`, `Reset All`, `Act` (для английских — `source_cn = ref_en = текст`).
- Канон: `秘偶` — марионетка (глоссарий TASK-024), `霸体` / `buffdisc(*id)` / `*d` / `*f` / `<HighLight>` / `<HyperLink …>` — без изменений, по `docs/GLOSSARY.md`. `Act` — подпись шкалы «действия» (метод действия, `扮演`) в продвижении последовательности: короткая, ≤ 6 символов.

### R5. Релиз
После R1–R3 и R4: `PackageRelease.ps1 -Publish` → v3.0.11-RU. В сборку войдут и TASK-027 R2 и пачка 1.

## Проверка
- Автоматическая: `BuildTools.ps1`, `ShardCompiler` (в выводе `enSkippedMarker ≥ 1`), `VerifyBatch` 0 ERR, `VerifyPatch`. Мок Lua 5.4 для R2: виджет `…WBP_KeyPrompt…text_key_lua` с текстом `I` → текст `I`, `SetFont` не вызывался; с текстом `空格` → перевод.
- Чек-лист для пользователя (после v3.0.11, с `absoluteru_dev.lua`):
  1. HUD, правый столбец иконок: подсказка клавиши — `I`, а не `#CanMoveЯ#`.
  2. Подсказка предмета из «Император возвращается», быстрая сборка («Полный набор») — по-русски (TASK-027).
  3. Описания навыков (окно навыков, подсказки) и пузыри реплик NPC в городе — по-русски.
  4. Открыть «Задания» (`TaskBoardPanel`), «Быструю сборку», «Усадьбу» → «Сообщения», пробыть 5 с. Затем в `C7.log` найти `[AbsruDiag] probe walkexact n=1` и `installed late-label class hook Task_Main_Panel: …` (список методов шире, чем `OnRefresh`).
  5. `C7.log`: нет `text fit fail … text=#CanMoveЯ#`.

## Промпты

### Чат исполнения
```
Чат исполнения (AGENTS.md §3). Выполни R1, R2, R3 из docs/tasks/TASK-028-untranslated-v3010-s2.md. Перевод (R4) не делать.
R1: batch_014.json id 067493 ref_en "I" → "#CanMoveI#"; ShardCompiler.cs:98-110 — не делать EN-ключ при #CanMove в cn без него в en и при en из одной латинской буквы (счётчик enSkippedMarker); такой же WARN в VerifyBatch.ps1; BuildTools.ps1, ShardCompiler, VerifyBatch.
R2: translateTextWidget (Init.lua:4723) — text_key_lua / WBP_KeyPrompt без CJK не переводить и не стилизовать.
R3: probe "taskstory" у LateLabelClasses.Task_Main_Panel (Init.lua:11867) с расширенными methods; probes.walk_exact + D.NoteSeenPath в AbsruDiagnostics.lua (только Diag); раздел в CollectDiagLogs → late.md и в docs/DIAGNOSTICS.md.
Мок Lua 5.4 для R2, VerifyPatch. Код читать точечно по ссылкам файл:строка. Коммит и push; релиз не собирать до пачки перевода R4.
```

### Чат перевода
```
/translate-pack
Пачка: TASK-028 (docs/tasks/TASK-028-untranslated-v3010-s2.md, раздел R4).
Батч: source/translation_batches/batch_044_t028.json — StringDbGaps -EmitData -Fields SkillDisc,RawText -Logs reference\logs\2026-10-03_1423\Saved\Mods\logs -Sid 20261003-131849; плюс -EmitList: 秘偶名字, 非凡方案一二三, 玩家的队伍, 分线选择, Reset All, Act (английские: source_cn = ref_en). Если RawText не выгрузился через -EmitData — реплики NPC из раздела R4/п.3 добавить в -EmitList.
Канон: 秘偶 — марионетка (TASK-024); теги <HighLight>/<HyperLink>, buffdisc(*id), *d, *f, %s сохранять; Act — короткая подпись шкалы метода действия (≤ 6 символов).
Код не трогать, файлы не читать — только команды скилла. В конце — коммит и push, короткий итог.
```
