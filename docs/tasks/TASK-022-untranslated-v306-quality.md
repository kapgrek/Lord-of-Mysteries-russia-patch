# TASK-022: Остатки китайского после v3.0.6, пробы, качество перевода «Магната» и UI

## Симптом
v3.0.6-RU, сессия `20260927-133404` (слот s5). Карточки Автошахмат и «Магнат» переведены, скачков размера нет, но местами остался китайский. Пользователь нашёл ошибки перевода: 窖藏拉菲干红 → «Погребальный Лафит…» (窖藏 — «выдержанный в погребе»), 物产简介 → «Введение продукта» (нужно «Описание товара»).

## Данные
- Логи: `reference/logs/2026-09-27_1423/` (`CollectDiagLogs -Session 20260927-133404`), отчёты в `report/`. В слотах s1–s4 той же папки лежат сессии v3.0.3–v3.0.6 от 03:38–05:02; в файлах слота s5 (`untranslated-011/012`, `overflow-006/007`) есть хвосты старой сессии `20260926-190040`. Их нужно отфильтровывать по `sid`, иначе появятся ложные `Settings_Panel`/`KGTextBlock: …`.
- Сборка в игре — `build/…v3.0.6-RU.zip` (04:51). Пачка 3 (`batch_035_stringdb_s5_ui`, коммиты 13:18 и 13:26) в неё **не входит**.
- Скрипты анализа: `temp/t022/` (одноразовые), `StringDbGaps -Report` → `temp/t022/stringdb_gaps.csv`.

## 1. Разбор непереведённого

### Сводка (виджеты и данные: `untranslated.csv`, только sid 133404)
| src | всего | ложные | появится после пересборки | (а) перевод есть, не доходит | (б) перевода нет |
|---|---:|---:|---:|---:|---:|
| widget, видимые (`vis=True`) | 55 | 33: ники в Автошахматах (7, count до 1024), выбор роли (5), гильдия (`猫咪之家`, `开摆`, `月代雪`, эмблема `咪`), титулы (2), бегущая строка с ником, пиньинь (`chengyuan`, `wodezhanji`, `rucurhauyu`, `zhaohuan`, `ZHOUHUIHONGBAO`, `JULEBUSHANGDIAN`), декор (`LORD OF MYSTERIOUS`, `trading`, `area`), `ESC`, заглушка `路线名` | 5: `Extraordinary Arcana`, `Great Tarot Club` (batch_035) и 3 составные строки `ActivityMain_Panel/RichText_Desc` «Eliminate a total of 20 opponents（8/20）» и т. п. (база в batch_035) | 5 (а1, а2) | 5 CJK |
| widget, скрытые (`vis=False`) | 50 | 44 заглушки макета («占位文本…», «Placeholder Text», «一二三四…») | — | — | 6 EN: `Auto-Dismantle`, `World of Order`, `Final Hunt`, `Beckland`, `Screenshot`, `Review` |
| data | 673 | ≈620: пузыри чата Gossip 134 (55 CJK + 79 LAT), `SECRET_PARTNER_FOLLOW` с никами 6, служебные `Desc` `【自走棋】…` 14, пути, звуки, сокеты, енумы (`GoodsType ART/FOOD/WINE`, `PartType WHEEL`, `EffectType`, `ConditionType`, `DropAction*`) ≈460 | — | 1 (`WidgetText` напоминания, а1) | 25 CJK (данные KSBC 16, `WidgetText` 9), 4 EN `BuffDisc` (они же StringDB `skill`) |
| stringdb | 7363 | 767: `service` 532, `technical` 235 (+6 `clipped`, 38 `pending` — форматы `%s（%s）`, `wᴛ6.`, не переводятся) | **2380 — все из batch_035** (пачка 3) | 0 | 5020 (раздел 5) |

Регистры «ключ отличается регистром» (`ART`, `FOOD`, `WHEEL`, `area`) ложные: это енумы данных и декоративная подпись. Алиасы для них **не** добавлять (иначе перевод ключа `ART` сломает логику «Магната»). Инструмент отсеивает `Key`/`StringValue`/`*Limit*` (`tools/CollectDiagLogs.ps1:283`), но не `GoodsType`, `PartType`, `StationType`, `*EffectType`, `*ConditionType`, `*CompareOperator` (план, И3).

### (а) Перевод есть, но не доходит

