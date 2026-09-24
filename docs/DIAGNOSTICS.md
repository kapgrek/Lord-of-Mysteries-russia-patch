# Диагностика для разработки (AbsruDiagnostics)

Одна сборка для всех. Без файла флагов разработчика патч работает как обычно: в `C7.log` одна строка при старте (`v2.9.1-RU active hooks_installed=N`), модуль диагностики не загружается, в горячих путях `Init.lua` добавлена одна проверка `runtimeFixes.Diag ~= nil`. С файлом флагов сборка собирает данные для следующих этапов:

- **этап 4** (шрифт через CompositeFont): какие FontObject/Typeface реально рисуют кириллицу;
- **этап 5** (подгонка текста по измерению, удаление мёртвых костылей): какие хуки, спеки и ветки ремонта ни разу не сработали или ни разу не изменили текст, где текст не помещается;
- **этап 8** (русификация картинок): какие текстуры показываются на каких экранах.

Диагностика **только наблюдает**: не вызывает `SetText`, `SetFont`, `ForceLayoutPrepass`, не меняет `LetterSpacing` и не трогает виджеты. План и обоснование: [tasks/TASK-005-diagnostics.md](tasks/TASK-005-diagnostics.md).

| Что | Где |
|---|---|
| Модуль | `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/AbsruDiagnostics.lua` (в пакете, но загружается только при файле флагов; в `manifest.lua` его нет) |
| Точки вызова | `Init.lua`: чтение флагов (строки 2–12), запуск модуля после `local runtimeFixes = {}` (~1409), `Attach` после `walkWidgetDescendants` (~2163), вставки `runtimeFixes.diagWrap(...)` / `runtimeFixes.Diag` из TASK-005 §4 |
| Файл флагов (в игре) | `…\C7\Saved\Mods\lua\absoluteru_dev.lua` — в пакете его нет, установщик его не создаёт и не удаляет |
| Данные (в игре) | `…\C7\Saved\Mods\logs\absru-s<слот>-*` (или `…\Saved\Mods\absru-s<слот>-*`, если папку `logs` создать не удалось; видно по `dir=` в маркере) |
| Сбор и отчёты | `tools/CollectDiagLogs.ps1` → `reference/logs/<yyyy-MM-dd_HHmm>/report/` |

## Включение

Создать `…\C7\Saved\Mods\lua\absoluteru_dev.lua`:

```lua
-- AbsoluteRU: диагностика для разработки. Удалите файл, чтобы выключить.
return {
    Enabled = true,          -- главный выключатель
    VerboseLog = true,       -- Loader.Features.DiagnosticsMode = true (reportVerbose в C7.log)
    Hooks = true,            -- счётчики хуков/спеков/веток -> hooks.json
    Untranslated = true,     -- CJK/английский в виджетах и промахи StringDB -> untranslated-*.jsonl
    Overflow = true,         -- переполнение текста -> overflow-*.jsonl
    Fonts = true,            -- сводка шрифтов -> fonts.json
    Images = true,           -- ресурсы кистей Image -> images-*.jsonl
    PanelWalk = true,        -- собственный обход панели после Open (нужен для Untranslated/Overflow/Images)
    FrameBudgetMs = 2.0,     -- не больше N мс работы диагностики за тик
    TickSeconds = 0.05,      -- период тика, пока очередь не пуста
    FlushSeconds = 30,       -- период сброса на диск
    PartKB = 512,            -- размер части JSONL
    SessionMB = 32,          -- потолок на сессию; дальше только счётчики "dropped"
    Slots = 5,               -- ротация сессий (s1..s5)
    PanelWalksPerUid = 3,    -- обходов одной панели за сессию
}
```

