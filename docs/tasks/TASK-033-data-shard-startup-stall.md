# TASK-033 — v3.1.0-RU: старт подвисает на 4–12 с, 1024 ошибки шардов в логе

Статус: этап 1 в коммите 2191e2b9, проверен в игре 15.10. Этап 2A (выгрузка ключей StringDB, `StringDbDump`, `StringDbGaps -ImportKeys`) реализован, ждёт dev-сессии пользователя (чек-лист 2A). Этап 2B — после выгрузки. Основа: коммит a3f8db67 (TASK-032, этап A).

## Симптомы (C7.log пользователя, только чтение)

| Лог | Версия | Ошибок `external mapping …RuntimeTextGemini_*` | Трейсбеков CrashSight | `installed translated localization lookup` → `installed safe KSBC missing-table fallback` |
|---|---|---|---|---|
| `C7-backup-2026.10.12-21.50.39.log` | v3.0.11 (compile ok) | 0 | 0 | 00:32:36.649 → 00:32:38.208 = **1,56 с** |
| `C7-backup-2026.10.15-16.06.40.log` (запуск 19:04) | v3.1.0 | 1024 | 2049 | 19:05:00.804 → 19:05:12.731 = **11,9 с** |
| `C7.log` (запуск 19:07) | v3.1.0 | 1024 | 2048 | 19:08:03.473 → 19:08:07.442 = **4,0 с** |

- `bootstrap.lua:112 compile probe startup=ok` (кадр 0), затем `Init.lua:1364 shard load path=data compile=fail (text mode is not supported at all) startup=ok` (кадр 699/738): VM отключает компиляцию исходника между загрузкой bootstrap и `KsbcMgr.Init`.
- Лог раздут до 51–55 тыс. строк (v3.0.11: 12,8 тыс.): на каждый шард 2 ошибки и 2 стека по ~25 строк.

## Первопричина

### Кто трогает все 1024 шарда
Стек из `C7.log:105–128` и `130–153`:
`KsbcMgr.lua:45 require` (StringDB-модуль из `Loader.Overlays`) → `bootstrap.lua:501` (обёртка `external_searcher`) → `merge_overlay` `bootstrap.lua:432–442` (цикл по **всем** строкам StringDB) → `Loader.TranslateDatabaseString` `Init.lua:12598` → `lookupGeminiText` `Init.lua:2262` → `runtimeFixes.loadDataModule` `Init.lua:2186`.
Хеш-префикс текста строк StringDB покрывает все 1024 префикса, поэтому за один `require` загружаются все шарды. Так было и в v3.0.11 (`git show f6ed781f:…/Init.lua` — тот же шаг 3 `lookupGeminiText(cnValue)`, а `merge_overlay` той версии тоже вызывал translator на каждую строку). Само массовое чтение не новое: в v3.0.11 оно стоило ~1,5 с через `require` + компиляцию LuaJIT. Новое — то, **как** грузится каждый шард.

### Что стоит каждый шард в data-режиме (`Init.lua:2184–2208`, `bootstrap.lua:70–99`, `490–531`)
1. `pcall(require, moduleName)` (`Init.lua:2186`) идёт по `package.loaders`:
   - наш `external_searcher` → `read_chunk`: `File.LoadFile` (чтение 1, ~52 КБ), `loadfile(<path>.compat.luac)` (файла нет), `loadfile(path)` (чтение 2, отказ компиляции), `load(source)` (отказ) → `report(...)` = `Log.Error` + стек CrashSight (`bootstrap.lua:529`, `:64`);
   - штатный поисковик Slua (поиск в паках) → `Slua: Error: Can't load file …` + второй стек CrashSight.
2. Data-путь: `fileLibrary.LoadFile` (чтение 3) + `parseDataLiteral` (разбор ~52 КБ на чистом Lua).

Итого на старте: 3 чтения × 1024 файла (52,2 МБ исходника, 3 × 52 МБ), 2048 ошибок со стеками, разбор 52 МБ в Lua.