**а1. Название режима в напоминании: «Вы инициировали подбор игроков 愚者棋局.»** (`WBP_ReminderMsgNormal/RTB_Content`, 13:42:02, `vis=True`; тот же текст в данных `WidgetText`/`LiveString`, scope `nested:ReminderMain_Panel/ReminderMsgNormal:Open`).
- Шаблон `你发起了%s匹配` переведён (`batch_015:071170`), аргумент `愚者棋局` есть в шардах: «Гамбит Шута» (`batch_013:060132`).
- Путь виджета содержит `remindermsgnormal`, а этот шаблон входит в `runtimeFixes.UserContentWidgetPatterns` (`Init.lua:3817-3821`). Для таких виджетов `translateTextWidget` принимает только полный перевод: если в результате остался CJK, возвращается исходный текст (`Init.lua:4739-4744`), фрагменты не переводятся. Это сделано в TASK-019 R4 из-за ников в дуэлях («<ник> оказался более опытным и выиграл дуэль у <ник>»).
- До v3.0.3 эту строку «переводила» общая замена `愚者 → Шут` («Шут棋局»), удалённая в R3. Поэтому строка и всплыла сейчас.

**а2. Подписи, которые видит только обход диагностики (`scope = panel:<uid>:walk`)** — 4 строки, ключи в шардах есть:
| Текст | Панель / путь | Ключ |
|---|---|---|
| `Plot Overview` | `TaskBoardPanel … WBP_Task_StoryBtn/Text_Name` | `RuntimeTextGemini_1d8:11` |
| `地图加载中` | `NewMap_Panel/Load` | `_22d:110` |
| `Punctuation Filter` | `NewMap_Panel … WBP_CityMapLayer/WBP_FilterBtn/Text_Name` | `_111:25` |
| `索引` | `NewMap_Panel/Text_Name` | `_16f:154` |

Что установлено по логам для `Plot Overview`:
- C7.log: 13:41:21.560 открытие `TaskBoardPanel`, 13:41:21.678 `installed late-label class hook Task_Main_Panel: OnRefresh`. Обход увидел английский текст в 13:41:23. Затем 12 отложенных проходов `TaskBoardPanel` (13:41:25–13:41:32, 1400–2877 виджетов каждый) дали `labels=0`.
- `hooks.json`: `late-class:Task_Main_Panel.OnRefresh` — 1 вызов, `NO_EFFECT`. Хук на `TaskBoardPanel` не ставился: у панели `__cname = Task_Main_Panel`, и `installLateLabelClassHooks` (`Init.lua:11803-11888`) нашёл спецификацию по нему. У класса есть только собственный `OnRefresh`, он вызвался до появления текста.
- Проход панели обходит всё дерево, включая вложенные UserWidget (`translateViewTextWidgets`, `Init.lua:5011-5063`: `view`, `_widgetCache`, `VisibleWidgetNames`, рекурсия по `userWidget`). Значит, проходы, скорее всего, **доходят** до `Text_Name`, но `translateTextWidget`/`translateVisibleText` возвращают 0. Почему — по логам не установить: `visibleTextCache` / `VisibleMiss` (`Init.lua:3000-3008`) или одна из ранних веток `translateVisibleText`. В s4 эта же строка тоже была (2 записи). Нужна проба R0 (план). Без неё правка была бы «на удачу» (AGENTS §4).
- `NewMap_Panel`: один отложенный проход (`owner:NewMap_Panel/NewMap_Panel:delayed`, calls=1, `NO_EFFECT`), причина та же — неизвестна до пробы.

**а3. Появится после пересборки (не баг).** Все 2380 «known» строк StringDB — из `batch_035_stringdb_s5_ui`. `Extraordinary Arcana`, `Great Tarot Club` и составные строки `ActivityMain_Panel/RichText_Desc` («…（3/3）») собираются из этих строк StringDB.

