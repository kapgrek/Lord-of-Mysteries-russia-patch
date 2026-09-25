# TASK-015: новый установщик (WPF в стиле CPDD, опции DPS / чат / Visual Clarity, `--payload`), починка `PackageRelease -Publish`

Статус: **исполнено 2026-09-25 (v3.0.0-RU в репозитории, не опубликован), ждёт проверки пользователем** — итоги в разделе «Исполнение» в конце. Этап 6 ROADMAP (раньше обозначался TASK-004, план не оформлялся).

**Решения пользователя (2026-09-25):**
1. Игра после «Переключить на English» старым установщиком **не запустилась** (подтверждает §3). Переключение языка **убрать полностью** (возможно, вернём позже отдельной задачей). Вместо него — ссылка на Discord CPDD с пометкой, что русификатор сделан на основе их английского патча.
2. Версия нового установщика и патча — **`3.0.0`** (тег `v3.0.0-RU`). Дальше обновления только `3.0.1`, `3.0.2`, …; `3.1.0` — после хорошей редакции перевода.
3. DPS-метр берём у английского патча (CPDD): все его режимы и внешний счётчик должны быть в нашем установщике (§2, §4.4).
4. Выбор папки игры — в стиле всего установщика, аккуратный (образец — блок `GAME LOCATION` CPDD, §4.5).
5. Своя иконка и эмблема (как у CPDD) — в будущем; сейчас в окне место под логотип с текущим `app.ico`.
6. Ссылки на наши соцсети: Telegram-канал перевода, личный Telegram автора, «Поддержать на Boosty» (§4.7). Адреса даёт пользователь.
7. Вкладка «Как играть»: по нажатию открывается окно с инструкцией — как скачать игру, зарегистрироваться и т. д. (§4.8). Текст даёт пользователь.

## Симптом / цель
- Установщик — окно Windows Forms 740×620 с тремя кнопками и логом (`installer/Program.cs:152-704`). Опций CPDD (DPS-метр, чат, Visual Clarity) нет, хотя моды лежат в пакете и читают настройки (§2).
- `ResolvePayloadDir` (`installer/Program.cs:901-1005`) сам ищет «локальный payload»: `patch_payload` рядом с exe и уровнем выше, жёстко прописанный `D:\gameDev\AbsoluteRU\patch_payload` (`:912`), любые `*patch*.zip`/`*lom*.zip` рядом с exe и в `Загрузках` пользователя (`:929-956`). У игрока в `Загрузках` может лежать старый архив (v2.6–v2.9.0), и установщик возьмёт его вместо актуального без проверки версии.
- Переключение RU↔EN ломает запуск игры (§3, подтверждено пользователем).
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
- `Install(payloadDir)` (`:244-323`): блок моста = `installed_sha256`; `owned_files.json` проверяется, **только если он есть** (`:563`); запись блока только на чистую базу, бэкап `Saved/RussianPatchBackups/launch-original.block`; копирование, удаление файлов прошлой версии по `installed_files.json`; копия `supported_game.json` в бэкап; BakedText; `VerifyInstallation`. Удаляет `CPDDTranslation.lua.disabled` (`:294`) — то есть уже чинит состояние после старого переключения.
- `Uninstall` (`:411-459`): только свои файлы; блок восстанавливается при `current = installed_sha256` и бэкапе = `clean_sha256`.
- `ToggleLanguage` (`:496-527`): переименовывает `CPDDTranslation.lua` ↔ `.disabled` и меняет в `bootstrap.lua` `RussianLocalization`/`Language`.

**Вывод:** InstallerCore не зависит от UI и загрузки, его API (`InspectPak`, `InspectStatus`, `Install(payloadDir)`, `Uninstall(payloadDir)`) подходит новому окну без переписывания. Меняется UI и выбор payload; опции — отдельным классом; из ядра удаляется только `ToggleLanguage` (решение 1).

### Сборка: `installer/build_installer.ps1`
- csc `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (C# 5), ссылки `System.Windows.Forms`, `System.Drawing`, `System.IO.Compression(.FileSystem)`, `System.Web.Extensions` (`:20`), ресурс `supported_game.json` (`:33`), самоподписанная подпись и проверка Defender (`:45-67`).
- `tools/BuildTools.ps1:16-21` собирает `InstallerCoreTests.exe` из `tools/InstallerCoreTests.cs` + `installer/InstallerCore.cs`.

## 2. Что делают опции CPDD (установщик CPDD 2.6.1, Rust + egui)
Источник: строки `reference/cpdd-english/Lord-of-Mysteries-English-Patch-2.6.1.exe`, моды в `patch_payload/Saved/Mods/`, `reference/cpdd/v2.6.4/`.

**Окно CPDD:** заголовок «LORD OF MYSTERIES / ENGLISH COMMUNITY PATCH», логотип, плашка статуса (`READY TO INSTALL`, `PATCH INSTALLED`, `UPDATE AVAILABLE`, `STARTUP REPAIR NEEDED`, `NEWER DATA INSTALLED`, `ATTENTION NEEDED`, `NOT READY`), блок `GAME LOCATION` (подпись слева, подсказка справа «Folder ending in Game\C7», поле пути на всю ширину, под ним две равные кнопки `Auto-detect` и `Browse folders…`; скриншот пользователя 2026-09-25), блок опций, кнопки `Install English` / `Update English` / `Reinstall English` / `Resume Installation` / `Repair Startup`, `Clean Files`, `Launch External Meter`, журнал `ACTIVITY`, ссылки GitHub и Discord (`https://discord.gg/yyds` — строка из exe, перед релизом открыть и проверить). Переключения языка у CPDD нет.

**DPS-метр CPDD (решение 3) у нас уже есть байт в байт** (TASK-003 §1, сверка с CPDD 2.6.4): `DpsMeter.lua` v1.9.1, `DpsTelemetry.lua`, `Saved/Mods/ExternalDpsMeter/Lord of Mysteries Combat Meter.exe` v1.1.0 (sha `ca0fbd87…` = `release.json → external_bridge.combat_meter`). Последний релиз CPDD на 2026-09-25 — v2.6.4 (`gh release list`), новее нет. Обновляет их `tools/SyncCpdd.ps1 -Components dps`. Не хватает только того, что даёт установщик CPDD: выбора режима и кнопки запуска внешнего счётчика.

