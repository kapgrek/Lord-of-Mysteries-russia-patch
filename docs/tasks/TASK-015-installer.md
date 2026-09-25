# TASK-015: новый установщик (WPF в стиле CPDD, опции DPS / чат / Visual Clarity, RU↔EN, `--payload`), починка `PackageRelease -Publish`

Статус: анализ 2026-09-25, ждёт исполнения. Этап 6 ROADMAP (раньше обозначался TASK-004, план не оформлялся). Релиз после этапа — v3.0 (решение пользователя 2026-09-25).

## Симптом / цель
- Установщик — окно Windows Forms 740×620 с тремя кнопками и логом (`installer/Program.cs:152-704`). Опций CPDD (DPS-метр, чат, Visual Clarity) нет, хотя моды лежат в пакете и читают настройки (§2).
- `ResolvePayloadDir` (`installer/Program.cs:901-1005`) сам ищет «локальный payload»: `patch_payload` рядом с exe и уровнем выше, жёстко прописанный `D:\gameDev\AbsoluteRU\patch_payload` (`:912`), любые `*patch*.zip`/`*lom*.zip` рядом с exe и в `Загрузках` пользователя (`:929-956`). У игрока в `Загрузках` может лежать старый архив (v2.6–v2.9.0), и установщик возьмёт его вместо актуального без проверки версии.
- Переключение RU↔EN, скорее всего, не даёт английского и может ломать запуск игры (§3). Вопрос пользователю из ROADMAP ещё без ответа.
- `tools/PackageRelease.ps1 -Publish` падает на новом теге (ROADMAP «Прочее», §6).

## 1. Текущее устройство

### `installer/Program.cs` (1743 строки; C# 5, csc .NET Framework 4)
| Что | Где | Заметки |
|---|---|---|
| Версия, репозиторий | `:26-27` | `VERSION = "2.9.10-RU"`, `DEFAULT_REPO = "kapgrek/Lord-of-Mysteries-russia-patch"` |
| `Main`: CLI при наличии аргументов, иначе `MainForm` | `:29-63` | `AttachConsole` для вывода в консоль |
| CLI | `:65-149` | `--smoke-ui` (печатает строку, окно не создаёт), `--verify-bundle`, `--diagnose`, `--install`, `--uninstall`, `--toggle`, `--download-payload`; аргумент без ключа = путь для установки |
| Окно WinForms | `:152-704` | абсолютные координаты, тёмная тема; кнопки «Установить / Обновить», «Переключить язык», «Исходный (Откат)»; `MessageBox` для итогов |
| `IsGameRunning` | `:733-745` | среди процессов `GMZZLauncher`: требует закрыть и лаунчер (CPDD разрешает лаунчер открытым, но проверяет внешний DPS-метр) |
| `FindGameFolder` | `:778-840` | 12 захардкоженных путей + ключи `Uninstall` в HKLM |
| `ResolvePayloadDir` | `:901-1005` | порядок: папки `patch_payload`/`data` → путь репозитория `:912` → zip рядом с exe и в `Загрузках` (`:924-982`, распаковка в `%TEMP%\lom_patch_payload_<размер>` `:962`, повторно берётся **по размеру** без проверки хеша `:963-964`) → скачивание → кеш `%LOCALAPPDATA%\LotmRussianPatch\payload` |
| Скачивание и проверка | `:1007-1153` | sha256 zip сверяется, только если удалось прочитать `release.json` (`:1050`, `:1090`); у публичного репозитория это фоллбек `:1533-1558` |
| `InstallWithAutoPayloadAsync` | `:1161-1225` | проверка папки/процессов/доступа → `ResolvePayloadDir(true)` → `SupportedGame` → `InstallerCore.Install` |
| `CoreForInstalledGame` | `:1258-1268` | берёт `supported_game.json` из `Saved/RussianPatchBackups`, иначе из пакета или встроенный |
| `ToggleLanguage`, `Uninstall` | `:1270-1299` | `Uninstall` тоже зовёт `ResolvePayloadDir(false)` (`:1287`), то есть на машине разработчика — папку репозитория |
| `TryGetGitHubToken` | `:1398-1431` | на ПК игрока запускает `gh auth token`; токен идёт в заголовок запросов к GitHub API |
| Клиент GitHub | `:1433-1740` | `HttpWebRequest`, ручные редиректы S3, прогресс и скорость |

