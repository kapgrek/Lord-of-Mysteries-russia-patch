# TASK-018: Выгрузка вкладки «Божий путь» (GodWay) для Electron-приложения, без AES-ключа

Дорожная карта: [ROADMAP.md](ROADMAP.md). Данные: `reference/logs/2026-09-26_1435/` (сессия с открытой вкладкой, `report/textures.csv`), скриншот пользователя 2026-09-26.

Статус: **анализ завершён 2026-09-26**. Шаг 0 выполнен (пробы 1–3). **План пересмотрен 2026-09-26 после пробы 3** (раздел «Пересмотр плана»): анимация — WebGL-шейдеры, эталон — кадры движка через RetainerBox (проба 4, шаг 3.0).

## Ход исполнения
- **Шаг 0 (2026-09-26).** `AbsruAssetExport.lua`: грузится из `Init.lua` в блоке `if Loader.DevFlags` только при непустой таблице `DevFlags.AssetExport` и запущенной `AbsruDiagnostics`; `OnPanelOpen` вызывается рядом с `Diag.OnPanelOpen` в хуке `UIComponent.Open`. Обход панели — через новую `D.NewPanelWalk` в `AbsruDiagnostics.lua` (те же корни и дети, что у обхода диагностики). Проба запускается через 3 с после открытия панели из `Panels`, одна стадия за тик таймера: `api`, `context`, `find`, `texture_canvas` (Canvas `K2_DrawTexture` в режимах Opaque и Translucent → `ExportRenderTarget`), `sprite`, `mid_params`, `mid_draw`, `mid_draw_2` (второй кадр через 1 с, чтобы понять, анимирован ли материал по времени), `texture_direct`. `ExportTexture2D` стоит последним: он читает CPU-мипы, которых у cooked-текстуры может не быть. `probe.json` перезаписывается до и после каждой стадии, так что при падении видно, на какой стадии оно произошло. Итоговая строка в C7.log: `[AbsruExport] probe api=… file=… sprite=… mid_draw=… animated=… ctx=… json=…`.
- `tools/GodWayExport.ps1 -ProbeOnly` копирует `Saved/Mods/logs/godway/**` (или запасной `logs/godway-*`), строки `[AbsruExport]` из C7.log и флаги в `reference/godway_export/raw/<дата>/` и пишет там `probe_summary.md` (формат и размеры PNG по заголовку). Без `-ProbeOnly` скрипт пока останавливается с сообщением. Проверен на `temp/fake_game`, мок-прогон модуля — на Lua 5.4 (`temp/luacheck/LuaRun.exe`).
- **Проба 1 (`reference/godway_export/raw/2026-09-26_1616/`).** Игра не упала, все стадии прошли. Все функции `KismetRenderingLibrary` доступны, есть `RTF_RGBA8_SRGB`, `FVector2D`, `FLinearColor`, `GetContextObject` (`BP_C7GI_C`), вьюпорт 1920×1080. Ошибки самой пробы: (1) первым приходит `Open` дочернего `WBP_ComBackTitle` с тем же uid `GodWay_Panel`, поэтому обход прошёл только 17 узлов, а иконка, `TextBg1` и `Img_Bg01` не нашлись (`mid_draw=fail`, `no material`); (2) `BeginDrawCanvasToRenderTarget(ctx, rt)` → `expect userdata at arg 4`: slua требует out-параметры аргументами. `ExportTexture2D` создал файл **0 байт**, этот путь не работает. У `KGSprite` читаются `Atlas` (`KGSpriteAtlas`) и `SpriteName`; метатаблица slua свойства не перечисляет.
- **Проба 2 (исправления).** Выбирается компонент, у которого `userWidget` называется как uid. Добавлена стадия `rt_clear` (очистка RT 64×64 в красный и `ExportRenderTarget`). Для Canvas перебираются сигнатуры `(ctx, rt, nil, size, context)` → `(ctx, rt, size, context)` → `(ctx, rt)`. Поля `KGSprite`/`KGSpriteAtlas` проверяются по расширенному списку имён, методы атласа вызываются с `SpriteName`, дополнительно пробуется обход через `__pairs`. В строку лога добавлены `canvas=` и `component=`.
- **Проба 2 (`reference/godway_export/raw/2026-09-26_1625/`).** Компонент `GodWay_Panel` найден (2337 узлов, иконка `Icon_Class5`, `TextBg1`, `Img_Bg01`). **`ExportRenderTarget` работает:** `probe_rt_clear.png` — PNG 64×64 RGBA, пиксели (255,0,0,255). **Атлас:** у `KGSpriteAtlas` есть `AtlasTexture` (`Texture_Atlas_GodWay`), `AtlasWidth`/`AtlasHeight` = 512, `Sprites` — TMap «имя → структура» (15 записей), читается через `__pairs`. **UI-материал через `DrawMaterialToRenderTarget` даёт полностью прозрачный кадр** (все 16 точек 0,0,0,0, в обоих кадрах). У `Img_Bg01` MID → MIC `MI_UI_WBP_GodWay_Way_Item_liudong09` (15 scalar, 12 vector, 2 texture) → Material `MA_UI_TY_6_5zong_2Mask`; `MainTex` у MID = `UI_GodWay_Bg_TU1`. Canvas: `(ctx, rt, nil, size, context)` → `expect struct but got nil`, потому что передавался сам импортированный тип структуры, а не экземпляр.
- **Проба 3.** Контекст Canvas создаётся вызовом `DrawToRenderTargetContext()` (так же, как `FVector2D(...)`). Выводится структура записи `Sprites[SpriteName]` и размер `AtlasTexture`. Новая стадия `engine_material` загружает `/Engine/EngineMaterials/Widget3DPassThrough*`, `DefaultMaterial` и `WorldGridMaterial` (`slua.loadObject`), рисует их; для `Widget3DPassThrough*` создаётся MID с `SlateUI` = иконка — это замена Canvas. Также UI-материал рисуется в RT `RTF_RGBA16f`. В строке лога добавлено `engine=`. `GodWayExport.ps1`: исправлен разбор размера PNG (сдвиг `[byte]` давал 0x0 для 512).
- **Проба 3 (`reference/godway_export/raw/2026-09-26_1632/`), итог шага 0.**
  - **Canvas работает:** `BeginDrawCanvasToRenderTarget(ctx, rt, nil, FVector2D(0,0), DrawToRenderTargetContext())`, контекст — экземпляр `DrawToRenderTargetContext()` (userdata); `K2_DrawTexture` + `EndDrawCanvasToRenderTarget(ctx, context)` + `ExportRenderTarget` дают PNG 176×176 RGBA, иконка `UI_GodWay_Icon_Class5` выгружена верно. **Для шага 1 использовать `BLEND_Opaque`:** он пишет прямую (straight) альфу и сохраняет RGB у прозрачных пикселей; `BLEND_Translucent` даёт ту же альфу, но RGB домножен на альфу (пиксель A=198: 104,89,55 против 92,79,48).
  - **Спрайты:** `KGSpriteAtlas.Sprites[SpriteName]` = `{ Name, StartUV, Size }` **в пикселях атласа** (`TextBg1`: StartUV 305,1, Size 120×72; атлас 512×512, `AtlasTexture` = `Texture_Atlas_GodWay`). Поворота/обрезки в записи нет. Для шага 1: атлас целиком через Canvas, прямоугольники из `Sprites`.
  - **`DrawMaterialToRenderTarget`:** поверхностные материалы рисуют RGB, но **альфу не пишут** (у `Widget3DPassThrough*` с `SlateUI` = иконка все пиксели A=0, RGB есть). `DefaultMaterial`, `WorldGridMaterial` → RGB 0. **UI-материал `Img_Bg01` в RGBA8_SRGB и RGBA16f → все 0,0,0,0**: материалы домена UI этим вызовом не рисуются.
  - `ExportTexture2D` → файл 0 байт (не использовать).