| Опция CPDD | Подпись и подсказка (кратко) | Что пишет установщик | Кто читает |
|---|---|---|---|
| DPS: `Simple In-Game DPS Meter` | простая кнопка «Статистика» игры везде | `Saved/Mods/lua/cpdd_patcher_settings.lua`: `DpsMeterMode = "native"` | `bootstrap.lua:81-121` (`apply_feature_settings`) → `StatisticsEverywhere` (`Init.lua:11228-11270`) |
| DPS: `Advanced DPS Meter` (по умолчанию) | DpsMeter v1.9.1: перемещаемые, масштабируемые, переведённые панели | `DpsMeterMode = "advanced"` | `DpsMeter.lua` через `Features.AdvancedDpsMeter` |
| DPS: `External DPS Meter` | экспорт боя во внешний оверлей | `DpsMeterMode = "external"`; кнопка `Launch External Meter` запускает `Saved/Mods/ExternalDpsMeter/Lord of Mysteries Combat Meter.exe` | `DpsTelemetry.lua` через `Features.ExternalDpsMeter` |
| DPS: `Opt out of DPS meters` | выключает все счётчики | `DpsMeterMode = "off"` (+ CPDD пишет `Saved/Mods/lua/cpdd_user_settings.lua` = `return { StatisticsEverywhere = false }`) | `bootstrap.lua:109-121`; `off` сам ставит `StatisticsEverywhere = false`, поэтому `cpdd_user_settings.lua` нам **не нужен** (patcher-настройки применяются после user, `bootstrap.lua:128-153`) |
| `Enable new Chat UI` | перемещаемая панель чата для ПК, по умолчанию выключена | `DesktopChatUI = true/false` в том же файле | `DesktopChat.lua:77` (`Enabled = Features.DesktopChatUI == true`) |
| `Enable Visual Clarity Patch` | убирает туман, объёмный туман и облака, motion blur, lens flare, bloom, light shafts, refraction, Lumen GI/отражения, AO; прочие настройки Engine.ini сохраняются | блок в `Saved/Config/Windows/Engine.ini` между `; BEGIN CPDD VISUAL CLARITY PATCH` и `; END CPDD VISUAL CLARITY PATCH` (текст блока — §4.4); Engine.ini не в UTF-8 → отказ; битый блок (есть BEGIN без END) → отказ | `EngineIniBridge.lua` (`after_main`, приоритет 1600, `:140`): читает блок и выставляет только разрешённые CVar (`:6-29`) |

Формат файла настроек CPDD (строка в exe): `return {\n    DpsMeterMode = "<mode>",\n    DesktopChatUI = <true|false>,\n}\n`. Если файла нет, действуют умолчания `bootstrap.lua:19-28`: Advanced DPS вкл., чат выкл. На ПК пользователя сейчас (чтение 2026-09-25): нет ни `cpdd_patcher_settings.lua`, ни `cpdd_user_settings.lua`, ни `Saved/Config/Windows/Engine.ini` (есть только `GameUserSettings.ini`), значит Visual Clarity должен уметь **создать** Engine.ini.

## 3. Переключение RU↔EN: почему убираем
- `InstallerCore.ToggleLanguage` (`:496-527`) переименовывает `Binaries/Win64/lua/Launch/Base/CPDDTranslation.lua` в `.disabled`. Блок моста в `pakchunk0` при этом **остаётся** (`InspectStatus` проверяет его, `:226`).
- Блок моста — заменённый `LaunchInstance`, который загружает `Launch.Base.CPDDTranslation` (сам `CPDDTranslation.lua` делает `require("Launch.Base.LaunchStringExt")` и возвращает его, то есть встроен в цепочку запуска). Без файла `require` падает на старте. **Пользователь подтвердил: игра не запустилась.** CPDD такого состояния не создаёт: у него «startup bridge reset or removed» — поломка, которую чинит `Repair Startup`.
- Даже при удачном старте это был бы не английский: без `CPDDTranslation.lua` не грузится `bootstrap.lua` и ни один мод CPDD, остаётся китайский клиент с английскими картинками BakedText.
- Флаги `Language = "ru"` / `RussianLocalization = true` в `bootstrap.lua:6-8` **никто не читает** (grep по `patch_payload/Saved/Mods`: единственное вхождение — объявление). Их можно оставить: `InspectStatus` использует `RussianLocalization = false` как маркер старого «выключенного» состояния.
- **Решение:** убрать кнопку, CLI `--toggle`, `PatcherBackend.ToggleLanguage` (`Program.cs:1270-1282`), `InstallerCore.ToggleLanguage` + `ReplaceInFile` (`:496-537`) и тест `ToggleLanguage` (`tools/InstallerCoreTests.cs:63`, `:323-345`). Статус `InstalledDisabled` остаётся и в окне показывается как «НУЖНО ВОССТАНОВИТЬ ЗАПУСК»: у кого после старого установщика остался `.disabled`, тот чинит игру кнопкой «Восстановить запуск» = обычная установка RU (`Install` удаляет `.disabled` и копирует `CPDDTranslation.lua`, `:293-294`; `bootstrap.lua` перезаписывается из пакета).
- На будущее (не в этой задаче): настоящий English возможен установкой данных CPDD тем же `InstallerCore.Install` — их раскладка (`payload/bridge/game/{Binaries,Saved}` + тот же блок моста `c0317269…`) совпадает с нашей. Записано в «Дальнейшее».

## 4. Решения