### `installer/InstallerCore.cs` (798 строк; проверен `tools/InstallerCoreTests.exe`, 15 сценариев)
- `SupportedGame` (`:37-147`): поля CPDD `supported_base_paks` + `launch_block`; `Load` — файл рядом с payload, иначе ресурс `LotmRussianPatcher.supported_game.json` (`:96-108`).
- `InspectPak` (`:188-204`): sha256 всего `pakchunk0` → `CleanSupported` / `Installed` / `Unknown`.
- `InspectStatus` (`:218-240`): `InstalledDisabled`, если есть `CPDDTranslation.lua.disabled` или в `bootstrap.lua` строка `RussianLocalization = false`.
- `Install(payloadDir)` (`:244-323`): блок моста = `installed_sha256`; `owned_files.json` проверяется, **только если он есть** (`:563`); запись блока только на чистую базу, бэкап `Saved/RussianPatchBackups/launch-original.block`; копирование, удаление файлов прошлой версии по `installed_files.json`; копия `supported_game.json` в бэкап; BakedText; `VerifyInstallation`. Удаляет `CPDDTranslation.lua.disabled` (`:294`).
- `Uninstall` (`:411-459`): только свои файлы; блок восстанавливается при `current = installed_sha256` и бэкапе = `clean_sha256`.
- `ToggleLanguage` (`:496-527`): переименовывает `CPDDTranslation.lua` ↔ `.disabled` и меняет в `bootstrap.lua` `RussianLocalization`/`Language`.

**Вывод:** InstallerCore не зависит от UI и загрузки, его API (`InspectPak`, `InspectStatus`, `Install(payloadDir)`, `Uninstall(payloadDir)`) подходит новому окну без переписывания. Меняется только UI, выбор payload и новое: опции и язык — отдельными классами.

