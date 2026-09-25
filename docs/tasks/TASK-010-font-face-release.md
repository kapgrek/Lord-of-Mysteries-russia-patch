# TASK-010: шрифт — режим `face` по умолчанию, SDF-начертания, чистка неудавшихся режимов (этап 4a, завершение)

Дорожная карта: [ROADMAP.md](ROADMAP.md), этап 4a. Предыдущая: [TASK-009](TASK-009-font-face-swap.md).

## Симптом (проверка v2.9.5 в игре, 2026-09-25, тест 1 TASK-009)
Режим `CyrillicFont = "face"` (face `Title` → face `Regular`) сработал. По словам пользователя, «почти везде теперь выглядит хорошо»: варианты диалога, кнопка «Разговаривать», Исследование, магазин, левый список заданий, «Цель задания» и «Plot Overview» набраны пропорциональным шрифтом. C7.log:
```
12:00:28 cyrillic font mode=face source=Aleo_Regular title_face=/Game/Arts/UI_2/Resource/Font/Aleo_Regular.Aleo_Regular previous=/Game/Arts/UI_2/Resource/Font/Aleo_Title.Aleo_Title write=ok(set) verify=ok flush=ok applied_at=load
```
Остались:
1. Имена персонажей и NPC над головой («Себастьян», «Киренаика») — по-прежнему разреженный Mincho. Подписи под ними («Менеджер клуба», «Земляк Шута») нормальные.
2. Описание задания (`TaskBoardPanel`, «По прошествии некоторого времени…») — разреженное, а «Цель задания» под ним — нормальная.
3. Старые записи боёв Автошахмат: описания талантов и резонансов на английском и китайском. Это не шрифт, см. «Вне задачи».

## Первопричина
- **Правка CompositeFont из Lua работает, если применена при загрузке.** `applied_at=load`: v2.9.5 пишет на кадре 0, до того как Slate закэширует шрифт. `cultures` в v2.9.4 применялся позже (строка в `after_main`), и это, вероятно, объясняет, почему он не дал эффекта при `verify=ok`. Перепроверять `cultures` не нужно: `face` решает задачу проще.
- **Пп. 1–2 — SDF-начертания, которые `face` сознательно не трогает** (`Init.lua:1958-1959`: меняется только запись `Title`).
  - `Font_Aleo.DefaultTypeface` (проба composite, `reference/logs/2026-09-25_1046/report/fonts.md`): `Title_SDF → Aleo_Title_SDF`, `Regular_SDF → Aleo_Regular_SDF`, `Title_SDF_HeadName → Aleo_Title_SDF_HeadName`.
  - Описание задания: `TaskBoardPanel / Text_TaskDesc1`, **typeface `Title_SDF`** (`fonts.md → Title с кириллицей`, styled=True rich=True). «Цель задания» — `Text_TargetDesc`, typeface `Title`, поэтому она и исправилась.
  - Имена над головой: по имени typeface — `Title_SDF_HeadName`. У него нет пары `Regular_SDF_HeadName` (TASK-007). Подписи-титулы под именем, судя по виду, рисуются `Regular*`.
  - Решение: в той же записи CompositeFont заменить face у `Title_SDF` и `Title_SDF_HeadName` на face `Regular_SDF` (`Aleo_Regular_SDF`) — **SDF на SDF**, тип растеризации тот же. Обычный (не SDF) face в SDF-запись не ставить.
- **Режимы `subfont` и `cultures` больше не нужны.** `FInt32Range` непрозрачен (TASK-008), `cultures` не дал эффекта (TASK-009), а `face` работает. Их код и пробы диапазонов увеличивают `Init.lua`: VerifyPatch уже на 182 из 190 локальных переменных верхнего уровня (запас 8).

## План
Версия **v2.9.6-RU**.

1. **SDF-записи в режиме `face`.** Обобщить `titleIndex` / `writeTitleFace` / `applyFace` (`Init.lua:1957-2090`) до списка замен `{ Title → Regular, Title_SDF → Regular_SDF, Title_SDF_HeadName → Regular_SDF }`: face источника брать из записи-источника в прочитанной структуре (`entryFace(findEntry(entries, "<источник>"))`). Писать все замены одной копией `CompositeFont` и одной записью обратно; проверять чтением каждую; при любой ошибке откатывать **все** записи к прежним face (их держать через `AddToRoot`, как сейчас). Если записи-источника нет (например, нет `Regular_SDF`), пропустить эту замену и указать это в логе, остальные выполнить.
   - `CyrillicTitleFace` (dev-флаг) влияет только на запись `Title`. SDF-записи всегда берут `Regular_SDF`: у NotoSerif и прочих sub нет SDF-версии.
   - Строка лога: `cyrillic font mode=face title=<face> title_sdf=<face|skip> title_sdf_headname=<face|skip> write=… verify=… flush=… applied_at=…`.
