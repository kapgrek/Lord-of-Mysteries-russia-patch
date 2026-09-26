# TASK-018: Выгрузка вкладки «Божий путь» (GodWay) для Electron-приложения, без AES-ключа

Дорожная карта: [ROADMAP.md](ROADMAP.md). Данные: `reference/logs/2026-09-26_1435/` (сессия с открытой вкладкой, `report/textures.csv`), скриншот пользователя 2026-09-26.

Статус: **анализ завершён 2026-09-26**. Шаг 0 реализован 2026-09-26 и ждёт пробы в игре. Шаги 1–5 начинать только после результатов пробы.

## Ход исполнения
- **Шаг 0 (2026-09-26).** `AbsruAssetExport.lua`: грузится из `Init.lua` в блоке `if Loader.DevFlags` только при непустой таблице `DevFlags.AssetExport` и запущенной `AbsruDiagnostics`; `OnPanelOpen` вызывается рядом с `Diag.OnPanelOpen` в хуке `UIComponent.Open`. Обход панели — через новую `D.NewPanelWalk` в `AbsruDiagnostics.lua` (те же корни и дети, что у обхода диагностики). Проба запускается через 3 с после открытия панели из `Panels`, одна стадия за тик таймера: `api`, `context`, `find`, `texture_canvas` (Canvas `K2_DrawTexture` в режимах Opaque и Translucent → `ExportRenderTarget`), `sprite`, `mid_params`, `mid_draw`, `mid_draw_2` (второй кадр через 1 с, чтобы понять, анимирован ли материал по времени), `texture_direct`. `ExportTexture2D` стоит последним: он читает CPU-мипы, которых у cooked-текстуры может не быть. `probe.json` перезаписывается до и после каждой стадии, так что при падении видно, на какой стадии оно произошло. Итоговая строка в C7.log: `[AbsruExport] probe api=… file=… sprite=… mid_draw=… animated=… ctx=… json=…`.
- `tools/GodWayExport.ps1 -ProbeOnly` копирует `Saved/Mods/logs/godway/**` (или запасной `logs/godway-*`), строки `[AbsruExport]` из C7.log и флаги в `reference/godway_export/raw/<дата>/` и пишет там `probe_summary.md` (формат и размеры PNG по заголовку). Без `-ProbeOnly` скрипт пока останавливается с сообщением. Проверен на `temp/fake_game`, мок-прогон модуля — на Lua 5.4 (`temp/luacheck/LuaRun.exe`).

## Цель
Воспроизвести в стороннем Electron-приложении (JS) вкладку «Божий путь» один в один, **с живой анимацией**. Результат складывается в `reference/godway_export/` (не в git, не очищается), оттуда пользователь заберёт его сам.

Решение пользователя: **без AES-ключа.** Контейнеры `.ucas` зашифрованы, ключ зашит в exe (`TASK-006-font.md:53`). Ключ не извлекаем и FModel/CUE4Parse не используем. Всё берём **из памяти игры**: движок сам расшифровывает ассеты, а мы рисуем их в render target и сохраняем в PNG.

## Что есть на вкладке (факты из `reference/logs/2026-09-26_1435/report/textures.csv`)
Панель `GodWay_Panel`, элементы деревьев `WBP_GodWay_Item`: 332 записи, из них 41 статичный ресурс и 291 динамический материал (MID).

| Слой | Ресурсы | Тип |
|---|---|---|
| Иконки путей | `/Game/Arts/UI_2/Resource/ConfigIcon/GodWay/UI_GodWay_Icon_Class1,3,5,6,11` (видно 5, всего путей больше) | Texture2D 176×176 |
| Силуэты деревьев и подсветка | `GodWay/NotAtlas/UI_GodWay_Img_Bottom`, `Bottom1…5`, `Img_Glowing1`, `Img_Hover1/2` | Texture2D до 952×1396 |
| Подложки, завитки, линии | атлас `GodWay/Atlas/Sprites_Atlas_GodWay/*`: `TextBg1/2/3/5`, `Dec1/2`, `Bottom8…11`, `Glowing2/3` | KGSprite (область атласа) |
| Общие элементы | `Common_2/Atlas/Sprites/UI_Com_Icon_Arrow01/02`, `UI_Com_Icon_Info`, `UI_Com_Img_Hover07`, `Common_2/NotAtlas/Button/UI_Com_Icon_ArrowBg02` | KGSprite / Texture2D |
| **Фон** | `Img_Bg01` → `MID_MI_UI_WBP_GodWay_Way_Item_liudong09` | MID 2048×2024 |
| «Пульс» по веткам | `liudong01/02/03/04/05/06/07/11/12` (`vx_HighLine_liudong`, `Img_Lev3Bg02/03`, `vx_*_liudong*`, `vx_UnlockedBg02_saoguang`, `vx_3dmesh`) | MIC / MID |
| Проявление деревьев | `dis01/02/03_Animated` (`Img_SelectedBg02/03/08`) | MI `_Animated` |
| Дым, туман, свечение | `smoke01/02/03`, `vx_liuti`, `vx_liuti8`, `Common_Material_glow_add`, `glow_huxi10` | MIC / MI `_Animated` |

