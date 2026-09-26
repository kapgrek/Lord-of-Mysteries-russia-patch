# Карта проекта AbsoluteRU (Project & Codebase Map)

Единый навигатор по файловой структуре, компонентам и точкам входа кодовой базы **AbsoluteRU** (Lord of the Mysteries / C7 Russian Localization Patch). Правила работы агента описаны в [AGENTS.md](../AGENTS.md).

---

## 1. Быстрый роутер задач (Quick Routing)

| Задача / Компонент | Где искать (Файлы и папки) | Что там находится |
| :--- | :--- | :--- |
| **Логика перехвата UI, шрифты, хуки строк** | `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua` | Хуки `TranslateDatabaseString`, вычисление FNV-1a хешей, загрузка шардов, автоисправление верстки UMG; размер текста — подгонка замером `runtimeFixes.TextFit` (TASK-011) |
| **Мод-лоадер / перехватчик `package.loaders`** | `patch_payload/Saved/Mods/bootstrap.lua` | Точка входа модов, подмена модулей (`external_searcher`), `merge_overlay`, флаг `DiagnosticsMode` |
| **Нативный загрузчик (Bridge)** | `patch_payload/bridge/LaunchInstance.native-bridge.padded.oodle`<br>`patch_payload/Binaries/Win64/lua/Launch/Base/CPDDTranslation.lua` | 4660-байтный патч-блок для `pakchunk0` и скрипт первичной инициализации |
| **Исходные тексты для перевода** | `source/translation_batches/batch_*.json`<br>`source/translation_batches/BATCH_MANIFEST.md` | Батчи строк (`target_ru`, `source_cn`, `ref_en`): `batch_001…027` (основной массив), `batch_028_autochess` (энциклопедия Автошахмат, EN-ключи с приоритетом), `batch_029_cpdd_264`, `batch_030_stringdb_aliases` (алиасы ключей StringDB), `batch_031_autochess_stringdb`, `batch_032_stringdb_ui`. **Source of Truth** для текстов |
| **Канон терминов и глоссарии** | `source/glossary/*.json`<br>`docs/GLOSSARY.md` | Пути, Последовательности, персонажи, артефакты, географические названия |
| **Компиляция строк в шарды игры** | `tools/ShardCompiler.cs` (+ `.ps1`) | Распределение строк из `batch_*.json` по 1024 шардам `RuntimeTextGemini_*.lua`. `.exe` собирается `tools/BuildTools.ps1` |
| **Нарезка чанков и импорт переводов** | `tools/BatchHelper.ps1` | `-Action Export` (чанк в `temp/temp_chunk.json`), `Import` (с автокомпиляцией шардов), `Stats`, `Dashboard`; батч по номеру `-Batch N` или имени `-BatchFile batch_031_….json` |
| **Термины и глоссарий** | `tools/GlossaryCheck.ps1`, `source/glossary/combat_stats.json` | Сверка `target_ru` с боевыми характеристиками: `-Report`, `-FixShort`, `-Export`/`-Import` (чанки для агента `ru-translator`), `-BuildDoc` (пересборка `docs/GLOSSARY.md`); скиллы `/glossary-check`, `/translate-chunk` |
| **Непереведённые строки StringDB** | `tools/StringDbGaps.ps1` | Промахи `src=stringdb` из логов диагностики, сверка побайтно с семантикой ShardCompiler, категории (Автошахматы, UI, навыки…), `-Report`, `-Emit <батч> -Category …`, `-Aliases <батч>` |
| **Валидация тегов и плейсхолдеров** | `tools/VerifyBatch.ps1`<br>`tools/VerifyPatch.ps1` | Теги `<Highlight>`, `%s`, `%d`, `{0}`, макросы `{*d,…}`, `{{player.name}}` (ERR), числа и хвосты `b` (WARN); синтаксис Lua |
| **Базы данных Excel (диалоги, квесты)** | `patch_payload/Saved/Mods/lua/cpdd_translation/Data/Excel/LanguageData/` | 38 таблиц строк **в байткоде LuaJIT** (`1B 4C 4A`), несмотря на расширение `.lua`. В `.gitattributes` помечены как `binary` |
| **Текстуры и виджеты IoStore** | `patch_payload/Saved/Mods/BakedText/blocks.bin`<br>`patch_payload/Saved/Mods/BakedText/manifest.json`<br>`tools/BakedTextManager.ps1` | 39 МБ пропатченных блоков для `.ucas` файлов контейнеров UE5 |
| **Движок и графический инсталлятор** | `installer/Program.cs`<br>`installer/PatcherBackend.cs`<br>`installer/InstallerCore.cs`<br>`installer/GameOptions.cs`<br>`installer/PayloadSource.cs`<br>`installer/AppInfo.cs`<br>`installer/supported_game.json` | `Program.cs`: `Main`, CLI, `--payload`. `PatcherBackend.cs`: поиск папки игры (диски × пути CPDD, реестр, последняя папка в `%LOCALAPPDATA%\LotmRussianPatch\settings.json`), статус, установка/удаление, запуск Combat Meter. `InstallerCore.cs`: проверка версии игры (sha256 всего `pakchunk0`), блок моста, бэкап в `Saved/RussianPatchBackups/`, установка и удаление только своих файлов (`installed_files.json`), BakedText; `.disabled` после старого переключения RU↔EN чинится установкой. `GameOptions.cs`: `cpdd_patcher_settings.lua` в формате CPDD, блок Visual Clarity в `Engine.ini`. `PayloadSource.cs`: `--payload` → zip рядом с exe (точное имя) → релиз GitHub (sha256 по `release.json`) → проверенный кеш. `AppInfo.cs`: версия и репозиторий |
| **Окно установщика (WPF)** | `installer/Ui/*.xaml`, `installer/Ui/*.cs`<br>`installer/links.json`<br>`installer/HowToPlay.md`, `installer/howto/*.png` | XAML без `x:Class`, встраивается ресурсом и грузится `XamlReader` (сборка `csc`, без .NET SDK); события подключаются в `MainWindow.cs` по `ElementNames`. `Theme.xaml` — общая тёмная тема, `UiKit.cs` — диалоги и тёмный заголовок, `FolderPicker.cs` — `IFileOpenDialog`. Ссылки соцсетей — `links.json` (только https на t.me, boosty.to, discord.gg, github.com). «Как играть» — `HowToPlay.md` → `FlowDocument` |
| **Тесты установщика** | `tools/InstallerCoreTests.cs` | Сценарии `InstallerCore`, `GameOptions`, `PayloadSource`, разметки окон, `links.json` и `HowToPlay.md` на поддельных pak из случайных байт в `temp/installer-tests/`; `--check-payload <dir>` проверяет распакованный zip данных |
| **Синхронизация с CPDD** | `tools/SyncCpdd.ps1`<br>`vendor/cpdd/` | Скачать релиз CPDD → сравнить с базой (`vendor/cpdd/BASE.json`) и `patch_payload/` → отчёт `reference/cpdd/<tag>/SYNC_REPORT.md` → `-Apply` выбранных компонентов (verbatim, 3-way merge `Init.lua`/`bootstrap.lua`, `state.json`, новые строки шардов в батч, `supported_game.json`) |
| **Сборка и публикация релиза** | `tools/PackageRelease.ps1`<br>`installer/build_installer.ps1`<br>`tools/BuildTools.ps1` | Установщик, `lom-russian-patch-data.zip` (+ `supported_game.json`, `owned_files.json` в корне zip), `release.json` (+ `supported_base_paks`, `launch_block`, `owned_files`) и bundle в `build/`. `-DataOnly -BuildDir temp\x` собирает только zip данных. С `-Publish`: черновик → загрузка assets (`--clobber`, повторяемо) → публикация как latest; `-WhatIfPublish` только печатает поиск релиза (через `gh api`, с черновиками) и команды `gh` |
| **Диагностика для разработки** | `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/AbsruDiagnostics.lua`<br>`tools/CollectDiagLogs.ps1`<br>`docs/DIAGNOSTICS.md` | Модуль сбора (хуки, непереведённое, переполнение, шрифты, текстуры); включается только файлом `Saved/Mods/lua/absoluteru_dev.lua` в игре. `CollectDiagLogs` копирует логи ИЗ игры в `reference/logs/<дата>/` и строит отчёты в `report/` |
| **Выгрузка ассетов «Божий путь» (TASK-018)** | `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/AbsruAssetExport.lua`<br>`tools/GodWayExport.ps1`<br>`docs/DIAGNOSTICS.md` (раздел AssetExport) | Dev-only (флаг `AssetExport` в `absoluteru_dev.lua`): пробы (`Probe = true` / `"retainer"`) и полная выгрузка текстур, атласов, материалов, раскладки, дорожки и кадров RetainerBox из памяти игры. `GodWayExport.ps1` копирует ИЗ игры в `reference/godway_export/raw/`, режет спрайты, пишет `manifest.json` и `summary.md` |
| **Дополнительные моды (DPS Meter, Чат)** | `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/DesktopChat.lua`<br>`patch_payload/Saved/Mods/ExternalDpsMeter/` | Мод чата для ПК и автономный счетчик урона |
| **Правила и защита ИИ-агента** | `AGENTS.md`<br>`.claude/settings.json`<br>`.claude/hooks/` | Регламент; permissions; хук-сторож папки игры и Stop-хук перекомпиляции шардов |
| **Задачи и уроки** | `docs/tasks/TASK-xxx.md`<br>`docs/LESSONS.md` | Планы из аналитического чата; разбор прошлых инцидентов |
| **Временные файлы агента (Scratch)** | `temp/` | Промежуточные файлы и одноразовые скрипты (пользователь может очистить) |
| **Внешние справочные материалы** | `reference/` | Английский патч CPDD, выгрузки из игры (не в git, не очищается) |

