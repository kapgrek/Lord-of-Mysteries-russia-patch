# TASK-032: обновление игры 1.2018737.2218968 — перевод не запускается

## Симптом
15.10.2026 игра скачала хотпатч ресурсов 2171866 → 2218968. После этого весь текст на китайском: русификатор v3.0.11-RU не загружается совсем. Папка игры, установленный патч и `Content/Paks/pakchunk0-Windows.pak` не менялись.

## Первопричина (подтверждена логами и файлами)

### 1. Хотпатч перекрывает `LaunchInstance` своим `pakchunk0` в кеше
- Запуск в 17:36, ещё на старой версии (`Saved/Logs/C7-backup-2026.10.15-14.48.42.log:9-10`): `Slua: Error: Can't load file Launch.Base.CPDDTranslation`, затем `[LOMModLoader] bootstrap path=…/Saved//Mods/bootstrap.lua bytes=23099`. Мост работает (ошибка Slua — обычный промах первого поисковика, она была и 12.10).
- Запуск в 17:49, после обновления (`Saved/Logs/C7.log`): `PatchInitVersionWork … LocalVersion:1.2018737.2171866, RemoteVersion:1.2018737.2218968` (стр. 198), `LoginPanel … HINT_CURRENT_VERSION : 1.2018737.2218968` (стр. 13760). В логе **нет** строк `CPDDTranslation`, `LOMModLoader`, `CPDDRuntimeFix`: `LaunchInstance.lua:63/84` выполняется, но мост не вызывается.
- Хотпатч записал `Saved/kscache/2218968/pakchunk0-Windows.pak` (112 028 892 байт). Прошлые хотпатчи (`kscache/2171866`, `kscache/2153744`) `pakchunk0` не содержали, поэтому раньше блок моста в базовом паке работал.
- В этом паке по смещению **41063360** лежит чистый блок `LaunchInstance`, 5258 байт, sha256 `3124ee28ea3b4db83666da313d5e022eaef882d191356d5e38b86d94c6173084`. Это ровно `external_bridge.cache_launch.original` / `clean_sha256` из CPDD v2.7.1 `release.json` (проверено побайтным поиском, найдено одно совпадение).
- `cache_launch.manifest_sha256` = `6d23b1cf…` = sha256 `Saved/kscache/package_2018737.manifest` у пользователя. CPDD 2.7.1 рассчитан ровно на эту сборку.
- Версия кеша читается из `Saved/kscache/AssetsVersion.txt` (`1.2018737.2218968.Online_Shipping`).

**Вывод:** наш установщик (`installer/InstallerCore.cs:209-218, 327-361`) патчит только `Content/Paks/pakchunk0-Windows.pak` по фиксированному смещению. Блок из кеша монтируется поверх, и мост не вызывается.

### 2. CPDD 2.6.6–2.7.1 (выпущены 15.10) — что они поменяли под эту сборку
Скачано `tools/SyncCpdd.ps1 -Tag v2.7.1`, отчёт `reference/cpdd/v2.7.1/SYNC_REPORT.md`, распаковка `reference/cpdd/v2.7.1/unpacked/`.
- **Мост в кеше:** `payload/cache-startup.oodle` (5258 байт, sha `ee48b48a…`) пишется вместо `original` в `kscache/<ver>/pakchunk0-Windows.pak`. Смещение ищется на месте («resolving local cache paths and offsets dynamically»), проверки «original/replacement» обязательны. `patch_method: bootstrap_external_and_guarded_cache_startup`, `touches_game_cache: true`. Старый блок для базового пака (`launch_block`) не изменился.
- **Байткод-компаньоны `*.lua.compat.luac`:** 1287 файлов в `cpdd_runtime_fixes` (шарды, индексы, `Init`, `DesktopChat`…), плюс `bootstrap`, `manifest`, `translation-overrides`, `CPDDTranslation`. Комментарий в их `bootstrap.lua:68-69`: «The shipping VM can disable source compilation after startup». Компаньон возвращает `(исходник, chunk)` и принимается, только если исходник побайтно равен `.lua` рядом (`bootstrap.lua:64-91`, `Loader.ReadCompatibleChunk`).
  - Формат: заголовок `1B 4C 4A 82 08` + имя чанка открытым текстом, дальше **зашифрованные** данные (исходник внутри не читается, см. hex `CPDDTranslation.lua.compat.luac`). Стандартный LuaJIT их не соберёт, а кодировщика CPDD у нас нет. **Свои компаньоны мы сделать не можем.** Компаньоны CPDD подходят только к файлам, которые у нас побайтно совпадают с CPDD: `CPDDTranslation.lua`, 256 `LanguageSourceIndex_*.lua`, `DpsMeter`, `DpsTelemetry`, `EngineIniBridge`, `ServerScheduleFix`, `WidgetNameIndex`, `DesktopChat` — это нужно проверить по sha.
