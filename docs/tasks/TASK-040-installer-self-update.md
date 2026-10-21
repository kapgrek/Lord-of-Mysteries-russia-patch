# TASK-040: самообновление установщика — не перекачивать exe после каждого хотпатча

## Симптом (2026-10-21)
После хотпатча 2228458 у пользователя открыт установщик 3.1.1-RU. Статус «ИГРА ОБНОВИЛАСЬ — НУЖНА НОВАЯ ВЕРСИЯ», строка «Дождитесь обновления русификатора», кнопка «Установить» неактивна. При этом в журнале того же окна:
```
18:02:05 Проверка кеша: UnsupportedBuild, версия 2228458, манифест package_2018737.manifest не совпадает с поддерживаемым; AssetsVersion.txt: 1.2018737.2228458.Online_Shipping
18:02:06 Последняя версия на GitHub: v3.1.2-RU (82 МБ)
```
Исправление (TASK-039) уже опубликовано в v3.1.2-RU (тег на `a5d25daf`), но игрок об этом не узнаёт: ему нужно самому найти релиз и скачать новый exe. Так будет после каждого хотпатча, который ломает логику кеша. Пользователь: «сделай так, чтоб не надо было вечно перекачивать лаунчер».

## Первопричина
Данные патча установщик и так берёт из последнего релиза (`PayloadSource.ResolveAsync` → `DownloadAsync`, `installer/PayloadSource.cs:114-160`, `:215-267`). А вся логика поиска блока запуска в `kscache` (`InspectCache`, `KsLocalCache`, проверки `supported_game.json`) **скомпилирована в exe**. Поэтому при изменениях в механизме обновлений игры нужен новый exe, а механизма его доставки нет:
- `installer/Ui/MainWindow.cs:450-458` `FetchLatestAsync` узнаёт `manifest.Version` и только пишет его в журнал. Новее ли релиз, чем сам exe (`AppInfo.Version`), не проверяется.
- `installer/Ui/MainWindow.cs:324`, `:328` — текст «Дождитесь обновления русификатора», даже когда обновление уже вышло.
- `installer/PatcherBackend.cs:264-270` `InstallerTooOld` — только отказ со ссылкой «скачайте … со страницы релиза».
- `installer/PayloadSource.cs:316-385` `FetchLatestReleaseInfo` не читает asset exe, хотя `release.json` уже содержит `patcher_asset {name, sha256, size}` (`tools/PackageRelease.ps1:149-153`). Проверка подлинности для нового exe уже есть, кода нет.

## Решение: установщик обновляет сам себя при запуске
Автоматически, без вопроса. Если GitHub отдал релиз новее `AppInfo.Version`, окно скачивает exe этого релиза, сверяет SHA-256 с `release.json`, подменяет себя и перезапускается. Пользователь видит в журнале строку и через несколько секунд новое окно.

**Важно:** у пользователя на руках 3.1.1 без этого кода. Один последний раз exe придётся скачать вручную (версия с самообновлением, 3.1.3-RU). Дальше обновления будут приходить сами.

## План

### Этап 1. Сведения об exe в манифесте (`installer/PayloadSource.cs`)
1. `ReleaseManifest`: поля `PatcherDownloadUrl`, `PatcherApiUrl`, `PatcherSize`, `PatcherSha256`, `PatcherName`. `FromReleaseJson` читает `patcher_asset` (`name`, `sha256` в нижнем регистре, `size`).
2. `FetchLatestReleaseInfo`: в цикле по `assets` запоминать asset с именем `patcher_asset.name` (по умолчанию `Lord-of-Mysteries-Russian-Patch.exe`): `browser_download_url`, `url`, `size`. С токеном использовать API-адрес, как для zip (`:367`). Запасной путь без API (`:376-384`): `https://github.com/<repo>/releases/download/<release_tag>/<name>`, **с тегом**, а не `latest`, чтобы exe и `release.json` были из одного релиза.
3. Без `PatcherSha256` самообновление не выполняется вообще (exe без проверки не запускаем).

