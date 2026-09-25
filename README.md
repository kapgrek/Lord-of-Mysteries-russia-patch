# Lord of the Mysteries — Русский патч локализации (v3.0.0-RU)

Проект полной русской локализации игры **Lord of the Mysteries** (кодовое имя: **C7**, движок: **Unreal Engine 5**).

Архитектура патча построена на базе реверс-инжиниринга стабильной версии v2.6.3 с полной поддержкой безопасного No-Injection моддинга, шардированного рантайм-перевода, динамической адаптации верстки UI под кириллицу и блочного патчинга текстур IoStore.

---

## Состав репозитория

* **`patch_payload/`** — Готовая структура полезной нагрузки патча (1 342 файла), готовая к внедрению в игру:
  * `bridge/LaunchInstance.native-bridge.padded.oodle` — Проверенный нативный 4660-байтный Oodle-блок для `pakchunk0-Windows.pak`.
  * `Binaries/Win64/lua/Launch/Base/CPDDTranslation.lua` — Мост инициализации модов.
  * `Saved/Mods/bootstrap.lua` — Продвинутый мод-лоадер (No-Injection, хук `package.loaders[1]`).
  * `Saved/Mods/lua/cpdd_translation/` — 46 модулей баз данных (квесты, диалоги, скиллы, экипировка).
  * `Saved/Mods/lua/mods/cpdd_runtime_fixes/` — 1 024 шардов рантайм-перевода (`RuntimeTextGemini_*.lua`), 256 шардов индекса (`LanguageSourceIndex_*.lua`) и адаптированный `Init.lua` (UI Repair под русский язык).
  * `Saved/Mods/BakedText/` — Манифест и бинарные блоки (39.17 МБ) для in-place патчинга `.ucas` файлов контейнеров UE5.
  * `Saved/Mods/ExternalDpsMeter/` — Автономный счетчик урона (Combat Meter).