### (б) Перевода нет — объём
- **Видно на экране, CJK (виджеты и `WidgetText`, 10 строк; `-EmitData` их не берёт — список для `-EmitList` ниже):** талант Автошахмат `咒术回响` и его описание `获得<HighLight>1个魅欲女妖</>。其技能强化为：…`; вкладка `航海`; `选择一个任务并达成，将获得兑换装备的奖励`; `第3名`; подсказка загрузки `为强力棋子佩上非凡装备，一子可定胜负。`; новая редакция приглашения `灰雾之上，搭子入座！\n邀请新朋友，共同体验愚者棋局，可获取星币、绑定金镑、外观·发饰等丰厚奖励！` (в `batch_031:100` старая); задание истории `超过四个非凡者同时达到宗师段位。`; реплика NPC «Магната» `欢迎您，尊敬的小姐。我们随时准备装载物产发车，或者您是想保养一下车厢和引擎？` (хук `NPCTalkTextComp` работает: `ShowContent` 4 вызова; перевода просто нет); карта стратегии `如果下一站<LightHighlight>是【酒庄】</>…` (идёт и через данные).
- **Данные KSBC (`-EmitData`, ≈16):** `GetSkillDataNewRow.BriefDescription` 5 и `SkillDisc` 4 (новые фигуры: `重锤震击…`, `锁定最远敌人…`, `扑杀残血…`, `宣判最远敌人…`), `GetBuffDataNewRow.BuffName` 2 (`午夜余韵`, `魔女教派4人破防`), `GetTrainStrategyCardDataRow.CardDescText` 1, `GetTrainDifficultyDataRow.FeaturesUnlockedTextID` 2, `GetItemNewDataRow.funcRep` 1 и `itemDes` 1.
- **Английский (Blueprint, скрытые):** 6 строк выше, добавить как алиасы с `source_cn` = английский текст (как `batch_032_stringdb_ui`).
- **StringDB:** 5020 строк, раздел 5.

## 2. Шаблоны карточек Автошахмат (`probes.tips_missing`)
- В `absru-s5-session.json` этой сессии нет `tips_desc` и `tips_missing`. `hooks.json`: `fix:DescFormulaHelper.GenerateTipsDesc` — `NEVER_CALLED` (в s3 было 56 вызовов, в s4 — 54). Пользователь открывал подсказки фигур в бою (`ac-class:AutoChess_Tips_PieceTips.Refresh` 123 вызова, 21 изменение текста). Они берут готовый текст навыка из `GetSkillDataNewRow` (`SkillDisc`/`BriefDescription` с уже подставленными числами), а не шаблон `GenerateTipsDesc`. Непереведённые описания фигур этой сессии — это данные (б), а не шаблоны.
- В s4 (`20260927-045610`) `tips_desc` = 20, `tips_missing` нет: все открытые шаблоны были в шардах.
- **`StringDbGaps -EmitProbe` по этой сессии выгрузит 0 строк.** Выгрузку повторить по сессии, в которой открыта энциклопедия/описание фигур (`AutoChess_CardDescription_Panel`), — промпт «Шаблоны карточек» ниже.

## 3. Пробы настроек (TASK-019 R0.2–R0.3, TASK-021)
- В сессии 133404 настройки **не открывались**: в C7.log нет `installed late-label class hook Settings_*`, в `hooks.json` и `late.md` нет `Settings_Panel` этой сессии, `probes.settings = {}`.
- Подтверждение по сессии s4 (`20260927-045610`, тоже v3.0.6, `C7-backup-2026.09.27-02.02.32.log`):
  - `installed late-label class hook Settings_Switch_Item: Refresh,SetDefaultValue,SetSwitcher` и `… Settings_DoubleSwitch_Item: Refresh`;
  - `probes.settings[]`: 2 открытия, `refreshes` 141 и 298, `classes` заполнен (11 классов `Settings_*_Item`), проходы `Open` (`style_changes` 1) и `delayed` @119/141 мс — **`style_changes = 0`** (цель TASK-021 достигнута);
  - в `fit` s4 по `Settings_*` — 297 строк `style`, чередование размера у одного пути и текста — 1 случай.
- `fit` сессии 133404: строк `recapture` 1875 (реестр `TF.Paths` TASK-021 п. 1 работает), чередований 20↔22 нет. У 83 пар «путь + текст» размер меняется в два шага: сначала уменьшение, потом частичный возврат (`AutoChess_Shop_Rate_Widget/Text_BtnName` «Вероятность следующего уровня» 21→12,6→14, `PieceTips/Text_Sell` «Продавать» 27→16,2→20, `TalentCard_Item/Text_Refresh` «Обновить» 21→12,6→20, `Trinity_Task_Card_Item` «Отправляйтесь в» 24→14,4→16,4). Пользователь скачков не видит. Похоже, первый замер идёт до раскладки (узкий бюджет), и виджет ещё скрыт. **Не править**, только наблюдать: если пользователь заметит «прыжок» кнопки магазина Автошахмат, это кандидат на отдельную задачу.

