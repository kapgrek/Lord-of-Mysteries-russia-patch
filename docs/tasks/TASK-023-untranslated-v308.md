# TASK-023: Китайский и английский после v3.0.8, «английские» переводы в батчах

## Симптом
v3.0.8-RU, сессия `20260928-150247` (слот s5, 15:02–16:31). Пользователь видит в игре несколько китайских фраз.

## Данные
- Логи: `reference/logs/2026-09-28_1818/` (`CollectDiagLogs.ps1`, одна сессия), отчёты в `report/` (`untranslated.csv`, `untranslated.md`).
- `StringDbGaps -Report -Logs reference\logs\2026-09-28_1818 -Sid 20260928-150247` → `temp/t023/stringdb_gaps.csv`.
- Одноразовые файлы: `temp/t023/emit_list.txt` (список ниже, раздел 1.1), `temp/t023/english_target_ru.csv` (раздел 2). Если `temp/` очищен, их можно пересоздать: список лежит в этом файле, правило поиска — в разделе 2.

## 1. Разбор непереведённого (sid 150247)

| src | всего | ложные | перевода нет | перевод есть, не доходит |
|---|---:|---:|---:|---:|
| widget, CJK | 78 | ники: Автошахматы 14 (`AutoChess_Hud_Panel/Text_Name`, count до 1024), выбор роли 5, `WBP_HUDGroup` 1, гильдия (`猫咪之家`, `开摆`, `月代雪`, эмблема `咪`), титул `铁锅炖`, фильтр объектов `花园宝宝`; заглушки скрытых виджетов (`占位文本…`, `一二三四…`, `装备名称七个字`, `秘偶名字`, `玩家名字七个字`); ники в бегущей строке `WBP_Marquee_Announcement` (`[野鸭]`, `[布罗迪·布彻]` — шаблон переведён) | 13 (1.1) | 1 (`欢迎您回到俱乐部！`, 3.1) |
| widget, EN | — | — | — | 2 (`Aesthetic`, `Home Coin`, 3.2) |
| data, CJK | 214 | пузыри чата Gossip 147, `SECRET_PARTNER_FOLLOW` с никами 3 («Следует за 清湫丷»), служебные `GetSkillDataNewRow.Desc` `【自走棋】…` 20 | ≈45 KSBC (1.2) + 5 `StringDB_CN_Data.RawText` (1.1) | — |
| stringdb | 750 | `service` 486, `technical` 231, `clipped` 6 (base64-блоб) | 27 `achievement` без `cn`, только EN (1.3) | 0 |

На экране (`on_screen`) из StringDB — 0 строк.

### 1.1 Видно на экране, CJK → `-EmitList` (18 строк, `temp/t023/emit_list.txt`)
Формат: строка на строку, `\n` — литерал.
```
全境雍容，华冠加冕！全新神眷时装登场
<InvHighlight>男款</><InvDefault>采用</><InvHighlight>黑色立领礼服</><InvDefault>，银灰纹样由领口延伸至前胸。</>
<InvHighlight>珠链</><InvDefault>与</><InvHighlight>银色细链</><InvDefault>垂向腰际，勾勒腰线，红色宝石点缀其间。</>
<InvDefault>红色宝石与层叠</><InvHighlight>银色链饰</><InvDefault>点亮深色衣身。金属护臂与肩甲呼应，勾勒硬朗轮廓。</>
<InvDefault>【专属动态头像】</>
<InvDefault>时装【全境雍容】</>
<InvHighlight>女款</><InvDefault>以</><InvHighlight>红色束身礼裙</><InvDefault>为主，暗纹铺陈，白色领口褶边衔接胸前镂空纹饰。</>
愚者棋局平衡调整公告
<InvHighlight>9月29日（星期二）</>
<InvDefault>获取时装后，各位非凡者还将同步解锁</><InvHighlight>专属动态头像</><InvDefault>、</><InvHighlight>花式待机</><InvDefault>以及</><InvHighlight>结算动画</><InvDefault>。</>
<InvDefault>全新时装</><InvHighlight>【全境雍容】</><InvDefault>将上新灵界焕容，也可使用</><InvHighlight>2张神眷牌</><InvDefault>兑换。</>
同一局中，同时上阵克莱恩和阿兹克。
迟到十分钟
快来看看这个魔术师的表演！
为我鼓掌吧！
继续!
谢、谢谢你，女士！
哇！
```
- 11 строк — объявление `Announce_Panel` (обновление 29.09: наряд 全境雍容, баланс «Гамбита Шута»). Это текст сервера: ключ живёт, пока висит объявление. Переводим, потому что строки дешёвые и видны при входе. Канон: 全境雍容 = «Царственное изящество» (`batch_035`), 愚者棋局 = «Гамбит Шута», 神眷牌 — как в `batch_035/036`.
- 2 строки — всплывающее достижение (`WBP_ReminderAchievementTips_Widget` Text1/Text2).
- 5 строк — реплики NPC из `StringDB_CN_Data.RawText` (данные, `-EmitData` их не берёт).

