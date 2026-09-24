# TASK-003: сверка с CPDD (v2.6.3 → v2.6.4), SyncCpdd.ps1, проверка состояния игры

Статус: **анализ завершён** 2026-09-24. Код патча не менялся.

## Исходные данные
- Релизы CPDD: `gh release list -R Lani27/lord-of-mysteries-english-patch`. Последний `v2.6.4` вышел 2026-09-24. С `v2.6.2` установщик не менялся (`Lord-of-Mysteries-English-Patch-2.6.1.exe`), в релизах обновляются только данные.
- Скачано с разрешения пользователя (только v2.6.4): `reference/cpdd/v2.6.4/` — `lom-english-patch-data.zip` (58 012 780 Б, sha256 `008c79f4…f6a7`, совпадает с `SHA256SUMS.txt`), `release.json`, `release.json.sig`, `SHA256SUMS.txt`, распаковано в `unpacked/`. v2.6.3 уже лежала в `reference/cpdd-english/eng_stable/unpacked/`.
- Раскладка в zip: `payload/bridge/LaunchInstance.native-bridge.padded.oodle` и `payload/bridge/game/{Binaries,Saved}/…`. В `release.json → external_bridge.files` перечислены все 1341 файл с `sha256`/`size`. Этот список годится как готовый манифест для сравнения.
- Версии из v2.6.4 не скачивались (v2.5.0, v2.6.0–v2.6.2). Базу нашего патча определяем по git и по метаданным, см. §1.

## 1. От какой версии CPDD наш патч

| Файл | ours | CPDD 2.6.3 | CPDD 2.6.4 | Вывод |
|---|---|---|---|---|
| `bridge/…padded.oodle` | `c0317269…` | = | = | чистый CPDD |
| `Binaries/…/CPDDTranslation.lua` | `d224604d…` | = | = | чистый CPDD |
| `Saved/Mods/manifest.lua`, `translation-overrides.lua` | | = | = | чистый CPDD |
| `DpsMeter.lua` (v1.9.1), `DpsTelemetry.lua`, `DesktopChat.lua`, `EngineIniBridge.lua`, `ServerScheduleFix.lua`, `WidgetNameIndex.lua` | | = | = | чистый CPDD |
| `ExternalDpsMeter/…Combat Meter.exe` (v1.1.0) | `ca0fbd87…` | = | = | чистый CPDD |
| `lua/cpdd_translation/**` (46 файлов байткода) | | **46/46 =** | 45/46 (другой `StringDB_CN_Data.lua`) | **данные = v2.6.3** |
| `LanguageSourceIndex_*` (256) | | 256 = | 256 = | чистый CPDD, не менялся |
| `BakedText/blocks.bin` | `9c7788e5…` | = | = | чистый CPDD |
| `BakedText/manifest.json` | 1 785 325 Б | 1 271 879 Б | = 2.6.3 | данные те же (сравнение `ConvertFrom-Json` даёт True). У нас файл переформатирован PowerShell и лежит с CRLF |
| `bootstrap.lua` | 0.4.5-RU | 0.4.5 | = 2.6.3 | CPDD + наш патч (3 ханка) |
| `Init.lua` | `2.9.0-RU`, 10 662 строки | `0.9.71`, 7 863 строки | = 2.6.3 | CPDD 0.9.71 + наши правки |
| `translation-overrides.state.json` | id `c7-ru-release-v2.6.3` | | | метаданные CPDD 2.6.3, id переписаны на RU |
| `RuntimeTextGemini_*` (1024) | RU | EN | EN | генерируются из наших батчей |

**Итог:** данные взяты из **CPDD v2.6.3**: в коммите `2c6336f` (v2.8.0-RU) обновлены `StringDB_CN_Data.lua` и `state.json`. Рантайм-код (loader 0.4.5, runtime 0.9.71) не менялся с первоначальной базы. Первый коммит `d051f78` (2026-09-08) содержал `state.json` с `displayVersion "2.6 bootstrapper, translation fixes and DPS Preview 7"` и `translationReleaseId c7-en-20260821-residual-repair2`, то есть данные, встроенные в установщик CPDD 2.6. `Init.lua` из `d051f78` отличается от CPDD 2.6.3 только нашими RU-правками (55 строк: BOM, `marionetteEnglishNames`, `shortMenuLabels`), а `VERSION = "0.9.71"` совпадает. Значит, **в `Init.lua` нет ни одного изменения CPDD, которое мы бы пропустили**.

