# TASK-047: обновление 2307645 — новые строки StringDB (Автошахматы S2, «斗邪恶», костюм)

## Симптом (2026-11-13)
После обновления игры до `1.2018737.2307645` (`Saved/kscache/AssetsVersion.txt`) и установки v3.1.5-RU часть интерфейса снова на китайском. Больше всего это заметно в Автошахматах: подсказки бонусов (`WBP_AutoChess_Tips_FetterTips*`), снаряжение (`WBP_AutoChess_Tips_EquipTips`: «塔罗徽章»), настройки матча (`WBP_AutoChess_Entrance_Page`: «对局设置»). Кроме того, на китайском новый режим «斗邪恶» (карточная игра, панели `FightEvils_*`), новый костюм «蝠影与猫步» (`LoginFashionPopUp_Panel`), события (`ActivityMain_Panel`) и магазин (`Shops_Panel`).

## Подтверждение из логов
Dev-сессия `20261113-144447` (слот s2, v3.1.5-RU, флаги с `StringDbDump`). Логи скопированы в `reference/logs/2026-11-13_1542/`.
- Патч работает: `C7.log:438` `[CPDDRuntimeFix] v3.1.5-RU active hooks_installed=26`, `C7.log:445` `translation overlays applied modules=1 entries=66950`.
- Пакеты StringDB устарели: `C7.log:108` `stringdb pack stale Data.Excel.LanguageData.StringDB_CN_Data unknown=1672 shards=844`. Такие же строки есть для `_itemoutlook` (89), `_itemgift` (69), `_gossip` (71), `_manor` (92). Пакеты собраны на 2295021 (TASK-041), а для 2307645 выгрузки не было.
- Выгрузка ключей полная: `C7.log:3914` `stringdb dump done modules=38 keys=118304 … failed=0`.
- `StringDbGaps -Report -Sid 20261113-144447` (CSV: `temp/gaps_2307645.csv`, при очистке temp пересоздаётся той же командой): **4029** строк без перевода, из них на экране 235.

| категория | строк | экран |
|---|---|---|
| alias_tags | 14 | 0 |
| autochess | 73 | 14 |
| formula | 1 | 0 |
| ui | 959 | 88 |
| quest | 4 | 0 |
| mail | 62 | 4 |
| skill | 185 | 38 |
| buff | 146 | 1 |
| assistant | 32 | 0 |
| npc | 82 | 0 |
| item | 209 | 51 |
| loading | 1 | 1 |
| text | 791 | 34 |
| service / technical / clipped | 111 / 1352 / 7 | не переводить / не переводить / нужен полный текст |

По модулям (без technical/service/clipped): `StringDB_CN_Data` 1625, `_guide` 204, `_buffdata` 149, `_achievement` 106, `_manor` 91, `_itemoutlook` 89, `_gossip` 70, `_itemgift` 69, `_itemnormal` 52, `_skill3` 33, остальные меньше 25.

## Первопричина
1. **Обновление переписало исходные строки, а перевод привязан к ним байт в байт.** В Автошахматах начался сезон S2, и описания бонусов переделаны:
   - перед строкой добавлен маркер `· `: было `席位属性×<HighLight>100%</>` (`batch_028_autochess.json:3460`, перевод есть), стало `· 席位属性×<HighLight>100%</>`;
   - строки ступеней склеены через `\n` с новыми пунктами (`· 获得<HighLight>一件</>独特的装备。`, `· 商会将出现【特选·塔罗会】棋子。`);
   - к описаниям бонусов добавлен абзац «特选» (`【X】(4)：商会中【X】棋子概率变为【特选·X】…`). Поэтому в подсказке встречается смесь: первый абзац на русском (его закрыл старый перевод по частям), хвост на китайском (`untranslated.csv`, `WBP_AutoChess_Tips_FetterTips → RichText_Detailed`);
   - у бонусов изменились числа.

   Новые ключи не попадают ни в пакеты, ни в шарды, поэтому старый перевод не применяется. Ошибки рантайма нет.