Выключение: удалить `absoluteru_dev.lua`. Папку `Saved\Mods\logs\` можно удалить вручную (Lua удалять файлы не умеет).

### Что делает `VerboseLog`
- `absoluteru_dev.lua` читается в самом начале `Init.lua` (через `Loader.LoadExternal`) и включает `Loader.Features.DiagnosticsMode` **только для Init.lua**: `reportVerbose` начинает писать подробные строки (установка хуков, медленные ремонты, метрики).
- `report()` и маркеры модуля пишут через `Log.Info`: в C7.log это строки `LuaLog: ReleaseLog: …`, и `PerformanceMode` их не отсекает. Вывод `LuaCLogger.Warning` в C7.log **не попадает** (первая сессия 2026-09-25: 0 строк, в том числе `[CPDDPerformance] active` самого CPDD), поэтому его не использовать. **При включённых флагах в `C7.log` видны строки `[CPDDRuntimeFix]` от `reportVerbose`**, без флагов — только строка `active hooks_installed=` и ошибки.
- На `bootstrap.lua` файл флагов не влияет, и это ожидаемо: к загрузке `Init.lua` bootstrap уже прочитал `cpdd_user_settings.lua` / `cpdd_patcher_settings.lua` и принял свои решения (PerformanceMode, DPS-метр, чат). Единственное место bootstrap, которое смотрит `DiagnosticsMode` позже, — `PersonalLoad` для `mods.personal_cjk_logger.Init` (`bootstrap.lua:580-587`); он срабатывает, только если модуль перечислен в `cpdd_user_settings.lua`, а в пакете и у пользователя этого файла нет.
- Обратное тоже верно: `DiagnosticsMode = true` из `cpdd_user_settings.lua` включает только подробный лог, **модуль сбора он не включает**.

## Что собирается

| Флаг | Источник | Файл |
|---|---|---|
| `Hooks` | Каждая обёртка метода в `Init.lua` (`runtimeFixes.diagWrap(id, kind, fn, meta)`), объявленные спеки (`DeclareSpec`), проходы `panelTextRepair:Repair` и ветки внутри него, `Loader.Hooks`/`Loader.Applied` (AfterLoad) | `absru-s<n>-hooks.json` |
| `Untranslated` | `widget`: итоговый текст `translateTextWidget` и текст из обхода панели с CJK или латиницей без кириллицы; `data`: `runtimeMetrics.CaptureDataAssignment` (CJK или неизменённый английский); `stringdb`: `Loader.TranslateDatabaseString` вернул nil | `absru-s<n>-untranslated-NNN.jsonl` |
| `Overflow` | `GetDesiredSize` против `GetLocalSize(GetCachedGeometry())` и против геометрии родителя; только нарисованные (не 0×0) и видимые виджеты | `absru-s<n>-overflow-NNN.jsonl` |
| `Fonts` | Шрифт **до** нашей стилизации (первый снимок виджета в `translateTextWidget`) и **после**; в обходе панели — авторский шрифт виджетов, которые мы не трогали | `absru-s<n>-fonts.json` |
| `Images` | `Brush.ResourceObject` у виджетов с кистью в обходе панели | `absru-s<n>-images-NNN.jsonl` |
| `PanelWalk` | Обход дерева панели через 0,5 и 2,0 с после `UIComponent.Open`, не больше `PanelWalksPerUid` раз на uid | питает три строки выше |

**Корни обхода.** `WidgetTree.GetAllWidgets` в этой сборке недоступен (`GetAllWidgetsCalls = 0` за всю первую сессию), а у UserWidget нет `GetChildrenCount`, поэтому обход только от `component.userWidget` находил ~6 виджетов на панель. Обход стартует с тех же корней, что и `translateViewTextWidgets` в Init.lua: все значения `component.view` и `view._widgetCache` (рекурсивно по `_childComponents`), `userWidget.WidgetTree.RootWidget` (и у вложенных UserWidget при спуске), `runtimeFixes.VisibleWidgetNames` через `getNamedWidget`. Проба имён через `FindWidget` (`queueGeneratedWidgetProbe`) не повторяется: слишком дорого. Сколько корней дал каждый источник — `session.json → counters.roots_view / roots_cache / roots_tree / roots_named`; доступность — `api["WidgetTree.RootWidget"]`, `api["WidgetTree.GetAllWidgets"]`.

**Идентификаторы хуков:** `view:<Class>.<method>`, `data:…`, `exact:…`, `dlg:…`, `ac-class:<Class>.<method>`, `ac-method:<method>`, `ui:UIComponent.<method>`, `fix:<Class>.<method>`, `branch:<name>`, `panel:<uid>:<reason>` (reason: `Open`, `Refresh`, `delayed`, `extended-<delay>`, `manual`).

**Статусы** (в `hooks.json` и `dead_hooks.md`): `NOT_LOADED` — модуль игры не загружался; `NOT_INSTALLED` — модуль загружался, но класс/метод не найден; `NEVER_CALLED`; `NO_EFFECT` — вызывался, но `text_changes`, `data_changes` и `text_writes` равны 0; `CALLED` — лёгкий счётчик (`StringConst.Get`, форматтеры цен и чисел, `UIComponent.Close/Destroy`) без замера эффекта; `ACTIVE`. Отложенные ремонты (`scheduleRepairAfter`, `scheduleRepairBurst`) засчитываются хуку, который их запланировал; изменение текста засчитывается всем вложенным scope (хук → панель → ветка).

## Бюджет и безопасность
- Хуки только считают и кладут в очередь слабые ссылки. Замеры, обход дерева, чтение шрифтов и кистей, JSON и запись идут в `D.Tick()` (таймер `Game.NewUIManager:AddTimerWithFunction`), пока не исчерпан `FrameBudgetMs`; остаток переносится на следующий тик. Элемент очереди обрабатывается не раньше чем через один тик (прошёл хотя бы кадр).
- Потолки: очередь 5000, дедуп 20 000 ключей, промахи StringDB 100 000, сессия `SessionMB`. После потолка растут только счётчики `dropped.*` в `session.json`.
- Запись: закрытые части JSONL пишутся один раз; текущая часть, `fonts.json` и `session.json` переписываются раз в `FlushSeconds` (и через 5 с после открытия панели). `hooks.json` переписывается, только если изменился какой-либо счётчик (`counters.hooks_writes` / `hooks_unchanged`), и кодируется по частям в тиках в пределах `FrameBudgetMs`, а записывается одной операцией (первая сессия: `flush_ms_max = 35` из-за синхронного кодирования 106 КБ). Каждая запись ≤ 512 КБ.
- `os.clock` в игре идёт шагами ~1 мс, бюджет проверяется между элементами, поэтому один тяжёлый элемент может превысить `FrameBudgetMs`. `session.json → budget.max_item_ms / max_item_kind` (`measure`, `walk`, `font`, `image`, `encode`, `db`) показывает, какой именно. Выхода игры Lua не видит, поэтому **перед выходом постойте 30–40 с**.
- Все обращения к игре идут через `pcall`; ошибка внутри диагностики увеличивает `errors.<stage>` и не ломает хук. После 2000 внутренних ошибок модуль отключается (`[AbsruDiag] disabled: …`). Ошибки исходных функций обёртка считает (`errors`) и пробрасывает дальше с тем же сообщением.
- Нет `io.open`, нет путей разработчика: запись только через `LuaFunctionLibrary.SaveStringContentToFile` в `Loader.Root .. "logs/"`.
- JSON пишется чистым ASCII: кириллица и CJK — через `\uXXXX` (`AsciiJson = true`). Кодировку, в которой `SaveStringContentToFile` пишет не-ASCII, мы не проверяли, а ASCII читается одинаково при любой. `ConvertFrom-Json` и `CollectDiagLogs.ps1` декодируют экранирование сами.

## Ограничения
- Нативный `SetText` игры из Lua не перехватить: текст, который сменился без `Open` панели и без наших хуков, диагностика не увидит (ни в «непереведённом», ни в «переполнении»).
- Какой глиф выбрал Slate (fallback), из Lua не видно, в C7.log строк про fallback нет. Для этапа 4 список `pre`-шрифтов с кириллицей сверяется офлайн: экспорт `UFont/UFontFace` (FModel/CUE4Parse → `reference/fonts/`) и проверка cmap на U+0400–U+04FF.
- Удалять файлы Lua не умеет: старые части слота остаются, но `session.json → parts` перечисляет текущие, а у каждой строки есть `sid`; `CollectDiagLogs.ps1` фильтрует по `sid`.
- Повторы одной записи: строка JSONL пишется при первом появлении и затем при `count` = 2, 4, 8, … (и при росте переполнения больше чем на 2 px). Офлайн берётся максимум `count` по ключу.
- В диагностическом режиме обёртки вызывают исходную функцию через `pcall`: ошибка доходит до вызывающего с тем же сообщением, но без исходного стека.
- Счётчики `runtimeMetrics.GetAllWidgetsCalls`/`WidgetIndexesBuilt` не включают обходы диагностики (модуль восстанавливает их после своих вызовов).

## Файлы (`Saved/Mods/logs/`)
Все файлы — ASCII (валидный UTF-8 без BOM), LF. `sid` = `YYYYMMDD-HHMMSS`.

| Файл | Содержимое |
|---|---|
| `absru-state.txt` | номер последнего слота (`slot=`, `sid=`) |
| `absru-s<n>-session.json` | `sid`, `slot`, `version`, `started`, `last_flush`, `flags`, `dir`, `parts`, `lines`, `api` (какие API сработали: `GetParent`, `GetClass`, `Brush.ResourceObject`, `GetDesiredSize`, `GetCachedGeometry`, `IsVisible`, `GetPathName`), `gauges` (от `bootstrap.lua`), `budget` (`ticks`, `tick_ms_max`, `max_item_ms`, `max_item_kind`, `io_ms_max`, `flush_ms_max`, `queue_peak`, `flushes`), `dropped`, `errors`, `counters`, `pending`, `metrics` (весь `runtimeMetrics`) |
| `absru-s<n>-hooks.json` | `afterload[]` (`id`, `module`, `applied`), `hooks[]` (`id`, `kind`, `status`, `module`, `declared`, `installed`, `calls`, `text_changes`, `text_writes`, `data_changes`, `errors`, `ms_total`, `ms_max`), `panels[]` (`id`, `runs`, `labels`, `widgets`, `ms_*`), `writes` (сайты `SetText` в Init.lua), `unscoped` |
| `absru-s<n>-untranslated-NNN.jsonl` | `{"src":"widget","text","norm","panel","widget","path","scope","vis","count"}`, `{"src":"data","module","class","field","original","translated"}`, `{"src":"stringdb","module","row","en","cn"}` |
| `absru-s<n>-overflow-NNN.jsonl` | `panel`, `widget`, `path`, `text`, `len`, `font`, `typeface`, `size`, `size_pre`, `ls`, `ls_pre`, `ls_negative`, `wrap`, `need`, `have`, `parent`, `parent_have`, `kind` (`self`/`parent`/`both`), `count` |
| `absru-s<n>-fonts.json` | `standard`, `standard_typeface`, `cinematic`, `fonts[]` (`key` = `путь|typeface`, `role` `pre`/`post`, `count`, `texts_cyrillic`, `texts_cjk`, `texts_latin`, `sizes`, `widgets`, `panels`) |
| `absru-s<n>-images-NNN.jsonl` | `panel`, `widget`, `resource`, `class`, `size`, `count` |

**Маркеры в C7.log** (`Log.Info`, строки `LuaLog: ReleaseLog:`): `[AbsruDiag] session=<sid> slot=<n> dir=<путь> version=… flags=…`, `[AbsruDiag] flush #<k> parts=… queue=<n> tick_ms_max=<x> io_ms_max=<x> flush_ms=<x>`, `[AbsruDiag] disabled: <причина>`, `[AbsruDiag] error stage=<этап>: …` (первые 3 на этап), `[CPDDRuntimeFix] diagnostics unavailable: …` (модуль не запустился).

