# TASK-042: CPDD v2.7.5 — применять ли и как

Чат 1 (анализ), 09.11.2026. Материалы: `reference/cpdd/v2.7.5/SYNC_REPORT.md` (dry-run 09.11 09:28), `reference/cpdd/v2.7.5/sync/Init.lua.merged`, dev-сессия `reference/logs/2026-11-09_1005` (v3.1.1-RU, 10 мин: логин, HUD, загрузка), плюс отчёты `untranslated.csv` всех 32 dev-сессий в `reference/logs/`.

## Итог

**Рекомендация: применить v2.7.5 частично. Взять только `state` и `shards`. Рантайм (`Init.lua`, `Init.lua.compat.luac`) не применять, хуки upstream не переносить. `bakedtext` не трогать.**

`SyncCpdd -Tag v2.7.5 -Apply` целиком запускать **нельзя**:
1. Он удалит наш `patch_payload/Saved/Mods/BakedText/blocks.bin` и `manifest.json`: см. `tools/SyncCpdd.ps1:427` и п. 4.
2. Для `Init.lua` merge3 не даёт ничего полезного, автоматически его не применить (п. 2).

Релиз не нужен: в игре ничего не меняется (п. 6).

## 1. Факты

### 1.1. Наш `Init.lua` — форк CPDD v2.6.4, а не v2.7.x
- `vendor/cpdd/BASE.json`: `tag` = v2.7.1, но `component_bases."Saved/Mods/lua/mods/cpdd_runtime_fixes/Init.lua"` = **v2.6.4**, `bakedtext` = v2.6.4. В TASK-032 `Init.lua` намеренно не синхронизировали (`TASK-032-game-update-2218968.md:23, 36, 51`).
- Размеры: v2.6.4 = 7 863 строки, наш = 12 784, upstream v2.7.1 = 697 строк (+ байткод `Init.lua.compat.luac`), v2.7.5 = 1 483 строки. В v2.7.0 upstream переписал рантайм под exact-source: убрал широкие «подметания» UI и ID-оверлеи.
- Поэтому dry-run делает merge3 с базой v2.6.4: ours = 12 784 строки, theirs = 1 483. Из 14 конфликтов в `Init.lua.merged` один охватывает почти весь файл: `:2439–11426` (8 676 наших строк против 311 upstream). Если «разрешить» его в пользу upstream, мы потеряем весь наш рантайм (StringDbPack, fit, шрифты, диагностику, data-хуки). Если в пользу нашего — получим ровно наш файл.

