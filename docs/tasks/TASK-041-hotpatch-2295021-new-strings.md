# TASK-041: хотпатч 2295021 — новые строки StringDB и обновление пакетов

## Симптом (2026-11-09)
09.11 в 8:43 игра поставила два хотпатча: `Saved/kscache/2274143/` и `Saved/kscache/2295021/`. Текущая версия ресурсов в `Saved/kscache/AssetsVersion.txt`: `1.2018737.2295021.Online_Shipping`. Базовый пак не менялся (`Content/Paks/AssetsVersion.txt` = `1.2018737.2018737`).

Патч работает: в `C7.log` за 09.11 есть строка `[CPDDRuntimeFix] v3.1.1-RU active hooks_installed=26`. Но там же впервые появилась строка:
```
[2026.11.09-08.45.10:429] … Init.lua:1364 [CPDDRuntimeFix] stringdb pack stale Data.Excel.LanguageData.StringDB_CN_Data unknown=98 shards=91 (new StringDbDump needed, docs/DIAGNOSTICS.md)
```
В логах за 05.11 (`C7-backup-2026.11.05-08.24.17.log`) и 07.11 (`C7-backup-2026.11.07-*.log`) этой строки нет. Значит, новые строки принёс именно хотпатч 09.11.

## Первопричина
- Пакеты StringDB (`StringDbPack*.lua`, TASK-033) собраны из `source/stringdb/stringdb_keys.json`, а он выгружен на сборке **2218968** (`reference/stringdb_dump/2218968/`). Других выгрузок нет.
- Китайские строки, добавленные хотпатчем, в пакете отсутствуют (`nil`). Рантайм ищет их в шардах (`docs/DIAGNOSTICS.md`, раздел «Пакеты StringDB»). Если строки нет и в шардах, она остаётся китайской.
- `unknown=98` — нижняя граница: это только модуль `StringDB_CN_Data` и только то, что слилось при старте. Другие модули и таблицы `LanguageData` (диалоги, квесты) так не видны.
- Сколько из 98 строк уже покрыто шардами, а сколько не переведено, неизвестно. Это покажет выгрузка.

Дополнительно: последний релиз CPDD — **v2.7.5** (24.10.2026), а у нас база **v2.7.1** (`vendor/cpdd/BASE.json`). v2.7.5 вышел до хотпатча 09.11, поэтому строк 2295021 в нём, скорее всего, нет, но там могут быть строки хотпатчей 2228458/2255640.

## План

### Этап 0. Dev-сессия (делает пользователь)
1. Создать `D:\Games\GMZZLauncher\Game\C7\Saved\Mods\lua\absoluteru_dev.lua` по шаблону из `docs/DIAGNOSTICS.md` → «Включение». Раскомментировать `StringDbDump = true`. Остальные флаги оставить как в шаблоне (`Enabled`, `Untranslated`, `PanelWalk` обязательны).
2. Запустить игру и войти персонажем. После входа игра может подвиснуть: модуль грузит все модули StringDB. Дождаться, пока отвиснет.
3. Пройти места с новым контентом хотпатча (события, новые окна, магазин, задания), если они известны, плюс пару обычных экранов.
4. Выйти из игры. Удалить `absoluteru_dev.lua`.
5. Сказать в чате исполнения, что сессия готова.

### Этап 1. Импорт ключей и пересборка пакетов (чат исполнения)
1. `powershell -ExecutionPolicy Bypass -File tools\CollectDiagLogs.ps1` → папка `reference/logs/<дата>/`, `sid` последней сессии взять из вывода.
2. Проверить, что выгрузка полная: в `absru-s<sid>-stringdb-*.jsonl` есть `stringdb_key_summary` по каждому модулю.
3. `powershell -ExecutionPolicy Bypass -File tools\StringDbGaps.ps1 -ImportKeys -Logs reference\logs\<дата> -Sid <sid> -GameBuild 2295021`. Записать в отчёт, сколько ключей добавилось и удалилось по модулям (сравнение с прежним `stringdb_keys.json` через `git diff --stat` и сводку скрипта).
4. `tools\ShardCompiler.exe -CheckResolved reference\stringdb_dump\2295021\resolved.json` → **0 расхождений** (заодно пересобирает пакеты).
5. `tools\LuaDataCheck.exe`, `powershell -ExecutionPolicy Bypass -File tools\VerifyPatch.ps1`: без ERR, без WARN о `game_build`.
6. Коммит: `source/stringdb/stringdb_keys.json` и пакеты `StringDbPack*.lua`. Сообщение: `chore(stringdb): TASK-041 keys for build 2295021`. Push.

