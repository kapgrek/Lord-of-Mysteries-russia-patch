# TASK-005: диагностическая сборка для разработки (счётчики хуков, непереведённое, переполнение, шрифты, картинки)

Статус: **анализ завершён** 2026-09-25, ждёт исполнения. TASK-004 зарезервирован под опции DPS/Chat/Visual Clarity в новом установщике.
Номера строк даны по `HEAD c7c3dc3`. Перед правкой их нужно сверить: при вставке строки сдвигаются.

## Цель
Одна сборка для всех. Без файла флагов разработчика она ведёт себя как v2.9.0: в C7.log пишется одна строка при старте, горячие пути не получают новых вычислений. Если пользователь вручную положит файл флагов, сборка собирает данные для следующих этапов:
- **этап 4** (шрифт через CompositeFont): какие FontObject/Typeface реально рисуют кириллицу;
- **этап 5** (подгонка текста по измерению, удаление мёртвых костылей в `Init.lua`): какие хуки, спеки и ветки ремонта ни разу не сработали или ни разу не изменили текст; где текст не помещается;
- **этап 8** (русификация картинок): какие текстуры показываются на каких экранах.

Диагностика **только наблюдает**: не вызывает `SetText`, `SetFont`, `ForceLayoutPrepass`, не меняет `LetterSpacing` и не трогает виджеты.

---

## 1. Что уже есть (факты)

### 1.1 Флаги и логи
- `patch_payload/Saved/Mods/bootstrap.lua:19-28`: `Loader.Features`, `DiagnosticsMode = false`. `:81-123` `apply_feature_settings`, `:127-139` чтение `lua/cpdd_user_settings.lua`, `:143-158` `lua/cpdd_patcher_settings.lua`. Оба файла выполняются через `read_chunk` (`:66-79`), отсутствующий файл тихо даёт `nil`. **В игре пользователя обоих файлов нет** (в `Saved/Mods/lua/` лежат только `cpdd_translation/` и `mods/`), и ошибок про них в C7.log нет. Это код CPDD, его правит 3-way merge в `tools/SyncCpdd.ps1` (`:88`, `:400`), поэтому **bootstrap.lua не трогаем**.
- `bootstrap.lua:167-185` `Loader.LoadExternal(name)` читает `Saved/Mods/lua/<name>.lua` и выполняет его. Годится для файла флагов без правки bootstrap.
- `bootstrap.lua:531-534`: CPDD уже предусмотрел слот `Loader.Diagnostics:Gauge(category, name, value)`. Сейчас его никто не заполняет (в нашем `Init.lua` и в `vendor/cpdd/v2.6.4/Init.lua` нет определения). Наш модуль может занять этот слот и получит счётчики overlay бесплатно.
- `bootstrap.lua:580-587`: `PersonalLoad` грузит `mods.personal_cjk_logger.Init` только при `DiagnosticsMode`. Это личный модуль автора CPDD, в пакете его нет.
- `bootstrap.lua:208`: `Loader.Applied[moduleName]` считает применения AfterLoad-хуков по модулю, `Loader.Hooks[moduleName]` хранит их `Id`. Из этих двух таблиц видно, какие хуки зарегистрированы для модулей, которые ни разу не загрузились. Правка кода для этого не нужна.
- `Init.lua:1340-1345` `report()` → `Log.Info("[CPDDRuntimeFix] …")`; `:1396-1400` `reportVerbose` (только при `DiagnosticsMode == true`); `:1402-1405` `reportInstalled` (счётчик `HooksInstalled` + verbose). `:10566` — единственная строка релизного лога: `v2.9.0-RU active hooks_installed=N` (в последнем C7.log `hooks_installed=26`).
- `Init.lua:1347-1391` `runtimeMetrics`: там уже есть счётчики панелей и кэшей (`PanelsRepaired`, `PanelLabelsRepaired`, `SlowPanelRepairs`, `TargetedPanelSkips`, `SinglePassPanelSkips`, `NestedComponentSkips`, `WidgetsVisited`, `GetAllWidgetsCalls` и др.). Модуль экспортируется как `PerformanceMetrics` (`:10660`).
- `Init.lua:2064-2070`: **готовый шов CPDD** для dev-сборок, `runtimeMetrics.CaptureDataAssignment = function() return false end` («Development builds replace this no-op inside the stripped JSONL block») и флаг `CaptureDataAssignmentsEnabled` (`:1389`). Вызывается из `translateTableStrings` (`:3786`, `:3836`), `returnLiveRepairResult` (`:4045`, только если флаг включён и результат содержит CJK), `installDataMethodRepair` (`:6078`), `:4290`. Сигнатура: `(component, module, class, field, original, translated, record)`.
- **Куда пишутся логи сейчас:** только `Saved/Logs/C7.log` (ротация `C7-backup-*.log`). `Saved/Mods/cpdd-autochess-diag.log` писал блок диагностики AutoChess из `367dc94`, который удалён в `ffe9942` (v2.9.0). В игре остался файл от 24.09 20:35: 4594 строки, 870 КБ. Сейчас его никто не пишет, и ссылка на него в `docs/LESSONS.md:10` устарела.

### 1.2 Проверенные API (уже используются в продакшн-коде)
Движок использует **slua**, а не UnLua: `slua.loadObject` (`Init.lua:1550`), `import("…Library")`, в C7.log есть `Slua: …`.