### Сборка: `installer/build_installer.ps1`
- csc `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (C# 5), ссылки `System.Windows.Forms`, `System.Drawing`, `System.IO.Compression(.FileSystem)`, `System.Web.Extensions` (`:20`), ресурс `supported_game.json` (`:33`), самоподписанная подпись и проверка Defender (`:45-67`).
- `tools/BuildTools.ps1:16-21` собирает `InstallerCoreTests.exe` из `tools/InstallerCoreTests.cs` + `installer/InstallerCore.cs`.

## 2. Что делают опции CPDD (установщик CPDD 2.6.1, Rust + egui)
Источник: строки `reference/cpdd-english/Lord-of-Mysteries-English-Patch-2.6.1.exe`, моды в `patch_payload/Saved/Mods/`, `reference/cpdd/v2.6.4/`.

**Окно CPDD:** заголовок «LORD OF MYSTERIES / ENGLISH COMMUNITY PATCH», логотип, плашка статуса (`READY TO INSTALL`, `PATCH INSTALLED`, `UPDATE AVAILABLE`, `STARTUP REPAIR NEEDED`, `NEWER DATA INSTALLED`, `ATTENTION NEEDED`, `NOT READY`), папка игры (`Auto-detect`, `Browse folders`), блок опций, кнопки `Install English` / `Update English` / `Reinstall English` / `Resume Installation` / `Repair Startup`, `Clean Files`, `Launch External Meter`, журнал `ACTIVITY`, ссылки GitHub и Discord. Переключения языка у CPDD нет.

| Опция CPDD | Подпись и подсказка (кратко) | Что пишет установщик | Кто читает |
|---|---|---|---|
| DPS: `Simple In-Game DPS Meter` | простая кнопка «Статистика» игры везде | `Saved/Mods/lua/cpdd_patcher_settings.lua`: `DpsMeterMode = "native"` | `bootstrap.lua:81-121` (`apply_feature_settings`) → `StatisticsEverywhere` (`Init.lua:11228-11270`) |
| DPS: `Advanced DPS Meter` (по умолчанию) | DpsMeter v1.9.1: перемещаемые, масштабируемые, переведённые панели | `DpsMeterMode = "advanced"` | `DpsMeter.lua` через `Features.AdvancedDpsMeter` |
| DPS: `External DPS Meter` | экспорт боя во внешний оверлей | `DpsMeterMode = "external"`; кнопка `Launch External Meter` запускает `Saved/Mods/ExternalDpsMeter/Lord of Mysteries Combat Meter.exe` (v1.1.0, есть в нашем пакете) | `DpsTelemetry.lua` через `Features.ExternalDpsMeter` |
| DPS: `Opt out of DPS meters` | выключает все счётчики | `DpsMeterMode = "off"` (+ CPDD пишет `Saved/Mods/lua/cpdd_user_settings.lua` = `return { StatisticsEverywhere = false }`) | `bootstrap.lua:109-121`; `off` сам ставит `StatisticsEverywhere = false`, поэтому `cpdd_user_settings.lua` нам **не нужен** (patcher-настройки применяются после user, `bootstrap.lua:128-153`) |
| `Enable new Chat UI` | перемещаемая панель чата для ПК, по умолчанию выключена | `DesktopChatUI = true/false` в том же файле | `DesktopChat.lua:77` (`Enabled = Features.DesktopChatUI == true`) |
| `Enable Visual Clarity Patch` | убирает туман, объёмный туман и облака, motion blur, lens flare, bloom, light shafts, refraction, Lumen GI/отражения, AO; прочие настройки Engine.ini сохраняются | блок в `Saved/Config/Windows/Engine.ini` между `; BEGIN CPDD VISUAL CLARITY PATCH` и `; END CPDD VISUAL CLARITY PATCH` (текст блока — §4.4); Engine.ini не в UTF-8 → отказ; битый блок (есть BEGIN без END) → отказ | `EngineIniBridge.lua` (`after_main`, приоритет 1600, `:140`): читает блок и выставляет только разрешённые CVar (`:6-29`) |

Формат файла настроек CPDD (строка в exe): `return {\n    DpsMeterMode = "<mode>",\n    DesktopChatUI = <true|false>,\n}\n`. Если файла нет, действуют умолчания `bootstrap.lua:19-28`: Advanced DPS вкл., чат выкл. На ПК пользователя сейчас (чтение 2026-09-25): нет ни `cpdd_patcher_settings.lua`, ни `cpdd_user_settings.lua`, ни `Saved/Config/Windows/Engine.ini` (есть только `GameUserSettings.ini`), значит Visual Clarity должен уметь **создать** Engine.ini.

## 3. Переключение RU↔EN: что происходит сейчас
- `InstallerCore.ToggleLanguage` (`:496-527`) переименовывает `Binaries/Win64/lua/Launch/Base/CPDDTranslation.lua` в `.disabled`. Блок моста в `pakchunk0` при этом **остаётся** (`InspectStatus` проверяет его, `:226`).
- Блок моста — это заменённый `LaunchInstance`, который загружает `Launch.Base.CPDDTranslation` (сам `CPDDTranslation.lua` делает `require("Launch.Base.LaunchStringExt")` и возвращает его, то есть подменяет модуль в цепочке запуска). Если файла нет, `require` модуля падает на старте. Как поведёт себя игра (ошибка Lua и продолжение, зависание или вылет), по нашим данным не проверить: блок сжат Oodle. CPDD такого состояния никогда не создаёт: у него «startup bridge reset or removed» считается поломкой, которую чинит `Repair Startup`.
- Даже если игра запустится, это будет **не английский**: без `CPDDTranslation.lua` не грузится `bootstrap.lua`, то есть нет ни одного мода CPDD. Будет китайский клиент с английскими картинками BakedText (они остаются в `.ucas`).
- Флаги `Language = "ru"` / `RussianLocalization = true` в `bootstrap.lua:6-8` **никто не читает** (grep по `patch_payload/Saved/Mods`: единственное вхождение — само объявление). Их меняет только установщик, и `InspectStatus` использует их как маркер.
- Тест `ToggleLanguage` (`tools/InstallerCoreTests.cs:323`) проверяет только переименование файлов.

**Как сделать настоящий английский.** Раскладка данных CPDD (`reference/cpdd/v2.6.4/unpacked/payload/bridge/game/{Binaries,Saved}` + `payload/bridge/LaunchInstance.native-bridge.padded.oodle`) совпадает с нашей один в один, у нас только лишний `AbsruDiagnostics.lua`. Блок моста тот же (`c0317269…`), `supported_base_paks` и `launch_block` тоже. Значит, EN = установить данные CPDD тем же `InstallerCore.Install`, а RU = наши. `pakchunk0` при переключении не трогается (состояние `Installed`), файлы прошлого языка убирает `installed_files.json`, настройки и история DPS остаются. `owned_files.json` для CPDD генерируется из их `release.json → external_bridge.files` (`relative_path`, `sha256`, `size`; 1341 запись), так что проверка целостности не слабее нашей.

Варианты (решает пользователь, шаг 0):
- **A (рекомендуется):** EN = данные последнего релиза CPDD с `github.com/Lani27/lord-of-mysteries-english-patch` (`release.json` + `lom-english-patch-data.zip`, sha256 zip = `release.json → payload.sha256`). Перед установкой проверить, что их `launch_block` и `supported_base_paks` совпадают с нашим `supported_game.json`; иначе EN недоступен с понятным сообщением. Кеш обоих языков в `%LOCALAPPDATA%\LotmRussianPatch\{ru,en}\`, повторное переключение без сети. Подпись `release.json.sig` (ed25519) в .NET Framework 4.8 без сторонних библиотек не проверить: опираемся на HTTPS и sha256 из `release.json`.
- **B:** переключения нет; кнопка «English» открывает страницу релизов CPDD, удаление RU и установку CPDD делает пользователь.
- **C (не рекомендуется):** оставить переименование. Требует подтверждения, что игра стартует, и всё равно даёт китайский.

При любом варианте старое состояние `CPDDTranslation.lua.disabled` установщик распознаёт как «нужно восстановить запуск» и чинит установкой RU (`Install` уже удаляет `.disabled`, `:294`).

## 4. Решения

### 4.1. Сборка WPF без .NET SDK — csc + XAML как ресурс
Проверено 2026-09-25 в scratchpad-папке сессии: `csc.exe` 4.8.9221 (C# 5) со ссылками
`Framework64\v4.0.30319\WPF\PresentationFramework.dll`, `WPF\PresentationCore.dll`, `WPF\WindowsBase.dll`, `v4.0.30319\System.Xaml.dll`
собирает exe, который грузит окно из встроенного `Main.xaml` (`/resource:Main.xaml,Main.xaml` → `XamlReader.Load(GetManifestResourceStream(...))`), находит элементы через `FindName`, кириллица в XAML (UTF-8 без BOM) читается: вывод `WPF_SMOKE_OK title=15 rb=True clr=4.0.30319.42000`.
- XAML без `x:Class` и без обработчиков событий в разметке (иначе нужна компиляция BAML): элементы с `x:Name`, события подключаются в C# после `FindName`. Стили, цвета, шаблоны кнопок — `ResourceDictionary` в том же XAML.
- Альтернатива — `MSBuild.exe` из .NET Framework 4 с `Microsoft.WinFX.targets` и `WPF\PresentationBuildTasks.dll` (обе есть): даёт компиляцию XAML в BAML и `x:Class`, но требует csproj и старого MSBuild (ToolsVersion 4.0) с его ограничениями. .NET 8 WPF требует SDK — его нет. Выбран csc: один exe, как сейчас, под .NET Framework 4.8 (есть в Windows 10/11), без новых зависимостей.
- Ограничения C# 5: нет `?.`, `$"..."`, `nameof`, expression-bodied членов (текущий код их уже не использует).
- Иконка окна: `/win32icon` для exe, в окне — `BitmapFrame.Create` из встроенного `app.ico`.

### 4.2. Файлы (новые/изменённые)
| Файл | Что |
|---|---|
| `installer/Program.cs` | `Main` + CLI + `PatcherBackend` + `GitHubReleaseClient`; класс `MainForm` удаляется. Запуск окна: `new Application().Run(MainWindow.Create())` в STA |
| `installer/Ui/MainWindow.xaml` | разметка окна (ресурс `LotmRussianPatcher.MainWindow.xaml`) |
| `installer/Ui/MainWindow.cs` | загрузка XAML, привязка элементов, состояния кнопок, асинхронные операции через `Task.Run` + `Dispatcher` |
| `installer/PayloadSource.cs` | выбор payload (§4.3), распаковка, адаптер раскладки CPDD, генерация `owned_files.json` из `release.json` CPDD |
| `installer/GameOptions.cs` | чтение/запись `cpdd_patcher_settings.lua` и блока Visual Clarity в Engine.ini (§4.4); без UI, покрывается тестами |
| `installer/InstallerCore.cs` | не переписывается. Допустимое добавление: `InstalledLanguage()` (`ru` — `Loader.Version` в `bootstrap.lua` оканчивается на `-RU`; `en` — версия без `-RU`; `none`). `ToggleLanguage` остаётся только ради старого CLI и тестов, окно его не вызывает |
| `installer/build_installer.ps1` | ссылки WPF (полные пути в `Framework64\v4.0.30319\WPF\`, `System.Xaml.dll`), убрать `System.Windows.Forms`/`System.Drawing` (если `FolderBrowserDialog` не нужен — см. ниже), ресурсы `MainWindow.xaml`, `app.ico`; новые исходники |
| `tools/BuildTools.ps1` | `InstallerCoreTests` += `installer/GameOptions.cs`, `installer/PayloadSource.cs`, ссылки WPF и ресурс `MainWindow.xaml` (проверка разметки) |
| `tools/InstallerCoreTests.cs` | новые сценарии (§5) |
| `tools/PackageRelease.ps1` | `-Publish` (§6), `Version` по умолчанию `v3.0.0-RU` |

Выбор папки: в WPF для .NET 4.8 нет диалога выбора папки. Варианты: оставить `System.Windows.Forms.FolderBrowserDialog` (ссылка на `System.Windows.Forms.dll`, работает из WPF) или `OpenFileDialog` на `C7-Win64-Shipping.exe` / `pakchunk0-Windows.pak`. Рекомендуется `FolderBrowserDialog`: привычно пользователю и проверено в текущем установщике.

### 4.3. Payload: только явный `--payload`, иначе GitHub
Порядок в `PayloadSource.Resolve`:
1. `--payload <папка|zip>` в командной строке (и в CLI, и при запуске окна: `Lord-of-Mysteries-Russian-Patch.exe --payload D:\gameDev\AbsoluteRU\patch_payload` открывает окно с этим пакетом; в заголовке окна и журнале — «Локальный пакет: …»). Папка проверяется `ValidatePayloadContents`; zip распаковывается во временную папку, **каждый раз заново** или с проверкой sha256 zip, а не по размеру.
2. `lom-russian-patch-data.zip` рядом с exe — **только** это точное имя (раздача «архив + установщик» из bundle `PackageRelease.ps1:112-126`). Если доступен `release.json` релиза, sha256 сверяется; если нет — используется с записью в журнал «проверка по release.json недоступна».
3. Скачивание последнего релиза (как сейчас, `:1007-1115`).
4. Кеш `%LOCALAPPDATA%\LotmRussianPatch\ru\` — только если zip в кеше совпадает по sha256 с сохранённым рядом `release.json`.

Удалить: кандидатов `patch_payload`/`data` рядом с exe и выше (`:906-911`), путь репозитория (`:912`), поиск шаблонов `*patch*.zip`… рядом с exe (`:929-939`) и в `Загрузках` (`:941-956`), повторное использование распаковки по размеру (`:962-964`). `Uninstall` не ищет payload вообще: ему хватает `installed_files.json`; payload нужен только для старых установок без списка (`InstallerCore.Uninstall:430-434`) — брать его из `--payload` или кеша.
Токен: убрать запуск `gh auth token` (`:1406-1428`); оставить `GITHUB_TOKEN`/`GH_TOKEN` из окружения (для приватного репозитория разработчика). `--verify-bundle` без `--payload` отвечает «укажите --payload».

### 4.4. Опции (`installer/GameOptions.cs`)
- **Состояние** читается из игры: `DpsMeterMode` и `DesktopChatUI` из `cpdd_patcher_settings.lua` (регэкспы `DpsMeterMode\s*=\s*"(off|native|advanced|external)"`, `DesktopChatUI\s*=\s*(true|false)`); нет файла → умолчания `advanced` / `false`. Visual Clarity включён, если в Engine.ini есть целый блок BEGIN…END.
- **Запись настроек** при установке RU/EN и кнопкой «Применить»: ровно формат CPDD (§2), UTF-8 без BOM, LF. Если файл есть, но не распознаётся (чужие ключи, синтаксис), не перезаписывать: ошибка «файл изменён вручную: …», остальное продолжается. `cpdd_user_settings.lua` не создавать и не трогать.
- **Visual Clarity:** блок
  ```
  ; BEGIN CPDD VISUAL CLARITY PATCH
  ; Managed by the Lord of Mysteries English Patcher. Disable the option to remove this block.
  [/Script/Engine.RendererSettings]
  r.DynamicGlobalIlluminationMethod=0
  r.ReflectionMethod=0

  [ConsoleVariables]
  r.MotionBlurQuality=0
  r.DefaultFeature.MotionBlur=0
  r.LensFlareQuality=0
  r.DefaultFeature.LensFlare=0
  r.BloomQuality=0
  r.DefaultFeature.Bloom=0
  r.LightShaftQuality=0
  r.RefractionQuality=0
  r.Refraction.OffsetQuality=0
  r.DistanceFieldAO=0
  r.AOQuality=0
  r.AmbientOcclusionLevels=0
  r.AmbientOcclusionMaxQuality=0
  r.Fog=0
  r.VolumetricFog=0
  r.VolumetricCloud=0
  ; END CPDD VISUAL CLARITY PATCH
  ```
  байт-в-байт как у CPDD (маркеры и комментарий на английском: блок общий с установщиком CPDD и с `EngineIniBridge.lua`). Включение: нет файла → создать `Saved/Config/Windows/Engine.ini` с блоком; есть → дописать блок в конец (если блок уже есть — заменить его целиком). Выключение: удалить блок и одну пустую строку перед ним; если файл после этого пуст и в `Saved/RussianPatchBackups/options.json` записано, что его создали мы, удалить файл. Отказ без изменений: BOM UTF-16 / не UTF-8; BEGIN без END или два BEGIN. Концы строк — как в существующем файле (CRLF, если в нём CRLF).
  Внимание: Engine.ini в `Saved/Config` игра может переписывать при выходе. Если блок пропадёт после сессии — это видно в чек-листе (п. 6); тогда нужно выяснить, как CPDD переживает это (вероятно, повторной записью при каждом «Применить»).
- **Удаление русификатора:** настройки `cpdd_*settings.lua` остаются (как сейчас и как у CPDD), блок Visual Clarity удаляется (он «managed by patcher»; без моста игра всё равно прочтёт Engine.ini сама). Переключение на EN опции не меняет: CPDD читает те же файлы.
- **Внешний DPS-метр:** кнопка «Запустить внешний счётчик» активна при `external` и наличии exe в игре; `Process.Start` с `UseShellExecute = true`, рабочая папка — папка exe. `IsGameRunning` дополнить процессом `Lord of Mysteries Combat Meter` (перед установкой его нужно закрыть, он лежит в `Saved/Mods`), а `GMZZLauncher` убрать из списка: CPDD разрешает открытый лаунчер (текст CPDD: «BiliBili and TapTap launchers can remain open»).

### 4.5. Макет окна (≈ 780×640, тёмная тема: фон `#14181E`, панели `#1C212A`, золото `#D4AF37`, текст `#DCE1EB`; Segoe UI)
```
┌──────────────────────────────────────────────────────────────────────┐
│ [app.ico]  LORD OF MYSTERIES                              v3.0.0-RU  │
│            РУССКАЯ ЛОКАЛИЗАЦИЯ · AbsoluteRU                          │
├──────────────────────────────────────────────────────────────────────┤
│ ● РУССКИЙ УСТАНОВЛЕН   Сборка игры 1.2018737.2044036 — поддерживается │
│ Папка игры  [D:\Games\GMZZLauncher\Game\C7          ] [Найти] [Обзор] │
├── Язык ──────────────────────────────────────────────────────────────┤
│ (•) Русский (AbsoluteRU v3.0.0)   ( ) English (CPDD v2.6.4)          │
├── Счётчик урона (DPS) ───────────────────────────────────────────────┤
│ ( ) Простой   (•) Расширенный   ( ) Внешний   ( ) Выключить все      │
│ Расширенный: перемещаемые панели DPS, v1.9.1.  [Запустить внешний ▸] │
├── Дополнительно ─────────────────────────────────────────────────────┤
│ [ ] Новый чат для ПК            (перемещаемая панель чата)           │
│ [ ] Visual Clarity  ⓘ           (без тумана, bloom, motion blur…)    │
├──────────────────────────────────────────────────────────────────────┤
│ [   Установить   ]   [ Применить настройки ]   [ Удалить русификатор ]│
│ ▓▓▓▓▓▓▓▓▓▓░░░░░░  62%  Загрузка 36,0 / 58,0 МБ (4,1 МБ/с)  [Отмена]  │
│ ЖУРНАЛ                                                               │
│ 12:01:05 Проверка версии игры (SHA-256 всего pakchunk0)…             │
│ 12:01:07   -> Мост уже установлен, блок не перезаписывается.         │
│ GitHub проекта · Английский патч CPDD            Локальный пакет: —  │
└──────────────────────────────────────────────────────────────────────┘
```
Статусы (плашка): `НЕ ВЫБРАНА ПАПКА`, `ГОТОВ К УСТАНОВКЕ` (чистая поддерживаемая сборка), `РУССКИЙ УСТАНОВЛЕН`, `ENGLISH (CPDD) УСТАНОВЛЕН`, `ДОСТУПНО ОБНОВЛЕНИЕ vX` (версия в `bootstrap`/`installed` старше релиза), `НУЖНО ВОССТАНОВИТЬ ЗАПУСК` (есть `CPDDTranslation.lua.disabled` или мост в pak есть, а файла нет), `ВЕРСИЯ ИГРЫ НЕ ПОДДЕРЖИВАЕТСЯ` (`PakState.Unknown`), `ИГРА ЗАПУЩЕНА`.
Главная кнопка меняет текст: «Установить» / «Обновить до vX» / «Переустановить» / «Восстановить запуск» / «Переключить на English» (выбран другой язык). «Применить настройки» активна, когда патч установлен и опции отличаются от записанных. Подсказки (`ToolTip`) к каждой опции — русские версии текстов CPDD из §2, у Visual Clarity — полный список CVar. Итог операции — в плашке и журнале, модальные окна только для подтверждения удаления и переключения языка.
Проверка версии игры (sha256 426 МБ, 0,5–2 с) выполняется в фоне после выбора папки, окно не блокируется.

