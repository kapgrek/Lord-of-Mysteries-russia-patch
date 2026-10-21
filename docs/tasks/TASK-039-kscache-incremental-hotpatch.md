# TASK-039: инкрементальный хотпатч 2228458 — установщик ищет блок запуска не в той папке кеша

## Симптом (2026-10-21)
После обновления игры установщик 3.1.1-RU не даёт ставить и обновлять русификатор: статус «ИГРА ОБНОВИЛАСЬ — НУЖНА НОВАЯ ВЕРСИЯ», кнопка установки неактивна. `%LOCALAPPDATA%\AbsoluteRU\installer.log`:
```
2026-10-21 17:11:02 Проверка кеша: UnsupportedBuild, версия 2228458, манифест package_2018737.manifest не совпадает с поддерживаемым; AssetsVersion.txt: 1.2018737.2228458.Online_Shipping
```
При этом **перевод в игре работает**: `C7.log` сессии 17:14 содержит `[LOMModLoader] bootstrap path=…`, `[CPDDRuntimeFix] v3.1.1-RU active hooks_installed=26`, `translation overlays applied modules=1 entries=67331`.

## Первопричина
Хотпатч 2228458 **инкрементальный**: он не перекачал pakchunk0 целиком, а положил рядом маленький пак с изменёнными фрагментами. Блок запуска (и наш мост в нём) остался в старой папке 2218968, и игра его по-прежнему читает. Установщик же жёстко берёт пак из папки текущей версии и требует точного sha манифеста.

Факты (только чтение папки игры):
- `Saved\kscache\AssetsVersion.txt` = `1.2018737.2228458.Online_Shipping` (21.10 17:14:56).
- `Saved\kscache\2228458\pakchunk0-Windows.pak` — **302 027 байт** (в 2218968 — 224 057 784). Ни `original_head_hex`, ни `installed_head_hex` из `cache_launch` в нём нет.
- `Saved\kscache\local.cache` (12 239 452 байт) разобран до конца без ошибок: `2218968/pakchunk0-Windows.pak` — 35 972 записи (было 36 018), `2228458/pakchunk0-Windows.pak` — 49 записей. Запись со смещением **186 467 874** для `2218968/pakchunk0-Windows.pak` жива, sha256 5258 байт по этому смещению = `ee48b48a…` = `cache_launch.installed_sha256`: **мост стоит и живой**.
- Ключ этой записи в `local.cache`: `e5b5a377c686bc9e96abc007 4bc268a7`. Первые 12 байт = `external_bridge.cache_launch.entry_id` из CPDD `release.json` v2.7.4 (`e5b5a377c686bc9e96abc007`). То есть CPDD находит блок **по ключу записи в `local.cache`**, а не по папке версии. Наш `SyncCpdd.ps1` поле `entry_id` не переносит.
- `package_2018737.manifest` перезаписан 21.10 17:05:44, sha256 `44d27851…` ≠ `cache_launch.manifest_sha256` `6d23b1cf…`. Манифест меняется с каждым хотпатчем, хотя `manifestId` (2018737) тот же.
- CPDD для 2228458 пока ничего не выпустил (последний релиз v2.7.4 от 17.10), и это ожидаемо: им, судя по `entry_id`, новый релиз не нужен.

Код:
- `installer/InstallerCore.cs:295-308` `FindCachePak`: путь `kscache\<version из AssetsVersion>\pakchunk0-Windows.pak` — берёт новый маленький пак 2228458.
- `installer/InstallerCore.cs:329` `ReadCacheRecordOffset(version, …)` ищет `cache-launch-2228458.json`, а запись лежит в `cache-launch-2218968.json` (`CacheRecordPath`, `:289`) — «установлено» не распознаётся.
- `installer/InstallerCore.cs:339-345`: sha манифеста ≠ → `UnsupportedBuild`.
- `installer/InstallerCore.cs:755-758` (`Install`) отказ «Игра обновилась…»; `installer/Ui/MainWindow.cs:66,323,409,433` — красная строка, статус и `mainButton.IsEnabled = false`.

Проверка `manifest_sha256` лишняя: подлинность блока и так гарантирует полное sha256 5258 байт (`clean_sha256` / `installed_sha256`). Если байты блока совпали, запись моста безопасна при любом манифесте.

## План