| API | Где уже используется | Для чего нам |
|---|---|---|
| `import("LuaFunctionLibrary").SaveStringContentToFile(text, path)` | `DpsTelemetry.lua:909-914`, `DesktopChat.lua:1346`, `DpsMeter.lua:224-227`, старый diag `367dc94` | запись файлов; перезаписывает файл целиком, **функции дозаписи (append) не найдено** |
| `File.LoadFile(path)` | `bootstrap.lua:72`, `EngineIniBridge.lua:107` | чтение слота ротации |
| `widget:GetCachedGeometry()` + `SlateBlueprintLibrary.GetLocalSize/GetAbsoluteSize/LocalToAbsolute` | `DpsMeter.lua:691-710`, `DesktopChat.lua:596-601`, `Init.lua:5843` | фактический размер виджета |
| `widget:GetDesiredSize()` (`.X/.Y`) | `DpsMeter.lua:957`, `DesktopChat.lua:2341-2360` | нужный тексту размер |
| `widget:ForceLayoutPrepass()` | `DpsMeter.lua:955` | **не использовать**: меняет раскладку, диагностика только наблюдает |
| `widget.Slot:GetOffsets()/GetAnchors()` | `DpsMeter.lua:460-468` | размер слота (Canvas) |
| `WidgetLayoutLibrary.GetViewportSize` | `DpsMeter.lua:662-675` | масштаб экрана |
| `userWidget.WidgetTree:GetAllWidgets(arr)` | `Init.lua:1958-1996` (`getWidgetList`) | обход дерева панели |
| `GetChildrenCount/GetChildAt/GetContent/GetDisplayedEntryWidgets` | `Init.lua:2074-2134` (`walkWidgetDescendants`) | обход вложенных деревьев и строк ListView |
| `GetFont()` → `FontObject:GetPathName()`, `TypefaceFontName`, `Size`, `LetterSpacing` | `Init.lua:3435-3509` | шрифт |
| `GetDefaultTextStyleOverride()/DefaultTextStyle` у RichTextBlock | `Init.lua:3516-3531` | шрифт RichText |
| `image.Brush` (поле структуры) | `DesktopChat.lua:3788` (`Brush.ImageSize.X`) | кисть картинки |
| `owner:AddTimerWithFunction(delay, 1, fn)` на компоненте или `Game.NewUIManager` | `Init.lua:3584-3595`, `:6251-6264` | тик диагностики |
| `os.clock()`, `os.date` (через pcall) | `Init.lua:1598`, старый diag | бюджет времени, метки |

**Не проверено, проверять пробой при старте сессии** (результат записывается в `session.json → api`): `widget:GetParent()`, `widget:GetClass():GetName()`, `Brush.ResourceObject` и его `GetPathName()`, `widget:GetVisibility()/IsVisible()`, `widget:GetPathName()` у виджета (у шрифта работает). Если API нет, соответствующее поле пишется `null`, а сбор продолжается.

### 1.3 Ограничения и уроки, которые определяют дизайн
1. **Лимит local в Init.lua.** `tools/VerifyPatch.ps1:84-93` считает строки `^local ` и падает при > 190. Сейчас их **182** (запас 8). В Init.lua **не добавлять ни одного local верхнего уровня**: состояние держать в полях `runtimeFixes.*` и `Loader.*`, временные local — только внутри `do … end` или функций.
2. **Дампер `dumpAllChessTables`** (`c8a89b1`, откат `b9a3454`; затем `7f464bb`, удалён в `f8c9c03`): синхронный обход всех таблиц KSBC в игровом кадре и полная перезапись JSON (`io.open(... "w")` по абсолютному пути `d:/gameDev/...`) каждые 1,5 с. Отсюда правила: никаких синхронных обходов баз, никакого `io.open`, никаких путей разработчика.
3. **Старый diag AutoChess** (`367dc94`) после каждого события вызывал `diag.Flush()` (строки 10496/10520/10539/10545 в той ревизии), а тот переписывал весь файл через `SaveStringContentToFile`. Это O(N²) по объёму: 870 КБ за 5 минут. Правило: писать части фиксированного размера, текущую часть переписывать не чаще раза в N секунд, закрытые части больше не трогать.
4. **Хуки на уровне классов** (`docs/LESSONS.md:5-11`, память `autochess-class-level-refresh-hooks`): классы перекрывают `Refresh/OnRefresh`, поэтому сработавший хук базового `UIComponent` ничего не говорит о конкретной панели. Счётчики нужны на каждой обёртке (класс.метод), а не только на `UIComponent.Open/Refresh`.
5. **Выхода игры в Lua не видно:** в `cpdd_runtime_fixes/*.lua` нет обработчиков Quit/Shutdown/EndPlay. Сброс на диск делать периодически (раз в 30 с) и по крупным событиям (after_main, открытие панели). Перед выходом из игры пользователь ждёт 30 с.
6. **PerformanceMode** (`Init.lua:10-94`) опускает уровень игровых логов до Warning. Старый diag писал через `LuaCLogger.Warning`, чтобы строки не терялись. Маркеры диагностики в C7.log писать так же, а данные — в свои файлы.
7. **Отрицательный LetterSpacing задаёт наш код**, а не игра: `Init.lua:3416-3425` ставит `-120` (заголовки) / `-60` (остальное) для любого текста с кириллицей, `:3467` пишет то же в `font.LetterSpacing`. Там же `:3469-3506` подгоняют размер шрифта по **длине строки** (`> 14`, `> 10`, `> 6` символов) и `getAdjustedFontSize` (`:3291-3313`) добавляет `+2` к исходному размеру. Именно это заменит этап 5, поэтому диагностика пишет LetterSpacing и размер **до** и **после** стилизации. В `docs/LESSONS.md` пункта про «кашу» от отрицательного LetterSpacing **нет**: история есть только в git (`dbbbb49`, `e59b8f8`, `e33c004`, `7b2c29e`, `1b5c79f`, `17a9523`). Добавить урок в LESSONS при исполнении.
8. **Устаревшие хеши в LESSONS:** `docs/LESSONS.md:9` ссылается на `f15e301`, но после чистки истории это `ecd7dd2`. Блок диагностики, который упоминает `ffe9942` («kept in history, 88d787e»), на самом деле лежит в `367dc94`. Поправить.
9. **CPDD-merge:** `Init.lua` сливается 3-way (`tools/SyncCpdd.ps1:97`), поэтому правки в нём должны быть короткими однострочными вставками. Новый файл модуля SyncCpdd не видит: он перебирает только файлы из релизов CPDD (`:203`) и чужие файлы не удаляет. Имя выбрать такое, чтобы CPDD не выпустил файл с тем же именем: **`AbsruDiagnostics.lua`** (слот `Loader.Diagnostics` намекает, что у CPDD есть свой `Diagnostics`).