### 1.2. Что добавил upstream v2.7.1 → v2.7.5 (`git diff --no-index vendor/cpdd/v2.7.1/Init.lua …/v2.7.5/…/Init.lua`: +786 строк, 0 удалений)
| Блок upstream | Что делает | У нас |
|---|---|---|
| `visibleTextExactOverrides[...] = "<EN>"` (13 строк) | английские правки | для RU не нужно |
| `compactSources` + обёртка `exactCurrent` | короткие EN-подписи (`装备`→`Gear`, `米`→`m`) | для RU не нужно, у нас свой канон кнопок |
| `restoreMethod`/`restoreHook`/`restoreLabels` — ≈40 классов (BrassTome, Login, Task, HUD_Task, NPCBtnCut, ItemSmall, SkillCustomizer, Talent, Equipment, Bag, PVPLastHunt, Border/MimeWhite…) | возвращает точечный ремонт виджетов, потерянный при переписывании v2.7.0 | **уже есть**: `exactWidgetRepairSpecs` (`Init.lua:10088–10740`, цикл `:10741`), унаследовано от v2.6.4 (`vendor/cpdd/v2.6.4/Init.lua:6601`) и расширено нами |
| `DescFormulaHelper.GenerateTipsDesc`, `SkillCustomSystem.Generate*`, `GetCurrentSkillRelatedTalentIDs`, `GuildSystem.RoleIDToRoleName/GetOccupationText` | перевод шаблонов и возвращаемых строк | **уже есть**: `Init.lua:7650–7737, 7785–7819, 8059–8068` |
| `installCurrency`, `formatPrice`, `FormatScoreTip`, `GetFormatNumberString`, `PVP_Stats_Item`, аукцион и мода в обменнике, `kg_require` | группировка цифр в ценах | **уже есть** и устроено иначе: `runtimeFixes.installCurrencyFormatting` `:9122`, `installLastHuntScoreFormatting` `:9105`, обменник `:9180–9299`, PVP `:9341–9446`. У upstream `money()` для чисел < 100 000 возвращает число без форматирования, наш `formatGameMoney` форматирует по-своему. Если поставить оба, выйдет **двойная обёртка с разным результатом** |
| `speakerText`/`authoredText`: `Dialogue_Panel`, `Sequence_Panel`, `HUDAside_Bubble`, `HeadInfoName`, `HeadInfoBubble`, `DialogueTalk.ShowContent` | имена говорящих и аргументы диалогов | **уже есть**: data-спеки `:10602–10620`, `HeadInfoName` `:7521–7540` (`translateVisibleText`), `DialogueTalk` `:8339`. К тому же у нас диалоги переводятся уже на уровне StringDB (`StringDbPack`, TASK-033), а upstream после отключения ID-оверлеев переводит их только на экране |
| `RaceTrace_Widget.UpdateDistance` (`123米`→`123m`) | единица расстояния | **уже есть** `:7544` |
| Layout-блок `do … end`: `Fashion_DetailExpand`, `Sequence_*`, `DialogueTalk.LineMaxCharCount`, `SceneTextBoardComponent` | шрифты и масштаб для длинного EN | для RU не сработает: все ветки стоят за `ascii()`/`plain()`, а кириллица их не проходит. С нашим fit (TASK-011) и `LineMaxCharCount` (2 места в `Init.lua`) он **конфликтовал** бы на остаточном английском |
| `ItemTips_Item.FillMainLibText/FillLibText`, `LibText`, `ItemTipsText_Item`, `ItemTipsEquipStory` | описания предметов | 3 из 4 **уже есть** (`:10657–10668`). Нет `ItemTips_Item` |
| `Dialogue_CSStyle/CSLine.ShowContent`, `ReviewListItem.OnRefresh`, `DialogueOptionItem` (`Text_Item`), `Loading_Panel` (`Text_MapName`, `TipsShuffle`) | катсцены, журнал реплик, варианты ответа, экран загрузки | **нет** точечных хуков. Покрыто иначе: текст приходит уже переведённым из StringDB, `Data.Excel.DialogueOptionText` `:6166`, `Loading_Panel` закрывают late-class и owner-обход (в `hooks.csv` они ACTIVE с text_changes) |
| `contracts.json` | упоминается только в комментарии (`-- audited in contracts.json`), в payload такого файла нет | — |

### 1.3. Что видно непереведённым в логах
- `2026-11-09_1005/report/untranslated.md`: видимых (`vis=True`) виджетов 18, и ни один не относится к классам из п. 1.2. Это имена и титулы игроков (`CreateRoleChooseItem`, `WBP_AppellationInfo_Lv1`), объявления в бегущей строке с никами (`WBP_Marquee_Announcement`), `ESC` и один реальный промах: `HUD_Panel/Text_Object_lua` = `魔术师牌` (перевод есть в batch_016, но не применился). Его upstream тоже не закрывает. HUD_Task/Sequence-плейсхолдеры скрыты (`vis=False`).
- Во всех 32 сессиях `reference/logs/*/report/untranslated.csv` ни разу не встретились непереведённые строки в `Dialogue_CS*`, `ReviewListItem`, `DialogueOptionItem`, `ItemTips_Item`, `NPCCSDialog`. Совпадения по шаблону дают только `Announce_Panel` (серверные объявления) и `WBP_Shops_TabLv2Text_Item`.
- **Вывод:** ни один новый хук upstream не закрывает видимый у нас пробел. 90 % из них дублируют наши хуки, а валюта и layout с ними конфликтуют.
- **Оговорка:** dev-сессия 09.11 короткая, и `fix:DialogueTalk.ShowContent`, `Sequence_Panel.ShowDialoguePanel` там NEVER_CALLED (`hooks.csv`). Катсцены, журнал реплик и подсказки предметов ею не проверены. Поэтому эти 4 класса идут в чек-лист (п. 7), а не в правку «на удачу» (AGENTS §4).