2. **Новый контент**: режим «斗邪恶» (правила, лобби `FightEvils_Outside_*`, итог `FightEvils_Result_Panel`), костюм «蝠影与猫步» и предметы `_itemoutlook`/`_itemgift`, события («齐聚牌友会», «储蓄返利», «搬砖得京东卡»), магазин «战略躺赢»/«趣斗商店», бой с Росселем, достижения, справка `_guide`.
3. Автоматически вернуть по старым переводам почти ничего нельзя. Проверка «убрать `· ` и разбить по `\n`, затем найти каждую часть в батчах» (скрипт в scratchpad, на 149 043 ключах батчей) полностью закрывает только **~48 строк** (autochess 1, skill 19, text 18, ui 5 …). Частично (часть строк ступени уже есть) — ещё ~60. Значит, нужна пачка перевода. Частичные совпадения агент `ru-translator` берёт из глоссария и `names`, отдельный алиасный механизм под `· ` делать не стоит.

Что не является проблемой:
- `AutoChess_Hud_Panel → Text_Name` («高傲的豆沙包», «熊猫»…), `FightEvils_Ready_Panel → TB_MemberName`, `WBP_Marquee_Announcement`: это ники игроков и объявления сервера, их не переводим.
- `C7.log:10` `Can't load file Launch.Base.CPDDTranslation` и `StringDB_EN_Data*`: так было и раньше, загрузка идёт по `bootstrap path=` (`C7.log:11`).

## План

### Этап 1. Ключи и пакеты на 2307645 (чат исполнения)
1. `powershell -ExecutionPolicy Bypass -File tools\StringDbGaps.ps1 -ImportKeys -Logs reference\logs\2026-11-13_1542 -Sid 20261113-144447 -GameBuild 2307645`. Записать сводку по модулям: добавлено, удалено, сколько добавленных без перевода. Сохранить список новых ключей в `reference/stringdb_dump/2307645/new_keys_2295021_to_2307645.csv`, как в TASK-041.
2. `tools\ShardCompiler.exe -CheckResolved reference\stringdb_dump\2307645\resolved.json`. Ожидается 0 расхождений: в игре v3.1.5-RU, то есть текущий репозиторий. Если расхождения есть, разобрать их, как с Гроселем в TASK-041. Если код возврата 3 и пакеты не собраны, запустить обычный `ShardCompiler.exe`.
3. `tools\LuaDataCheck.exe`, `powershell -ExecutionPolicy Bypass -File tools\VerifyPatch.ps1`: без ERR, `[OK] Пакеты StringDB: 38 модулей, game_build=2307645`.
4. Коммит `source/stringdb/stringdb_keys.json` и `StringDbPack*.lua`: `chore(stringdb): TASK-047 keys for build 2307645`, push.

### Этап 2. Подготовка пачек (чат исполнения, без перевода)
1. Батч: `source/translation_batches/batch_051_update_2307645.json` (последний занятый номер — `batch_050_cpdd_275`).
2. `StringDbGaps -Aliases batch_051_update_2307645.json -Logs reference\logs\2026-11-13_1542 -Sid 20261113-144447`: 14 строк `alias_tags` (перевод есть, теги отличаются).
3. Полные тексты 7 строк `clipped` и длинных правил «斗邪恶» взять из выгрузки (`reference/stringdb_dump/2307645/`, как `emit_list_extra.txt` в TASK-041) и сохранить в `reference/stringdb_dump/2307645/emit_list_extra.txt` (UTF-8, строка на строку, `\n` литералом).
4. Строки, которые видны только в виджетах, не в StringDB. Из `reference/logs/2026-11-13_1542/report/untranslated.csv` взять строки, где `status = нет в батчах`, есть CJK, `src=widget, visible=True` или `src=data, module=WidgetText`, и которых нет среди ключей StringDB. Исключить `AutoChess_Hud_Panel|Text_Name`, `TB_MemberName`, `Text_RoleNameTitle`, `WBP_Marquee_Announcement`, `HyperLink`, ники и строки, собранные из имени и шаблона («思想已加入牌桌» — переводится шаблон из StringDB). Сейчас таких около 70, нужных из них ~25: «前往牌桌», «周限轮», «攻略者», «旧日真匣», «猫咪之家», «秘偶置换道具», навыки Росселя «帝国旗帜», сюжетный текст о Росселе. Записать их в `reference/stringdb_dump/2307645/emit_list_widgets.txt`.
5. Данные KSBC: `-EmitData` с полями `itemName,itemDes,funcRep,UseConditionDesc.1,BriefDescription,SkillDisc` (костюм «蝠影与猫步» и его описание, новые предметы, навыки). Сейчас это ~100 строк, точное число покажет `-EmitData`.
6. Обновить раздел «Порядок пачек» фактическими числами и отдать пользователю промпты. **Сам перевод в чате исполнения не делать** (AGENTS.md §3).