## 2. v2.6.3 → v2.6.4 по компонентам

`release.json`: `changelog` = «Translates 386 new or changed localization records and 24 captured announcement strings. Corrects shifted Utopia Theater descriptions, including Giant's Physique and Afflicted I.». `runtime_text_entries` 130668 → 130692. `supported_base_paks`, `launch_block`, `combat_meter`, `loader_version`, `runtime_version`, `bootstrap_protocol` не изменились.

| Компонент | Что изменилось в 2.6.4 | Брать? | Конфликт с нашими правками |
|---|---|---|---|
| Мост (`.oodle`, `CPDDTranslation.lua`), `bootstrap.lua`, `manifest.lua` | ничего | — | — |
| `Init.lua` (runtime 0.9.71) | ничего | — | — |
| `cpdd_translation/…/StringDB_CN_Data.lua` | новый байткод (4 917 931 → 4 935 370 Б, sha `d7d0e2ba…`): 386 записей и исправленные описания Utopia Theater | **да, байт в байт** | нет: у нас этот файл = CPDD 2.6.3. RU поверх накладывает `Loader.TranslateDatabaseString` (`Init.lua:10595`) по CN-оригиналу (шаг 3), затем по EN (шаг 4) |
| `RuntimeTextGemini_*` (EN) | +24 новых ключа CN→EN в 24 шардах, изменённых нет. Анонсы Y1S1.2, внешность «荒野脉络 / Wilderness Veins», «野玫瑰 / Wild Rose», аукцион серверов, баланс «Fool's Gambit» | **да, как новые записи батча** | нет: ни один из 24 CN-ключей не найден в `source/translation_batches` |
| `LanguageSourceIndex_*` | ничего | — | — |
| BakedText (`blocks.bin`, `manifest.json`) | ничего, поддерживаемая база та же (BiliBili C7 1.2018737.2044036) | — | — |
| DPS-метр (DpsMeter 1.9.1, DpsTelemetry, External 1.1.0) | ничего | — | — |
| Chat UI (`DesktopChat.lua`) | ничего | — | — |
| Visual Clarity (`EngineIniBridge.lua` + блок Engine.ini) | ничего | — | — |
| График сервера (`ServerScheduleFix.lua`) | ничего | — | — |
| `translation-overrides.state.json` | id/версия 2.6.4, sha/size `StringDB_CN_Data.lua` | да, с переписанными RU-id | нет. Рантайм файл не читает (grep по `bootstrap.lua`/`Init.lua`/`installer/`), это метаданные установщика CPDD |

**Ограничение:** `cpdd_translation/*.lua` собраны в байткоде LuaJIT формата `1B 4C 4A 82` (собственная сборка игры, `launch_block.storage: "native LoM LuaJIT 0x82"`), и тело прототипов обфусцировано. Разбор констант стандартным форматом LuaJIT падает. Поэтому посмотреть, какие именно 386 записей изменились, нельзя. Компонент принимается от CPDD целиком. Если CN-текста новых записей нет в наших батчах, игра покажет исправленный английский CPDD. Найти такие строки можно только в игре (см. «Дальнейшее»).

## 3. `Init.lua` и `bootstrap.lua`: что от CPDD, что наше

`bootstrap.lua`: 3 ханка наших правок поверх CPDD 0.4.5:
1. `Loader.Version = "0.4.5-RU"`, `Language = "ru"`, `RussianLocalization = true` (`bootstrap.lua:6-8`). Эти строки правит `ToggleLanguage` в `installer/Program.cs:1483`.
2. `merge_overlay` сохраняет CN-оригиналы в `Loader.OverlayOriginals` и прогоняет каждое значение через `Loader.TranslateDatabaseString` (~`bootstrap.lua:392-425`).
3. Флаг `DiagnosticsMode` и чтение `cpdd_user_settings.lua` / `cpdd_patcher_settings.lua` (`bootstrap.lua:19-158`) — **это код CPDD**, а не наш.