## Сбор и отчёты

```
powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1
```

Скрипт копирует **только из игры** (`C7.log` и `C7-backup-*.log` новее старта сессии, `Saved\Mods\logs\absru-*`, `Saved\Mods\absru-*`, `absoluteru_dev.lua`) в `reference\logs\<yyyy-MM-dd_HHmm>\` и строит `report\`: `REPORT.md` (сессии, бюджет, API, маркеры и ошибки из C7.log), `dead_hooks.md` + `hooks.csv`, `overflow_top.md` + `overflow.csv`, `untranslated.md` + `untranslated.csv` (сверка с батчами: «перевод есть, не применился» / «не переведено в батче» / «нет в батчах»), `fonts.md`, `textures.md` + `textures.csv`. В папку игры скрипт ничего не пишет.

Параметры: `-GameDir <…\C7>` (по умолчанию `D:\Games\GMZZLauncher\Game\C7`), `-Out <папка>`, `-Session latest|all|<sid>` (по умолчанию последняя), `-Aggregate` (все папки `reference\logs\*`; хук мёртвый, только если мёртв во всех сессиях), `-NoCopy` (только отчёты по уже скопированному), `-LogsRoot`.

## Чек-лист проверки в игре
1. Установить сборку v2.9.1-RU (`build\Lord-of-Mysteries-Russian-Patch.exe`: он возьмёт `patch_payload` из репозитория).
2. **Сначала без флагов:** запустить игру, пройти пару экранов. В `Saved\Logs\C7.log` должна быть строка `v2.9.1-RU active hooks_installed=` и **не должно быть** `[AbsruDiag]`; строк `[CPDDRuntimeFix]`, кроме этой и ошибок, быть не должно. Папка `Saved\Mods\logs\` не появилась. Субъективно подвисаний не больше, чем на v2.9.0.
3. Скопировать шаблон флагов (выше) в `…\C7\Saved\Mods\lua\absoluteru_dev.lua`.
4. Запустить игру. В C7.log найти `[AbsruDiag] session=… dir=…`; если там `disabled:` или есть `[CPDDRuntimeFix] diagnostics unavailable`, прислать эти строки. **При включённых флагах в C7.log видны строки `[CPDDRuntimeFix]` от `reportVerbose`** (например, `installed post-refresh widget repair for …`, `registered v2.9.1-RU`).
5. Пройти экраны (на каждом 3–5 с; списки прокрутить; вкладки переключить): логин и выбор сервера → главный HUD → Esc-меню (все пункты) → сумка + подсказка предмета → снаряжение (перековка/наследование) → навыки и таланты → детали персонажа (обе вкладки характеристик) → задания (доска, список) → диалог с NPC (с выбором ответа) → магазин и биржа (лоты, аукцион) → гильдия (участники, права, события) → стиль/гардероб → настройки (графика) → статистика/DPS → Автошахматы: главное меню, энциклопедия (таланты, снаряжение, фигуры, поиск), матч (HUD, карточки, итоги) → печати/слияние → активности.
6. Постоять 30–40 с на любом экране (сброс на диск раз в 30 с), затем закрыть игру. В C7.log должны быть строки `[AbsruDiag] flush #…` с `tick_ms_max` не больше ~3.
7. В репозитории: `powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1`. Открыть `reference\logs\<дата>\report\REPORT.md`.
8. Чтобы выключить диагностику, удалить `Saved\Mods\lua\absoluteru_dev.lua`. Папку `Saved\Mods\logs\` можно удалить вручную.

**Выяснится по первой сессии:** создаёт ли `SaveStringContentToFile` папку `logs/` (если нет — файлы в `Saved\Mods\` с тем же префиксом `absru-`, видно по `dir=` в маркере), какие API доступны (`session.json → api`), реальная цена тика (`budget.tick_ms_max`).
