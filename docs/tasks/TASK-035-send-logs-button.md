# TASK-035: кнопка «Отправить логи» в установщике

## Симптом
У игроков бывают проблемы, но прислать логи автору им сложно: нужно знать, где лежит `Saved\Logs\C7.log`, какие файлы брать и кому отправлять. Нужна одна кнопка в окне установщика, которая соберёт логи и подскажет, что делать дальше.

## Решение (согласовано с пользователем 2026-10-17)
- Автоматической отправки нет: у Telegram нет ссылки, которая открывает чат с уже приложенным файлом, а отправка через бота требует вшить токен в exe. Поэтому кнопка готовит файлы и показывает игроку, что и куда отправить.
- Логи копируются в папку **рядом с exe установщика**: 3 последних лога игры.
- Адресат: личка автора **https://t.me/KapGrek**. Это не `telegram_author` (`t.me/AbsoluteGrek`, кнопка «Канал автора»).

## Зачем раздел о версии (2026-10-17)
Первый случай, ради которого нужна кнопка: игрок видит сообщение «игра устарела». Такого текста нет ни в установщике (`installer/`: там только «Игра обновилась…» и «Версия игры не поддерживается…»), ни в патче. Это ответ сервера игры на проверку версии клиента, переведённый патчем, например `batch_026.json:18178` (`当前版本老旧，请更新，服务端：%s，客户端：%s` → «Текущая версия устарела, обновите. Сервер: %s, Клиент: %s.»), `batch_002.json:9300`, `batch_003.json:3420`.
- У пользователя на той же сборке всё работает: `AssetsVersion.txt` = `1.2018737.2218968.Online_Shipping` (файл обновлён 17.10 10:01:41), последний удачный вход на сервер — 16.10 20:45 (`OnLoginServerCompleted result0`, лог `C7-backup-2026.10.16-17.47.37.log`, патч v3.1.0-RU). Сессия 17.10 10:01 до входа не дошла: через 13 с после `v3.1.0-RU active` лог обрывается на `FDebug::DumpStackTrace` без `Closing by request`, папки `Saved\Crashes` нет. Причина не выяснена.
- C7.log версию клиента почти не пишет: при входе есть только `GameLoopManagerV2:OnLoginServerCompleted … serveVersion:0.0.0`. Поэтому по одним логам причину не найти, и нужны данные о версии из `kscache`.
- Гипотезы, которые различает раздел «Версия игры» (ни одна пока не подтверждена):
  1. У игрока не скачан хотпатч, и `AssetsVersion` у него старше 2218968. Тогда нужно обновить игру в лаунчере, патч тут ни при чём.
  2. Вышел более новый хотпатч, но без `pakchunk0`. Тогда `InspectCache` его не замечает, установщик считает сборку поддерживаемой, а сервер требует новую версию.
  3. Игра у игрока не в той папке или установлена дважды: установщик проверил одну копию, а запускается другая.

## Исходные данные
- Окно: `installer/Ui/MainWindow.xaml`, код `installer/Ui/MainWindow.cs`. События подключаются по `ElementNames` (`MainWindow.cs:20`), тест разметки — `tools/InstallerCoreTests.cs:916`.
- Ссылки: `installer/links.json` → `Links.Get` (`installer/Ui/Links.cs:65`), открываются только https на `AllowedHosts`; `t.me` разрешён. Тест ссылок: `tools/InstallerCoreTests.cs:928-934`.
- Папка exe: `PayloadSource.ExeDir` (`installer/PayloadSource.cs:33`).
- Папка игры: поле `gameDir` в `MainWindow` (`MainWindow.cs:51`). Если `null`, папка не выбрана или не прошла проверку.
- Логи в игре (замер на ПК пользователя 2026-10-17): `Saved\Logs\C7.log` (~70 КБ) и `C7-backup-<дата>.log` (от 70 КБ до 1,3 МБ, около 10 штук). Пока игра запущена, `C7.log` открыт на запись, поэтому копировать его надо через `FileShare.ReadWrite | FileShare.Delete`.
- Исходники установщика перечислены в двух местах: `installer/build_installer.ps1:26` и `tools/BuildTools.ps1:21`. Новый `.cs` нужно добавить в оба списка.