- **Для чата анализа (шаг 3 невыполним как описан):** кадры `anim/<материал>/*.png` через `DrawMaterialToRenderTarget` получить нельзя — UI-материалы дают пустой кадр. Нужен другой источник анимации: (а) воспроизвести шейдеры в WebGL по выгруженным параметрам (`materials.json`: scalar/vector/texture по цепочке MID → MIC → Material) и текстурам-параметрам, база — несколько общих материалов (`MA_UI_TY_6_5zong_2Mask` и т. п.), граф которых из памяти не читается; (б) захват экрана (видео/скриншоты вкладки, например `HighResShot`/`Shot showui` или запись пользователем) и вырезка слоёв; (в) искать движковый путь отрисовки виджета в RT (в Lua не найден). Шаги 1–2 от этого не зависят.
- **Исполнение «Пересмотра плана» (2026-09-26, чат 2).** `AbsruAssetExport.lua`: режимы `Probe = true` (без изменений поведения), `"retainer"` (шаг 3.0) и полный (шаги 1, 2, 3.1, 3.2), общие функции RT/Canvas работают через `S.job`; константы в таблице `K` (159 локальных, порог VerifyPatch поднят до 180). `AbsruDiagnostics.lua`: `NewPanelWalk` передаёт визитору родителя, `D.JsonArray`. `GodWayExport.ps1`: шаги 4.1–4.4 и `-FromRaw`. Описание, форматы и строки C7.log — `docs/DIAGNOSTICS.md`, раздел AssetExport. Отличия от плана: calib — не больше 75 % потолка (текстуры важнее); при закрытии панели незаконченное помечается `skipped` (контекст мира — userWidget); путь определяется по подписи (поля компонента, иконки, первые тексты). Проверка: VerifyPatch OK; мок на Lua 5.4 (`temp/export_mock/run_all.ps1`: probe, retainer, full, limit, flat) без ошибок; `GodWayExport.ps1` на `temp/fake_game` — нарезка спрайтов совпала попиксельно (включая полупрозрачные и A=0). Не сделано в этом чате: уроки в `LESSONS.md` и строка в `ROADMAP.md` (лимит); шаг 4.5 — отдельный чат. В игре не проверено.
- **Под вопросом для чата анализа (исходная пометка):** если UI-материалы и в пробе 3 не рисуются в RT, шаг 3 плана (кадры материалов через `DrawMaterialToRenderTarget`) невыполним в текущем виде. → **Решено в разделе «Пересмотр плана».**