- **Exact-source policy (2.7.0):** ID-оверлеи `cpdd_translation.*` отключены (`bootstrap.lua` 2.7.1: `LoadExternal`, `read_overlay_chunk`, `merge_overlay`, `external_searcher`, `deniedTranslationAliases`). Причина в их changelog: числовые ID в обновлении сдвинулись, и старые ID-переводы показывали посторонний текст. Их `Init.lua` переписан (≈8000 → ≈800 строк, 3-way merge с нашим даёт 9 конфликтов, `reference/cpdd/v2.7.1/sync/Init.lua.merged`). **Init целиком не мержить.**
- **Картинки:** `Saved/Mods/BakedText/blocks.bin` + `manifest.json` удалены, вместо них `baked_images` с подписанными профилями на сборки 2171866 и 2218968 и путями в кеше.
- **Новые строки:** шарды CPDD 2.7.1 добавили 16001 CN-исходник, из них **9408 нет в наших батчах** (`SYNC_REPORT.md:315`).

### 3. Что из этого касается нашего кода
- Код наших модулей грузится на старте: `bootstrap.lua:565-579` делает `require` для `manifest.Load` прямо во время выполнения моста. Если компиляция исходника отключается «after startup», то `Init.lua` и прочие entry-модули скорее всего скомпилируются.
- Лениво грузятся данные: шарды `RuntimeTextGemini_*` (`Init.lua:2083-2085`), `LanguageSourceIndex_*` (`Init.lua:5446-5448`), `WidgetNameIndex` (`Init.lua:5083`), диагностика (`Init.lua:1426, 1438`). Их `require` → `external_searcher` → `read_chunk` (`bootstrap.lua:66-79`: `loadfile`, затем `load(source)`) **упадёт, если VM запрещает компиляцию**. Шарды наши, компаньонов для них не будет.
- ID-путь `directLookup` (`Init.lua:5366-5403`) берёт английскую таблицу `cpdd_translation…StringDB_CN_Data` по ID. Он используется как запасной в `Init.lua:5518, 5990, 6136, 6175, 6222`. После сдвига ID он подставит чужой текст (как у CPDD).
- **Не подтверждено (нужен лог пользователя):** действительно ли в 2218968 отключена компиляция и в какой момент. Мы знаем это только из комментария и действий CPDD. Поэтому план делает загрузку данных независимой от компиляции и пишет в лог, какой путь сработал.

## План

### Этап A — запуск на 2218968 (релиз v3.1.0-RU)
1. **Синхронизация с CPDD 2.7.1 (без Init):** `SyncCpdd.ps1 -Tag v2.7.1 -Components bridge,sourceindex,dps,chat,engineini,schedule,widgets,stringdb,state -Apply`. Добавить в `SyncCpdd.ps1` правило для `*.compat.luac`: компонент = компонент соседнего `.lua`; копировать **только** если наш `.lua` побайтно равен CPDD-шному. Иначе компаньон не класть: несовпадающий компаньон `read_chunk` CPDD отвергает с ошибкой, а наш `read_chunk` должен откатываться на исходник. Скопировать `payload/cache-startup.oodle` в `patch_payload/bridge/`. `bakedtext` не трогать (этап C). Перед `-Apply` проверить, что наш `CPDDTranslation.lua` = CPDD 2.7.1 (иначе компаньон моста не подходит).
2. **`bootstrap.lua`, ручной перенос из CPDD 2.7.1:**
   - `read_chunk`: сначала компаньон (логика CPDD `bootstrap.lua:70-84`, но при несовпадении исходника — откат на `loadfile`/`load`, а не отказ), затем `loadfile`, затем `load`. Экспортировать `Loader.ReadCompatibleChunk`.
   - Exact-source policy: отключить ID-оверлеи `cpdd_translation.*` и `deniedTranslationAliases` как в CPDD (диф в разделе 2). Сначала проверить, какие наши алиасы из `manifest.lua` (`Launch.I18n.zh`, `Shared.language_zhs`, `DebugConst`…) несут **русские** переводы, а не английские CPDD. Если наш алиас русский и не по ID, оставить его и записать решение в TASK.
   - Однострочная проба (всегда, не только в DiagnosticsMode, это одна строка): на старте `[LOMModLoader] compile probe startup=<ok|fail>`, а в `Init` при первой загрузке шарда `[CPDDRuntimeFix] shard load path=<companion|loadfile|load|data>`.