Выводы:
- Около 40 картинок выгружаются как обычные текстуры. KGSprite — это область атласа, поэтому выгружаем атлас целиком вместе с UV-прямоугольниками и режем офлайн.
- **Фон, пульс, дым и проявление — это шейдеры, а не картинки.** Суффикс `_Animated` означает, что параметры материала крутит UMG-анимация виджета. Значит, одного захвата материала по игровому времени мало, нужна ещё **дорожка параметров** (scalar/vector) по времени.
- Раскладки (позиции, размеры, слои) диагностика сейчас не пишет: `noteImage` (`AbsruDiagnostics.lua:1498-1521`) сохраняет только `resource`, `class` и `ImageSize`.

## Точки опоры в коде
- Dev-флаги: `Init.lua:3-11` читает `Saved/Mods/lua/absoluteru_dev.lua` в `Loader.DevFlags`. Модуль диагностики подключается в `Init.lua:1420-1423`.
- Открытие панели: `D.OnPanelOpen(component)` (`AbsruDiagnostics.lua:1664`), отложенные обходы через 0,5 и 2 с, корни обхода описаны в `docs/DIAGNOSTICS.md:119`.
- Кисть виджета: `widget.Brush` → `ResourceObject`, `ImageSize` (`AbsruDiagnostics.lua:1498-1545`).
- Таймер тиков: `Game.NewUIManager:AddTimerWithFunction` (`AbsruDiagnostics.lua:2146`), бюджет кадра `FrameBudgetMs`.
- Импорт движковых библиотек из Lua работает: `KismetInputLibrary`, `WidgetLayoutLibrary`, `SlateBlueprintLibrary` (`DesktopChat.lua:493-597`). `KismetRenderingLibrary` в проекте ещё не использовался, **его доступность не проверена**.
- Запись текста: `LuaFunctionLibrary.SaveStringContentToFile` в `Loader.Root .. "logs/"` (`AbsruDiagnostics.lua:2374-2398`).

## План

### Шаг 0. Проба API (отдельная короткая сессия, обязательна до шага 1)
Новый модуль `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/AbsruAssetExport.lua`. Грузится из того же места, что `AbsruDiagnostics` (`Init.lua:1420+`), **только если** `DevFlags.AssetExport` — непустая таблица. Без флага модуль не загружается, в обычном режиме ничего не меняется. Флаг в `absoluteru_dev.lua`:
```lua
AssetExport = { Panels = { "GodWay_Panel" }, Probe = true },
```
При `Probe = true` один раз после открытия панели выполнить через `pcall` и записать в `logs/godway/probe.json`:
1. `import("KismetRenderingLibrary")`: наличие `CreateRenderTarget2D`, `DrawMaterialToRenderTarget`, `BeginDrawCanvasToRenderTarget`/`EndDrawCanvasToRenderTarget`, `ExportRenderTarget`, `ExportTexture2D`, `ReadRenderTargetPixel`.
2. Источник world context: `component.userWidget` / `GetWorld()` / `Game.*`.
3. Экспорт одной иконки `UI_GodWay_Icon_Class*` двумя способами: `ExportTexture2D` напрямую и через RT + Canvas `K2_DrawTexture` + `ExportRenderTarget`. Записать, куда лёг файл (относительный путь от `Loader.Root` или абсолютный), и его размер.
4. У одного KGSprite (`UI_GodWay_Img_TextBg1_Sprite`) перечислить поля (атлас/`BakedSourceTexture`, `SourceUV`, `SourceDimension` или аналоги, `pairs` по метатаблице / `GetClass():GetName()`).
5. У одного MID (`Img_Bg01`) — список параметров: `TextureParameterValues`, `ScalarParameterValues`, `VectorParameterValues` (имя, значение), `Parent`, и `DrawMaterialToRenderTarget` одного кадра в RT 512×512 → PNG. Проверить, что материал домена UI рисуется (не чёрный/пустой кадр: сверить по `ReadRenderTargetPixel` в нескольких точках).
6. В `C7.log` одна строка: `[AbsruExport] probe api=<список ok/missing> file=<путь> sprite=<поля> mid_draw=<ok|black|fail>`.