## Пересмотр плана (анализ 2026-09-26, после пробы 3)

### Что установлено (`reference/godway_export/raw/2026-09-26_1632/probe.json`)
- Рабочий конвейер «текстура → PNG»: `CreateRenderTarget2D` (`RTF_RGBA8_SRGB` = 3, `RTF_RGBA8` = 2) → `BeginDrawCanvasToRenderTarget(ctx, rt, nil, FVector2D(0,0), DrawToRenderTargetContext())` → `Canvas:K2_DrawTexture(tex, pos, size, FVector2D(0,0), FVector2D(1,1), white, BLEND_Opaque=0)` → `EndDrawCanvasToRenderTarget(ctx, context)` → `ExportRenderTarget`. Код: `AbsruAssetExport.lua:392` (`createTarget`), `:407` (`exportTarget`), `:609` (`canvasDraw`), `:445` (`textureSize`). Правило slua: out-параметры передаются аргументами как **экземпляры** структур (`FVector2D(0,0)`, `DrawToRenderTargetContext()`), не типы и не `nil`.
- Спрайты: `KGSpriteAtlas.Sprites` (TMap, читается через `__pairs`) → `{Name, StartUV, Size}` в пикселях атласа, без поворота/обрезки; `AtlasTexture`, `AtlasWidth/Height`.
- Параметры материалов по цепочке MID → MIC → Material читаются (`materialParams`, `AbsruAssetExport.lua:459`). У самого `Material` списки пусты: **значения по умолчанию и параметры, не переопределённые в MIC, не видны.**
- `DrawMaterialToRenderTarget`: UI-материал → 0,0,0,0 (в SRGB и 16f), поверхностные — RGB без альфы. Путь «кадры материала через Kismet» закрыт.
- В GodWay_Panel (сессия `2026-09-26_1435`): 15 Texture2D, 16 KGSprite (атласы `Atlas_GodWay` и `Common_2`), 10 MIC + 291 MID. Уникальные MI вкладки: `liudong01…07,09,11,12`, `dis01…03_Animated`, `liudong07_Animated`, `smoke01`, `smoke02/03_Animated`, `vx_liuti`, `vx_liuti8`, `Common_Material_glow_add`, `Common_Material_glow_huxi10` (~20). Базовых `Material` за ними, судя по именам (`MA_UI_TY_6_5zong_2Mask` — «универсальный» материал), немного; точный список даст шаг 1.