### Этап 2. Логика подмены (`installer/SelfUpdate.cs`, новый файл)
Чистые функции с путями в параметрах, чтобы их можно было тестировать в `temp/`:
4. `static bool IsNewer(ReleaseManifest m)` = `m != null && PatcherSha256 != null && CompareVersions(m.Version, AppInfo.Version) > 0`.
5. `static async Task<string> DownloadAsync(ReleaseManifest m, string targetDir, log, progress, token)`: скачать в `<targetDir>\<name>.new` через `GitHubReleaseClient.DownloadFileWithProgressAsync`, сверить размер и SHA-256. При несовпадении удалить файл и вернуть `null` с записью в журнал «SHA-256 нового установщика не совпадает с release.json, обновление пропущено».
6. `static string Swap(string currentExe, string newFile, log)`: Windows разрешает **переименовать** запущенный exe. Шаги: `currentExe` → `currentExe + ".old"` (старый `.old` перед этим удалить, если есть), `newFile` → `currentExe`. Если второй шаг упал, вернуть `.old` на место. Вернуть путь exe для запуска или `null`.
7. Запасной вариант, если папка exe недоступна для записи (Program Files, флешка только для чтения, `UnauthorizedAccessException` или `IOException` на шаге 6): положить новый exe в `%LOCALAPPDATA%\LotmRussianPatch\installer\<name>` и запустить оттуда. В журнале сообщить: «Новая версия сохранена в …, дальше запускайте её».
8. `static void CleanupOld(string currentExe)`: при старте молча удалить `<exe>.old` и `<exe>.new` (`try/catch`, файл может быть ещё занят старым процессом, тогда до следующего раза).
9. Перезапуск: `Process.Start(newExe, "--updated-from " + AppInfo.Version + <исходные аргументы>)`, затем `Application.Current.Shutdown()`. Новый процесс должен подождать, пока старый освободит exe: на шаге 8 повторять удаление `.old` до ~3 с в фоне, не блокируя окно.

### Этап 3. Встраивание (`Program.cs`, `Ui/MainWindow.cs`)
10. `Program.Main`: разобрать `--updated-from <ver>` (как `--payload`, `:37-41`), сохранить в `SelfUpdate.UpdatedFrom`. Вызвать `SelfUpdate.CleanupOld(exe)`. Флаг `--no-self-update` отключает механизм.
11. Когда самообновление **не** выполняется: задан `--payload`, `--no-self-update`, переменная `LOTM_PATCH_REPO` (разработка), CLI-команды (`--install` и прочие: без окна никаких подмен), а также задан `UpdatedFrom` и релиз всё равно новее (защита от цикла, если в релиз попал exe со старым `AppInfo.Version`). В последнем случае записать в журнал: «Самообновление уже выполнялось, но версия не сменилась: скачайте установщик вручную».
12. `MainWindow.FetchLatestAsync` (`:450`): если `SelfUpdate.IsNewer(manifest)` и условия п.11 позволяют: `busy = true`, статус «ОБНОВЛЕНИЕ УСТАНОВЩИКА ДО vX», в журнале `Найден установщик vX, текущий vY: обновление…`, прогресс в том же индикаторе, что и загрузка пакета. Затем `DownloadAsync` → `Swap` → перезапуск. При любой ошибке `busy = false`, в журнал причина, окно продолжает работать как раньше, а строка папки и статус показывают ссылку (п.13).
13. Тексты: в `MainWindow.cs:324`, `:328` и `PatcherBackend.InstallerTooOld` (`:264`), если `latestVersion` новее `AppInfo.Version`, вместо «Дождитесь обновления русификатора» писать «Вышла версия vX — установщик обновится при следующем запуске» (или «… не смог обновиться сам: скачайте Lord-of-Mysteries-Russian-Patch.exe со страницы релиза», если попытка провалилась). «Дождитесь» оставить только для случая, когда новее релиза нет.
14. После перезапуска с `--updated-from`: первая строка журнала `Установщик обновлён: <old> → <AppInfo.Version>`. Её же писать в `installer.log` (`InstallerLog`).
15. Окно не должно терять выбранную папку игры. Сейчас `PatcherBackend.SaveLastGameDir` (`PatcherBackend.cs:183`) вызывается только при установке (`:339`), а при старте папку берёт `LoadLastGameDir` (`:123`). Перед перезапуском вызвать `SaveLastGameDir(gameDir)`, если папка уже выбрана и валидна.

### Этап 4. Тесты (`tools/InstallerCoreTests.cs`)
16. Заглушка `PayloadSource.FetchManifest` (уже используется) и подмена загрузки: вынести в `SelfUpdate` делегат `Download` (по умолчанию `GitHubReleaseClient.DownloadFileWithProgressAsync`), чтобы тест копировал локальный файл.
17. Сценарии на поддельных файлах в `temp/selfupdate-*`:
    - `IsNewer`: 3.1.3 > 3.1.2 → да; равные → нет; нет sha → нет; `v`-префикс тега.
    - Скачанный файл с чужим SHA → `null`, `.new` удалён, исходный exe не тронут.
    - `Swap` успешный: старый стал `.old`, новый на месте исходного, содержимое новое.
    - `Swap`, когда целевой путь защищён (файл открыт с `FileShare.None` или папка только для чтения) → откат, исходный exe цел, срабатывает запасной путь в подменённый `AppDataRoot`.
    - `CleanupOld` удаляет `.old`/`.new`, если они свободны, и не падает, если заняты.
    - `FromReleaseJson` читает `patcher_asset` из реального `build/release.json` формата 2.
