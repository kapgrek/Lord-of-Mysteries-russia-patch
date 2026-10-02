# TASK-027: Разрыв «Н   овое событие» (заголовок с буквицей) и новый китайский после 1.10

## Симптом
v3.0.10-RU, сессия 2026-10-02 (`reference/logs/2026-10-02_1410`, sid `20261002-132631`, dev-диагностика включена).
1. Всплывающее окно активности при входе (`LoginActivityPopUp_Panel`): заголовок «Н» и «овое событие» разнесены на ~100 px.
2. «В начале игры немного нового китайского»; в Автошахматах ничего нового.

## Первопричина

### 1. Заголовок с буквицей — два виджета, наш стиль ломает оба
Заголовок `WBP_ComFirstBigText` (и `WBP_ComDIYText`, `KText_TitleDrug`) — это два `KGTextBlock`: `Text_First` (первая буква, крупная) и `Text_Affix` (остаток). Игра сама режет переведённую строку «Новое событие» на «Н» + «овое событие», поэтому перевод работает. Ломает раскладку наша стилизация:
- `fit-001.jsonl`, 13:28:53: `LoginActivityPopUp_Panel…WBP_ComFirstBigText…Text_First` `"Н"` `size_pre 30 → size 20`; `Text_Affix` `"овое событие"` `30 → 20`.
- Там же: `DungeonSelect…KText_TitleDrug…Text_First` «И» `57 → 20`, `DungeonHandbook…WBP_ComTitle…Text_First` «И» `42 → 20`, `SecretPartner_GachaWish…Text_First` «М» `42 → 20`, `DungeonTabItem…WBP_ComDIYText…Text_First` «Н» `32.25 → 20`, `AutoChess_Shop_Panel…Text_First` «т» `34.5 → 20`. Буквица везде становится размером с остаток (20), дизайн «крупная первая буква» пропадает.
- Причина 20: `TF.Legacy` (`Init.lua:4413`): `orig > 36 → 18` (`:4428`), затем `baseSize > 22 → font.Size = 20` (`:4454-4455`). Исключений для `Text_First`/`Text_Affix` нет: `grep Text_First|Text_Affix|FirstBigText|ComDIYText` по `cpdd_runtime_fixes/*.lua` находит только `WidgetNameIndex.lua`.
- Сам **разрыв** логи не объясняют: в `overflow-*.jsonl` записей по этим виджетам нет, в `fit` нет геометрии. Это раскладка Blueprint (фиксированный слот `Text_First`, выравнивание `Text_Affix` в fill-слоте или позиция, посчитанная игрой по CJK-ширине). Править «на удачу» нельзя (AGENTS §4), поэтому R1 — снять раскладку.
- Попутно: `batch_018.json:27480` `商会` → «торговая палата» со строчной буквы, отсюда буквица «т» в магазине Автошахмат.