`Init.lua` (diff с CPDD 2.6.3: 275 ханков, +3784/−985 строк, `temp/init_vs_cpdd263.diff`):
- **Замена EN-значений на RU внутри таблиц CPDD**: `aggregateOverrides`, `splitOverrides`, `stringConstOverrides`, `visibleTextExactOverrides`, `visibleTextReplacements`, `marionetteEnglishNames`, `shortMenuLabels`, строки в `setPanelWidgetText` и т.п. (~574 удалённые строки с EN-литералами, 1106 добавленных с кириллицей). **При обновлении CPDD здесь будет больше всего конфликтов.**
- **Тишина лога** (v2.9.0): 80 замен `report(` → `reportVerbose(` / `reportInstalled(`.
- **Изменения логики внутри функций CPDD**: `repairLiveString` (fuzzy lookup, `__LOM_OnTextIntercepted`, обработка без CJK), `translateVisibleText`, `translateTextWidget`, `lookupGeminiText` (LRU-кэш), `SOURCE_SHARD_CACHE_LIMIT 128→256`, раскладка SceneText, TaskBoard, `panelTextRepair:ProcessOnce`, `installShortMenuLabels`.
- **Чистые добавления** (28 ханков, 1597 строк): шрифты/letter-spacing для кириллицы, AutoChess, `exactWidgetRepairSpecs`, event-driven panel repair (+656 строк после `:7705` CPDD), `Loader.TranslateDatabaseString`, `ReapplyOverlays`, защита `ChatModel` (`Init.lua:10569-10644`).
- `VERSION` CPDD `0.9.71` заменён на `2.9.0-RU` (`Init.lua:3`). Через него проверяются уже установленные хуки (`installed.Version == VERSION`).

## 4. Как хранить наши правки поверх CPDD

Рекомендация в два этапа.

**Этап A (в этой задаче): эталон + 3-way merge.**
- Хранить в git нетронутую базу CPDD для текстовых файлов, которые мы патчим: `vendor/cpdd/<tag>/Init.lua`, `vendor/cpdd/<tag>/bootstrap.lua`, `vendor/cpdd/<tag>/translation-overrides.state.json` и `vendor/cpdd/BASE.json` (`{ "tag": "v2.6.3", "release_json_sha256": …, "files": {путь: sha256} }`). Объём ~0,6 МБ. Бинарники и шарды туда **не класть**: их всегда можно заново скачать по тегу в `reference/cpdd/<tag>/`.
- Обновление CPDD: `git merge-file -p <ours> <vendor base> <theirs>`. Если CPDD файл не менял (как в 2.6.4), результат совпадает с нашим. Если конфликт, файл не записывается, а `.rej` и отчёт пишутся в `reference/cpdd/<tag>/sync/`.
- Чисто CPDD-компоненты (§1, строки «чистый CPDD») копируются байт в байт. Их хеши сверяются с `release.json → external_bridge.files`.
- **Нужно решение пользователя:** новая папка верхнего уровня `vendor/` (в git). Альтернатива: хранить базу только в `reference/` (не в git), тогда 3-way merge в другом клоне требует скачать базовый тег.

**Этап B (отдельная задача, после A): вынести RU-значения из таблиц CPDD.**
Перенести RU-значения, которые сейчас подменяют EN-литералы в таблицах CPDD (`aggregateOverrides`, `splitOverrides`, `stringConstOverrides`, `visibleTextExactOverrides`, `shortMenuLabels`, `marionetteEnglishNames`), в отдельный модуль `cpdd_runtime_fixes/RuOverrides.lua`. Таблицы CPDD в `Init.lua` вернуть к оригиналу, а в начале `Init.lua` накладывать RU поверх (`for k,v in pairs(ru.aggregate) do aggregateOverrides[k]=v end`). После этого merge будет конфликтовать только на реальных изменениях логики. Ограничение: в `Init.lua` уже был упор в лимит 200 локальных переменных (коммит `40ad67e`), поэтому RU-таблицы подключать одной `local`.

## 5. Дизайн `tools/SyncCpdd.ps1`