### 1.4. Строки шардов
- В v2.7.5 добавлено 141 запись, из них 112 нет в батчах на момент dry-run. После TASK-041 (`batch_049_hotpatch_2295021.json`) без перевода остаются 26:
  - 24 технические `终末猎杀草丛;草丛组NN` (имена групп кустов в «Финальной охоте»). Их нет ни в StringDB билда 2295021 (`reference/stringdb_dump/2295021/new_keys_2218968_to_2295021.csv`), ни в одном логе — игрок их не видит.
  - 2 варианта правил 四方联赛: `RuntimeTextGemini_0e1.lua` (2 072 симв.) и `RuntimeTextGemini_3eb.lua` (602 симв.), оба начинаются с `联赛新赛季前两轮…`. **Почему они не совпали:** дело не в пробелах. Это другая редакция текста. По сравнению с нашими ключами batch_049 (2 050 и 580 симв., из `emit_list_extra.txt`) в upstream после `…战略服档位越高，可获得的奖励越丰厚` вставлена фраза **`，黄金战略服仅会在最高强度等级的战略服中产生`** (22 символа). Время `周日20:45开启` одинаковое. С batch_047 (CPDD 2.7.1) они расходятся ещё и временем (`20:00` → `20:45`). В дампе 2295021 (`resolved.json`, `new_keys_*.csv`) этой фразы **нет** (0 совпадений). Значит, это текст промежуточного хотпатча (2228458/2255640), который 2295021 заменил. В текущей игре он не появится.
- У 23 записей изменился EN: это только `ref_en`, `SyncCpdd` лишь предупреждает (`SyncCpdd.ps1:501`). На русский перевод это не влияет.

## 2. Почему не Apply рантайма и не выборочный перенос
- Apply невозможен (п. 1.1), а выборочно переносить нечего: всё полезное для RU у нас уже есть (п. 1.2–1.3).
- Риск двойного перевода и двойной обёртки. `restoreMethod` распознаёт повторную установку только своих обёрток (`methods[name] == original`), а наши `diagWrap`/`__cpdd*`-флаги не видит. Валюта получила бы два форматтера с разным результатом. `HeadInfoName.OnHeadNameChanged` гонял бы `translateVisibleText`, а затем `exactCurrent` по уже русскому тексту (no-op, но лишний поиск на каждом кадре смены имени). Layout-блок спорил бы с нашим fit.
- Лимит локальных переменных: `Init.lua` = 182 переменные верхнего уровня, порог `VerifyPatch.ps1:174–186` — 190 (жёсткий лимит 200). Блок upstream добавляет ≈ 25 top-level `local` (`restoredWrappers`, `restoreMethod`, `restoreHook`, `namedWidget`, `repairNamed`, `restoreLabels`, `grouped`, `finite`, `money`, `installCurrency`, `repaintPrice`, `restoreCached`, `authoredText`, `speakerText`, …). Без `do … end` он пробил бы порог. Если когда-нибудь переносить хук, то только строкой в существующие таблицы спеков (`exactWidgetRepairSpecs` или data-спеки `:10602`), без новых top-level `local`.

## 3. `translation-overrides.state.json`
Это метаданные установщика CPDD, рантайм файл не читает (`TASK-003-cpdd-sync.md:50`, grep по `bootstrap.lua`, `Init.lua`, `installer/`). В v2.7.5 изменились id и версия релиза, пропал `mappingKind: "overlay"`, добавлены записи. `SyncCpdd` перегенерирует файл с RU-id (`Convert-StateToRussian`, `:440`). Это безопасно: так файл будет соответствовать базе.

