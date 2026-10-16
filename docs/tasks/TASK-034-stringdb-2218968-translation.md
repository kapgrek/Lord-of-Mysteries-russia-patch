# TASK-034 — перевод непереведённых строк StringDB билда 2218968 (этап B TASK-032) и релиз v3.1.1-RU

## Исходные данные (анализ 16.10)
- Выгрузка ключей StringDB: sid `20261016-200529`, `source/stringdb/stringdb_keys.json`, `reference/stringdb_dump/2218968/resolved.json` (TASK-033, «Ход 2B»). Уникальных cn 109 482, из них без перевода (`res = null`, в пакетах `false`) **8 190**.
- Из 8 190: с иероглифами **7 938**; без иероглифов 252 (base64-блобы `hLBjdXJX…`, мелкий шрифт `ʜʙ⒎ᴘᴜʙ`): не переводятся.
- **7 869 из 7 938 (99 %) есть в английских шардах CPDD 2.7.1** (`reference/cpdd/v2.7.1/unpacked/.../RuntimeTextGemini_*.lua`), и все они — ключи, добавленные в 2.7.1 относительно 2.6.4 (точное совпадение, в 2.6.4 их нет). Это ровно этап B TASK-032: `SyncCpdd.ps1 -Components shards -Apply` создаёт батч из 9 408 строк (`reference/cpdd/v2.7.1/SYNC_REPORT.md`: «Added 16001 (not in our batches: 9408)»). В нём 7 869 строк StringDB и около 1 540 прочих новых строк CPDD (UI, данные KSBC) — **с `ref_en`**. Выгрузка через `StringDbGaps -EmitList` дала бы пустой `ref_en`, поэтому основной путь — `SyncCpdd`.
- 69 cn с иероглифами без английского у CPDD (в основном основной модуль, `_achievement` 7, `_skill3` 7) добавляются через `-EmitList` (`ref_en` пустой).
- `StringDbGaps -Emit/-EmitData` здесь не подходят: они берут строки из логов промахов (`absru-s*-untranslated-*.jsonl`), а не из файла ключей.

Разбивка 7 938 cn с иероглифами по модулям (каждый cn учтён в первом модуле по ordinal-порядку):

| Модуль | cn | есть EN CPDD | КБ cn | Решение |
|---|---|---|---|---|
| основной `StringDB_CN_Data` | 3 806 | 3 755 | 337 | перевод (45 строк > 1000 байт) |
| `_buffdata` | 677 | 675 | 17 | перевод |
| `_debug` | 503 | 502 | 22 | **не переводить** |
| `_maintask` | 432 | 432 | 31 | перевод |
| `_itemoutlook` | 384 | 384 | 27 | перевод |
| `_beckland` | 346 | 346 | 21 | перевод |
| `_tingen` | 227 | 227 | 14 | перевод |
| `_talkother` / `_gossip` / `_itemgift` | 167 / 166 / 164 | все | 12 / 8 / 32 | перевод |
| `_achievement` / `_buffappear` | 147 / 142 | 140 / 141 | 5 / 4 | перевод |
| ещё 21 модуль | 1 – 91 | почти все | ≤ 19 | перевод |

### Почему `_debug` не переводим
Выборка из 25 строк: внутренние подписи дизайнеров и служебные метки навыков: «终末猎杀-草丛15逐簇隐匿02», «玩家秘偶-奇迹牌雨 改 测试验证用», «【自走棋英雄强化内部子技能】…», «…筛3远程». Игроку они не показываются. 503 строки ≈ 10 чанков ≈ четверть чата перевода без пользы. Их переносят в отдельный батч `batch_048_cpdd_271_debug.json` со статусом «не переводить». Так повторный `SyncCpdd` их не добавит снова, а `-ExportNew` по `batch_047` их не выгрузит. Английский из CPDD (`ref_en`) попадёт в шарды (см. ниже), и это безвредно.

### Важное: пустой `target_ru` → в игре английский
`tools/ShardCompiler.cs:83`: `finalVal = !string.IsNullOrEmpty(ru) ? ru : en`. Сразу после создания батча (Stop-хук или `ShardCompiler.exe`) около 9 400 новых cn получат в шардах и пакетах StringDB английский текст CPDD вместо `false`. В игре до перевода будет английский, а не китайский. Это то же поведение, что у прежних батчей с `ref_en`, и для игрока это лучше китайского. Но **промежуточный релиз до конца перевода покажет смесь RU/EN**. Пакеты StringDB после компиляции: `false` останется только у cn без английского (≈ 69 с иероглифами + 252 без).

## План

