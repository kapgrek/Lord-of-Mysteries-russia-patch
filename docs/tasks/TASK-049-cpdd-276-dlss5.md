# TASK-049: CPDD v2.7.6 — 92 новые строки и опция DLSS5 (совместимо со старым установщиком)

## Что вышло
CPDD `v2.7.6` (2026-11-13). Отчёт: `tools/SyncCpdd.ps1 -Tag v2.7.6` (без `-Apply`) → `reference/cpdd/v2.7.6/SYNC_REPORT.md`, распаковка в `reference/cpdd/v2.7.6/unpacked/payload/`.

Разница с v2.7.5 (`git diff --no-index reference/cpdd/v2.7.5/unpacked/payload/… reference/cpdd/v2.7.6/unpacked/payload/…`):

| Что | Изменение | Нам |
|---|---|---|
| Мост (`bridge/`, `cache-startup.oodle`) | файлы те же. «Fixes loading after the game moves startup code into its base archive» = `cache_launch.block` с offset 422563913, clean `3124ee28…` → `ee48b48a…` | Уже сделано в TASK-046 (`installer/supported_game.json`), **ничего не делать** |
| `cpdd_runtime_fixes/Init.lua` | 2.7.5 = 2.7.6 побайтно | Не трогать. 14 конфликтов merge3 в отчёте — старые: наш `Init.lua` форк от v2.6.4 (`vendor/cpdd/BASE.json`, урок TASK-042) |
| `BakedText/*` | «removed» с 2.7.0 | Не удалять (нет `-AllowRemoval`) |
| Шарды | +2448 CN→EN, из них **92 нет в наших батчах** (51 служебная метка: «测试属性buff…», «【PVP测试】…», «罗塞尔Boss终局-…»; остальное — имена NPC, «【自走棋装备】…», «【木桩训练场】», `[置顶]`, `[卡了]`, `<ChatTag_GVG>[斗邪恶]</>`, `剩余时间 <Highlight>%s</>`) | Новый батч, перевод в отдельном чате |
| `state` (`translation-overrides.state.json`) | изменён | regenerate |
| **DLSS5** | новый `cpdd_runtime_fixes/Dlss5.lua` (+`.compat.luac`), `manifest.lua` +1 модуль, `bootstrap.lua` +6 строк (флаг `Features.Dlss5Unlock = false`, ветка в `apply_feature_settings`, `enabled` в цикле загрузки) | Переносим, по умолчанию выкл. |

`Dlss5.lua` (68 строк) только в памяти: оборачивает `manager.refreshDLSSNR` / `__Cmd_DLSS_NR`, на время refresh подменяет `bDLSSNRSupported = true`; активен, только если `Loader.Features.Dlss5Unlock == true` и `manager.bPCMode`. Файлов не пишет, Engine.ini не трогает. Лог-префикс `[LOMDlss5]`.

## Требование совместимости (от пользователя)
Обновление должно ставиться **и старым установщиком (3.1.6–3.1.8-RU), и новым** (с галочкой DLSS5).

Как это работает сейчас (проверено по коду):
- Старый установщик при запуске видит более новый релиз и **сам обновляется** (`installer/SelfUpdate.cs:40` `IsNewer`). Если самообновление выключено или не удалось, он ставит данные последнего релиза (`PayloadSource`).
- Данные отклоняются только при `min_installer_version` выше версии exe (`installer/supported_game.json:3` = `3.1.6-RU`, `PatcherBackend.cs:341`). **Не поднимать** — тогда 3.1.6–3.1.8 поставят новый пакет.
- Список «своих» файлов строится из пакета (`InstallerCore.GetPayloadFiles`, `InstallerCore.cs:852, 1163` → `installed_files.json`). `Dlss5.lua` попадёт в него автоматически, старый установщик его и поставит, и удалит.
- Без ключа в настройках `Dlss5Unlock = false` (умолчание `bootstrap.lua`) → модуль не грузится. Старый установщик даёт рабочий патч без DLSS5.
- **Ловушка:** старый `GameOptions.ParseSettings` (`installer/GameOptions.cs:155-175`) отвергает файл с любым посторонним ключом. Установка при этом проходит, только пишется «часть настроек не записана» (`PatcherBackend.cs:355-358`), а «Применить настройки» отказывает. Поэтому новый установщик пишет `Dlss5Unlock` **только когда он включён**: при выключенном DLSS файл побайтно прежний (`FormatSettings` для `false` не меняется), и старый установщик его понимает. При включённом DLSS старый установщик оставит файл как есть, DLSS сохранится.

## План (чат исполнения)
1. **Правило синхронизации** `tools/SyncCpdd.ps1`: в классификатор (`:104-119`, рядом с `'DesktopChat.lua' { return 'chat' }`) добавить `'Dlss5.lua' { return 'dlss5' }`; компаньон `.lua.compat.luac` классифицируется так же, как у `DesktopChat` (проверить, как это сделано для `chat`). `'dlss5'` добавить в `$verbatimComponents` (`:30`). Повторный отчёт `SyncCpdd -Tag v2.7.6 -SkipDownload` → в таблице нет `unknown`.
2. **Применить:** `tools/SyncCpdd.ps1 -Tag v2.7.6 -SkipDownload -Components dlss5,loader,state,shards -Apply` (код 2 ожидаем из-за конфликта Init). Проверить:
   - появились `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/Dlss5.lua` и `.compat.luac` (sha как в отчёте);
   - `git diff patch_payload/Saved/Mods/manifest.lua` = только `+ "mods.cpdd_runtime_fixes.Dlss5",`; `manifest.lua.compat.luac` обновлён;
   - `Init.lua` и `BakedText/` **не изменились** (`git status`);
   - создан `source/translation_batches/batch_052_cpdd_276.json` (92 записи, `target_ru` пустой), строка в `BATCH_MANIFEST.md`;
   - `vendor/cpdd/BASE.json` → `tag` v2.7.6, `component_bases` для Init/bakedtext прежние (v2.6.4).