---

## 2. Иерархическое дерево репозитория

```
AbsoluteRU/
├── AGENTS.md                  # Правила для ИИ-агентов (~40 строк)
├── README.md                  # Общее описание проекта и инструкция для пользователей
├── .gitattributes             # eol=lf для .lua/.json; байткод cpdd_translation — binary
├── .gitignore                 # build/, *.exe, temp/*, reference/
├── .ignore                    # Исключения для поиска (шарды, BakedText, temp, reference, build)
├── .claude/
│   ├── settings.json          # permissions (allow/deny) и хуки
│   └── hooks/
│       ├── guard-game.ps1     # PreToolUse: блок изменений папки игры, запуска установщика/игры, force-push
│       └── recompile-shards.ps1 # Stop: ShardCompiler + VerifyBatch для изменённых батчей
│
├── docs/                      # Документация проекта
│   ├── PROJECT_MAP.md         # [ЭТОТ ФАЙЛ] Полная карта репозитория и правила поиска
│   ├── LESSONS.md             # Уроки прошлых инцидентов (ложные фиксы, хуки классов, кэши, CRLF)
│   ├── DIAGNOSTICS.md         # Диагностика для разработки: файл флагов, что собирается, форматы, чек-лист
│   ├── tasks/                 # TASK-xxx.md из аналитических чатов (шаблон в tasks/README.md)
│   ├── ARCHITECTURE.md        # Архитектурный отчет: мост, хуки package.loaders, LRU-кэш
│   ├── GLOSSARY.md            # Каноничный глоссарий терминов, Путей и Последовательностей
│   ├── TRANSLATION_GUIDE.md   # Руководство по форматированию, UMG-тегам, плейсхолдерам и чанкам для ИИ
│   ├── AI_TRANSLATOR_PROMPT.md# Оптимальный системный промпт для переводчика
│   ├── DESIGN_NOTES.md        # Заметки по реверс-инжинирингу и бэклог задач
│   └── TEXTURE_GUIDE.md       # Инструкция по замене текстур и шрифтов
│
├── source/                    # Исходные материалы перевода (Source of Truth)
│   ├── glossary/              # Машиночитаемые JSON-глоссарии
│   │   ├── pathways_and_sequences.json # 22 Пути и все 220 Последовательностей
│   │   ├── characters_and_factions.json # Имена, фракции, божества
│   │   ├── locations_and_geography.json # Города, страны, континенты
│   │   └── terms_and_items.json         # Артефакты, ритуалы, системные термины
│   └── translation_batches/   # batch_001.json ... batch_027.json, batch_028_autochess.json ... batch_032_stringdb_ui.json
│       └── BATCH_MANIFEST.md  # Манифест прогресса по всем батчам
│
├── patch_payload/             # Полезная нагрузка патча, внедряемая в клиент игры
│   ├── bridge/
│   │   └── LaunchInstance.native-bridge.padded.oodle # 4660-байтный патч для pakchunk0
│   ├── Binaries/Win64/lua/Launch/Base/
│   │   └── CPDDTranslation.lua # Стартовый шлюз входа в Mods/bootstrap.lua
│   └── Saved/Mods/            # Основной каталог модификаций
│       ├── bootstrap.lua      # Мод-лоадер (хук package.loaders, merge_overlay, DiagnosticsMode)
│       ├── manifest.lua       # Список активных модов
│       ├── translation-overrides.lua # Ручные оверрайды единичных строк
│       ├── BakedText/         # Блочный патч контейнеров IoStore (.ucas)
│       │   ├── blocks.bin     # Бинарные пропатченные блоки (39 МБ)
│       │   └── manifest.json  # Таблица смещений и контрольных сумм
│       ├── ExternalDpsMeter/  # Мод боевого лога и счетчика урона (сторонний .exe — единственный бинарник в git)
│       └── lua/
│           ├── cpdd_translation/ # Базы данных строк (Overlay) — 46 файлов байткода LuaJIT
│           │   ├── Data/Excel/LanguageData/ # 38 файлов StringDB_CN_Data_*.lua
│           │   ├── Data/Config/             # Константы и конфигурации
│           │   └── Framework/, Gameplay/, Launch/, Shared/
│           └── mods/
│               └── cpdd_runtime_fixes/      # Рантайм-мод локализации
│                   ├── Init.lua             # Ядро перехвата строк и UI Repair
│                   ├── AbsruDiagnostics.lua # Диагностика для разработки (только при Saved/Mods/lua/absoluteru_dev.lua)
│                   ├── DesktopChat.lua      # Адаптация окна чата для ПК
│                   ├── DpsMeter.lua         # Встроенный счетчик урона
│                   ├── DpsTelemetry.lua     # Телеметрия боя
│                   ├── EngineIniBridge.lua  # Мост параметров движка
│                   ├── ServerScheduleFix.lua# Коррекция серверных таймеров
│                   ├── WidgetNameIndex.lua  # Индекс виджетов интерфейса
│                   ├── RuntimeTextGemini_000.lua ... _3ff.lua # [1024 ШАРДА] (Генерируются!)
│                   └── LanguageSourceIndex_00.lua ... _ff.lua  # [256 ИНДЕКСОВ] (Генерируются!)
│
├── tools/                     # Утилиты автоматизации (*.exe не в git — собирает BuildTools.ps1)
│   ├── BuildTools.ps1         # Сборка всех tools/*.exe из .cs (csc .NET 4)
│   ├── BatchHelper.ps1        # Экспорт чанков в temp/, импорт переводов, статистика
│   ├── ShardCompiler.cs/.ps1  # Компилятор батчей в 1024 шарда RuntimeText
│   ├── VerifyBatch.ps1        # Валидатор плейсхолдеров и тегов в батчах
│   ├── VerifyPatch.ps1        # Полная проверка синтаксиса и целостности патча (Init.lua + AbsruDiagnostics.lua)
│   ├── CollectDiagLogs.ps1    # Логи диагностики ИЗ игры -> reference/logs/<дата>/, отчёты в report/
│   ├── GlossaryCheck.ps1      # Сверка перевода с глоссарием: -Report/-FixShort/-Export/-Import/-BuildDoc
│   ├── StringDbGaps.ps1       # Промахи StringDB из логов диагностики -> категории, -Report, -Emit/-Aliases в батч
│   ├── BakedTextManager.ps1   # Управление блоками BakedText для IoStore
│   ├── AutoTranslate.ps1      # Машинный перевод батчей (Google Translate / DeepL Free API)
│   ├── FixCapitalization.cs/.ps1 # Исправление регистра первой буквы
│   ├── MergeOldTranslation.cs/.ps1 # Слияние старых переводов
│   ├── MergeTranslated.cs     # Слияние переведенных чанков
│   ├── SyncCpdd.ps1           # Сверка с релизом CPDD: отчёт и применение компонентов
│   ├── InstallerCoreTests.cs  # Тесты InstallerCore на поддельных папках игры в temp/
│   └── PackageRelease.ps1     # Сборка релиза в build/ (+ -Publish в GitHub Release, -DataOnly)
│
├── installer/                 # Исходный код автономного установщика (*.exe не в git)
│   ├── Program.cs             # Main, CLI, --payload; окно — Ui/MainWindow
│   ├── PatcherBackend.cs      # Поиск папки игры, статус, установка/удаление, Combat Meter
│   ├── InstallerCore.cs       # Установка/обновление/удаление для папки игры
│   ├── GameOptions.cs         # cpdd_patcher_settings.lua и блок Visual Clarity в Engine.ini
│   ├── PayloadSource.cs       # Откуда пакет: --payload, zip рядом с exe, GitHub, кеш
│   ├── AppInfo.cs             # Версия и репозиторий
│   ├── Ui/                    # WPF: Theme.xaml, MainWindow, HowToPlayWindow, FolderPicker, UiKit, Links
│   ├── links.json             # Ссылки на соцсети (встраивается в exe)
│   ├── HowToPlay.md, howto/   # Текст и картинки окна «Как играть» (встраиваются в exe)
│   ├── supported_game.json    # Поддерживаемая сборка игры (генерирует SyncCpdd, встраивается в exe и кладётся в zip)
│   ├── build_installer.ps1    # Сборка EXE (csc + WPF, XAML/тексты как ресурсы; по умолчанию в build/)
│   └── AssemblyInfo.cs, app.ico, app.manifest
│
├── vendor/cpdd/               # Нетронутая база CPDD для 3-way merge (BASE.json, <tag>/Init.lua, bootstrap.lua, state.json, release.json)
│
├── build/                     # [не в git] Результаты PackageRelease: exe, payload zip, release.json, bundle
├── reference/                 # [не в git, не очищается] Внешние материалы
│   ├── cpdd/<tag>/            # Релизы CPDD для SyncCpdd (release.json, zip, unpacked/, SYNC_REPORT.md)
│   ├── cpdd-english/          # Английский патч CPDD 2.6.1 (exe и распакованный eng_stable/)
│   ├── logs/<yyyy-MM-dd_HHmm>/ # Копии логов диагностики из игры (CollectDiagLogs) + report/; logs/aggregate/ — сводный отчёт
│   └── tools/                 # Разовые утилиты для работы с reference (DumpEnglishStrings)
└── temp/                      # [не в git] Временная папка (Scratch). Безопасна для очистки!
```

