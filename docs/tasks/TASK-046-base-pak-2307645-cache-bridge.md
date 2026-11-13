# TASK-046: поддержка базового пака 2307645 мостом `cache-startup.oodle`

## Симптом
TASK-044: после обновления 2307645 перевод не загружается, установщик не знает новый базовый `pakchunk0-Windows.pak`.

## Первопричина (TASK-045, «Результат»)
- Новый базовый пак: 443251659 байт, sha `7791a5fb558ac0757e3c0aa6becd81318a2d453fb477b5eeba0045cc64ccb369`.
- По смещению **422563913** в нём лежит блок запуска размером 5258 байт с sha `3124ee28ea3b4db83666da313d5e022eaef882d191356d5e38b86d94c6173084`. Это тот же чистый блок, что был в кеше 2218968 (`installer/supported_game.json:23`).
- Мост для этого блока уже лежит в `patch_payload/bridge/cache-startup.oodle` (sha `ee48b48a…`, `supported_game.json:24`).
- sha пака после записи моста: `21bc7187494faaba8888f5858f62eba94606e125311620736950f1556c0f04bc`, размер прежний.
- Сейчас мост базового пака зашит в код: `InstallerCore.cs:284` (`BridgeBlockPayloadRel = bridge\LaunchInstance.native-bridge.padded.oodle`), а также `PackageRelease.ps1:116`, `VerifyPatch.ps1:14`, `InstallerCoreTests.cs:242`.

## План
1. `base_launch_block` получает необязательное поле `payload` (по умолчанию `bridge/LaunchInstance.native-bridge.padded.oodle`, для старых данных). `InstallerCore` читает и пишет его (`ToJson`), а `BridgeBlockPayloadRel` заменяется значением из данных. `PackageRelease.ps1:116` и `VerifyPatch.ps1:14` берут путь из `supported_game.json`.
2. `installer/supported_game.json`: `game_build` `1.2018737.2307645`; `supported_base_paks` — новый пак (sha `7791a5fb…`, 443251659); `base_launch_block` — `offset 422563913`, `size 5258`, `clean_sha256 3124ee28…`, `installed_sha256 ee48b48a…`, `installed_pak_sha256 21bc7187…`, `installed_pak_size 443251659`, `payload bridge/cache-startup.oodle`; `source` — `TASK-045 (own mapping, CPDD bridge reused)`. Старый пак 2044036 убрать: он больше не встречается. Если поддержку старого пака придётся оставить, это отдельное решение и формат 3 со списком блоков.
3. `cache_launch`: в кеше 2307645 блока нет. Установщик не должен падать и не должен считать установку неполной, если блок в кеше не найден, а базовый пак пропатчен (проверить `InstallerCore.cs` в местах поиска `cache_launch` и статуса). Если `cache_launch` нужен только для старых хотпатчей, сделать его необязательным или оставить, но с мягким результатом `NotFound`. Не ослаблять проверку sha: поверх несовпавших байт не писать.
4. Тесты `tools/InstallerCoreTests.cs` (поддельная папка в `temp/`): пак со вставленным блоком `3124ee28…` по смещению из данных → установка пишет `cache-startup.oodle` и получает ожидаемый sha; повтор идемпотентен; откат возвращает `7791a5fb…`; данные без `payload` → старый мост; кеш без блока → не ошибка.
5. `BuildTools.ps1`, `InstallerCoreTests.exe`, `VerifyPatch.ps1`. Версия v3.1.6-RU (`installer/AppInfo.cs`), `min_installer_version` = `3.1.6-RU` (старые установщики не знают `payload` и записали бы не тот мост). `PackageRelease.ps1`, коммит, `-Publish` только после подтверждения пользователя.
6. Обновить TASK-044: решено через TASK-046, ждать CPDD не нужно.

## Проверка
- Автоматически: тесты зелёные, `VerifyPatch` чистый.
- Чек-лист пользователю:
  1. Новый установщик показывает поддерживаемую версию игры, установка проходит без «неизвестная версия».
  2. В игре: `Saved/Logs/C7.log` содержит `[LOMModLoader] bootstrap path=` и `translation overlays applied … entries=`.
  3. Меню и диалоги на русском.
  4. После «Восстановить файлы» в лаунчере sha пака снова `7791a5fb…` (или установщик видит чистый пак).

## Промпт для чата исполнения
> Выполни `docs/tasks/TASK-046-base-pak-2307645-cache-bridge.md`: поле `payload` в `base_launch_block` (InstallerCore, ToJson, PackageRelease, VerifyPatch, тесты), новый `supported_game.json` под пак `7791a5fb…` (смещение 422563913, мост `bridge/cache-startup.oodle`, `installed_pak_sha256 21bc7187…`), мягкое поведение без блока в кеше, тесты на поддельной папке в `temp/`, BuildTools, тесты, VerifyPatch, v3.1.6-RU, `min_installer_version 3.1.6-RU`, PackageRelease, коммит. Публикацию — после моего подтверждения. Папку игры не трогать, игру и установщик не запускать.

## Результат (2026-11-13, v3.1.6-RU, не опубликован)
- `InstallerCore`: `SupportedGame.BasePayload` читает поле `base_launch_block.payload`, по умолчанию `bridge/LaunchInstance.native-bridge.padded.oodle`. `ToJson` пишет его, только если оно отличается от значения по умолчанию. Значения с `..` и `:` отвергаются. `Install` берёт мост базового пака из этого поля.
- Новое состояние кеша `CacheState.NoLaunchBlock`. Условия: `local.cache` прочитан, записи с ключом `entry_id` нет, а в паке папки `AssetsVersion` нет ни одной головы блока, даже «заголовок совпал». Тогда считается только базовый пак (`InstallerCore.BaseBlockCounts`): так работают `InspectStatus`, `Install` (шаг [2/6]) и `VerifyInstallation`. Без `local.cache` или без `entry_id` установщик, как и раньше, отказывает. На копии реального кеша (`temp/real-kscache`, `--probe-cache`) получилось `NoLaunchBlock`, а до правки было `UnsupportedBuild`, то есть именно этот отказ увидел бы пользователь.
- `installer/supported_game.json` заточен под 2307645. `cache_launch` оставлен: по `entry_id` установщик отличает «в кеше нет блока» от «в кеше чужой блок».
- `PackageRelease.ps1` и `VerifyPatch.ps1` берут мост из `base_launch_block.payload`.
- Тесты: 528/528. Новые сценарии: `NoLaunchBlock` (установка, повтор, удаление, отказ без `local.cache` или `entry_id`), «нет записи, но в кеше есть голова блока → отказ», поле `payload`. `VerifyPatch` чистый, кроме ожидаемого WARN «ключи StringDB сняты на 2295021». `--check-payload` по собранному zip: всё OK.
- Не сделано: публикация (ждёт подтверждения), выгрузка новых строк обновления 2307645 (StringDB) и проверка в игре.
- Внимание: `SyncCpdd.ps1` при генерации `supported_game.json` из CPDD поле `payload` не знает и `min_installer_version` ставит `3.1.1-RU` (`tools/SyncCpdd.ps1:363`). Перед следующим `-Apply` с `supported_game.json` это нужно учесть.