```
tools/SyncCpdd.ps1 [-Tag v2.6.4|latest] [-Base <tag из vendor/cpdd/BASE.json>]
                   [-Components all|stringdb,shards,state,runtime,bakedtext,dps,chat,engineini,schedule,bridge]
                   [-Apply] [-SkipDownload]
```
1. **Download** (если нет `reference/cpdd/<tag>/`): `gh release download <tag> -p lom-english-patch-data.zip -p release.json -p release.json.sig -p SHA256SUMS.txt`. Сверить sha256 zip с `SHA256SUMS.txt` и `release.json.payload.sha256`, распаковать в `unpacked/`. Базовый тег скачать так же, если его нет. Без `-Apply` скрипт ничего не пишет за пределами `reference/`.
2. **Compare**: построить три карты `relpath → sha256` (base = `release.json` базового тега, theirs = новый `release.json`, ours = `patch_payload/`) и разложить каждый файл по правилам путей:
   - `verbatim`: `bridge/*.oodle`, `Binaries/**`, `manifest.lua`, `translation-overrides.lua`, `lua/cpdd_translation/**`, `LanguageSourceIndex_*`, `BakedText/*`, `ExternalDpsMeter/**`, `DpsMeter.lua`, `DpsTelemetry.lua`, `DesktopChat.lua`, `EngineIniBridge.lua`, `ServerScheduleFix.lua`, `WidgetNameIndex.lua`;
   - `merge3`: `bootstrap.lua`, `Init.lua`;
   - `state`: `translation-overrides.state.json`;
   - `shards`: `RuntimeTextGemini_*` (в `patch_payload` не копируются!);
   - `unknown`: новый файл, которого нет в правилах, → только отчёт, стоп.
   Для shards: распарсить `["cn"] = "en",` в base и theirs, получить списки added / changed-EN / removed и сверить с `source_cn` в `source/translation_batches/*.json`.
   Сравнить `supported_base_paks`, `launch_block`, `combat_meter`, `minimum_patcher_version`, `loader_version`, `runtime_version`.
3. **Report**: `reference/cpdd/<tag>/SYNC_REPORT.md` с таблицей «компонент / base→theirs / ours / действие / конфликт», как в §2 этого файла. Код выхода: 0 — без изменений, 1 — есть изменения, 2 — конфликты или `unknown`.
4. **Apply** (только с `-Apply` и только выбранные `-Components`):
   - `verbatim`: скопировать байт в байт и проверить sha по `release.json`;
   - `merge3`: `git merge-file`. Если конфликт, файл не менять, `.rej` положить в `reference/cpdd/<tag>/sync/`. После успешного merge `VERSION = "…-RU"` и `Loader.Version` остаются нашими;
   - `state`: взять JSON из theirs и переписать `translationReleaseId`/`installerReleaseId`/`signedDataReleaseId` на `c7-ru-*`, `displayVersion` на «<ver> Russian localization update (AbsoluteRU)». Записать UTF-8 без BOM, LF, двумя пробелами, как у CPDD;
   - `shards`: новые CN-ключи дописать в `source/translation_batches/batch_0NN_cpdd_<tag>.json` (`id` = max+1, `source_cn`, `ref_en`, `target_ru: ""`). Изменённые EN у существующих CN только перечислить в отчёте, `ref_en` не переписывать без ревью. Затем запустить `tools/ShardCompiler.exe` и `tools/VerifyBatch.ps1`;
   - по завершении обновить `vendor/cpdd/BASE.json` и эталонные текстовые файлы на новый тег;
   - поля `supported_base_paks` / `launch_block` переносить в наш шаблон release (см. §6).
5. Все записи: UTF-8 без BOM, LF. Путь репозитория брать из `$PSScriptRoot/..`. Скрипт не трогает папку игры и не запускает установщик.

## 6. «Поддерживаемое состояние игры»