### 4.1. Сборка WPF без .NET SDK — csc + XAML как ресурс
Проверено 2026-09-25 в scratchpad-папке сессии: `csc.exe` 4.8.9221 (C# 5) со ссылками
`Framework64\v4.0.30319\WPF\PresentationFramework.dll`, `WPF\PresentationCore.dll`, `WPF\WindowsBase.dll`, `v4.0.30319\System.Xaml.dll`
собирает exe, который грузит окно из встроенного `Main.xaml` (`/resource:Main.xaml,Main.xaml` → `XamlReader.Load(GetManifestResourceStream(...))`), находит элементы через `FindName`, кириллица в XAML (UTF-8 без BOM) читается: вывод `WPF_SMOKE_OK title=15 rb=True clr=4.0.30319.42000`.
- XAML без `x:Class` и без обработчиков событий в разметке (иначе нужна компиляция BAML): элементы с `x:Name`, события подключаются в C# после `FindName`. Стили, цвета, шаблоны кнопок, полей, радиокнопок, флажков и полосы прокрутки — `ResourceDictionary` в том же XAML (стандартная тема Aero выглядит чужеродно на тёмном фоне, поэтому шаблоны свои).
- Альтернатива — `MSBuild.exe` из .NET Framework 4 с `Microsoft.WinFX.targets` и `WPF\PresentationBuildTasks.dll` (обе есть): даёт компиляцию XAML в BAML и `x:Class`, но требует csproj и старого MSBuild (ToolsVersion 4.0). .NET 8 WPF требует SDK — его нет. Выбран csc: один exe, как сейчас, под .NET Framework 4.8 (есть в Windows 10/11), без новых зависимостей.
- Ограничения C# 5: нет `?.`, `$"..."`, `nameof`, expression-bodied членов (текущий код их уже не использует).
- Иконка: `/win32icon` для exe; в окне и заголовке — `BitmapFrame.Create` из встроенного `app.ico`. Место под логотип — отдельный `Image x:Name="Logo"` 56×56 в шапке, чтобы потом заменить картинку одним ресурсом (решение 5).

### 4.2. Выбор папки игры (решение 4)
- **Блок в окне** — как `GAME LOCATION` у CPDD: заголовок «ПАПКА ИГРЫ» мелкими заглавными слева, справа серая подсказка «Папка, оканчивающаяся на Game\C7»; поле пути на всю ширину (моноширинный шрифт, скруглённая рамка, тёмная заливка); под ним две равные кнопки «Найти автоматически» и «Выбрать папку…». Под блоком строка результата проверки: «✓ Сборка игры 1.2018737.2044036 — поддерживается» / «✗ В папке нет C7-Win64-Shipping.exe» (зелёный/красный).
- **Диалог «Выбрать папку…»** — современный проводник Windows (`IFileOpenDialog` с `FOS_PICKFOLDERS` через COM-interop, ~60 строк объявлений в `installer/Ui/FolderPicker.cs`), тот же, что открывает CPDD (egui/rfd). Он отрисовывается системой и выглядит опрятно, в отличие от `FolderBrowserDialog` WinForms (дерево XP-стиля), и не тянет ссылку на `System.Windows.Forms`. Начальная папка — текущий путь или `C:\`. После выбора путь нормализуется `NormalizeGameDir` (`Program.cs:754-768`): можно выбрать корень игры или `GMZZLauncher`, установщик сам найдёт `Game\C7`.
- Путь можно ввести и руками: проверка через 400 мс после последнего изменения, без блокировки окна.
- **Автопоиск** (`FindGameFolder`, `:778-840`) дополнить списком CPDD (строки exe): `BiliBili/GMZZLauncher/Game/C7`, `GMZZLauncher/Game/C7`, `Program Files/GMZZLauncher/Game/C7`, `Program Files (x86)/GMZZLauncher/Game/C7` на всех фиксированных дисках (`DriveInfo.GetDrives()`, `DriveType.Fixed`, `IsReady`), вместо захардкоженных букв `C:`–`F:`. Признак игры — `Binaries\Win64\C7-Win64-Shipping.exe` и `Content\Paks\pakchunk0-Windows.pak` (сейчас достаточно одного из них, `:770-776`; для автопоиска требовать оба). Последняя выбранная папка запоминается в `%LOCALAPPDATA%\LotmRussianPatch\settings.json` и предлагается первой.

### 4.3. Файлы (новые/изменённые)
| Файл | Что |
|---|---|
| `installer/Program.cs` | `Main` + CLI + `PatcherBackend` + `GitHubReleaseClient`; класс `MainForm`, `--toggle`, `ToggleLanguage` удаляются. Запуск окна: `new Application().Run(MainWindow.Create(...))` в STA |
| `installer/Ui/MainWindow.xaml` | разметка и стили окна (ресурс `LotmRussianPatcher.MainWindow.xaml`) |
| `installer/Ui/MainWindow.cs` | загрузка XAML, привязка элементов, состояния кнопок, асинхронные операции через `Task.Run` + `Dispatcher` |
| `installer/Ui/FolderPicker.cs` | `IFileOpenDialog` (COM), выбор папки |
| `installer/PayloadSource.cs` | выбор payload (§4.4), распаковка, проверка sha256 |
| `installer/GameOptions.cs` | чтение/запись `cpdd_patcher_settings.lua` и блока Visual Clarity в Engine.ini (§4.5); без UI, покрывается тестами |
| `installer/InstallerCore.cs` | не переписывается; удаляются только `ToggleLanguage` и `ReplaceInFile` (§3) |
| `installer/build_installer.ps1` | ссылки WPF (полные пути в `Framework64\v4.0.30319\WPF\`, `System.Xaml.dll`), без `System.Windows.Forms`/`System.Drawing`; ресурсы `MainWindow.xaml`, `app.ico`; новые исходники |
| `tools/BuildTools.ps1` | `InstallerCoreTests` += `installer/GameOptions.cs`, `installer/PayloadSource.cs`, ссылки WPF и ресурс `MainWindow.xaml` (проверка разметки) |
| `tools/InstallerCoreTests.cs` | новые сценарии (§5), удалён `ToggleLanguage` |
| `tools/PackageRelease.ps1` | `-Publish` (§6), `Version` по умолчанию `v3.0.0-RU` |
| `installer/AssemblyInfo.cs` | `AssemblyVersion`/`FileVersion` `3.0.0.0` |

**Версии (решение 2):** `Program.VERSION = "3.0.0-RU"`, тег `v3.0.0-RU`; версия в `Init.lua` (`VERSION`) и `bootstrap.lua` (`Loader.Version` остаётся `0.4.5-RU` — это версия загрузчика CPDD, её не трогать) — сверить, как её поднимали раньше (`2.9.10-RU` → `3.0.0-RU`). Следующие сборки — `3.0.1`, `3.0.2`, …; `3.1.0` — только после редакции перевода. Записать правило в ROADMAP («Релизы») при исполнении.

### 4.4. Payload: только явный `--payload`, иначе GitHub
Порядок в `PayloadSource.Resolve`:
1. `--payload <папка|zip>` в командной строке (и в CLI, и при запуске окна: `Lord-of-Mysteries-Russian-Patch.exe --payload D:\gameDev\AbsoluteRU\patch_payload` открывает окно с этим пакетом; внизу окна и в журнале — «Локальный пакет: …»). Папка проверяется `ValidatePayloadContents`; zip распаковывается во временную папку заново или с проверкой sha256 zip, а не по размеру.
2. `lom-russian-patch-data.zip` рядом с exe — **только** это точное имя (раздача «архив + установщик» из bundle `PackageRelease.ps1:112-126`). Если доступен `release.json` релиза, sha256 сверяется; если нет — используется с записью в журнал «проверка по release.json недоступна».
3. Скачивание последнего релиза (как сейчас, `:1007-1115`).
4. Кеш `%LOCALAPPDATA%\LotmRussianPatch\payload\` — только если zip в кеше совпадает по sha256 с сохранённым рядом `release.json`.

Удалить: кандидатов `patch_payload`/`data` рядом с exe и выше (`:906-911`), путь репозитория (`:912`), поиск шаблонов `*patch*.zip`… рядом с exe (`:929-939`) и в `Загрузках` (`:941-956`), повторное использование распаковки по размеру (`:962-964`). `Uninstall` payload не ищет: ему хватает `installed_files.json`; payload нужен только для старых установок без списка (`InstallerCore.Uninstall:430-434`) — брать из `--payload` или кеша.
Токен: убрать запуск `gh auth token` (`:1406-1428`); оставить `GITHUB_TOKEN`/`GH_TOKEN` из окружения (для приватного репозитория разработчика). `--verify-bundle` без `--payload` отвечает «укажите --payload».

### 4.5. Опции (`installer/GameOptions.cs`)
- **Состояние** читается из игры: `DpsMeterMode` и `DesktopChatUI` из `cpdd_patcher_settings.lua` (регэкспы `DpsMeterMode\s*=\s*"(off|native|advanced|external)"`, `DesktopChatUI\s*=\s*(true|false)`); нет файла → умолчания `advanced` / `false`. Visual Clarity включён, если в Engine.ini есть целый блок BEGIN…END.
- **Запись настроек** при установке и кнопкой «Применить настройки»: ровно формат CPDD (§2), UTF-8 без BOM, LF. Если файл есть, но не распознаётся (чужие ключи, синтаксис), не перезаписывать: ошибка «файл изменён вручную: …», остальное продолжается. `cpdd_user_settings.lua` не создавать и не трогать.
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
  байт-в-байт как у CPDD (маркеры и комментарий на английском: блок общий с установщиком CPDD и с `EngineIniBridge.lua`). Включение: нет файла → создать `Saved/Config/Windows/Engine.ini` с блоком; есть → дописать блок в конец (если блок уже есть — заменить целиком). Выключение: удалить блок и одну пустую строку перед ним; если файл после этого пуст и в `Saved/RussianPatchBackups/options.json` записано, что его создали мы, удалить файл. Отказ без изменений: BOM UTF-16 / не UTF-8; BEGIN без END или два BEGIN. Концы строк — как в существующем файле (CRLF, если в нём CRLF).
  Внимание: Engine.ini в `Saved/Config` игра может переписывать при выходе. Если блок пропадёт после сессии — видно в чек-листе (п. 5); тогда выяснить, как это переживает CPDD.
- **Удаление русификатора:** `cpdd_*settings.lua` остаются (как сейчас и как у CPDD), блок Visual Clarity удаляется (он «managed by patcher»).
- **Внешний DPS-метр:** кнопка «Запустить внешний счётчик» активна при режиме `external` и наличии exe в игре; `Process.Start` с `UseShellExecute = true`, рабочая папка — папка exe. `IsGameRunning` дополнить процессом `Lord of Mysteries Combat Meter` (перед установкой его нужно закрыть, он лежит в `Saved/Mods`), а `GMZZLauncher` убрать: CPDD разрешает открытый лаунчер («BiliBili and TapTap launchers can remain open»).

### 4.6. Макет окна (≈ 780×680, тёмная тема: фон `#14181E`, панели `#1C212A`, рамки `#2C3340`, золото `#D4AF37`, текст `#DCE1EB`, вторичный `#8A94A6`; Segoe UI, путь — Consolas)
```
┌──────────────────────────────────────────────────────────────────────┐
│ [лого]  LORD OF MYSTERIES                                 v3.0.0-RU  │
│         РУССКАЯ ЛОКАЛИЗАЦИЯ · AbsoluteRU                             │
│         ● РУССКИЙ УСТАНОВЛЕН                                         │
├──────────────────────────────────────────────────────────────────────┤
│ ПАПКА ИГРЫ                        Папка, оканчивающаяся на Game\C7   │
│ ┌──────────────────────────────────────────────────────────────────┐ │
│ │ D:\Games\GMZZLauncher\Game\C7                                    │ │
│ └──────────────────────────────────────────────────────────────────┘ │
│ ┌──────── Найти автоматически ───────┐ ┌────── Выбрать папку… ─────┐ │
│ ✓ Сборка игры 1.2018737.2044036 — поддерживается                     │
├── СЧЁТЧИК УРОНА (DPS) ───────────────────────────────────────────────┤
│ ( ) Простой   (•) Расширенный   ( ) Внешний   ( ) Выключить все      │
│ Перемещаемые панели DPS v1.9.1.            [ Запустить внешний ▸ ]   │
├── ДОПОЛНИТЕЛЬНО ─────────────────────────────────────────────────────┤
│ [ ] Новый чат для ПК            перемещаемая панель чата             │
│ [ ] Visual Clarity  ⓘ           без тумана, bloom, motion blur…      │
├──────────────────────────────────────────────────────────────────────┤
│ [    Установить    ]   [ Применить настройки ]   [ Удалить ]         │
│ ▓▓▓▓▓▓▓▓▓▓░░░░░░  62%  Загрузка 36,0 / 58,0 МБ (4,1 МБ/с)  [Отмена]  │
│ ЖУРНАЛ                                                               │
│ 12:01:05 Проверка версии игры (SHA-256 всего pakchunk0)…             │
│ 12:01:07   -> Мост уже установлен, блок не перезаписывается.         │
├──────────────────────────────────────────────────────────────────────┤
│ [✈ Канал перевода] [✈ Автор] [♥ Поддержать на Boosty]  [? Как играть] │
│ Основано на английском патче CPDD · Discord CPDD · GitHub            │
└──────────────────────────────────────────────────────────────────────┘
```
Кнопка «Как играть» есть и в шапке справа от версии (иконка «?»), чтобы новичок увидел её до установки. Если папка игры не найдена, строка под блоком «ПАПКА ИГРЫ» добавляет «Игра ещё не установлена? → Как играть».
- Статусы (плашка в шапке): `ВЫБЕРИТЕ ПАПКУ ИГРЫ`, `ГОТОВ К УСТАНОВКЕ` (чистая поддерживаемая сборка или мост CPDD без наших файлов), `РУССКИЙ УСТАНОВЛЕН`, `ДОСТУПНО ОБНОВЛЕНИЕ vX` (версия установленного `Init.lua` старше релиза), `НУЖНО ВОССТАНОВИТЬ ЗАПУСК` (`InstalledDisabled`: `.disabled` после старого переключения или мост в pak без `CPDDTranslation.lua`), `ВЕРСИЯ ИГРЫ НЕ ПОДДЕРЖИВАЕТСЯ` (`PakState.Unknown`), `ИГРА ЗАПУЩЕНА`.
- Главная кнопка: «Установить» / «Обновить до vX» / «Переустановить» / «Восстановить запуск». «Применить настройки» активна, когда патч установлен и опции отличаются от записанных. «Удалить» — с подтверждением в собственном тёмном диалоге (не системный `MessageBox`).
- Подвал: «Основано на английском патче CPDD (Lani27)» + ссылки Discord CPDD (`https://discord.gg/yyds`, проверить перед релизом) и GitHub проекта; при наведении — подсказка «Русификатор использует загрузчик, моды и DPS-метр английского патча CPDD». Пункт README «Благодарности» с тем же текстом.
- Подсказки (`ToolTip`, в стиле окна) — русские версии текстов CPDD из §2; у Visual Clarity — полный список CVar.
- Проверка версии игры (sha256 426 МБ, 0,5–2 с) — в фоне после выбора папки, окно не блокируется.

### 4.7. Ссылки на соцсети (решение 6)
- Три кнопки-ссылки в подвале, в стиле окна (контурные, золотая рамка при наведении): «Канал перевода» (Telegram), «Автор» (личный Telegram), «Поддержать на Boosty» (выделена акцентом). Открытие — `Process.Start(new ProcessStartInfo(url) { UseShellExecute = true })`.
- Адреса не зашиваются в код: `installer/links.json` (UTF-8 без BOM, LF), встраивается ресурсом `LotmRussianPatcher.links.json`:
  ```json
  {
    "telegram_channel": "https://t.me/…",
    "telegram_author":  "https://t.me/…",
    "boosty":           "https://boosty.to/…",
    "cpdd_discord":     "https://discord.gg/yyds",
    "github":           "https://github.com/kapgrek/Lord-of-Mysteries-russia-patch"
  }
  ```
  Разрешены только `https://` на доменах `t.me`, `boosty.to`, `discord.gg`, `github.com` (проверка при загрузке; иначе кнопка скрыта). Пустое значение → кнопка скрыта. Тест §5 п.8.
- Те же ссылки — в `README.md` (раздел «Сообщество и поддержка»).
- **Адреса спрашиваются у пользователя на шаге 0** чата исполнения; не выдумывать.

### 4.8. Окно «Как играть» (решение 7)
- Отдельное окно `installer/Ui/HowToPlayWindow.xaml` (≈ 680×600, та же тёмная тема, владелец — главное окно, по центру над ним, закрывается «Закрыть» и Esc). Слева список разделов, справа прокручиваемый текст; или один прокручиваемый текст с оглавлением сверху — выбрать проще в реализации, без смены стиля.
- **Текст не в коде**: `installer/HowToPlay.md` (ресурс `LotmRussianPatcher.HowToPlay.md`) в упрощённой разметке, которую окно само превращает в `FlowDocument`: `# ` — раздел, `## ` — подзаголовок, `1. ` — шаг, `- ` — пункт, `**…**` — жирный, `[текст](https://…)` — ссылка (те же ограничения по https; для ссылок на загрузку игры добавить домены из текста пользователя в список разрешённых), `![](img/имя.png)` — картинка из ресурсов `installer/howto/*.png` (необязательно, на будущее). Редактировать инструкцию можно без знания C#; пересборка exe обязательна.
- Разделы (шаблон; текст внутри пишет или присылает пользователь — **агент фактов о регистрации и загрузке игры не придумывает**, оставляет в шаблоне пометки `TODO: текст от автора`):
  1. Где скачать игру (лаунчер);
  2. Регистрация аккаунта;
  3. Установка игры и первый запуск;
  4. Установка русификатора (этим установщиком; можно описать уже сейчас по §4.6);
  5. Что делать после обновления игры (установщик сообщит «версия игры не поддерживается» — ждать обновления русификатора, при проблемах «Проверить файлы» в лаунчере);
  6. Частые проблемы и где спросить (ссылки §4.7).
- Тест §5 п.9: разбор `HowToPlay.md` в `FlowDocument` (заголовки, списки, ссылки; запрещённая ссылка не превращается в гиперссылку).

## 5. Тесты (`tools/InstallerCoreTests.exe`, только `temp/installer-tests`)
Существующие сценарии, кроме удаляемого `ToggleLanguage`, проходят без изменений. Новые:
1. `GameOptions`: нет `cpdd_patcher_settings.lua` → умолчания `advanced/false`; запись → файл байт-в-байт формата CPDD; чтение обратно; для каждого из 4 режимов и обоих значений чата.
2. `GameOptions`: файл с посторонним содержимым → отказ, файл не изменён.
3. Visual Clarity: нет Engine.ini → создан с блоком; выключение → файл удалён (создан нами); Engine.ini с `[Core.System]` → блок дописан, остальное байт-в-байт; повторное включение не дублирует блок; выключение возвращает исходные байты; CRLF сохраняется; UTF-16 BOM → отказ без изменений; BEGIN без END → отказ.
4. Удаление: `cpdd_*settings.lua` остаются, блок Visual Clarity удалён, чужие строки Engine.ini целы.
5. `PayloadSource`: без `--payload` папки рядом с «exe» (фикстура в `temp/`) не подхватываются; zip с другим именем рядом не подхватывается; `--payload` папка без `bridge/` → отказ; `--payload` zip распаковывается и проходит `VerifyOwnedFiles`.
6. Старое состояние `CPDDTranslation.lua.disabled` + `RussianLocalization = false` → `InstalledDisabled`; установка из пакета возвращает `.lua`, `.disabled` удалён, `InstalledActive`, `pakchunk0` не изменён.
7. Разметка: `MainWindow.xaml` и `HowToPlayWindow.xaml` грузятся `XamlReader.Load` в STA-потоке теста, все `x:Name` из кода находятся (списки имён — публичные константы в `MainWindow.cs` / `HowToPlayWindow.cs`, тест берёт их же).
8. `links.json`: встроенный файл разбирается; ссылка не `https` или чужой домен → отбрасывается; пустое значение → кнопка скрыта.
9. `HowToPlay.md` → `FlowDocument`: число разделов, списков и гиперссылок совпадает с ожидаемым на тестовом тексте; `javascript:`/`http://`/чужой домен остаются текстом.
Установщик агент не запускает (AGENTS.md §1, `.claude/hooks/guard-game.ps1:22`): окно проверяется тестом разметки (п. 7) и пользователем.

## 6. `PackageRelease.ps1 -Publish` (`tools/PackageRelease.ps1:132-145`)
- **Причина:** `gh release view $Version -R $repo *> $null` (`:135`) при несуществующем релизе пишет в stderr; в Windows PowerShell 5.1 при `$ErrorActionPreference = 'Stop'` (`:9`) это `NativeCommandError`, и скрипт обрывается до `gh release create`. v2.9.6 публиковался вручную.
- **Исправление:** найти релиз по тегу через API, включая черновики (их нет в `releases/tags/<tag>`):
  `gh api "repos/$repo/releases?per_page=100" --jq ".[] | select(.tag_name == \"$Version\") | .id"` внутри блока с локальным `$ErrorActionPreference = 'Continue'`; результат и `$LASTEXITCODE` проверять явно, без `*> $null`/`2>&1`.
  - не найден → `gh release create $Version --draft --target main --title $Version (--notes-file|--notes '')` **без** assets;
  - затем `gh release upload $Version --clobber @assets` (повторяемо: при обрыве следующий запуск находит черновик и докачивает, второго черновика не создаётся);
  - затем `gh release edit $Version --draft=false --latest`.
  - Если найдено больше одного релиза с тегом (остатки прошлых обрывов) — остановиться и вывести их id, ничего не удалять.
- Проверка без публикации: ключ `-WhatIfPublish` (печатает результат поиска релиза и команды `gh`, которые выполнились бы) — на несуществующем теге (`v0.0.0-test`) и на существующем `v2.9.6-RU`. Настоящая публикация — только по просьбе пользователя.

## 7. План для чата исполнения
0. Спросить у пользователя: адреса Telegram-канала перевода, личного Telegram автора и страницы Boosty (§4.7); текст «Как играть» (§4.8) — прислать сейчас или сделать шаблон с `TODO`; какие домены сайтов загрузки игры разрешить в ссылках.
1. `tools/PackageRelease.ps1`: §6 + `-WhatIfPublish`; проверить на `v0.0.0-test` и `v2.9.6-RU`. Отдельный коммит.
2. Убрать переключение языка (§3): кнопка, `--toggle`, `PatcherBackend.ToggleLanguage`, `InstallerCore.ToggleLanguage`/`ReplaceInFile`, тест; добавить тест §5 п.6. Прогнать `InstallerCoreTests`.
3. `installer/GameOptions.cs` + тесты §5 п.1–4 (`tools/BuildTools.ps1 -Only InstallerCoreTests`).
4. `installer/PayloadSource.cs` по §4.4; из `Program.cs` удалить старый `ResolvePayloadDir` и `gh auth token`; CLI `--payload`. Тесты §5 п.5.
5. WPF: `installer/Ui/MainWindow.xaml`, `MainWindow.cs`, `FolderPicker.cs`, запуск окна в `Program.cs`, удаление `MainForm`; автопоиск по §4.2; `build_installer.ps1` по §4.1/§4.3. Ссылки (§4.7: `installer/links.json`, кнопки в подвале) и окно «Как играть» (§4.8: `HowToPlayWindow.xaml/.cs`, `installer/HowToPlay.md`, разбор в `FlowDocument`). Тесты §5 п.7–9. Собрать `installer/build_installer.ps1 -OutDir temp\installer-build` (не запускать).
6. Версия `3.0.0` (§4.3): `Program.VERSION`, `AssemblyInfo.cs`, `Init.lua VERSION`, `PackageRelease -Version`; правило нумерации — в ROADMAP «Релизы».
7. Документы: `docs/PROJECT_MAP.md` (строки установщика, новые файлы), `README.md` (опции, `--payload`, благодарности CPDD со ссылкой на Discord), `docs/LESSONS.md` (урок: «переименование `CPDDTranslation.lua` при мосте в pak ломает запуск — игра не стартовала; язык нельзя выключать удалением звена цепочки запуска»), ROADMAP — строка этапа 6 и «Прочее» про `-Publish`.
8. `tools/VerifyPatch.ps1`, `PackageRelease.ps1 -DataOnly -BuildDir temp\data` + `InstallerCoreTests.exe --check-payload <распакованный zip в temp>`. Коммиты по шагам, `push origin main`. Полный релиз и `-Publish` — только по просьбе пользователя.

## 8. Проверка
- Автоматическая: `tools/InstallerCoreTests.exe` — все сценарии `passed`, `failed 0`; `build_installer.ps1` без ошибок; `PackageRelease.ps1 -WhatIfPublish` на новом и существующем теге; `git diff --stat` не содержит `patch_payload/` кроме `Init.lua` (версия).
- **Чек-лист для пользователя** (собранный `Lord-of-Mysteries-Russian-Patch.exe` v3.0.0-RU):
  1. Запуск без аргументов: окно WPF в тёмной теме, блок «ПАПКА ИГРЫ» как на макете, путь найден автоматически, под ним «✓ Сборка игры … — поддерживается», плашка `РУССКИЙ УСТАНОВЛЕН`. В журнале нет «Обнаружены исходные файлы патча: D:\gameDev\…». Кнопки переключения языка нет, внизу «Основано на английском патче CPDD» и рабочая ссылка на Discord.
  2. «Выбрать папку…» открывает современный диалог проводника; выбор `D:\Games\GMZZLauncher` сам превращается в `…\Game\C7`. Ввод неверного пути вручную — красная строка, кнопки установки неактивны.
  3. Запуск с `--payload D:\gameDev\AbsoluteRU\patch_payload`: внизу «Локальный пакет: …», «Переустановить» ставит из репозитория.
  4. DPS «Внешний» → «Применить настройки»: `Saved\Mods\lua\cpdd_patcher_settings.lua` содержит `DpsMeterMode = "external"`; «Запустить внешний» открывает Combat Meter, в бою он получает данные. «Расширенный» — в игре панели DPS v1.9.1; «Простой» — кнопка «Статистика» везде; «Выключить все» — счётчиков нет.
  5. «Новый чат для ПК» → в игре перемещаемая панель чата. Visual Clarity → в `Saved\Config\Windows\Engine.ini` блок `; BEGIN CPDD VISUAL CLARITY PATCH`; в игре нет тумана и bloom; в `C7.log` — `[CPDDVisualClarity] submitted 18 managed Engine.ini CVars (failed=0)`. **Выйти из игры и проверить, что блок в Engine.ini остался.** Выключить опцию — блок исчез.
  6. «Удалить»: собственный тёмный диалог подтверждения; после удаления игра чистая, `cpdd_patcher_settings.lua` остался, блока Visual Clarity нет.
  7. Установка с открытым лаунчером BiliBili проходит; с запущенной игрой или Combat Meter — отказ с понятным текстом.
  8. Кнопки «Канал перевода», «Автор», «Поддержать на Boosty» открывают в браузере нужные страницы.
  9. «Как играть» (в шапке и в подвале) открывает окно в том же стиле: разделы «Где скачать игру», «Регистрация», «Установка и первый запуск», «Установка русификатора», «После обновления игры», «Частые проблемы»; текст читается, ссылки кликабельны, окно закрывается по Esc.

## Дальнейшее (не в этой задаче)
- ~~Своя иконка~~ — сделано 2026-09-26: иконка пользователя (иероглифы 诡秘 + «RU»), `installer/app.ico` (16–256, углы прозрачные) и `installer/icon.png` 512 для README; логотип в шапке окна 64×64 из того же `app.ico`.
- English как опция установщика: ставить данные CPDD (`github.com/Lani27/lord-of-mysteries-english-patch`, `release.json` + `lom-english-patch-data.zip`) тем же `InstallerCore.Install` через адаптер раскладки и `owned_files.json` из их `release.json → external_bridge.files`; блок моста и `supported_base_paks` совпадают (§3).

## Промпт для чата исполнения
> Выполни docs/tasks/TASK-015-installer.md по разделу «План для чата исполнения». Решения я уже принял (шапка файла): переключения языка нет, версия 3.0.0 (дальше 3.0.x), DPS-метр и опции как у CPDD, выбор папки в стиле установщика, логотип — позже, ссылки на Telegram-канал, Telegram автора и Boosty, окно «Как играть». Сначала спроси у меня по шагу 0 адреса ссылок и текст «Как играть» (адреса и факты не выдумывай). По шагам: починка PackageRelease.ps1 -Publish с -WhatIfPublish (без настоящей публикации); удаление переключения языка из окна, CLI и InstallerCore с тестом восстановления запуска; installer/GameOptions.cs (cpdd_patcher_settings.lua в формате CPDD, блок Visual Clarity в Engine.ini байт-в-байт как у CPDD); installer/PayloadSource.cs (локальный payload только по --payload, zip рядом с exe только по точному имени, без Загрузок, пути репозитория и gh auth token); WPF-окно по макету §4.6 с блоком «Папка игры» и выбором папки по §4.2, через csc + XAML как ресурс (§4.1); ссылки из installer/links.json (§4.7) и окно «Как играть» из installer/HowToPlay.md (§4.8); версия 3.0.0. Все новые сценарии — в tools/InstallerCoreTests.cs, только в temp/installer-tests. В папку игры ничего не пиши, установщик, игру и лаунчер не запускай, reference/ только читай. Коммить по шагам и запушь в main; релиз собирай и публикуй только по моей просьбе. В конце дай мне чек-лист из §8.

## Исполнение (чат 2, 2026-09-25, v3.0.0-RU)
Шаг 0 (ответы пользователя): Telegram-канал `https://t.me/LoM_ru_patch`, автор `https://t.me/AbsoluteGrek`, Boosty `https://boosty.to/kapgrek`. Текст «Как играть» — 8 шагов пользователя (лаунчер → Bilibili на телефоне → вход по QR → закрыть игру при выборе сервера → русификатор → играть) + картинка окна входа (`installer/howto/qr-login.png`); разделы «Установка русификатора», «После обновления игры», «Вопросы и поддержка» — по §4.6/§4.7. Лаунчер `D:\gameDev\LoM_Launcher.exe` (156 579 656 байт) в git не кладётся: ссылка ведёт на `https://github.com/kapgrek/Lord-of-Mysteries-russia-patch/releases/download/launcher/LoM_Launcher.exe` — релиз с тегом `launcher` **ещё не создан** (публикация только по просьбе пользователя; создать с `--latest=false`, иначе установщик примет его за последний релиз перевода). Ссылки на Bilibili-приложение нет (адрес не дан).

| Шаг | Коммит | Что |
|---|---|---|
| 1 | `bfa73f77` | `PackageRelease.ps1`: поиск релиза `gh api --paginate` (с черновиками; тег сравнивается в PowerShell — PS 5.1 срезает кавычки в `--jq`), черновик → `upload --clobber` → `edit --draft=false --latest`, стоп при нескольких релизах с тегом, `-WhatIfPublish` (без сборки). Проверено: `v0.0.0-test` (create/upload/edit), `v2.9.0-RU` (найден, upload/edit), `v2.9.6-RU` — **два релиза** (`396503544` опубликован, `396498707` лишний черновик) → остановка без изменений |
| 2 | `4d143954` | Удалены `--toggle`, кнопка, `PatcherBackend.ToggleLanguage`, `InstallerCore.ToggleLanguage`/`ReplaceInFile`; тест «старое состояние `.disabled` + `RussianLocalization = false` → установка восстанавливает запуск, pak не пишется» |
| 3 | `c31afd80` | `installer/GameOptions.cs` + 4 сценария (формат CPDD байт-в-байт, чужой файл не трогается, Visual Clarity: создание/удаление Engine.ini, дописывание/замена/удаление блока, CRLF, UTF-16/не UTF-8/битые маркеры → отказ; удаление русификатора) |
| 4 | `0044fdbf` | `installer/PayloadSource.cs` (+ `AppInfo.cs`, `PatcherBackend.cs` вынесен из `Program.cs`): `--payload` → точный `lom-russian-patch-data.zip` рядом с exe → GitHub → кеш только при совпадении с сохранённым `release.json`; sha256 теперь сверяется и без токена (`release.json` по `browser_download_url`; раньше у игроков не проверялся). Нет пути репозитория, `Загрузок`, `*patch*.zip`, `gh auth token`. `IsGameRunning` → `RunningBlocker`: без `GMZZLauncher`, с Combat Meter. 5 сценариев |
| 5 | `645e54f1` | WPF: `installer/Ui/` (`Theme.xaml`, `MainWindow.xaml/.cs`, `HowToPlayWindow.xaml/.cs`, `FolderPicker.cs`, `UiKit.cs`, `Links.cs`), `links.json`, `HowToPlay.md`; `build_installer.ps1` — WPF-ссылки и ресурсы; тесты разметки (все `ElementNames`, `MainWindow.Create()`), `links.json`, `HowToPlay.md`. Автопоиск — фиксированные диски × пути CPDD + реестр HKLM/HKCU + последняя папка (`%LOCALAPPDATA%\LotmRussianPatch\settings.json`). Высота окна ограничена рабочей областью экрана |
| 6 | `ec76fdfb` | Версия 3.0.0: `AppInfo.cs`, `AssemblyInfo.cs`, `app.manifest`, `Init.lua`, `VerifyPatch.ps1`, `PackageRelease.ps1`, README; правило нумерации в ROADMAP |
| 7–8 | этот коммит | README, PROJECT_MAP, LESSONS (переключение языка; PS 5.1: кавычки и одноэлементные массивы), ROADMAP; `--check-payload` проверяет и корень пакета |

Отступления от плана: бэкенд вынесен в `installer/PatcherBackend.cs` (а не оставлен в `Program.cs`), чтобы тесты собирали его без UI; тема окон — отдельный `Ui/Theme.xaml` в `Application.Resources` (общая для главного окна, «Как играть» и диалогов). Поддельного `Browse` в тестах нет: диалог проводника проверяет пользователь.

Проверка: `InstallerCoreTests.exe` — 26 сценариев, `passed 254, failed 0`; `build_installer.ps1 -OutDir temp\installer-build` — SUCCESS (подпись `UnknownError` и ошибка сканирования Defender — как и до задачи); `VerifyPatch` OK; `PackageRelease -DataOnly -BuildDir temp\data` → `--check-payload`: `files=1342 owned_files=OK bridge=OK payload_root=OK`; из `patch_payload/` изменён только `Init.lua` (версия). Установщик не запускался; вид окон проверен рендером разметки в PNG (`temp/render`, без доступа к игре).

### Правки после первого просмотра (2026-09-26)
- Релиз `launcher` создан (id `396953551`, не latest; `LoM_Launcher.exe` 156 579 656 байт, ссылка отдаёт 200). Лишний черновик `v2.9.6-RU` (`396498707`) удалён, тег и опубликованный релиз `396503544` на месте.
- Telegram-кнопки — с логотипом Telegram (`TelegramIcon` в `Theme.xaml`), перенесены в шапку справа; «Автор» → «Канал автора» (ссылка `t.me/AbsoluteGrek` не изменилась). Версия — под иконкой слева. В подвале — Boosty, «Как играть», благодарности CPDD.
- «Как играть»: шаги в обратном отсчёте 9 → 0 (номер берётся из текста как есть; шаги — абзацы с висячим отступом: `Table` в `FlowDocumentScrollViewer` сжимал вторую колонку до нуля, `List` умеет только возрастающие номера). Новый шаг «Подтвердите номер телефона и ID личности» со ссылкой на документ `ap.wps.com` (домен добавлен в `Links.AllowedHosts`). Автор перевода — [@KapGrek](https://t.me/KapGrek).