---
name: translate-chunk
description: Правка строк корзин B и C глоссария и перевод новых строк (сценарий «Новые строки», -ExportNew) субагентом ru-translator — Export чанков, перевод до 4 параллельно, Import с проверкой канона и разметки, VerifyBatch. Использовать после glossary-check, когда в B/C остались строки, или после выгрузки новых строк в батч.
---

# Правка терминов чанками

## Шаги
1. **Выгрузка:** `powershell -File tools\GlossaryCheck.ps1 -Export -Count 50` → `temp\glossary_chunk_NNN.json` (старые чанки удаляются). В чанк идут строки корзин `B` и `C`; у каждой — только найденные в ней термины (`ru`, `ru_short`, `must_match`, `forbidden`).
2. **Перевод:** по субагенту `ru-translator` на чанк, **не больше 4 одновременно**. Промпт: «Чанк: temp/glossary_chunk_NNN.json. Ответ: temp/glossary_answer_NNN.json. Правила — в твоём описании.» Дождаться всех ответов.
3. **Импорт:** по каждому ответу `powershell -File tools\GlossaryCheck.ps1 -Import temp\glossary_answer_NNN.json`. Строка отклоняется, если после правки нет канона или остался запрещённый вариант, изменилось число `%s`/`{…}`/`*d`/тегов/`\n` (против `source_cn` и старого `target_ru`), строка пустая или id не найден. Строки без изменений пропускаются.
4. **Отказы:** выписать ключи и причины. Если причина исправима (падеж вне `must_match`, потерянный тег) — собрать их в новый чанк или поправить вручную и импортировать повторно. Ложные совпадения оставить и перечислить в отчёте задачи.
5. **Проверка:** `tools\ShardCompiler.exe`, затем `powershell -File tools\VerifyBatch.ps1 -Batch N` по каждому затронутому батчу (номера — из вывода `-Import`); ERR быть не должно. Затем `GlossaryCheck.ps1 -Report` — цель `B = 0`, в `C` только ложные совпадения.
6. **Итог пользователю:** принято / без изменений / отклонено, таблица Report, выборка «было → стало» (по 3 строки на термин, `git diff` батчей).

## Сценарий «Новые строки» (TASK-019)
Для строк без перевода, выгруженных `StringDbGaps.ps1 -Emit … -OnScreen` / `-EmitData` / вручную в новый батч (`batch_034_stringdb_s5.json` и следующие).
1. **Выгрузка:** `powershell -File tools\GlossaryCheck.ps1 -ExportNew -BatchFile batch_NNN_*.json -Count 50` → `temp\glossary_chunk_NNN.json` (старые чанки удаляются). У каждой строки `"mode": "new"`, пустой `target_ru`, `terms` (боевые характеристики) и `names` (имена, места, Пути, понятия из `source/glossary/*.json`).
2. **Перевод:** `ru-translator` на чанк, не больше 4 одновременно; промпт тот же. Агент подхватывается только при старте сессии: если его правили в этой же сессии, вызвать `general-purpose` с текстом `.claude/agents/ru-translator.md` в промпте (LESSONS, TASK-017).
3. **Импорт:** `powershell -File tools\GlossaryCheck.ps1 -Import temp\glossary_answer_NNN.json`. Для новой строки разметка сверяется только с `source_cn`, канон — по `terms` строки.
4. **Проверка:** `tools\ShardCompiler.exe`, `powershell -File tools\VerifyBatch.ps1 -Batch NNN` (0 ERR), `GlossaryCheck.ps1 -Report` (`B` не растёт), `StringDbGaps.ps1 -Report` на тех же логах: строки пачки ушли из своих категорий.
5. **Итог пользователю:** сколько переведено, выборка «source → перевод» по типам (подписи, описания, имена), список отказов.

## Правила
- Чанки и ответы лежат в `temp/` и могут быть удалены — всё ценное оказывается в батчах после `-Import`.
- Ответы субагента не редактировать массово регулярками: править только отклонённые строки.
- Батчи пишет только `-Import` (UTF-8 без BOM, LF, меняется только `target_ru`).