### 1.4 Установка и payload (п.9)
- `installer/Program.cs:901-922` `ResolvePayloadDir`: первыми проверяются локальные папки `<exe>\patch_payload`, `<exe>\..\patch_payload`, `data`, **жёстко прописанный `D:\gameDev\AbsoluteRU\patch_payload`**, затем zip рядом с exe и в Загрузках, затем GitHub. На ПК разработчика любой установщик (и `build\Lord-of-Mysteries-Russian-Patch.exe`, и скачанный релиз) ставит **рабочую копию репозитория**. При этом `VerifyOwnedFiles` (`InstallerCore.cs:559-563`) без `owned_files.json` в папке возвращает `true`, так что целостность не проверяется. Для dev-цикла это удобно, но это неочевидное поведение. Предложение вынести в TASK-004 (установщик): локальная папка только по явному `--payload <dir>`. **В этой задаче не менять.**
- `InstallerCore.cs:258-304`: установщик копирует всё из `Binaries/` и `Saved/` пакета, пишет `installed_files.json`, удаляет устаревшие **свои** файлы. `Uninstall` (`:411-459`) удаляет только файлы из списка и пустые папки. Значит, файл флагов, которого нет в пакете, установщик никогда не создаст и не удалит. Папку `Saved/Mods/logs/` тоже не тронет.
- `tools/PackageRelease.ps1:44-55`: `owned_files.json` строится по всем файлам `Binaries/` и `Saved/`, поэтому `AbsruDiagnostics.lua` попадёт в пакет автоматически.

**Решение по п.9:** отдельный профиль `-Profile dev` **не нужен**. Модуль входит в обычный пакет (≈ 30–40 КБ, в обычном режиме не загружается). Диагностику включает только файл флагов, который пользователь кладёт руками. Чтобы проверить сборку до публикации: `tools\PackageRelease.ps1 -Version v2.9.1-RU` без `-Publish` → запустить `build\Lord-of-Mysteries-Russian-Patch.exe`: он сам возьмёт `..\patch_payload` (`Program.cs:909`).

---

## 2. Архитектура

### 2.1 Файл флагов разработчика
`Saved/Mods/lua/absoluteru_dev.lua` (в игре). В пакете его нет, установщик его не создаёт и не удаляет. Шаблон лежит в `docs/DIAGNOSTICS.md`:

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

**Чтение:** в самом начале `Init.lua`, после `:1`, внутри `do … end` (новых local верхнего уровня нет):
```lua
do
    local ok, flags = pcall(Loader.LoadExternal, "absoluteru_dev")
    if ok and type(flags) == "table" and flags.Enabled == true then
        Loader.DevFlags = flags
        if flags.VerboseLog ~= false and type(Loader.Features) == "table" then
            Loader.Features.DiagnosticsMode = true
        end
    end
end
```
В обычном режиме это одна неудачная попытка открыть файл при старте и больше ничего. `DiagnosticsMode` из `cpdd_user_settings.lua` по-прежнему включает только verbose-лог, **модуль сбора он не включает**: так пользователь CPDD-настроек не получит тяжёлую диагностику случайно.

### 2.2 Модуль `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/AbsruDiagnostics.lua`
Грузится только из Init.lua и только если есть `Loader.DevFlags`. В `manifest.lua` его **не добавлять**. Возвращает таблицу `D`:

| Функция | Вызывается | Что делает |
|---|---|---|
| `D.Start(Loader, runtimeFixes, version)` | Init после `:1392` | выбирает слот, проверяет запись (`logs/` или корень `Mods/`), ставит `Loader.Diagnostics = D`, регистрирует `Loader.On("after_main", …, "absru.diagnostics.start")` для запуска тика; пишет в C7.log маркер `[AbsruDiag] session=<id> slot=<n> dir=<path>` через `LuaCLogger.Warning` |
| `D.Attach(helpers)` | Init после `:2134` | получает `getWidgetList` и подменяет `runtimeMetrics.CaptureDataAssignment` + ставит `CaptureDataAssignmentsEnabled = true` (подмена после `:2069`, иначе её затрёт no-op) |
| `D.Wrap(id, kind, fn, meta)` | каждый сайт замены метода | возвращает счётчик-обёртку: `calls++`, время, стек scope; ошибки пробрасывает (`error(msg, 0)`) и считает `errors` |
| `D.Declare(id, kind, meta)` | циклы регистрации спеков `:9047-9055` | объявленный id: попадёт в отчёт, даже если класс не нашёлся |
| `D.Enter(id, kind)` / `D.Leave(prev, t0, labels)` | `panelTextRepair:Repair`, отложенные ремонты | scope для веток без отдельной функции |
| `D.CurrentScope()` / `D.RunInScope(scope, fn, …)` | `scheduleRepairAfter`, `scheduleRepairBurst` | отложенный ремонт засчитывается хуку, который его запланировал |
| `D.NoteTextChange(widget, before, after)` | `translateTextWidget` после успешного `SetText` | `text_changes++` у текущего scope |
| `D.NoteTextWrite(site)` | остальные 10 вызовов `SetText` в Init | `text_writes++` (без сравнения, дёшево) |
| `D.FontSnapshot(widget)` | `translateTextWidget` до стилизации | путь FontObject, Typeface, Size, LetterSpacing **до** наших правок |
| `D.OnTextWidget(widget, text, name, pre)` | `translateTextWidget` перед `return` | очередь: непереведённое, шрифт, замер переполнения в следующем тике |
| `D.OnPanelOpen(component)` | обёртка `UIComponent.Open` | ставит в очередь обход дерева панели через 0,5 с и 2,0 с, не больше `PanelWalksPerUid` раз на uid |
| `D.OnDbMiss(module, rowId, en, cn)` | `Loader.TranslateDatabaseString` перед `return nil` | добавляет запись в массив, JSON кодируется позже в тике |
| `D:Gauge(cat, name, value)` | `bootstrap.lua:532-533` (уже есть) | в `session.json → gauges` |
| `D.Tick()` / `D.Flush(force)` | таймер | обработка очереди в пределах `FrameBudgetMs`, сброс на диск раз в `FlushSeconds` |

