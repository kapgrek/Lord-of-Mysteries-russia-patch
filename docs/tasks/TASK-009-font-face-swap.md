# TASK-009: шрифт — применяется ли вообще правка CompositeFont в рантайме (замена face у `Title`)

Статус: **шаги 1–5 исполнены** 2026-09-25 (v2.9.5-RU, режим по умолчанию `"typeface"`), **ждут проверки в игре** по разделу «Проверка». Релиз не опубликован.
- Шаги 1–3: `Init.lua` — `applyFace`, `titleIndex`, `resolveTitleFace`, `writeTitleFace`, `cultureFlush`; `runtimeFixes.CyrillicTitleFace = "Aleo_Regular"`; блок выбора режима обёрнут в `run(stage)`, повтор — `runtimeFixes.CyrillicFontRetry` в хуке `after_main` (1500) перед выводом строки. Логика прогнана на заглушках (fengari): face по умолчанию и из SubTypeface, SDF не меняется, `Set` и `Remove` + `Insert`, откат при `verify` и `flush=err`, неизвестное имя face → `typeface`, `flush2=ok` с возвратом культуры, повтор с `applied_at=after_main`, Title не меняется на Regular в `face`.
- К шагу 2: блок шрифта и в v2.9.4 выполнялся при загрузке `Init.lua` (кадр 0), в `after_main` выводилась только строка. Значит, `cultures` уже тогда писался до экрана загрузки, и версия «правка пришла слишком поздно» для H1 маловероятна; `applied_at` теперь это подтверждает в логе.
- Шаг 5: `fonts.json → cyrillic_font` и `CollectDiagLogs.ps1` дополнены полями `source`, `title_face`, `flush2`, `applied_at`.

Дорожная карта: [ROADMAP.md](ROADMAP.md), этап 4a. Предыдущие: [TASK-006](TASK-006-font.md), [TASK-007](TASK-007-font-coverage.md), [TASK-008](TASK-008-font-cultures.md).

## Симптом (проверка v2.9.4 в игре, 2026-09-25)
Режим `cultures` отработал без ошибок в обоих тестах, но на экране **ничего не изменилось**. В режиме `cultures` подмена Title → Regular выключена, поэтому вид откатился к v2.9.1 (широкий Mincho, 1,0 em) — пользователь видит это как регресс. Скриншоты: варианты диалога, описание задания (`TaskBoardPanel`), карточки Исследования, магазин.

C7.log (`D:\Games\…\C7\Saved\Logs\C7.log`, читался из игры):
```
11:09:04 cyrillic font mode=cultures sub=/Game/Arts/UI_2/Resource/Font/Fallback/NotoSerif_Regular.NotoSerif_Regular cultures=en previous= write=ok(set) verify=ok flush=ok cyr=unknown latin=unknown
11:20:48 cyrillic font mode=cultures sub=/Game/Arts/UI_2/Resource/Font/Fallback/NotoSansCJKsc_Regular.NotoSansCJKsc_Regular cultures=en previous= write=ok(set) verify=ok flush=ok cyr=unknown latin=unknown
```

## Первопричина (что уже исключено)
- **Не в NotoSerif.** Второй тест поставил `Cultures=en` на `NotoSansCJKsc_Regular`. Этот sub кириллицу точно покрывает: Regular рисует ею «Прогресс: 0/3», ширина 0,62 em = Source Han Sans (`reference/fonts/loose/cmap_report.txt`). Title всё равно остался Mincho.
- **Не в записи.** `write=ok(set) verify=ok`: значение читается обратно из `Font_Aleo.CompositeFont`.
- **Остаются две гипотезы, различить их данными пока нельзя:**
  - **H1 — рантайм-правка CompositeFont не доходит до Slate.** `FCompositeFontCache` держит разобранную копию шрифта (`FCachedCompositeFontData`: typeface, диапазоны, приоритеты). `C7FunctionLibrary.FlushFontCache` (игровая обёртка) может сбрасывать только атлас глифов, а не этот кэш. Либо правка приходит, когда шрифт уже закэширован (экран загрузки рисует текст раньше `after_main`).
  - **H2 — правка доходит, но приоритет по `Cultures` в этой сборке не перебивает default-face.**
- **Решающий тест:** заменить `FontFaceAsset` в записи `Title` у `DefaultTypeface` — без диапазонов и культур. Если Title изменится (везде, включая RichText и текст из данных), верна H2, и замена face сама по себе решение. Если не изменится ничего, верна H1, и путь «править CompositeFont из Lua» закрыт.

## План
Версия **v2.9.5-RU**. Режим по умолчанию — `"typeface"` (как в v2.9.3). Новое — только по dev-флагу.

1. **Режим `CyrillicFont = "face"`** (`Init.lua`, блок шрифта кириллицы, рядом с режимом `cultures`):
   - В `Font_Aleo.CompositeFont.DefaultTypeface.Fonts` найти запись `Name == "Title"`. Записи `*_SDF*` не трогать: SDF-face — другой тип растеризации.
   - Источник face — dev-флаг `CyrillicTitleFace`, по умолчанию `"Aleo_Regular"`. Значения: `"Aleo_Regular"` (face записи `Regular`), `"NotoSerif_Regular"` / `"NotoSansCJKsc_Regular"` / `"NotoSans_Regular"` (face из `Typeface.Fonts[0]` соответствующего SubTypeface, по окончанию пути). Объект face брать из уже прочитанной структуры, а не через `loadObject` по угаданному пути.
   - Запись через копию, как в `cultures`: `cf = font.CompositeFont; def = cf.DefaultTypeface; fonts = def.Fonts; e = item(fonts, i); data = e.Font; data.FontFaceAsset = face; e.Font = data;` заменить элемент тем способом, который сработал в `cultures` (`write=ok(set)`); `def.Fonts = fonts; cf.DefaultTypeface = def; font.CompositeFont = cf`.
   - Проверка чтением (путь face у `Title` = новый), затем `FlushFontCache()`.
   - Строка в `after_main`: `cyrillic font mode=face title_face=<путь> previous=<путь> write=… verify=… flush=… applied_at=<load|after_main>`.
   - Ошибка → вернуть прежний face → `typeface` с `reason=…`.
   - В режиме `face` подмену Title → Regular (`typeface`) не выполнять: тест должен показать эффект только самой правки шрифта.