### 1.2 Данные KSBC → `-EmitData` (≈45 строк)
Поля: `SkillDisc` 17, `BriefDescription` 6, `Name` 2 (`欲念七重奏`, `傀儡提线`), `BuffName` 5 + `BuffName1` 1 (`厄运锋芒`, `重伤灼烧`, `魔女教派2人破防`, `疾猎攻速`…), `funcRep` 4, `Brief2` 3 (`EquipmentSpiritualityConvergenceData`: «提高穿刺185，释放人脉技能、秘偶技能时…», видна в `WBP_Lib_Equipment_Spiritual/Text_Detail`), `WordDesc` 1 (`EquipmentMythData`). Поле `Desc` не брать: там служебные описания `【自走棋】…`.
- В батчах уже есть **старые редакции**: `batch_036:2578` «…释放位移技能时…» (в игре теперь «释放人脉技能、秘偶技能时»), `batch_005:27190` `苍白余韵发型 … 360万` (в игре `funcRep` «…Прическу «Бледное послесвечение»…\n若已拥有此外观，则可选择分解获得300万绑定苏勒»: первая строка переведена по частям, вторая — нет). `-EmitData` берёт текст из лога как есть. Для `funcRep` со смешанным текстом ключ будет смешанным, и перевести его как строку нельзя. Эту строку пропустить: полный китайский оригинал в логах не записан.

### 1.3 StringDB `achievement` без `cn` (27 строк, P2)
Английские названия и условия достижений (`Strengthening Beginner`, `The Fool's Shelter`, `Favor of the Bishop of Horror`, «Obtain 1 Extraordinary Material with a {愚者} affix»…). В этой сессии на экране их не было, они видны в панели достижений. `-Emit … -Category ui,mail,text`. Если `-Emit` не пишет строки с пустым `cn`, выгружать через `-EmitList` с `source_cn` = английский текст (как `batch_032_stringdb_ui`, TASK-022).

## 2. «Английские» переводы в батчах (341 строка) — главная находка
Бегущая строка на экране: «<ник> condensed a [Мутировавший материал] carrying the <Подстрекатель> affix during a **Потусторонний** Convergence, receiving the favor of the King of Yellow and Black who wields good luck». Причина — не рантайм, а батч: `batch_012.json:11232` — `target_ru` равен `ref_en`, в котором замена канона TASK-022 заменила `Beyonder` на «Потусторонний». Машинный перевод когда-то вернул английский, и строка считается переведённой.

Правило поиска (скрипт в этом чате, PowerShell + `JavaScriptSerializer`): в `target_ru` без тегов `<…>` и `{{…}}` не меньше 6 латинских слов из 3+ букв, и латинских слов больше, чем 2× кириллических. Отсечены отладочные строки (`[UIFrame…`, `local …`, три и более `%s`). Итог — **341 строка** в `batch_005…027` (по 6–24 на батч), список: `temp/t023/english_target_ru.csv` (`batch,id,lat,cyr,cn,ru`). Примеры:
- `batch_006:025983` «When the World Calamity dies, Потустороннийs who participated…»
- `batch_006:027367` «Insufficient "Потусторонний Material" quantity, cannot aggregate with one tap»
- `batch_007:034013` «The Последовательность name "Зритель" might lead people…»
- `batch_006:028575` «The final resting place for "Охотникs"…»

