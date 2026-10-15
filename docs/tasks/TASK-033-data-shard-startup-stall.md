# TASK-033 — v3.1.0-RU: старт подвисает на 4–12 с, 1024 ошибки шардов в логе

Статус: анализ завершён, реализация — чат исполнения. Основа: коммит a3f8db67 (TASK-032, этап A).

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

### Этап 2 (по цифрам из `data load stats`, отдельным заходом)
Выбор по замеру, не наугад:
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
