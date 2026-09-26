# Диагностика для разработки (AbsruDiagnostics)

Одна сборка для всех. Без файла флагов разработчика патч работает как обычно: в `C7.log` три строки после старта, все пишутся в `after_main` (`[CPDDRuntimeFix] cyrillic font mode=…`, `text fit mode=… early_nested=…` и `v2.9.9-RU active hooks_installed=N`; в режимах `cap` / `measure`, если проба `ForceLayoutPrepass` к этому моменту ещё не прошла, позже добавится `text fit prepass=ok|missing`), модуль диагностики не загружается, в горячих путях `Init.lua` добавлена одна проверка `runtimeFixes.Diag ~= nil`. С файлом флагов сборка собирает данные для следующих этапов:

- **этап 4** (шрифт через CompositeFont): какие FontObject/Typeface реально рисуют кириллицу;
- **этап 5** (подгонка текста по измерению, удаление мёртвых костылей): какие хуки, спеки и ветки ремонта ни разу не сработали или ни разу не изменили текст, где текст не помещается;
- **этап 8** (русификация картинок): какие текстуры показываются на каких экранах.

Диагностика **только наблюдает**: не вызывает `SetText`, `SetFont`, `ForceLayoutPrepass`, не меняет `LetterSpacing` и не трогает виджеты. Замеры до перевода (`need_pre`), результаты подгонки (`fit`) и пробу `ForceLayoutPrepass` ей передаёт `Init.lua` (`runtimeFixes.TextFit`, TASK-011) через `D.PreMeasure`, `D.NoteFit`, `D.NoteApi`. План и обоснование: [tasks/TASK-005-diagnostics.md](tasks/TASK-005-diagnostics.md).

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
    -- CyrillicFont = "typeface", -- режим кириллицы: "face" (по умолчанию) | "typeface" | "off"
    -- CyrillicTitleFace = "NotoSerif_Regular", -- для "face": чей face поставить в Title (по умолчанию "Aleo_Regular")
    -- TextFit = "cap",      -- подгонка текста: "legacy" (по умолчанию, пороги v2.9.6) | "cap" (legacy + уменьшение по исходной разметке) | "measure" (v2.9.7)
    -- EarlyNested = false,  -- выключить ранний перевод вложенных компонентов (для сравнения)
}
```

Выключение: удалить `absoluteru_dev.lua`.

### Флаг `CyrillicFont` (TASK-006, TASK-009, TASK-010)
Перекрывает релизную константу `CYRILLIC_FONT_MODE` в `Init.lua` (с v2.9.6 — `"face"`). Читается, только если в файле `Enabled = true`. Это не наблюдение, а смена поведения, поэтому флаг по умолчанию закомментирован. Другие значения (в том числе удалённые `subfont` и `cultures`) игнорируются, и работает режим по умолчанию.
- `"face"` (TASK-009, TASK-010; по умолчанию) — в `Font_Aleo.CompositeFont.DefaultTypeface.Fonts` заменяется `FontFaceAsset` у трёх записей: `Title` → face записи `Regular`, `Title_SDF` → face `Regular_SDF`, `Title_SDF_HeadName` → face `Regular_SDF`. SDF-запись получает только SDF-face (путь содержит `_SDF`), обычный face в неё не ставится. Все face берутся из уже прочитанной структуры, по пути не загружаются. Все замены пишутся в одну копию `CompositeFont` (`Fonts:Set`, иначе `Remove` + `Insert`), и она присваивается обратно один раз. Затем путь face каждой записи читается обратно, число записей сверяется, вызывается `C7FunctionLibrary.FlushFontCache()`. При любой ошибке **все** записи возвращаются к прежним face (они удерживаются через `AddToRoot`), и включается `"typeface"`. Если нет записи-цели или записи-источника SDF (например, `Regular_SDF`), эта замена пропускается (`skip(…)` в логе), остальные выполняются. Запись `Title` обязательна: без неё ничего не пишется, и включается `"typeface"`. Подмена Title → Regular в виджетах в этом режиме не выполняется: пропорциональную кириллицу даёт сам шрифт, включая RichText и текст из данных.
- Флаг `CyrillicTitleFace` влияет только на запись `Title`: `"Aleo_Regular"` (по умолчанию, face записи `Regular`) или имя SubTypeface `Font_Aleo` — `"NotoSerif_Regular"`, `"NotoSansCJKsc_Regular"`, `"NotoSans_Regular"` (первый face записи, у которой путь содержит `/Fallback/<имя>.`). SDF-записи всегда получают `Regular_SDF`: у Fallback-шрифтов SDF-версии нет. Тест `NotoSerif_Regular` (v2.9.5, TASK-010) выглядел так же, как `Aleo_Regular`: в сборке игры у этого face кириллицы нет, и она уходит в `NotoSansCJKsc_Regular`. Кириллица с засечками возможна только через свой face (этап 4b).
- `"typeface"` — откат: у виджетов с кириллицей в `Font_Aleo` typeface `Title` меняется на `Regular` (`Title_SDF` → `Regular_SDF`, если такой есть). Текст, который игра выставляет сама (RichText, данные), остаётся Mincho (TASK-007).
- `"off"` — авторские typeface.

Во всех режимах текст с кириллицей в шрифтах не-Aleo (`Font_Mistery`, `Font_Aleo_Update`, Roboto) переводится на `Font_Aleo` (typeface `Title` или `Regular`), `LetterSpacing` у кириллицы — max(0, авторский) (до v2.9.7 — 0); при возврате виджета к тексту без кириллицы авторский шрифт восстанавливается. RichText не трогается.

**Когда применяется.** `face` пишется при загрузке `Init.lua` (кадр 0, до экрана загрузки, пока Slate не закэшировал шрифт). Если `Font_Aleo` на кадре 0 ещё не загружен, попытка повторяется в `after_main` (хук 1500, перед выводом строки). В строке режима `applied_at=load|after_main` — когда запись прошла успешно. Правка живёт только в памяти до выхода из игры.

Итог — одна строка в C7.log:
- `face`: `[CPDDRuntimeFix] cyrillic font mode=face title=<путь face> title_sdf=<путь face|skip(…)> title_sdf_headname=<путь face|skip(…)> write=<ok(set)|ok(insert)|err> verify=<ok|fail> flush=<ok|missing|err> applied_at=<load|after_main>` (и `source=<CyrillicTitleFace>`, если он не `Aleo_Regular`). Причины пропуска: `no_entry` (нет записи-цели), `no_source:<запись>`, `not_sdf`, `face_unreadable`, `no_face:<имя>` (для `Title`);
- при откате `mode=typeface reason=<…> title=… … title_typeface=Regular`; `reason` = `no_title`, `title_face_unreadable`, `no_face:<имя>`, `write:<ошибка>`, `verify_count`, `verify_no_entry:<запись>`, `verify:<запись>`, `flush`;
- `typeface` по флагу: `mode=typeface title_typeface=Regular`;
- `Font_Aleo` не загрузился: `mode=off reason=Font_Aleo_not_loaded requested=<режим> stage=<load|after_main>` (для `face` строка со `stage=load` заменяется результатом повтора в `after_main`).

То же пишется в `fonts.json → cyrillic_font` (`title`, `title_sdf`, `title_sdf_headname`, `source`, `previous` — прежние face через запятую). Режим выбирается при загрузке `Init.lua`, но строка выводится в `after_main`, прямо перед `active hooks_installed=`: `Log.Info` до инициализации логгера игры в C7.log не попадает (TASK-007).

**История.** `subfont` (v2.9.2–v2.9.5) откатывался всегда: `FInt32Range` в slua непрозрачен (TASK-008). `cultures` (v2.9.4–v2.9.5) давал `verify=ok`, но на экране ничего не менял (TASK-009). Оба режима, флаги `CyrillicCultureSub` и `CyrillicFlush` и проба `FInt32Range` удалены в v2.9.6 (TASK-010). Папку `Saved\Mods\logs\` можно удалить вручную (Lua удалять файлы не умеет).

### Флаг `TextFit` (TASK-011, TASK-013)
Перекрывает релизную константу `TEXT_FIT_MODE` (с v2.9.8 — `"legacy"`, блок `runtimeFixes.TextFit` в `Init.lua`). Значения: `legacy` | `cap` | `measure`, остальные игнорируются. Читается, только если `Enabled = true`.
- `"legacy"` (по умолчанию) — стилизация v2.9.6: авторский + 2, пороги по длине строки (`> 14` / `> 10` / `> 6` символов), выключенный перенос у «заголовков» по подстрокам имени и у синергий, `LetterSpacing` 0 у кириллицы. Замеров нет. В v2.9.7 по умолчанию был `measure`, он дал 1018 переполнений против 251 (TASK-013).
- `"cap"` (TASK-013, на проверке). Сначала ровно `legacy` (размер, перенос, интервал); этот размер — **потолок** (`cap`) и стартовая точка, крупнее он не становится. Дальше кириллица уменьшается только при надёжной мерке, снятой **на разметке исходного текста** перед нашей первой заменой (`PreMeasure`):
  - слот фиксирован (`have_pre > need_pre + 1`) → бюджет = ширина слота до перевода (с переносом — высота, если фиксирована высота);
  - слот авторазмерный → бюджет = ширина исходного текста × 1,15 (с переносом — высота × 1,25). Ширину исходного текста `PreMeasure` берёт после `ForceLayoutPrepass` (закэшированный desired size может принадлежать тексту-заглушке Blueprint) и только для того русского текста, который её заменил: у переиспользованного виджета с другим текстом этой мерки нет;
  - иначе (нет разметки исходного текста) — ничего не замеряется, размер = `cap`, `TextFitNoBudget + 1`. Геометрия родителя и разметка нашего текста бюджетом **не бывают**: авторазмерный родитель растёт вместе с текстом;
  - `need ≤ budget + 1` → `cap`; иначе размер = max(min, cap × budget / need), шаг 0,5, min = min(cap, max(12, 0,6 × авторский)); не больше 2 перезамеров, `fail` / `noeffect` — как у `measure`. Результат кэшируется по тексту и `cap`: повторные проходы ничего не замеряют. Отложенный замер — не больше 24 виджетов и 2 мс за тик; `ForceLayoutPrepass` вызывается только у виджетов с разметкой исходного текста.
  - В строках `fit` поля `mode = cap`, `cap` (размер legacy), `size_pre` (авторский); в `overflow` — `cap`. В `fit.md` — раздел «Уменьшено ниже v2.9.6».
- `"measure"` (v2.9.7, только для сравнения). Текст получает авторский размер, авторский перенос и `LetterSpacing` = max(0, авторский) у кириллицы (у прочего текста — авторский шрифт и интервал). Размер кириллицы уменьшается, только если замер показывает, что текст не помещается:
  - замер: `ForceLayoutPrepass()` + `GetDesiredSize()` против `GetLocalSize(GetCachedGeometry())`;
  - доступная ширина: собственный слот, если он фиксирован (до перевода был шире текста, или после раскладки текущего текста не равен ему); для авторазмерного виджета — до правого края родителя, но не меньше ширины исходного текста `need_pre`; `ScrollBox`-родитель не ограничивает. С авторским переносом сравнивается высота фиксированного слота;
  - размер = max(min, авторский × budget / need), шаг 0,5; min = max(12, 0,6 × авторский) (меньше 12 — авторский); не больше 2 перезамеров; размер только уменьшается;
  - на min не помещается → остаётся min, `TextFitFailed`, строка `fit` с `kind = fail` (в `fit.md` — список на сокращение перевода);
  - после `SetFont` замер не уменьшился пропорционально (±10 %) → `TextFitNoEffect`, строка `kind = noeffect`, второй попытки нет;
  - текст и размер не менялись с прошлой подгонки → ничего не замеряется (повторные проходы `delayed` / `extended` работы не добавляют). Размер, который игра выставила сама (не наш и не авторский), становится авторским;
  - нулевая геометрия (виджет ещё не прошёл layout) или слот нельзя классифицировать до раскладки → отложенный замер: таймер `Game.NewUIManager:AddTimerWithFunction` каждые 0,05 с, до 2 мс на тик, до 10 попыток; невидимые виджеты пропускаются;
  - нет `ForceLayoutPrepass` (`prepass=missing`) → каждый шаг ждёт следующей раскладки (один шаг на тик);
  - RichText (нет своего `Font`) и Esc-меню не трогаются. Синергии Автошахмат: перенос выключен, `SetRenderScale(0.7)` у `title_fetter`, размер — той же подгонкой.
  - Почему не подошёл: старт с авторского размера (21–27 вместо 14–16 у legacy), а бюджет авторазмерного слота брался по родителю, который к моменту замера уже растянут русским текстом, поэтому почти всё «помещалось» (TASK-013, LESSONS).

Метрики (`session.json → metrics`): `TextFitMeasured`, `TextFitShrunk`, `TextFitFailed`, `TextFitDeferred`, `TextFitNoEffect`, `TextFitNoBudget` (cap), `TextFitMs`, `TextFitMsMax`; режим — `session.json → text_fit` (v2.9.9+). Строка C7.log: `[CPDDRuntimeFix] text fit mode=legacy early_nested=<on|off>` или `text fit mode=<cap|measure> prepass=<ok|missing|pending> early_nested=<on|off>`; при `pending` позже одна строка `text fit prepass=<ok|missing>` (может не попасть в C7.log до входа в аккаунт, LESSONS TASK-008; значение есть и в `session.json → api.ForceLayoutPrepass`).

### Флаг `EarlyNested` (TASK-011)
`EarlyNested = false` выключает ранний перевод вложенных компонентов (`EARLY_NESTED_REPAIR` в `Init.lua`). По умолчанию вложенный компонент (элемент списка, подвкладка), чей корень уже прошёл `Open`, переводится сразу после своего `Open` / `Refresh` — только собственное дерево, без `_childComponents`. Не трогаются Esc-меню, корни из `ClassHookedPanelUids` и `targetedPanelRepairUids`, Автошахматы. Проходы `delayed` и extended остаются страховкой. Метрики: `NestedEarlyRuns`, `NestedEarlyLabels`, `NestedEarlyMs`, `NestedEarlyMsMax`.

### Подсказки Автошахмат (TASK-016, v3.0.1)
При `VerboseLog = true` в C7.log:
- `autochess tip hint shrink widget=<имя> panel=<внешний Blueprint> owner=<ближайший Blueprint> size=<до>-><после>` — один раз за сессию, когда строка «Дважды щёлкните по портрету фигуры…» (id 056763, таблица `runtimeFixes.TextFit.HintSources` / `HintEnglish`) уменьшена вдвое (минимум 10 pt, перенос не меняется);
- `autochess piece skill fit need=<X>x<Y> have=<X>x<Y> scale=<s> wrapAt=<px|authored|missing>` — первые 5 подгонок `RichTextBlock_Detailed` в `AutoChess_Tips_PieceTips` (`Refresh` / `OnRefresh`): `scale=1.00` — текст помещается; `wrapAt=authored` — масштаб без смены переноса (замер после переноса не удался); `missing` — у RichText нет `SetWrapTextAt` (ещё строка `autochess piece skill fit api WrapTextAt=missing` и `session.json → api["RichText.SetWrapTextAt"] = false`).

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
| `Fonts` | Шрифт **до** нашей стилизации (первый снимок виджета в `translateTextWidget`) и **после**; в обходе панели — авторский шрифт виджетов, которые мы не трогали; виджеты, у которых кириллицу рисует `Font_Aleo` с typeface `Title` (раздел `title_cyrillic`, TASK-007); один раз после старта — структура `CompositeFont` у `Font_Aleo`, `Font_Mistery`, `Font_Aleo_Update`, `Roboto` (раздел `composite`, по одному шрифту за тик, только чтение); у SubTypeface — только число диапазонов (`FInt32Range` в slua непрозрачен) | `absru-s<n>-fonts.json` |
| `Images` | `Brush.ResourceObject` у виджетов с кистью в обходе панели | `absru-s<n>-images-NNN.jsonl` |
| `PanelWalk` | Обход дерева панели через 0,5 и 2,0 с после `UIComponent.Open`, не больше `PanelWalksPerUid` раз на uid | питает три строки выше |

**Корни обхода.** `WidgetTree.GetAllWidgets` в этой сборке недоступен (`GetAllWidgetsCalls = 0` за всю первую сессию), а у UserWidget нет `GetChildrenCount`, поэтому обход только от `component.userWidget` находил ~6 виджетов на панель. Обход стартует с тех же корней, что и `translateViewTextWidgets` в Init.lua: все значения `component.view` и `view._widgetCache` (рекурсивно по `_childComponents`), `userWidget.WidgetTree.RootWidget` (и у вложенных UserWidget при спуске), `runtimeFixes.VisibleWidgetNames` через `getNamedWidget`. Проба имён через `FindWidget` (`queueGeneratedWidgetProbe`) не повторяется: слишком дорого. Сколько корней дал каждый источник — `session.json → counters.roots_view / roots_cache / roots_tree / roots_named`; доступность — `api["WidgetTree.RootWidget"]`, `api["WidgetTree.GetAllWidgets"]`.

**Идентификаторы хуков:** `view:<Class>.<method>`, `data:…`, `exact:…`, `dlg:…`, `ac-class:<Class>.<method>`, `ac-method:<method>`, `ui:UIComponent.<method>`, `fix:<Class>.<method>`, `branch:<name>`, `panel:<uid>:<reason>` (reason: `Open`, `Refresh`, `delayed`, `extended-<delay>`, `manual`). Scope-записи TASK-011 (в `dead_hooks.md` не попадают, сводятся в `late.md`): `owner:<uid корня>/<__cname компонента>:<reason>` — компонент внутри прохода `delayed` / `extended-*` в `panelTextRepair:Repair`; `nested:<uid корня>/<__cname>:<Open|Refresh>` — ранний перевод вложенного компонента.

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
- Какой глиф выбрал Slate (fallback), из Lua не видно, в C7.log строк про fallback нет. Какие face входят в шрифт, показывает `composite`; их cmap сверяется офлайн (`reference/fonts/`, `reference/tools/FontScan.exe`, TASK-006).
- Удалять файлы Lua не умеет: старые части слота остаются, но `session.json → parts` перечисляет текущие, а у каждой строки есть `sid`; `CollectDiagLogs.ps1` фильтрует по `sid`.
- Повторы одной записи: строка JSONL пишется при первом появлении и затем при `count` = 2, 4, 8, … (и при росте переполнения больше чем на 2 px). Офлайн берётся максимум `count` по ключу.
- В диагностическом режиме обёртки вызывают исходную функцию через `pcall`: ошибка доходит до вызывающего с тем же сообщением, но без исходного стека.
- Счётчики `runtimeMetrics.GetAllWidgetsCalls`/`WidgetIndexesBuilt` не включают обходы диагностики (модуль восстанавливает их после своих вызовов).

## Файлы (`Saved/Mods/logs/`)
Все файлы — ASCII (валидный UTF-8 без BOM), LF. `sid` = `YYYYMMDD-HHMMSS`.

| Файл | Содержимое |
|---|---|
| `absru-state.txt` | номер последнего слота (`slot=`, `sid=`) |
| `absru-s<n>-session.json` | `sid`, `slot`, `version`, `text_fit` (режим подгонки, v2.9.9+), `started`, `last_flush`, `flags`, `dir`, `parts`, `lines`, `api` (какие API сработали: `GetParent`, `GetClass`, `Brush.ResourceObject`, `GetDesiredSize`, `GetCachedGeometry`, `IsVisible`, `GetPathName`, `UFont.CompositeFont`, `C7FunctionLibrary`; `C7FunctionLibrary.FlushFontCache` — Lua-тип поля, функция не вызывается; `culture.GetCurrentCulture` / `GetCurrentLanguage` / `GetCurrentLocale` — из `KismetInternationalizationLibrary`; `ForceLayoutPrepass` — есть ли метод у виджета, проба `Init.lua` в режимах `cap` и `measure`), `gauges` (от `bootstrap.lua`), `budget` (`ticks`, `tick_ms_max`, `max_item_ms`, `max_item_kind`, `io_ms_max`, `flush_ms_max`, `queue_peak`, `flushes`), `dropped`, `errors`, `counters`, `pending`, `metrics` (весь `runtimeMetrics`) |
| `absru-s<n>-hooks.json` | `afterload[]` (`id`, `module`, `applied`), `hooks[]` (`id`, `kind`, `status`, `module`, `declared`, `installed`, `calls`, `text_changes`, `text_writes`, `data_changes`, `errors`, `ms_total`, `ms_max`), `panels[]` (`id`, `runs`, `labels`, `widgets`, `ms_*`), `writes` (сайты `SetText` в Init.lua), `unscoped` |
| `absru-s<n>-untranslated-NNN.jsonl` | `{"src":"widget","text","norm","panel","widget","path","scope","vis","count"}`, `{"src":"data","module","class","field","original","translated"}`, `{"src":"stringdb","module","row","en","cn"}` |
| `absru-s<n>-overflow-NNN.jsonl` | `panel`, `widget`, `path`, `text`, `len`, `font`, `typeface`, `size`, `size_pre`, `cap` (потолок legacy в режиме `cap`, v2.9.9+), `ls`, `ls_pre`, `ls_negative`, `wrap`, `wrap_pre`, `need`, `need_pre`, `have`, `parent`, `parent_have`, `pexcess`, `parent_grew`, `kind` (`self`/`parent`/`both`), `count`. С v2.9.7: `need_pre` / `wrap_pre` — desired size и `AutoWrapText` исходного текста, снятые `Init.lua` перед первой нашей заменой (нет, если текст не заменялся); `pexcess` — на сколько текст выходит за родителя в локальных px (флаг `parent` — при `pexcess > 2`, раньше > 1 без величины; родитель `ScrollBox` не проверяется); `parent_grew` = `need.X > need_pre.X + 2` (текст стал шире, чем до перевода) |
| `absru-s<n>-fit-NNN.jsonl` | Подгонка (TASK-011, TASK-013): `kind` (`shrunk` / `fail` / `noeffect`), `mode` (`cap` / `measure`, v2.9.9+), `panel`, `widget`, `path`, `text`, `len`, `size_pre` (авторский), `cap` (размер legacy, только `cap`), `size`, `min`, `steps`, `slot` (`fixed` / `auto`), `axis` (`x`, у переноса `y`), `budget`, `need0` (при стартовом размере: авторском или `cap`), `need` (после), `need_pre`, `reason` (`min` / `steps` у `fail`), `scope`, `count` |
| `absru-s<n>-fonts.json` | `standard`, `cinematic`, `cyrillic_font` (`mode`, `requested`, `title_typeface`, `typefaces`, `title`, `title_sdf`, `title_sdf_headname`, `source`, `previous`, `write`, `via`, `verify`, `flush`, `reason`, `applied_at`), `composite` (`<путь>` → `loaded`, `error`, `default[]` и `fallback.fonts[]` (`name`, `face`, `loading`, `hinting`, `subface`), `fallback.scaling`, `subs[]` (`cultures`, `scaling`, `ranges` — число диапазонов (до v2.9.6 — массив), `fonts[]`)), `title_cyrillic[]` (до 500: `panel`, `widget`, `class`, `typeface`, `size`, `styled` (проходил через `translateTextWidget`), `rich` (RichText, шрифт из `DefaultTextStyleOverride` / `GetDefaultTextStyle`), `font_read`, `font_src`, `count`, `text` (≤ 60 символов), `path`), `fonts[]` (`key` = `путь|typeface`, `role` `pre`/`post`, `count`, `texts_cyrillic`, `texts_cjk`, `texts_latin`, `sizes`, `widgets`, `panels`) |
| `absru-s<n>-images-NNN.jsonl` | `panel`, `widget`, `resource`, `class`, `size`, `count` |

**Маркеры в C7.log** (`Log.Info`, строки `LuaLog: ReleaseLog:`): `[AbsruDiag] session=<sid> slot=<n> dir=<путь> version=… flags=…` (пишется при загрузке и повторяется в `after_main` отдельным хуком с приоритетом 1501, сразу после `active hooks_installed=`: до инициализации логгера игры строка теряется, а после хука `cpdd.runtime-fix.performance-mode` (2000000) `LuaLog` понижен до Warning, пока игра не поднимет уровень при входе в аккаунт; поэтому первые `flush #…` в C7.log не видны), `[AbsruDiag] flush #<k> parts=… queue=<n> tick_ms_max=<x> io_ms_max=<x> flush_ms=<x>`, `[AbsruDiag] disabled: <причина>`, `[AbsruDiag] error stage=<этап>: …` (первые 3 на этап), `[CPDDRuntimeFix] diagnostics unavailable: …` (модуль не запустился).