### Выбор источника живой анимации
| Путь | Точность | Объём | Вывод |
|---|---|---|---|
| (а) WebGL-шейдеры по параметрам | Текстуры и параметры точные. Граф материала в cooked-сборке не хранится (выражения — editor-only, байткод шейдеров в зашифрованных `.ucas`), математику восстанавливаем по именам параметров (`*Tiling(XY)Offset(ZW)`, `*Flow(XY)Rot(Z)RotFlow(W)`, `Distortion*`, `Disolve*`, `Flow*`). **Без эталона — «похоже», не 1:1.** | 3–6 базовых шейдеров по ~150 строк GLSL + подгонка | Бесконечная петля, смена путей, малый размер. **Рантайм демо.** |
| (б) Захват экрана | Композит: слои не разделить, под панелью 3D-сцена/блюр; `HighResShot` без UI, `Shot showui` — единичные кадры | Видео пользователя | **Только визуальная сверка в конце.** |
| (в) Кадр от самого Slate через `RetainerBox` | SRetainerWidget рисует поддерево виджета в свой RT и передаёт его в effect-материал параметром-текстурой; RT берём `EffectMaterial:K2_GetTextureParameterValue(имя)` и выгружаем уже проверенным Canvas → `ExportRenderTarget`. Это настоящий UI-материал в момент t — **1:1**. Не проверено (проба 4); альфа/гамма Slate (premultiplied?) — калибруется по контрольной иконке. | Кадры не зацикливаются (flow непериодичен), 2048² тяжело | **Эталон для подгонки шейдеров** и запасной источник кадров для одноразовых `_Animated`. |

Запасной вариант к (в): `WidgetComponent.GetRenderTarget()` (класс импортируется в рантайме, см. `reference/cpdd-english/.../Init.lua` sceneText), но нужен актёр в мире — сложнее, только если RetainerBox недоступен (решать в чате анализа).

**Решение — гибрид:** демо рисует анимации WebGL-шейдерами (параметры из `materials.json`, текстуры-параметры, дорожка `timeline.json` для UMG-анимаций); шейдеры подгоняются к эталонным кадрам RetainerBox с автоматическим сравнением (`calibrate.html`). Одноразовые `_Animated` (`dis01…03`, `liudong07`, `smoke02/03`) — тот же шейдер + дорожка параметров; их кадры RetainerBox остаются запасным вариантом проигрывания, если шейдер не сошёлся.

**Реалистичность «один в один»:** статика и раскладка — 1:1 по пикселям. Анимации — 1:1 только после подгонки; цель приёмки на эталонных кадрах (после подбора фазы времени): средняя ошибка ≤ 2/255, максимальная ≤ 16/255 по каналу. Для материалов с кастомными нодами/процедурным шумом точное совпадение не гарантировано — такие помечаются в README. **Если проба 4 провалится**, остаётся (а) без эталона: подгонка на глаз по видео пользователя, точность «визуально близко»; сообщить пользователю до шага 4.5.

Объём: шаги 1–3 (Lua + сбор) — один чат исполнения; шейдеры и демо (шаг 4.5) — отдельный чат после получения данных, итеративно по 1–2 базовых материала.

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

Режимы модуля задаются флагом: `Probe = true` — проба шага 0 (оставить как есть), `Probe = "retainer"` — проба 4 (шаг 3.0), `Probe = false`/нет — полная выгрузка (шаги 1–3). Код пробы переиспользовать (`createTarget`, `exportTarget`, `canvasDraw`, `textureSize`, `materialParams`, `readPixels`), не копировать.