### Замер по меткам времени (скрипт по логам, мс)
| Интервал на шард | 19:04 (сумма / сред. / макс.) | 19:07 (сумма / сред. / макс.) |
|---|---|---|
| ошибка `external mapping` → `Slua Can't load file` (1-й стек + поиск в паках) | 309 / 0,30 / 3 | 200 / 0,20 / 6 |
| `Can't load file` → ошибка следующего шарда (2-й стек + чтение 3 + parse + строки StringDB до следующего промаха + `read_chunk` следующего шарда: чтения 1–2) | 11 026 / 10,8 / 175 | 3 265 / 3,2 / 30 |

Выводы:
- Сами строки лога дешёвые: ~0,2–0,3 мс на стек, ~0,5 с на 2048 стеков. Главная цена — не в логировании.
- Остаток (3,2 мс/шард в «тёплом» запуске против ~1,5 мс/шард в v3.0.11, где было одно чтение + компиляция в C) приходится на 3 чтения файла и разбор в Lua. Разделить чтение и parse по логу нельзя: в штатном режиме нет промежуточных меток. Нужен замер в игре (этап 1, п. 2).
- Разброс 11,9 с / 4,0 с между двумя запусками подряд одного патча — вероятно, холодный файловый кэш и фоновая нагрузка на первом запуске после обновления. Это не подтверждено, но в любом случае каждое лишнее чтение умножает стоимость холодного старта.

## План

### Этап 1 (обязательно, подтверждено логами)
1. **Data-only после отказа компиляции.** `runtimeFixes.loadDataModule` (`Init.lua:2184`):
   - если `package.loaded[moduleName]` уже таблица — вернуть её (маршрут из `Loader.ChunkRoutes` или `"require"`);
   - флаг модуля `dataOnly` (локальный в блоке `do`): вычисляется один раз при первом вызове как `Loader.CompileProbe() ~= "ok"`; дополнительно ставится в `true`, если `require` упал с текстом `text mode is not supported`;
   - при `dataOnly == true` сразу `File.LoadFile` + `parseDataLiteral`, **без** `require`: нет `read_chunk`, нет чтений 1–2, нет обеих ошибок и стеков;
   - при компиляции `ok` всё как сейчас (`require` → companion/loadfile/load).
   Это касается всех пользователей `loadDataModule`: шардов (`Init.lua:2262`), `WidgetNameIndex` (`Init.lua:5271`), LSI (`Init.lua:5637`).
   Строку `shard load path=… compile=… startup=…` (одна в любом режиме, TASK-032) оставить.
2. **Замер фаз только в диагностике.** В `runtimeMetrics` (`Init.lua:~1370`) добавить `DataReadMillis`, `DataParseMillis`, `DataRequireMillis`, `DataLoads` (через `nowMilliseconds()` вокруг `LoadFile`, `parseDataLiteral`, `pcall(require)`). Одна строка `[CPDDRuntimeFix] data load stats loads=… require_ms=… read_ms=… parse_ms=… shard_ms=<GeminiShardLoadMillis>` выводится только при `runtimeFixes.Diag` (DiagnosticsMode или `absoluteru_dev.lua`), один раз — после первого `merge_overlay`. Проще всего вывести её из Init в обработчике, который вызывает bootstrap рядом со строкой `[LOMPerf] overlays` (`bootstrap.lua:~563`), например через `Loader.DataLoadStats`, если эта функция задана. В обычном режиме лог тихий.
3. **Офлайн-проверка:** `tools/VerifyPatch.ps1`, `tools/LuaDataCheck.exe` (парсер не меняется — должно остаться 0 расхождений), `tools/InstallerCoreTests.exe`. Сборка `tools/PackageRelease.ps1` без `-Publish` до проверки пользователем.