### Этап 2. Отчёт о непереведённом (чат исполнения)
1. `powershell -ExecutionPolicy Bypass -File tools\StringDbGaps.ps1 -Report -Logs reference\logs\<дата> -Sid <sid>`: сколько строк без перевода по категориям, сколько из них `on_screen`.
2. Отдельно посчитать, сколько из **новых** ключей сборки 2295021 (разница `stringdb_keys.json` до/после) не имеют перевода в шардах. Это и есть объём работы.
3. Записать цифры в раздел «Результат выгрузки» этого файла и разбить строки на пачки в разделе «Порядок пачек». Ориентир: пачка ≤ 2000 строк (лимит `/translate-pack`). Если строк меньше ~300, это одна пачка.
4. Новый батч: `batch_040_hotpatch_2295021.json` (следующий свободный номер после `batch_039`). Строка в `BATCH_MANIFEST.md` добавляется при выгрузке (`/translate-pack`, шаг 1).
5. **Сам перевод в чате исполнения не делать** (AGENTS.md §3). Выдать пользователю промпт `/translate-pack` по шаблону ниже.

### Этап 3. Сверка с CPDD v2.7.5 (чат исполнения, только отчёт)
1. `powershell -ExecutionPolicy Bypass -File tools\SyncCpdd.ps1 -Tag v2.7.5` (без `-Apply`) → `reference/cpdd/v2.7.5/SYNC_REPORT.md`.
2. Кратко пересказать пользователю: новые строки шардов, изменения `supported_game.json`/моста, затронутые рантайм-файлы. `-Apply` не запускать без решения пользователя: при необходимости это отдельная задача.

### Этап 4. Перевод (отдельный чат, `/translate-pack`)
По промпту из этапа 2. После перевода — релиз, только если пользователь попросит (`tools\PackageRelease.ps1 -Publish`).

## Результат выгрузки

### Этап 1: выполнен с третьей попытки
Сессия `reference/logs/2026-11-09_1005`, sid `20261109-095548`, слот s3: 38 итогов `stringdb_key_summary` из 38, последним идёт `_trap`; `skipped_long`, `lossy`, `capped` и `failed` везде 0.
- `-ImportKeys -GameBuild 2295021`: 38 модулей, 116 453 ключа, 109 582 уникальных cn. Шаг 3 нашёл 109 164, без перевода 418. `stringdb_keys.json`: +179/−75 строк.
- Разница с ключами 2218968 по модулям (добавлено / удалено / из добавленных без перевода): `StringDB_CN_Data` 98/35/96, `_itemgift` 63/28/63, `_itemoutlook` 4/1/4, `_itemnormal` 2/2/2, `_buffappear` 2/0/1, `_buffdata` 1/0/1, `_skill3` 1/1/1. Остальные 31 модуль не изменились. Итого **167 новых уникальных cn, из них 165 без перевода**. Список: `reference/stringdb_dump/2295021/new_keys_2218968_to_2295021.csv`.
- `ShardCompiler -CheckResolved`: **10 расхождений, все по 格罗塞尔 (Гросель)**. В игре стоит v3.1.1-RU, а канон Гроселя (`f87d7284`, TASK-036 T2, 11 строк) вошёл только в v3.1.2. Значит, в игре старый перевод, а в репозитории новый. Ошибки пакетов тут нет. Из-за кода 3 `-CheckResolved` пакеты не собирает (`tools/ShardCompiler.cs:616-619`), поэтому их собрал обычный `ShardCompiler.exe`: 38 пакетов, `game_build=2295021`, с переводом 116 019 ключей.
- `LuaDataCheck`: 0 расхождений. `VerifyPatch`: без ERR, `[OK] Пакеты StringDB: 38 модулей, game_build=2295021`. Остался WARN о `game_build`, но он вызван несоответствием форматов: `tools/VerifyPatch.ps1:159` сравнивает `2295021` с `supported_game.json` = `1.2018737.2044036`. Такие значения не совпадут никогда, предупреждение было и при 2218968.