## 4. BakedText: что значит «removed»
- `SYNC_REPORT.md`: `blocks.bin` и `manifest.json` [bakedtext] **removed**. Upstream убрал BakedText ещё в v2.7.0 и заменил его `baked_images` с профилями под сборки (`TASK-032-game-update-2218968.md:24`, этап C `:63–64`). В v2.7.1 файлов тоже нет, поэтому `component_bases.bakedtext` = v2.6.4. В v2.7.5 ничего нового тут нет.
- **Опасность:** `bakedtext` входит в `$verbatimComponents` (`SyncCpdd.ps1:27`). При `-Apply` без `-Components` для verbatim-файла с `Upstream -eq 'removed'` выполняется `Remove-Item` (`:427`). Наши файлы совпадают с базой v2.6.4 (`Ours = base 2/2`), поэтому никакой `Note` их не защитит, и файлы будут удалены. Мы потеряем английские картинки CPDD (2 949 блоков) до готовности п. 8 ROADMAP (русские картинки).
- Нужен предохранитель в `SyncCpdd.ps1` (план, шаг 3).

## 5. Что сделает `-Components state,shards -Apply`
По коду `SyncCpdd.ps1:417–535`:
- `state` → перегенерированный `patch_payload/Saved/Mods/translation-overrides.state.json` (RU-id).
- `shards` → новый `source/translation_batches/batch_050_cpdd_275.json` с ожидаемыми 26 записями и пустым `target_ru` (id после текущего максимума), затем `ShardCompiler.exe`. Пустые `target_ru` допустимы, прецедент — `batch_048_cpdd_271_debug.json`.
- `runtime` и `bakedtext` не входят в `Components` и уходят в pending (`Add-Pending`, `:423`, `:453`). Их базы остаются v2.6.4, файлы не трогаются, компаньон `Init.lua.compat.luac` не копируется.
- `BASE.json`: `tag` → v2.7.5, `component_bases` = `bakedtext` и `Init.lua` (и, возможно, ключ компаньона) на v2.6.4. `vendor/cpdd/v2.7.5/` создаётся (`release.json`, runtime `.lua`, state). `vendor/cpdd/v2.7.1/` удаляется как неиспользуемый (`:533`). Это нормально: исходник v2.7.1 остаётся в `reference/cpdd/v2.7.1/unpacked/`.
- Код выхода 2 (`:538`): в отчёте по-прежнему висят конфликты merge3 `Init.lua`. Это ожидаемо, а не ошибка применения. Пример: в TASK-034 был код 255 при «Not applied: BakedText, Init.lua».

## 6. Нужен ли релиз
Нет. Игрок не увидит ни одного изменения: state — метаданные, а 26 строк в текущей игре не встречаются (п. 1.4). Достаточно коммита, обновление уйдёт в следующий релиз вместе с другими задачами.

## План для чата 2 (исполнение)

1. **Предусловие.** `git status` чистый. `tools/SyncCpdd.ps1 -Tag v2.7.5 -SkipDownload` (dry-run) → в отчёте `Added 141 (not in our batches: 26)`. Если число не 26, остановиться и сообщить.
2. **Применить:** `tools/SyncCpdd.ps1 -Tag v2.7.5 -SkipDownload -Components state,shards -Apply`. Код 2 ожидаем (п. 5). Проверить:
   - `git status`: изменены только `patch_payload/Saved/Mods/translation-overrides.state.json`, `vendor/cpdd/BASE.json`, `vendor/cpdd/v2.7.5/*` (новые), `vendor/cpdd/v2.7.1/*` (удалены), `source/translation_batches/batch_050_cpdd_275.json` (новый), а также сгенерированные шарды и пакеты, если `ShardCompiler` их переписал;
   - **не** изменены `patch_payload/Saved/Mods/BakedText/*`, `patch_payload/.../cpdd_runtime_fixes/Init.lua`, `vendor/cpdd/companions.json`;
   - в `batch_050_cpdd_275.json` 26 записей: 24 `终末猎杀草丛;草丛组NN` и 2 `联赛新赛季前两轮…` с фразой `黄金战略服仅会在最高强度等级的战略服中产生`;
   - `BASE.json`: `tag` v2.7.5, `component_bases` содержит `bakedtext` и `Init.lua` → v2.6.4.