---

## 3. Правила эффективного поиска для ИИ-агента

### Главная проблема: «Шардовый потоп» (Shard Flooding)
В каталоге `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/` лежат **1 280 автоматически генерируемых файлов**: 1024 шарда `RuntimeTextGemini_*.lua` и 256 индексов `LanguageSourceIndex_*.lua`. Поиск без фильтра забивает выдачу шардами, и нужные исходные файлы в неё не попадают.

### Исключения
Файл `.ignore` в корне уже исключает шарды, `BakedText/`, `temp/`, `reference/` и `build/` для инструментов на базе ripgrep (Grep/Glob в Claude Code). Если инструмент `.ignore` не учитывает, исключения нужно указать явно:

```json
"Excludes": [
  "**/RuntimeTextGemini_*",
  "**/LanguageSourceIndex_*",
  "**/BakedText/**",
  "temp/**",
  "reference/**",
  "build/**",
  ".git/**"
]
```

### Таргетированный поиск по компонентам
1. **Логика хуков UI и рантайма:** искать только в `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua` или `patch_payload/Saved/Mods/bootstrap.lua`.
2. **Строка перевода:** искать в батчах `source/translation_batches/`, а не в шардах `RuntimeTextGemini_*.lua`.
3. **Инструмент или утилита:** ограничивать поиск папкой `tools/`.
4. **Код установщика:** ограничивать поиск папкой `installer/`.
5. **Термины и имена персонажей:** смотреть `source/glossary/` или `docs/GLOSSARY.md`.
6. **Таблицы `cpdd_translation/`:** это байткод, текстовый поиск по ним бесполезен. Для исходного английского текста смотреть `reference/cpdd-english/`.