* **`docs/`** — Полная документация проекта:
  * [`PROJECT_MAP.md`](./docs/PROJECT_MAP.md) — Исчерпывающая карта файлов, подсистем и навигационный роутер репозитория.
  * [`ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — Исчерпывающий технический отчет об архитектуре внедрения и хуках Lua.
  * [`DESIGN_NOTES.md`](./docs/DESIGN_NOTES.md) — Архитектурный бэклог, отложенные задачи и спецификации на будущее.
  * [`GLOSSARY.md`](./docs/GLOSSARY.md) — Каноничный глоссарий 22 Путей, Последовательностей, персонажей и фракций.
  * [`TRANSLATION_GUIDE.md`](./docs/TRANSLATION_GUIDE.md) — Инструкция для переводчиков по разметке, тегам и переменным.
  * [`AI_TRANSLATOR_PROMPT.md`](./docs/AI_TRANSLATOR_PROMPT.md) — Готовый оптимизированный системный промпт для ИИ-чатов.
  * [`LESSONS.md`](./docs/LESSONS.md) — Уроки прошлых инцидентов (ложные фиксы, хуки UI, кэши, тайминги).
  * [`TEXTURE_GUIDE.md`](./docs/TEXTURE_GUIDE.md) — Руководство по замене графики и запеченных текстур.
* **`source/`** — Исходные данные для переводчиков:
  * `glossary/` — Структурированные JSON-глоссарии (Пути, персонажи, локации, термины).
  * `translation_batches/` — Батчи текстов для перевода в отдельном процессе.
* **`tools/`** — Набор автоматизированных утилит:
  * `BuildTools.ps1` — Сборка утилит `*.exe` из исходников `.cs` (бинарники в git не хранятся).
  * `BatchHelper.ps1` — Экспорт чанков для ИИ в `temp/` и импорт переводов в батч с автокомпиляцией шардов.
  * `VerifyBatch.ps1` — Валидатор целостности UMG-тегов, плейсхолдеров `%s` и синтаксиса в батчах.
  * `ShardCompiler.cs` / `.ps1` — Компилятор/распределитель строк по 1024 шардам на базе алгоритма FNV-1a.
  * `StringDbGaps.ps1` — Промахи StringDB из логов диагностики: категории, отчёт, выгрузка новых строк и алиасов в батч.
  * `PackageRelease.ps1` — Сборка установщика, payload-архива и `release.json` в `build/`; `-Publish` загружает их в GitHub Release.
  * `BakedTextManager.ps1` — Менеджер блочного патчинга `.ucas` контейнеров.
  * `VerifyPatch.ps1` — Полная валидация целостности патча, синтаксиса Lua и плейсхолдеров.
  * `SyncCpdd.ps1` — Сравнение релиза английского патча CPDD с нашей базой, отчёт и применение выбранных компонентов.
  * `InstallerCoreTests.cs` — Тесты `installer/InstallerCore.cs` на поддельных папках игры в `temp/`.
* **`installer/`** — Автономный установщик/деинсталлятор для игроков (WPF, .NET Framework 4.8, собирается `csc` без .NET SDK):
  * `Program.cs` — `Main` и CLI; `PatcherBackend.cs` — действия с папкой игры (поиск, статус, установка, удаление, внешний счётчик).
  * `Ui/` — окно в стиле установщика CPDD (`MainWindow.xaml` + `.cs`, тема `Theme.xaml`), выбор папки проводником (`FolderPicker.cs`), окно «Как играть» (`HowToPlayWindow`), ссылки (`Links.cs`).
  * `InstallerCore.cs` — Установка, обновление и удаление: проверка версии игры по `supported_game.json`, бэкап блока в `Saved/RussianPatchBackups/`, удаление только своих файлов.
  * `GameOptions.cs` — Опции CPDD: режим DPS-метра и новый чат (`cpdd_patcher_settings.lua`), блок Visual Clarity в `Engine.ini`.
  * `PayloadSource.cs` — Откуда берётся пакет: `--payload`, `lom-russian-patch-data.zip` рядом с exe, последний релиз GitHub (SHA-256 по `release.json`), проверенный кеш.
  * `links.json`, `HowToPlay.md`, `howto/*.png` — ссылки на соцсети и текст «Как играть» (встраиваются в exe; правка без знания C#, но с пересборкой).
  * `supported_game.json` — Поддерживаемая сборка игры (хеши `pakchunk0` и блока запуска), генерирует `tools/SyncCpdd.ps1`.
* **`vendor/cpdd/`** — Нетронутая база CPDD (версия в `BASE.json`) для 3-way merge в `tools/SyncCpdd.ps1`.
* **`temp/`** — Выделенная папка для временных файлов (промежуточные чанки ИИ, сырые ответы, тестовые логи). Безопасна для полной очистки в любой момент.
* **`reference/`** — Локальные внешние материалы (английский патч CPDD, выгрузки из игры). Не в git и не очищается.
* **`build/`** — Результаты сборки (`PackageRelease.ps1`). Не в git: готовый установщик и данные публикуются в [GitHub Releases](https://github.com/kapgrek/Lord-of-Mysteries-russia-patch/releases).

---

## Быстрый старт для игроков

1. Скачайте `Lord-of-Mysteries-Russian-Patch.exe` со страницы [последнего релиза](https://github.com/kapgrek/Lord-of-Mysteries-russia-patch/releases/latest) и запустите его. Игры ещё нет — нажмите **«Как играть»**: там ссылка на лаунчер (релиз [`launcher`](https://github.com/kapgrek/Lord-of-Mysteries-russia-patch/releases/tag/launcher)) и шаги входа через Bilibili.
2. Папка игры (оканчивается на `Game\C7`) находится автоматически, иначе — **«Выбрать папку…»**.
3. Выберите режим счётчика урона и дополнительные опции, нажмите **«Установить»**. Игру нужно закрыть, лаунчер можно оставить открытым.
4. Запустите игру через официальный лаунчер.

Установщик проверяет версию игры: если `pakchunk0` не совпадает с поддерживаемой сборкой (например, после обновления игры), он ничего не меняет и сообщает, что нужно дождаться обновления русификатора.

**Опции** (как в английском патче CPDD):
* **Счётчик урона (DPS):** «Простой» — кнопка «Статистика» игры везде; «Расширенный» (по умолчанию) — панели DpsMeter v1.9.1; «Внешний» — оверлей Combat Meter (кнопка «Запустить внешний»); «Выключить все». Пишется в `Saved/Mods/lua/cpdd_patcher_settings.lua`.
* **Чистая картинка** (Visual Clarity CPDD) — блок `; BEGIN/END CPDD VISUAL CLARITY PATCH` в `Saved/Config/Windows/Engine.ini`: без тумана, облаков, bloom, motion blur, lens flare, Lumen GI/отражений и AO. Остальной `Engine.ini` не меняется.

Новый чат CPDD установщик не предлагает (DesktopChatUI = false). Опции меняются кнопкой **«Применить настройки»**. **«Удалить»** убирает только файлы русификатора и блок «Чистая картинка»; `cpdd_*settings.lua` и другие моды остаются. Переключения на английский в установщике нет: оно ломало запуск игры.

**Для разработчика:** `Lord-of-Mysteries-Russian-Patch.exe --payload <папка|zip>` открывает окно (или выполняет команду CLI) с локальным пакетом вместо GitHub, например `--payload D:\gameDev\AbsoluteRU\patch_payload`. Без ключа установщик берёт только `lom-russian-patch-data.zip` рядом с собой или последний релиз. `--help` — список команд.

---

## Сообщество и поддержка

* Telegram-канал перевода: [t.me/LoM_ru_patch](https://t.me/LoM_ru_patch)
* Автор перевода: [@KapGrek](https://t.me/KapGrek)
* Канал автора: [t.me/AbsoluteGrek](https://t.me/AbsoluteGrek)
* Поддержать перевод: [boosty.to/kapgrek](https://boosty.to/kapgrek)

## Благодарности

Русификатор основан на английском патче **CPDD** (Lani27): загрузчик модов, мост запуска, моды, DPS-метр и Combat Meter взяты из него. Discord CPDD: [discord.gg/yyds](https://discord.gg/yyds).