### Этап 1. Поиск блока по ключу `local.cache` (`installer/`)
1. **`tools/SyncCpdd.ps1:304-320`**: переносить `cache_launch.entry_id` в `installer/supported_game.json` (`"entry_id": "e5b5a377c686bc9e96abc007"`). Обновить сейчас `installer/supported_game.json` (и копию в `patch_payload`, если она там генерируется) прогоном `SyncCpdd.ps1 -Tag v2.7.4` или правкой генератора и повторным запуском; проверить, что остальные поля не изменились.
2. **`SupportedGame` (`InstallerCore.cs:36`, `:153-171`, `:215`)**: поле `CacheLaunch.EntryId` (hex, необязательное, 0…16 байт), чтение и запись в `ToJson`. Отсутствие поля — старое поведение.
3. **`KsLocalCache`**: новый метод `static List<Entry> FindByKeyPrefix(string localCachePath, byte[] keyPrefix)` → записи `{ RelPath, Offset }`, тот же строгий разбор, что в `ChunkStarts` (при нарушении формата `null`). Плюс `ChunkStarts` для найденного `RelPath` (можно одним проходом вернуть всё нужное).
4. **`InspectCache` (`InstallerCore.cs:310`)**, порядок:
   - Если `c.EntryId` задан и `local.cache` прочитан: найти записи с этим префиксом ключа. Ровно одна → пак = `kscache\<RelPath>`, `info.Version` = папка из `RelPath` (2218968), кандидат = смещение записи; проверить sha256 `c.Size` байт: `installed_sha256` → `Installed`, `clean_sha256` → `Clean`, иначе `NotFound` (Detail: «по ключу entry_id блок найден в <RelPath>:<off>, но байты не совпадают»). Больше одной записи → `Ambiguous` с перечнем. Ни одной → дальше старый путь.
   - Старый путь (`FindCachePak` по `AssetsVersion` + скан по голове) остаётся запасным. В нём проверку `manifest_sha256` **ослабить**: при несовпадении не отказывать сразу, а продолжить скан; `UnsupportedBuild` выдавать, только если ни живой чистой, ни живой установленной копии не нашлось. В `Detail` писать оба факта (манифест другой, блок не найден).
   - `ReadCacheRecordOffset` вызывать с версией той папки, где реально лежит блок (`info.Version` после поиска), а не с версией из `AssetsVersion`.
   - Новое поле `CacheInfo.AssetsVersion` (из `AssetsVersion.txt`), чтобы журнал и `info.txt` показывали обе версии: «кеш 2228458, блок запуска в 2218968».
5. **`Install` / удаление** (`InstallerCore.cs:747-790`, `:464`, `:492`, `:514`): запись `cache-launch-<ver>.json` и путь пака — по папке, где найден блок. Проверить, что повторная установка в состоянии «блок в 2218968, кеш 2228458» даёт `Installed` и ничего не пишет, а удаление возвращает оригинальный блок в 2218968.
6. **Сообщения**: в журнале `[2/6]` для этого случая — `-> Мост уже установлен в Saved\kscache\2218968 (кеш обновления 2228458, блок найден по local.cache), блок не перезаписывается.` `LogCollector.cs:127` дописать `entry_id` и найденный `RelPath`.

### Этап 2. Тесты (`tools/InstallerCoreTests.cs`)
7. В `AddCache` (~`:441`) поддержать ключи записей и вторую папку версии. Сценарии:
   - **Инкрементальный хотпатч, мост стоит**: блок в `2218968`, `AssetsVersion` = 2228458, в `2228458\pakchunk0` блока нет, манифест другой → `Installed`, `Version` = 2218968; `Install` ничего в кеш не пишет и завершается успешно.
   - **То же, блок чистый** → `Clean`, мост пишется в `2218968` по смещению записи; `cache-launch-2218968.json` создан.
   - **Ключ найден, байты чужие** → `NotFound`, ничего не записано.
   - **Два ключа с префиксом** → `Ambiguous`.
   - **Нет `entry_id` в `supported_game.json`, манифест другой, блок в папке `AssetsVersion` живой и чистый** → `Clean` (ослабленная проверка манифеста).
   - **Нет `entry_id`, манифест другой, блока нет** → `UnsupportedBuild` (тест `:610-612` и смысл кнопки «Игра обновилась» сохраняются).
   - Существующие сценарии TASK-038 (мёртвые/живые копии) — зелёные.