Ожидание (оценка, проверяется в игре): 0 строк ошибок шардов; интервал «localization lookup → KSBC fallback» в тёплом запуске меньше текущих 4,0 с — минус два чтения и поиск в паках на шард. Точное число даст строка `data load stats`.

### Этап 2 — варианты до замера (исторически; решение — раздел «Этап 2: компактные пакеты StringDB» ниже)
- **C. Прекомпиляция в bootstrap, пока компиляция работает** (предпочтительно, если `parse_ms` больше ~1000). На кадре 0 `compile probe startup=ok`: bootstrap может сделать `load(File.LoadFile(path))` для данных шардов и хранить функции в `Loader.PrecompiledData[relative]`, а `loadDataModule` берёт оттуда. Это возвращает стоимость v3.0.11 (~1,5 с), но переносит её на заставку (кадр 0) и держит скомпилированные функции в памяти до первого вызова. Перед внедрением нужно замерить в игре время кадра 0 и `memory_kb` (`[LOMPerf] phase=…`).
- **B. Ускорение `parseDataLiteral`** (если parse дорог, а C не подходит): быстрый путь в `parseString` (строка без escape → сразу `text:sub`, без `parts`/`table.concat`); в `skip()` заменить `text:sub(pos, pos + 1) ~= "--"` на сравнение байтов без аллокации. Любое изменение парсера зеркально переносится в `PortParser` в `tools/LuaDataCheck.cs`; критерий — 0 расхождений на всех 1281 файлах. Посимвольного прохода в текущем парсере уже нет (`string.find` по классам), поэтому выигрыш ограничен аллокациями.
- **Ленивая загрузка — не рекомендуется.** Строки StringDB нужны переведёнными сразу после `require` в `KsbcMgr.Init`, а таблица `data` — обычная таблица, которую игра читает напрямую и обходит через `pairs`. Прокси через `__index` не сработает, пока в таблице лежат китайские значения, и ломает `pairs`/`rawget`. Отложенный `merge_overlay` даст китайский текст в первых экранах.

## Чек-лист для пользователя (после этапа 1)
1. Установить сборку и запустить игру дважды подряд, дойти до главного меню.
2. В `Saved\Logs\C7.log`:
   - 0 строк `external mapping mods.cpdd_runtime_fixes.RuntimeTextGemini` и `Can't load file mods.cpdd_runtime_fixes`;
   - есть строка `shard load path=data compile=fail (text mode is not supported at all) startup=ok`;
   - интервал между `installed translated localization lookup` и `installed safe KSBC missing-table fallback` в обоих запусках (было 11,9 с и 4,0 с, в v3.0.11 — 1,6 с);
   - размер лога снова порядка 12–15 тыс. строк.
3. Интерфейс и StringDB-тексты на русском, как в v3.1.0.
4. Для этапа 2: один запуск с `Saved/Mods/lua/absoluteru_dev.lua` и прислать строку `data load stats …`.

## Этап 2: компактные пакеты StringDB (анализ 15.10)

### Факты после этапа 1 (логи пользователя, только чтение)
| Лог | `data load stats` | `localization lookup` → `KSBC fallback` |
|---|---|---|
| `C7-backup-2026.10.15-16.21.47.log` (холодный) | `loads=1025 data_only=true read_ms=8548 parse_ms=1722 shard_ms=10265` (строка 469) | 19:20:23.187 → 19:20:34.059 = **10,9 с** |
| `C7-backup-2026.10.15-16.23.25.log` (тёплый) | `read_ms=1088 parse_ms=1501 shard_ms=2590` (строка 468) | 19:23:07.396 → 19:23:10.591 = **3,2 с** |
| `C7.log` (тёплый) | — | **2,9 с** |