**Как это делает CPDD** (`release.json` + строки в `Lord-of-Mysteries-English-Patch-2.6.1.exe`, `src\patcher.rs`):
- `supported_base_paks[]`: `{name, sha256, size}` **целого** чистого `Content/Paks/pakchunk0-Windows.pak` (`BiliBili C7 1.2018737.2044036`, `abbadeea…`, 446 910 011 Б).
- `external_bridge.launch_block`: `offset 427225161`, `size 4660`, `clean_sha256 566e72d6…` (блок до патча), `installed_sha256 c0317269…` (блок моста), `installed_pak_sha256 1712e55d…` / `installed_pak_size` (весь pak после патча).
- Установщик считает sha256 всего pak и выбирает состояние: `clean` (== supported), `installed` (== installed_pak_sha256) или «The selected game package is not compatible with this patch». Во время установки он ведёт журнал `.lomenglish.range-journal` / `.lomenglish.rollback` («The game package changed while the English patch was installing»). Бэкап блока лежит в `Saved/EnglishPatchBackups/startup-…-launch-original.bin`.
- `release.json` подписан (`release.json.sig`, ed25519/ring). Есть `minimum_patcher_version`, `release_blocker`, `install_ready`.
- BakedText защищён поблочно: `original_sha256` / `replacement_sha256` плюс `container_size`.
- Настройки: `Saved/Mods/lua/cpdd_patcher_settings.lua` = `return {\n    DpsMeterMode = "off|native|advanced|external",\n    DesktopChatUI = true|false,\n}`. Отказ от DPS записывает `Saved/Mods/lua/cpdd_user_settings.lua` = `return { StatisticsEverywhere = false }`. Visual Clarity пишет в `Saved/Config/Windows/Engine.ini` блок между `; BEGIN CPDD VISUAL CLARITY PATCH` и `; END CPDD VISUAL CLARITY PATCH` (`[/Script/Engine.RendererSettings]` GI/Reflection=0 и `[ConsoleVariables]` motion blur, lens flare, bloom, light shafts, refraction, AO, fog, volumetric fog/cloud = 0). Если Engine.ini не в UTF-8, файл не трогается.

**Как сейчас у нас (проблема):**
- `installer/Program.cs:1326-1347` (`InstallCore`) пишет блок моста **при любом** текущем хеше блока, если он не равен `PATCHED_PAK_SHA256`. `ORIGINAL_PAK_SHA256` (`:718`) объявлен, но не проверяется. `installer/PatcherEngine.cs:84-88` при «неизвестном хеше» прямо пишет «Возможно, игра обновлена» и всё равно записывает блок. После обновления игры смещение `427225161` почти наверняка укажет на другие данные, и установщик испортит `pakchunk0` (4660 байт).
- Бэкап создаётся только при первом запуске (`:1340`). Если pak уже пропатчен CPDD, нашего бэкапа нет, и `Uninstall` (`:1527-1544`) оставляет блок моста, но удаляет `CPDDTranslation.lua` и `Saved/Mods`. `Uninstall` также восстанавливает бэкап без проверки, что текущий блок равен `installed_sha256`, а бэкап — `clean_sha256`.
- `PatchBakedText` (`:1606-1639`) проверяет `original_sha256` поблочно (это хорошо), но не сверяет `container_size`.
- Наш `release.json` (`tools/PackageRelease.ps1:46-60`) содержит только версию, exe и payload.

**Предложение:**
1. В наш `release.json` добавить `supported_base_paks`, `launch_block` (те же поля, что у CPDD) и `game_build` (`1.2018737.2044036`), а также `minimum_installer_version`. Источник значений: `release.json` CPDD того тега, от которого сделан патч. `SyncCpdd -Components bridge` переносит их в `installer/supported_game.json` (п.6).
2. В установщике перед записью считать sha256 всего pak (~0,5–2 с на 426 МБ) и выбирать состояние:
   - `== supported.sha256 && size` → чистая база: сделать бэкап блока (sha должен быть = `clean_sha256`), записать блок, проверить, что весь pak = `installed_pak_sha256`;
   - `== installed_pak_sha256` → мост уже стоит (наш или CPDD): блок не трогать. Если бэкапа нет, это не страшно: восстанавливать можно, только если бэкап = `clean_sha256`;
   - иначе → **отказ** с сообщением «Версия игры не поддерживается этим русификатором (ожидается <game_build>). Дождитесь обновления патча». Ничего не записывать (ни блок, ни BakedText, ни Saved/Mods).
   - Если скачать release.json не удалось, использовать значения, зашитые в exe (сейчас константы `:716-719`).
3. `Uninstall`: восстанавливать блок, только если текущий блок = `installed_sha256` и бэкап = `clean_sha256`. Иначе не трогать pak и предложить «Проверить файлы» в лаунчере.
4. `PatchBakedText`: пропускать контейнер, если `FileInfo.Length != container_size`.
5. То же для `PatcherEngine.cs` и `Lord-of-Mysteries-Russian-Patch.ps1` (или объявить их устаревшими: **решение пользователя**).
6. Шаблон значений держать в `installer/supported_game.json` (генерирует `SyncCpdd`, читают `PackageRelease.ps1` и `build_installer.ps1` для констант).