2. **Время применения.** Режимы `face` и `cultures` применять **при загрузке `Init.lua`** (кадр 0, до экрана загрузки), а не только в `after_main`. В `applied_at` писать, когда запись прошла успешно. Если на кадре 0 `Font_Aleo` ещё не загружен (`loadObject` вернул nil), повторить в `after_main` и записать `applied_at=after_main`.
3. **Второй способ сброса (dev-флаг `CyrillicFlush = "culture"`, по умолчанию выкл.).** После `FlushFontCache` переключить культуру туда и обратно: `KismetInternationalizationLibrary.SetCurrentCulture("en-US", false)` → `SetCurrentCulture(<исходная>, false)`. В UE смена культуры сбрасывает кэши шрифтов Slate. Результат дописать в строку лога (`flush2=ok|err`). Включать только в третьем тесте чек-листа.
4. **Ничего больше не менять:** `cultures` оставить как есть (пригодится, если подтвердится H2 + неверный приоритет). Ассеты игры не заменяются, хуков не добавлять.
5. **Проверки и документы.** `tools/VerifyPatch.ps1`; Lua без BOM, LF. `DIAGNOSTICS.md`: `face`, `CyrillicTitleFace`, `CyrillicFlush`. `LESSONS.md`: «`cultures` в v2.9.4: запись и проверка ok, на экране без изменений — рантайм-правку CompositeFont проверять по экрану, а не по `verify`». ROADMAP, TASK-008 (статус: гипотеза не подтвердилась). Закоммитить, запушить; релиз не публиковать.

## Проверка
**Автоматическая:** `VerifyPatch.ps1` OK; `git diff --stat` — `Init.lua`, версии, документы.

**Чек-лист для пользователя** (установить v2.9.5-RU; экраны каждый раз одни и те же: диалог с вариантами ответа, описание задания справа, карточки Исследования, магазин, кнопка «Разговаривать», латиница «Plot Overview»):
1. **Тест 1:** в `absoluteru_dev.lua` `CyrillicFont = "face"` (без `CyrillicTitleFace`, т. е. `Aleo_Regular`). Ожидание при H2: весь Title-текст (кириллица и латиница) выглядит как обычный текст «Прогресс: 0/3», в том числе в описании задания и вариантах диалога. Прислать строку `cyrillic font mode=face …` и скриншоты.
2. **Тест 2 (если тест 1 изменил вид):** `CyrillicTitleFace = "NotoSerif_Regular"`. Ожидание: кириллица с засечками, пропорциональная; проверить, что нет квадратов и пустых мест.
3. **Тест 3 (если тест 1 ничего не изменил):** `CyrillicFont = "face"` + `CyrillicFlush = "culture"`. Если и так без изменений — рантайм-путь закрыт (H1).
4. После тестов вернуть обычный вид: удалить строки `CyrillicFont`, `CyrillicTitleFace`, `CyrillicFlush` из `absoluteru_dev.lua`.

## Промпт для чата исполнения
> Ты — чат исполнения проекта AbsoluteRU (AGENTS.md §3, чат 2). Прочитай AGENTS.md, docs/LESSONS.md, docs/DIAGNOSTICS.md, docs/tasks/ROADMAP.md, docs/tasks/TASK-008-font-cultures.md и выполни docs/tasks/TASK-009-font-face-swap.md, раздел «План», шаги 1–5. Главное: режим `cultures` (v2.9.4) дважды дал `write=ok verify=ok flush=ok`, в том числе на `NotoSansCJKsc_Regular`, который точно покрывает кириллицу, но на экране ничего не изменилось. Нужен решающий тест: новый режим `CyrillicFont = "face"` — заменить `FontFaceAsset` у записи `Title` в `Font_Aleo.CompositeFont.DefaultTypeface.Fonts` на face, выбранный флагом `CyrillicTitleFace` (по умолчанию face записи `Regular`; варианты — face SubTypeface `NotoSerif_Regular`/`NotoSansCJKsc_Regular`/`NotoSans_Regular`, объект брать из прочитанной структуры), проверить чтением, `FlushFontCache`, при ошибке вернуть прежний face и уйти в `typeface`; в режиме `face` подмену Title → Regular не выполнять; SDF-записи не трогать. Режимы `face`/`cultures` применять уже при загрузке `Init.lua` (кадр 0), с повтором в `after_main`, если `Font_Aleo` ещё не загружен; писать `applied_at`. Добавь dev-флаг `CyrillicFlush = "culture"` (переключение культуры en-US и обратно после сброса, по умолчанию выключен). Режим по умолчанию остаётся `"typeface"`. Версия v2.9.5-RU. Lua — UTF-8 без BOM, LF. Не пиши «исправлено»: дай мне чек-лист из раздела «Проверка». Закоммить и запушь в main; релиз не публикуй. В папку игры ничего не пиши и игру не запускай.