3. **`bootstrap.lua` вручную** (компонент `runtime` не применять: он тянет Init). В `patch_payload/Saved/Mods/bootstrap.lua` перенести ровно 3 куска из upstream-диффа 2.7.5→2.7.6: `Dlss5Unlock = false,` в `Loader.Features` (после `DesktopChatUI = false,`, ~`:28`); ветку `if type(settings.Dlss5Unlock) == "boolean"` в `apply_feature_settings` (после `DesktopChatUI`, ~`:137-139`); `elseif name == "mods.cpdd_runtime_fixes.Dlss5" then enabled = Loader.Features.Dlss5Unlock == true` (после ветки DesktopChat, ~`:601-602`). Наш `bootstrap.lua.compat.luac` не совпадает с исходником, загрузчик откатится на исходник (так и было, TASK-032) — не трогать.
4. **Установщик:**
   - `GameOptions.cs`: `GameOptionsState.Dlss5` (bool, умолчание false); regex `^Dlss5Unlock\s*=\s*(true|false)$` в `ParseSettings` (любой порядок ключей, без повторов); `FormatSettings(mode, chat, dlss5)` дописывает `    Dlss5Unlock = true,\n` **только при true**; `Read`/`Apply`/`WriteSettings`/лог учитывают флаг.
   - `Ui/MainWindow.xaml` + `.cs`: галочка «DLSS 5 (экспериментально, NVIDIA)» рядом с «Чистая картинка», подсказка: «Открывает пункт DLSS 5 в настройках графики. Нужна поддержка видеокарты и драйвера; на старых картах не проверено. Включение: DLSS → Нейронный рендеринг». `CurrentOptions()` / заполнение из состояния (~`:531-546`).
   - CLI (`Program.cs` / `GameOptions.cs:279`), если там есть ключи для чата, — такой же `--dlss5 on|off`.
   - `AppInfo.Version` → `3.1.9-RU`; `min_installer_version` **оставить** `3.1.6-RU`.
   - `README.md:72` — строка про DLSS5.
5. **Тесты** `tools/InstallerCoreTests` (на поддельных папках в `temp/`): парс файла старого формата → dlss5=false; `FormatSettings(…, false)` == старой строке побайтно; true → ключ есть и читается обратно; файл CPDD с `Dlss5Unlock` в другом порядке читается; посторонний ключ по-прежнему отвергается; установка пакета с `Dlss5.lua` кладёт его в `installed_files.json`, удаление убирает. `tools/BuildTools.ps1`, тесты зелёные.
6. **Перевод 92 строк — отдельный чат** (промпт ниже). Чат исполнения его не делает.
7. `docs/LESSONS.md`: «Новую опцию в `cpdd_patcher_settings.lua` писать только в состоянии ≠ умолчанию: старые установщики отвергают незнакомые ключи (`GameOptions.ParseSettings`)». `docs/PROJECT_MAP.md` — `Dlss5.lua` в таблице доп. модов.
8. Коммиты по шагам, push. Релиз `v3.1.9-RU` (`PackageRelease.ps1 -Publish`) — **после** перевода пачки (шаг 6) и только по просьбе пользователя.

## Проверка в игре (делает пользователь)
- **Старый установщик 3.1.8** с `--no-self-update` (или без интернета, с `lom-russian-patch-data.zip` рядом): установка проходит, `C7.log` — `[CPDDRuntimeFix] v3.1.9-RU active`, строки `[LOMDlss5]` **нет**, перевод на месте.
- **Новый 3.1.9**, DLSS5 выкл.: `Saved/Mods/lua/cpdd_patcher_settings.lua` без `Dlss5Unlock`; запустить 3.1.8 → без предупреждения «изменён вручную».
- **Новый 3.1.9**, DLSS5 вкл.: в файле `Dlss5Unlock = true`; в игре Настройки → Графика: выбрать DLSS, пункт «Нейронный рендеринг» доступен; в `C7.log` строки `[LOMDlss5]`. Повторный запуск установщика показывает галочку включённой.
- Новые строки (после пачки): `[置顶]`/`[卡了]` в чате, справка «Тренировочное поле с манекенами» (`【木桩训练场】`), бирка `[斗邪恶]` в чате.

## Порядок пачек
1. Пачка 1 — `batch_052_cpdd_276.json`, 92 строки (`ref_en` от CPDD уже заполнен). Служебные метки («测试…», «【PVP测试】…», «…Boss终局-…») переводить коротко и буквально.

## Промпт для чата перевода
```
/translate-pack
Пачка: 1 из docs/tasks/TASK-049-cpdd-276-dlss5.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_052_cpdd_276.json (уже есть после SyncCpdd -Apply, продолжить).
Строки: все с пустым target_ru (92), логи не нужны — StringDbGaps -Report пропустить.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```
