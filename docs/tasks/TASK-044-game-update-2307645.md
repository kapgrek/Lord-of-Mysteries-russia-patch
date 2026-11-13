# TASK-044: обновление игры 2307645 (новый базовый pakchunk0)

## Симптом
12.11.2026 вышло обновление игры. После него перевод не загружается: русского текста в игре нет. Установленный патч v3.1.5-RU.

## Первопричина
Обновление заменило **базовый** `Content/Paks/pakchunk0-Windows.pak`. Хотпатча в кеше для этого недостаточно. Блок запуска, под который собраны наш мост и мост CPDD, в новом паке отсутствует. Мост не выполняется.

Данные с ПК пользователя (снято только чтением):
- `Saved/kscache/AssetsVersion.txt` = `1.2018737.2307645.Online_Shipping`. Появились `package_2306710.manifest` (12.11 21:11) и папка `kscache/2307645/`.
- `Content/Paks/pakchunk0-Windows.pak`: размер **443251659** (был 446910011), sha256 `7791a5fb558ac0757e3c0aa6becd81318a2d453fb477b5eeba0045cc64ccb369`, mtime 12.11 20:17. Этой сборки нет в `installer/supported_game.json:5-8` (`game_build 1.2018737.2044036`, sha `abbadeea…`).
- Чистый блок запуска базового пака (`RussianPatchBackups/launch-original.block`, 4660 байт, sha `566e72d6…` = `supported_game.json:13`) в новом паке не найден даже по первым 32 байтам. Значит, `LaunchInstance` пересобран, и старый `bridge/LaunchInstance.native-bridge.padded.oodle` к нему не подходит.
- Кеш: из `pakchunk0-Windows.pak` остался только `kscache/2307645/pakchunk0-Windows.pak` (22227 байт, дельта). Блока `3124ee28…` (`cache_launch.clean_sha256`, `supported_game.json:23`) в нём нет, а старого `kscache/2218968/pakchunk0-Windows.pak` больше нет.
- Новые файлы того же обновления: `pakchunk0-ext-Windows_s1.upak` (836 МБ), `pakchunk0-Windows_s1.ucas`, `pakchunk0optional-Windows_s1.ucas`. Также перезаписан `pakchunk0-Windows.ucas` (BakedText).
- Лог. В `Saved/Logs/C7-backup-2026.11.10-15.56.37.log` (до обновления) есть `CPDDTranslation.lua:6 [LOMModLoader] bootstrap path=…` и `translation overlays applied … entries=67402`. В текущем `C7.log` (12.11 21:29) нет ни одной строки `LOMModLoader`/`CPDDTranslation`: работает только стоковый `LaunchInstance.lua:63…125`.

**Собрать мост сами мы не можем:** декомпрессора Oodle нет (`TASK-032-game-update-2218968.md:69`, `TASK-043…md:29`). CPDD (`Lani27/lord-of-mysteries-english-patch`) на 12.11 ещё не выпустил релиз под эту сборку: последний `v2.7.5` от 24.10, он уже в `vendor/cpdd/BASE.json`.

## Статус
Решено без релиза CPDD: TASK-045 нашёл в новом базовом паке блок 3124ee28… (смещение 422563913), мост ridge/cache-startup.oodle ставится в базовый пак. Реализация в TASK-046 (v3.1.6-RU). План ниже устарел.

## План
Исполнять только после выхода релиза CPDD новее v2.7.5, где в `release.json` есть `game_build`/`supported_base_paks` с sha `7791a5fb…` или `AssetsVersion …2307645`.

1. `gh release list -R Lani27/lord-of-mysteries-english-patch -L 3`. Если нового релиза нет, остановиться и сообщить пользователю.
2. `tools/SyncCpdd.ps1 -Tag <новый тег>` → изучить `reference/cpdd/<tag>/SYNC_REPORT.md`. Проверить:
   - что `supported_base_paks` содержит sha `7791a5fb…` / размер 443251659;
   - новый `launch_block` (offset, clean/installed sha) и мост `LaunchInstance.native-bridge.padded.oodle`, у которого мог измениться размер (не 4660);
   - есть ли `cache_launch` в новом релизе. Сейчас блока запуска в кеше нет, поэтому `cache_launch` может отсутствовать или стать необязательным. Установщик не должен падать, если `cache_launch` нет или блок не найден в кеше, а базовый пак поддерживается. Проверить это в `InstallerCore.cs` и тестах;
   - не упоминает ли CPDD `pakchunk0-ext-Windows_s1.upak` / `_s1.ucas` (новый формат контейнера);
   - BakedText: совпадают ли в новом релизе CPDD блоки для `pakchunk0-Windows.ucas` с нашим `BakedText/manifest.json`. Если контейнер сменился, пропатченные блоки, скорее всего, пропускаются (`InstallerCore.cs:939-941`).
3. `SyncCpdd.ps1 -Apply` для моста, `supported_game.json`, `bridge/*`, `CPDDTranslation.lua`, `bootstrap.lua` (3-way) и при необходимости компаньонов/BakedText. `Init.lua` и шарды на v2.6.4 не трогать без отдельного решения. Удаления только с `-AllowRemoval` и с объяснением.
4. Новые строки обновления: по `SYNC_REPORT.md` (новые строки шардов CPDD → батч) составить отдельный промпт `/translate-pack` для чата перевода. В этом чате не переводить.
5. `tools/BuildTools.ps1`, `tools/InstallerCoreTests.exe` (добавить сценарий «новый базовый пак, без `cache_launch` в кеше» на поддельной папке в `temp/`), `tools/VerifyPatch.ps1`.
6. Поднять версию (`installer/AppInfo.cs`) до v3.1.6-RU, `PackageRelease.ps1`, коммит, `-Publish` (по подтверждению пользователя).

Если CPDD долго не выпускает релиз (несколько дней), завести отдельный TASK на сборку своего моста: открытый Kraken-декомпрессор (`ooz`), распаковка нового `LaunchInstance`, вставка вызова `CPDDTranslation`, повторная упаковка в размер блока.

## Проверка
- Автоматическая: `InstallerCoreTests.exe` (все зелёные), `VerifyPatch.ps1`, `InstallerCoreTests.exe --probe-cache` на копии `kscache` в `temp/`.
- Чек-лист для пользователя:
  1. Запустить новый установщик. Статус должен показать поддерживаемую версию игры, установка проходит без «неизвестная версия».
  2. Запустить игру. В `Saved/Logs/C7.log` есть `[LOMModLoader] bootstrap path=` и `translation overlays applied … entries=`.
  3. Меню и диалоги на русском. Текстуры BakedText (надписи на картинках) тоже на русском, иначе это отдельная задача.

## Промпт для чата исполнения
> Выполни `docs/tasks/TASK-044-game-update-2307645.md`. Сначала проверь, вышел ли релиз CPDD новее v2.7.5 (`gh release list -R Lani27/lord-of-mysteries-english-patch -L 3`) и поддерживает ли он базовый pakchunk0 sha `7791a5fb…` (размер 443251659). Если не вышел — остановись и сообщи. Если вышел — `SyncCpdd.ps1 -Tag <tag>`, разбор `SYNC_REPORT.md` по пунктам плана, `-Apply` моста/`supported_game.json`/`bootstrap.lua`, проверка установщика без `cache_launch` (тест на поддельной папке), BuildTools, тесты, VerifyPatch, версия v3.1.6-RU, PackageRelease, коммит; публикацию — после моего подтверждения. Новые строки не переводи — дай отдельный промпт для `/translate-pack`. Папку игры не трогать, игру и установщик не запускать.
