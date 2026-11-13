# TASK-048: Автошахматы — подсказка резонанса: описание занимает всё окно, уровни не прокрутить

Дорожная карта: [ROADMAP.md](ROADMAP.md). Предыдущие: [TASK-016](TASK-016-autochess-tips-fit.md) (подгонка подсказок Автошахмат), [TASK-047](TASK-047-update-2307645-new-strings.md) (перевод абзаца «特选»). Данные: сессия диагностики `20261113-192230` (v3.1.6 локальная сборка, `Saved/Mods/logs/absru-s4-*`), скриншот пользователя 2026-11-13.

Статус: **этап B1 исполнен (v3.1.8-RU), ждёт проверки в игре.**

### Этап B1 — выполнено
- `TF.MoveFetterDetail` + начало `runtimeFixes.fitAutoChessFetterTip` (`Init.lua`): работает **всегда** (не только в DiagnosticsMode). Ищет у родителя `RichText_Detailed` первый `*ScrollBox*` после него, проверяет API (`AddChild`, `GetChildAt`, `RemoveFromParent`), снимает описание и детей ScrollBox, добавляет описание первым, затем прежних детей. Слоты: `HorizontalAlignment`/`VerticalAlignment` и `Padding` (числами — старый слот уничтожается) переносятся; описание получает отступы своего прежнего `VerticalBoxSlot`.
- Отступление от плана: `InsertChildAt` не используется — у `UScrollBox` `OnSlotAdded` добавляет Slate-слот в конец, порядок не совпал бы. Всегда пересборка.
- Повтор: слабая таблица `TF.FetterMoved` + проверка «родитель уже ScrollBox» (на случай нового Lua-прокси). Неудача фиксируется на экземпляр, повторно не пробуется; при сбое `AddChild` описание возвращается в конец старого столбца.
- Логи только в DiagnosticsMode: `autochess fetter reparent ok` / `autochess fetter reparent skip reason=no-detail|no-parent|no-scrollbox|detail-not-in-parent|api-missing|remove-failed|add-failed`. Снимок дерева (этап A) остаётся и снимается после переноса.
- Проверки: VerifyPatch OK (182 локальных), LuaJIT компилирует; заглушка `temp/task048/stub_b1.lua` — перенос и порядок, отступы/выравнивание, повторный Refresh, новый прокси, нет ScrollBox, нет описания, уничтоженный компонент, снимок в DiagnosticsMode — PASS.

### Этап A — выполнено
- `runtimeFixes.fitAutoChessFetterTip` (после `fitAutoChessPieceSkill`, `Init.lua`) + `TF.FetterTreeLine` / `TF.DumpFetterTree`; подключена в `hookAutoChessClassTable` для `AutoChess_Tips_FetterTips.Refresh/OnRefresh`.
- Только при `DiagnosticsMode`, через тик (`DEFER_SECONDS`). Отступление от плана: до **3 снимков** за сессию, каждый для своего текста описания (чтобы сравнить длинный и короткий бонус). Лимит 200 строк на снимок, глубина ≤ 14, вложенные `WidgetTree` (элементы уровней) обходятся.
- Формат: `autochess fetter tree begin snapshot=<n> textLen=<…>`, далее `autochess fetter tree depth=… name=… class=… slot=… desired=… local=… extra=vis=…,[MaxDesiredHeight…|children=…|sizeRule=…,sizeValue=…|autoSize=…,slotSize=…]`, в конце `autochess fetter tree end lines=<n>`.
- Проверки: VerifyPatch OK (182 локальных), Init.lua компилируется LuaJIT (`temp/task016/LuaHost.exe -c`), заглушка `temp/task048/stub_test.lua` (дерево с SizeBox/VerticalBox/ScrollBox/вложенным UserWidget, дубль ребёнка, лимит строк) — PASS.

## Симптом
Подсказка резонанса в Автошахматах (наведение на бонус слева, например «Тактика»): верхний блок описания занимает почти всё окно. Прокручивается только узкая полоса внизу (уровни резонанса `· +20 начальной маны…`), видна одна строка с затуханием. Высота окна ограничена.