## 4. Качество перевода
Проверка скриптом по всем батчам (135 669 строк, `source_cn` × `target_ru`):

| Правило | Строк | Примеры | Предлагаемый канон |
|---|---:|---|---|
| 窖藏 → «Погребальный», «в подвале» | 2 (+4 разнобоя названия) | `batch_021:104183` «Погребальный Лафит Сухой Красный»; «Сухой красный лафит в подвале» | 窖藏拉菲干红 → «Выдержанный красный «Лафит»» (ряд товаров: 稀·拉菲干红 «Редкий красный «Лафит»» и т. п. — по одному образцу) |
| 简介 / 介绍 → «Введение» | 77 | 物产简介 «Введение продукта» (`batch_007:032868`), «Введение в обменный магазин», заголовки справки `<Assistant_Title2>Введение:` | 物产简介 → «Описание товара»; 简介/介绍 в заголовке → «Описание», «Об …»; «Введение» только для 引言/入门 |
| 匹配 → «сватовство», «сопоставление», «подходит для» | ≈40 (без анимационного `动势匹配`) | `batch_006:027020` 匹配 «Сватовство», `对局匹配` «Сватовство», «Вы отменили сватовство %s», `已在匹配%s中` «Уже подходит для %s» | «подбор (игроков)» |
| 标点 (метка на карте) → «пунктуация» | 2 (`标点筛选`, `战术标点`) | `batch_005:022019` «Фильтр пунктуации» (виден на карте) | 标点筛选 → «Фильтр меток»; 战术标点 → «тактическая метка». Строки про поэзию (`batch_002:005899`, `batch_006:028941`) — пунктуация верно, не трогать |
| {1,2,（烙印已失效）} — разнобой и китайский | 115 | 13 вариантов: «Срок действия бренда истек» 39, «Клеймо истекло» 28, «марки», «срок годности марки»; 3 строки `batch_027` (3222, 3552, 3678) с китайским внутри макроса — видны в `EquipmentUniqueData.SuitBrief1` | «(клеймо неактивно)» во всех 115 |
| «Магнат»: 生效 → «эффективна/действительна» | 47 | «Хороший подарок · Торговая фирма эффективна» | 生效 → «срабатывает» |
| «Магнат»: ·失效 → «провалился», «вышла из строя» | 18 | «Обычный: Винодельня вышла из строя» | 失效 → «не срабатывает» |
| 熟客 → «Обычный» | 11 | «Обычный · Винодельня» | «Постоянный клиент» |
| 备货 → «Чулок», 非酒庄 → «Невинный завод» | 4 + 6 | «Чулок · Невинный завод» (`batch_013:064761`) | 备货 → «Запас»; 非酒庄 → «не Винодельня» |
| Станции в 【】: разнобой | 食铺 9 вариантов, 商行 5 | 食铺: «Магазин», «Продовольственный магазин», «Закусочная», «Лавка снеди»; 商行: «Торговый Дом», «Торговая фирма», «Торговая палата» | 食铺 «Продуктовая лавка», 商行 «Торговый дом», 酒庄 «Винодельня», 工业站 «Промышленная станция», 始发站 «Станция отправления» |

Весь корпус «Магната» — около 600 строк в 27 батчах (183 строки эффектов карт «X·станция»). Качество машинное, поэтому лучше прогнать его целиком через глоссарий, а не по одной строке. Канон в таблице — **предложение, до правки его подтверждает пользователь**.

## 5. `StringDbGaps -Report` (sid 133404)
Строк StringDB (module|row) 7363, без русского 5020, на экране 5 (все `skill`, английские `BuffDisc` «Attack Speed increased by 15%…»).

| Категория | Строк | Пачка |
|---|---:|---|
| skill | 666 | 4 |
| buff | 390 | 4 |
| assistant | 283 | 4 |
| item | 207 | 4 |
| mail | 145 | 4 |
| text | 1912 | 5 |
| npc | 606 | 5 |
| ui, quest, equip, autochess, loading, formula, alias_* | 0 | закрыты пачками 1–3 |
| known | 2343 (+37 алиасов) | batch_035, после пересборки |
| service / technical / clipped / pending | 532 / 235 / 6 / 38 | не переводить |

Пачка 4 — 1691 строка (34 чанка), пачка 5 — 2518 (51 чанк, **два чата** по лимиту 40 чанков).