### E1. Чат исполнения: создание батчей (до перевода)
1. `powershell -ExecutionPolicy Bypass -File tools\SyncCpdd.ps1 -Tag v2.7.1 -SkipDownload -Components shards -Apply -BatchName batch_047_cpdd_271.json | Select-Object -Last 30`. Ожидание: `batch_047_cpdd_271.json`, 9 408 записей, id от 140185, `target_ru` пустой. В `vendor/cpdd/BASE.json` `component_bases.shards` переходит на v2.7.1; `companions.json` без изменений (у шардов компаньонов нет). Других изменений в `git status` быть не должно: если есть, остановиться и разобрать.
2. Дубликаты по семантике ShardCompiler (требование TASK-032): одноразовый скрипт в `temp/t034/` (PowerShell, UTF-8 с BOM). Для каждой записи `batch_047` с ключом `TrimLuaSpace(cn)` ≠ `cn`: если в других батчах есть **переведённая** запись с тем же обрезанным ключом, удалить запись из `batch_047` (рантайм `lookupGeminiTextFuzzy` уже покрывает обрезку, а точная запись с английским перебила бы русский). Число удалённых записать в итог. Для 7 869 строк StringDB таких быть не должно (`resolve` для них дал `null`).
3. Перенести `_debug` в `batch_048_cpdd_271_debug.json`. Множество `_debug`-only = ключи модуля `Data.Excel.LanguageData.StringDB_CN_Data_debug` из `stringdb_keys.json` минус ключи всех остальных модулей. Записи `batch_047`, у которых `source_cn` (как есть и после trim) входит в это множество, перенести без изменений (те же id и формат, что у `SyncCpdd` `Write-BatchFile`: UTF-8 без BOM, LF). Ожидание ≈ 502.
4. `tools\ShardCompiler.exe | Select-Object -Last 5`. Затем список для 69 строк без EN: строки `["…"] = false,` с иероглифами из всех `patch_payload/.../StringDbPack*.lua`, кроме `StringDbPack_debug.lua` → раскрыть экранирование Lua → `temp/t034/noen.txt` (строка на строку, перевод строки как литерал `\n`). `powershell -ExecutionPolicy Bypass -File tools\StringDbGaps.ps1 -EmitList batch_047_cpdd_271.json -ListFile temp\t034\noen.txt | Select-Object -Last 5`. Ожидание ≈ 69 новых записей.
5. `BATCH_MANIFEST.md`: две строки. `batch_047_cpdd_271` — «Ждёт перевода (TASK-034: новые ключи CPDD 2.7.1 с `ref_en` + N строк `-EmitList` без EN; пачки 1–5, `-ExportNew`)», диапазон id. `batch_048_cpdd_271_debug` — «Не переводить (TASK-034: `StringDB_CN_Data_debug`, служебные подписи; в игре английский CPDD)».
6. Проверки: `ShardCompiler.exe`; `VerifyBatch.ps1 -Batch 047` и `-Batch 048` (0 ERR; предупреждения о пустом `target_ru` ожидаемы); `LuaDataCheck.exe` (0 расхождений); `VerifyPatch.ps1`. Сумма `false=` в заголовках `StringDbPack*.lua`: сейчас 8 474 (8 190 уникальных cn, часть повторяется в нескольких модулях), ожидание — несколько сотен (cn без EN и без иероглифов). Число строк к переводу: `GlossaryCheck.ps1 -ExportNew -BatchFile batch_047_cpdd_271.json -Count 50 | Select-Object -Last 3`, потом удалить `temp/glossary_chunk_*`.
7. Коммит `feat(TASK-034): E1 - batch_047 CPDD 2.7.1 new keys (N to translate), batch_048 _debug deferred`, push. В TASK-034 — раздел «Итог E1» с числами: записей в 047/048, удалённых дубликатов, `-EmitList`, сумма `false`, число чанков.

### Пачки перевода (отдельные чаты `/translate-pack`, строго по очереди)
Объём ≈ 8 970 строк ≈ 180 чанков по 50, ≈ 5 чатов по 40 чанков. Чаты **не запускать параллельно**: один батч и общие `temp/glossary_chunk_NNN.json` дадут гонку (как у batch_036/037 в TASK-022). `-ExportNew` сам берёт только пустые `target_ru`, поэтому все пачки запускаются одним и тем же промптом.

#### Порядок пачек
- Пачка 1: `batch_047_cpdd_271.json`, после E1. Чанки 1–40.
- Пачки 2–5: тот же батч, продолжение тем же промптом. Последняя пачка закрывает остаток (≈ 970 строк).
- `batch_048_cpdd_271_debug.json` — не переводить.

Замер «до/после» вместо `StringDbGaps -Report` (логов промахов для этих строк нет): строк с пустым `target_ru` в `batch_047` — из вывода `-ExportNew`.

