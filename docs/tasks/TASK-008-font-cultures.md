# TASK-008: шрифт — кириллица Title через приоритет существующего SubTypeface (этап 4a, без записи диапазонов)

Статус: **шаги 1–5 исполнены** 2026-09-25 (v2.9.4-RU, режим по умолчанию `"typeface"`), **ждут проверки в игре** по разделу «Проверка». Релиз не опубликован.
- Шаг 1: проба `range_probe` дополнена полями `get_keys`, `set_keys`, `get_LowerBound…`/`get_UpperBound…` (вызов геттера и поля `Type`/`Value` результата), `get_LowerBound_keys`, `clone`, `clone_method`; сеттеры не вызываются. Вывод в `fonts.md → Проба FInt32Range`.
- Шаг 2: `Init.lua` — `applyCultures`, `runtimeFixes.CyrillicCultureSubs`, флаг `CyrillicCultureSub`. Если у `TArray` нет `Set`, элемент заменяется через `Remove` + `Insert(index, value)`, а при ошибке — `Insert(value, index)`; после записи сверяются `Cultures` и число SubTypeface. Логика прогнана на заглушках (fengari): `Set` и `Insert`, `en-US` → `en-US;en`, откат при `flush=missing` и при ошибке записи, выбор `NotoSans_Regular` по флагу, Title не меняется в `cultures` и меняется в `typeface`.
- Шаг 3: сделан заранее, только чтение. Если в игре сработают геттеры `.get`, диагностика заполнит `covers_0410`/`covers_0041` (`read = get`), а строка режима — `cyr=`/`latin=`. Пока они не читаются, там `unknown`. `subfont` не менялся.
- Шаг 4: причина найдена. `afterMain` диагностики вызывался, но его хук стоял на приоритете 2100000, то есть после `cpdd.runtime-fix.performance-mode` (2000000). Тот понижает `LuaLog` до Warning, и поэтому в сессии 1046 после 10:38:19 нет даже `[LOMPerf] phase=after_main`, а строки `Lua:` возвращаются только в 10:38:54 после `CheckLogLvAndSGameDebugger`. Маркер теперь выводит отдельный хук с приоритетом 1501.

Дорожная карта: [ROADMAP.md](ROADMAP.md), этап 4a. Предыдущие: [TASK-006](TASK-006-font.md), [TASK-007](TASK-007-font-coverage.md). Данные: `reference/logs/2026-09-25_1046/` (v2.9.3-RU, сессия A, режим `typeface`, сессия 20260925-103753).

## Симптом
Сессия A прошла, но шаг 4 TASK-007 (правка `subfont`) сделать нельзя: проба не нашла ни одного способа прочитать или записать `FInt32Range`. Сессия B (`CyrillicFont = "subfont"`) заведомо откатится в `typeface`, проходить её не нужно.

## Первопричина

### 1. `FInt32Range` в slua непрозрачен
`report/fonts.md → Проба FInt32Range`, все 17 SubTypeface `Font_Aleo` одинаково:
- метатаблица `name=FInt32Range`, ключи `.get, .set, __gc, __index, __is_slua_userdata, __name, __newindex, __next, __pairs, clone`; `index_keys=[]`;
- `GetLowerBoundValue`, `GetUpperBoundValue`, `IsEmpty`, `Contains` → `attempt to call method`; `range.LowerBound` → `nil`; `LowerBound.Value` / `.Type` → `attempt to index field`;
- `REPORT.md → API`: `import(Int32Range)=import=ok ctor=userdata LowerBound.Value=nil GetLowerBoundValue=error`.

Итог: `cyrillicSubIndex` (`Init.lua:1577-1593`) никогда ничего не находит, а `newRange` (`Init.lua:1623-1634`) пишет в `nil` → `writeCyrillicSub` падает → откат. Не проверено только одно: что лежит в таблицах `.get` / `.set` метатаблицы. У slua-структур это таблицы геттеров и сеттеров свойств, и проба их ключи не выводила. Если там есть `LowerBound`, свойства доступны другим синтаксисом (шаг 1).