## План (чат исполнения: только код и инструменты, v3.0.7-RU)

### R0. Проба «почему проход не перевёл» (только при `runtimeFixes.Diag`, AGENTS §4)
`translateTextWidget` (`Init.lua:4655-4760`) при Diag и **точном попадании** текста в шарды (`lookupGeminiText(current)` не nil и не равен тексту) пишет причину, если в итоге `translated == currentText`. Коды: `talkcontent`/`esc` (ранний выход `Init.lua:4711`), `cache` (`visibleTextCache` вернул исходник), `miss` (`VisibleMiss`), `user` (ветка `Init.lua:4739-4744`), `unchanged` (прочее). `AbsruDiagnostics.lua`: `D.NoteTextSkip(widget, text, reason)` → `session.json → probes.text_skip[]` (до 200 уникальных «путь|текст|причина», путь ≤ 512 байт); в C7.log один раз `[AbsruDiag] probe textskip n=<N>`. `CollectDiagLogs.ps1`: раздел «Пробы TASK-022» в `late.md`. Без модуля диагностики этот код не выполняется.

### R1. Термины в пользовательских виджетах (а1)
`runtimeFixes.UserContentTermFragments = { ["愚者棋局"] = true }` (расширяемый список названий режимов). В ветке пользовательского контента (`Init.lua:4739-4744`): если результат содержит CJK и строка не из одного иероглифа, заменить только **отдельно стоящие** (`runtimeFixes.isStandaloneCjkRun`) фрагменты из этого списка точным `lookupGeminiText`. Результат принимается только без CJK, иначе — исходный текст, как сейчас. Ники не затрагиваются: фрагмент не из списка остаётся как есть.
Мок: «Вы инициировали подбор игроков 愚者棋局.» → «…Гамбит Шута.»; «鲁讯 оказался более опытным и выиграл дуэль у 旋风棒棒糖.» — без изменений; «晚安» в титуле — без изменений.

### R2. `Plot Overview` / карта — после пробы R0
Не делать в этом чате. По `probes.text_skip` следующей сессии: `cache`/`miss` → сброс записи кэша, если ключ в шардах появился после (или не класть в `VisibleMiss` строки с точным попаданием); `unchanged` → разбор ветки. Если причина — «проход не дошёл» (записи нет, а обход видит), то `repairLateLabels(comp, spec)` для панелей с `LateLabelClasses` вызывать и из `panelTextRepair:Repair` при `reason == "delayed"` (`Init.lua:10821-10890`).

### И1. `GlossaryCheck.ps1 -Glossary <файл>`
Сейчас жёстко `combat_stats.json` (`tools/GlossaryCheck.ps1:69`, проверка `-Terms` на `:86`). Добавить параметр (по умолчанию `combat_stats.json`) для `-Report/-FixShort/-Export/-Import`. `-BuildDoc` (`:419`) включает все `source/glossary/*.json` со схемой `terms`. Новое поле термина `scan_markup: true`: для него `{…}`-вставки не маскируются (`$markupRegex`, `:36`). Без этого 烙印已失效 внутри `{1,2,（…）}` не проверить. Ответ `-Import` для такого термина сверяет макрос `{n,m,` по числам, текст внутри может меняться. `.claude/skills/translate-chunk/SKILL.md`: одна строка про `-Glossary`.

### И2. `StringDbGaps.ps1 -EmitList <батч> -ListFile <txt>`
Строки из UTF-8 файла (одна на строку, `\n` — литерал), `source_cn` = строка, `ref_en` пусто. Пропуск известных ключей (`Find-ShardTranslation`, `$batchKeyInfo`) и повторов — как в `-EmitData` (`:430-458`). Нужно для `WidgetText`, который `-EmitData` исключает (`:444`), и для английских алиасов Blueprint.

### И3. `CollectDiagLogs.ps1:283` — енумы данных в идентификаторы
Условие `field -match '^(Key|StringValue)$|Limit'` расширить полями `(Goods|Part|Station|Effect|Condition)Type$|CompareOperator$|DropActionEnum`. Критерий ВЕРХНИЙ_РЕГИСТР (`-cmatch '^[A-Z][A-Z0-9_]*$'`) сохранить. Итог: `ART/FOOD/WHEEL` уходят из «ключ отличается регистром».