### Попытки 1–2 (для истории)
Сессия 09.11 (`reference/logs/2026-11-09_0922`, sid `20261109-091642`, слот s1).

**Выгрузки ключей нет.** В `absoluteru_dev.lua` строка `StringDbDump = true` осталась закомментированной. В C7.log флаги диагностики: `flags=Hooks,Untranslated,Overflow,Fonts,Images,PanelWalk`, без StringDbDump; файлов `absru-s*-stringdb-*.jsonl` нет. Поэтому `-ImportKeys`, `-CheckResolved`, пересборка пакетов и коммит ключей отложены. Предупреждение `stringdb pack stale … unknown=98` останется, пока не будет новой выгрузки. Число новых ключей сборки 2295021 (этап 2, п. 2) без выгрузки посчитать нельзя. Кроме того, файл `absoluteru_dev.lua` всё ещё лежит в игре.

Вторая попытка (`reference/logs/2026-11-09_0952`, sid `20261109-094233`, s2): флаг StringDbDump был включён, но выгрузка **неполная**. В ней 27 итогов `stringdb_key_summary` из 38: отсутствуют `_skill`, `_skill1-3`, `_spellfield`, `_talk`, `_talkother`, `_tingen`, `_tingentalk`, `_traingame`, `_trap`. Игру закрыли в 09:51:55, когда шла запись модуля `_skill` (файл `stringdb-047`). Лимит потока не превышен: 23 МБ из 64. За 9 минут выгрузились 27 модулей. В следующей сессии нужно оставаться в игре, пока в `Saved/Mods/logs/absru-s*-stringdb-*.jsonl` не появится итог по `StringDB_CN_Data_trap`.

`StringDbGaps -Report` (только промахи, увиденные за сессию): 406 строк, все без русского, на экране 3.

| категория | строк | экран | из них есть в CPDD v2.7.5 (NEW) |
|---|---|---|---|
| ui | 62 | 1 | 21 |
| mail | 4 | 0 | 2 |
| skill | 7 | 1 | 5 |
| buff | 1 | 0 | 0 |
| assistant | 2 | 0 | 2 |
| item | 69 | 1 | 42 |
| text | 21 | 0 | 12 |
| service | 3 | 0 | — не переводить |
| technical | 229 | 0 | — не переводить (капитель, кана, смайлы) |
| clipped | 8 | 0 | 7 из них base64-мусор; 1 настоящий текст: `<Assistant_Title1>【四方联赛】…`, нужен полный текст |

Итого к переводу **166 строк** (ui, mail, skill, buff, assistant, item, text). Тематика хотпатча: «Четырёхсторонняя лига» (四方联赛), «Финальная охота» и дракон, «Призрак оперы», Двойная 11 (双十一 — ноябрьская распродажа), коробки снаряжения 66/68 ур., новые локации (群星渡口, 苍穹巨桥 …), медуза (水母). У 84 строк есть английский эталон в CPDD v2.7.5, но наши шарды на базе v2.7.1, так что `ref_en` в батч не попадёт, пока не применён `SyncCpdd -Apply`.