Часть строк служебная (`[Марионетка Skill] … Agent Main Skill`), их тоже переводим: это дёшево, а разделять вручную дороже.

`VerifyBatch.ps1` такие строки не ловит. Нужна проверка, чтобы новые «английские» строки не появлялись (И2).

## 3. Перевод есть, но не доходит (код)

### 3.1 `欢迎您回到俱乐部！` в `P_NPCTalk/RTB_TalkContent` (`vis=True`, 15:07:10 и 15:12:09)
- Ключ есть: `batch_012.json:2830` → «Добро пожаловать обратно в Клуб!».
- `session.json → probes.text_skip`: `reason=talkcontent`. Проход по панели намеренно не переписывает виджеты `*talkcontent*` (`Init.lua:4749-4750`). NPC-текст переводится только через аргументы `NPCTalkTextComp` (`LateLabelClasses.NPCTalkTextComp = { args = true }`, `Init.lua:11810`; `lateLabelArgs`, `Init.lua:11848-11859`).
- `hooks.json`: `late-class:NPCTalkTextComp.ShowContent` 2 вызова, `NO_EFFECT`; `Refresh` — `NEVER_CALLED`. `text_changes` считает только запись в виджет, замену аргумента он не видит. Значит, по логам **нельзя установить**, что пришло в `ShowContent`: строка (тогда `lateLabelArgs` должен был её перевести) или ID/таблица (тогда текст берётся внутри из данных и args-хук бесполезен).
- Нужна проба R1 (план) и проверка пользователем: была ли реплика «欢迎您回到俱乐部！» на экране по-китайски. Если она выводилась по-русски, это ложная запись: обход увидел текст до печати.

### 3.2 `Aesthetic`, `Home Coin` в `HomePage_Panel` (`WBP_ManorMessagesPage/WBP_ContentPaper/Text_Title_4/6`)
Ключи есть (`batch_034_stringdb_s5` → «Эстетика», «Монеты дома»). В `text_skip` этих строк нет, в данных тоже нет, их видит только обход (`scope=panel:HomePage_Panel:walk`). Это тот же класс, что `Plot Overview` в TASK-022 а2. Проба R0 из TASK-022 пишет только ветки с `noteSkip`, поэтому причина здесь неизвестна. Не править до новых данных. Кандидат в R1: расширить пробу.

## План

### Порядок пачек (чат перевода, `/translate-pack`)
1. **Пачка 1** — новый батч `batch_038_s5_t023.json`: `-EmitList temp\t023\emit_list.txt` (18), затем `-EmitData … -Fields SkillDisc,BriefDescription,Name,BuffName,BuffName1,funcRep,Brief2,WordDesc` (≈45, смешанный `funcRep` удалить из батча до перевода), затем `-Emit … -Category ui,mail,text` (27). Всего ≈90 строк, 2–3 чанка.
2. **Пачка 2** — 341 «английская» строка. Сначала в чате исполнения выполняется И1, потом перевод в чате `/translate-pack` по `batch_039_retranslate_en.json`.

### И1. Подготовка перевыгрузки «английских» строк (чат исполнения)
- Скрипт в `temp/t023/` по правилу раздела 2 переносит 341 строку из исходных батчей в новый `source/translation_batches/batch_039_retranslate_en.json` с **теми же** `id`, `source_cn`, `ref_en` и пустым `target_ru`, а из исходных батчей эти записи удаляет. До переноса нужно проверить, как `ShardCompiler` относится к дублям ключа и `id` (дублей быть не должно), и что пустой `target_ru` не ломает сборку. До перевода эти строки в игре будут китайскими, а не английскими. Релиз выпускать только после пачки 2.
- `ShardCompiler.exe` + `VerifyBatch.ps1` по затронутым батчам — 0 ERR.