### 2. Новый китайский (сверка `untranslated.md`, `vis=true`, кроме ников, названий команд, комментариев к наборам, `猫咪之家` — это контент игроков)
Ключей в батчах нет, это новое с 1.10 (подземелье «Возвращение Императора» `大帝重临`, быстрая сборка):
- `GetItemNewDataRow/funcRep` — 21 строка: `参与副本<Highlight>大帝重临（普通）</>，有概率获得…`, `组队模式参加副本<Highlight>大帝重临（普通）</>…`, `…完成阶段<Highlight>污染意志</>/<Highlight>残留意志</>后…`, `使用后获得<Highlight>大帝的辉光披风</>…/白枫往事发型/知识的掠影顶饰/大地之吻披风`, `参与副本<Highlight>安提哥努斯笔记（普通）</>…55~60装等…`, `集齐15个可以获得秘偶疗愈骑士…`, `…秘偶小星虫…`, `使用后，有<Highlight>极小概率获得零元购凭证</>…`; `itemDes` — `<Highlight>工艺：</>湖光细纱・丰饶祝福…`. Видны в подсказке предмета и справочнике подземелий (`BagItemTips_Panel`, `WBP_Lib_MainText`).
- `ComMessageBoxSimple_Panel`: кнопка `前往检查` (`UIComButton.SetName`) и текст `您当前的形态<HighLight>…</>与天赋<HighLight>…</>不匹配，是否前往检查?` — имена внутри уже русские, значит шаблон форматирует игра, а ключа шаблона нет. Источник шаблона в логах не виден (нет промаха StringDB/StringConst).
- `QuickAssembly_PC_Main_Panel`: `全套方案` (`Text_Icon`, точного ключа нет: есть только `全套方案%s`, `全套方案切换`); `大神推荐` — ключ есть (`batch_007`), но не применился (видит только обход диагностики, `panel:…:walk`).
- `WBP_GameplayIntegration_DungeonEntrance_Item/Text_Lable`: `共次数奖励：0/5` — ключа нет.
- `HomePage_Panel`: `Home Coin`, `Aesthetic` — перевод есть (`batch_034`), не применился.
- StringDB (715 промахов): видимых новых нет, всё служебное/тестовое (`测试`, `占位`, `【PVP测试】`…). Исключения, которые могут попасть в чат/напоминания: `1315019397473792` `与誓约对象<Chat_Highlight>%s</>共同参与玩法，誓约值增加<Chat_Highlight>%s</>点`, `1315019396787456` `已成功购买<Reminder_Orange>%d</>个%s，总共花费<Reminder_Orange>%d</>战略金镑`, `457398716231680/…936` `神眷牌` → `红与黑` / `全境雍容`.

## План

### R1. Снять раскладку заголовка (делает пользователь, код не нужен)
В `…\C7\Saved\Mods\lua\absoluteru_dev.lua` добавить в таблицу:
```lua
AssetExport = { Panels = { "LoginActivityPopUp_Panel", "DungeonSelect_Panel" }, Calib = false, MaxFiles = 1 },
```
Открыть окно активности при входе и окно подземелий (по 5–10 с), выйти, затем `powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1`. В `layout_NNN.json` смотреть узлы `WBP_ComFirstBigText` / `KText_TitleDrug` / `Text_First` / `Text_Affix`: `slot` (`size_rule`, `padding`, `halign`, `position`/`size`/`autosize` у Canvas), `geom` (`px`, `px_end`, `local_size`), `text.justification`, размер шрифта. После снимка убрать строку `AssetExport`.
По снимку выбрать R2 (аналитический чат дописывает в этот TASK):
- `Text_First` в фиксированном слоте (SizeBox/Canvas под ширину иероглифа) → выравнивание `Text_First` вправо или уменьшение слота;
- `Text_Affix` в fill-слоте с центровкой → выравнивание `Text_Affix` влево;
- иначе — запасной вариант: вся строка в `Text_Affix`, `Text_First` пустой.

### R2. Стиль буквицы (`Init.lua`, можно сразу)
В `translateTextWidget` / `TF.Legacy` (`Init.lua:4413`) для `Text_First` и `Text_Affix`, у которых путь содержит `ComFirstBigText`, `ComDIYText` или `KText_TitleDrug`, не менять размер (оставить авторский / выставленный игрой, без `+2`, `orig > 36 → 18`, `> 22 → 20`); `LetterSpacing = 0` для кириллицы оставить. Пропорция «крупная буква + остаток» сохранится; у `Text_Affix` длинный русский остаток может не влезть — проверить `overflow` в следующей сессии.