### 2. Можно обойтись без диапазонов: сделать приоритетным SubTypeface, который уже есть в игре
- В `Font_Aleo` уже есть `sub#1 → Fallback/NotoSerif_Regular` (6 диапазонов) и `sub#2 → Fallback/NotoSans_Regular` (3 диапазона); `Cultures` у всех пустые, и **строковое поле `Cultures` читается** (в `composite` оно есть).
- Текущая культура игры: `en` (`culture.GetCurrentCulture=en`, `GetCurrentLanguage=en`).
- Как Slate выбирает шрифт (`FCachedCompositeFontData`, UE5): SubTypeface, у которых `Cultures` совпадает с текущей культурой, попадают в **приоритетные** диапазоны и проверяются раньше default-typeface. Остальные SubTypeface работают как запасные.
- Сходится с наблюдениями: Title рисует кириллицу глифами FZ Mincho из самого `Aleo_Title` (1,0 em). Значит, запасные диапазоны default-face не перебивают, даже если NotoSerif кириллицу покрывает. У Regular (`Aleo_Regular`) своей кириллицы, по-видимому, нет, и она приходит из запасного sub: 0,62–0,66 em.
- **Гипотеза для проверки в игре:** если записать `Cultures = "en"` в существующий `sub#1` (NotoSerif), его диапазоны станут приоритетными. Если среди них есть кириллица, Title и Regular, включая RichText и текст из данных, получат пропорциональную кириллицу с засечками. Наш SubTypeface и `FInt32Range` для этого не нужны.
- **Риск:** если в диапазоны NotoSerif входит Basic Latin (U+0020–007F), латиница тоже уйдёт с Aleo на Noto Serif. Это видно глазами («Plot Overview», цифры). На этот случай есть вариант `sub#2` (NotoSans) и откат.

### 3. Мелочи сессии A
- Маркер `[AbsruDiag] session=…` в C7.log так и не появился (`AbsruDiagnostics.lua:2474` формирует `S.sessionLine`, но строки в логе нет). Первые сбросы `flush #1–4` тоже потеряны: логгер игры ещё не готов.
- `menu button without short label enum=false`: поле `ButtonEnum` у кнопок не читается (всегда `false`), подписи работают только по тексту.
- `title_cyrillic`: 52 виджета, из них 30 — RichText. Это подтверждает TASK-007: полное покрытие возможно только на уровне шрифта.

## План
Версия **v2.9.4-RU**. Режим по умолчанию остаётся `"typeface"`, новое — только по dev-флагу.

1. **Проба `.get`/`.set` (флаг `Fonts`, только чтение).** В пробе `FInt32Range` (`AbsruDiagnostics.lua`, рядом со строками 1946–1952) вывести ключи `getmetatable(range)[".get"]` и `[".set"]`; для ключей `LowerBound` / `UpperBound`, если они есть, — результат `pcall(getter, range)` и поля `Type` / `Value` полученного значения. Проверить `range:clone()`. Вывести в `fonts.md`. Выполнять вместе с шагом 2; шаг 2 от результата не зависит.
2. **Новый режим `CyrillicFont = "cultures"`** (`Init.lua`, блок шрифта кириллицы, рядом с `applySubfont`):
   - Найти в `Font_Aleo.CompositeFont.SubTypefaces` запись, у которой `Typeface.Fonts[0].Font.FontFaceAsset` имеет путь `…/Fallback/NotoSerif_Regular…`. Путь face берётся из списка `runtimeFixes.CyrillicCultureSubs = { "NotoSerif_Regular", "NotoSans_Regular" }`; значение в dev-флаге `CyrillicCultureSub = "NotoSans_Regular"` меняет первый элемент.
   - Прочитать текущую культуру (`import("KismetInternationalizationLibrary").GetCurrentCulture()`, запасное значение `"en"`). Записать в найденную запись `Cultures = <культура>`, для `en-US` — `"en-US;en"`. Запись делать через копию: `cf = font.CompositeFont; subs = cf.SubTypefaces; sub = item(subs, i); sub.Cultures = …; subs:Set(i, sub)` (или способ, которым в slua заменяется элемент TArray; если `Set` нет — `Remove(i)` + `Insert(sub, i)`); затем `cf.SubTypefaces = subs; font.CompositeFont = cf`.
   - Проверка: прочитать `Cultures` обратно; затем `C7FunctionLibrary.FlushFontCache()` (как `flushFontCache`, `Init.lua:1687`).
   - Одна строка после инициализации логгера (как у `typeface`, в `after_main`): `cyrillic font mode=cultures sub=<face> cultures=<…> write=<ok|err> verify=<ok|fail> flush=<ok|missing|err>`. Любая ошибка → откат (вернуть прежний `Cultures`) и режим `typeface` с `reason=…`.
   - В режиме `cultures` ветку `typeface` (Title → Regular) не выполнять: Title остаётся Title, кириллица должна прийти из NotoSerif.
   - Ассеты игры не заменяются, диапазоны не создаются, новых хуков нет.