### И2. Проверка «английского перевода» в `VerifyBatch.ps1`
- Предупреждение `WARN en_target` по правилу раздела 2: не меньше 6 латинских слов, латинских больше 2× кириллических, без отладочных строк `[UIFrame`/`local`. После И1 и пачки 2 по всем батчам должно быть 0 срабатываний, кроме отладочных.

### R1. Проба NPC-реплик (только при `runtimeFixes.Diag`, AGENTS §4)
- В обёртке `lateLabelArgs` для `NPCTalkTextComp.ShowContent` при Diag записывать в `session.json → probes.npc_args` типы аргументов и (для строк) первые 80 байт до и после замены, уникально, до 50 записей. Одна строка в C7.log на первое срабатывание. В обычном режиме — ничего.
- Решение о правке — в следующем аналитическом чате по данным пробы.

### Документы и релиз
- `docs/DIAGNOSTICS.md`: `probes.npc_args`; `docs/PROJECT_MAP.md`: `batch_038`, `batch_039`, `WARN en_target`.
- Релиз v3.0.9-RU — после пачек 1 и 2 (`tools/PackageRelease.ps1 -Publish`).

## Исполнение (2026-09-28)
- **Правило уточнено до точного воспроизведения 341 строки:** латинское слово — `\b[A-Za-z]{3,}\b` (с границами слова, поэтому `Sports_Meet_…` считается одним словом), кириллическое — любая длина (`\p{IsCyrillic}+`); `\n` и разметка вырезаются перед подсчётом.
- **ShardCompiler:** ключ шарда — `source_cn` (поле `id` не используется); при дублях `source_cn` побеждает последний батч по имени файла. Пустой `target_ru` сборку не ломает, но CN-ключ получает значение **`ref_en`**, а EN-алиас не пишется. Значит, до пачки 2 эти 340 строк в игре будут английскими (по `ref_en`, без канонических вставок), а не китайскими.
- **Дубли:** у 341 строки нет совпадений `source_cn` в других батчах, кроме пары внутри самого списка (`batch_022:107878` = `batch_025:122288`). В batch_039 перенесена одна запись, `122288` удалена. Итог: **340 строк** в `batch_039_retranslate_en.json`. Скрипты: `temp/t023/find_en.ps1`, `temp/t023/move_en.ps1` (перенос текстовый, с проверкой round-trip формата каждого батча).
- **И2:** `VerifyBatch.ps1` проверка 10 — `WARN en_target`. До переноса она нашла ровно те же 341 строку, после — 0; ERR 0.
- **R1:** `D.NoteNpcArgs` (`AbsruDiagnostics.lua`) и вызов в обёртке late-class с `args = true` (`Init.lua`, `installLateLabelClassHooks`). Мок на Lua 5.4 (`temp/t023/npcargs_test.lua`) — всё ок, VerifyPatch — ок.

## Проверка (аналитический чат, 2026-09-28)
Коммиты `e075bb45` (И1, И2, R1), `e98f7763` (пачка 1), `5acf4acc` (пачка 2). Релиз v3.0.9 ещё не собран.
- `batch_038_s5_t023.json`: 75 строк, пустых нет. Строки 1.1, 1.2 и 1.3 на месте (объявление, достижение, 欲念七重奏, 傀儡提线, 厄运锋芒, `Brief2`, `Strengthening Beginner`…). Китайский в `target_ru` — только плейсхолдер `{愚者}` (верно). 48 `WARN` «ref_en is empty» — ожидаемо для `-EmitList`/`-EmitData`.
- `batch_039_retranslate_en.json`: 340 строк, пустых нет. Английский остался в 2 строках, и это верно: перечень енумов `LightHit,HitBack…` (единственный `WARN en_target` по всем батчам, ложный) и формула `CheckStar(...)`.
- `VerifyBatch` по всем батчам: 140 023 строки, 0 ERR. R1: вызов в `pcall`, только при `runtimeFixes.Diag`, лимит 50 записей, строка в C7.log одна.
- Бегущая строка в шарде (`RuntimeTextGemini_39f.lua:260`) теперь русская: «…в ходе Потустороннего слияния…». Внутреннее имя механики — `EquipmentSpiritualityConvergence`; единого русского термина в `docs/GLOSSARY.md` нет. Расхождение мелкое, отдельно не правится.