### R3. Пачка перевода (чат перевода, `/translate-pack`)
- Батч `batch_043_t027.json`: `StringDbGaps -EmitData` по логам `reference/logs/2026-10-02_1410`, sid `20261002-132631`, поля `funcRep,itemDes` модуля `GetItemNewDataRow` (≈22 строки, `大帝重临`, наряды, `秘偶`).
- `-EmitList` (там же): `前往检查`, `全套方案`, `共次数奖励：`… — для `共次数奖励：0/5` сначала найти шаблон (`-EmitData`/KSBC по `共次数奖励`); если шаблона нет — пропустить. Для `您当前的形态…不匹配` — так же искать шаблон с `%s`; точная строка не подойдёт (имена меняются).
- 3 строки StringDB (`誓约值`, `战略金镑`, `神眷牌` ×2) — `-Emit` по id или `-EmitList`.
- Канон: `大帝重临` — «Император возвращается», как в заголовке подземелья (`batch_014.json:14956`); в батчах встречается и «Возвращение Императора» (`Text_FashionTitle` окна активности) — для названия в `<Highlight>` брать «Император возвращается»; `污染意志`, `残留意志`, `秘偶` — по глоссарию TASK-024; `苏勒` — как в `batch_001.json:25492`.
- Заодно: `batch_018.json:27480` `商会` → «Торговая палата» (с заглавной).

### R4. «Перевод есть, не применился» (`大神推荐`, `Home Coin`, `Aesthetic`) — отдельной задачей, если повторится: текст ставится после проходов; нужен late-class хук `QuickAssembly_PC_Main_Panel` / `HomePage_Panel` (как TASK-025 R1). Сейчас не делать — по одному показу в сессии.

**Статус R2 (2026-10-02):** сделано. `TF.State` помечает `st.dropCap` по пути виджета (`TF.IsDropCap`: имя `Text_First`/`Text_Affix` + хост `ComFirstBigText`/`ComDIYText`/`KText_TitleDrug`); `TF.Legacy` оставляет размер игры, `TF.Cap` не запускает подгонку. Мок `temp/t027/dropcap_test.lua` (Legacy и Cap) — ALL OK, VerifyPatch — OK. В игре не проверено.

## Проверка
- Автоматическая: `VerifyPatch`; мок Lua 5.4 для R2: виджет `…WBP_ComFirstBigText…Text_First` с кириллицей и `size 42` → после `TF.Legacy` размер 42; обычный `Text_Title` 30 → 20, как раньше. `ShardCompiler` + `VerifyBatch` — 0 ERR.
- Чек-лист для пользователя:
  1. Окно «Новое событие» при входе: «Н» крупнее остатка и стоит вплотную к «овое событие» (после R2 — только размер; разрыв уходит после R2 по снимку R1).
  2. Подземелья («Возвращение Императора»): заголовок «И» + «мператор возвращается» — буквица крупная.
  3. Подсказка предмета из «Возвращения Императора» и справочник наград — по-русски.
  4. `C7.log`: `[AbsruExport] snapshot index=…` (во время R1).

## Промпты

### Чат исполнения (R2 сразу; R2-раскладка — после снимка R1)
```
Чат исполнения (AGENTS.md §3). Выполни R2 из docs/tasks/TASK-027-firstbig-text-v3010.md: в TF.Legacy (Init.lua:4413) не менять размер у Text_First/Text_Affix внутри ComFirstBigText / ComDIYText / KText_TitleDrug (путь виджета), LetterSpacing 0 оставить. Перевод не делать.
Мок Lua 5.4 (2 случая из «Проверка»), VerifyPatch. Код читать точечно по ссылкам файл:строка. Коммит и push, релиз не собирать.
```

### Чат перевода
```
/translate-pack
Пачка: TASK-027 (docs/tasks/TASK-027-firstbig-text-v3010.md, раздел R3).
Батч: source/translation_batches/batch_043_t027.json — StringDbGaps -EmitData, модуль GetItemNewDataRow, поля funcRep,itemDes; логи reference/logs/2026-10-02_1410, sid 20261002-132631. Плюс -EmitList: 前往检查, 全套方案 и 3 строки StringDB из раздела R3 (誓约值, 战略金镑, 神眷牌 ×2).
Канон: 大帝重临 — «Император возвращается» (batch_014); 秘偶 — глоссарий TASK-024; 苏勒 — как batch_001. Теги <Highlight>, плейсхолдеры %s/%d сохранять.
Заодно batch_018 商会 → «Торговая палата» (с заглавной).
Код не трогать, файлы не читать — только команды скилла. В конце — коммит и push, короткий итог.
```