- `translation overlays applied modules=1 entries=63575`: на старте сливается один модуль `Data.Excel.LanguageData.StringDB_CN_Data`, 63 575 строк получают перевод. Остальные 37 модулей из `Loader.Overlays` (`translation-overrides.lua:13–52`) грузятся позже, по требованию игры.
- `startup metrics gemini_loads=1024`: ради этого модуля читаются все 1024 шарда.
- Вне шардов на интервал приходится ≈ 0,6 с (3,2 − 2,59; 10,9 − 10,27): FNV-хеш каждой строки в `getShardPrefix` (`Init.lua:2047`, цикл по байтам на Lua), `lookupGeminiTextFuzzy` для промахов, прочая работа `KsbcMgr.Init`.
- Диск с игрой — NVMe SSD. Холодное чтение 8,5 с / 1024 файла = 8,3 мс на файл 53 КБ; тёплое — 1,0 мс. Для NVMe это цена открытия файла (вероятно, проверка антивирусом при первом открытии и обёртка `File.LoadFile`), а не пропускная способность диска. Значит, на холодном старте важно в первую очередь **число файлов**, во вторую — байты.

### Данные (замеры в репозитории)
- Шарды: 1024 файла, 54 773 766 байт, 276 398 записей (222–325 на шард). Ключи с иероглифами: 140 801 запись, 28,6 МБ (в среднем 203 байта на запись); прочие (EN-ключи, алиасы) — 135 597 записей, 26,0 МБ.
- Батчи `batch_001…027` (прокси основного массива StringDB): 130 317 уникальных `source_cn`, в среднем cn 52 байта, ru 115 байт.
- Промахи StringDB из диагностики (`reference/logs/2026-10-12_2129`, 12 сессий, старый билд): в `StringDB_CN_Data` **1485** уникальных непереведённых значений, разбросаны по **793** шардам из 1024 (с иероглифами 1245 → 709 шардов); 240 из них — бинарные base64-блобы (cn = en, ~190 КБ).
- Офлайн-выгрузки китайского StringDB нет: `reference/cpdd/*/…/StringDB_CN_Data*.lua` — байткод LuaJIT с английским по ID (`1B 4C 4A`). Точное число уникальных cn текущего билда даст только выгрузка из игры (этап 2A).

### Вывод
Переводу StringDB на старте нужно ≈ 63,6 тыс. пар cn → ru из 276 тыс. Оценка компактного пакета для основного модуля: ≤ 63 575 × ~180 байт ≈ **11–12 МБ** (21 % объёма шардов) в **одном** файле, плюс ~1,5 тыс. отрицательных ключей (~0,3 МБ). Отрицательные ключи обязательны: без них 1485 промахов по-прежнему поднимут ~793 шарда, и выигрыша не будет.

Ожидание по пропорции замеров (проверяется в игре): чтение ≈ 0,2 с тёплое и 0,1–1,8 с холодное (нижняя граница, если цена — открытие файла, верхняя — если байты), разбор ≈ 0,33 с, FNV для попаданий не нужен (−0,5 с). Интервал `localization lookup → KSBC fallback` ≈ **0,6–0,8 с** тёплый и **0,7–2,4 с** холодный (сейчас 3,2 / 10,9 с, в v3.0.11 — 1,6 с).

### Сравнение вариантов
| Вариант | Чтение на старте | Холодный старт (оценка) | Минусы |
|---|---|---|---|
| Сейчас | 1024 файла, 54,7 МБ, разбор 54,7 МБ, FNV на 63,6 тыс. строк | 10,9 с (тёплый 3,2) | — |
| **E. Пакеты StringDB из выгрузки ключей (рекомендуется)** | 1 файл ~11–12 МБ | 0,7–2,4 с | нужна выгрузка cn из игры на каждый билд (dev-сессия); C#-порт fuzzy |
| A. Слить шарды в 1–16 файлов | 1–16 файлов, 54,7 МБ | ~3 с (убирает цену открытий, остаются разбор 1,5 с + FNV 0,6 с + байты) | UI-поиск по одному префиксу тянет целую «корзину» — рывки во время игры |
| B. Ускорить `parseDataLiteral` | как сейчас | ~10 с (разбор −0,3…0,5 с из 1,5) | холодное чтение 8,5 с не трогает; парсер и `PortParser` меняются синхронно |
| C. Прекомпиляция в bootstrap | 1024 файла на кадре 0 | ~10 с, только на заставке | чтение остаётся (отклонён) |
| D. Кеш, который пишет сам мод (`SaveStringContentToFile`) после первого старта | 1 файл со 2-го старта | первый старт после установки/обновления — те же 10,9 с | инвалидация, частично записанный файл, чистка установщиком; кодировка `SaveStringContentToFile` для не-ASCII не проверена (`AbsruDiagnostics.lua:26`). Резерв, если выгрузка всех модулей невозможна |