Пользователь запускает, открывает «Божий путь», ждёт 20 с, выходит. Логи забрать (шаг 4). **Если `ExportRenderTarget` и `ExportTexture2D` недоступны, остановиться** и вернуться в чат анализа: запасной путь — `ReadRenderTargetPixel` в Lua с кодированием PNG через `SaveStringContentToFile`, но он медленный и под вопросом из-за записи бинарных данных строкой.

### Шаг 1. Статичные текстуры и атласы
После пробы (флаг `Probe = false`), по открытию панели из `Panels`:
- Обойти дерево виджетов теми же корнями, что `D.OnPanelOpen`/обход панели (переиспользовать функции диагностики: вынести в `D.WalkPanel(component, visitor)` или передавать через `D.Attach`, не копировать).
- Для каждого `ResourceObject`, дедупликация по пути:
  - `Texture2D` → `textures/<имя>.png` в собственном разрешении текстуры (`Blueprint_GetSizeX/Y` или `GetSurfaceWidth/Height`, а не `ImageSize` кисти);
  - `KGSprite` → атлас один раз в `atlases/<имя атласа>.png`, прямоугольник спрайта — в `sprites.json` (`name`, `atlas`, `x`, `y`, `w`, `h`, плюс поворот/обрезка, если есть такие поля);
  - `MaterialInstance*` → параметры в `materials.json`, все текстуры-параметры выгрузить как `Texture2D` (маски, шум, градиенты).
- Перелистывание путей: панель остаётся открытой, пользователь нажимает «›» по всем путям. Новые ресурсы подхватываются повторным обходом на `Refresh`/смене выбранного пути (хук тот же, что у диагностики, лимит `PanelWalksPerUid` для этой панели снять).
- Текстуры в sRGB рисовать без изменения гаммы (RT `RTF_RGBA8_SRGB`, если есть; иначе `RTF_RGBA8`, и записать в `probe.json`, какой формат использован). Альфу сохранять.

### Шаг 2. Раскладка → `layout.json`
Для каждого виджета `GodWay_Panel` и каждого экземпляра `WBP_GodWay_Item`:
`name`, `class`, `parent`, `z` (порядок в родителе + `ZOrder` слота), геометрия на экране (`SlateBlueprintLibrary.LocalToViewport` / `GetAbsolutePosition` + `GetLocalSize` от `GetCachedGeometry`, в пикселях вьюпорта), слот (`CanvasPanelSlot`: `GetPosition`, `GetSize`, `GetAnchors`, `GetAlignment`, `GetAutoSize`), `RenderOpacity`, `RenderTransform` (translation, scale, shear, angle) и `RenderTransformPivot`, `Visibility`, `ColorAndOpacity`. Для кисти: `DrawAs`, `Tiling`, `Margin` (9-slice), `TintColor`, `ImageSize`, ссылка на ресурс. Для текстов: текст, шрифт, размер, цвет, выравнивание. Отдельно размер вьюпорта и DPI-масштаб (`WidgetLayoutLibrary.GetViewportSize` / `GetViewportScale`). Снимок делать после завершения анимации открытия (через 3 с после открытия) и повторять при смене пути.

Виджеты вне `GodWay_Panel` (например, строка `ID:…` внизу экрана) не записывать.

### Шаг 3. Анимация
Два вида данных, обе дорожки по одним тикам с отметкой времени `t` (мс от открытия панели):
1. **Дорожка параметров** `timeline.json`: для всех виджетов панели — `RenderOpacity`, `RenderTransform`, `Visibility`, `ColorAndOpacity`, и для каждого MID/`_Animated` MI — значения всех scalar/vector-параметров. Писать только изменения (дельты). Длительность — от открытия панели 8 с (анимация появления), затем при смене пути ещё по 4 с. Плюс список UMG-анимаций виджета (`WidgetAnimation` по полям userWidget: имя, `GetEndTime`), если читаются.
2. **Кадры материалов** `anim/<материал>/<nnnn>.png`: для каждого уникального родительского материала (liudong01…12, dis01…03, smoke01…03, vx_liuti, vx_liuti8, glow_add, glow_huxi10, liudong09-фон) — `DrawMaterialToRenderTarget` этого MID/MI с его текущими параметрами, 24 кадра/с на 4 с (петля), по одному материалу за раз, чтобы не просаживать кадр. Размер RT = `ImageSize` кисти; фон 2048×2024 — 12 кадров/с, до 1024 по длинной стороне, в `probe.json`/`manifest` записать масштаб. `frames.json` по каждому: `fps`, `count`, `size`, `t` первого и последнего кадра, `loop` (совпадает ли последний кадр с первым по `ReadRenderTargetPixel` в 16 точках).
   - Для `_Animated`-материалов, чьи параметры меняет UMG-анимация, кадры снимать **во время** анимации появления: они и есть анимация. Плюс отдельная петля при статичных параметрах, если материал анимирован ещё и по времени.