### Документы и релиз
- `docs/DIAGNOSTICS.md`: проба R0; `docs/PROJECT_MAP.md`: `-Glossary`, `-EmitList`.
- Версия 3.0.7-RU (AppInfo, AssemblyInfo, app.manifest, Init.lua, VerifyPatch, PackageRelease, README). **Пересборка нужна и для пачки 3** (batch_035 → шарды уже в git, в zip v3.0.6 их нет).
- `ShardCompiler.exe`, `VerifyPatch.ps1`, `VerifyBatch.ps1` (0 ERR), `PackageRelease.ps1` **без** `-Publish`.

## Проверка (пользователь, v3.0.7-RU, с `absoluteru_dev.lua`)
1. Автошахматы → «Начать подбор»: напоминание «Вы инициировали подбор игроков **Гамбит Шута**.»; дуэли и ники в напоминаниях — без изменений.
2. Активности → Автошахматы: «Потустороннее чародейство», «Великий клуб Таро», задания «Устраните в сумме 20 противников（8/20）» по-русски (пачка 3).
3. Журнал заданий (`TaskBoardPanel`) и большая карта (фильтр меток, «Загрузка карты», «Индекс»): если там всё ещё английский/китайский — в `session.json → probes.text_skip` будут записи с причиной, в C7.log `[AbsruDiag] probe textskip n=`.
4. **Открыть настройки** (переключатели, двойные переключатели) — в C7.log `installed late-label class hook Settings_Switch_Item: …`, в `late.md` `Settings_Panel:delayed` с `style_changes = 0`.
5. **Открыть описание фигур в энциклопедии/магазине** (`AutoChess_CardDescription_Panel`), чтобы проба собрала `tips_missing` для промпта «Шаблоны карточек».
6. Затем `tools/CollectDiagLogs.ps1 -Session <sid>`.