3. **Предохранитель в `tools/SyncCpdd.ps1`** (короткая правка):
   - добавить `[switch]$AllowRemoval` в `param` (`:10–17`) и в шапку-справку (`:3–8`);
   - в `:427`: если `$r.Upstream -eq 'removed'` и не задан `-AllowRemoval`, вызвать `Add-Pending $r` и `Write-Warning "Kept $($r.Rel): removed upstream; pass -AllowRemoval to delete"` вместо `Remove-Item`;
   - проверка (после коммита шага 2): `SyncCpdd -Tag v2.7.5 -SkipDownload -Components bakedtext -Apply` → выведено предупреждение `Kept … BakedText/blocks.bin` и `manifest.json`, `git status -- patch_payload/Saved/Mods/BakedText` пуст. Побочные изменения этого прогона (`vendor/cpdd/BASE.json`, `vendor/cpdd/*`) откатить через `git checkout -- vendor/cpdd` и `git clean -n vendor/cpdd` (сначала посмотреть список, потом `-f`).
4. **Документы:**
   - `docs/LESSONS.md`, новый урок: «`Init.lua` — форк CPDD v2.6.4. merge3 с upstream v2.7.x бессмыслен (один конфликт на весь файл). Новые фичи upstream сравнивать диффом upstream→upstream (`git diff --no-index vendor/cpdd/<old>/Init.lua reference/cpdd/<new>/…/Init.lua`) и переносить вручную строкой в таблицы спеков. `SyncCpdd -Apply` без `-Components` раньше удалял `BakedText` (upstream убрал его в 2.7.0), теперь удаление только с `-AllowRemoval`»;
   - `docs/PROJECT_MAP.md`: в строке `SyncCpdd.ps1` упомянуть `-AllowRemoval`;
   - в этом файле заполнить раздел «Результат» (коммит, вывод `SyncCpdd`, число записей).
5. **Проверки:** `tools/VerifyPatch.ps1` (без ошибок, `Init.lua` по-прежнему 182/190, компаньоны совпадают), `tools/VerifyBatch.ps1` для `batch_050_cpdd_275.json`, `tools/LuaDataCheck.exe` (0 расхождений, если `ShardCompiler` перегенерировал шарды).
6. **Коммит:** `chore(cpdd): TASK-042 sync v2.7.5 state+shards (runtime/bakedtext kept), SyncCpdd -AllowRemoval`. `push origin main`. Релиз **не** собирать.
7. **Перевод 26 строк** не делать в этом чате. Это необязательная мини-пачка для чата `/translate-pack` (п. «Промпт для перевода» ниже), приоритет низкий: в текущей игре эти строки не видны.

**Не делать:** не применять `runtime`, не копировать `Init.lua.compat.luac`, не переносить блоки upstream (`restoreMethod` и др.) в `Init.lua`, не трогать `BakedText`, не запускать игру и установщик.

## 7. Чек-лист для пользователя (следующая dev-сессия, `absoluteru_dev.lua`)
Эти пункты определяют, понадобится ли когда-нибудь точечный хук из upstream (п. 1.2, строка «нет»):
1. Сюжетная катсцена с репликами (`Sequence_Panel`/`NPCCSDialog`): реплики и имена говорящих на русском. В `hooks.csv` должны появиться `data:Sequence_Panel.ShowDialoguePanel` ACTIVE или `nested:Sequence_Panel/NPCCSDialog:Refresh`, а в `untranslated.md` — ни одной строки с этими панелями.
2. Журнал реплик в диалоге (кнопка «история»/review, `ReviewListItem`): текст и имена на русском.
3. Варианты ответа NPC (`DialogueOptionItem`, `Text_Item`) на русском.
4. Подсказка предмета с описанием (`ItemTips_Item`): название и описание на русском.
5. Экран загрузки: название локации (`Text_MapName`) и подсказка (`RTB_Tips`) на русском.