## Что подтверждено
- Окно: `WBP_AutoChess_Tips_FetterTips`, заполняется в `AutoChess_Tips_FetterTips.Refresh` (`hooks.json`: `ac-class:AutoChess_Tips_FetterTips.Refresh` ACTIVE, 8 вызовов, 8 text_changes).
- Корневой столбец окна ограничен по высоте: `overflow-001.jsonl`, `Text_Mark` («Дважды щёлкните…»), родитель `KGVerticalBox` **528×900**. Окно уже упёрлось в 900 px.
- Уровни резонанса — отдельные элементы `WBP_AutoChess_Tips_FetterTips_Item` / `WBP_AutoChess_Tips_BondTips_Item_*` → `RichText_Bond` в `KGCanvasPanel` фиксированной высоты 200 / 280 / 320 (`overflow-001.jsonl`, 19:25:30–19:26:09). Они внутри прокрутки: у них по ширине запас 7 px, по высоте переполнения нет, а overflow-проверка пропускает родителей `ScrollBox` (`AbsruDiagnostics.lua:1609`).
- Описание бонуса — `RichText_Detailed` того же окна (`TASK-047`, раздел «Анализ», `untranslated.csv`). Оно **над** прокруткой: на скриншоте не двигается при прокрутке.
- С обновлением 2307645 в описание добавлен второй абзац «特选» (`【X】(4)：商会中【X】棋子概率变为【特选·X】…`, 36 строк в `batch_051_update_2307645.json`). По-русски описание вместе с этим абзацем — ~13 строк при ширине ~488 px, по-китайски — ~4–5. Поэтому в китайском клиенте прокрутке остаётся место, а в русском нет.

## Первопричина (гипотеза, проверить этапом A)
Раскладка Blueprint: `[заголовок] / RichText_Detailed (авторазмер) / ScrollBox с уровнями (Fill) / Text_Mark` в столбце с потолком ~900 px. Русское описание вдвое-втрое выше китайского и забирает высоту у `ScrollBox`. Само описание не прокручивается.

`SetRenderScale` (приём TASK-016) здесь **не поможет**: масштаб рендера не меняет размер в раскладке, место под `ScrollBox` не освободится. `SetFont` на RichTextBlock запрещён (`Init.lua:4378-4381`).

## План

Новых локальных верхнего уровня в `Init.lua` не добавлять (VerifyPatch). Lua — UTF-8 без BOM, LF. Всё новое — полями `runtimeFixes` / `TF`.

### Этап A. Снимок раскладки окна (только `DiagnosticsMode`)
1. В `hookAutoChessClassTable` (`Init.lua:12049-12053`) для `AutoChess_Tips_FetterTips` и `Refresh` / `OnRefresh` передать `afterTranslate` = `runtimeFixes.fitAutoChessFetterTip` (новая, рядом с `fitAutoChessPieceSkill`, `Init.lua:4896`).
2. В `fitAutoChessFetterTip` при `DiagnosticsMode` (через тик, как в `fitAutoChessPieceSkill`, `Init.lua:4945`) — один раз за сессию снять дерево от `userWidget.WidgetTree.RootWidget`: для каждого виджета имя, класс, класс слота, `GetDesiredSize`, `GetLocalSize(GetCachedGeometry())`, для `SizeBox` — `MaxDesiredHeight` / `HeightOverride` / флаги `bOverride_*`, для слота `VerticalBoxSlot` — `Size.SizeRule`, для `ScrollBox` — число детей. Вывод одной строкой на виджет в `C7.log`: `autochess fetter tree depth=<n> name=<…> class=<…> slot=<…> desired=<X>x<Y> local=<X>x<Y> extra=<…>`.
3. Пользователь (с `absoluteru_dev.lua`) открывает подсказку 2–3 бонусов и приносит `C7.log` в чат анализа. Из снимка определить: родитель `RichText_Detailed`, имя `ScrollBox`, где стоит потолок 900 (SizeBox, слот канваса или размер экрана).

### Результат этапа A (C7.log 2026-11-13 19:42:16, snapshot=1, textLen=626)
```
Canvas_Content KGCanvasPanel 532x900
 HB_Tips KGHorizontalBox → Canvas_Bond KGCanvasPanel 532x900
  KGSizeBox_0 KGSizeBox MaxDesiredHeight=900 (bOverride=true), slot autoSize
   VB_Content KGVerticalBox desired 528x1641.7, local 528x900
    HB_Title        Auto  92
    RichText_Detailed Auto  local 488x600   ← забирает 600 из 900
    KGScrollBox_1   Fill  local 488x133.3, desired 875, 1 ребёнок KGVerticalBox_0 (уровни)
    Text_Mark       Auto  18.7
```
Гипотеза подтверждена: потолок 900 задаёт `KGSizeBox_0.MaxDesiredHeight`; описание (600 px) остаётся над `KGScrollBox_1`, которому достаётся 133 px из 875 нужных. Для B1: перенести `RichText_Detailed` в `KGScrollBox_1` (точнее, первым ребёнком `KGVerticalBox_0` внутри него или самого ScrollBox). B2 (поднять 900) даст лишь +~100–150 px при экране 1080 — только как дополнение.