## Сбор и отчёты

```
powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1
```

Скрипт копирует **только из игры** (`C7.log` и `C7-backup-*.log` новее старта сессии, `Saved\Mods\logs\absru-*`, `Saved\Mods\absru-*`, `absoluteru_dev.lua`) в `reference\logs\<yyyy-MM-dd_HHmm>\` и строит `report\`: `REPORT.md` (сессии, бюджет, API, маркеры и ошибки из C7.log), `dead_hooks.md` + `hooks.csv`, `overflow_top.md` + `overflow.csv` (колонки `need_pre`, `pexcess`, `wrap_pre`; разделы «parent: текст шире, чем до перевода» и «parent: вынос как в оригинале»), `fit.md` + `fit.csv` (метрики подгонки по сессиям с режимом и `NoBudget`, число переполнений против v2.9.6 (251) и v2.9.7 (1018) — та же строка в выводе скрипта, «Уменьшено ниже v2.9.6 (cap)», «не помещается даже на минимуме» — список строк на сокращение для TASK-012, `noeffect`, подогнанные, RichText с переполнением), `late.md` (отложенные проходы по панелям, `owner:` против `nested:` по классам компонентов), `untranslated.md` + `untranslated.csv` (сверка с батчами: «перевод есть, не применился» / «не переведено в батче» / «нет в батчах»), `fonts.md` (`composite` с числом диапазонов и культурами SubTypeface, «Title с кириллицей» по группам `styled`/`rich`, `pre`/`post`), `textures.md` + `textures.csv`. В `REPORT.md → C7.log` выводятся строки `active hooks_installed=`, `cyrillic font mode=`, `text fit mode=`, `text fit prepass=` и `menu button without short label`. В папку игры скрипт ничего не пишет.

Параметры: `-GameDir <…\C7>` (по умолчанию `D:\Games\GMZZLauncher\Game\C7`), `-Out <папка>`, `-Session latest|all|<sid>` (по умолчанию последняя), `-Aggregate` (все папки `reference\logs\*`; хук мёртвый, только если мёртв во всех сессиях), `-NoCopy` (только отчёты по уже скопированному), `-LogsRoot`.

## Выгрузка ассетов: AssetExport (TASK-018)

Модуль `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/AbsruAssetExport.lua` (только для разработки) выгружает вкладку «Божий путь» из памяти игры, без AES-ключа: текстура рисуется Canvas в render target, а `KismetRenderingLibrary.ExportRenderTarget` сохраняет её в PNG. `Init.lua` загружает модуль только при непустой таблице `AssetExport` в `absoluteru_dev.lua` и запущенной `AbsruDiagnostics`: модуль берёт у неё JSON (`D.EncodeJson`, `D.JsonArray`) и обход панели (`D.NewPanelWalk`, визитор получает `widget, parent`). Вызывается из хука `UIComponent.Open` рядом с `Diag.OnPanelOpen`. Модуль реагирует только на корневой компонент, у которого `userWidget` называется как uid, а не на дочерний `WBP_ComBackTitle`. План, пробы и выводы: [tasks/TASK-018-godway-export.md](tasks/TASK-018-godway-export.md).

```lua
AssetExport = { Panels = { "GodWay_Panel" }, Probe = false },
```

| Поле | Значение |
|---|---|
| `Panels` | uid панелей |
| `Probe` | `true` — проба шага 0 (`probe.json`); `"retainer"` — проба 4, RetainerBox (`probe_retainer.json`); `false` или нет — полная выгрузка |
| `Calib` | `false` — полная выгрузка без эталонных кадров RetainerBox (по умолчанию `true`) |
| `FrameBudgetMs` / `TimelineBudgetMs` / `SnapshotBudgetMs` | 4 / 4 / 12 мс за тик: обход и материалы / дорожка / снимок раскладки. Экспорт PNG в бюджет не входит (одна операция за тик) |
| `MaxFiles` / `MaxMB` | потолок всей выгрузки, по умолчанию 3000 PNG / 600 МБ |

**Правила slua, подтверждённые пробами.** Out-параметры передаются аргументами и обязательно **экземплярами** структур: `FVector2D(0,0)`, `DrawToRenderTargetContext()`. `nil` или сам тип структуры не подходят. Рабочий конвейер: `CreateRenderTarget2D` → `ClearRenderTarget2D` → `BeginDrawCanvasToRenderTarget(ctx, rt, nil, FVector2D(0,0), DrawToRenderTargetContext())` → `Canvas:K2_DrawTexture(…, BLEND_Opaque)` (прямая альфа, RGB прозрачных пикселей сохраняется) → `EndDrawCanvasToRenderTarget` → `ExportRenderTarget` → `ReleaseRenderTarget2D`. `ExportTexture2D` даёт файл 0 байт. `DrawMaterialToRenderTarget` не рисует материалы домена UI (кадр 0,0,0,0), поэтому анимацию снимает RetainerBox.

### Режимы
- **`Probe = true` (шаг 0).** Через 3 с после открытия, по одной стадии за тик: `api`, `context`, `rt_clear`, `find`, `texture_canvas`, `sprite`, `mid_params`, `mid_draw`, `mid_draw_2`, `engine_material`, `texture_direct`. Строка `[AbsruExport] probe …`.
- **`Probe = "retainer"` (проба 4, шаг 3.0).** Через 3 с после открытия выполняются стадии `api`, `context`, `find` (иконка `UI_GodWay_Icon_Class*`, MID `Img_Bg01`, MID `liudong04` у `Img_Lev3Bg02`), затем:
  - `cvar`: `KismetSystemLibrary.GetConsoleVariableIntValue("Slate.EnableRetainedRendering")`;
  - `create`: `RetainerBox` и `Image` создаются через `WidgetTree:ConstructWidget` → `ObjectActorManager:KGNewObject` → `NewObject` и кладутся в корневую `CanvasPanel` (`AddChildToCanvas`, `ZOrder` −1000, позиция 0,0);
  - `setup`: effect-материал — MID от `/Engine/EngineMaterials/Widget3DPassThrough`, `SetTextureParameter("SlateUI")`, `SetRetainRendering(true)` (или поле `bRetainRender`), `SetRenderingPhase(0, 1)`. В JSON попадает список методов и полей RetainerBox;
  - `icon`: RT берётся как `GetEffectMaterial():K2_GetTextureParameterValue("SlateUI")`. Texture2D в этом параметре означает значение по умолчанию: retainer ещё не рисовал, тогда ожидание до 20 тиков. RT выгружается напрямую, а также копиями Canvas Opaque в `RTF_RGBA8_SRGB` и `RTF_RGBA8`. Эталоном служит сама иконка через Canvas. Сравнение сетки 6×6 даёт `copy=srgb|linear` (какая копия совпала с прямым экспортом) и `alpha=straight|premultiplied|unknown`;
  - `mid`: `Img_Bg01` в 1024×1012, два кадра с интервалом 0,5 с, `animated`, `copy_ms`, `export_ms`, прямой экспорт первого кадра;
  - `mid_small`: то же для `liudong04` в размере `ImageSize` (≤ 1024);
  - `cleanup`.
- **`Probe = false` (полная выгрузка, шаги 1–3).** Описана ниже.

### Полная выгрузка: порядок
- **0 с (Open корня).** Обход `open`: виджеты для дорожки, ресурсы кистей, MID с MI `*_Animated`. Открывается окно дорожки на 10 с. Сразу стартуют серия `calib/<MI>_open/` для каждого `_Animated` (кадр каждый тик до 2 с от открытия, не больше 40) и контрольная иконка `calib/_control/`.
- **3 с.** Обход `full`, затем снимок раскладки `layout_001.json`. Начинается экспорт текстур: не раньше чем через 2 с после `SetForceMipLevelsToBeResident(30, 0)`, одна операция за тик, кадры calib раньше текстур. Идут регулярные серии calib, по 2 одновременно: одна серия на пару «MI родитель MID + размер кисти», моменты 0, 1, 2, 3 тика, затем +0,25 / 0,5 / 1 / 2 / 4 с, копии в пул RT (≤ 256 МБ), экспорт после серии.
- **Смена пути.** Раз в 1 с строится подпись из Lua-полей компонента панели (имена с `select`, `index`, `cur`, `way`, `path`, `tab`, `page`, `id`), кистей иконок `Icon_Class` и первых 30 текстов. Ключи, которые меняются сами в первые 15 с, и ключи, появившиеся позже, не учитываются. Подпись изменилась → окно дорожки на 5 с, обход `path`, через 2 с снимок с новым `path_index`. К уже виденной подписи возвращается её прежний индекс.
- **Конец.** 30 с без работы → `done reason=idle` (при новой смене пути выгрузка продолжится, и позже будет ещё одна строка `done`). Закрытие панели → `done reason=panel closed`; незаконченное помечается `skipped: panel closed`: контекст мира — `userWidget` панели, без него рисовать нельзя. Повторное открытие панели продолжает ту же выгрузку.
- Свои RetainerBox и Image в обход и раскладку не попадают. Если первый экспорт не создал подпапку, имена становятся плоскими (`textures+x.png`, `export_state.json → flat`), и `GodWayExport.ps1` восстанавливает папки.

### Файлы (`Saved/Mods/logs/godway/`; запасной вариант — `Saved/Mods/logs/godway-*`)

| Файл | Содержимое |
|---|---|
| `export_state.json` | `status`, `api`, `context` (`viewport`, `viewport_scale`), `walks[]`, `paths[]` (`t`, `path_index`, `key`), `component_fields` (скалярные поля Lua-компонента панели), `local_to_viewport` (какая сигнатура сработала), `calib` (`available`, `alpha`, `copy_format`, `series[]`), `files`, `mb`, `limited`, `queue`, `errors` |
| `textures.json`, `textures/*.png` | `textures[]`: `path`, `name`, `file`, `file_linear`, `w`, `h`, `SRGB`, `CompressionSettings`, `AddressX`, `AddressY`, `Filter`, `LODGroup`, `rt_format`, `streamed` (`true` / `false` / `"unknown"`), `force_mips`, `source` (`brush`, `material`, `material_streaming`, `material_cached`), `status`, `error`; `unknown_resources[]` — прочие классы кистей и параметров без выгрузки. Формат RT выбирается по `SRGB`: `true` → `RTF_RGBA8_SRGB`, `false` → `RTF_RGBA8`; если флаг не прочитался, выгружаются оба варианта (`<имя>.srgb.png`, `<имя>.linear.png`) |
| `sprites.json`, `atlases/*.png` | `atlases[]` (поля текстуры атласа, `AtlasWidth`, `AtlasHeight`, `AtlasFilter`, `BatchAtlasIndex`, `count`); `sprites[]` — **все** записи `KGSpriteAtlas.Sprites`: `sprite`, `atlas`, `x`, `y`, `w`, `h` в пикселях атласа; `sprite_assets` — путь KGSprite → `atlas`, `sprite` |
| `materials.json` | `materials{путь}`: `class`, `chain[]` (MID → MIC → … → Material: `path`, `class`, `scalar[]`, `vector[]`, `texture[]`), `parent`, `mi`, `base`, `effective` (`K2_Get*ParameterValue` по объединению имён всех MI той же базы, включая имена из `CachedExpressionData`), `widgets`; `bases{Material}`: `instances[]`, `mids`, `widgets`; `base_materials{Material}`: `props` (`BlendMode`, `MaterialDomain`, `TwoSided`, …), `fields` (`__pairs`, верхний уровень), `texture_streaming[]`, `cached` / `referenced_textures` / `parameter_names` / `ScalarValues` / `VectorValues` / `TextureValues` (если читаются); `names{Material}`: объединённые имена. Все текстуры-параметры выгружаются в `textures/` |
| `layout.json`, `layout_NNN.json` | Индекс снимков и сами снимки: `t`, `path_index`, `path_key`, `viewport`, `viewport_scale`, `root` (геометрия панели), `widgets[]`: `id`, `name`, `class`, `parent` (узел обхода), `panel` / `index` (`GetParent`, `GetChildIndex`), `slot` (`position`, `size`, `anchors`, `alignment`, `autosize`, `zorder`, `padding`, `halign`, `valign`, `size_rule`), `geom` (`abs`, `abs_size`, `local_size`, `px`, `px_end`, `vp` — пиксели вьюпорта через `LocalToViewport`), `opacity`, `transform`, `pivot`, `visibility`, `clipping`, `color`, `brush` (`draw_as`, `tiling`, `mirroring`, `margin`, `tint`, `image_size`, `uv_region`, `resource` = `{kind: texture|sprite|material|unknown, path, atlas, sprite}`), `text` (`text`, `font`, `color`, `justification`). В снимок попадают только виджеты последнего обхода |
| `timeline.json` | `windows[]`, `rates` (`samples_per_s`, `sweeps_per_s`, `tracks`, `active`), `animations[]` (`WidgetAnimation` в полях UserWidget: `owner`, `name`, `start`, `end`), `events[]` = `{t, rt, o, k, id, p, v}`: `t` — мс от открытия, `rt` — `GameplayStatics.GetRealTimeSeconds`, `o` — номер открытия, `k` = `w` (виджет, `id` из раскладки; `p` = `opacity`, `transform`, `visibility`, `color`, `tint`) или `m` (MID, `id` = путь; `p` = `s:<имя>` / `v:<имя>`). Пишутся первое значение и изменения. Треки, которые уже менялись, опрашиваются каждый тик, остальные — по кругу |
| `calib/<MI>[_open]/NNN.png`, `frames.json` | `kind` (`regular`, `open`, `control`), `mi`, `mid`, `size`, `image_size`, `scale` (фон — 0,5), `rt` (класс, размер, формат RT retainer), `copy_format`, `alpha`, `status`, `frames[]` (`file`, `t`, `rt_s`, `params` — действующие scalar/vector MID, `export`). `_control/`: `000.png` (копия sRGB), `001.png` (копия linear), `icon_direct.png`, в `control` — сравнение с эталоном |

**Потолок.** Считается по несжатому RGBA (w × h × 4, PNG на диске меньше). Кадры calib занимают не больше 75 % потолка: дальше `limit part=calib`, и выгрузка идёт без них. На 100 % — `limit part=all`: экспорт PNG останавливается, JSON дописываются.

### Строки C7.log
- `[AbsruExport] ready dir=<папка> mode=probe|retainer|full panels=…`
- `[AbsruExport] probe api=… file=… canvas=… engine=… sprite=… mid_draw=… animated=… ctx=… json=…`
- `[AbsruExport] retainer cvar=<0|1> create=<путь|fail> rt=<класс WxH fmt=…|nil> icon=<ok|black|fail> copy=<srgb|linear> alpha=<straight|premultiplied|unknown> mid=<ok|black|fail> animated=<yes|no> small=<…>/<yes|no> export_ms=<n> copy_ms=<n> json=…`
- `[AbsruExport] full open=<n> panel=… calib=<true|false> budget_ms=…`
- `[AbsruExport] snapshot index=<n> path=<path_index> widgets=<n> ms=<n> scanned=<n>`: снимок записан, можно листать дальше
- `[AbsruExport] limit part=<calib|all> files=… mb=… max_files=… max_mb=…`
- `[AbsruExport] done files=<n> mb=<m> textures=<n> sprites=<n> materials=<n> calib=<n> timeline=<событий> snapshots=<n> paths=<n> reason=<idle|panel closed|…> limit=<yes|no> json=…`
- `[AbsruExport] error stage=<этап>: …` (первые 3 на этап; после 200 ошибок — `[AbsruExport] disabled: …`); `[CPDDRuntimeFix] asset export unavailable: …` — модуль не запустился.

### Сбор
```
powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1 -ProbeOnly   # пробы: raw/<дата>/probe_summary.md
powershell -ExecutionPolicy Bypass -File tools\GodWayExport.ps1              # полная выгрузка
```
Из игры скрипт только читает: `logs/godway/**` (или `godway-*`), строки `[AbsruExport]` из C7.log, `absoluteru_dev.lua`. Всё копируется в `reference/godway_export/raw/<yyyy-MM-dd_HHmm>/`. Затем скрипт собирает `reference/godway_export/`: `textures/`, `atlases/`, `calib/`, `textures/sprites/*.png` (нарезка по `sprites.json` через `LockBits` `Format32bppArgb`, построчное копирование байтов без премультипликации и сглаживания), проверку PNG (сигнатура, размер ≠ 0, совпадение с `textures.json` / `sprites.json` / `frames.json`), `layout.json` (индекс со всеми снимками), копии JSON, `manifest.json` (путь, вид, байты, sha256, размер PNG) и `summary.md` (файлы по типам, базовые материалы, `streamed != true`, непрочитанный `SRGB`, calib, строки done/limit/error, проблемы). Производные папки и файлы пересобираются целиком, `raw/` и `demo/` не трогаются. `-FromRaw <папка raw>` собирает выгрузку заново без игры, `-GameDir` и `-Out` — как у `CollectDiagLogs.ps1`.

## Чек-лист проверки в игре
1. Установить сборку v2.9.9-RU (`build\Lord-of-Mysteries-Russian-Patch.exe`: он возьмёт `patch_payload` из репозитория).
2. **Сначала без флагов:** запустить игру, пройти пару экранов. В `Saved\Logs\C7.log` должна быть строка `v2.9.9-RU active hooks_installed=` и **не должно быть** `[AbsruDiag]`; строк `[CPDDRuntimeFix]`, кроме этой, `cyrillic font mode=…`, `text fit mode=…` (и, возможно, `text fit prepass=…`) и ошибок, быть не должно. Папка `Saved\Mods\logs\` не появилась. Субъективно подвисаний не больше, чем на v2.9.0.
3. Скопировать шаблон флагов (выше) в `…\C7\Saved\Mods\lua\absoluteru_dev.lua`.
4. Запустить игру. В C7.log найти `[AbsruDiag] session=… dir=…`; если там `disabled:` или есть `[CPDDRuntimeFix] diagnostics unavailable`, прислать эти строки. **При включённых флагах в C7.log видны строки `[CPDDRuntimeFix]` от `reportVerbose`** (например, `installed post-refresh widget repair for …`, `registered v2.9.9-RU`, `text fit shrunk|fail|noeffect size … budget=… text=…`, `menu button without short label enum=… text=…` — кнопка Esc-меню без короткой подписи, её `ButtonEnum` добавляется в `shortMenuLabels`).
5. Пройти экраны (на каждом 3–5 с; списки прокрутить; вкладки переключить): логин и выбор сервера → главный HUD → Esc-меню (все пункты) → сумка + подсказка предмета → снаряжение (перековка/наследование) → навыки и таланты → детали персонажа (обе вкладки характеристик) → задания (доска, список) → диалог с NPC (с выбором ответа) → магазин и биржа (лоты, аукцион) → гильдия (участники, права, события) → стиль/гардероб → настройки (графика) → статистика/DPS → Автошахматы: главное меню, энциклопедия (таланты, снаряжение, фигуры, поиск), матч (HUD, карточки, итоги) → печати/слияние → активности.
6. Постоять 30–40 с на любом экране (сброс на диск раз в 30 с), затем закрыть игру. В C7.log должны быть строки `[AbsruDiag] flush #…` с `tick_ms_max` не больше ~3.
7. В репозитории: `powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1`. Открыть `reference\logs\<дата>\report\REPORT.md`.
8. Чтобы выключить диагностику, удалить `Saved\Mods\lua\absoluteru_dev.lua`. Папку `Saved\Mods\logs\` можно удалить вручную.

**Маршрут проверки подгонки текста (TASK-011, v2.9.7):** магазин (карточки товаров, «В неделю 0/70», 2–3 вкладки и прокрутка) → задания (главы, вкладки «Основной квест» / «Побочный квест», описание) → подземелья («Предпросмотр наград») → HUD (подписи кнопок, навыков, счётчики) → Путь Бога, Сумка, Активности, Боевой пропуск, Спутники (текст при открытии — сразу русский) → логин и выбор сервера → Автошахматы (синергии матча, энциклопедия) → Esc-меню (без изменений). Если экран хуже, чем в v2.9.6, — `TextFit = "legacy"` и/или `EarlyNested = false`, тот же экран ещё раз. С v2.9.8 `legacy` — режим по умолчанию; проверка режима `cap` — [tasks/TASK-013-text-fit-cap.md](tasks/TASK-013-text-fit-cap.md), раздел «Проверка». Смотреть `fit.md`, `late.md`, `overflow_top.md`, `REPORT.md`. Полный чек-лист — [tasks/TASK-011-text-fit.md](tasks/TASK-011-text-fit.md), раздел «Проверка».

**Выяснится по первой сессии:** создаёт ли `SaveStringContentToFile` папку `logs/` (если нет — файлы в `Saved\Mods\` с тем же префиксом `absru-`, видно по `dir=` в маркере), какие API доступны (`session.json → api`), реальная цена тика (`budget.tick_ms_max`).