### Остаток: правило раздела 2 не поймало короткие строки (И3, пачка 3)
- **169 строк** с китайским `source_cn`, у которых в `target_ru` 3–5 латинских слов и латинских больше 2× кириллических. Примеры: `batch_006:025014` «Ms. “Фокусник”, to you, what kind of existence is Mr. “Fool”?», `batch_006:025367` «Grade 0 Запечатанный артефакт... what do I need to pay attention to?», `batch_006:026740` «An astonishing ability—is this Потусторонний power?». Часть строк служебная (`模版精英-男树人` «Шаблон Elite-Male Tree Man», отладка `[ShadowChess]…`, `invId slotIndex…`): отладочные с `[Класс]`/именами полей не переносить. Список: `temp/t023/short_en.csv`.
- **10 строк** с английским множественным числом от русского слова (`[А-Яа-яЁё]s\b`): «Потустороннийs», «Марионеткаs», «Последовательностьs». Часть из них русская, кроме этого слова (`batch_016:075855`, `batch_017:080346`, `batch_017:081374`). Эти строки тоже перевести заново. Список: `temp/t023/cyr_s.csv`.
- Причина та же, что в разделе 2: машинный перевод вернул английский, а замена канона вставила в него русские термины.

### И3 (чат исполнения)
- Правило `WARN en_target` в `VerifyBatch.ps1` расширить: (а) при китайском `source_cn` порог 3 латинских слова вместо 6; (б) отдельный `WARN en_plural` на `[А-Яа-яЁё]s\b`. Отладочные строки (`^\[`, имена полей в camelCase, `%s`) исключить, как сейчас.
- Выбрать строки по новому правилу (≈170, без служебных) и перенести их `temp/t023/move_en.ps1` в `batch_040_retranslate_en2.json`, как в И1 (дубли `source_cn`, round-trip). До перевода строки будут показывать `ref_en`.
- `ShardCompiler` + `VerifyBatch`: 0 ERR. Коммит и push.

### И3 — исполнение (2026-09-28)
- **VerifyBatch, проверка 10:** порог `en_target` — 3 латинских слова при китайском `source_cn` (CJK), иначе 6. Отладочные строки определяются по `source_cn` (разметка вырезана): префикс `[Латиница]`, `LuaList(`, слово в camelCase (`invId`, `synExcelData`, `notificationTitle`); по `target_ru` — `[UIFrame`/`local`, как раньше; ≥ 3 `%s`. Префикс `[…]` проверяется только в `source_cn`: в `target_ru` он есть у настоящих строк (`[Roguelike]`, `[Collection]`, `[General]`, `[Position]` из `【…】`). Новый `WARN en_plural` — `[А-Яа-яЁё]s\b` (в скрипте записан `\u`-кодами: файл без BOM).
- **Отбор:** из 169 строк `short_en.csv` правило отсекло ровно 8 отладочных (`invId…`, `[ShadowChess]`, `[BagSynthesis_Panel]`, 3× `LuaList(`, `InputBase:UnBindInput`, JSON `notificationTitle`). Не перенесены и остаются известными ложными `WARN en_target`: `batch_035_stringdb_s5_ui:133450` «Duet Night Abyss» (название игры 異環) и `batch_039:097422` (енумы `LightHit…`). `en_plural` — те же 10 строк, что в `cyr_s.csv`, 3 из них пересекаются с `short_en`.
- **Перенос:** 167 строк из `batch_005`…`batch_026` в `batch_040_retranslate_en2.json` (пустой `target_ru`). Дублей `source_cn` в других батчах нет, round-trip всех 22 батчей совпал. Скрипты: `temp/t023/find_en2.ps1` (список `move_i3.csv` из вывода VerifyBatch `warn_i3.txt`), `temp/t023/move_en2.ps1`.
- `ShardCompiler` — 1024 шарда; `VerifyBatch` по всем батчам: 140 023 строки, 0 ERR, `en_target` — 2 (ложные, см. выше), `en_plural` — 0. До пачки 3 эти строки показывают `ref_en`.

