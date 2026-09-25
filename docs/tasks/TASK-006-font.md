# TASK-006: шрифт — пропорциональная кириллица в Font_Aleo (этап 4)

Дорожная карта: [ROADMAP.md](ROADMAP.md), этап 4. Данные: `reference/logs/2026-09-25_0312/` (v2.9.1-RU, сессия 20260925-024310, 30 мин). Шрифты: `reference/fonts/loose/` (+ `cmap_report.txt`), сканер cmap: `reference/tools/FontScan.cs` / `.exe`.

## Симптом
Русский текст шире английского и китайского оригинала; 1608 виджетов с переполнением, из них 1312 с кириллицей. Заголовки выглядят «кашей»: буквы слиплись из-за отрицательного `LetterSpacing`. Строк про шрифты или fallback в C7.log нет.

## Первопричина

### 1. Кириллицу в `Font_Aleo` рисуют китайские гарнитуры, а не Aleo
Почти весь текст идёт через `/Game/Arts/UI_2/Resource/Font/Font_Aleo.Font_Aleo` (`report/fonts.md`, `pre`: Title — 8395 виджетов, из них 5306 с кириллицей; Regular — 5173 и 3233). Из Lua не видно, какой face выбрал Slate, поэтому ширину глифа я восстановил по `overflow.csv`: для строк только из кириллицы и пробелов, без переноса, `(need/len − ls/1000·px) / px`, где `px = size·96/72` (Slate растеризует при 96 DPI):

| typeface | строк | ширина кириллической буквы, em (p10 / медиана / p90) |
|---|---|---|
| `Title` | 570 | 0,98 / **1,01** / 1,07 |
| `Regular` | 328 | 0,62 / **0,66** / 0,68 |
| `Font_Aleo` (неверное имя, см. п. 3) | 3 | 0,62 / 0,70 / — |

