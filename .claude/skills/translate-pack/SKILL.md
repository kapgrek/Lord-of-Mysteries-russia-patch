---
name: translate-pack
description: Перевод пачки новых строк (сотни–тысячи) с экономией токенов — отдельный чат только для перевода, выгрузка строк в батч, волны по 4 агента ru-translator (Sonnet), импорт, проверка, коммит. Использовать, когда нужно перевести пачку из TASK-плана (StringDbGaps -Emit/-EmitData) или продолжить прерванную. Для правки терминов глоссария — translate-chunk.
---

# Перевод пачки строк

Почему так (TASK-019): чат исполнения потратил около 45 млн токенов, из них на перевод около 2 %. Основной агент сам читал код, документы и батчи. Каждое следующее обращение перечитывало контекст в 300–465 тыс. токенов, а четыре переводчика выдали 132 строки за 30 секунд. **Переводят субагенты, основной агент только запускает команды.** Его контекст должен оставаться маленьким.

## Правила основного агента
1. **Чат только для перевода.** Код, рантайм, диагностика, документы (кроме строки в `BATCH_MANIFEST.md`/TASK) — в другом чате. Если по ходу нашлась ошибка кода, записать её одной строкой в итог и не чинить.
2. **Не читать** `Init.lua`, батчи, шарды, чанки, ответы агентов, `TRANSLATION_GUIDE.md`, `GLOSSARY.md`: правила уже лежат у агента (`.claude/agents/ru-translator.md`), разметку проверяет `-Import`. Читать можно только этот скилл и TASK-файл пачки (раздел с пачкой, не целиком).
3. **Вывод команд обрезать:** `| Select-Object -Last 15` (или `-First`). Полный вывод не выводить.
4. **Агент — `subagent_type: "ru-translator"`** (у него `model: sonnet`). Если агента правили в этой же сессии и он не подхватился — `general-purpose` с `model: "sonnet"` и промптом «Прочитай `.claude/agents/ru-translator.md` и работай по нему». Никогда не переводить строки самому.
5. **Волна = до 4 агентов параллельно**, по одному чанку на агента. Промпт агенту ровно такой: «Чанк: temp/glossary_chunk_NNN.json. Ответ: temp/glossary_answer_NNN.json. Правила — в твоём описании. Верни одну строку: сколько строк переведено, ключи спорных.» Дождаться уведомлений о завершении, не опрашивать.
6. **Лимит на чат: 40 чанков (~2000 строк).** Потом импорт, проверка, коммит и остановка с итогом «осталось N строк — продолжить тем же промптом в новом чате». Прерванная пачка продолжается сама: `-ExportNew` выгружает только строки с пустым `target_ru`.
7. Ручная правка допускается только для отклонённых `-Import` строк: по одной, через `-Import` маленького ответа. Ответы агентов регулярками не править.

## Шаги
0. **Какая пачка.** Из TASK-файла (раздел «Порядок пачек»): имя батча, категории/поля, логи и `sid`. Если батч уже есть и в нём есть пустые `target_ru`, то сразу шаг 2.
1. **Выгрузка строк в батч** (один раз на пачку):
   - StringDB: `powershell -ExecutionPolicy Bypass -File tools\StringDbGaps.ps1 -Emit <батч> -Category <кат,…> [-OnScreen] -Logs <папка логов> -Sid <sid>`;
   - данные KSBC: `… tools\StringDbGaps.ps1 -EmitData <батч> -Fields <поле,…> -Logs … -Sid …`;
   - затем `… -Report -Logs … -Sid … | Select-Object -Last 25` для «до». Новый батч — `batch_NNN_<тема>.json`, следующий свободный номер; строка в `source/translation_batches/BATCH_MANIFEST.md`.
2. **Чанки:** `powershell -ExecutionPolicy Bypass -File tools\GlossaryCheck.ps1 -ExportNew -BatchFile <батч> -Count 50 | Select-Object -Last 3`: число строк и чанков. Чанк закрывается и по размеру: `-MaxBytes 40000` (по умолчанию) — сумма байт `source_cn`+`ref_en`+`target_ru`, минимум 1 строка; поэтому длинные строки справки (`<Assistant_*>`) дают чанки меньше 50 строк и агент не зависает на ответе (TASK-022).
3. **Волны:** чанки 001–004 → 4 агента; по завершении каждого — `… GlossaryCheck.ps1 -Import temp\glossary_answer_NNN.json | Select-Object -Last 8`. Отказы (ключ + причина) копить в список. Следующая волна — следующие 4 чанка. Стоп по лимиту из правила 6.
4. **Отказы:** если меньше 20 — одна дополнительная волна: собрать их в `temp\glossary_answer_fix.json` агентом (промпт: «Исправь строки по причинам отказа: <список>; чанк temp/glossary_chunk_NNN.json») и импортировать. Остальное перечислить в итоге.
5. **Проверка:** `tools\ShardCompiler.exe | Select-Object -Last 3`; `powershell -ExecutionPolicy Bypass -File tools\VerifyBatch.ps1 -Batch <номер батча> | Select-Object -Last 10` (0 ERR); `… GlossaryCheck.ps1 -Report | Select-Object -Last 12` (`B` не вырос); `… StringDbGaps.ps1 -Report -Logs … -Sid … | Select-Object -Last 25` («после»).
6. **Коммит:** `git add source/translation_batches/<батч> source/translation_batches/BATCH_MANIFEST.md patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/RuntimeTextGemini_*.lua patch_payload/Saved/Mods/lua/mods/cpdd_runtime_fixes/LanguageSourceIndex_*.lua` (только свои пути), сообщение `feat(translation): <TASK> pack N - <тема>, <X> strings`, push. Сборку релиза не запускать, если пользователь не просил.
7. **Итог пользователю (коротко):** переведено / отклонено / осталось; категории «до → после» из `StringDbGaps -Report`; 10 примеров «source → перевод» (взять `git diff` батча с `| Select-Object -First 60`); что проверить в игре.

## Шаблон промпта для запуска (его выдаёт аналитический чат или пользователь)
```
/translate-pack
Пачка: <N> из docs/tasks/TASK-xxx-*.md (раздел «Порядок пачек»).
Батч: source/translation_batches/<batch_NNN_тема>.json (<создать через StringDbGaps -Emit … / уже есть, продолжить>).
Строки: <-Category ui,quest | -EmitData -Fields … | -OnScreen>, логи reference/logs/<папка>, sid <sid>.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```