### Почему пакет совместим с `TranslateDatabaseString`
`merge_overlay` (`bootstrap.lua:432–442`) вызывает `translator(nil, cn, key, name)`, то есть `enValue == nil`. Порядок в `Init.lua:12614–12657`:
1. `aggregateOverrides[rowId]`, 2. `splitOverrides[tag][rowId]` — встроенные таблицы, шарды не нужны, остаются **до** пакета без изменений;
3. `lookupGeminiText(cn) or lookupGeminiTextFuzzy(cn)` — результат зависит **только от cn** и шардов. Именно этот шаг заменяет пакет: `pack[cn]` = итог шага 3 (строка) или `false` (шаг 3 не нашёл);
4. по `enValue` — в merge не выполняется (`nil`);
5. `visibleTextExactOverrides`, `Diag.OnDbMiss` — без изменений, выполняются при `false`, как сейчас при промахе.

От ключа строки (rowId) и модуля зависят только шаги 1–2, они остаются в рантайме. Поэтому пакет можно строить по cn, без rowId: ID строк между билдами меняются (TASK-032), cn — источник истины.

Обновление игры: cn, которых нет в пакете (`pack[cn] == nil`), идут старым путём (шард по требованию). Результат верный, медленнее только для изменённых строк; при массовых изменениях старт деградирует до нынешнего, пока не сделана новая выгрузка.

Тонкости C#-порта fuzzy (`Init.lua:2342–2404`): шаблоны Lua работают с **байтами**. `%s` — пробел, `\t \n \v \f \r` (как `TrimLuaSpace` в `ShardCompiler.cs:439`); классы `[:：%-%?%.]` и `[%[%{%(【]` / `[%]%}%)】]` содержат многобайтовые символы и совпадают с **отдельными байтами** UTF-8 (`EF BC 9A`, `E3 80 90/91`), поэтому `.-` может разрезать символ. Порт работает на байтовых строках (Latin-1 1:1, как `LuaDataCheck.cs:20`) и повторяет рекурсию и порядок шагов дословно. Шаг 5 fuzzy (`Level`/`Lv`) — тоже.

### План этапа 2

#### 2A. Выгрузка ключей StringDB (dev-only) и рефакторинг шага 3
1. `Init.lua`: вынести шаг 3 `TranslateDatabaseString` в `runtimeFixes.resolveStringDbText(cn)` (логика без изменений) и открыть `runtimeFixes.sourceKey` (`Init.lua:2026`).
2. `AbsruDiagnostics.lua`: флаг `StringDbDump = true` в `absoluteru_dev.lua` (по умолчанию выключен). В `D.Tick()` после `after_main`:
   - для каждого имени из `Loader.Overlays` модуль загружается, если ещё не загружен (`pcall(require, name)`; это dev-сессия, остановка допустима), и берутся `Loader.OverlayOriginals[name]`;
   - по каждому модулю — уникальные строковые значения; запись `{"src":"stringdb_key","module":…,"cn":…,"res":<sourceKey(resolveStringDbText(cn)) или null>}`. Без обрезки `DB_TEXT_MAX`: предел записи 64 КБ, длиннее — счётчик `skipped_long`;
   - итог по модулю: `{"src":"stringdb_key_summary","module":…,"rows":…,"unique":…,"skipped_long":…,"version":VERSION}`;
   - отдельный поток `absru-s<slot>-stringdb-NNN.jsonl`, свой лимит 64 МБ (не `SessionMB`), `AsciiJson`, в бюджете кадра `FrameBudgetMs`;
   - одна строка в `C7.log`: `[AbsruDiag] stringdb dump done modules=… keys=… skipped_long=…`.
