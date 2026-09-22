# Карта проекта AbsoluteRU (Project & Codebase Map)

Настоящий документ является единым навигатором по файловой структуре, компонентам и точкам входа кодовой базы **AbsoluteRU** (Lord of the Mysteries / C7 Russian Localization Patch).

---

## 1. Быстрый роутер задач (Quick Routing)

Если вам нужно выполнить конкретную задачу, используйте эту таблицу для прямого перехода к файлам без лишнего сканирования всего репозитория:

| Задача / Компонент | Где искать (Файлы и папки) | Что там находится |
| :--- | :--- | :--- |
| **Логика перехвата UI, шрифты, хуки строк** | `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua` | Хуки `TranslateDatabaseString`, вычисление FNV-1a хешей, загрузка шардов, автоисправление верстки UMG |
| **Мод-лоадер / перехватчик `package.loaders`** | `patch_payload/Saved/Mods/bootstrap.lua` | Точка входа модов, подмена модулей (`external_searcher`), `merge_overlay` для баз данных |
| **Нативный загрузчик (Bridge)** | `patch_payload/bridge/LaunchInstance.native-bridge.padded.oodle`<br>`patch_payload/Binaries/Win64/lua/Launch/Base/CPDDTranslation.lua` | 4660-байтный патч-блок для `pakchunk0` и скрипт первичной инициализации |
| **Исходные тексты для перевода** | `source/translation_batches/batch_*.json`<br>`source/translation_batches/BATCH_MANIFEST.md` | 27 батчей строк (`target_ru`, `source_cn`, `ref_en`). **Source of Truth** для текстов |
| **Канон терминов и глоссарии** | `source/glossary/*.json`<br>`docs/GLOSSARY.md` | Пути, Последовательности, персонажи, артефакты, географические названия |
| **Компиляция строк в шарды игры** | `tools/ShardCompiler.cs` / `.exe` / `.ps1` | Распределение строк из `batch_*.json` по 1024 шардам `RuntimeTextGemini_*.lua` |
| **Нарезка чанков и импорт из буфера** | `tools/BatchHelper.ps1` | `Export-ChunkToClipboard`, `Import-ChunkFromClipboard`, статистика батчей |
| **Валидация тегов и плейсхолдеров** | `tools/VerifyBatch.ps1`<br>`tools/VerifyPatch.ps1` | Проверка целостности тегов `<Highlight>`, `%s`, `%d`, `{0}` и синтаксиса Lua |
| **Базы данных Excel (диалоги, квесты)** | `patch_payload/Saved/Mods/lua/cpdd_translation/Data/Excel/LanguageData/` | 38 Lua-таблиц строк (`StringDB_CN_Data_maintask.lua`, `_skill.lua` и др.) |
| **Текстуры и виджеты IoStore** | `patch_payload/Saved/Mods/BakedText/blocks.bin`<br>`patch_payload/Saved/Mods/BakedText/manifest.json`<br>`tools/BakedTextManager.ps1` | 39 МБ пропатченных блоков для `.ucas` файлов контейнеров UE5 |
| **Движок и графический инсталлятор** | `installer/Program.cs`<br>`installer/PatcherEngine.cs`<br>`installer/Lord-of-Mysteries-Russian-Patch.ps1` | Windows Forms UI установщика, блочный патчер Oodle/IoStore, бэкапы |
| **Дополнительные моды (DPS Meter, Чат)** | `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/DesktopChat.lua`<br>`patch_payload/Saved/Mods/ExternalDpsMeter/` | Мод чата для ПК и автономный счетчик урона |
| **Временные файлы агента (Scratch)** | `temp/` | Единственная разрешенная папка для промежуточных файлов и скриптов |

---

## 2. Иерархическое дерево репозитория