### Шаг 1. Статичные текстуры, атласы, материалы
По открытию панели из `Panels` (через 3 с, как в пробе), обход через `D.NewPanelWalk` (уже есть в `AbsruDiagnostics.lua`), корень — компонент, у которого `userWidget` называется как uid (исправление пробы 2).
- **Очередь экспорта:** одна операция `Export*` за тик таймера, как в пробе; дедупликация по пути ресурса. Перед экспортом у текстуры вызвать `SetForceMipLevelsToBeResident(30, 0)` (если есть) и ставить её в очередь не раньше чем через 2 с; записать `IsFullyStreamedIn()`, если метод доступен, иначе `"unknown"` (защита от выгрузки пониженного мипа).
- **`Texture2D`** → `textures/<имя>.png` в собственном размере (`Blueprint_GetSizeX/Y`). RT: `ClearRenderTarget2D` в (0,0,0,0), Canvas `BLEND_Opaque` (прямая альфа), `ReleaseRenderTarget2D` после экспорта. **Формат RT по флагу текстуры `SRGB`:** `true` → `RTF_RGBA8_SRGB`, `false` → `RTF_RGBA8` (иначе у линейных масок/шума появится гамма). Если `SRGB` не читается — выгрузить оба варианта `<имя>.srgb.png` и `<имя>.linear.png`. В `textures.json` по каждой: `path`, `file`, `w`, `h`, `SRGB`, `CompressionSettings`, `AddressX`, `AddressY`, `Filter`, `LODGroup`, `rt_format`, `streamed` (свойства читать через `get`, отсутствующие — `null`).
- **`KGSprite`** → для каждого встреченного `KGSpriteAtlas` один раз: `AtlasTexture` как Texture2D → `atlases/<атлас>.png`; **все** записи `Sprites` (через `__pairs`, не только встреченные) → `sprites.json`: `{ sprite, atlas, x = StartUV.X, y = StartUV.Y, w = Size.X, h = Size.Y }` + у атласа `AtlasWidth`, `AtlasHeight`, `Filter`, `BatchAtlasIndex`. Другие классы кисти (`DynamicSprite` и т. п.) — только запись класса и пути в `unknown_resources` без экспорта.
- **Материалы** → `materials.json`, ключ — путь объекта:
  - по цепочке MID → MIC → … → `Material`: класс, путь, `Parent`, все `Scalar/Vector/TextureParameterValues` на каждом уровне (как `materialParams`);
  - у `Material`: `BlendMode`, `MaterialDomain`, `TwoSided`, `bUsedWithUI`/аналоги, перечень полей через `__pairs` (верхний уровень, глубина 1), а также `TextureStreamingData` и `CachedExpressionData`, если читаются (там могут быть имена и значения **по умолчанию** всех параметров и список всех текстур материала);
  - у MID — **действующие** значения: объединение имён параметров всех MI того же базового материала, запрошенное `K2_GetScalarParameterValue`/`K2_GetVectorParameterValue`/`K2_GetTextureParameterValue`;
  - все текстуры-параметры (включая найденные в `TextureStreamingData`) выгрузить как Texture2D тем же конвейером.
  - в `materials.json` — сводка `bases`: базовый `Material` → список MI и число виджетов.
- Перелистывание путей: панель открыта, пользователь нажимает «›»; новые ресурсы подхватываются повторным обходом при смене выбранного пути (хук `Refresh` компонента панели или опрос каждые 1 с по смене выбранного пути; лимит `PanelWalksPerUid` для этой панели снять).

### Шаг 2. Раскладка → `layout.json`
Для каждого виджета `GodWay_Panel` и каждого экземпляра `WBP_GodWay_Item`:
`name`, `class`, `parent`, `z` (порядок в родителе + `ZOrder` слота), геометрия на экране (`SlateBlueprintLibrary.LocalToViewport` / `GetAbsolutePosition` + `GetLocalSize` от `GetCachedGeometry`, в пикселях вьюпорта), слот (`CanvasPanelSlot`: `GetPosition`, `GetSize`, `GetAnchors`, `GetAlignment`, `GetAutoSize`), `RenderOpacity`, `RenderTransform` (translation, scale, shear, angle) и `RenderTransformPivot`, `Visibility`, `ColorAndOpacity`. Для кисти: `DrawAs`, `Tiling`, `Margin` (9-slice), `TintColor`, `ImageSize`, ссылка на ресурс. Для текстов: текст, шрифт, размер, цвет, выравнивание. Отдельно размер вьюпорта и DPI-масштаб (`WidgetLayoutLibrary.GetViewportSize` / `GetViewportScale`). Снимок делать после завершения анимации открытия (через 3 с после открытия) и повторять при смене пути.