## 5. Тесты (`tools/InstallerCoreTests.exe`, только `temp/installer-tests`)
Существующие 15 сценариев должны проходить без изменений. Новые:
1. `GameOptions`: нет `cpdd_patcher_settings.lua` → умолчания `advanced/false`; запись → файл байт-в-байт формата CPDD; чтение обратно; для каждого из 4 режимов.
2. `GameOptions`: файл с посторонним содержимым → отказ, файл не изменён.
3. Visual Clarity: нет Engine.ini → создан с блоком; выключение → файл удалён (создан нами); Engine.ini с `[Core.System]` → блок дописан, остальное байт-в-байт; повторное включение не дублирует блок; выключение возвращает исходные байты; CRLF сохраняется; UTF-16 BOM → отказ без изменений; BEGIN без END → отказ.
4. Удаление: `cpdd_*settings.lua` остаются, блок Visual Clarity удалён, чужие строки Engine.ini целы.
5. `PayloadSource`: папка без `bridge/` → отказ; zip с раскладкой CPDD (`payload/bridge/game/...`) адаптируется, `owned_files.json` собирается из `release.json` (фейкового, в `temp/`); подменённый файл → отказ `VerifyOwnedFiles`; `launch_block` CPDD ≠ наш → EN недоступен.
6. RU → EN → RU на фикстуре: `pakchunk0` не меняется (sha до/после), файлы RU-only (`AbsruDiagnostics.lua`) удаляются при EN и возвращаются при RU, настройки целы, `InstalledLanguage()` = `ru`/`en`/`ru`.
7. Старое состояние `CPDDTranslation.lua.disabled` → статус «нужно восстановить запуск»; установка RU возвращает `.lua`, `.disabled` удалён.
8. Разметка: `MainWindow.xaml` грузится `XamlReader.Load` в STA-потоке теста, все `x:Name` из `MainWindow.cs` находятся (список имён — константа в `MainWindow.cs`, тест берёт её же).
Установщик агент не запускает (AGENTS.md §1, `.claude/hooks/guard-game.ps1:22`): окно проверяется тестом разметки (п. 8) и пользователем.