**Нулевая цена в обычном режиме:** в Init.lua есть поле `runtimeFixes.Diag = nil` и функция `runtimeFixes.diagWrap = function(_, _, fn) return fn end`, которая вызывается только при установке хука. В горячих путях добавляется только `local d = runtimeFixes.Diag; if d ~= nil then … end`: один поиск в хеш-таблице.

**Бюджет и безопасность (диагностический режим):**
- Вся тяжёлая работа (замеры, обход дерева, чтение шрифтов, кисти, кодирование JSON, запись) идёт только в `D.Tick()`. Хуки лишь кладут в очередь слабые ссылки (`__mode = "k"` / `"v"`) и строки.
- `Tick` работает, пока `os.clock()*1000 - t0 < FrameBudgetMs`, затем переносит остаток на следующий тик (`AddTimerWithFunction(TickSeconds, 1, …)` на `Game.NewUIManager`, перепланирование в конце тика). Если таймер недоступен (до `after_main`), очередь копится, а `D.OnPanelOpen` вызывает `D.Tick()` как запасной «насос».
- «Через кадр»: у элемента очереди есть поколение `gen`; тик обрабатывает только элементы из прошлых тиков, то есть хотя бы один кадр прошёл.
- Потолки: очередь ≤ 5000 (дальше `dropped.queue++`), дедуп-наборы ≤ 20 000 ключей, промахи StringDB ≤ 100 000, сессия ≤ `SessionMB`. После потолка остаются только счётчики.
- Запись: закрытые части JSONL (`PartKB`) пишутся один раз. Текущая часть и сводки `hooks.json`/`fonts.json`/`session.json` переписываются раз в `FlushSeconds`. Каждая запись ≤ 512 КБ, а время записи учитывается в `session.json → io_ms_max`.
- Все вызовы API идут через `pcall`. Ошибка внутри диагностики увеличивает `errors.<stage>` и никогда не ломает хук.
- Ротация сессий: `logs/absru-state.txt` хранит номер последнего слота (`File.LoadFile`, затем +1 по модулю `Slots`). Удалять файлы в Lua нечем, поэтому старые части слота остаются, но `session.json → parts` перечисляет только текущие, а у каждой строки есть `sid`.

### 2.3 Идентификаторы хуков
Формат `<kind>:<Class>.<method>` (для панелей `panel:<uid>:<reason>`):

| kind | Источник | Пример |
|---|---|---|
| `view` | `installViewMethodRepair` `:6013` | `view:SkillCommon_Panel.OnRefresh` |
| `data` | `installDataMethodRepair` `:6066` | `data:UIComButton.SetName` |
| `exact` | `installExactWidgetRepair` `:7693` + `D.Declare` из `exactWidgetRepairSpecs` | `exact:LoginPanel.setServerInfoUI` |
| `dlg` | `installDialogueControlRepair` `:7653` | `dlg:Dialogue_Panel.<method>` |
| `ac-class` | `hookAutoChessClassTable` `:10273` | `ac-class:AutoChess_Catalog_Talent_Page.RefreshTalentResult` |
| `ac-method` | `hookAutoChessMethod` `:10328` | `ac-method:SetData` |
| `ui` | `installEventDrivenPanelRepair` `:10397`, `:10457` | `ui:UIComponent.Open` |
| `panel` | `panelTextRepair:Repair` `:9542` (reason: `Open`, `Refresh`, `delayed`, `extended-<delay>`, `manual`) | `panel:Shops_Panel:extended-2` |
| `branch` | ветки внутри Repair: `:9557` (Shops currency), `:9581` (GuildInside event preview), `:9587` (AutoChess HUD attrs) | `branch:guild-event-preview` |
| `fix` | одиночные сайты (список ниже) | `fix:SceneText.RefreshContent` |
| `afterload` | `Loader.Hooks`/`Loader.Applied` (без правок) | `afterload:cpdd.runtime-fix.guild-role-names` |

Одиночные сайты `fix:` (обернуть `runtimeFixes.diagWrap("fix:<Class>.<method>", "fix", function … end)`): `:4219` PostHotfix, `:5054` KsbcManager.Init, `:5449` SetDisplayText, `:5466` RefreshContent, `:5480` InnerTextBlockReady, `:5518` StringConst.Get, `:5647` GetSeatName, `:5708` RefreshStyle, `:5917` GenerateTipsDesc, `:5951` skillSystem[method], `:5964` GetCurrentSkillRelatedTalentIDs, `:6139` SetData (EquipSpecial), `:6188` GetSealedSkillDescText, `:6221` guildSystem[method], `:6502` InitUIData, `:6515` ShowContent, `:7259` FormatScoreTip, `:7335` formatPrice, `:7353` refreshAuctionItemInfo, `:7385` OnRefresh (exchange), `:7474` GetFormatNumberString, `:7559/7573/7589` SetAs6V6/12V12/Champion, `:7912` OnRefresh (player detail row), `:7988` RefreshProperties, `:8158` Refresh (settings preset), `:9388` MenuBtn, `:9432` Menu_Panel, `:10519` CheckSwitchMapStats, `:10580` processSystemTextMessage. Для частых форматтеров (`StringConst.Get`, `formatPrice`, `GetFormatNumberString`) считать только `calls`, без scope (флаг `meta.light = true`), чтобы не мерить время на каждом вызове.