## Исполнение (2026-09-27, v3.0.7-RU)
- **R0.** `Init.lua`, `translateTextWidget`: при `runtimeFixes.Diag` с `NoteTextSkip` и точном ключе (`lookupGeminiText(text)` не nil и ≠ текста) непереведённый виджет пишется с причиной `talkcontent`/`esc` (ранний выход), `cache`/`miss` (состояние `visibleTextCache`/`VisibleMiss` **до** вызова `translateVisibleText`), `user` (ветка пользовательского контента), `unchanged`. `AbsruDiagnostics.lua`: `D.NoteTextSkip` → `probes.text_skip[]` (`t`, `path` ≤ 512 байт, `text`, `reason`, `scope`), уникально по «путь|текст|причина», до 200, в C7.log один раз `[AbsruDiag] probe textskip n=1`. Константы внутри функции (локалей верхнего уровня 145/150). `CollectDiagLogs.ps1`: раздел `late.md → Пробы TASK-022` (путь без префикса `/Engine/Transient…`).
- **R1.** `runtimeFixes.UserContentTermFragments = { ["愚者棋局"] = true }` и `runtimeFixes.translateUserContentTerms`: в виджетах пользовательского контента заменяются только отдельно стоящие (`isStandaloneCjkRun`) фрагменты из списка точным `lookupGeminiText` без CJK; результат принимается, только если китайского не осталось, иначе исходный текст. Одиночный иероглиф — как раньше.
- **И1.** `GlossaryCheck.ps1 -Glossary <файл>` (имя в `source/glossary` или путь; по умолчанию `combat_stats.json`) для `-Report/-FixShort/-Export/-ExportNew/-Import`. Поле термина `scan_markup: true`: для него маскируются только теги, `{…}` просматриваются; `-Import` для строк с таким термином сверяет макросы `{n,m,` с `source_cn`. `-BuildDoc` добавляет подразделы раздела 1 для прочих `source/glossary/*.json` со схемой `terms` (сейчас таких нет — `GLOSSARY.md` не изменился). SKILL `translate-chunk` — строка про `-Glossary`.
- **И2.** `StringDbGaps.ps1 -EmitList <батч> -ListFile <txt>`: строки UTF-8, `\n` — литерал, пропуск известных (`Find-ShardTranslation`, `$batchKeyInfo`) и повторов; логи для `-EmitList` не обязательны.
- **И3.** `CollectDiagLogs.ps1:283`: поля `(Goods|Part|Station|Effect|Condition)Type$|CompareOperator$|DropActionEnum` в ВЕРХНЕМ_РЕГИСТРЕ → `identifier`.
- **Проверки.**
  - Моки `temp/t022/test_r1.lua` (копия `t019/test_r4.lua` + R1/R0) — 63/0: «Вы инициировали подбор игроков 愚者棋局.» в `WBP_ReminderMsgNormal` → «…Гамбит Шута.»; дуэль с никами, «ник + 愚者棋局», «晚安», «林» — без изменений; без Diag записей нет. `temp/t022/test_r0.lua` — 27/0: уникальность, лимит 200, путь ≤ 512, строка C7.log одна, `session.json → probes.text_skip`. Старый `t019/test_r4.lua` — 52/0.
  - `-Report -Glossary combat_stats.json` = `-Report` без параметра = до правки (md и json совпали: 1016 строк, ok 969, S 42, X 5). Временный глоссарий с `烙印已失效` + `scan_markup` находит 133 строки (ok 1, B 67, C 65), без `scan_markup` — 0. `-Import` на поддельном репозитории: `{1,2,(клеймо неактивно)}` принят, `{1,3,…}` отклонён («макрос {n,m,»).
  - `-EmitList` на поддельном репозитории со списком из TASK (+ повтор `航海`, известный `愚者棋局`): 15 новых, 1 известный, 1 повтор; `\n` стал переводом строки. `StringDbGaps -Report` по sid 133404: 7363 / 5020 / 5 — как в разделе 5.
  - `CollectDiagLogs -NoCopy` на копии логов с подставленной записью `text_skip`: раздел в `late.md` есть; `ART/FOOD/WHEEL` → `identifier` (+15 енумов «нет в батчах»).
  - `ShardCompiler` (35 батчей, 135 669 строк, шарды без изменений — batch_035 уже был в git), `VerifyPatch` OK, `VerifyBatch` 0 ERR, `PackageRelease.ps1` без `-Publish` → `build/Lord-of-Mysteries-Russian-Patch-v3.0.7-RU.zip` (68,05 МБ). В шардах zip есть строки batch_035 («Великий клуб Таро», «Потустороннее чародейство»).
- **Не сделано по плану:** R2 (ждёт `probes.text_skip` следующей сессии), перевод и правки качества (отдельные чаты). Релиз не опубликован.

## Порядок пачек перевода
0. **Чат исполнения** (код и инструменты, выше) — первым: промпт «Качество» использует `-Glossary`, пачка 4 — `-EmitList`.
1. **Пачка 4** — `batch_036_stringdb_s5_p4.json`: видимое и новые данные (10 `WidgetText` + 6 EN-алиасов через `-EmitList`, ≈16 полей KSBC через `-EmitData`) + StringDB `skill,buff,assistant,item,mail` (≈1730 строк, 35 чанков).
2. **Пачка 5** — `batch_037_stringdb_s5_p5.json`: `text,npc` (2518 строк, 51 чанк). Два чата одним промптом: второй продолжит пустые `target_ru`.
3. **Качество** — глоссарий `source/glossary/ui_traintrade.json` по таблице раздела 4 (после подтверждения канона пользователем) и правка корзин B/C через `/translate-chunk`.
4. **Шаблоны карточек** — после сессии с открытыми описаниями фигур (п. 5 проверки).

### Список для `-EmitList` (пачка 4; в чате перевода записать в `temp\t022\emit_list.txt`, UTF-8, строка на строку)
```
咒术回响
获得<HighLight>1个魅欲女妖</>。其技能强化为：连续攻击目标<HighLight>7次</>，施法期间共恢复自身<HighLight>20%最大生命值</>。
航海
选择一个任务并达成，将获得兑换装备的奖励
第3名
为强力棋子佩上非凡装备，一子可定胜负。
灰雾之上，搭子入座！\n邀请新朋友，共同体验愚者棋局，可获取星币、绑定金镑、外观·发饰等丰厚奖励！
超过四个非凡者同时达到宗师段位。
欢迎您，尊敬的小姐。我们随时准备装载物产发车，或者您是想保养一下车厢和引擎？
Auto-Dismantle
World of Order
Final Hunt
Beckland
Screenshot
Review
```

## Промпт для чата исполнения
```
Чат исполнения (AGENTS.md §3). Выполни план docs/tasks/TASK-022-untranslated-v306-quality.md, разделы «План» R0, R1, И1, И2, И3, «Документы и релиз». R2 не делать (ждёт пробы R0). Перевод не делать: пачки и правки качества — отдельные чаты /translate-pack и /translate-chunk.
Код читать точечно по ссылкам файл:строка из TASK. Моки: temp/t019/test_r4.lua (R1: «愚者棋局» в ReminderMsgNormal переводится, ники и одиночные иероглифы — нет) и temp/t019/test_r0.lua (R0: запись text_skip только при Diag и точном ключе, лимит 200, строка C7.log). Если temp/t019 очищен — создать моки заново в temp/t022.
И1 проверить на копии: -Report -Glossary combat_stats.json даёт те же корзины, что и без параметра; временный глоссарий с термином scan_markup находит {1,2,（烙印已失效）}.
Версия 3.0.7-RU, ShardCompiler, VerifyPatch, VerifyBatch (0 ERR), PackageRelease.ps1 без -Publish. В сборку должен войти batch_035 (пачка 3).
В конце: раздел «Исполнение» в TASK-022, коммит и push, чек-лист проверки для пользователя из раздела «Проверка».
```

## Промпты для чатов перевода

### Пачка 4 (после чата исполнения)
```
/translate-pack
Пачка: 4 из docs/tasks/TASK-022-untranslated-v306-quality.md (раздел «Порядок пачек перевода»).
Батч: source/translation_batches/batch_036_stringdb_s5_p4.json (создать).
Строки, по порядку:
1) -EmitList batch_036_stringdb_s5_p4.json -ListFile temp\t022\emit_list.txt — список из раздела «Список для -EmitList» TASK-022 (скопировать в файл как есть, UTF-8);
2) -EmitData batch_036_stringdb_s5_p4.json -Fields BriefDescription,SkillDisc,Name,BuffName,funcRep,itemDes,CardDescText,FeaturesUnlockedTextID;
3) -Emit batch_036_stringdb_s5_p4.json -Category skill,buff,assistant,item,mail.
Логи reference/logs/2026-09-27_1423, sid 20260927-133404.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```

### Пачка 5 (text, npc; два чата одним промптом)
```
/translate-pack
Пачка: 5 из docs/tasks/TASK-022-untranslated-v306-quality.md (раздел «Порядок пачек перевода»).
Батч: source/translation_batches/batch_037_stringdb_s5_p5.json (создать через StringDbGaps -Emit … -Category text,npc; если батч уже есть и в нём есть пустые target_ru — продолжить с шага 2 скилла).
Строки: -Category text,npc, логи reference/logs/2026-09-27_1423, sid 20260927-133404.
Лимит: 40 чанков за чат (всего ≈51 — будет два чата); код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог и сколько строк осталось.
```

### Качество (после чата исполнения и подтверждения канона пользователем)
```
/translate-chunk
Правка качества из docs/tasks/TASK-022-untranslated-v306-quality.md, раздел 4 (только эта таблица).
0) Создать source/glossary/ui_traintrade.json по схеме combat_stats.json: термины таблицы раздела 4 (cn, ru = канон, ru_match, forbidden = неверные варианты из столбца «Примеры», cn_exclude: 动势匹配 для 匹配; 诗/标点符号 для 标点; для 烙印已失效 — scan_markup: true). Канон — как подтвердил пользователь.
1) powershell -ExecutionPolicy Bypass -File tools\GlossaryCheck.ps1 -Report -Glossary ui_traintrade.json | Select-Object -Last 15 — «до».
2) -Export -Glossary ui_traintrade.json -Count 50, волны по 4 агента ru-translator, -Import -Glossary ui_traintrade.json (как в скилле).
3) После: -Report (B и C → 0), ShardCompiler, VerifyBatch по затронутым батчам (0 ERR), GlossaryCheck -Report по combat_stats (B не вырос), -BuildDoc.
Лимит 40 чанков; код не трогать, батчи не читать. Коммит: fix(translation): TASK-022 quality - TrainTrade/UI glossary, <N> strings; push; короткий итог с 10 примерами «было → стало».
```

### Шаблоны карточек (после сессии с открытыми описаниями фигур)
```
/translate-pack
Пачка: шаблоны карточек Автошахмат из docs/tasks/TASK-022-untranslated-v306-quality.md (раздел 2).
Батч: source/translation_batches/batch_034_stringdb_s5.json (уже есть; добавить через StringDbGaps -EmitProbe batch_034_stringdb_s5.json).
Строки: -EmitProbe, логи reference/logs/<папка новой сессии>, sid <sid новой сессии>. Если -EmitProbe выгрузил 0 строк — остановиться и сообщить.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```
