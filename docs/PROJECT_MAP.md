# Карта проекта AbsoluteRU (Project & Codebase Map)

Единый навигатор по файловой структуре, компонентам и точкам входа кодовой базы **AbsoluteRU** (Lord of the Mysteries / C7 Russian Localization Patch). Правила работы агента описаны в [AGENTS.md](../AGENTS.md).

---

## 1. Быстрый роутер задач (Quick Routing)

| Задача / Компонент | Где искать (Файлы и папки) | Что там находится |
| :--- | :--- | :--- |
| **Логика перехвата UI, шрифты, хуки строк** | `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua` | Хуки `TranslateDatabaseString`, вычисление FNV-1a хешей, загрузка шардов, автоисправление верстки UMG |
| **Мод-лоадер / перехватчик `package.loaders`** | `patch_payload/Saved/Mods/bootstrap.lua` | Точка входа модов, подмена модулей (`external_searcher`), `merge_overlay`, флаг `DiagnosticsMode` |
| **Нативный загрузчик (Bridge)** | `patch_payload/bridge/LaunchInstance.native-bridge.padded.oodle`<br>`patch_payload/Binaries/Win64/lua/Launch/Base/CPDDTranslation.lua` | 4660-байтный патч-блок для `pakchunk0` и скрипт первичной инициализации |
| **Исходные тексты для перевода** | `source/translation_batches/batch_*.json`<br>`source/translation_batches/BATCH_MANIFEST.md` | 28 батчей строк (`target_ru`, `source_cn`, `ref_en`), включая `batch_028_autochess.json`. **Source of Truth** для текстов |
| **Канон терминов и глоссарии** | `source/glossary/*.json`<br>`docs/GLOSSARY.md` | Пути, Последовательности, персонажи, артефакты, географические названия |
| **Компиляция строк в шарды игры** | `tools/ShardCompiler.cs` (+ `.ps1`) | Распределение строк из `batch_*.json` по 1024 шардам `RuntimeTextGemini_*.lua`. `.exe` собирается `tools/BuildTools.ps1` |
| **Нарезка чанков и импорт переводов** | `tools/BatchHelper.ps1` | `-Action Export` (чанк в `temp/temp_chunk.json`), `Import` (с автокомпиляцией шардов), `Stats`, `Dashboard` |
| **Валидация тегов и плейсхолдеров** | `tools/VerifyBatch.ps1`<br>`tools/VerifyPatch.ps1` | Проверка целостности тегов `<Highlight>`, `%s`, `%d`, `{0}` и синтаксиса Lua |
| **Базы данных Excel (диалоги, квесты)** | `patch_payload/Saved/Mods/lua/cpdd_translation/Data/Excel/LanguageData/` | 38 таблиц строк **в байткоде LuaJIT** (`1B 4C 4A`), несмотря на расширение `.lua`. В `.gitattributes` помечены как `binary` |
| **Текстуры и виджеты IoStore** | `patch_payload/Saved/Mods/BakedText/blocks.bin`<br>`patch_payload/Saved/Mods/BakedText/manifest.json`<br>`tools/BakedTextManager.ps1` | 39 МБ пропатченных блоков для `.ucas` файлов контейнеров UE5 |
| **Движок и графический инсталлятор** | `installer/Program.cs`<br>`installer/PatcherEngine.cs`<br>`installer/Lord-of-Mysteries-Russian-Patch.ps1` | Windows Forms UI установщика (данные качает из GitHub Releases, `Program.cs:1103`), блочный патчер Oodle/IoStore, бэкапы |
| **Сборка и публикация релиза** | `tools/PackageRelease.ps1`<br>`installer/build_installer.ps1`<br>`tools/BuildTools.ps1` | Установщик, `lom-russian-patch-data.zip`, `release.json` и bundle в `build/`. С `-Publish` всё загружается как assets GitHub Release |
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
│   └── translation_batches/   # batch_001.json ... batch_027.json, batch_028_autochess.json
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
│   ├── VerifyPatch.ps1        # Полная проверка синтаксиса и целостности патча
│   ├── StringExtractor.cs/.ps1 # Извлечение строк из оригинальных дампов
│   ├── BakedTextManager.ps1   # Управление блоками BakedText для IoStore
│   ├── AutoTranslate.ps1      # Машинный перевод батчей (Google Translate / DeepL Free API)
│   ├── FixCapitalization.cs/.ps1 # Исправление регистра первой буквы
│   ├── MergeOldTranslation.cs/.ps1 # Слияние старых переводов
│   ├── MergeTranslated.cs     # Слияние переведенных чанков
│   └── PackageRelease.ps1     # Сборка релиза в build/ (+ -Publish в GitHub Release)
│
├── installer/                 # Исходный код автономного установщика (*.exe не в git)
│   ├── Program.cs             # GUI на Windows Forms (выбор пути, прогресс-бар, лог)
│   ├── PatcherEngine.cs       # Высокоскоростной блочный движок модификации .pak/.ucas
│   ├── Lord-of-Mysteries-Russian-Patch.ps1 # PowerShell-версия установщика
│   ├── build_installer.ps1    # Сборка Program.cs в EXE (по умолчанию в build/)
│   ├── Install.bat            # Однокликовый батник запуска
│   └── AssemblyInfo.cs, app.ico, app.manifest
│
├── build/                     # [не в git] Результаты PackageRelease: exe, payload zip, release.json, bundle
├── reference/                 # [не в git, не очищается] Внешние материалы
│   ├── cpdd-english/          # Английский патч CPDD 2.6.1 (exe и распакованный eng_stable/)
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