Подтверждение, что база совпадает (только чтение, 2026-09-24): `D:\Games\GMZZLauncher\Game\C7\Content\Paks\pakchunk0-Windows.pak` — 446 910 011 Б, sha256 `1712e55d…c6bd1` = `installed_pak_sha256`, блок по смещению = `c0317269…` (мост). Файлов `cpdd_patcher_settings.lua` / `cpdd_user_settings.lua` нет, поэтому действуют значения по умолчанию из `bootstrap.lua:19-28` (Advanced DPS вкл., Chat UI выкл.).

## Попутные находки
- **CRLF в рабочей копии**: `git ls-files --eol` показывает `i/lf w/crlf` для `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua` и `patch_payload/Saved/Mods/BakedText/manifest.json`. `PackageRelease.ps1:32` пакует рабочую копию, поэтому в v2.9.0 эти файлы ушли с CRLF (урок «CRLF и hash mismatch» в `docs/LESSONS.md:25`).
- `BakedText/manifest.json` у нас переформатирован `ConvertTo-Json` (1,78 МБ против 1,27 МБ), хотя данные те же. Нужно вернуть байт-в-байт CPDD, тогда sha совпадёт с `release.json` CPDD.
- `reference/cpdd-english/eng_stable/INVENTORY.md` §4 содержит неверный список 38 таблиц (например, `itemquest`, `mail`, `npc` — таких файлов нет). Реальный список есть в `reference/cpdd/v2.6.4/release.json → external_bridge.files`. Путь `temp/eng_stable` там тоже устарел.

## План для чата исполнения
0. Гигиена: убедиться, что `git status` чист. Пересоздать с LF `Init.lua` и `BakedText/manifest.json` (`Remove-Item` + `git checkout -- <file>`) и проверить, что `git ls-files --eol -- patch_payload | Select-String w/crlf` пуст. Заменить `patch_payload/Saved/Mods/BakedText/manifest.json` на байт-в-байт CPDD (`reference/cpdd/v2.6.4/unpacked/payload/bridge/game/Saved/Mods/BakedText/manifest.json`, sha `509286d3…`) и отдельно закоммитить.
1. Решения пользователя (спросить в начале): (a) `vendor/cpdd/` в git — да/нет; (b) отказ установщика на неподдерживаемом pak — да (рекомендуется); (c) `PatcherEngine.cs` и `.ps1`-установщик — чинить или удалить; (d) опции DPS/Chat/Visual Clarity в нашем установщике — делать в этой задаче или вынести в TASK-004 (рекомендуется вынести).
2. Написать `tools/SyncCpdd.ps1` по §5. Для этапа A завести `vendor/cpdd/v2.6.3/` из `reference/cpdd-english/eng_stable/unpacked` (`Init.lua`, `bootstrap.lua`, `translation-overrides.state.json`, `BASE.json` из `reference/cpdd-english/eng_stable/release.json`). Прогнать `SyncCpdd.ps1 -Tag v2.6.4 -SkipDownload` без `-Apply` и сверить отчёт с §2: изменения только в `StringDB_CN_Data.lua`, `state.json` и 24 ключах шардов; merge3 для `Init.lua`/`bootstrap.lua` проходит без изменений.
3. `SyncCpdd.ps1 -Tag v2.6.4 -Components stringdb,state,shards -Apply`:
   - `StringDB_CN_Data.lua` ← CPDD 2.6.4 (sha `d7d0e2ba…`);
   - `state.json` ← 2.6.4 с RU-id (`c7-ru-release-v2.6.4`, sequence `2006001004`);
   - `source/translation_batches/batch_029_cpdd_264.json` с 24 записями. Перевести `target_ru` по `docs/TRANSLATION_GUIDE.md` и глоссарию, теги `<InvDefault>`/`<InvHighlight>`/`</>` и `【】` сохранить. «荒野脉络» и «野玫瑰» сверить с `source/glossary/terms_and_items.json`; если терминов там нет, добавить. Обновить `BATCH_MANIFEST.md`;
   - `ShardCompiler.exe` и `VerifyBatch.ps1`.