3. `tools/StringDbGaps.ps1 -ImportKeys -Logs <папка> -Sid <sid> -GameBuild <билд>`:
   - пишет `source/stringdb/stringdb_keys.json` (`{ "game_build", "patch", "sid", "modules": { "<module>": { "rows": N, "keys": [ … ] } } }`, модули и ключи отсортированы ordinal, UTF-8 без BOM, LF);
   - пишет `reference/stringdb_dump/<build>/resolved.json` (cn → `res`) для сверки порта.
   Ожидаемый размер `stringdb_keys.json` ≈ 65 тыс. × ~60 байт ≈ 4–6 МБ для основного модуля, плюс остальные модули. Это игровые исходные данные (как `source_cn` в батчах), поэтому они лежат в `source/` и коммитятся: без них ShardCompiler (и Stop-хук) не пересоберёт пакеты.
4. Сборка `tools/PackageRelease.ps1` без `-Publish`. Пользователь делает одну dev-сессию с `StringDbDump = true` (чек-лист 2A).

#### 2B. Пакеты, рантайм, проверки (после выгрузки)
1. `tools/ShardCompiler.cs`, после построения `shardMap`:
   - если есть `source/stringdb/stringdb_keys.json` — для каждого модуля `resolve(cn)` = C#-порт `lookupGeminiText` ∘ `lookupGeminiTextFuzzy` по `shardMap` (байтовая семантика, см. выше) и файл `StringDbPack<суффикс>.lua` в `cpdd_runtime_fixes/`: суффикс — часть имени модуля после `StringDB_CN_Data` (`""` → `StringDbPack.lua`, `_talk` → `StringDbPack_talk.lua`);
   - формат — тот же литерал, что и шарды (его читают `parseDataLiteral` и `LuaDataCheck`): заголовок `-- StringDB pack <module> game_build=<…> keys=<…> hits=<…> false=<…>`, `return {`, `["cn"] = "ru",` или `["cn"] = false,`, ключи отсортированы, экранирование `EscapeLua`;
   - лишние `StringDbPack*.lua` удаляются; нет файла ключей — пакетов нет, предупреждение в выводе;
   - `-CheckResolved <resolved.json>`: сравнить `sourceKey(resolve(cn))` с `res` из игры. Запускается один раз сразу после импорта, пока шарды совпадают со сборкой, на которой делалась выгрузка; критерий — **0 расхождений** (иначе порт fuzzy неверен).
2. `Init.lua`:
   - `stringDbPack(moduleName)`: лениво, один раз на модуль, `runtimeFixes.loadDataModule("mods.cpdd_runtime_fixes.StringDbPack" .. суффикс)`; нет файла или ошибка → `false`, работает старый путь. Ошибка разбора — одна строка в любом режиме (это поломка сборки), отсутствие файла — только в диагностике;
   - `TranslateDatabaseString`: шаги 1–2 без изменений; шаг 3: `v = pack[cn]`: строка → вернуть; `false` → пропустить шаг 3 (дальше шаг 5 и `OnDbMiss`); `nil` → `resolveStringDbText(cn)`, как сейчас, со счётчиками `unknown` и числа разных префиксов шардов;
   - без Lua 5.2 `goto` — флагом;
   - диагностика: в `Loader.DataLoadStats` добавить строку `stringdb pack module=… keys=… hits=… false=… unknown=… unknown_shards=… pack_ms=…` для каждого слитого модуля;
   - обычный режим: тихо. Одна строка только при устаревшем пакете (`unknown_shards >= 64` после слияния модуля): `stringdb pack stale <module> unknown=… shards=… — нужна новая выгрузка ключей`.
   UI-поиск (`translateVisibleText` и пр.) по-прежнему идёт в шарды, теперь они загружаются по требованию, а не все на старте.