**Осторожно с маркерами-наборами:** `runtimeFixes.AutoChessClassWrappers[wrapper]` (`:10276`) и `AutoChessHookedWrappers[wrapper]` (`:10382`) должны получать **итоговую** функцию (после `diagWrap`), иначе `:10262` и `:10314` снова обернут уже обёрнутое.

### 2.4 Непереведённое (п.3)
Три источника, один файл `untranslated-NNN.jsonl`, дедуп по `(src, norm)`, где `norm` — текст с цифрами, заменёнными на `#`, и схлопнутыми пробелами:
1. `widget`: итоговый текст из `translateTextWidget` и из собственного обхода панели, если в нём есть CJK (`[\228-\233][\128-\191][\128-\191]`, как `hasCjk` `:3911-3913`) или латиница без кириллицы (≥ 2 букв подряд; числа, `%s`, теги `<…>`, одиночные аббревиатуры `HP/DPS/PvP/UID/ID/Lv` отсекаются уже офлайн, а не в рантайме).
2. `stringdb`: `Loader.TranslateDatabaseString` вернул `nil` (`Init.lua:10636`). Функция вызывается из `bootstrap.lua:412-418` при слиянии overlay (≈ 65 000 записей, `C7.log`: `entries=65027`) синхронно при загрузке. Поэтому `D.OnDbMiss` только кладёт 4 ссылки в массив, а JSON собирается в тиках.
3. `data`: `CaptureDataAssignment`, если `translated` всё ещё содержит CJK или равен `original` и не содержит кириллицы.

### 2.5 Переполнение (п.4, только наблюдение)
Кандидаты: виджеты из `D.OnTextWidget` (наши правки) и текстовые виджеты из обхода панели (текст, который ставит игра). Нативные `SetText` игры из Lua перехватить нельзя, поэтому текст, который сменился без Open панели и без наших хуков, диагностика не увидит. Это нужно явно написать в DIAGNOSTICS.md.

Замер в тике (не раньше следующего поколения):
1. Пропустить, если `GetCachedGeometry` даёт 0×0 (не нарисован или скрыт).
2. `desired = GetDesiredSize()`, `alloc = GetLocalSize(GetCachedGeometry())`.
3. `overflow_self`: `desired.X > alloc.X + 1` (без `AutoWrapText`) или `desired.Y > alloc.Y + 1`.
4. `overflow_parent`: если `GetParent()` доступен, геометрия виджета выходит за `GetLocalSize` родителя (сравнение через `LocalToAbsolute` углов, как `DpsMeter.lua:708-710`). Записать класс родителя: `ScrollBox` и `SizeBox`/`ScaleBox` офлайн обрабатываются отдельно.
5. Запись идёт, только если переполнение больше 1 px. Дедуп по `(path, norm)`: хранить максимум `need−have` и `count`.

### 2.6 Шрифты (п.5)
`fonts.json`: ключ `font_path|typeface`. Для каждого ключа: `widgets` (уникальные имена, ≤ 20), `sizes` (гистограмма), `texts_cyrillic`, `texts_cjk`, `texts_latin`, `panels` (≤ 20), `role` (`pre` — авторский шрифт до нашей замены, `post` — после). Отдельно пишутся `runtimeFixes.StandardFontObject`/`CinematicFontObject` (пути) и `StandardTypefaceFontName`.
Узнать из Lua, что Slate подставил fallback-глиф, **нельзя**: выбор глифа идёт в `FSlateFontCache`, в C7.log нет строк про fallback/LastResort (проверено по 4 логам). Поэтому для этапа 4 данные сопоставляются офлайн: список `pre`-шрифтов с кириллицей → экспорт этих `UFont/UFontFace` из паков (FModel/CUE4Parse в `reference/fonts/`) → проверка cmap на U+0400–U+04FF. Шрифт без кириллицы, который рисует кириллицу, и есть случай fallback.

### 2.7 Картинки (п.6)
В обходе панели для виджетов, у которых есть поле `Brush` (Image/KGImage): `Brush.ResourceObject:GetPathName()`, класс ресурса (Texture2D/PaperSprite/Material), `ImageSize`, имя виджета, uid панели. Дедуп по `(panel, resource)`. Приоритеты для этапа 8 считаются офлайн: число панелей × число показов, эвристика имени (`Text|Title|Word|Font|Name|Label|_CN|Zi`). Сами текстуры выгружаются офлайн из `Content/Paks` (FModel/CUE4Parse → `reference/textures/`). **Риск для этапа 8:** в `Content/Paks` лежат 8 файлов `.upak` (нестандартный контейнер) рядом с 2 `.utoc`/47 `.ucas`/1 `.pak`. Поддержку `.upak` в FModel проверить до начала этапа 8.

---

## 3. Форматы файлов (`Saved/Mods/logs/`)
Все файлы UTF-8 без BOM, LF. Строки JSONL — по одному объекту на строку, `sid` = id сессии (`YYYYMMDD-HHMMSS`).

`absru-s<slot>-session.json`
```json
{"schema":1,"sid":"20260925-213000","slot":2,"version":"2.9.1-RU","started":"2026-09-25 21:30:00",
 "flags":{...},"dir":"D:/…/Saved/Mods/logs","parts":{"untranslated":3,"overflow":2,"images":1},
 "api":{"GetParent":true,"GetClass":true,"Brush.ResourceObject":true,"GetDesiredSize":true,"GetCachedGeometry":true},
 "gauges":{"translation_data.overlay_modules":1,"translation_data.overlay_entries":65027},
 "budget":{"ticks":1234,"ms_total":812.4,"tick_ms_max":2.9,"queue_peak":417,"io_ms_max":6.1,"flushes":41},
 "dropped":{"queue":0,"dedup":0,"session_cap":0},"errors":{"measure":0,"walk":0,"io":0},
 "metrics":{ ...runtimeMetrics целиком... },"last_flush":"2026-09-25 21:50:30"}
```