4. Установщик по §6 п.1–4 (+ п.5 по решению 1c): `supported_game.json`, проверка всего pak, отказ на неизвестном pak, безопасный `Uninstall`, проверка `container_size`. `PackageRelease.ps1` дописывает в `release.json` `supported_base_paks`/`launch_block`/`game_build`.
5. Обновить `docs/PROJECT_MAP.md` (`reference/cpdd/`, `vendor/cpdd/`, `SyncCpdd.ps1`) и `docs/LESSONS.md` (урок «блок в pak писать только на известную базу»).
6. `tools/VerifyPatch.ps1`, коммиты по шагам, `push origin main`. Релиз собирать только по просьбе пользователя.

## Проверка
- Автоматическая:
  - `SyncCpdd.ps1 -Tag v2.6.4 -SkipDownload` после шага 3 сообщает «без изменений» (код 0);
  - sha `patch_payload/.../StringDB_CN_Data.lua` = `d7d0e2ba2e23c5d0f73bcfe0b13509702059f422e3935e6ba77cfcbf6849c28e`, sha `BakedText/manifest.json` = `509286d3af469ecbbfe1107835ce771732f91677db8ea754ca239ee7ae67016a`;
  - `git ls-files --eol -- patch_payload` не содержит `w/crlf`;
  - `VerifyBatch.ps1` без ошибок, в шардах есть 24 новых CN-ключа с RU;
  - установщик на поддельной папке в `temp/fakegame/` (`Content/Paks/pakchunk0-Windows.pak` из случайных байт размером 446 910 011) отказывает, и sha pak до и после одинаковый. На папке, где pak = копия с `installed_pak_sha256`, установщик не пишет в pak. **В папку игры не писать.**
- Чек-лист для пользователя в игре (после установки новой сборки):
  - в новостях/объявлениях видны «Объявление об обновлении Y1S1.2» и анонс внешности «荒野脉络» на русском;
  - в Utopia Theater у описаний (Giant's Physique / Afflicted I) текст соответствует своему пункту и не сдвинут. Если пункты на английском, значит их CN нет в батчах, записать для TASK-004;
  - в `Saved\Logs\C7.log` есть строка `[LOMModLoader] … v2.9.x-RU active hooks_installed=` и нет `patcher settings failed` / `user settings failed`;
  - установщик на текущей игре говорит, что мост уже установлен (pak = `installed_pak_sha256`), и не пишет «неподдерживаемая версия».

## Дальнейшее (не в этой задаче)
- TASK-004: опции DPS (off/native/advanced/external), Chat UI, Visual Clarity в нашем установщике в формате CPDD (§6).
- Этап B из §4 (`RuOverrides.lua`).
- Поиск непереведённых записей StringDB в игре: при `DiagnosticsMode = true` писать в лог записи, для которых `Loader.TranslateDatabaseString` вернул `nil`.
- Подпись нашего `release.json` (по образцу `release.json.sig` у CPDD).

## Промпт для чата исполнения
> Выполни docs/tasks/TASK-003-cpdd-sync.md по разделу «План для чата исполнения». Сначала задай мне 4 вопроса из шага 1 (vendor/cpdd в git; отказ установщика на неподдерживаемом pak; судьба PatcherEngine.cs и .ps1-установщика; опции DPS/Chat/Visual Clarity сейчас или в TASK-004). Затем по шагам: гигиена CRLF и байт-в-байт BakedText/manifest.json; tools/SyncCpdd.ps1 по §5 с базой v2.6.3 и отчётом по v2.6.4 (данные уже лежат в reference/cpdd/v2.6.4 и reference/cpdd-english/eng_stable, ничего не скачивай без моего разрешения); применение stringdb/state/shards из v2.6.4 с переводом 24 новых строк в batch_029_cpdd_264.json, ShardCompiler и VerifyBatch; проверка «поддерживаемого состояния игры» в установщике по §6. В папку игры ничего не пиши и установщик не запускай; тесты установщика только на поддельной папке в temp/. Прогони проверки из раздела «Проверка», коммить по шагам и запушь в main. Релиз не собирай, пока я не попрошу; в конце дай мне чек-лист для проверки в игре.