## Чек-лист для пользователя (после v3.0.9)
1. Экран входа → объявление «Царственное изящество…» и «Баланс Гамбита Шута» по-русски.
2. Бегущая строка о конвергенции: «… во время Потусторонней конвергенции …» по-русски целиком (ник остаётся как есть).
3. Снаряжение → духовная конвергенция (`WBP_Lib_Equipment_Spiritual`): «Повышает Пробивание на 185…» без китайского.
4. Автошахматы: описания навыков 欲念七重奏 / 傀儡提线 и баффы по-русски.
5. Клуб (NPC у входа): реплика «Добро пожаловать обратно в Клуб!» — по-русски или по-китайски? Сообщить результат. При `absoluteru_dev.lua` искать в `absru-s*-session.json` → `probes.npc_args`.
6. Прочитать 2–3 ранее английских описания (например, «Недостаточно „Потустороннего материала“…»).

## Промпты

### Чат исполнения
```
Чат исполнения (AGENTS.md §3). Выполни план docs/tasks/TASK-023-untranslated-v308.md: И1, И2, R1, «Документы». Перевод не делать — пачки 1 и 2 идут отдельными чатами /translate-pack.
Правило «английских» target_ru и список — в разделе 2 TASK (temp/t023/english_target_ru.csv; если temp очищен — пересоздать скриптом по правилу). Перед переносом проверить в ShardCompiler обработку дублей и пустого target_ru.
R1 — только под runtimeFixes.Diag, мок на Lua 5.4 как в LESSONS (TASK-018). Код читать точечно по ссылкам файл:строка. Коммит и push; релиз не собирать до перевода пачки 2.
```

### Чат перевода — пачка 1
```
/translate-pack
Пачка: 1 из docs/tasks/TASK-023-untranslated-v308.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_038_s5_t023.json (создать: StringDbGaps -EmitList с -ListFile temp\t023\emit_list.txt; затем -EmitData -Fields SkillDisc,BriefDescription,Name,BuffName,BuffName1,funcRep,Brief2,WordDesc; затем -Emit -Category ui,mail,text; строку funcRep со смешанным русским+китайским удалить до перевода).
Строки: логи reference/logs/2026-09-28_1818, sid 20260928-150247. Канон: 全境雍容 = «Царственное изящество», 愚者棋局 = «Гамбит Шута».
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```

### Чат перевода — пачка 2 (после И1)
```
/translate-pack
Пачка: 2 из docs/tasks/TASK-023-untranslated-v308.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_039_retranslate_en.json (уже есть после И1, target_ru пустой).
Строки: -ExportNew по батчу; переводить с source_cn, ref_en — ориентир (прежний target_ru был английским).
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог; затем VerifyBatch без WARN en_target.
```

### Чат исполнения — И3
```
Чат исполнения (AGENTS.md §3). Выполни И3 из docs/tasks/TASK-023-untranslated-v308.md (раздел «Проверка → Остаток»). Перевод не делать — пачка 3 отдельным чатом /translate-pack.
Скрипты И1: temp/t023/find_en.ps1, temp/t023/move_en.ps1; списки temp/t023/short_en.csv, cyr_s.csv (если temp очищен — пересоздать по правилу из TASK). Служебные и отладочные строки не переносить.
Коммит и push; релиз не собирать до пачки 3.
```

### Чат перевода — пачка 3 (после И3)
```
/translate-pack
Пачка: 3 из docs/tasks/TASK-023-untranslated-v308.md (раздел «Проверка → Остаток»).
Батч: source/translation_batches/batch_040_retranslate_en2.json (уже есть после И3, target_ru пустой).
Строки: -ExportNew по батчу; переводить с source_cn, ref_en — ориентир (прежний target_ru был английским). Канон: 非凡 = «Потусторонний» (склонять, не «Потустороннийs»).
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог; затем VerifyBatch без WARN en_target/en_plural (кроме 2 известных ложных: 133450 «Duet Night Abyss», 097422 LightHit…).
```
После пачки 3 — релиз v3.0.9-RU (`tools/PackageRelease.ps1 -Publish`) и чек-лист выше.