## План
1. **`installer/links.json`:** добавить `"telegram_dm": "https://t.me/KapGrek"`. В `Links.cs` завести константу `TelegramDm = "telegram_dm"`.
2. **Новый `installer/LogCollector.cs`** (логика без WPF, чтобы её можно было протестировать):
   - `public const string FolderName = "AbsoluteRU_логи";` (или латиницей `AbsoluteRU_logs`, если кириллица в пути чем-то мешает; выбрать одно и описать в комментарии).
   - `public static LogCollectResult Collect(string gameDir, string outRoot, int count = 3)`:
     - источник: `Path.Combine(gameDir, "Saved", "Logs")`, маска `C7*.log`; сортировка по `LastWriteTimeUtc` по убыванию, взять первые `count`;
     - цель: `Path.Combine(outRoot, FolderName)`. Перед копированием удалить из неё только старые `*.log` и `info.txt`, а саму папку и чужие файлы не трогать;
     - копировать потоком через `new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)`, имена файлов сохранять;
     - дописать `info.txt`: версия установщика (`AppInfo.Version`), установленная версия патча (`PatcherBackend.InstalledVersion`), дата, список скопированных файлов с размерами, а также раздел **«Версия игры»** (см. «Зачем раздел о версии» ниже):
       - текст `Saved\kscache\AssetsVersion.txt`;
       - сборка, на которую рассчитан установщик (`supported_game.json`: `game_build`, `cache_launch.manifest_sha256`, если блок есть);
       - результат `PatcherBackend.InspectPak` (`PakState` и build) и `PatcherBackend.InspectCache` (`State`, `Version`, `Detail`, `PakPath`);
       - список папок `Saved\kscache\<число>` с номерами больше 100000 (хотпатчи вида `2218968`). Для каждой указать, есть ли в ней `pakchunk0-Windows.pak`, его размер и дату изменения;
       - имена и sha256 файлов `Saved\kscache\package_*.manifest`;
       - статус `PatcherBackend.InspectGameStatus` и `RunningBlocker()`.
       Сбор каждого пункта обернуть в try/catch, а ошибку записать строкой в `info.txt`: файл должен получиться, даже если часть данных недоступна. Путь к игре писать без имени пользователя Windows (префикс `Environment.GetFolderPath(UserProfile)` заменить строкой `%USERPROFILE%`); как правило, путь игры вида `D:\Games\…` его и не содержит;
     - если `outRoot` недоступен для записи (exe лежит в `Program Files`, в архиве или только для чтения), повторить в `Desktop` (`Environment.SpecialFolder.DesktopDirectory`), а в результате отметить `UsedFallback`;
     - результат: `Folder`, `Files` (список), `Error` (текст для игрока: «логи не найдены — запустите игру хотя бы раз», «нет доступа…»).
3. **`MainWindow.xaml`:** в строку заголовка «ЖУРНАЛ» (`MainWindow.xaml:152`) справа поставить кнопку `SendLogsButton` с текстом «📤 Отправить логи» (если эмодзи в Segoe UI на Win10 выглядит плохо, оставить просто «Отправить логи»), стиль `SocialButton` или обычная кнопка с `Padding="12,4"`, `FontSize="12"`. Добавить `SendLogsButton` в `ElementNames`.
4. **`MainWindow.cs` → `SendLogs()`:**
   - Если `gameDir == null`, показать `UiKit.Message`: «Сначала укажите папку игры».
   - `LogCollector.Collect(gameDir, PayloadSource.ExeDir)` выполнить в `Task.Run`, на это время отключить кнопку.
   - При ошибке записать её в журнал и показать `UiKit.Message(..., true)`.
   - При успехе вывести в журнал `Логи скопированы: <папка> (<n> файла)` и открыть диалог (через `UiKit.Confirm` или новый метод в `UiKit` с двумя кнопками) с текстом:
     «Логи сохранены в папку:\n<путь>\n\nОтправьте файлы из этой папки в личные сообщения Telegram: t.me/KapGrek. Коротко опишите проблему: что делали и что пошло не так.»
     Кнопки: **«Открыть папку и Telegram»** (основная) и **«Закрыть»**.
     Основная кнопка открывает Проводник с выделенной папкой (`explorer.exe /select,"<папка>"` или просто папку) и `Links.Open(Links.Get(Links.TelegramDm))`.
   - Кнопка доступна, даже если игра запущена (`blocker`) или версия не поддерживается: именно в таких случаях логи и нужны. Блокировать её только при `busy`.
   - ToolTip: «Копирует 3 последних лога игры в папку рядом с установщиком и подсказывает, куда их отправить».