## 6. `PackageRelease.ps1 -Publish` (`tools/PackageRelease.ps1:132-145`)
- **Причина:** `gh release view $Version -R $repo *> $null` (`:135`) при несуществующем релизе пишет в stderr; в Windows PowerShell 5.1 при `$ErrorActionPreference = 'Stop'` (`:9`) это `NativeCommandError`, и скрипт обрывается до `gh release create`. v2.9.6 публиковался вручную.
- **Исправление:** найти релиз по тегу через API, включая черновики (они не видны в `releases/tags/<tag>`):
  `gh api "repos/$repo/releases?per_page=100" --jq ".[] | select(.tag_name == \"$Version\") | .id"` внутри блока с локальным `$ErrorActionPreference = 'Continue'`; результат и `$LASTEXITCODE` проверять явно, без `*> $null`/`2>&1`.
  - не найден → `gh release create $Version --draft --target main --title $Version (--notes-file|--notes '')` **без** assets;
  - затем `gh release upload $Version --clobber @assets` (повторяемо: при обрыве следующий запуск находит черновик и докачивает, второго черновика не создаётся);
  - затем `gh release edit $Version --draft=false` (и `--latest`).
  - Если найдено больше одного релиза с тегом (остатки прошлых обрывов) — остановиться и вывести их id, ничего не удалять.
