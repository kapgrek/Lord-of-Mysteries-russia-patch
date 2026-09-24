# TASK-002: гигиена ShardCompiler (LF, путь репозитория)

Статус: **выполнено**, ждёт проверки пользователем в игре. Найдено при чистке репозитория 2026-09-24 (коммит `1ee4ecb`).
Решение по п.3: BOM убрать. Шарды грузятся через `require` → `bootstrap.lua` `read_chunk` (loadfile / `File.LoadFile` + `load`), и LuaJIT пропускает BOM сам. У CPDD шарды без BOM. Установщик хеши шардов не проверяет.
Результат: 1024 шарда без BOM и без `\r`. Побайтно каждый совпадает с HEAD без первых 3 байт (BOM). `-Root <path>` работает; по умолчанию корень определяется по расположению exe. `StringExtractor.cs` тоже пишет без BOM.

## Симптом
1. **CRLF в шардах.** После каждого запуска `tools/ShardCompiler.exe` все 1024 файла `RuntimeTextGemini_*.lua` на диске получают концы строк CRLF. В git они лежат в LF (`.gitattributes: *.lua text eol=lf`), поэтому `git status` чист. Но `tools/PackageRelease.ps1` собирает `lom-russian-patch-data.zip` из **рабочей копии**, и в релизный payload шарды попадают с CRLF, то есть не в том виде, в каком лежат в git. `git ls-files --eol` после запуска компилятора показывает `i/lf w/crlf` для 1025 файлов в `cpdd_runtime_fixes/`.
2. **Жёсткий путь.** Компилятор всегда читает батчи и пишет шарды в `d:\gameDev\AbsoluteRU`, откуда бы его ни запустили. Это ломает работу в другом клоне или worktree и проверку на подставных данных: тест Stop-хука на фейковом корне всё равно перезаписал настоящие шарды.

## Первопричина
- `tools/ShardCompiler.cs:357-367`: строки шарда собираются через `StringBuilder.AppendLine`, а он использует `Environment.NewLine` (`\r\n` на Windows). Файл записывается в `:368` через `File.WriteAllText`.
- `tools/ShardCompiler.cs:36`: `string root = @"d:\gameDev\AbsoluteRU";`. Из аргументов переопределяется только `batchesDir` (`:40-42`), а `shardsDir` (`:38`) всегда строится от жёсткого корня.
- Попутно: `tools/ShardCompiler.cs:350` задаёт `new UTF8Encoding(true)`, то есть шарды пишутся **с BOM** (`EF BB BF`). BOM есть и в HEAD. Это противоречит правилу AGENTS.md §5 (UTF-8 без BOM).

## План
1. `:357-367`: заменить `AppendLine(x)` на `Append(x).Append('\n')` (или сделать хелпер `Line(sb, x)`).
2. `:36-42`: определять корень репозитория от расположения exe: `Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."))` (exe лежит в `tools/`). Добавить именованные параметры `--root <path>`, `--batches <path>` и `--shards <path>`; сохранить обратную совместимость с позиционным `args[0]` = папка батчей.
3. `:350`, BOM (**нужно решение пользователя**): убрать BOM (`new UTF8Encoding(false)`) можно только после проверки, что рантайм (`Init.lua`, загрузка шардов через `loadstring`/`package.loaders`) и установщик не зависят от BOM. Если решение отложить, зафиксировать исключение в AGENTS.md.
4. Пересобрать `tools/BuildTools.ps1 -Only ShardCompiler`, запустить компилятор, затем `tools/VerifyPatch.ps1`.
5. Проверить, что вызывающие стороны работают без изменений: `tools/BatchHelper.ps1` (Import), `tools/MergeTranslated.cs:325`, `.claude/hooks/recompile-shards.ps1`.

## Проверка
- После запуска компилятора `git ls-files --eol -- 'patch_payload/**/RuntimeTextGemini_*.lua'` показывает `w/lf` для всех 1024 файлов, а `git status` чист (содержимое не изменилось).
- Если BOM убран, в git появится диф: 1024 файла на 3 байта короче. Это ожидаемо, коммитить отдельно.
- Запуск из копии репозитория в другой папке (или с `--root`) меняет шарды только в этой копии, а `D:\gameDev\AbsoluteRU` не трогает (сравнить mtime).
- `tools/PackageRelease.ps1` без `-Publish`: в zip шарды с LF. Чек-лист для пользователя в игре: русский текст в диалогах и UI отображается как в v2.9.0, в `C7.log` нет ошибок загрузки `RuntimeTextGemini_*`.

## Промпт для чата исполнения
> Выполни docs/tasks/TASK-002-tools-hygiene.md: в tools/ShardCompiler.cs замени AppendLine на явный '\n', корень репозитория вычисляй от расположения exe и добавь параметры --root/--batches/--shards (с совместимостью по args[0]). BOM не трогай без моего решения по пункту 3. Пересобери через tools/BuildTools.ps1, прогони компилятор, VerifyPatch и проверки из раздела «Проверка», закоммить и запушь.