Уточнения после пробы:
- Out-параметры `SlateBlueprintLibrary.LocalToViewport(ctx, geometry, local, pixelOut, viewportOut)` и подобных передавать экземплярами `FVector2D(0,0)` и читать возвращаемые значения (как у `BeginDrawCanvasToRenderTarget`); записать, какая сигнатура сработала.
- Ссылка на ресурс кисти: `Texture2D` → ключ `textures.json`; `KGSprite` → `{ atlas, sprite }` из `sprites.json`; материал → путь MID (ключ `materials.json`). Плюс `Clipping` виджета и `UVRegion`/`Mirroring` кисти, если есть.
- Для панели — `path_index`/идентификатор выбранного пути в каждом снимке, чтобы демо переключало раскладки.

Виджеты вне `GodWay_Panel` (например, строка `ID:…` внизу экрана) не записывать.

### Шаг 3. Анимация
Старый пункт «кадры через `DrawMaterialToRenderTarget`» **отменён** (проба 3: UI-материалы дают пустой кадр).

#### 3.0. Проба 4: RetainerBox (отдельная короткая сессия, `Probe = "retainer"`)
Через 3 с после открытия панели, по стадиям за тик, всё через `pcall`, результат в `logs/godway/probe_retainer.json` (перезапись до/после стадии):
1. `cvar`: `KismetSystemLibrary.GetConsoleVariableIntValue("Slate.EnableRetainedRendering")` (если 0 — записать и продолжить).
2. `create`: `import("RetainerBox")`, `import("Image")`; создать виджеты тем же способом, что `DesktopChat.lua:2158-2183` (`WidgetTree:ConstructWidget(class)` → `Game.ObjectActorManager:KGNewObject` → `NewObject`), дерево — `WidgetTree` корня GodWay_Panel. Image положить в RetainerBox (`AddChild`/`SetContent`), RetainerBox — в корневую `CanvasPanel` панели (`AddChildToCanvas` или `AddChild`), `ZOrder` минимальный (под фоном), слот: позиция (0,0), размер = размер кадра. Записать, какой путь создания и добавления сработал.
3. `setup`: effect-материал — MID от `/Engine/EngineMaterials/Widget3DPassThrough` (грузится `slua.loadObject`, проба 3); `SetEffectMaterial(mid)`, `SetTextureParameter("SlateUI")`, `SetRetainRendering(true)` (или поле `bRetainRender`), `SetRenderingPhase(0, 1)`. Записать доступные методы/поля RetainerBox.
4. `icon` (контроль): кисть Image = `UI_GodWay_Icon_Class5` (176×176, `SetBrushFromTexture`), подождать 2 тика, `rt = GetEffectMaterial():K2_GetTextureParameterValue("SlateUI")` (если `nil` — пробовать `mid:K2_GetTextureParameterValue`, поле `RenderTarget`/методы с `RenderTarget` в имени). Записать класс/размер/формат RT. Выгрузить двумя путями: `ExportRenderTarget(rt)` напрямую и копией Canvas Opaque в свой RT `RTF_RGBA8_SRGB` → `probe_retainer_icon*.png`; `readPixels` в тех же 9 точках, что `canvas_opaque` пробы 3 (сравнение даст premultiplied/гамму Slate).
5. `mid`: кисть Image = MID `Img_Bg01` (тот же объект, `SetBrushFromMaterial`), размер 1024×1012 (половина), два экспорта через 0,5 с → `probe_retainer_bg_t0/t1.png`; `pixels`, `animated` (отличаются ли кадры), время каждой операции (`nowMs`) для экспорта 1024 и копии Canvas.
6. `mid_small`: то же для одного MID `liudong04` (`Img_Lev3Bg02`) в размере его `ImageSize`.
7. `cleanup`: `RemoveFromParent` у созданных виджетов.
Строка в C7.log: `[AbsruExport] retainer cvar=… create=<путь|fail> rt=<class WxH|nil> icon=<ok|black|fail> mid=<ok|black|fail> animated=<yes|no> export_ms=<n> json=…`.

**Если `rt=nil` или `mid=black`** — шаги 3.1 и 4.1–4.4 всё равно выполнять (они не зависят от RetainerBox), а в чат анализа вернуться с `probe_retainer.json` (варианты: `WidgetComponent.GetRenderTarget`, калибровка по видео).