### E2. Чат исполнения: релиз v3.1.1-RU (после пачки 5)
1. Убедиться, что в `batch_047` 0 пустых `target_ru` (кроме отклонённых и перечисленных в итогах пачек). `ShardCompiler.exe`, `VerifyBatch.ps1 -Batch 047`, `GlossaryCheck.ps1 -Report` (`B` не вырос), `LuaDataCheck.exe`, `VerifyPatch.ps1`.
2. Версия 3.1.1-RU по образцу `f6ed781f` (`chore(release): v3.0.11-RU`): `Init.lua` VERSION, `installer/AppInfo.cs`, `installer/AssemblyInfo.cs`, `README.md`, `tools/PackageRelease.ps1` и `tools/VerifyPatch.ps1`, если в них есть номер (`3.1.0-RU` сейчас найден в этих файлах). Проверить, по чему установщик определяет обновление (тег/версия релиза), и что 3.1.1 > 3.1.0 в его сравнении.
3. `tools/BuildTools.ps1`, `InstallerCoreTests.exe`, `tools/PackageRelease.ps1` **без** `-Publish`. Дать пользователю сборку и чек-лист ниже. `-Publish` — только после его подтверждения.

## Чек-лист для пользователя (после E2)
1. Установить сборку v3.1.1-RU (игра закрыта). Окно установщика: «Русский установлен», версия 3.1.1-RU.
2. `C7.log`: `translation overlays applied modules=1 entries=…` — число не меньше 63 575; нет `stringdb pack stale` и ошибок `StringDbPack`/`external mapping`.
3. Места, где раньше был китайский (основной модуль, баффы `_buffdata`, основные задания `_maintask`, облики предметов `_itemoutlook`, Бекланд `_beckland`, Тинген): описания баффов на персонаже и враге, журнал заданий, гардероб/облики, подарки, достижения — русский текст, без китайского и английского. Английский допустим только в отладочных подписях.
4. Старт игры не медленнее v3.1.0 (холодный ≈ 5,4 с, тёплый ≈ 2,7 с от `[Game:InitFrameworkBase]` до `translation overlays applied`).

## Промпты

### Промпт для чата исполнения — E1 (создать сейчас)
```
Чат 2 (исполнение) по AGENTS.md. Задача: docs/tasks/TASK-034-stringdb-2218968-translation.md, раздел «E1. Чат исполнения: создание батчей».
Выполнить шаги 1–7 E1: SyncCpdd -Tag v2.7.1 -SkipDownload -Components shards -Apply -BatchName batch_047_cpdd_271.json; удалить дубликаты по trim-ключу с уже переведёнными записями; перенести _debug-only строки в batch_048_cpdd_271_debug.json; ShardCompiler; -EmitList строк без EN (false с иероглифами из StringDbPack*.lua, кроме _debug); BATCH_MANIFEST.md; проверки (VerifyBatch 047/048, LuaDataCheck, VerifyPatch, сумма false=, число чанков -ExportNew); итог в TASK-034; коммит и push.
Одноразовые скрипты — temp/t034/ (PowerShell 5.1, .ps1 с кириллицей/иероглифами — UTF-8 с BOM; Python нет). Батчи читать скриптом, не глазами; вывод команд обрезать. Ничего не переводить: строки остаются с пустым target_ru для чатов /translate-pack. Игру и папку игры не трогать. Релиз не собирать.
Если git status после SyncCpdd показывает изменения вне batch_047, BASE.json, companions.json и сгенерированных шардов/пакетов — остановиться и описать.
```

### Промпт для пачки перевода (пачки 1–5, один и тот же; после E1)
```
/translate-pack
Пачка: <1|2|3|4|5> из docs/tasks/TASK-034-stringdb-2218968-translation.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_047_cpdd_271.json (уже есть, продолжить: -ExportNew берёт только пустые target_ru). batch_048_cpdd_271_debug.json не трогать.
Строки: шаг 1 скилла пропустить (батч создан в E1); логов промахов нет — StringDbGaps -Report не запускать, «до/после» = число строк из -ExportNew.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push (сообщение feat(translation): TASK-034 pack <N> - CPDD 2.7.1 new keys, <X> strings), короткий итог: переведено / отклонено / осталось.
```

### Промпт для чата исполнения — E2 (после пачки 5)
```
Чат 2 (исполнение) по AGENTS.md. Задача: docs/tasks/TASK-034-stringdb-2218968-translation.md, раздел «E2. Чат исполнения: релиз v3.1.1-RU».
Проверить, что batch_047_cpdd_271.json переведён (пустые target_ru — только перечисленные в итогах пачек), прогнать ShardCompiler, VerifyBatch -Batch 047, GlossaryCheck -Report, LuaDataCheck, VerifyPatch. Поднять версию до 3.1.1-RU по образцу коммита f6ed781f, проверить сравнение версий в установщике. BuildTools, InstallerCoreTests, PackageRelease без -Publish. Коммит и push; дать пользователю чек-лист из TASK-034. Публиковать (-Publish) только после его подтверждения. Игру не запускать, папку игры не трогать.
```