Сверка с шрифтами, которые лежат в игре открытыми файлами (`C7\Binaries\Win64\allin_data\font\`, скопированы в `reference/fonts/loose/`, проверены `FontScan`):

| файл | настоящее семейство | U+0400–04FF | 66 русских букв | ширина a–z / а–я, em |
|---|---|---|---|---|
| `Aleo_TitleNew.ttf` | **FZFW ZhuZi A Old Mincho** (Founder, китайский) | 66/256 | 66/66 | 0,500 / **1,000** |
| `SourceHanSansCN-Regular.otf` | Source Han Sans CN | 66/256 | 66/66 | 0,530 / **0,619** (А–Я 0,716) |
| `SourceHanSansCN-Medium.otf` | Source Han Sans CN Medium | 66/256 | 66/66 | 0,546 / 0,636 |
| `HYQiHei-55S.otf` | HYQiHei 55S (китайский) | 66/256 | 66/66 | 0,533 / 1,000 |
| `LastResort.ttf` (Engine/SlateDebug) | LastResort | 255/256 | 66/66 | 1,147 (заглушки) |

Вывод (совпадение до сотых):
- **Title** рисует кириллицу глифами китайского Old Mincho из набора GB2312. Они моноширинные, **1,0 em**, вдвое шире латиницы (0,5 em). Отсюда «разреженный» русский заголовок, и поэтому кто-то когда-то поставил `LetterSpacing` −120. Кириллица здесь не уходит в fallback: у этого face есть свои 66 букв, и Slate берёт их.
- **Regular** рисует кириллицу глифами Source Han Sans (пропорциональная, 0,62–0,72 em). Это гротеск без засечек, по стилю не совпадает с Aleo, но по ширине терпимо.
- Сам Aleo (латинский slab) кириллицы не содержит. Имя `Aleo_TitleNew.ttf` у файла webview-SDK вводит в заблуждение: файл с этим именем — FZ Mincho.
- Оговорка: `allin_data` — шрифты встроенного webview (логин, вики), а не UE-ассеты. Что UE-face в `Font_Aleo` те же самые, доказывают совпадение метрик и проба из п. «План, шаг 1», которая прочитает структуру CompositeFont напрямую.

### 2. Наш `translateTextWidget` сжимает текст вместо смены шрифта
`patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua`:
- `:3444-3453` — `targetLs = isTitleName and -120 or -60` для любой кириллицы; значение пишется и в виджет, и в `font.LetterSpacing` (`:3495`). Авторский `ls_pre` у заголовков при этом **положительный** (24, 40, 60; `overflow_top.md`, столбец `ls_pre→ls`).
- `:3497-3534` — размер подбирается по длине строки (`> 14` → 14, `> 10` → 15, `> 6` → 16, `baseSize > 20` → 18/20). С моноширинной кириллицей 1,0 em это не спасает: `Shops_Panel / Text_ItemName` «Книга военных заслуг: Битва за Трон Божий» — `need 1009 > have 248` даже при 21→14 и −120.
- Доля: в этой сессии у **1132 из 1608 (70%)** переполненных виджетов итоговый `LetterSpacing` отрицательный (в первой короткой сессии было 46 из 52). У 446 он был отрицательным уже до нашего снимка: мы же его и поставили при прошлом проходе.

### 3. Подмена шрифта (`StandardFontObject` / `CinematicFontObject`) почти ничего не делает, а в одном месте ломает typeface
- `Init.lua:1573-1580` при загрузке регистрирует `Font_Aleo` с typeface **`"Font_Aleo"`**: `registerFontCandidate(aleoObj, "Font_Aleo", "Slua_Preload")`. Такого typeface в шрифте нет. Это подтверждает `absru-s2-fonts.json`: `"standard_typeface":"Font_Aleo"`.
- `:3480-3493`: объект шрифта меняется, только если `font.FontObject ~= StandardFontObject`. У 13 568 виджетов (Title + Regular) шрифт уже Aleo, и для них замена не выполняется. Она срабатывает на единицах: `Font_Mistery` с кириллицей (9), `Font_Aleo_Update` (1), `Roboto` (4). Им ставится typeface `"Font_Aleo"`, отсюда в `fonts.md → post` строка `Font_Aleo | Font_Aleo | 20` (виджетов). Slate не находит такой typeface и берёт первый попавшийся.
- `isStandardFontObject` (`:1489-1514`) решает по подстрокам `"ui"`, `"regular"`, `"body"`, `"default"`… и может принять за стандартный любой шрифт. После предзагрузки `:1575` эта ветка уже не нужна.
- `CinematicFontObject` (`Font_Mistery`, typeface `TheLeon`) — декоративная латиница. После нашей обработки кириллицы в нём 0 (`post`), и это правильно: латинские надписи в TheLeon мы не трогаем.
- **Вывод:** после исправления шрифта глобальная подмена не нужна. Нужно одно узкое правило: не-Aleo шрифт (Mistery, Roboto, Aleo_Update) с кириллическим текстом → `Font_Aleo` с **настоящим** typeface (`Regular` или `Title`).

### 4. Мод-пак: проверить не удалось, и для этапа 4 он не обязателен
Что установлено чтением файлов (в папке игры ничего не менялось):
- `pakchunk0-Windows.utoc`: версия 8, `ContainerFlags = 0x0B` (Compressed | **Encrypted** | Indexed), `EncryptionKeyGuid` нулевой, то есть ключ по умолчанию зашит в exe. Метод сжатия — Oodle. Сам Oodle вкомпилирован статически, отдельной `oo2core*.dll` нет.
- `pakchunk0-Windows.pak`: `bEncryptedIndex = 1`, поле версии `0x8000000C` — нестандартный старший бит. Индекс зашифрован.
- У `pakchunk9999` и `pakchunk10001` нет `.utoc`, вместо него `.upak`. Там записи в стиле pak (offset/size/Kraken `8C 06`), то есть это собственный формат контейнера. В exe есть строки `.upak`, `signedpak`, `LogPakFile`, регэксп `(^|.*/)pakchunk0-[^/]+(\.|-|_).*`. Строки `~mods` нет (стандартный UE её и не содержит: монтирует все `*.pak` в `Content/Paks`).
- AES-ключа в репозитории и в CPDD нет. CPDD не добавляет свои паки, а патчит блоки внутри существующих контейнеров (BakedText, мост в `pakchunk0`). Это косвенный признак, что мод-пак у них не заработал или не пробовался.
- Версия движка: UE5 ≥ 5.1 (в exe есть сериализаторы Iris `FLastResortPropertyNetSerializer`). Точную версию найти не удалось: для кука UFont она нужна.
- Поддержку `.upak` в FModel/CUE4Parse не проверял: инструменты нужно скачивать, это решение пользователя (AGENTS.md и правила безопасности). Для ответа на главный вопрос этапа выгрузка ассетов больше не нужна: face и их cmap определены выше, а точную структуру CompositeFont даст Lua-проба.

### 5. Запасной путь через Lua существует
- В exe есть UFUNCTION **`FlushFontCache`** (в библиотеке рядом с `TrimMemory`, `UpdateCrashReportValue`, `GenerateWayPointNet`; строка профайлера `LuaFlushFontCache` рядом с `UC7FunctionLibrary::…`). Скорее всего, это `import("C7FunctionLibrary").FlushFontCache()`: сброс кэша шрифтов Slate, который нужен после правки CompositeFont в рантайме.
- `UFont.CompositeFont` — UPROPERTY (`DefaultTypeface.Fonts[]`, `FallbackTypeface`, `SubTypefaces[]` с `CharacterRanges`). Через slua его можно прочитать и, возможно, записать. Это и проверяет шаг 1.
- Ограничение Lua: новый TTF в рантайме не подключить, `UFontFace` из файла в shipping не создать. Можно использовать только face, которые уже есть в игре: Source Han Sans (Regular), Roboto (engine) и т. п.

### 6. Какая доля переполнений уйдёт после смены шрифта
Модель на `overflow.csv`: однострочные записи с кириллицей (1153 из 1608). Ширина кириллицы Title 1,0 → 0,60 em, Regular 0,64 → 0,60 em; размеры шрифта оставляем текущими; предел — `have` / `parent_have` по `kind`.

| вариант | помещается | доля от 1153 |
|---|---|---|
| A. новый шрифт + `LetterSpacing = 0` | 559 | **48%** (Title 457/703 = 65%, Regular 101/447 = 23%) |
| B. новый шрифт + авторский `ls_pre` | 553 | 48% |
| C. новый шрифт + авторские `ls_pre` **и** `size_pre` | 296 | 26% |
| D. только `LetterSpacing = 0`, шрифт прежний | 192 | 17% |

- После этапа 4 уйдёт **~560 из 1608 (~35%)**, остальные **~1050** — работа этапа 5: 594 однострочные строки с кириллицей, которые не помещаются и с новым шрифтом, плюс записи с переносом (50), без кириллицы (296) и без шрифта в записи (176; эти группы пересекаются).
- Вариант C показывает, что подгонка размера всё ещё нужна (при авторских размерах помещается вдвое меньше). Поэтому пороги по длине в этой задаче **не трогаем**: их заменит подгонка по измерению на этапе 5.
- Оговорка: 1233 записи имеют `kind = parent`. Часть из них может быть ложной (родитель — узкий слот внутри прокрутки), поэтому оценка сверху. Реальную цифру даст повторная диагностическая сессия.

### 7. Какой шрифт подобрать
- **Путь Lua (этот TASK):** выбора нет, берём то, что уже в игре. Для кириллицы в Title — тот же face, что даёт кириллицу в Regular (Source Han Sans CN; если проба найдёт в `Font_Aleo` Bold/Medium-вариант — его для Title). Стиль — гротеск: это компромисс ради ширины.
- **Путь мод-пака (этап 4b, после v3.0 и только если проба пака пройдёт):** шрифты OFL с полной кириллицей, похожие на Aleo (slab) и на викторианский стиль игры:
  - основной (Regular): **Bitter** или **Roboto Slab** — slab-serif, как Aleo, хорошо читаются на 14–20 pt;
  - заголовки (Title): **PT Serif** (Bold / Caption) — классическая антиква ParaType с сильной кириллицей; декоративная альтернатива — **Old Standard TT** (стиль XIX века) или **Cormorant Garamond SemiBold** (только для крупных кеглей ≥ 24 pt);
  - критерий приёмки: `reference/tools/FontScan.exe` — средняя ширина а–я ≤ 0,60 em, все 66 букв. Шрифты скачивает пользователь (или даёт на это явное разрешение) в `reference/fonts/candidates/`.

## План

Все изменения — в `Init.lua` и `AbsruDiagnostics.lua`, версия **v2.9.2-RU** (строка версии в `Init.lua`, `registered …`, `active hooks_installed=`). Диагностика только наблюдает (DIAGNOSTICS.md); эксперимент включается отдельным dev-флагом.

1. **Проба CompositeFont (диагностика, флаг `Fonts`).** В `AbsruDiagnostics.lua` один раз после `D.Start` (в тике, в бюджете, всё через `pcall`) для путей `Font_Aleo`, `Font_Mistery`, `/Game/Arts/UI_Update/Resource/Font/Font_Aleo_Update.Font_Aleo_Update`, `/Engine/EngineFonts/Roboto.Roboto` через `slua.loadObject` прочитать `CompositeFont`:
   - `DefaultTypeface.Fonts[i]`: `Name`, `Font.FontFaceAsset` (путь), `Font.LoadingPolicy`, `Font.Hinting`;
   - `FallbackTypeface.Typeface.Fonts[i]` (то же) и `FallbackTypeface.ScalingFactor`;
   - `SubTypefaces[i]`: `Cultures`, `ScalingFactor`, `CharacterRanges[j]` (нижняя и верхняя граница; если slua не отдаёт `FInt32Range`, записать `tostring` и тип), `Typeface.Fonts[k]`.
   
   Добавить в `fonts.json` раздел `"composite": {<путь>: {...}}`. В `session.json → api` записать `C7FunctionLibrary` (удался ли import), `C7FunctionLibrary.FlushFontCache` (тип поля), `UFont.CompositeFont` (читается ли). **Ничего не вызывать и не записывать** в объекты игры. В `CollectDiagLogs.ps1` (раздел `fonts.md`) вывести `composite` таблицей: шрифт → typeface → face → диапазоны.
2. **Исправить typeface при предзагрузке.** `Init.lua:1577`: регистрировать `Font_Aleo` без имени typeface (`nil`), чтобы `StandardTypefaceFontName` не становился `"Font_Aleo"`. Эвристику `registerFontCandidate` / `isStandardFontObject` по подстрокам (`:1489-1571`, вызовы `:3474`, `:3556`, `:3711`, `:8409`, `:9383`) заменить фиксированными путями: `StandardFontObject` = `Font_Aleo` (`slua.loadObject` + `AddToRoot`, как сейчас), `CinematicFontObject` = `Font_Mistery`. Функции, которые больше никто не вызывает, удалить.
3. **Сузить подмену шрифта** (`:3478-3493`, `:9377-9384`). Менять `FontObject` только если текст содержит кириллицу **и** шрифт не `Font_Aleo` (Mistery, Aleo_Update, Roboto). Typeface ставить настоящий: `Title`, если исходный typeface содержит `Title`, иначе `Regular`. Шрифт Aleo не трогать вообще.
4. **Убрать отрицательный `LetterSpacing`** (`:3444-3453`, `:3495`). Для кириллицы `targetLs = 0`; `-120` и `-60` удалить. Для текста без кириллицы `LetterSpacing` не трогать: сейчас мы затираем авторские 24–60 нулём, а по варианту B разницы для кириллицы нет. Окончательное правило (`max(0, авторский)` с подгонкой по измерению) — этап 5. Пороги размера `:3497-3534` оставить как есть (см. вариант C).
5. **Кириллица в Title — пропорциональная.** Режим задаётся полем `CyrillicFont` в `absoluteru_dev.lua` (для экспериментов) и константой в `Init.lua` (для релиза). Значения: `"typeface"` (по умолчанию для v2.9.2), `"subfont"`, `"off"`.
   - `"typeface"`: в `translateTextWidget`, если в тексте есть кириллица, шрифт `Font_Aleo` и typeface `Title`, поставить typeface, который даёт пропорциональную кириллицу. По умолчанию `Regular`; если проба из шага 1 покажет Bold/Medium с тем же face, что у Regular, — его. Rich text (`:3540-3559`) не трогать: там шрифт задаёт TextStyleSet, и правка ломает материалы (комментарий в коде).
   - `"subfont"` (экспериментальный, только по dev-флагу): один раз при старте `Init.lua` добавить в `Font_Aleo.CompositeFont.SubTypefaces` запись `{CharacterRanges = [0x0400–0x045F], Typeface.Fonts = [{Name="Title", face Regular}, {Name="Regular", face Regular}]}`, записать структуру обратно (`font.CompositeFont = cf`) и вызвать `C7FunctionLibrary.FlushFontCache()`, если он есть. Каждый шаг — в `pcall` с `report(...)` результата: `[CPDDRuntimeFix] cyrillic font mode=subfont write=<ok|err> flush=<ok|missing|err>`. Если запись или сброс не удались — откат в `"typeface"`. Этот режим не требует обходить каждый виджет, но идёт только после положительной пробы в игре.
   - Одна строка в C7.log при старте (через `report`, `Log.Info`): `[CPDDRuntimeFix] cyrillic font mode=<…> title_typeface=<…>`.
6. **Проверки и документы.** `tools/VerifyPatch.ps1` (синтаксис `Init.lua` и `AbsruDiagnostics.lua`); `git diff` — только `Init.lua`, `AbsruDiagnostics.lua`, `CollectDiagLogs.ps1` (UTF-8 **с BOM**), документы. В `docs/LESSONS.md` — урок «Title рисует кириллицу китайским Mincho 1,0 em; лечить шрифтом, а не LetterSpacing» (коротко, со ссылкой на TASK-006). В `docs/DIAGNOSTICS.md` — раздел `composite` в `fonts.json` и флаг `CyrillicFont`. В `ROADMAP.md` — статус этапа 4. Закоммитить. Релиз не публиковать без решения пользователя.
7. **Этап 4b (мод-пак) в этом TASK не делать**, только записать в ROADMAP как отдельную исследовательскую задачу:
   - (a) пробный legacy-`.pak` с одним Lua-файлом: грузит ли игра дополнительные паки (Init.lua пробует `require` и пишет `pak-probe ok/miss`);
   - (b) при успехе — IoStore-контейнер с `Font_Aleo`, в котором добавлен SubTypeface с Bitter / PT Serif. Нужен UE той же версии для кука UFont / UFontFace;
   - инструменты (repak / UnrealPak / FModel / retoc) скачивает пользователь.

## Проверка

**Автоматическая:** `tools/VerifyPatch.ps1` — OK; `git diff --stat` — только файлы из шага 6; поиск `-120` / `-60` рядом с `LetterSpacing` в `Init.lua` ничего не находит; строка `"Font_Aleo", "Slua_Preload"` исчезла.

**Чек-лист для пользователя в игре** (установить сборку v2.9.2-RU, диагностика включена `absoluteru_dev.lua` как в DIAGNOSTICS.md):
1. В C7.log есть `v2.9.2-RU active hooks_installed=` и `[CPDDRuntimeFix] cyrillic font mode=typeface title_typeface=Regular` (или имя, выбранное по пробе).
2. Магазин (`Shops_Panel`), список товаров: названия вида «Книга военных заслуг: …» набраны пропорциональным шрифтом, буквы не слиплись и не разрежены; строки короче, чем в v2.9.1.
3. Главное меню, Esc-меню, заголовки панелей (Title): кириллица без наложения букв. Латинские надписи в декоративном TheLeon (`Font_Mistery`) не изменились.
4. Подсказка предмета, диалог с NPC (Regular и RichText): текст выглядит как в v2.9.1, без пурпурных квадратов и пустых мест.
5. Пройти маршрут из DIAGNOSTICS.md (чек-лист, п. 5), постоять 30–40 с, закрыть игру, запустить `tools\CollectDiagLogs.ps1`. В `report/fonts.md` должен появиться раздел `composite` (face у Title / Regular), в `REPORT.md → api` — `C7FunctionLibrary.FlushFontCache`. В `overflow_top.md` переполнений заметно меньше 1608 (ожидание ~1000–1100 при похожем маршруте) и нет `ls` −60 / −120.
6. (Необязательно, только после п. 5) В `absoluteru_dev.lua` добавить `CyrillicFont = "subfont"`, перезапустить. В C7.log найти `cyrillic font mode=subfont write=… flush=…` и прислать строку. Если `write=ok flush=ok`, сравнить заголовки с режимом `typeface`.

## Промпт для чата исполнения
> Ты — чат исполнения проекта AbsoluteRU (AGENTS.md §3, чат 2). Прочитай AGENTS.md, docs/LESSONS.md, docs/DIAGNOSTICS.md, docs/tasks/ROADMAP.md и выполни docs/tasks/TASK-006-font.md, раздел «План», шаги 1–6 (шаг 7 только записать в ROADMAP). Главное из анализа: Title-typeface `Font_Aleo` рисует кириллицу китайским FZ Old Mincho шириной 1,0 em, Regular — Source Han Sans 0,62 em; наш `translateTextWidget` компенсирует это `LetterSpacing` −120/−60, а при предзагрузке ставит несуществующий typeface `"Font_Aleo"` (Init.lua:1577). Сделай: пробу CompositeFont в AbsruDiagnostics (только чтение, раздел `composite` в fonts.json + вывод в CollectDiagLogs), фиксированные StandardFontObject/CinematicFontObject вместо эвристик, узкую подмену шрифта только для не-Aleo с кириллицей, `LetterSpacing` 0 для кириллицы (без отрицательных), режим `CyrillicFont = "typeface"` (Title → Regular для кириллицы; RichText не трогать) и экспериментальный `"subfont"` только по dev-флагу с откатом. Пороги размера по длине не трогать (этап 5). Версия v2.9.2-RU. Проверь `tools/VerifyPatch.ps1`; `.ps1` с кириллицей сохраняй в UTF-8 с BOM, Lua — UTF-8 без BOM, LF. Не пиши «исправлено»: дай пользователю чек-лист из раздела «Проверка». Закоммить и запушь в main; релиз не публикуй без решения пользователя. В папку игры ничего не пиши и игру не запускай.