### Итог этапов 1–2 (2026-11-13, чат исполнения)
- `-ImportKeys`: 38 модулей, 118 304 ключа, уникальных cn 111 368 (с переводом 108 771, без перевода 2597). По сравнению с 2295021: **+2443 / −592** ключа, из добавленных без перевода **2413**: `StringDB_CN_Data` +1672 (без перевода 1650), `_buffdata` +150 (149), `_manor` +92 (91), `_itemoutlook` +89 (89), `_gossip` +71 (70), `_itemgift` +69 (69), `_buffappear` +53 (51), `_itemnormal` +52 (52), `_achievement` +48 (46), `_debug` +35 (35), `_skill3` +33 (33), `_skill` +21 (21), остальные меньше 20. Список: `reference/stringdb_dump/2307645/new_keys_2295021_to_2307645.csv`.
- `-CheckResolved`: расхождений 0. Пакеты: 38 модулей, `game_build=2307645`, ключей с переводом 115 628. LuaDataCheck: 0 расхождений. VerifyPatch: без ERR.
- VerifyPatch выдавал ложный WARN: `supported_game.json` после TASK-046 хранит `1.2018737.2307645`, а ключи — `2307645`. Теперь сравнивается последний сегмент версии.
- Коммит `1e8a4a42 chore(stringdb): TASK-047 keys for build 2307645`.
- `-Aliases`: 14 строк в `batch_051_update_2307645.json` (id 149857…149870).
- `clipped` (7): 5 строк — base64-мусор, 2 — настоящие тексты. В `emit_list_extra.txt` 3 полных текста из новых ключей: подсказка «日暮飓风» (283 и 681 символ) и правила «势力对战» (2368 символов).
- `emit_list_widgets.txt`: 12 строк, которых нет среди ключей StringDB: «周限轮», «猫咪之家», «星之虫·破阵», «前往牌桌», «完成手机端登录», «秘偶置换道具», «【补偿】S1.4版本停服维护补偿», «旧日真匣», «攻略者», «地牢», «玛蒂·古德温», «开摆». Длинные виджетные тексты (навык Росселя «帝国旗帜», сюжет о Росселе, правила «斗邪恶» в `ComTips_Panel`) в логе виджета обрезаны, а их полные версии уже есть в gaps (skill/text), поэтому их выгрузит `-Emit`. Не взяты: ники, обрывки анимации набора («翡», «柯», «略应援…», «来 我见 我征服»), строки, собранные из шаблона StringDB («继续提升需【上等兵】军衔», «消耗100点活力 (60/100)», «本期上限：30/1000», таймеры), смешанные RU+CN подсказки бонусов (их части переводятся через ключи StringDB).
- `-EmitData` (проба во временный батч, удалён): 100 строк, но 96 из них уже входят в категории gaps (item 49, ui 28, skill 16, autochess 2, text 1). `-EmitData` пропускает cn, которые уже есть в батчах, поэтому после `-Emit` он добавит ~4 строки.

### Этап 3. Перевод (отдельные чаты `/translate-pack`)
См. «Порядок пачек». После обеих пачек: `VerifyBatch`, `GlossaryCheck -Report` по батчу 051. Релиз — только по просьбе пользователя (`PackageRelease.ps1 -Publish`).

### Не входит
- `SyncCpdd`: если вышел релиз CPDD под 2307645, сверку делать отдельной задачей **до** этапа 3, чтобы батч CPDD не занял номер 051 (см. урок TASK-041).
- Переполнения (`overflow_top.md`: 2237) — отдельная тема.