3. `tools/LuaDataCheck.cs`: добавить `StringDbPack*.lua` в список файлов (булев `false` уже поддерживают оба читателя: `LuaDataCheck.cs:188`, `parseValue` в `Init.lua:2160`). Критерий — 0 расхождений.
4. `tools/VerifyPatch.ps1`: если есть `stringdb_keys.json` — для каждого модуля есть пакет, `game_build` в заголовке совпадает с файлом ключей; WARN, если `game_build` ключей ≠ `installer/supported_game.json → game_build` (пакеты устарели после обновления игры).
5. `tools/SyncCpdd.ps1:103`: `StringDbPack*` — сгенерированный компонент (как `shards`), не CPDD. `.ignore`: исключить `StringDbPack*`. `.claude/hooks/recompile-shards.ps1`: запускать ShardCompiler и при изменении `source/stringdb/stringdb_keys.json`.
6. Установщик: код не меняется. `PackageRelease.ps1:101` перечисляет `patch_payload` целиком, новые файлы попадают в `owned_files.json`, ставятся и удаляются штатно. `InstallerCoreTests.exe` — прогнать.
7. Документация: `docs/PROJECT_MAP.md` (пакеты, `source/stringdb/`, `-ImportKeys`, `-CheckResolved`), `docs/DIAGNOSTICS.md` (`StringDbDump`, поток `stringdb`), процедура после обновления игры (ниже).
8. Проверка: `ShardCompiler.exe -CheckResolved` = 0, `LuaDataCheck.exe` = 0, `VerifyPatch.ps1`, `InstallerCoreTests.exe`; сборка без `-Publish` до проверки пользователем.

**Ход 2B (15.10, чат исполнения).** Выгрузки в логах ещё нет: последний запуск игры (19:28) раньше сборки 2A (19:49), в `reference/logs/2026-10-15_2004` нет `absru-s*-stringdb-*.jsonl` и строки `stringdb dump done`. По решению пользователя код 2B сделан и закоммичен без пакетов; импорт, `-CheckResolved`, пакеты и релиз — после dev-сессии.
- Сделано: порт и генерация (`StringDbPacks` в `ShardCompiler.cs`), `-CheckResolved`, `Init.lua` (`stringDbPack`, шаг 3, `Loader.OnOverlayMerged`, строки `stringdb pack …`), `LuaDataCheck`, `VerifyPatch`, `SyncCpdd`, `.ignore`, Stop-хук, документы. Порт проверен на синтетических ключах (trim, CRLF, теги, пунктуация `：`, скобки `【】` с разрезом байтов, `Level`/`Lv`), `-CheckResolved` ловит расхождение (код 3), `LuaDataCheck` 0 расхождений, `VerifyPatch` ловит устаревший `game_build`, `InstallerCoreTests` 319/0.
- Отступление от плана: всегда пишется `StringDbPackIndex.lua`, и `Init.lua` грузит только перечисленные в нём пакеты. Иначе при включённой компиляции поиск отсутствующего пакета логирует `external mapping … failed` (`bootstrap.lua:529`) в обычном режиме. Счётчики прохода закрывает новый вызов `Loader.OnOverlayMerged(name)` в конце `merge_overlay` (`bootstrap.lua`).
- Открытый вопрос: `supported_game.json → game_build` = базовый билд `1.2018737.2044036`, а выгрузка снимается на хотпатче 2218968 — WARN `VerifyPatch` о `game_build` будет всегда, пока в `supported_game.json` нет версии кеша.
- 16.10: полная выгрузка sid `20261016-200529` (`reference/logs/2026-10-16_2031`, ≈5 мин): 38/38 модулей, ключей 116 349, skipped_long/lossy/capped/failed = 0, ошибок модулей нет. `-ImportKeys`: уникальных cn 109 482, с переводом 101 292, без перевода 8 190. `-CheckResolved`: 0 расхождений. Пакеты: 38 шт. + индекс, ≈21,3 МБ, ключей с переводом 107 875. `LuaDataCheck` 0 различий, `VerifyPatch` OK (+ ожидаемый WARN `game_build`), `InstallerCoreTests` 319/0.
- Найдено попутно: строки `AbsruDiagnostics` через `warn()` после строки `session=…` (`stringdb dump start/done` и др.) не доходят до `C7.log` ни в одной сессии из `reference/logs`. Итог выгрузки сверялся по `stringdb_key_summary` в `absru-s*-stringdb-*.jsonl`. Ждать строку `dump done` в логе бесполезно; причину (`Log.Info` в `AbsruDiagnostics.lua:173`) разобрать отдельно.