5. **Сборка:** добавить `LogCollector.cs` в `$sources` в `installer/build_installer.ps1:26` и в список в `tools/BuildTools.ps1:21`.
6. **Тесты `tools/InstallerCoreTests.cs`:**
   - `links.json`: проверить `Links.Get(Links.TelegramDm) == "https://t.me/KapGrek"`.
   - Новый сценарий `LogCollector` на поддельной папке `temp/installer-tests/…`: создать 5 файлов `C7*.log` с разными `LastWriteTime` и `other.txt`. Проверить, что скопированы ровно 3 самых новых, `info.txt` создан, а повторный запуск не оставляет лишних `.log`. Отдельно проверить, что копируется файл, открытый на запись (`FileShare.ReadWrite` держится в тесте), и что при отсутствии `Saved\Logs` возвращается `Error` без исключения.
7. Пересобрать: `tools/BuildTools.ps1`, затем `tools/InstallerCoreTests.exe`. Все тесты должны пройти.
8. `docs/PROJECT_MAP.md`, строка «Движок и графический инсталлятор» / «Окно установщика»: упомянуть `LogCollector.cs` и `telegram_dm`.
9. Коммит `feat(installer): TASK-035 send logs button`. Релиз собирать только по просьбе пользователя.

## Проверка
- Автоматическая: `tools/InstallerCoreTests.exe` проходит без ошибок, в том числе разметку (`SendLogsButton`), `links.json` и `LogCollector`.
- Чек-лист для пользователя (собранный exe, игру не обязательно запускать):
  1. Запустить установщик, папка игры определилась. Справа от «ЖУРНАЛ» видна кнопка «Отправить логи».
  2. Нажать её. Рядом с exe появилась папка `AbsoluteRU_логи` с 3 файлами `C7*.log` (самыми свежими по дате) и `info.txt`. В журнале установщика есть строка «Логи скопированы: …».
  3. В диалоге нажать «Открыть папку и Telegram». Открылись Проводник с этой папкой и `t.me/KapGrek` в браузере или в Telegram.
  4. Повторить при запущенной игре: копирование проходит, `C7.log` не пустой.
  5. Положить exe в папку только для чтения: логи оказываются на Рабочем столе, и диалог показывает этот путь.
  6. Очистить поле папки игры и нажать кнопку: появляется сообщение «Сначала укажите папку игры».

## Промпт для чата исполнения
> Выполни план из `docs/tasks/TASK-035-send-logs-button.md`: кнопка «Отправить логи» в установщике (WPF, `installer/Ui/MainWindow.*`). Логика в новом `installer/LogCollector.cs`: копирует 3 последних `Saved\Logs\C7*.log` и `info.txt` с разделом «Версия игры» (`AssetsVersion.txt`, `InspectPak`/`InspectCache`, папки хотпатчей `kscache`, sha манифестов) в папку рядом с exe (если туда нельзя писать, то на Рабочий стол). Ссылка на ЛС `telegram_dm = https://t.me/KapGrek` берётся из `links.json`. Добавь файл в списки исходников `installer/build_installer.ps1` и `tools/BuildTools.ps1`, допиши тесты в `tools/InstallerCoreTests.cs`, собери `tools/BuildTools.ps1` и прогони `tools/InstallerCoreTests.exe`. Обнови `docs/PROJECT_MAP.md` и закоммить. Установщик и игру не запускать (AGENTS.md §1). В конце выдай пользователю чек-лист из раздела «Проверка».