3. **Если шаг 1 покажет рабочий доступ к границам**, в `fonts.json → composite.subs[]` заполнить `covers_0410` / `covers_0041` и в строке лога режима `cultures` указать, покрывает ли выбранный sub кириллицу и латиницу. Режим `subfont` не чинить, пока пользователь не решит, нужен ли он (при удаче `cultures` он лишний).
4. **Маркер сессии.** `[AbsruDiag] session=…` выводить в `afterMain` (то, что сделано в TASK-007, в логе не видно; проверить, вызывается ли `afterMain` у модуля диагностики).
5. **Проверки и документы.** `tools/VerifyPatch.ps1`; Lua без BOM, LF; `.ps1` с BOM. `DIAGNOSTICS.md`: флаги `CyrillicFont = "cultures"`, `CyrillicCultureSub`, проба `.get`. `LESSONS.md`: «`FInt32Range` через slua не читается методами и полями; приоритет подшрифта задаётся строкой `Cultures`». `ROADMAP.md`, TASK-007 (шаг 4 — заменён TASK-008). Закоммитить, запушить; релиз не публиковать.

## Проверка
**Автоматическая:** `VerifyPatch.ps1` OK; `git diff --stat` — `Init.lua`, `AbsruDiagnostics.lua`, `CollectDiagLogs.ps1` (если менялся), версии, документы.

**Чек-лист для пользователя** (сборка v2.9.4-RU; в `absoluteru_dev.lua` добавить `CyrillicFont = "cultures",`):
1. В C7.log найти `cyrillic font mode=cultures sub=… cultures=… write=… verify=… flush=…` и прислать строку. Сразу после `v2.9.4-RU active hooks_installed=` должна идти строка `[AbsruDiag] session=…`.
2. Если `mode=cultures`, проверить экраны: задания (описание справа, `TaskBoardPanel`), диалог с NPC (все варианты ответа), Исследование (заголовки карточек), магазин VIP (`Shops_Panel`, RichText), подсказка загрузки. Кириллица должна быть пропорциональной и с засечками, без разрядки.
3. **Латиница и цифры:** «Plot Overview», числа в HUD, английские названия. Сравнить со скриншотом до изменения: остались ли они шрифтом Aleo. Если латиница поменялась, повторить с `CyrillicCultureSub = "NotoSans_Regular"` и сравнить.
4. Китайских иероглифов и квадратов нигде не появилось.
5. `tools\CollectDiagLogs.ps1` → прислать папку. В `fonts.md` раздел «Title с кириллицей» и проба `.get`.

## Промпт для чата исполнения
> Ты — чат исполнения проекта AbsoluteRU (AGENTS.md §3, чат 2). Прочитай AGENTS.md, docs/LESSONS.md, docs/DIAGNOSTICS.md, docs/tasks/ROADMAP.md, docs/tasks/TASK-007-font-coverage.md и выполни docs/tasks/TASK-008-font-cultures.md, раздел «План», шаги 1–5. Главное: сессия A (reference/logs/2026-09-25_1046) показала, что `FInt32Range` в slua непрозрачен (нет полей и методов), поэтому `subfont` не может ни найти, ни создать диапазон. Обходной путь — новый режим `CyrillicFont = "cultures"`: в существующем SubTypeface `Font_Aleo` с face `Fallback/NotoSerif_Regular` (запасной — `NotoSans_Regular`) записать `Cultures` = текущая культура (`en`), чтобы его диапазоны стали приоритетнее default-typeface; проверить запись чтением, вызвать `C7FunctionLibrary.FlushFontCache()`, при ошибке вернуть прежнее значение и откатиться в `typeface`; в режиме `cultures` не выполнять подмену Title → Regular. Добавь пробу ключей `.get`/`.set` метатаблицы `FInt32Range` (только чтение) и вывод маркера `[AbsruDiag] session=` в `afterMain`. Ассеты игры не заменять, диапазоны не создавать, новые хуки не добавлять. Режим по умолчанию остаётся `"typeface"`. Версия v2.9.4-RU. Lua — UTF-8 без BOM, LF; `.ps1` с кириллицей — с BOM. Не пиши «исправлено»: дай мне чек-лист из раздела «Проверка». Закоммить и запушь в main; релиз не публикуй. В папку игры ничего не пиши и игру не запускай.