#### 3.1. Дорожка параметров `timeline.json` (всегда)
По одним тикам с отметкой `t` (мс от открытия панели) и `rt_s` (`GameplayStatics.GetRealTimeSeconds` — для привязки к `Time` в материале):
- для всех виджетов панели — `RenderOpacity`, `RenderTransform`, `Visibility`, `ColorAndOpacity`, `Brush.TintColor`;
- для каждого MID — действующие scalar/vector-параметры (объединение имён из шага 1).
Писать только изменения. Окна записи: 10 с от открытия панели, затем 5 с после каждой смены пути. Плюс список UMG-анимаций (`WidgetAnimation` по полям userWidget: имя, `GetEndTime`), если читаются. Опрос параметров распределять по тикам с бюджетом `FrameBudgetMs`, записать фактическую частоту выборки.

#### 3.2. Эталонные кадры RetainerBox (только если проба 4 = ok)
Для каждой уникальной пары (MI-родитель MID, размер кисти), максимум по одному представителю:
- создать RetainerBox + Image (как в пробе 4) с общим MID представителя; фон — половинное разрешение, остальные — `ImageSize` (≤ 1024 по длинной стороне);
- серия: в каждый нужный тик копировать RT retainer в заранее созданный RT из пула (Canvas Opaque, дёшево), записывать `rt_s` и действующие параметры MID; экспорт пула — после серии, по одному за тик. Моменты: 0, 1, 2, 3 тика подряд, затем +0,25; 0,5; 1; 2; 4 с (фактические `rt_s` важнее плановых);
- для `_Animated` (`dis01…03`, `liudong07`, `smoke02/03`) дополнительно серия каждый тик в течение 2 с **от открытия панели** (retainer создавать сразу в `OnPanelOpen`, не через 3 с) — это эталон появления вместе с дорожкой 3.1;
- `calib/<MI>/<nnn>.png` + `calib/<MI>/frames.json`: `size`, `scale`, `mid`, `frames[] = { file, rt_s, t, params }`, `alpha` (итог калибровки иконки из пробы 4).
- Retainer удалять после серии. Потолок: 3000 файлов и 600 МБ на весь экспорт; при превышении — `[AbsruExport] limit ...` и остановка.

По окончании всех стадий: `[AbsruExport] done files=<n> mb=<m> textures=<n> sprites=<n> materials=<n> calib=<n> timeline=<событий>`.

### Шаг 4. Сбор и сборка результата
Новый скрипт `tools/GodWayExport.ps1` (UTF-8 с BOM):
1. Копирует **из игры** (только чтение) `Saved/Mods/logs/godway/**` в `reference/godway_export/raw/<yyyy-MM-dd_HHmm>/`. В папку игры ничего не пишет.
2. Режет спрайты из атласов по `sprites.json` → `reference/godway_export/textures/sprites/*.png` (System.Drawing, без изменения альфы: `PixelFormat.Format32bppArgb`, копирование через `LockBits`, не через `DrawImage`, чтобы не было премультипликации/сглаживания).
3. Копирует `textures/`, `atlases/`, `calib/` в `reference/godway_export/`, проверяет PNG (сигнатура, размер по заголовку ≠ 0, совпадение с `textures.json`).
4. Собирает `reference/godway_export/manifest.json` (все ассеты, размеры, sha256) и копирует `layout.json`, `timeline.json`, `materials.json`, `textures.json`, `sprites.json`. Пишет `summary.md`: число файлов по типам, список базовых материалов (`bases`), какие текстуры `streamed != true`, какие `SRGB` не прочитались, есть ли `calib/`.
5. **Отдельный чат после получения данных:** демо `reference/godway_export/demo/` (чистый JS, без сборщика, `file://` в Electron): абсолютная раскладка 1920×1080 с масштабированием, слои по `z`, `Box`-кисти через `border-image` по `Margin`, текстуры/спрайты; материалы — **WebGL** (`godway-gl.js`, `shaders/<базовый материал>.frag`): униформы по именам параметров из `materials.json`, текстуры с `AddressX/Y` и фильтрацией из `textures.json`, смешивание по `BlendMode` (Translucent — straight alpha «over», Additive — `ONE, ONE`), `Time` = `performance.now()`; дорожка `timeline.json` применяется к opacity/transform/параметрам. `calibrate.html`: для каждого кадра `calib/` рисует шейдер при `rt_s + фаза`, подбирает фазу, выводит тепловую карту разницы, среднюю/максимальную ошибку и итог по порогу из «Пересмотра плана». Материалы, не прошедшие порог: для `_Animated` — проигрывание кадров `calib/`, для остальных — пометка в README. Переключение путей стрелками.
6. `reference/godway_export/README.md`: структура папки, как подключить в Electron, что и откуда снято, таблица «материал → шейдер → ошибка калибровки», известные отличия.