Если где-то в `untranslated.md` будет `vis=True` с такой панелью, это повод для нового TASK с точечным хуком в стиле наших спеков. Отдельно, вне этой задачи: `HUD_Panel/Text_Object_lua` = `魔术师牌` («перевод есть, не применился») — кандидат на отдельный разбор.

## Промпт для чата исполнения
> Выполни `docs/tasks/TASK-042-cpdd-275-runtime.md` по разделу «План для чата 2». Коротко: CPDD v2.7.5 применяем только компонентами `state,shards` (`tools/SyncCpdd.ps1 -Tag v2.7.5 -SkipDownload -Components state,shards -Apply`, материалы уже лежат в `reference/cpdd/v2.7.5/`). Рантайм `Init.lua` и `BakedText` не трогать. Добавь в `SyncCpdd.ps1` предохранитель `-AllowRemoval` (без него файлы, удалённые upstream, не удаляются), обнови `docs/LESSONS.md`, `docs/PROJECT_MAP.md` и раздел «Результат» в TASK-042. Прогони `VerifyPatch.ps1`, `VerifyBatch.ps1`, `LuaDataCheck.exe`, закоммить и запушь в main. Релиз не собирать, 26 новых строк не переводить (это отдельный чат). Папку игры только читать, игру и установщик не запускать.

## Промпт для перевода (необязательно, низкий приоритет)
> `/translate-pack` для `source/translation_batches/batch_050_cpdd_275.json` (26 строк с пустым `target_ru`). 24 технические строки `终末猎杀草丛;草丛组NN` переводить единообразно по шаблону, номер сохранять. 2 длинных текста правил 四方联赛 отличаются от уже переведённых ключей batch_049 (2 050 и 580 символов) только вставкой `，黄金战略服仅会在最高强度等级的战略服中产生` после `…可获得的奖励越丰厚`. Взять `target_ru` соответствующей записи batch_049 и добавить перевод этой фразы по глоссарию (`docs/GLOSSARY.md`: 战略服, 黄金). Теги сохранить.

## Результат
Чат 2, 09.11.2026.
- **Dry-run** `SyncCpdd -Tag v2.7.5 -SkipDownload`: `Added 141 (not in our batches: 26), changed EN 23, removed 0`, конфликтов merge3 в `Init.lua` 14, код 2.
- **Apply** `-Components state,shards`, код 2 (ожидаемо): коммит `7b736597`. Изменены `translation-overrides.state.json`, 26 шардов `RuntimeTextGemini_*.lua`, `vendor/cpdd/BASE.json` (`tag` v2.7.5, `bakedtext` и `Init.lua` остались на v2.6.4), добавлен `vendor/cpdd/v2.7.5/`, удалён `vendor/cpdd/v2.7.1/`. `Init.lua`, `BakedText/*`, `companions.json` не тронуты.
- `batch_050_cpdd_275.json`: 26 записей, 24 `终末猎杀草丛;草丛组NN` и 2 с `黄金战略服仅会在最高强度等级的战略服中产生`, `target_ru` пустые.
- **Предохранитель** `-AllowRemoval` в `tools/SyncCpdd.ps1`. Проверка `-Components bakedtext -Apply`: выведено `Kept Saved/Mods/BakedText/blocks.bin` и `Kept …/manifest.json`, `git status` по `BakedText` и `vendor/cpdd` пуст.
- **Проверки:** `VerifyPatch` OK (`Init.lua` 182/190, компаньоны 265 шт. совпадают; WARN о билде StringDB 2295021 против `supported_game.json` был и раньше), `VerifyBatch -Batch 50` 26/0 ошибок, `LuaDataCheck` 0 расхождений.
- Документы: урок в `docs/LESSONS.md`, `-AllowRemoval` в `docs/PROJECT_MAP.md`. Релиз не собирался, 26 строк не переведены (отдельный чат `/translate-pack`).