- Проверка без публикации: ключ `-WhatIfPublish` (печатает, какие команды `gh` выполнились бы, и результат поиска релиза по тегу) — запускать на несуществующем теге (например, `v0.0.0-test`) и на существующем `v2.9.6-RU`. Настоящая публикация — только по просьбе пользователя.

## 7. План для чата исполнения
0. Спросить пользователя (если ещё не ответил в чате анализа): (a) запускалась ли игра после «Переключить на English» старым установщиком и что было на экране; (b) вариант EN: A / B / C (§3, рекомендуется A); (c) номер версии `v3.0.0-RU`; (d) `FolderBrowserDialog` из WinForms — да (рекомендуется).
1. `tools/PackageRelease.ps1`: §6 + `-WhatIfPublish`; проверить на `v0.0.0-test` и `v2.9.6-RU`. Отдельный коммит.
2. `installer/GameOptions.cs` + тесты §5 п.1–4. `tools/BuildTools.ps1 -Only InstallerCoreTests`, прогнать.
3. `installer/PayloadSource.cs`: §4.3 (+ адаптер CPDD и `owned_files.json` из их `release.json`, если выбран A); из `Program.cs` удалить старый `ResolvePayloadDir` и `gh auth token`; CLI `--payload`. Тесты §5 п.5–7. Для проверки адаптера использовать `reference/cpdd/v2.6.4/` **копией в `temp/`** (reference только читать).
4. WPF: `installer/Ui/MainWindow.xaml`, `MainWindow.cs`, запуск окна в `Program.cs`, удаление `MainForm`; `build_installer.ps1` по §4.1–4.2. Тест §5 п.8. Собрать `installer/build_installer.ps1 -OutDir temp\installer-build` (не запускать).
5. `InstallerCore`: только `InstalledLanguage()` (если нужен) и распознавание `.disabled` в статусе; остальное не трогать. Все 15 старых сценариев + новые — зелёные.
6. `Program.VERSION`, `PackageRelease -Version` → `v3.0.0-RU`; `docs/PROJECT_MAP.md` (строки установщика, новые файлы), `README.md` (опции, `--payload`), `docs/LESSONS.md` (урок: «переключение языка переименованием `CPDDTranslation.lua` — не английский и риск запуска; язык = набор данных»), ROADMAP — строка этапа 6 и «Прочее» про `-Publish`.
7. `tools/VerifyPatch.ps1`, `PackageRelease.ps1 -DataOnly -BuildDir temp\data` + `InstallerCoreTests.exe --check-payload temp\data\…`. Коммиты по шагам, `push origin main`. Полный релиз и `-Publish` — только по просьбе пользователя.