`absru-s<slot>-hooks.json`
```json
{"schema":1,"sid":"…","afterload":[{"id":"cpdd.runtime-fix.guild-role-names","module":"Gameplay.LogicSystem.Guild.GuildSystem","applied":2}],
 "hooks":[{"id":"exact:LoginPanel.setServerInfoUI","kind":"exact","module":"Gameplay.LogicSystem.Login.LoginPanel",
   "declared":true,"installed":true,"calls":12,"text_changes":5,"text_writes":0,"data_changes":0,"errors":0,"ms_total":4.21,"ms_max":1.10}],
 "panels":[{"id":"panel:Shops_Panel:extended-2","runs":4,"labels":0,"widgets":8812,"ms_total":61.0,"ms_max":19.2}]}
```
Статус хука в отчёте: `NOT_LOADED` (модуль не загружался: `applied` = 0/нет), `NOT_INSTALLED` (declared, но `installed=false`), `NEVER_CALLED`, `NO_EFFECT` (calls > 0, все `*_changes` = 0), `ACTIVE`.

`absru-s<slot>-untranslated-NNN.jsonl`
```json
{"sid":"…","src":"widget","text":"装备","norm":"装备","panel":"BagItemTips_Panel","widget":"Text_Name","path":"WBP_ItemTips_C_0.WidgetTree.Text_Name","scope":"data:ItemTipsText_Item.OnRefresh","count":1,"t":"21:31:05"}
{"sid":"…","src":"stringdb","module":"Data.Excel.LanguageData.StringDB_CN_Data_UI","row":413898750559745,"en":"…","cn":"…"}
{"sid":"…","src":"data","module":"…","class":"…","field":"SetName.argument1","original":"…","translated":"…"}
```

`absru-s<slot>-overflow-NNN.jsonl`
```json
{"sid":"…","panel":"Menu_Panel","widget":"Text_BtnName","path":"…","text":"Настройки авторазбора","len":21,
 "font":"/Game/Arts/UI_2/Resource/Font/Font_Aleo.Font_Aleo","typeface":"Regular","size":16,"size_pre":14,
 "ls":-120,"ls_pre":0,"ls_negative":true,"wrap":false,
 "need":[212.0,24.0],"have":[168.0,24.0],"parent":"SizeBox","parent_have":[168.0,30.0],"kind":"self","count":3}
```

`absru-s<slot>-fonts.json`: `{"sid":…, "standard":…, "cinematic":…, "fonts":[{"key":"<path>|<typeface>","role":"pre|post",…}]}`.

`absru-s<slot>-images-NNN.jsonl`
```json
{"sid":"…","panel":"ActivityMain_Panel","widget":"Img_Title","resource":"/Game/Arts/UI_2/…/T_Title_CN.T_Title_CN","class":"Texture2D","size":[512,128],"count":2}
```

Маркеры в C7.log (Warning, чтобы найти их `Select-String`):
`[AbsruDiag] session=<sid> slot=<n> dir=<path> flags=<…>`, `[AbsruDiag] flush #<k> parts=<…> queue=<n> tick_ms_max=<x>`, `[AbsruDiag] disabled: <reason>` (если запись невозможна).

---

## 4. Точки вставки в Init.lua (сверить номера строк)
| # | Место | Вставка |
|---|---|---|
| 1 | после `:1` | `do`-блок чтения `absoluteru_dev` (§2.1) |
| 2 | после `:1392` (`local runtimeFixes = {}`) | `runtimeFixes.diagWrap = function(_, _, fn) return fn end`; при `Loader.DevFlags` — `pcall(require, "mods.cpdd_runtime_fixes.AbsruDiagnostics")`, `D.Start(...)`, `runtimeFixes.Diag = D`, `runtimeFixes.diagWrap = D.Wrap`; ошибка → `report("diagnostics unavailable: …")` |
| 3 | после `:2134` (конец `walkWidgetDescendants`, уже после шва `:2069`) | `if runtimeFixes.Diag then runtimeFixes.Diag.Attach({ getWidgetList = getWidgetList, runtimeMetrics = runtimeMetrics }) end` |
| 4 | `:3377-3398` `translateTextWidget` | после `SetText`: `if changed and d then d.NoteTextChange(widget, currentText, translated) end` (`local d = runtimeFixes.Diag` в начале функции) |
| 5 | `:3404` перед стилизацией / `:3535` перед `return` | `local pre = d and d.FontSnapshot(widget)`; перед `return repairedCount` → `if d then d.OnTextWidget(widget, translated or currentText, widgetName, pre) end` |
| 6 | `:5800, :6552, :6560, :6586, :6616, :6664, :6746, :7363, :7393` | `D.NoteTextWrite("<site>")` при `runtimeFixes.Diag` |
| 7 | `:6251-6264` `scheduleRepairAfter`, `:6267-6299` `scheduleRepairBurst` | захватить `D.CurrentScope()` при планировании, колбэк выполнить через `D.RunInScope` |
| 8 | `:6013`, `:6066`, `:7653`, `:7693` | `class[methodName] = runtimeFixes.diagWrap("<kind>:" .. symbolName .. "." .. methodName, "<kind>", function(self, ...) … end, { module = source })` |
| 9 | `:9047-9055` | в циклах регистрации: `D.Declare` для каждого `spec[2] .. "." .. method` (view/data/exact) |
| 10 | `:9542-9632` `panelTextRepair:Repair` | `Enter("panel:" .. uid .. ":" .. reason)` в начале, `Leave(prev, started, repaired)` перед `return`; ветки `:9557/:9581/:9587` — `Enter/Leave("branch:…")` |
| 11 | `:10273`, `:10328` | `diagWrap("ac-class:" .. className .. "." .. name)`, `diagWrap("ac-method:" .. methodName)`; в `AutoChessClassWrappers`/`AutoChessHookedWrappers` класть итоговую функцию |
| 12 | `:10397-10440` | `diagWrap("ui:UIComponent." .. methodName)`; после `ProcessOnce` при `methodName == "Open"` → `d.OnPanelOpen(self)` |
| 13 | `:10457` | `diagWrap("ui:UIComponent." .. methodName)` (Close/Destroy): считаем только вызовы |
| 14 | одиночные сайты §2.3 | `diagWrap("fix:…", "fix", …)` |
| 15 | `:10636` | перед `return nil`: `local d = runtimeFixes.Diag; if d then d.OnDbMiss(moduleName, rowId, enValue, cnValue) end` |
| 16 | `:10566` | в строку релизного лога ничего не добавлять; `D.Start` пишет свой маркер сам |