#### 2C. Только по замеру: догрузка шардов в фоне
После 2B шарды грузятся при первом UI-поиске по префиксу (≈ 1 мс тёплый, ≈ 8 мс холодный). Если в диагностике (`shard_ms` за первые 120 с после `after_main`) или в игре заметны рывки на первых экранах — догружать по 4–8 шардов за тик таймера (`AddTimerWithFunction`, как в `Init.lua:4629`) после главного меню. Без замера не делать.

### Процедура после обновления игры (в `docs/DIAGNOSTICS.md`)
1. `SyncCpdd` / сборка под новый билд, как раньше. Пакеты старого билда остаются верными, новые cn идут через шарды.
2. Dev-сессия с `StringDbDump = true` → `CollectDiagLogs.ps1` → `StringDbGaps.ps1 -ImportKeys … -GameBuild <новый>` → `ShardCompiler.exe` (+ `-CheckResolved`) → коммит `source/stringdb/stringdb_keys.json` и пакетов.
3. Признак, что выгрузка нужна: строка `stringdb pack stale` в `C7.log` или WARN `VerifyPatch`.

## Чек-лист для пользователя (этап 2A — выгрузка)
1. Установить тестовую сборку. В `Saved/Mods/lua/absoluteru_dev.lua` добавить `StringDbDump = true` (вместе с `Enabled = true`).
2. Запустить игру, дойти до главного меню и подождать 1–2 минуты.
3. В `C7.log` есть строка `[AbsruDiag] stringdb dump done modules=38 keys=…`; в `Saved/Mods/logs/` появились файлы `absru-s*-stringdb-*.jsonl`.
4. Сообщить в чат — логи забираются `tools/CollectDiagLogs.ps1`. После этого выключить `StringDbDump`.

## Чек-лист для пользователя (этап 2B — пакеты)
1. Установить сборку. Перезагрузить ПК (холодный кеш), запустить игру и дойти до главного меню; закрыть и запустить ещё раз.
2. В `Saved\Logs\C7.log` обоих запусков:
   - интервал `installed translated localization lookup` → `installed safe KSBC missing-table fallback` (было 10,9 с холодный и 3,2 / 2,9 с тёплый; ожидание ≈ 0,7–2,4 с и ≈ 0,6–0,8 с);
   - `startup metrics gemini_loads=…` — заметно меньше 1024 (шарды только для UI);
   - `translation overlays applied modules=1 entries=63575` — число не меньше прежнего (тот же перевод);
   - нет строки `stringdb pack stale` и ошибок `StringDbPack`.
3. Интерфейс, предметы, задания — на русском, как в v3.1.0. Открыть диалог, письмо, газету, Автошахматы (модули StringDB, которые грузятся позже): без заметной паузы при первом открытии.
4. Нет рывков при первом открытии меню (инвентарь, навыки). Если есть — сообщить (этап 2C).
5. Один запуск с `absoluteru_dev.lua` (без `StringDbDump`): прислать строки `data load stats …` и `stringdb pack …`.