**Сверка CPDD v2.7.5** (`reference/cpdd/v2.7.5/SYNC_REPORT.md`, без `-Apply`): в шардах +141 строка, из них 112 нет в наших батчах; у 23 строк изменился EN. `supported_game.json` и мост не изменились, BakedText копируется как есть. Изменился рантайм `cpdd_runtime_fixes/Init.lua` (+`Init.lua.compat.luac`): **14 конфликтов** при merge3 (`reference/cpdd/v2.7.5/sync/Init.lua.merged`). Ещё нужно перегенерировать `translation-overrides.state.json`. `-Apply` создаст батч `batch_040_cpdd_275.json`, а он занимает тот же номер 040, что и батч хотпатча. Если делать Apply, то **до** выгрузки пачки, а батч хотпатча тогда получит номер 041.

## Порядок пачек
**Актуально (после полной выгрузки).** `-Report` по сессии `20261109-095548`: 434 строки, на экране 5. Переводить: ui 62, mail 4, skill 7, buff 1, assistant 2, item 69, text 22, итого **167**. Из них 162 новые строки 2295021 и 5 старых. Остальное не переводится: technical 256, service 3, clipped 8. Ещё 3 новые длинные строки Четырёхсторонней лиги (四方联赛: справка, расписание и правила сезона, 2–3 тыс. символов) в логах обрезаны, поэтому они идут через `-EmitList` из `reference/stringdb_dump/2295021/emit_list_extra.txt`. Всего 170 строк — **одна пачка**.

Пачка 1 (вариант B, без Apply v2.7.5; для варианта A замените 040 на 041):
```
/translate-pack
Пачка: 1 из 1, docs/tasks/TASK-041-hotpatch-2295021-new-strings.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_040_hotpatch_2295021.json, выгрузка в два шага:
  1) StringDbGaps -Emit batch_040_hotpatch_2295021.json -Category ui,mail,skill,buff,assistant,item,text (без -OnScreen), логи reference/logs/2026-11-09_1005, sid 20261109-095548 — 167 строк;
  2) StringDbGaps -EmitList batch_040_hotpatch_2295021.json -ListFile reference\stringdb_dump\2295021\emit_list_extra.txt — 3 длинные строки 四方联赛.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```

Ниже — прежний вариант по неполным логам первой сессии (устарел, оставлен для истории).

Одна пачка, 166 строк, меньше ~300. Варианты порядка:
- **A (рекомендуется):** сначала отдельной задачей `SyncCpdd -Tag v2.7.5 -Apply` (14 конфликтов в Init.lua). Тогда у 84 строк будет `ref_en`, а батч получит номер `batch_041_hotpatch_2295021.json`.
- **B:** переводить сейчас по `source_cn`, в батч `batch_040_hotpatch_2295021.json`. Тогда v2.7.5 при Apply принесёт свой батч 041, и около 84 строк в нём совпадут с уже переведёнными.

Пачка 1 (номер батча зависит от варианта):
```
/translate-pack
Пачка: 1 из 1, docs/tasks/TASK-041-hotpatch-2295021-new-strings.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_040_hotpatch_2295021.json (создать через StringDbGaps -Emit; при варианте A — batch_041_hotpatch_2295021.json).
Строки: -Category ui,mail,skill,buff,assistant,item,text (без -OnScreen, 166 строк), логи reference/logs/2026-11-09_0922, sid 20261109-091642.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```
Clipped-строку 【四方联赛】 через `-Emit` выгрузить нельзя. Её полный текст появится после новой выгрузки (или в шардах v2.7.5).

Шаблон промпта:
```
/translate-pack
Пачка: 1 из docs/tasks/TASK-041-hotpatch-2295021-new-strings.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_040_hotpatch_2295021.json (создать через StringDbGaps -Emit …).
Строки: -Category <…> [-OnScreen], логи reference/logs/<папка>, sid <sid>.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```

## Проверка в игре (пользователь, после перевода и установки)
- В `C7.log` после входа нет строки `stringdb pack stale`.
- Строки, которые попали в батч с флагом `on_screen` (примеры даст итог `/translate-pack`), на своих экранах показаны по-русски.
- Строка `v3.1.x-RU active hooks_installed=…` на месте, ошибок `stringdb pack … unavailable` нет.