Проверка лимита: после правок `(Select-String '^local ' Init.lua).Count` = **182** (не больше).

---

## 5. `tools/CollectDiagLogs.ps1` (п.8)
Параметры: `-GameDir` (по умолчанию `D:\Games\GMZZLauncher\Game\C7`, если есть), `-Out reference\logs\<yyyy-MM-dd_HHmm>`, `-Session latest|all|<sid>`, `-Aggregate` (отчёт по всем папкам `reference/logs/*`), `-NoCopy` (только отчёты по уже скопированному).
1. **Копирование только ИЗ игры** (`Copy-Item -Path <game> -Destination <reference>`; хук `guard-game.ps1` это разрешает): `Saved/Logs/C7.log` и `C7-backup-*.log` новее старта сессии, `Saved/Mods/logs/absru-*`, `Saved/Mods/lua/absoluteru_dev.lua` (для истории флагов). В игре ничего не создавать, не удалять и не переименовывать. Остальные операции работают с копией.
2. **Отчёты** в `<Out>/report/` (UTF-8 без BOM, LF; `[IO.File]::WriteAllText` с `UTF8Encoding($false)`):
   - `REPORT.md`: сессии, флаги, бюджет (`tick_ms_max`, `io_ms_max`, dropped), маркеры и ошибки `[AbsruDiag]`/`[CPDDRuntimeFix]` из C7.log.
   - `dead_hooks.md` + `hooks.csv`: статусы из §3. С `-Aggregate` хук мёртвый, только если он мёртв во всех сессиях. Сверка с кодом: распарсить `exactWidgetRepairSpecs`/`viewRepairSpecs`/`dataRepairSpecs` и `"cpdd.runtime-fix.*"` из текущего `Init.lua`. Id, которых нет ни в одной сессии, получают статус `NOT_LOADED (нет данных)`. Отдельная таблица `panel:*:extended-*` / `delayed` с `labels = 0`: это кандидаты на урезание `extendedPanelRepairDelays` (`Init.lua:9478-9495`), но только вместе с `docs/LESSONS.md` «Тайминги repair-очередей».
   - `overflow_top.md` + `overflow.csv`: топ по экранам (panel → виджеты по `need−have`), отдельный раздел `ls_negative = true`, сравнение `size_pre` и `size`.
   - `untranslated.md` + `untranslated.csv`: дедуп по всем сессиям, офлайн-фильтр (числа, плейсхолдеры, аббревиатуры). Сверка с `source/translation_batches/batch_*.json`: `source_cn`/`ref_en` найден и `target_ru` не пуст → «перевод есть, не применился»; найден без `target_ru` → «не переведено в батче»; не найден → «нет в батчах». Для `stringdb` — отдельный раздел по модулям.
   - `fonts.md`: `pre`-шрифты × кириллица / CJK / латиница, панели. Отдельно список путей для офлайн-экспорта на этапе 4.
   - `textures.md` + `textures.csv`: ресурс × панели × показы, эвристика имени, приоритет. Список путей для экспорта FModel на этапе 8.
3. Никаких сетевых запросов и запусков игры или установщика.

---

## 6. План для чата исполнения
1. **Модуль** `AbsruDiagnostics.lua` по §2.2–2.7 и §3: JSON-энкодер (экранировать `\\`, `"`, управляющие символы; UTF-8 без изменений), очередь с поколениями, тик с бюджетом, части JSONL, слоты, пробы API, `Gauge`. Внутри модуля никаких обращений к игре вне `pcall`. Верхних local — сколько угодно (это отдельный чанк, но лимит 200 тоже действует, держать < 150).
2. **Init.lua**: вставки §4 (однострочные, в стиле окружающего кода, без новых local верхнего уровня). `VERSION` → `2.9.1-RU` (и остальные места версии, как в `ffe9942`: `installer/AssemblyInfo.cs`, `installer/Program.cs`, `installer/app.manifest`, `README.md`, `tools/PackageRelease.ps1`, `tools/VerifyPatch.ps1`).
3. **VerifyPatch.ps1**: распространить проверки баланса блоков и счёт `^local ` на `AbsruDiagnostics.lua`. Проверить, что в `Init.lua` осталось 182 local верхнего уровня.
4. **tools/CollectDiagLogs.ps1** по §5. Проверить на поддельных данных: `temp/diag-fake-game/Saved/{Logs,Mods/logs}` с вручную составленными `session.json`/`hooks.json`/JSONL (по 2 сессии, один мёртвый хук, один переполненный виджет, одна CJK-строка, которая есть в батче) → `-GameDir temp\diag-fake-game -Out temp\diag-report`.
5. **Документы:** `docs/DIAGNOSTICS.md` (шаблон флагов §2.1, что собирается, ограничения §2.5, чек-лист §7, форматы §3 кратко); `docs/PROJECT_MAP.md` (строки для модуля, CollectDiagLogs, `reference/logs/`); `AGENTS.md` §4 — «новая диагностика только при `DiagnosticsMode = true` или в `AbsruDiagnostics.lua` при `Saved/Mods/lua/absoluteru_dev.lua`»; `docs/LESSONS.md`: исправить `f15e301 → ecd7dd2`, пометить `cpdd-autochess-diag.log` как удалённый в `ffe9942`, добавить уроки «диагностика не переписывает большой файл на каждое событие» и «отрицательный LetterSpacing задаёт наш `translateTextWidget`».
6. **Сборка без публикации:** `tools\PackageRelease.ps1 -Version v2.9.1-RU` (без `-Publish`) → `tools\InstallerCoreTests.exe --check-payload` на распакованном zip → убедиться, что `AbsruDiagnostics.lua` есть в `owned_files.json`, а `absoluteru_dev.lua` в пакете **нет**.
7. Коммиты: (a) модуль + Init.lua + VerifyPatch; (b) CollectDiagLogs; (c) документы. Push `main`. Релиз публиковать только после проверки пользователем (п.7 ниже), отдельным решением.