18. `tools/BuildTools.ps1`, затем `tools/InstallerCoreTests.exe`: всё зелёное. Установщик в окне не запускать на папке игры (AGENTS.md §1). Ручную проверку самообновления пользователь делает сам.

### Этап 5. Релиз
19. Версия **3.1.3-RU** (`AppInfo.cs`). `min_installer_version` не поднимать. Коммит `feat(installer): TASK-040 self-update from the latest GitHub release`.
20. Сборка `tools/PackageRelease.ps1` без `-Publish`. Проверить, что в `build/release.json` есть `patcher_asset.sha256` = sha256 `build/Lord-of-Mysteries-Russian-Patch.exe`. Отдать пользователю exe. Публиковать только после его проверки.
21. До публикации exe 3.1.3 на релизе 3.1.2 ничего не обновляет: он новее. Настоящую подмену пользователь увидит при выходе следующего релиза (3.1.4): старый 3.1.3 должен обновиться сам. Это и есть пункт 2 чек-листа.
22. `docs/LESSONS.md`: «логика кеша игры живёт в exe, данные в zip; после хотпатча игроки остаются со старым exe → самообновление по `patcher_asset` из `release.json`». `docs/PROJECT_MAP.md`: строка «самообновление установщика → `installer/SelfUpdate.cs`».

## Риски
- **Антивирус / SmartScreen.** Файл, скачанный через `HttpWebRequest`, не получает Mark of the Web, поэтому SmartScreen не спрашивает. Эвристика антивируса на «exe скачал и запустил exe» возможна; запасной путь — сообщение со ссылкой (п.12–13).
- **Битый релиз.** Если в релиз попадёт exe с неверным sha, проверка не пропустит подмену. Если exe со старым `AppInfo.Version` — защита от цикла (п.11).
- **Откат.** Плохой новый exe ломает всех сразу. Смягчение: `.old` лежит рядом до следующего запуска; в `docs` описать ручной откат (переименовать `.old`).
- **Запуск из архива.** Explorer распаковывает exe во временную папку; подмена там сработает, но при следующем запуске из архива снова будет старый. Терпимо, перезапуск всё равно обновит.

## Проверка
- Автоматическая: `InstallerCoreTests.exe` без ошибок, сценарии этапа 4.
- Чек-лист пользователя:
  1. Скачать вручную exe 3.1.3-RU (последний раз), запустить. В журнале `Последняя версия на GitHub: v3.1.3-RU`, никакого обновления, кнопки работают как в 3.1.2.
  2. После выхода 3.1.4 запустить **тот же** файл 3.1.3. В журнале `Найден установщик v3.1.4-RU, текущий 3.1.3-RU: обновление…`, затем окно закрывается и открывается снова; заголовок `3.1.4-RU`, первая строка журнала `Установщик обновлён: 3.1.3-RU → 3.1.4-RU`. Рядом с exe нет `.old`/`.new` (после второго запуска).
  3. В `%LOCALAPPDATA%\AbsoluteRU\installer.log` те же строки.

## Промпт для чата исполнения
> Выполни `docs/tasks/TASK-040-installer-self-update.md`: установщик при запуске окна сам обновляется до последнего релиза GitHub. `ReleaseManifest` читает `patcher_asset` из `release.json` и asset exe из API (запасной URL по тегу), новый `installer/SelfUpdate.cs`: `IsNewer`, загрузка в `.new` с проверкой SHA-256 и размера, подмена через переименование запущенного exe в `.old`, запасной путь в `%LOCALAPPDATA%\LotmRussianPatch\installer`, перезапуск с `--updated-from`, очистка `.old` при старте, защита от цикла, отключение при `--payload`/`--no-self-update`/`LOTM_PATCH_REPO`/CLI. Встроить в `MainWindow.FetchLatestAsync`, заменить «Дождитесь обновления русификатора» на текст о вышедшей версии, когда релиз новее exe. Тесты этапа 4 в `tools/InstallerCoreTests.cs` на файлах в `temp/`, сборка `tools/BuildTools.ps1`, прогон `tools/InstallerCoreTests.exe`. Папку игры не трогать, установщик и игру не запускать (AGENTS.md §1). Версия 3.1.3-RU, документы по этапу 5, коммит; exe и zip собрать `PackageRelease.ps1` без `-Publish`. В конце дай пользователю чек-лист из раздела «Проверка».