```
AbsoluteRU/
├── AGENTS.md                  # Системные правила и инструкции для ИИ-агентов (включаются в промпт)
├── GEMINI.md                  # Зеркало инструкций для Gemini
├── README.md                  # Общее описание проекта и инструкция для пользователей
├── Lord-of-Mysteries-Russian-Patch.exe # Скомпилированный бинарник установщика (корень)
│
├── docs/                      # Документация проекта
│   ├── PROJECT_MAP.md         # [ЭТОТ ФАЙЛ] Полная карта репозитория и правила поиска
│   ├── ARCHITECTURE.md        # Архитектурный отчет: мост, хуки package.loaders, LRU-кэш
│   ├── GLOSSARY.md            # Каноничный глоссарий терминов, Путей и Последовательностей
│   ├── TRANSLATION_GUIDE.md   # Руководство по форматированию, UMG-тегам и плейсхолдерам
│   ├── AI_CHAT_WORKFLOW.md    # Регламент нарезки на чанки и слияния для LLM
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
│   └── translation_batches/   # Батчи строк для перевода (batch_001.json ... batch_027.json)
│       └── BATCH_MANIFEST.md  # Манифест прогресса по всем батчам
│
├── patch_payload/             # Полезная нагрузка патча, внедряемая в клиент игры
│   ├── bridge/
│   │   └── LaunchInstance.native-bridge.padded.oodle # 4660-байтный патч для pakchunk0
│   ├── Binaries/Win64/lua/Launch/Base/
│   │   └── CPDDTranslation.lua # Стартовый шлюз входа в Mods/bootstrap.lua
│   └── Saved/Mods/            # Основной каталог модификаций
│       ├── bootstrap.lua      # Мод-лоадер (хук package.loaders, merge_overlay)
│       ├── manifest.lua       # Список активных модов
│       ├── translation-overrides.lua # Ручные оверрайды единичных строк
│       ├── BakedText/         # Блочный патч контейнеров IoStore (.ucas)
│       │   ├── blocks.bin     # Бинарные пропатченные блоки (39 МБ)
│       │   └── manifest.json  # Таблица смещений и контрольных сумм
│       ├── ExternalDpsMeter/  # Мод боевого лога и счетчика урона
│       └── lua/
│           ├── cpdd_translation/ # Базы данных строк (Overlay)
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
├── tools/                     # Утилиты автоматизации и компиляции
│   ├── BatchHelper.ps1        # Экспорт/импорт чанков через буфер обмена
│   ├── ShardCompiler.cs/.exe/.ps1 # Компилятор батчей в 1024 шарда RuntimeText
│   ├── VerifyBatch.ps1        # Валидатор плейсхолдеров и тегов в батчах
│   ├── VerifyPatch.ps1        # Полная проверка синтаксиса и целостности патча
│   ├── StringExtractor.cs/.exe/.ps1 # Извлечение строк из оригинальных дампов
│   ├── BakedTextManager.ps1   # Управление блоками BakedText для IoStore
│   ├── FixCapitalization.cs/.exe/.ps1 # Исправление регистра первой буквы
│   ├── MergeOldTranslation.cs/.exe/.ps1 # Слияние старых переводов
│   ├── MergeTranslated.cs/.exe/.ps1 # Слияние переведенных чанков
│   └── PackageRelease.ps1     # Сборка релизного архива
│
├── installer/                 # Исходный код автономного установщика
│   ├── Program.cs             # GUI на Windows Forms (выбор пути, прогресс-бар, лог)
│   ├── PatcherEngine.cs       # Высокоскоростной блочный движок модификации .pak/.ucas
│   ├── Lord-of-Mysteries-Russian-Patch.ps1 # PowerShell-версия установщика
│   ├── build_installer.ps1    # Скрипт сборки Program.cs в EXE
│   ├── Install.bat            # Однокликовый батник запуска
│   └── AssemblyInfo.cs, app.ico, app.manifest
│
└── temp/                      # Временная папка (Scratch). Безопасна для очистки!
```

---

## 3. Правила эффективного поиска для ИИ-агента

### Главная проблема: «Шардовый потоп» (Shard Flooding)
В каталоге `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/` хранится **1 280 автоматически генерируемых файлов** (1024 шарда `RuntimeTextGemini_*.lua` и 256 индексов `LanguageSourceIndex_*.lua`).
Если запустить поиск без фильтра, лимит выдачи (50 результатов) **моментально заполнится шардами**, а нужные исходные файлы не попадут в ответ.

### Обязательные шаблоны исключений (Search Excludes)
При вызове `find_by_name` или `grep_search` **всегда** указывайте исключения:

```json
"Excludes": [
  "**/RuntimeTextGemini_*",
  "**/LanguageSourceIndex_*",
  "**/BakedText/blocks.bin",
  "**/BakedText/manifest.json",
  "**/translation_batches/**",
  "temp/**",
  ".git/**"
]
```

### Таргетированный поиск по компонентам
Вместо поиска по всему корню `d:\gameDev\AbsoluteRU`:
1. **Ищете логику хуков UI / рантайма?**  
   Ищите только в `patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua` или `patch_payload/Saved/Mods/bootstrap.lua`.
2. **Ищете строку перевода?**  
   Не ищите в шардах `RuntimeTextGemini_*.lua`! Ищите в батчах `source/translation_batches/` (через ripgrep по конкретному батчу или слову).
3. **Ищете инструмент или утилиту?**  
   Ограничивайте `SearchPath` папкой `tools/`.
4. **Ищете код установщика?**  
   Ограничивайте `SearchPath` папкой `installer/`.
5. **Ищете термины или имена персонажей?**  
   Смотрите в `source/glossary/` или `docs/GLOSSARY.md`.