8. `tools/BuildTools.ps1`, затем `tools/InstallerCoreTests.exe`: всё зелёное.
9. **Реальные данные, только чтение**: скопировать в `temp/real-kscache/C7/Saved/kscache/` файлы `local.cache`, `AssetsVersion.txt`, `package_2018737.manifest`, `2218968\pakchunk0-Windows.pak`, `2228458\pakchunk0-Windows.pak` и `Saved\RussianPatchBackups\*` в `temp/real-kscache/C7/Saved/RussianPatchBackups/`. Прогнать `InspectCache` (режим `--probe-cache` из TASK-038). Ожидается `Installed`, `Version` 2218968, смещение **186467874**. Установщик и игру не запускать (AGENTS.md §1).

### Этап 3. Документы и релиз
10. `docs/LESSONS.md`: «хотпатчи лаунчера бывают инкрементальными: `kscache/<новая ver>/pakchunk0` может быть маленьким дельта-паком, а блок запуска остаётся в старой папке. Искать блок по ключу записи `local.cache` (`entry_id` CPDD), а не по `AssetsVersion.txt`; `manifest_sha256` меняется с каждым хотпатчем и не годится как блокирующая проверка». Обновить memory-заметку о kscache тем же.
11. `docs/ARCHITECTURE.md` / `docs/PROJECT_MAP.md`: `entry_id`, поиск по ключу.
12. Версия **3.1.2-RU**, `min_installer_version` в данных оставить 3.1.1-RU (3.1.1 на этой сборке просто отказывает, а не ломает). Коммит `fix(installer): TASK-039 find cache launch block by local.cache entry key`. Собрать exe и zip (`PackageRelease.ps1` без `-Publish`), отдать пользователю exe из `build/`. Публиковать после его проверки.

## Риски
- Префикс ключа — 12 байт из 16; остальные 4 байта (`4bc268a7`), вероятно, версия/CRC фрагмента и меняются при перекачке. Поэтому сравнивать только префикс длины `entry_id`.
- Если будущий хотпатч перекачает сам блок запуска, ключ останется, но байты станут другими → `NotFound`, установка откажет, игра без моста. Это честный отказ; тогда нужен новый `cache_launch` от CPDD (`SyncCpdd.ps1`).
- Ослабление проверки манифеста на запасном пути: защита остаётся в sha256 всего блока, записи моста «вслепую» нет.

## Проверка
- Автоматическая: `InstallerCoreTests.exe` без ошибок, проба на копии реального кеша — `Installed`, 2218968, 186467874.
- Чек-лист пользователя (новый exe из `build/`, игра закрыта):
  1. Запустить exe 3.1.2-RU. Красной строки «Игра обновилась» нет, статус «УСТАНОВЛЕНО» (или «ДОСТУПНО ОБНОВЛЕНИЕ»), кнопка активна. В `installer.log` строка `Проверка кеша: Installed, версия 2218968 … AssetsVersion.txt: 1.2018737.2228458…`.
  2. Нажать «Установить»/«Обновить»: в журнале `[2/6] -> Мост уже установлен в Saved\kscache\2218968 (кеш обновления 2228458…)`, `✔ Установка завершена`. Размер `Saved\kscache\2218968\pakchunk0-Windows.pak` по-прежнему 224 057 784.
  3. Запустить игру: в `C7.log` `[CPDDRuntimeFix] v3.1.x-RU active` и `translation overlays applied`, меню на русском.

## Промпт для чата исполнения
> Выполни `docs/tasks/TASK-039-kscache-incremental-hotpatch.md`: установщик должен находить блок запуска в `Saved\kscache` по ключу записи `local.cache` (`cache_launch.entry_id` из CPDD release.json, перенести через `tools/SyncCpdd.ps1` в `installer/supported_game.json`), а не по папке из `AssetsVersion.txt`, и не отказывать из-за другого `manifest_sha256`, если байты блока совпали. Правки: `KsLocalCache` (поиск по префиксу ключа), `SupportedGame.CacheLaunch.EntryId`, `InspectCache`/`ReadCacheRecordOffset`/`Install`/удаление по реальной папке блока, сообщения журнала и `LogCollector`. Тесты этапа 2 в `tools/InstallerCoreTests.cs`, сборка `tools/BuildTools.ps1`, прогон `tools/InstallerCoreTests.exe`, проба на копии реального кеша в `temp/real-kscache/` (ожидается `Installed`, папка 2218968, смещение 186467874). Папку игры только читать, установщик и игру не запускать (AGENTS.md §1). Версия 3.1.2-RU, документы по этапу 3, коммит; exe и zip собрать без публикации. В конце дай пользователю чек-лист из раздела «Проверка».