3. **Загрузка данных без компиляции (`Init.lua`):** если `require` шарда, индекса или `WidgetNameIndex` вернул ошибку компиляции, читать файл через `File.LoadFile` и разбирать собственным парсером таблицы-литерала `return { ["k"] = "v", … }`. Формат генерирует `ShardCompiler`, поэтому парсер обязан поддержать только его экранирование: `\"`, `\\`, `\n`, `\r`, `\t`, `\ddd`. Сверить с эмиттером в `tools/ShardCompiler.cs` и с форматом `LanguageSourceIndex_*` из CPDD. Парсер вынести в отдельную функцию и проверить офлайн: прогнать все 1024 шарда и 256 индексов через парсер **и** через обычный Lua-компилятор (если нет `lua`/`luajit` — C#-эквивалент в `tools/`) и сравнить таблицы побайтно. Расхождений должно быть 0.
4. **Exact-source в `Init.lua`:** `directLookup` (`:5400`) не использовать таблицу `cpdd_translation.*` (возвращать `nil`, как CPDD). Таблицы игры `Data.Excel.LanguageData.StringDB_EN/CN_Data` берутся из текущего билда, их ID актуальны — оставить. Пять мест вызова (`:5518, 5990, 6136, 6175, 6222`) не менять.
5. **Установщик — мост в кеше (`installer/InstallerCore.cs`, `supported_game.json`):**
   - В `supported_game.json` (и в генерацию в `SyncCpdd.ps1` / `PackageRelease.ps1`) добавить `cache_launch`: `manifest_sha256`, `block.size`, `clean_sha256`, `installed_sha256`, путь payload `bridge/cache-startup.oodle`, `original` не хранить (достаточно sha).
   - Поиск: `Saved/kscache/AssetsVersion.txt` → версия `N` → `Saved/kscache/N/pakchunk0-Windows.pak`. Сверить sha `Saved/kscache/package_*.manifest` с `manifest_sha256` (если не совпал — статус «версия игры не поддерживается», ничего не писать). Найти в паке блок длины `size` с sha `clean_sha256` (или `installed_sha256` = уже стоит): поиск по первым 64 байтам `original` (их хранить в json, это не секрет), потоково, без чтения 112 МБ целиком. Ровно одно совпадение, иначе отказ.
   - Запись: бэкап оригинального блока в `Saved/RussianPatchBackups/cache-launch-<N>.block` + смещение, запись, повторное чтение и проверка sha, откат при несовпадении (как `WriteBridgeBlock`).
   - Если в кеше нет `pakchunk0` (старые сборки), работать как раньше, только с базовым паком. Если в `kscache/N` есть `pakchunk0`, но manifest неизвестен — статус «Игра обновилась, нужна новая версия русификатора» (новый текст в `Ui`).
   - `VerifyInstallation` / `InspectStatus`: мост считается установленным, только если стоит блок, который реально загружается (кеш, если `pakchunk0` в кеше есть, иначе базовый пак).
   - `Uninstall`: восстановить блок кеша из бэкапа (только если текущий = `installed_sha256`).
   - Тесты `tools/InstallerCoreTests.cs`: поддельный `Saved/kscache` (AssetsVersion, manifest, pak со случайными байтами и вставленным «original» на случайном смещении): установка, повторная установка, удаление, неизвестный manifest, два совпадения, блок уже установлен, нет `pakchunk0` в кеше.
6. Документы: `docs/ARCHITECTURE.md` (мост в кеше, компаньоны, exact-source), `docs/PROJECT_MAP.md`, `docs/LESSONS.md` (урок: «хотпатч может принести свой `pakchunk0` в `Saved/kscache/<ver>/` — он перекрывает базовый пак; проверять `kscache` после каждого обновления игры»), `vendor/cpdd/BASE.json` → v2.7.1 (только для синхронизированных компонентов; в TASK отметить, что `Init.lua` остаётся на базе 2.6.4).
7. `VerifyPatch.ps1`, тесты установщика, `PackageRelease.ps1`, коммит, релиз v3.1.0-RU **после** проверки пользователем (сначала дать ему zip через `-DataOnly` или exe из `build/`).

### Этап B — новые строки (отдельные чаты перевода)
- После этапа A: `SyncCpdd.ps1 -Tag v2.7.1 -Components shards -Apply` → батч `batch_043_cpdd_271.json` (≈9408 строк, `source_cn` + `ref_en`, `target_ru` пустой). Проверить количество и что `source_cn` не дублирует наши батчи (сравнение по семантике ShardCompiler).
- Перевод — по `/translate-pack` пачками, отдельные чаты. Промпты для каждой пачки выдаёт этот аналитический чат или чат исполнения **после** создания батча (по шаблону из `.claude/skills/translate-pack/SKILL.md`). В чате исполнения кода не переводить.
- Строки, которых нет и у CPDD, ловятся потом обычной диагностикой (`absoluteru_dev.lua`, `StringDbGaps.ps1`).

#### Порядок пачек (этап B)
- Пачка 1: создать батч `SyncCpdd.ps1 -Tag v2.7.1 -SkipDownload -Components shards -Apply` (имя выберет скрипт: следующий свободный номер, `batch_NNN_cpdd_271.json`), добавить строку в `BATCH_MANIFEST.md`, затем шаги 2–7 скилла (без `StringDbGaps -Report`: логов для этой пачки нет).
- Пачки 2–5: тот же батч, продолжение (`-ExportNew` берёт только пустые `target_ru`). Всего ≈9408 строк ≈ 5 чатов по 40 чанков.

### Этап C — картинки (BakedText), отдельная задача
Наш `blocks.bin` рассчитан на старые смещения `.ucas`. Установщик пропускает несовпадающие блоки (sha), так что вреда нет, но картинки могут остаться китайскими. Перенос `baked_images` CPDD (профили по сборкам, пути в кеше) — отдельный TASK после этапа A.

## Риски
- Игра может сверять `kscache` с `local.cache` и перекачать пак: тогда мост пропадёт после следующего запуска. CPDD патчит так же (`touches_game_cache: true`), но живого подтверждения в их релизе нет. Проверка — в чек-листе (mtime пака не меняется, мост в логе на 2-м запуске).
- Каждое следующее обновление игры с новым `pakchunk0` в кеше снова сломает запуск, пока не будет новой `cache_launch` (обычно её первым выпускает CPDD → `SyncCpdd`).
- `cache-startup.oodle` от CPDD мы не можем прочитать (Oodle, в системе нет декомпрессора). Вызывает ли он `CPDDTranslation.lua` или его компаньон, неизвестно. Класть оба файла (они совпадают с CPDD).

## Проверка
- Автоматическая: `VerifyPatch.ps1`; `InstallerCoreTests.exe` (новые сценарии кеша); офлайн-сверка парсера с компилятором (0 расхождений); `VerifyBatch.ps1` для нового батча.
- Чек-лист пользователя (после установки, игра закрыта во время установки):
  1. Окно установщика: статус «Русский установлен», в журнале строка про блок в `kscache\2218968`.
  2. Запуск. `C7.log`: есть `[LOMModLoader] bootstrap path=`, `[LOMModLoader] compile probe startup=…`, `[CPDDRuntimeFix] installed translated localization lookup`, `[CPDDRuntimeFix] shard load path=…` (прислать значения этих строк).
  3. Экран входа и меню — на русском. Открыть персонажа, инвентарь, квест: текст русский, нет посторонних (не по смыслу) английских или русских строк.
  4. Перезапустить игру второй раз: перевод на месте, в `C7.log` снова `[LOMModLoader]`; дата изменения `Saved\kscache\2218968\pakchunk0-Windows.pak` = время установки (игра не перекачала пак).
  5. Удаление русификатором → игра запускается на китайском без ошибок; установка снова → русский.

## Итог этапа A (чат исполнения, 2026-10-15)
- **п.1 SyncCpdd.** Компаньоны `*.lua.compat.luac` относятся к компоненту своего `.lua` и копируются только при побайтном равенстве нашего `.lua` и CPDD-шного. Таких 265: `CPDDTranslation`, `manifest`, `translation-overrides`, 256 `LanguageSourceIndex_*`, `DesktopChat`, `DpsMeter`, `DpsTelemetry`, `EngineIniBridge`, `ServerScheduleFix`, `WidgetNameIndex`. Реестр `vendor/cpdd/companions.json` хранит sha `.lua`, а `VerifyPatch.ps1` по нему выдаёт ERROR, если исходник поменялся. Компаньонов для `bootstrap`, `Init` и шардов нет: файлы отличаются от CPDD-шных. `bridge/cache-startup.oodle` скопирован. База стала покомпонентной: `BASE.json → tag v2.7.1`, а `component_bases` держит на v2.6.4 `Init.lua`, `shards` и `bakedtext`. `Init.lua` по задаче не мержится, шарды — этап B, BakedText — этап C. `bootstrap.lua` перенесён руками и переведён на 2.7.1.
- **п.2 Алиасы — решение.** Все цели `Overrides` в `translation-overrides.lua` ведут на английский байткод CPDD, а каталог `cpdd_translation` совпадает с CPDD 46/46. Русских алиасов среди них нет, поэтому все 7 имён из `deniedTranslationAliases` запрещены, как у CPDD. Наш механизм оверлея сохранён в виде exact-source: оригинальная таблица игры текущей сборки плюс русский перевод по китайскому значению (`merge_overlay` → `translator(nil, cn, key, name)`). Он не опирается на ID и новых ключей не вставляет.
- **п.3 Парсер.** `runtimeFixes.parseDataLiteral` и `runtimeFixes.loadDataModule` (`Init.lua`) работают для шардов, LSI и `WidgetNameIndex`. Интерпретатора Lua на машине нет, поэтому сверка сделана C#-эквивалентом `tools/LuaDataCheck.exe` (лексер по семантике `llex` Lua 5.1 и построчный порт парсера). Результат: 1281 файл, 377 391 запись, 0 ошибок разбора, 0 расхождений.
- **п.4.** Из `getDirectTable` убран кандидат `cpdd_translation…StringDB_CN_Data`. Таблицы игры `StringDB_EN/CN_Data` оставлены.
- **п.5 Установщик.** Реализовано всё из п.5 и проверено на реальном кеше (только чтение): `InspectCache` = `Clean`, версия 2218968, смещение 41063360, поиск занимает 0,2 с. Базовый блок у пользователя — мост v3.0.11, статус `NotInstalled`: мост перекрыт кешем, всё верно. Тесты `InstallerCoreTests.exe`: 319 пройдено, 0 провалено, 9 из них — новые сценарии kscache (включая откат кеша, если запись в базовый пак не удалась, и повторную загрузку пака игрой).
- **Риск (не исправлялся, вне задачи):** шаги 1–2 `TranslateDatabaseString` (русские правки по ID из `aggregateOverrides`/`splitOverrides`) остаются. Если ID в 2218968 сдвинулись, такие правки могут подставить чужую строку. Признак в игре — русский текст «не по смыслу». Проверка — пункт 3 чек-листа. Если подтвердится, нужен отдельный TASK.
- Версия v3.1.0-RU: `Init.lua` VERSION 3.1.0-RU, `bootstrap` 0.4.6-RU, установщик 3.1.0-RU. Релиз не опубликован: ждёт чек-листа.

## Промпт для чата исполнения
> Выполни этап A из `docs/tasks/TASK-032-game-update-2218968.md` (обновление игры 2218968: мост в `Saved/kscache`, загрузка данных без компиляции, exact-source, синхронизация с CPDD v2.7.1 без `Init.lua`). Материалы CPDD уже скачаны в `reference/cpdd/v2.7.1/` (отчёт `SYNC_REPORT.md`, `unpacked/`). Папку игры только читать (`D:\Games\GMZZLauncher\Game\C7\Saved\kscache`), логику установщика проверять тестами `tools/InstallerCoreTests.exe` на поддельных папках в `temp/`. Порядок: п.1 (SyncCpdd + правило `*.compat.luac` + `cache-startup.oodle`), п.2 (`bootstrap.lua`), п.3 (парсер данных + офлайн-сверка всех шардов и индексов, 0 расхождений), п.4 (`directLookup`), п.5 (установщик + тесты), п.6 (документы). Не переводить строки и не создавать батч новых строк (это этап B). Собрать exe и zip в `build/`, закоммитить; релиз не публиковать, пока пользователь не пройдёт чек-лист из TASK. В конце дать пользователю чек-лист.