### Этап B. Правка (выбрать по снимку, отдельным коммитом после этапа A)
- **B1 (основной).** Перенести `RichText_Detailed` внутрь `ScrollBox` первым ребёнком: описание прокручивается вместе с уровнями. Один раз на экземпляр окна: `RemoveFromParent` → в `ScrollBox` пересобрать детей (снять, `AddChild(описание)`, вернуть остальных в прежнем порядке; `InsertChildAt` пробовать первым через `pcall`). Ссылки игры на виджет (`view.RichText_Detailed`) остаются действительными — тот же объект. Флаг «перенесено» хранить в слабой таблице по виджету. Отступы слота — как у первого элемента уровней. Если `ScrollBox` или нужные методы не найдены — ничего не делать и написать `autochess fetter reparent skip reason=…` (только в `DiagnosticsMode`).
- **B2 (если снимок покажет SizeBox с `MaxDesiredHeight` меньше доступной высоты экрана).** Поднять потолок до высоты вьюпорта минус отступ. Применять только вместе с B1 или если B1 невозможен.
- **C (текст, отдельный чат перевода, по желанию).** Сократить русский абзац «特选» в 36 строках `batch_051` (например, «【X】(4): в торговой палате вместо 【X】 появляются 【Избранный·X】: +1 уровень резонанса 【X】, одновременно не больше 2 фигур 【Избранный】.»). Это уменьшит высоту, но не решит проблему без B1.

### Версия и документы
После этапа B — версия v3.1.8-RU во всех местах (`AppInfo.cs`, `AssemblyInfo.cs`, `PackageRelease.ps1`, `Init.lua` `VERSION`). `LESSONS.md`: «`SetRenderScale` не освобождает место в раскладке; если авторазмерный текст вытесняет `ScrollBox`, текст переносить в прокрутку». ROADMAP — строка TASK-048. Релиз — только по решению пользователя.

## Проверка
**Автоматическая:** `VerifyPatch.ps1` OK, Init.lua компилируется LuaJIT. Логику пересборки детей `ScrollBox` прогнать на заглушке в `temp/` (таблицы-виджеты с `RemoveFromParent` / `AddChild` / `ClearChildren`): порядок детей, повторный `Refresh` не переносит второй раз.

**Чек-лист для пользователя (этап A):**
1. С `absoluteru_dev.lua` открыть Автошахматы, навести на 2–3 бонуса («Тактика», «Мэй Мэнор», «Церковь Богини Вечной Ночи»).
2. В `C7.log` строки `autochess fetter tree …` (один снимок за сессию). Принести лог в чат анализа.

**Чек-лист для пользователя (этап B):**
1. Наведение на «Тактика»: описание и уровни прокручиваются вместе колёсиком, до последнего уровня можно докрутить.
2. Короткие бонусы (без длинного описания) выглядят как раньше, без пустых мест.
3. Повторное наведение на тот же и другой бонус — без дублей описания и прыжков.
4. В `C7.log` нет `autochess fetter reparent skip`.

## Промпт для чата исполнения (этап A)
> Ты — чат исполнения проекта AbsoluteRU (AGENTS.md §3, чат 2). Прочитай AGENTS.md, docs/LESSONS.md, docs/DIAGNOSTICS.md и выполни docs/tasks/TASK-048-autochess-fetter-tip-scroll.md, **только этап A**: в `hookAutoChessClassTable` (`Init.lua:12049-12053`) для `AutoChess_Tips_FetterTips.Refresh/OnRefresh` передать `afterTranslate = runtimeFixes.fitAutoChessFetterTip`; новая функция рядом с `fitAutoChessPieceSkill` (`Init.lua:4896`) только при `DiagnosticsMode`, через тик, один раз за сессию пишет в `C7.log` дерево окна от `userWidget.WidgetTree.RootWidget` (имя, класс, класс слота, desired/local размер, у SizeBox — MaxDesiredHeight/HeightOverride, у VerticalBoxSlot — SizeRule, у ScrollBox — число детей) строками `autochess fetter tree …`. В обычном режиме — ничего. Новых локальных верхнего уровня не добавлять, Lua UTF-8 без BOM, LF. VerifyPatch, компиляция LuaJIT. Закоммить (вместе с TASK-048) и запушь; собери локальную сборку `tools/PackageRelease.ps1` без `-Publish`, версию не поднимай. Не пиши «исправлено», дай чек-лист этапа A. Папку игры не трогать, игру и установщик не запускать.