### Шаг 5. Документы
- `docs/DIAGNOSTICS.md`: раздел «AssetExport» (флаг и режимы `Probe = true | "retainer" | false`, файлы, строки в C7.log, бюджет, потолок).
- `docs/LESSONS.md`: урок «UI-материалы не рисуются `DrawMaterialToRenderTarget`; out-параметры slua — экземпляры структур; формат RT по флагу `SRGB` текстуры».
- `docs/PROJECT_MAP.md`: строки для `AbsruAssetExport.lua` и `tools/GodWayExport.ps1`.
- `ROADMAP.md`: строка TASK-018. Версию патча **не поднимать** и релиз не собирать: модуль dev-only, для пользователей ничего не меняется. Но `VerifyPatch.ps1` должен проходить (новый файл в payload).

## Ограничения
- Lua — UTF-8 без BOM, LF. Новых локальных переменных верхнего уровня в `Init.lua` не добавлять (VerifyPatch), подключение модуля — внутри существующего блока `if Loader.DevFlags`.
- Все вызовы движка через `pcall`. Ошибки → `[AbsruExport] error stage=<этап>: …` (первые 3 на этап), после 200 ошибок модуль отключается.
- Нет `io.open`, нет путей разработчика: запись только в `Loader.Root .. "logs/godway/"` (или то, что покажет проба для `ExportRenderTarget`).
- Всё, что получено, — ассеты NetEase. Кладутся только в `reference/` (не в git). Решение о распространении — за пользователем.

## Проверка
**Автоматическая:** `VerifyPatch.ps1` OK; без `AssetExport` в `absoluteru_dev.lua` модуль не грузится (проверить по коду: `require` только внутри ветки с флагом). `GodWayExport.ps1` прогнать на поддельной папке `temp/fake_game/Saved/Mods/logs/godway/` с парой PNG и JSON.

**Автоматическая (дополнение):** мок-прогон режимов `Probe = "retainer"` и полного на Lua 5.4 (`temp/luacheck/LuaRun.exe`) с заглушками движка; `GodWayExport.ps1` на `temp/fake_game` с `textures.json`, `sprites.json`, атласом 64×64 и одним `calib/`-кадром — нарезка спрайта совпадает по пикселям (включая полупрозрачные).

**Чек-лист для пользователя:**
1. Шаг 0 — выполнен (пробы 1–3).
2. **Проба 4 (шаг 3.0):** в `absoluteru_dev.lua` `AssetExport = { Panels = { "GodWay_Panel" }, Probe = "retainer" }`, запустить игру, открыть «Божий путь», подождать 20 с, выйти. В `C7.log` искать `[AbsruExport] retainer`. Запустить `tools\GodWayExport.ps1 -ProbeOnly` и принести результат в чат исполнения.
3. **Полная выгрузка (шаги 1–3):** `Probe = false`. Открыть «Божий путь», **не трогать 15 с**, затем пролистать «›» все пути, на каждом ждать 8 с, потом постоять 60 с и выйти. В `C7.log`: `[AbsruExport] done files=<n> mb=<m> …` и нет `[AbsruExport] limit`. Ошибки — строки `[AbsruExport] error stage=…`.
4. Запустить `tools\GodWayExport.ps1`, открыть `reference/godway_export/summary.md`: есть базовые материалы, текстуры с `streamed != true` отсутствуют или перечислены.
5. После чата шага 4.5: открыть `reference/godway_export/demo/index.html` и `calibrate.html`, сравнить с игрой (желательно короткое видео вкладки 10 с для сверки): фон, деревья, подписи, свечение, пульс по веткам, дым, проявление при открытии.