## 7. Проверка
**Автоматическая (чат исполнения):**
- `tools\VerifyPatch.ps1` зелёный; `^local ` в Init.lua = 182.
- `git diff` Init.lua: только вставки из §4, логика ремонта не изменилась (ни одного изменённого условия, задержки или регулярки).
- `Select-String 'io\.open|d:/gameDev|ForceLayoutPrepass|SetText|SetFont|SetLetterSpacing' AbsruDiagnostics.lua` → пусто.
- CollectDiagLogs на поддельной папке строит все 6 отчётов; мёртвый хук, переполнение и строка «перевод есть, не применился» видны.
- Поддельная папка игры после прогона не изменилась (сравнить хеши до/после).

**Чек-лист для пользователя (в игре):**
1. Установить сборку v2.9.1-RU (`build\Lord-of-Mysteries-Russian-Patch.exe`, он возьмёт `patch_payload` из репозитория).
2. **Сначала без флагов:** запустить игру, пройти пару экранов. В `Saved\Logs\C7.log` должна быть строка `v2.9.1-RU active hooks_installed=` и **не должно быть** `[AbsruDiag]`. Папка `Saved\Mods\logs\` не появилась. Субъективно: подвисаний больше, чем на v2.9.0, нет.
3. Скопировать шаблон из `docs/DIAGNOSTICS.md` в `…\C7\Saved\Mods\lua\absoluteru_dev.lua`.
4. Запустить игру. В C7.log найти `[AbsruDiag] session=… dir=…`; если там `disabled:`, прислать эту строку.
5. Пройти экраны (на каждом 3–5 с; списки прокрутить; вкладки переключить):
   логин и выбор сервера → главный HUD → Esc-меню (все пункты) → сумка + подсказка предмета → снаряжение (перековка/наследование) → навыки и таланты → детали персонажа (обе вкладки характеристик) → задания (доска, список) → диалог с NPC (с выбором ответа) → магазин и биржа (лоты, аукцион) → гильдия (участники, права, события) → стиль/гардероб → настройки (графика) → статистика/DPS → Автошахматы: главное меню, энциклопедия (таланты, снаряжение, фигуры, поиск), матч (HUD, карточки, итоги) → печати/слияние → активности.
6. Постоять 30–40 с на любом экране (сброс на диск раз в 30 с), затем закрыть игру. В C7.log должны быть строки `[AbsruDiag] flush #…` с `tick_ms_max` не больше ~3.
7. В репозитории: `powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1`. Открыть `reference\logs\<дата>\report\REPORT.md`.
8. Чтобы выключить диагностику, удалить `Saved\Mods\lua\absoluteru_dev.lua`. Папку `Saved\Mods\logs\` можно удалить вручную.

**Неизвестно заранее, выяснится по первой сессии:** создаёт ли `SaveStringContentToFile` папку `logs/` (если нет — модуль пишет в `Saved/Mods/` с тем же префиксом `absru-`, это видно в маркере `dir=`), какие API из «не проверено» (§1.2) доступны (`session.json → api`), реальная цена тика.

## Промпт для чата исполнения
> Выполни docs/tasks/TASK-005-diagnostics.md. Создай patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/AbsruDiagnostics.lua (§2.2–2.7, форматы §3): только наблюдение, вся работа в тике с бюджетом FrameBudgetMs, части JSONL фиксированного размера, слоты сессий, все вызовы игры через pcall, без io.open и без путей разработчика. В Init.lua сделай только вставки из §4 (сверь номера строк с текущим файлом), не добавляй ни одного local верхнего уровня (должно остаться 182) и не меняй логику ремонта. Файл флагов Saved/Mods/lua/absoluteru_dev.lua читается через Loader.LoadExternal, в пакет он не входит; bootstrap.lua и manifest.lua не трогай. Подними версию до 2.9.1-RU везде, где её меняли в ffe9942. Расширь tools/VerifyPatch.ps1 на новый модуль. Напиши tools/CollectDiagLogs.ps1 (§5: только копирование ИЗ игры в reference/logs/<дата>, отчёты в report/) и проверь его на поддельной папке в temp/. Обнови docs/DIAGNOSTICS.md (новый, с шаблоном флагов и чек-листом §7), PROJECT_MAP.md, AGENTS.md §4, LESSONS.md (§6 п.5). Собери PackageRelease без -Publish, проверь owned_files.json (модуль есть, файла флагов нет) и InstallerCoreTests --check-payload. Закоммить тремя коммитами и запушь main. Не публикуй релиз и не пиши «исправлено»: в конце дай мне чек-лист из §7.