## 8. Проверка
- Автоматическая: `tools/InstallerCoreTests.exe` — все сценарии (старые 15 + новые) `passed`, `failed 0`; `build_installer.ps1` без ошибок; `PackageRelease.ps1 -WhatIfPublish` на новом и существующем теге; `git diff --stat` не содержит `patch_payload/`.
- **Чек-лист для пользователя** (собранный `Lord-of-Mysteries-Russian-Patch.exe` v3.0.0-RU):
  1. Запуск без аргументов: окно WPF в тёмной теме, папка игры найдена, плашка `РУССКИЙ УСТАНОВЛЕН`, сборка игры «поддерживается». В журнале нет строки «Обнаружены исходные файлы патча: D:\gameDev\…» (раньше подхватывался репозиторий).
  2. Запуск `Lord-of-Mysteries-Russian-Patch.exe --payload D:\gameDev\AbsoluteRU\patch_payload`: внизу «Локальный пакет: …», «Переустановить» ставит из репозитория.
  3. DPS «Внешний» → «Применить настройки»: `Saved\Mods\lua\cpdd_patcher_settings.lua` содержит `DpsMeterMode = "external"`; кнопка «Запустить внешний» открывает Combat Meter; в игре оверлей получает данные. Вернуть «Расширенный» — в игре панели DPS v1.9.1.
  4. «Новый чат для ПК» → в игре перемещаемая панель чата (строка `DesktopChat` в `C7.log` может не появиться: после `performance-mode` уровень лога Warning, см. LESSONS).
  5. Visual Clarity → в `Saved\Config\Windows\Engine.ini` блок `; BEGIN CPDD VISUAL CLARITY PATCH`; в игре нет тумана и bloom; в `C7.log` — `[CPDDVisualClarity] submitted 18 managed Engine.ini CVars (failed=0)`. **Выйти из игры и проверить, что блок в Engine.ini остался.** Выключить опцию — блок исчез.
  6. (Вариант A) «English (CPDD)» → «Переключить на English»: скачан архив CPDD, плашка `ENGLISH (CPDD) УСТАНОВЛЕН`; игра запускается на английском; в `C7.log` строка `[LOMModLoader] … v0.9.71 active hooks_installed=` (без `-RU`). Обратно на «Русский» — русский, настройки DPS/чата сохранились. Проверить, что sha256 `pakchunk0` не изменился (установщик пишет «Мост уже установлен, блок не перезаписывается»).
  7. «Удалить русификатор»: игра чистая, `cpdd_patcher_settings.lua` остался, блока Visual Clarity нет.
  8. Установка с открытым лаунчером BiliBili проходит; с запущенной игрой или Combat Meter — отказ с понятным текстом.

## Промпт для чата исполнения
> Выполни docs/tasks/TASK-015-installer.md по разделу «План для чата исполнения». Сначала задай мне вопросы шага 0 (как вела себя игра после старого «Переключить на English»; вариант EN — A/B/C, рекомендуется A; версия v3.0.0-RU; FolderBrowserDialog), пропусти те, на которые я уже ответил в чате анализа. Затем по шагам: починка PackageRelease.ps1 -Publish с -WhatIfPublish (без настоящей публикации); installer/GameOptions.cs (cpdd_patcher_settings.lua в формате CPDD, блок Visual Clarity в Engine.ini байт-в-байт как у CPDD); installer/PayloadSource.cs (локальный payload только по --payload, zip рядом с exe только по точному имени, без Загрузок и пути репозитория, без gh auth token; адаптер данных CPDD для English); WPF-окно по макету §4.5 через csc + XAML как ресурс (§4.1), без переписывания InstallerCore. Все новые сценарии — в tools/InstallerCoreTests.cs, только в temp/installer-tests. В папку игры ничего не пиши, установщик, игру и лаунчер не запускай, reference/ только читай. Коммить по шагам и запушь в main; релиз собирай и публикуй только по моей просьбе. В конце дай мне чек-лист из §8.