## Порядок пачек
Объём (факт после этапа 2): 2545 строк StringDB + 3 из `emit_list_extra.txt` + 12 виджетных + ~4 из данных ≈ **2564**. В батче уже есть 14 алиасов. Лимит `/translate-pack` — 2000 строк на чат, поэтому пачек две. Первой идёт видимое и Автошахматы.

**Пачка 1 (~1147):** autochess 73, formula 1, ui 959, quest 4, mail 62, assistant 32, loading 1 (=1132), плюс `emit_list_extra.txt` (3) и `emit_list_widgets.txt` (12).
```
/translate-pack
Пачка: 1 из 2, docs/tasks/TASK-047-update-2307645-new-strings.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_051_update_2307645.json (алиасы уже добавлены этапом 2). Выгрузка:
  1) StringDbGaps -Emit batch_051_update_2307645.json -Category autochess,formula,ui,quest,mail,assistant,loading (без -OnScreen), логи reference/logs/2026-11-13_1542, sid 20261113-144447;
  2) StringDbGaps -EmitList batch_051_update_2307645.json -ListFile reference\stringdb_dump\2307645\emit_list_extra.txt;
  3) StringDbGaps -EmitList batch_051_update_2307645.json -ListFile reference\stringdb_dump\2307645\emit_list_widgets.txt.
Терминология Автошахмат — как в batch_028_autochess/batch_031 (【铁血】→【Железо и кровь】 и т. д.); маркер «· » и \n сохранять.
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```

**Пачка 2 (~1417):** skill 185, buff 146, npc 82, item 209, text 791 (=1413), плюс `-EmitData` (~4: остальное уже выгружено `-Emit`).
```
/translate-pack
Пачка: 2 из 2, docs/tasks/TASK-047-update-2307645-new-strings.md (раздел «Порядок пачек»).
Батч: source/translation_batches/batch_051_update_2307645.json (уже есть, продолжить). Выгрузка:
  1) StringDbGaps -Emit batch_051_update_2307645.json -Category skill,buff,npc,item,text, логи reference/logs/2026-11-13_1542, sid 20261113-144447;
  2) StringDbGaps -EmitData batch_051_update_2307645.json -Fields itemName,itemDes,funcRep,UseConditionDesc.1,BriefDescription,SkillDisc (те же логи и sid).
Лимит: 40 чанков за чат; код не трогать, файлы не читать — только команды скилла.
В конце — коммит и push, короткий итог.
```

## Проверка в игре (пользователь, после перевода и установки)
- В `C7.log` после входа нет строк `stringdb pack stale` (при `-ImportKeys` на 2307645).
- Автошахматы: наведение на бонус (например «Тайное искусство», «Грешный Тинген», «Таро») — подсказка полностью на русском, включая строки ступеней `· …` и абзац «Особый выбор (特选)». Подсказка снаряжения «塔罗徽章» и кнопка «对局设置» на русском.
- Режим «斗邪恶»: лобби (`前往牌桌`, `经典斗邪恶`, `【新手场】`), окно правил, итог («本周斗邪恶资产获取»).
- Всплывающее окно костюма «蝠影与猫步» и его карточка в гардеробе.
- События: «齐聚牌友会», «储蓄返利»; магазин: вкладки «战略躺赢», «趣斗商店».
- Не забыть удалить `Saved/Mods/lua/absoluteru_dev.lua` после dev-сессий: сейчас он лежит в игре со `StringDbDump = true`, и вход из-за него подвисает на ~4,5 минуты (`ms=271563`).

## Промпт для чата исполнения
> Выполни этапы 1–2 `docs/tasks/TASK-047-update-2307645-new-strings.md`: `-ImportKeys` по сессии `20261113-144447` (`reference/logs/2026-11-13_1542`, `-GameBuild 2307645`), сводка новых ключей, `-CheckResolved`, пакеты, LuaDataCheck, VerifyPatch, коммит ключей и пакетов. Затем подготовь батч `batch_051_update_2307645.json`: `-Aliases`, `emit_list_extra.txt` и `emit_list_widgets.txt` по правилам из этапа 2, оценка `-EmitData`. Обнови раздел «Порядок пачек» фактическими числами, закоммить TASK-файл. Сам не переводи: в конце выдай мне два промпта `/translate-pack`. Папку игры не трогать, игру и установщик не запускать.
