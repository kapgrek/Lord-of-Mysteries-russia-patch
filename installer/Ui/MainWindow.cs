using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace LotmRussianPatcher
{
    // Main window: Ui/MainWindow.xaml (resource LotmRussianPatcher.MainWindow.xaml) + this code.
    // Game state is read off the UI thread; every operation disables the controls until it ends.
    public class MainWindow
    {
        public const string XamlResource = "LotmRussianPatcher.MainWindow.xaml";
        public static readonly string[] ElementNames =
        {
            "Logo", "StatusBadge", "StatusDot", "StatusText", "VersionText", "HeaderHowToButton",
            "GamePathBox", "AutoDetectButton", "BrowseButton", "FolderCheckText", "FolderHowToHint", "FolderHowToLink",
            "DpsNative", "DpsAdvanced", "DpsExternal", "DpsOff", "DpsHint", "LaunchMeterButton",
            "ChatCheck", "ClarityCheck",
            "MainButton", "ApplyButton", "UninstallButton", "ProgressRow", "Progress", "ProgressText", "CancelButton",
            "LogBox", "TelegramChannelButton", "TelegramAuthorButton", "BoostyButton", "FooterHowToButton",
            "CpddLink", "GithubLink", "PayloadText"
        };

        private const string ClarityTooltip =
            "Убирает туман, объёмный туман и облака, motion blur, lens flare, bloom, light shafts, преломления, " +
            "Lumen GI и отражения, ambient occlusion. Остальные настройки Engine.ini сохраняются.\n\n" +
            "Блок в Saved\\Config\\Windows\\Engine.ini (тот же, что у английского патча CPDD):\n" +
            "r.DynamicGlobalIlluminationMethod=0, r.ReflectionMethod=0, r.MotionBlurQuality=0, r.DefaultFeature.MotionBlur=0, " +
            "r.LensFlareQuality=0, r.DefaultFeature.LensFlare=0, r.BloomQuality=0, r.DefaultFeature.Bloom=0, r.LightShaftQuality=0, " +
            "r.RefractionQuality=0, r.Refraction.OffsetQuality=0, r.DistanceFieldAO=0, r.AOQuality=0, r.AmbientOcclusionLevels=0, " +
            "r.AmbientOcclusionMaxQuality=0, r.Fog=0, r.VolumetricFog=0, r.VolumetricCloud=0";

        private readonly Window window;
        private readonly Border statusBadge;
        private readonly System.Windows.Shapes.Ellipse statusDot;
        private readonly TextBlock statusText, folderCheckText, dpsHint, progressText, payloadText;
        private readonly FrameworkElement folderHowToHint, progressRow;
        private readonly TextBox gamePathBox, logBox;
        private readonly Button autoDetectButton, browseButton, launchMeterButton, mainButton, applyButton, uninstallButton, cancelButton;
        private readonly RadioButton dpsNative, dpsAdvanced, dpsExternal, dpsOff;
        private readonly CheckBox chatCheck, clarityCheck;
        private readonly ProgressBar progress;
        private readonly DispatcherTimer pathTimer, blockerTimer;

        private CancellationTokenSource cts;
        private bool busy, settingPath;
        private int refreshId;
        private string gameDir;                 // validated folder or null
        private GameState state;                // last read state of gameDir
        private GameOptionsState writtenOptions; // what the game files contain now
        private string latestVersion;           // latest GitHub release, if known
        private string blocker;

        private class GameState
        {
            public GamePatchStatus Status;
            public PakState Pak;
            public string GameBuild;
            public string InstalledVersion;
            public bool BridgeFileMissing;
            public bool HasOwnFiles;
            public GameOptionsState Options;
            public string OptionsError;
        }

        public static Window Create()
        {
            UiKit.EnsureApplication();
            return new MainWindow().window;
        }

        private MainWindow()
        {
            window = (Window)UiKit.LoadXaml(XamlResource);
            UiKit.UseDarkTitleBar(window);
            ImageSource icon = UiKit.LoadImage(UiKit.IconResource);
            if (icon != null) window.Icon = icon;
            window.Title = "Lord of Mysteries — русская локализация " + AppInfo.Version;
            // 1366x768 laptops: the log (last DockPanel child) shrinks first.
            window.Height = Math.Max(window.MinHeight, Math.Min(window.Height, SystemParameters.WorkArea.Height - 8));

            UiKit.Find<Image>(window, "Logo").Source = icon;
            statusBadge = UiKit.Find<Border>(window, "StatusBadge");
            statusDot = UiKit.Find<System.Windows.Shapes.Ellipse>(window, "StatusDot");
            statusText = UiKit.Find<TextBlock>(window, "StatusText");
            UiKit.Find<TextBlock>(window, "VersionText").Text = "v" + AppInfo.Version;
            gamePathBox = UiKit.Find<TextBox>(window, "GamePathBox");
            autoDetectButton = UiKit.Find<Button>(window, "AutoDetectButton");
            browseButton = UiKit.Find<Button>(window, "BrowseButton");
            folderCheckText = UiKit.Find<TextBlock>(window, "FolderCheckText");
            folderHowToHint = UiKit.Find<FrameworkElement>(window, "FolderHowToHint");
            dpsNative = UiKit.Find<RadioButton>(window, "DpsNative");
            dpsAdvanced = UiKit.Find<RadioButton>(window, "DpsAdvanced");
            dpsExternal = UiKit.Find<RadioButton>(window, "DpsExternal");
            dpsOff = UiKit.Find<RadioButton>(window, "DpsOff");
            dpsHint = UiKit.Find<TextBlock>(window, "DpsHint");
            launchMeterButton = UiKit.Find<Button>(window, "LaunchMeterButton");
            chatCheck = UiKit.Find<CheckBox>(window, "ChatCheck");
            clarityCheck = UiKit.Find<CheckBox>(window, "ClarityCheck");
            mainButton = UiKit.Find<Button>(window, "MainButton");
            applyButton = UiKit.Find<Button>(window, "ApplyButton");
            uninstallButton = UiKit.Find<Button>(window, "UninstallButton");
            progressRow = UiKit.Find<FrameworkElement>(window, "ProgressRow");
            progress = UiKit.Find<ProgressBar>(window, "Progress");
            progressText = UiKit.Find<TextBlock>(window, "ProgressText");
            cancelButton = UiKit.Find<Button>(window, "CancelButton");
            logBox = UiKit.Find<TextBox>(window, "LogBox");
            payloadText = UiKit.Find<TextBlock>(window, "PayloadText");

            dpsNative.ToolTip = Tip("Простой счётчик: кнопка «Статистика» самой игры доступна во всех режимах.");
            dpsAdvanced.ToolTip = Tip("Расширенный DPS-метр v1.9.1 (по умолчанию): перемещаемые и масштабируемые панели урона, переведены на русский.");
            dpsExternal.ToolTip = Tip("Внешний счётчик: данные боя передаются в отдельное окно-оверлей Lord of Mysteries Combat Meter.");
            dpsOff.ToolTip = Tip("Выключает все счётчики урона.");
            chatCheck.ToolTip = Tip("Новая перемещаемая панель чата для ПК из английского патча CPDD. По умолчанию выключена.");
            clarityCheck.ToolTip = Tip(ClarityTooltip);
            launchMeterButton.ToolTip = Tip("Запускает Saved\\Mods\\ExternalDpsMeter\\Lord of Mysteries Combat Meter.exe. Доступно в режиме «Внешний».");
            UiKit.Find<TextBlock>(window, "CreditsText").ToolTip = Tip("Русификатор использует загрузчик, моды и DPS-метр английского патча CPDD.");

            pathTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
            pathTimer.Tick += (s, e) => { pathTimer.Stop(); RefreshAsync(); };
            blockerTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            blockerTimer.Tick += (s, e) => CheckBlocker();

            WireEvents();
            WireLinks();

            if (!string.IsNullOrEmpty(PayloadSource.ExplicitPayload))
            {
                payloadText.Text = "Локальный пакет: " + PayloadSource.ExplicitPayload;
                payloadText.Visibility = Visibility.Visible;
            }

            window.Loaded += (s, e) =>
            {
                Log("Установщик русской локализации " + AppInfo.Version + ".");
                if (!string.IsNullOrEmpty(PayloadSource.ExplicitPayload)) Log("Локальный пакет: " + PayloadSource.ExplicitPayload);
                blocker = PatcherBackend.RunningBlocker();
                blockerTimer.Start();
                AutoDetect(true);
                FetchLatestAsync();
            };
            window.Closing += (s, e) =>
            {
                if (busy && !UiKit.Confirm(window, "Операция ещё идёт", "Закрыть установщик сейчас? Текущая операция будет прервана.", "Закрыть", "Подождать", true)) e.Cancel = true;
                else if (cts != null) cts.Cancel();
            };
            UpdateDpsHint();
            UpdateButtons();
        }

        private static ToolTip Tip(string text)
        {
            return new ToolTip { Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, MaxWidth = 420 } };
        }

        private void WireEvents()
        {
            gamePathBox.TextChanged += (s, e) =>
            {
                if (settingPath) return;
                pathTimer.Stop();
                pathTimer.Start();
            };
            autoDetectButton.Click += (s, e) => AutoDetect(false);
            browseButton.Click += (s, e) => Browse();
            RoutedEventHandler optionChanged = (s, e) => { UpdateDpsHint(); UpdateButtons(); };
            foreach (RadioButton rb in new[] { dpsNative, dpsAdvanced, dpsExternal, dpsOff }) rb.Checked += optionChanged;
            chatCheck.Checked += optionChanged; chatCheck.Unchecked += optionChanged;
            clarityCheck.Checked += optionChanged; clarityCheck.Unchecked += optionChanged;
            launchMeterButton.Click += (s, e) => LaunchMeter();
            mainButton.Click += (s, e) => InstallAsync();
            applyButton.Click += (s, e) => ApplyAsync();
            uninstallButton.Click += (s, e) => UninstallAsync();
            cancelButton.Click += (s, e) => { if (cts != null) { cts.Cancel(); Log("Отмена…"); } };
            RoutedEventHandler howTo = (s, e) => HowToPlayWindow.Show(window);
            UiKit.Find<Button>(window, "HeaderHowToButton").Click += howTo;
            UiKit.Find<Button>(window, "FooterHowToButton").Click += howTo;
            UiKit.Find<Hyperlink>(window, "FolderHowToLink").Click += howTo;
        }

        // Buttons and links from links.json; a missing or disallowed address hides its button.
        private void WireLinks()
        {
            WireLinkButton("TelegramChannelButton", Links.TelegramChannel);
            WireLinkButton("TelegramAuthorButton", Links.TelegramAuthor);
            WireLinkButton("BoostyButton", Links.Boosty);
            WireHyperlink("CpddLink", Links.CpddDiscord);
            WireHyperlink("GithubLink", Links.Github);
        }

        private void WireLinkButton(string name, string key)
        {
            var button = UiKit.Find<Button>(window, name);
            string url = Links.Get(key);
            if (url == null) { button.Visibility = Visibility.Collapsed; return; }
            button.ToolTip = Tip(url);
            button.Click += (s, e) => Links.Open(url);
        }

        private void WireHyperlink(string name, string key)
        {
            var link = UiKit.Find<Hyperlink>(window, name);
            string url = Links.Get(key);
            if (url == null) { link.IsEnabled = false; return; }
            link.ToolTip = Tip(url);
            link.Click += (s, e) => Links.Open(url);
        }

        // ------------------------------------------------------------ log / progress

        private void Log(string message)
        {
            if (!window.Dispatcher.CheckAccess())
            {
                window.Dispatcher.BeginInvoke(new Action<string>(Log), message);
                return;
            }
            logBox.AppendText(DateTime.Now.ToString("HH:mm:ss") + " " + message + Environment.NewLine);
            logBox.ScrollToEnd();
        }

        private void ReportProgress(int percent, string text)
        {
            if (!window.Dispatcher.CheckAccess())
            {
                window.Dispatcher.BeginInvoke(new Action<int, string>(ReportProgress), percent, text);
                return;
            }
            progress.IsIndeterminate = percent < 0;
            if (percent >= 0) progress.Value = Math.Min(100, percent);
            progressText.Text = percent >= 0 ? percent + "%  " + (text ?? "") : (text ?? "");
        }

        // ------------------------------------------------------------ folder

        private void SetPath(string path)
        {
            settingPath = true;
            gamePathBox.Text = path ?? "";
            gamePathBox.CaretIndex = gamePathBox.Text.Length;
            settingPath = false;
            RefreshAsync();
        }

        private void AutoDetect(bool startup)
        {
            string found = PatcherBackend.FindGameFolder();
            if (found != null)
            {
                Log("Папка игры найдена: " + found);
                SetPath(found);
            }
            else
            {
                Log("Игра не найдена в стандартных папках. Укажите её кнопкой «Выбрать папку…».");
                if (startup) SetPath("");
                else UiKit.Message(window, "Игра не найдена", "Папку игры не удалось найти автоматически. Нажмите «Выбрать папку…» и укажите папку Game\\C7 (или папку GMZZLauncher — установщик найдёт Game\\C7 сам).", false);
            }
        }

        private void Browse()
        {
            try
            {
                string picked = FolderPicker.Pick(new WindowInteropHelper(window).Handle, "Папка игры Lord of Mysteries (Game\\C7)", gamePathBox.Text.Trim());
                if (picked == null) return;
                string normalized = PatcherBackend.NormalizeGameDir(picked);
                if (normalized != picked) Log("Выбрана папка " + picked + " → " + normalized);
                SetPath(normalized);
            }
            catch (Exception ex)
            {
                Log("ОШИБКА диалога выбора папки: " + ex.Message);
            }
        }

        // Reads everything about the typed folder in the background; stale results are dropped.
        private async void RefreshAsync()
        {
            if (busy) return;
            int id = ++refreshId;
            string typed = gamePathBox.Text.Trim();
            string normalized = PatcherBackend.NormalizeGameDir(typed);
            if (!string.IsNullOrEmpty(normalized) && normalized != typed && PatcherBackend.IsValidGameFolder(normalized))
            {
                settingPath = true;
                gamePathBox.Text = normalized;
                gamePathBox.CaretIndex = normalized.Length;
                settingPath = false;
            }

            bool folderOk;
            string folderText = PatcherBackend.DescribeFolder(normalized, out folderOk);
            gameDir = null;
            state = null;
            if (!folderOk)
            {
                SetFolderLine(string.IsNullOrWhiteSpace(typed) ? "Папка игры не выбрана." : folderText, string.IsNullOrWhiteSpace(typed) ? "MutedBrush" : "ErrorBrush");
                folderHowToHint.Visibility = Visibility.Visible;
                UpdateStatus();
                UpdateButtons();
                return;
            }

            folderHowToHint.Visibility = Visibility.Collapsed;
            SetFolderLine("Проверка версии игры (SHA-256 pakchunk0)…", "MutedBrush");
            GameState read = await Task.Run(() => ReadState(normalized));
            if (id != refreshId) return;
            gameDir = normalized;
            state = read;

            if (read.Pak == PakState.Unknown)
                SetFolderLine("✗ Версия игры не поддерживается (русификатор рассчитан на сборку " + (read.GameBuild ?? "?") + "). Дождитесь обновления русификатора.", "ErrorBrush");
            else
                SetFolderLine("✓ Сборка игры " + (read.GameBuild ?? "?") + " — поддерживается", "OkBrush");

            if (read.OptionsError != null) Log("Внимание: " + read.OptionsError);
            ShowOptions(read.Options);
            writtenOptions = read.Options;
            UpdateStatus();
            UpdateButtons();
        }

        private static GameState ReadState(string dir)
        {
            var st = new GameState();
            string build;
            st.Pak = PatcherBackend.InspectPak(dir, out build);
            st.GameBuild = build;
            st.Status = PatcherBackend.InspectGameStatus(dir);
            st.InstalledVersion = PatcherBackend.InstalledVersion(dir);
            st.BridgeFileMissing = !File.Exists(System.IO.Path.Combine(dir, InstallerCore.BridgeRel));
            st.HasOwnFiles = File.Exists(System.IO.Path.Combine(dir, InstallerCore.BackupDirRel, InstallerCore.InstalledListName)) || st.Status != GamePatchStatus.NotInstalled;
            string error;
            st.Options = new GameOptions(dir, null).Read(out error);
            st.OptionsError = error;
            return st;
        }

        private void SetFolderLine(string text, string brushKey)
        {
            folderCheckText.Text = text;
            folderCheckText.Foreground = UiKit.Brush(brushKey);
        }

        // ------------------------------------------------------------ status and buttons

        private string TargetVersion { get { return latestVersion ?? AppInfo.Version; } }

        private bool NeedsRepair
        {
            get
            {
                return state != null && (state.Status == GamePatchStatus.InstalledDisabled
                    || (state.Pak == PakState.Installed && state.BridgeFileMissing && state.HasOwnFiles));
            }
        }

        private bool UpdateAvailable
        {
            get
            {
                return state != null && state.Status == GamePatchStatus.InstalledActive && state.InstalledVersion != null
                    && PatcherBackend.CompareVersions(state.InstalledVersion, TargetVersion) < 0;
            }
        }

        private void UpdateStatus()
        {
            string target = TargetVersion.StartsWith("v") ? TargetVersion : "v" + TargetVersion;
            if (blocker != null) SetStatus("ИГРА ЗАПУЩЕНА", "ErrorBrush", "ErrorSoftBrush");
            else if (gameDir == null || state == null) SetStatus("ВЫБЕРИТЕ ПАПКУ ИГРЫ", "MutedBrush", "MutedSoftBrush");
            else if (NeedsRepair) SetStatus("НУЖНО ВОССТАНОВИТЬ ЗАПУСК", "WarnBrush", "WarnSoftBrush");
            else if (state.Pak == PakState.Unknown) SetStatus("ВЕРСИЯ ИГРЫ НЕ ПОДДЕРЖИВАЕТСЯ", "ErrorBrush", "ErrorSoftBrush");
            else if (UpdateAvailable) SetStatus("ДОСТУПНО ОБНОВЛЕНИЕ " + target, "GoldBrush", "GoldSoftBrush");
            else if (state.Status == GamePatchStatus.InstalledActive) SetStatus("РУССКИЙ УСТАНОВЛЕН", "OkBrush", "OkSoftBrush");
            else SetStatus("ГОТОВ К УСТАНОВКЕ", "GoldBrush", "GoldSoftBrush");

            if (NeedsRepair) mainButton.Content = "Восстановить запуск";
            else if (UpdateAvailable) mainButton.Content = "Обновить до " + target;
            else if (state != null && state.Status == GamePatchStatus.InstalledActive) mainButton.Content = "Переустановить";
            else mainButton.Content = "Установить";
        }

        private void SetStatus(string text, string fgKey, string bgKey)
        {
            statusText.Text = text;
            statusText.Foreground = UiKit.Brush(fgKey);
            statusDot.Fill = UiKit.Brush(fgKey);
            statusBadge.Background = UiKit.Brush(bgKey);
        }

        private void UpdateButtons()
        {
            bool ready = !busy && gameDir != null && state != null && blocker == null;
            bool installed = state != null && state.Status == GamePatchStatus.InstalledActive;
            mainButton.IsEnabled = ready && state.Pak != PakState.Unknown;
            applyButton.IsEnabled = ready && installed && writtenOptions != null && !CurrentOptions().SameAs(writtenOptions);
            uninstallButton.IsEnabled = ready && state.HasOwnFiles;
            launchMeterButton.IsEnabled = !busy && gameDir != null && dpsExternal.IsChecked == true && new GameOptions(gameDir, null).CombatMeterExists;
            foreach (UIElement e in new UIElement[] { gamePathBox, autoDetectButton, browseButton }) e.IsEnabled = !busy;
        }

        private void CheckBlocker()
        {
            string now = PatcherBackend.RunningBlocker();
            if (now == blocker) return;
            blocker = now;
            if (now != null) Log(PatcherBackend.BlockerMessage(now));
            UpdateStatus();
            UpdateButtons();
        }

        private async void FetchLatestAsync()
        {
            if (!string.IsNullOrEmpty(PayloadSource.ExplicitPayload)) return;
            ReleaseManifest manifest = await Task.Run(() => { try { return PayloadSource.FetchManifest(null); } catch { return null; } });
            if (manifest == null || string.IsNullOrEmpty(manifest.Version)) return;
            latestVersion = manifest.Version;
            Log("Последняя версия на GitHub: " + manifest.Version + (manifest.PayloadSize > 0 ? " (" + (manifest.PayloadSize / 1048576) + " МБ)" : ""));
            UpdateStatus();
        }

        // ------------------------------------------------------------ options

        private GameOptionsState CurrentOptions()
        {
            var o = new GameOptionsState();
            if (dpsNative.IsChecked == true) o.DpsMode = DpsMeterMode.Native;
            else if (dpsExternal.IsChecked == true) o.DpsMode = DpsMeterMode.External;
            else if (dpsOff.IsChecked == true) o.DpsMode = DpsMeterMode.Off;
            else o.DpsMode = DpsMeterMode.Advanced;
            o.DesktopChat = chatCheck.IsChecked == true;
            o.VisualClarity = clarityCheck.IsChecked == true;
            return o;
        }

        private void ShowOptions(GameOptionsState o)
        {
            if (o == null) return;
            dpsNative.IsChecked = o.DpsMode == DpsMeterMode.Native;
            dpsAdvanced.IsChecked = o.DpsMode == DpsMeterMode.Advanced;
            dpsExternal.IsChecked = o.DpsMode == DpsMeterMode.External;
            dpsOff.IsChecked = o.DpsMode == DpsMeterMode.Off;
            chatCheck.IsChecked = o.DesktopChat;
            clarityCheck.IsChecked = o.VisualClarity;
            UpdateDpsHint();
        }

        private void UpdateDpsHint()
        {
            switch (CurrentOptions().DpsMode)
            {
                case DpsMeterMode.Native: dpsHint.Text = "Кнопка «Статистика» самой игры доступна везде."; break;
                case DpsMeterMode.External: dpsHint.Text = "Бой передаётся во внешний оверлей Combat Meter — запустите его кнопкой справа."; break;
                case DpsMeterMode.Off: dpsHint.Text = "Все счётчики урона выключены."; break;
                default: dpsHint.Text = "Перемещаемые и масштабируемые панели DPS v1.9.1 на русском."; break;
            }
        }

        private void LaunchMeter()
        {
            if (gameDir == null) return;
            string error;
            if (PatcherBackend.LaunchCombatMeter(gameDir, out error)) Log("Внешний счётчик запущен.");
            else { Log("ОШИБКА: " + error); UiKit.Message(window, "Внешний счётчик", error, true); }
        }

        // ------------------------------------------------------------ operations

        private void BeginOperation(bool cancellable)
        {
            busy = true;
            cts = new CancellationTokenSource();
            progressRow.Visibility = Visibility.Visible;
            cancelButton.Visibility = cancellable ? Visibility.Visible : Visibility.Collapsed;
            ReportProgress(-1, "");
            UpdateButtons();
        }

        private void EndOperation()
        {
            busy = false;
            progressRow.Visibility = Visibility.Collapsed;
            if (cts != null) { cts.Dispose(); cts = null; }
            RefreshAsync();
        }

        private async void InstallAsync()
        {
            if (gameDir == null) return;
            string dir = gameDir;
            GameOptionsState options = CurrentOptions();
            BeginOperation(true);
            Log("=== " + mainButton.Content + " ===");
            InstallResult result;
            try
            {
                result = await PatcherBackend.InstallAsync(dir, options, Log, ReportProgress, cts.Token);
            }
            catch (OperationCanceledException)
            {
                result = new InstallResult { FailReason = "Операция отменена." };
            }
            catch (Exception ex)
            {
                Exception inner = ex;
                while (inner.InnerException != null) inner = inner.InnerException;
                result = new InstallResult { FailReason = inner.Message };
            }
            EndOperation();
            if (result.Success)
            {
                Log("✔ Готово.");
                UiKit.Message(window, "Русификатор установлен", "Русская локализация установлена и проверена. Можно запускать игру.", false);
            }
            else
            {
                Log("ОШИБКА: " + result.FailReason);
                UiKit.Message(window, "Установка не завершена", result.FailReason + "\n\nПодробности — в журнале.", true);
            }
        }

        private async void ApplyAsync()
        {
            if (gameDir == null) return;
            string dir = gameDir;
            GameOptionsState options = CurrentOptions();
            BeginOperation(false);
            var errors = new List<string>();
            bool ok = await Task.Run(() => PatcherBackend.ApplyOptions(dir, options, Log, errors));
            EndOperation();
            if (ok) Log("✔ Настройки применены.");
            else UiKit.Message(window, "Настройки применены не полностью", string.Join("\n", errors.ToArray()), true);
        }

        private async void UninstallAsync()
        {
            if (gameDir == null) return;
            if (!UiKit.Confirm(window, "Удалить русификатор?",
                "Будут удалены только файлы русификатора и блок Visual Clarity; оригинальный блок pakchunk0 восстановится из резервной копии. " +
                "Настройки DPS-метра и чата (cpdd_*settings.lua) и другие моды останутся.", "Удалить", "Отмена", true)) return;
            string dir = gameDir;
            BeginOperation(false);
            Log("=== Удаление русификатора ===");
            bool ok = await Task.Run(() => PatcherBackend.Uninstall(dir, Log));
            EndOperation();
            if (ok) UiKit.Message(window, "Русификатор удалён", "Игра возвращена к исходному состоянию.", false);
            else UiKit.Message(window, "Удаление с предупреждениями", "Часть шагов не выполнена — подробности в журнале. Если игра не запускается, проверьте файлы игры в лаунчере.", true);
        }
    }
}