- Бюджет: не больше одной операции `Export*` за тик, остальное в очередь, как в `D.Tick`. Общий потолок — 3000 файлов и 600 МБ; при превышении остановиться с `[AbsruExport] limit ...`.

### Шаг 4. Сбор и сборка результата
Новый скрипт `tools/GodWayExport.ps1` (UTF-8 с BOM):
1. Копирует **из игры** (только чтение) `Saved/Mods/logs/godway/**` в `reference/godway_export/raw/<yyyy-MM-dd_HHmm>/`. В папку игры ничего не пишет.
2. Режет спрайты из атласов по `sprites.json` → `reference/godway_export/textures/sprites/*.png` (System.Drawing).
3. Кадры материалов → спрайт-листы `anim/<материал>.png` + `anim/<материал>.json` (сетка, fps, размер кадра); большие (фон) остаются последовательностью PNG. WebM с альфой — только если у пользователя есть `ffmpeg` (путь параметром), **скачивать ffmpeg без разрешения пользователя нельзя**.
4. Собирает `reference/godway_export/manifest.json` (все ассеты, размеры, sha256) и копирует `layout.json`, `timeline.json`, `materials.json`.
5. Генерирует демо `reference/godway_export/demo/index.html` + `godway.js` + `godway.css` (чистый JS, без сборщика, работает в Electron через `file://`): абсолютная раскладка 1920×1080 с масштабированием под окно, слои по `z`, кисти `Box` через `border-image` по `Margin`, текстуры и спрайты как `<img>`/canvas, анимации — проигрывание спрайт-листов в canvas по `fps` и применение `timeline.json` (opacity/transform) через `requestAnimationFrame`. Переключение путей стрелками, как в игре.
6. `reference/godway_export/README.md`: структура папки, как подключить в Electron, что и откуда снято, известные отличия.

### Шаг 5. Документы
- `docs/DIAGNOSTICS.md`: раздел «AssetExport» (флаг, файлы, строки в C7.log, бюджет).
- `docs/PROJECT_MAP.md`: строки для `AbsruAssetExport.lua` и `tools/GodWayExport.ps1`.
- `ROADMAP.md`: строка TASK-018. Версию патча **не поднимать** и релиз не собирать: модуль dev-only, для пользователей ничего не меняется. Но `VerifyPatch.ps1` должен проходить (новый файл в payload).

## Ограничения
- Lua — UTF-8 без BOM, LF. Новых локальных переменных верхнего уровня в `Init.lua` не добавлять (VerifyPatch), подключение модуля — внутри существующего блока `if Loader.DevFlags`.
- Все вызовы движка через `pcall`. Ошибки → `[AbsruExport] error stage=<этап>: …` (первые 3 на этап), после 200 ошибок модуль отключается.
- Нет `io.open`, нет путей разработчика: запись только в `Loader.Root .. "logs/godway/"` (или то, что покажет проба для `ExportRenderTarget`).
- Всё, что получено, — ассеты NetEase. Кладутся только в `reference/` (не в git). Решение о распространении — за пользователем.

## Проверка
**Автоматическая:** `VerifyPatch.ps1` OK; без `AssetExport` в `absoluteru_dev.lua` модуль не грузится (проверить по коду: `require` только внутри ветки с флагом). `GodWayExport.ps1` прогнать на поддельной папке `temp/fake_game/Saved/Mods/logs/godway/` с парой PNG и JSON.

**Чек-лист для пользователя:**
1. Шаг 0: в `absoluteru_dev.lua` добавить `AssetExport = { Panels = { "GodWay_Panel" }, Probe = true }`, запустить игру, открыть «Божий путь», подождать 20 с, выйти. В `C7.log` искать строку `[AbsruExport] probe`. Принести в чат (`tools\GodWayExport.ps1 -ProbeOnly` или `CollectDiagLogs.ps1`).
2. Шаги 1–3: `Probe = false`, открыть «Божий путь», **не трогать 10 с**, затем пролистать «›» все пути, на каждом ждать 5 с, потом постоять 40 с и выйти. В `C7.log`: `[AbsruExport] done files=<n> mb=<m>`.
3. Запустить `tools\GodWayExport.ps1`, открыть `reference/godway_export/demo/index.html` и сравнить со скриншотом игры: фон, деревья, подписи, свечение, пульс по веткам, дым.