2. **`face` — режим по умолчанию.** `CYRILLIC_FONT_MODE = "face"` (`Init.lua:1514`). Откат при ошибке — в `typeface`, как сейчас. В режиме `face` подмена Title → Regular в `translateTextWidget` не выполняется.
3. **Удалить `subfont` и `cultures`.** Удалить из `Init.lua`: `writeCyrillicSub`, `removeCyrillicSub`, `cyrillicSubIndex`, `newRange`, `applySubfont`, режим `cultures` и `CyrillicCultureSubs`, флаг `CyrillicFlush` (переключение культуры) вместе с кодом. Оставить `flushFontCache`, `face`, `typeface`, `off`. Из `AbsruDiagnostics.lua` удалить пробу `FInt32Range` (методы, `.get`/`.set`, `import(Int32Range)` и прочие); `composite` оставить, но диапазоны писать только числом (`ranges=<N>`). В `CollectDiagLogs.ps1` убрать раздел «Проба FInt32Range» и колонки «А / A» и «чтение». Проверить, что VerifyPatch показывает больший запас по локальным переменным.
4. **Документы.** `DIAGNOSTICS.md` — флаги (`CyrillicFont`: `face` | `typeface` | `off`; `CyrillicTitleFace`), убрать описания `subfont` / `cultures` / `CyrillicFlush` / пробы диапазонов. `LESSONS.md` — урок: «CompositeFont из Lua правится, только если правка сделана при загрузке `Init.lua` (кадр 0); `verify=ok` не доказывает, что Slate увидел правку, — проверять по экрану». Статус TASK-006…009, ROADMAP (этап 4a — исполнено, ждёт проверки; 4b — теперь необязателен, только если нужен шрифт с засечками, которого нет в игре). Закоммитить, запушить; релиз не публиковать.

## Проверка
**Автоматическая:** `tools/VerifyPatch.ps1` OK, запас локальных переменных `Init.lua` больше 8; в `Init.lua` нет `newRange`, `cultures`, `CyrillicFlush`; `git diff --stat` — `Init.lua`, `AbsruDiagnostics.lua`, `CollectDiagLogs.ps1`, версии, документы.

**Чек-лист для пользователя** (установить v2.9.6-RU; в `absoluteru_dev.lua` **убрать** строки `CyrillicFont`, `CyrillicTitleFace`, `CyrillicFlush`: теперь `face` — режим по умолчанию):
1. C7.log: `cyrillic font mode=face title=…Aleo_Regular title_sdf=…Aleo_Regular_SDF title_sdf_headname=…Aleo_Regular_SDF write=ok… verify=ok flush=ok applied_at=load`.
2. Имена над NPC и персонажами («Себастьян», «Киренаика») — пропорциональные, не разреженные; не размытые и без «ореола» (SDF-рендер).
3. Задания: описание справа («По прошествии некоторого времени…») — как «Цель задания» под ним.
4. Повторить экраны TASK-009: диалог, «Разговаривать», Исследование, магазин, «Plot Overview» — без регресса.
5. (Необязательно) тест шрифта с засечками: `CyrillicTitleFace = "NotoSerif_Regular"` в `absoluteru_dev.lua` — заголовки с засечками; нет квадратов и пустых мест. Сообщить, какой вариант лучше: если NotoSerif, сделать его значением по умолчанию одной строкой (`runtimeFixes.CyrillicTitleFace`).

## Вне задачи: записи боёв Автошахмат
- В сессии 20260925-115934 (`Saved/Mods/logs/absru-s2-untranslated-*.jsonl`, читались из игры) около **283** промахов StringDB с текстом Автошахмат (`src=stringdb`, en содержит piece / Resonance / Gold Coins…), например row `158675419318528` «Randomly gain pieces with a total value of 12 Gold Coins…» и row `158469797713664` «Sinful Tingen pieces gain 15% Attack…» (показан китайским).
- В батчах этих строк нет (поиск `source_cn` «随机获得总价值», «罪恶廷根棋子获得» по `source/translation_batches/` — 0). Во вкладке энциклопедии те же таланты берутся из других строк, которые переведены.
- Это задача перевода (этап 7 или отдельный TASK): выгрузить промахи StringDB из `untranslated.csv` («нет в батчах»), добавить их в батч Автошахмат (`batch_028_autochess.json`) и перевести по глоссарию. Нужен отдельный анализ; в TASK-010 не делать.

## Промпт для чата исполнения
> Ты — чат исполнения проекта AbsoluteRU (AGENTS.md §3, чат 2). Прочитай AGENTS.md, docs/LESSONS.md, docs/DIAGNOSTICS.md, docs/tasks/ROADMAP.md, docs/tasks/TASK-009-font-face-swap.md и выполни docs/tasks/TASK-010-font-face-release.md, раздел «План», шаги 1–4. Главное: режим `face` (v2.9.5, замена FontFaceAsset у `Title` на face `Regular`, применённая при загрузке Init.lua) в игре сработал; остались разреженными имена над NPC и описание задания — это SDF-начертания `Title_SDF_HeadName` и `Title_SDF`, которые `face` не трогает. Сделай: в режиме `face` заменить face у `Title` → `Regular`, `Title_SDF` → `Regular_SDF`, `Title_SDF_HeadName` → `Regular_SDF` одной копией CompositeFont (face брать из прочитанной структуры, SDF только на SDF, проверка чтением, откат всех замен при ошибке); сделать `face` режимом по умолчанию (откат — `typeface`); удалить неудавшиеся режимы `subfont` и `cultures`, флаг `CyrillicFlush` и пробу `FInt32Range` из Init.lua, AbsruDiagnostics.lua и CollectDiagLogs.ps1. Записи боёв Автошахмат в этой задаче не трогать. Версия v2.9.6-RU. Lua — UTF-8 без BOM, LF; `.ps1` с кириллицей — с BOM. Проверь `tools/VerifyPatch.ps1`. Не пиши «исправлено»: дай мне чек-лист из раздела «Проверка». Закоммить и запушь в main; релиз не публикуй. В папку игры ничего не пиши и игру не запускай.
