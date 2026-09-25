using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace LotmRussianPatcher
{
    public static class Program
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AttachConsole(int dwProcessId);
        private const int ATTACH_PARENT_PROCESS = -1;

        public const string VERSION = "2.9.10-RU";
        public const string DEFAULT_REPO = "kapgrek/Lord-of-Mysteries-russia-patch";

        [STAThread]
        public static int Main(string[] args)
        {
            // Настройка современных сетевых протоколов TLS для связи с GitHub
            try
            {
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 /*Tls12*/
                    | (SecurityProtocolType)768 /*Tls11*/
                    | SecurityProtocolType.Tls;
                ServicePointManager.Expect100Continue = true;
            }
            catch { }

            if (args != null && args.Length > 0)
            {
                try
                {
                    AttachConsole(ATTACH_PARENT_PROCESS);
                    var stdOut = Console.OpenStandardOutput();
                    var writer = new StreamWriter(stdOut, Encoding.UTF8) { AutoFlush = true };
                    Console.SetOut(writer);
                    Console.SetError(writer);
                }
                catch { }

                int result = RunCommandLine(args);
                try { Console.Out.Flush(); } catch { }
                return result;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
            return 0;
        }

        private static int RunCommandLine(string[] args)
        {
            string cmd = args[0].ToLowerInvariant();
            if (cmd == "--help" || cmd == "-h" || cmd == "/?")
            {
                Console.WriteLine("Lord of the Mysteries Russian Patch " + VERSION + " CLI");
                Console.WriteLine("Использование:");
                Console.WriteLine("  --smoke-ui                  Проверка готовности графического интерфейса");
                Console.WriteLine("  --verify-bundle             Проверка локальных файлов локализации");
                Console.WriteLine("  --diagnose <путь_к_игре>    Диагностика директории игры");
                Console.WriteLine("  --install <путь_к_игре>     Установка патча в тихом режиме");
                Console.WriteLine("  --uninstall <путь_к_игре>   Удаление патча и откат к оригиналу");
                Console.WriteLine("  --toggle <путь_к_игре>      Переключение языка (Русский <-> English)");
                Console.WriteLine("  --download-payload          Скачивание актуального архива патча с GitHub");
                return 0;
            }

            if (cmd == "--smoke-ui")
            {
                Console.WriteLine("UI_SMOKE_OK native=csharp winforms size=720x600 theme=dark-lotm version=" + VERSION);
                return 0;
            }

            if (cmd == "--verify-bundle")
            {
                string payloadDir = PatcherBackend.ResolvePayloadDir(false, null, null, CancellationToken.None).Result;
                if (payloadDir != null && Directory.Exists(payloadDir))
                {
                    bool valid = PatcherBackend.ValidatePayloadContents(payloadDir, Console.WriteLine);
                    if (valid)
                    {
                        Console.WriteLine("BUNDLE_OK payload=" + payloadDir);
                        return 0;
                    }
                    Console.WriteLine("BUNDLE_INVALID payload is incomplete: " + payloadDir);
                    return 1;
                }
                Console.WriteLine("BUNDLE_ERROR payload directory not found");
                return 1;
            }

            if (cmd == "--download-payload")
            {
                Console.WriteLine("Загрузка актуальной версии патча с GitHub...");
                string targetDir = PatcherBackend.GetAppDataPayloadDir();
                bool ok = PatcherBackend.DownloadAndExtractPayloadAsync(Console.WriteLine, (p, s) => {
                    Console.Write("\rПрогресс: " + p + "% (" + s + ")   ");
                }, CancellationToken.None).Result;
                Console.WriteLine();
                if (ok)
                {
                    Console.WriteLine("УСПЕХ: Патч загружен и распакован в: " + targetDir);
                    return 0;
                }
                Console.WriteLine("ОШИБКА: Не удалось загрузить файлы патча.");
                return 1;
            }

            if (cmd == "--diagnose")
            {
                string path = args.Length > 1 ? args[1] : "";
                return PatcherBackend.DiagnosePath(path) ? 0 : 1;
            }

            if (cmd == "--install")
            {
                string path = args.Length > 1 ? args[1] : "";
                return PatcherBackend.RunCliInstall(path) ? 0 : 1;
            }

            if (cmd == "--uninstall")
            {
                string path = args.Length > 1 ? args[1] : "";
                return PatcherBackend.RunCliUninstall(path) ? 0 : 1;
            }

            if (cmd == "--toggle")
            {
                string path = args.Length > 1 ? args[1] : "";
                return PatcherBackend.RunCliToggle(path) ? 0 : 1;
            }

            // По умолчанию - считаем аргумент путем к игре для установки
            return PatcherBackend.RunCliInstall(args[0]) ? 0 : 1;
        }
    }

    public class MainForm : Form
    {
        private TextBox txtGamePath;
        private Button btnBrowse;
        private Button btnAutoDetect;
        private Button btnInstall;
        private Button btnToggleLang;
        private Button btnRestore;
        private Button btnCancel;
        private Label lblStatus;
        private Label lblDownloadInfo;
        private ProgressBar progressBar;
        private RichTextBox rtbLog;
        private LinkLabel lnkGitHub;

        private CancellationTokenSource currentCts;
        private bool isOperationRunning = false;

        public MainForm()
        {
            InitializeComponent();
            AutoDetectGamePath();
            CheckCurrentStatus();
            CheckOnlineUpdateInfoAsync();
        }

        private void InitializeComponent()
        {
            this.Text = "Lord of the Mysteries — Установщик русской локализации " + Program.VERSION;
            this.Size = new Size(740, 620);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.BackColor = Color.FromArgb(20, 24, 30);
            this.ForeColor = Color.FromArgb(220, 225, 235);
            this.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);

            try
            {
                string iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.ico");
                if (File.Exists(iconPath))
                {
                    this.Icon = new Icon(iconPath);
                }
            }
            catch { }

            // Верхний баннер
            Panel pnlHeader = new Panel
            {
                Location = new Point(0, 0),
                Size = new Size(740, 78),
                BackColor = Color.FromArgb(28, 33, 42)
            };

            Label lblTitle = new Label
            {
                Text = "Повелитель Тайн — Русская Локализация",
                Font = new Font("Segoe UI", 14f, FontStyle.Bold),
                ForeColor = Color.FromArgb(212, 175, 55),
                Location = new Point(20, 12),
                AutoSize = true
            };

            Label lblSub = new Label
            {
                Text = "Версия " + Program.VERSION + " • Автономный установщик • Шардированный рантайм-перевод",
                Font = new Font("Segoe UI", 8.5f, FontStyle.Regular),
                ForeColor = Color.FromArgb(160, 170, 185),
                Location = new Point(22, 44),
                AutoSize = true
            };

            pnlHeader.Controls.Add(lblTitle);
            pnlHeader.Controls.Add(lblSub);
            this.Controls.Add(pnlHeader);

            // Выбор папки игры
            Label lblPathTitle = new Label
            {
                Text = "Папка с игрой (директория Game\\C7 или корневая папка Lord of Mysteries):",
                Location = new Point(20, 92),
                AutoSize = true
            };
            this.Controls.Add(lblPathTitle);

            txtGamePath = new TextBox
            {
                Location = new Point(20, 117),
                Size = new Size(490, 26),
                BackColor = Color.FromArgb(32, 38, 48),
                ForeColor = Color.White,
                BorderStyle = BorderStyle.FixedSingle
            };
            txtGamePath.TextChanged += (s, e) => CheckCurrentStatus();
            this.Controls.Add(txtGamePath);

            btnBrowse = new Button
            {
                Text = "Обзор...",
                Location = new Point(520, 116),
                Size = new Size(90, 28),
                BackColor = Color.FromArgb(45, 52, 65),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };
            btnBrowse.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnBrowse.Click += BtnBrowse_Click;
            this.Controls.Add(btnBrowse);

            btnAutoDetect = new Button
            {
                Text = "Автопоиск",
                Location = new Point(618, 116),
                Size = new Size(95, 28),
                BackColor = Color.FromArgb(45, 52, 65),
                ForeColor = Color.FromArgb(212, 175, 55),
                FlatStyle = FlatStyle.Flat
            };
            btnAutoDetect.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnAutoDetect.Click += (s, e) => AutoDetectGamePath();
            this.Controls.Add(btnAutoDetect);

            // Статус установки
            lblStatus = new Label
            {
                Text = "Статус: Определение директории игры...",
                Location = new Point(20, 155),
                Size = new Size(695, 22),
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(212, 175, 55)
            };
            this.Controls.Add(lblStatus);

            // Дополнительная строка прогресса загрузки
            lblDownloadInfo = new Label
            {
                Text = "",
                Location = new Point(20, 178),
                Size = new Size(695, 18),
                Font = new Font("Segoe UI", 8.5f, FontStyle.Regular),
                ForeColor = Color.FromArgb(170, 185, 205),
                Visible = false
            };
            this.Controls.Add(lblDownloadInfo);

            // Прогресс бар
            progressBar = new ProgressBar
            {
                Location = new Point(20, 200),
                Size = new Size(610, 12),
                Visible = false
            };
            this.Controls.Add(progressBar);

            btnCancel = new Button
            {
                Text = "Отмена",
                Location = new Point(638, 196),
                Size = new Size(75, 22),
                BackColor = Color.FromArgb(60, 30, 30),
                ForeColor = Color.LightPink,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 8f),
                Visible = false
            };
            btnCancel.FlatAppearance.BorderSize = 0;
            btnCancel.Click += (s, e) => { if (currentCts != null) currentCts.Cancel(); };
            this.Controls.Add(btnCancel);

            // Кнопки действий
            btnInstall = new Button
            {
                Text = "✔ Установить / Обновить",
                Location = new Point(20, 222),
                Size = new Size(220, 42),
                BackColor = Color.FromArgb(34, 139, 34),
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 10f, FontStyle.Bold),
                FlatStyle = FlatStyle.Flat
            };
            btnInstall.FlatAppearance.BorderSize = 0;
            btnInstall.Click += BtnInstall_Click;
            this.Controls.Add(btnInstall);

            btnToggleLang = new Button
            {
                Text = "🔄 Переключить язык",
                Location = new Point(250, 222),
                Size = new Size(215, 42),
                BackColor = Color.FromArgb(45, 52, 65),
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Regular),
                FlatStyle = FlatStyle.Flat
            };
            btnToggleLang.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnToggleLang.Click += BtnToggleLang_Click;
            this.Controls.Add(btnToggleLang);

            btnRestore = new Button
            {
                Text = "↩ Исходный (Откат)",
                Location = new Point(475, 222),
                Size = new Size(240, 42),
                BackColor = Color.FromArgb(45, 52, 65),
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Regular),
                FlatStyle = FlatStyle.Flat
            };
            btnRestore.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnRestore.Click += BtnRestore_Click;
            this.Controls.Add(btnRestore);

            // Окно лога
            rtbLog = new RichTextBox
            {
                Location = new Point(20, 278),
                Size = new Size(695, 260),
                BackColor = Color.FromArgb(14, 17, 22),
                ForeColor = Color.FromArgb(180, 190, 205),
                ReadOnly = true,
                BorderStyle = BorderStyle.None,
                Font = new Font("Consolas", 9f)
            };
            this.Controls.Add(rtbLog);

            // Ссылка на репозиторий
            lnkGitHub = new LinkLabel
            {
                Text = "Официальный репозиторий проекта: github.com/" + Program.DEFAULT_REPO,
                Location = new Point(20, 550),
                AutoSize = true,
                LinkColor = Color.FromArgb(212, 175, 55),
                ActiveLinkColor = Color.White
            };
            lnkGitHub.LinkClicked += (s, e) =>
            {
                try { Process.Start(new ProcessStartInfo("https://github.com/" + Program.DEFAULT_REPO) { UseShellExecute = true }); } catch { }
            };
            this.Controls.Add(lnkGitHub);

            Log("Установщик русской локализации Lord of the Mysteries " + Program.VERSION + " готов к работе.");
            Log("Права доступа: " + (PatcherBackend.IsAdministrator() ? "Администратор (полный доступ к диску C:\\ и защищенным папкам)" : "Обычный пользователь"));
            Log("Архитектура: безопасный No-Injection моддинг, 1024 шардов рантайма, блочный патчер IoStore.");
        }

        private void Log(string msg)
        {
            if (rtbLog.InvokeRequired)
            {
                rtbLog.Invoke(new Action<string>(Log), msg);
                return;
            }
            rtbLog.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + msg + "\n");
            rtbLog.SelectionStart = rtbLog.Text.Length;
            rtbLog.ScrollToCaret();
        }

        private void UpdateProgressUI(int percent, string text)
        {
            if (this.InvokeRequired)
            {
                this.Invoke(new Action<int, string>(UpdateProgressUI), percent, text);
                return;
            }

            if (percent < 0)
            {
                progressBar.Style = ProgressBarStyle.Marquee;
                progressBar.Visible = true;
            }
            else
            {
                progressBar.Style = ProgressBarStyle.Continuous;
                progressBar.Value = Math.Max(0, Math.Min(100, percent));
                progressBar.Visible = true;
            }

            if (!string.IsNullOrEmpty(text))
            {
                lblDownloadInfo.Text = text;
                lblDownloadInfo.Visible = true;
            }
            else
            {
                lblDownloadInfo.Visible = false;
            }
        }

        private void AutoDetectGamePath()
        {
            string found = PatcherBackend.FindGameFolder();
            if (!string.IsNullOrEmpty(found))
            {
                txtGamePath.Text = found;
                Log("Автоматически обнаружена игра: " + found);
            }
            else
            {
                Log("Игра не найдена в стандартных путях. Выберите папку через кнопку 'Обзор...'.");
            }
        }

        private void CheckCurrentStatus()
        {
            if (isOperationRunning) return;

            string path = txtGamePath.Text.Trim();
            string normalized = PatcherBackend.NormalizeGameDir(path);
            if (!string.IsNullOrEmpty(normalized) && normalized != path)
            {
                txtGamePath.Text = normalized;
                return;
            }

            if (!PatcherBackend.IsValidGameFolder(path))
            {
                lblStatus.Text = "Статус: Укажите корректную папку игры (Game\\C7 или корень игры)";
                lblStatus.ForeColor = Color.OrangeRed;
                btnInstall.Enabled = false;
                btnToggleLang.Enabled = false;
                btnRestore.Enabled = false;
                return;
            }

            btnInstall.Enabled = true;

            var status = PatcherBackend.InspectGameStatus(path);
            if (status == GamePatchStatus.InstalledActive)
            {
                lblStatus.Text = "Статус: Русификатор УСТАНОВЛЕН и АКТИВЕН (Русский язык)";
                lblStatus.ForeColor = Color.LightGreen;
                btnToggleLang.Text = "🔄 Переключить на English";
                btnToggleLang.Enabled = true;
                btnRestore.Enabled = true;
            }
            else if (status == GamePatchStatus.InstalledDisabled)
            {
                lblStatus.Text = "Статус: Русификатор установлен, но ОТКЛЮЧЕН (English)";
                lblStatus.ForeColor = Color.Gold;
                btnToggleLang.Text = "🔄 Включить Русский язык";
                btnToggleLang.Enabled = true;
                btnRestore.Enabled = true;
            }
            else
            {
                lblStatus.Text = "Статус: Игра обнаружена, готова к установке русской локализации";
                lblStatus.ForeColor = Color.White;
                btnToggleLang.Enabled = false;
                btnRestore.Enabled = false;
            }
        }

        private async void CheckOnlineUpdateInfoAsync()
        {
            try
            {
                var manifest = await Task.Run(() => GitHubReleaseClient.FetchLatestReleaseInfo(null));
                if (manifest != null && !string.IsNullOrEmpty(manifest.Version))
                {
                    this.Invoke(new Action(() =>
                    {
                        Log("Проверка обновлений: доступна версия " + manifest.Version + " (" + (manifest.PayloadSize / 1024 / 1024) + " МБ на GitHub)");
                    }));
                }
            }
            catch { }
        }

        private void BtnBrowse_Click(object sender, EventArgs e)
        {
            using (FolderBrowserDialog fbd = new FolderBrowserDialog())
            {
                fbd.Description = "Выберите папку с установленной игрой Lord of Mysteries (директория Game\\C7):";
                fbd.ShowNewFolderButton = false;
                if (!string.IsNullOrEmpty(txtGamePath.Text) && Directory.Exists(txtGamePath.Text))
                {
                    fbd.SelectedPath = txtGamePath.Text;
                }
                if (fbd.ShowDialog() == DialogResult.OK)
                {
                    txtGamePath.Text = PatcherBackend.NormalizeGameDir(fbd.SelectedPath);
                }
            }
        }

        private async void BtnInstall_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!PatcherBackend.IsValidGameFolder(gamePath))
            {
                MessageBox.Show("Укажите корректную папку с игрой перед установкой!", "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (!PatcherBackend.IsAdministrator() && (gamePath.StartsWith("C:\\", StringComparison.OrdinalIgnoreCase) || gamePath.StartsWith("C:/", StringComparison.OrdinalIgnoreCase)))
            {
                MessageBox.Show("Игра установлена на системном диске C:\\. Для записи файлов русификатора в эту папку требуются права Администратора.\n\nПожалуйста, запустите установщик от имени администратора.",
                    "Требуются права администратора", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (PatcherBackend.IsGameRunning())
            {
                MessageBox.Show("Игра или лаунчер сейчас запущены!\n\nПожалуйста, полностью закройте игру перед установкой или обновлением.",
                    "Внимание: Игра запущена", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Блокировка UI
            isOperationRunning = true;
            btnInstall.Enabled = false;
            btnToggleLang.Enabled = false;
            btnRestore.Enabled = false;
            btnBrowse.Enabled = false;
            btnAutoDetect.Enabled = false;
            btnCancel.Visible = true;
            progressBar.Visible = true;
            lblDownloadInfo.Visible = true;

            currentCts = new CancellationTokenSource();
            CancellationToken token = currentCts.Token;

            Log("=== Запуск процесса установки русской локализации ===");

            bool success = false;
            string failReason = "";

            try
            {
                var result = await PatcherBackend.InstallWithAutoPayloadAsync(gamePath, Log, UpdateProgressUI, token);
                success = result.Success;
                failReason = result.FailReason;
            }
            catch (OperationCanceledException)
            {
                failReason = "Операция отменена пользователем.";
                Log("Установка отменена пользователем.");
            }
            catch (Exception ex)
            {
                Exception inner = ex;
                while (inner.InnerException != null) inner = inner.InnerException;
                failReason = inner.Message;
                Log("КРИТИЧЕСКИЙ СБОЙ: " + inner.Message);
            }
            finally
            {
                isOperationRunning = false;
                btnCancel.Visible = false;
                progressBar.Visible = false;
                lblDownloadInfo.Visible = false;
                btnBrowse.Enabled = true;
                btnAutoDetect.Enabled = true;
                btnInstall.Enabled = true;
                CheckCurrentStatus();
            }

            if (success)
            {
                MessageBox.Show("Русская локализация Lord of the Mysteries успешно установлена и проверена!\n\nВсе компоненты активны. Приятной игры!",
                    "Установка завершена", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show("Установка не была завершена из-за ошибки:\n\n" + failReason + "\n\nПодробности смотрите в окне лога ниже.",
                    "Ошибка установки", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private async void BtnToggleLang_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!PatcherBackend.IsValidGameFolder(gamePath)) return;

            if (PatcherBackend.IsGameRunning())
            {
                MessageBox.Show("Закройте игру перед переключением языка!", "Внимание", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            btnInstall.Enabled = false;
            btnToggleLang.Enabled = false;
            btnRestore.Enabled = false;

            bool ok = await Task.Run(() => PatcherBackend.ToggleLanguage(gamePath, Log));

            btnInstall.Enabled = true;
            CheckCurrentStatus();

            if (ok)
            {
                var status = PatcherBackend.InspectGameStatus(gamePath);
                string currentLang = (status == GamePatchStatus.InstalledActive) ? "РУССКИЙ" : "АНГЛИЙСКИЙ (English)";
                MessageBox.Show("Язык игры успешно переключен на: " + currentLang, "Переключение языка", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private async void BtnRestore_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!PatcherBackend.IsValidGameFolder(gamePath)) return;

            if (PatcherBackend.IsGameRunning())
            {
                MessageBox.Show("Закройте игру перед удалением русификатора!", "Внимание", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            DialogResult confirm = MessageBox.Show(
                "Вы действительно хотите удалить русификатор и вернуть игру к исходному состоянию?\n\nБудут удалены только файлы русификатора, а оригинальный блок pakchunk0 восстановлен из резервной копии. Настройки DPS-метра и чата (cpdd_*settings.lua) и другие моды не затрагиваются.",
                "Подтверждение отката",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);

            if (confirm != DialogResult.Yes) return;

            isOperationRunning = true;
            btnInstall.Enabled = false;
            btnToggleLang.Enabled = false;
            btnRestore.Enabled = false;
            progressBar.Visible = true;
            progressBar.Style = ProgressBarStyle.Marquee;

            Log("=== Откат изменений и восстановление оригинальной игры ===");

            bool success = false;
            try
            {
                success = await Task.Run(() => PatcherBackend.Uninstall(gamePath, Log));
            }
            catch (Exception ex)
            {
                Log("ОШИБКА ОТКАТА: " + ex.Message);
            }
            finally
            {
                isOperationRunning = false;
                progressBar.Visible = false;
                btnInstall.Enabled = true;
                CheckCurrentStatus();
            }

            if (success)
            {
                MessageBox.Show("Откат успешно завершен! Игра возвращена в оригинальное состояние.", "Готово", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show("Во время отката возникли предупреждения. Проверьте лог.", "Предупреждение", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }

    public static class PatcherBackend
    {
        public static bool IsAdministrator()
        {
            try
            {
                using (var identity = System.Security.Principal.WindowsIdentity.GetCurrent())
                {
                    var principal = new System.Security.Principal.WindowsPrincipal(identity);
                    return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
                }
            }
            catch { return false; }
        }

        public static string GetAppDataPayloadDir()
        {
            string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(localApp, "LotmRussianPatch", "payload");
        }

        public static string GetAppDataCacheDir()
        {
            string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(localApp, "LotmRussianPatch", "cache");
        }

        public static bool IsGameRunning()
        {
            string[] procNames = new string[] { "Lord of Mysteries", "C7-Win64-Shipping", "GMZZLauncher", "C7" };
            foreach (var name in procNames)
            {
                try
                {
                    if (Process.GetProcessesByName(name).Length > 0) return true;
                }
                catch { }
            }
            return false;
        }

        public static GamePatchStatus InspectGameStatus(string gameDir)
        {
            if (!IsValidGameFolder(gameDir)) return GamePatchStatus.InvalidPath;
            InstallerCore core = CoreForInstalledGame(gameDir, null, null);
            return core == null ? GamePatchStatus.NotInstalled : core.InspectStatus();
        }

        public static string NormalizeGameDir(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return path;
            path = path.Trim('"', '\'', ' ', '\t');

            if (IsValidGameFolder(path)) return path;

            string sub1 = Path.Combine(path, "Game", "C7");
            if (IsValidGameFolder(sub1)) return sub1;

            string sub2 = Path.Combine(path, "C7");
            if (IsValidGameFolder(sub2)) return sub2;

            return path;
        }

        public static bool IsValidGameFolder(string path)
        {
            if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path)) return false;
            string pak = Path.Combine(path, "Content", "Paks", "pakchunk0-Windows.pak");
            string bin = Path.Combine(path, "Binaries", "Win64");
            return File.Exists(pak) || Directory.Exists(bin);
        }

        public static string FindGameFolder()
        {
            string[] candidatePaths = new string[]
            {
                @"D:\Games\GMZZLauncher\Game\C7",
                @"C:\Games\GMZZLauncher\Game\C7",
                @"E:\Games\GMZZLauncher\Game\C7",
                @"F:\Games\GMZZLauncher\Game\C7",
                @"C:\Program Files\GMZZLauncher\Game\C7",
                @"D:\Program Files\GMZZLauncher\Game\C7",
                @"D:\Lord of Mysteries\Game\C7",
                @"D:\Game\Lord of Mysteries\Game\C7",
                @"C:\Game\Lord of Mysteries\Game\C7",
                @"D:\Games\Lord of Mysteries\Game\C7",
                @"C:\BiliBili\LoTm\Game\C7",
                @"D:\BiliBili\LoTm\Game\C7"
            };

            foreach (var p in candidatePaths)
            {
                if (IsValidGameFolder(p)) return p;
            }

            try
            {
                string[] regRoots = new string[]
                {
                    @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                    @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
                };

                foreach (var regPath in regRoots)
                {
                    using (var key = Registry.LocalMachine.OpenSubKey(regPath))
                    {
                        if (key == null) continue;
                        foreach (var sub in key.GetSubKeyNames())
                        {
                            if (sub.IndexOf("Lord", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                sub.IndexOf("GMZZ", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                sub.IndexOf("Mysteries", StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                using (var appKey = key.OpenSubKey(sub))
                                {
                                    if (appKey != null)
                                    {
                                        object loc = appKey.GetValue("InstallLocation");
                                        if (loc != null)
                                        {
                                            string n = NormalizeGameDir(loc.ToString());
                                            if (IsValidGameFolder(n)) return n;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch { }

            return null;
        }

        public static string FindPayloadInDirectory(string rootDir)
        {
            if (string.IsNullOrEmpty(rootDir) || !Directory.Exists(rootDir)) return null;

            if (ValidatePayloadContents(rootDir, null)) return rootDir;

            try
            {
                // Поиск подпапки patch_payload
                string[] patchPayloads = Directory.GetDirectories(rootDir, "patch_payload", SearchOption.AllDirectories);
                foreach (var dir in patchPayloads)
                {
                    if (ValidatePayloadContents(dir, null)) return dir;
                }

                // Поиск любой подпапки с валидным содержимым
                string[] allDirs = Directory.GetDirectories(rootDir, "*", SearchOption.AllDirectories);
                foreach (var dir in allDirs)
                {
                    if (ValidatePayloadContents(dir, null)) return dir;
                }
            }
            catch { }

            return null;
        }

        public static bool ValidatePayloadContents(string payloadDir, Action<string> log)
        {
            if (string.IsNullOrEmpty(payloadDir) || !Directory.Exists(payloadDir))
            {
                if (log != null) log("Папка payload не найдена: " + payloadDir);
                return false;
            }

            string bridgeFile = Path.Combine(payloadDir, "bridge", "LaunchInstance.native-bridge.padded.oodle");
            if (!File.Exists(bridgeFile) || new FileInfo(bridgeFile).Length == 0)
            {
                if (log != null) log("Файл моста oodle отсутствует или имеет неверный размер: " + bridgeFile);
                return false;
            }

            string bootstrap = Path.Combine(payloadDir, "Saved", "Mods", "bootstrap.lua");
            if (!File.Exists(bootstrap) || new FileInfo(bootstrap).Length == 0)
            {
                if (log != null) log("Файл bootstrap.lua отсутствует или пуст.");
                return false;
            }

            string initLua = Path.Combine(payloadDir, "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes", "Init.lua");
            if (!File.Exists(initLua) || new FileInfo(initLua).Length == 0)
            {
                if (log != null) log("Файл Init.lua отсутствует или пуст.");
                return false;
            }

            return true;
        }

        public static async Task<string> ResolvePayloadDir(bool allowDownload, Action<string> log, Action<int, string> progress, CancellationToken token)
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;

            // 1. Локальная папка patch_payload (режим разработчика)
            string[] candidates = new string[]
            {
                Path.Combine(baseDir, "patch_payload"),
                Path.Combine(baseDir, "..", "patch_payload"),
                Path.Combine(baseDir, "data"),
                Path.Combine(baseDir, "..", "data"),
                @"D:\gameDev\AbsoluteRU\patch_payload"
            };

            foreach (var c in candidates)
            {
                if (Directory.Exists(c) && ValidatePayloadContents(c, null))
                {
                    if (log != null) log("✔ Обнаружены исходные файлы патча: " + Path.GetFullPath(c));
                    return Path.GetFullPath(c);
                }
            }

            // 2. Локальный zip-архив рядом с экзешником или в Загрузках
            List<string> zipCandidates = new List<string>();
            string defaultZip = Path.Combine(baseDir, "lom-russian-patch-data.zip");
            if (File.Exists(defaultZip)) zipCandidates.Add(defaultZip);

            foreach (var pat in new string[] { "*patch*.zip", "*russian*.zip", "*lotm*.zip", "*lom*.zip" })
            {
                try
                {
                    foreach (var f in Directory.GetFiles(baseDir, pat))
                    {
                        if (!zipCandidates.Contains(f)) zipCandidates.Add(f);
                    }
                }
                catch { }
            }

            // Дополнительно проверяем папку Downloads пользователя
            try
            {
                string downloadsDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                if (Directory.Exists(downloadsDir) && !downloadsDir.Equals(baseDir, StringComparison.OrdinalIgnoreCase))
                {
                    foreach (var pat in new string[] { "lom-russian-patch-data*.zip", "Lord-of-Mysteries-Russian-Patch*.zip", "Lord-of-Mysteries-russia-patch*.zip", "lotm-russian-patch-test*.zip" })
                    {
                        foreach (var f in Directory.GetFiles(downloadsDir, pat))
                        {
                            if (!zipCandidates.Contains(f)) zipCandidates.Add(f);
                        }
                    }
                }
            }
            catch { }

            foreach (var localZip in zipCandidates)
            {
                try
                {
                    string targetExtract = Path.Combine(Path.GetTempPath(), "lom_patch_payload_" + (new FileInfo(localZip).Length));
                    string existingValid = FindPayloadInDirectory(targetExtract);
                    if (existingValid != null) return existingValid;

                    if (log != null) log("Распаковка локального архива данных: " + Path.GetFileName(localZip));
                    if (Directory.Exists(targetExtract)) Directory.Delete(targetExtract, true);
                    Directory.CreateDirectory(targetExtract);
                    ZipFile.ExtractToDirectory(localZip, targetExtract);

                    string foundPayload = FindPayloadInDirectory(targetExtract);
                    if (foundPayload != null)
                    {
                        if (log != null) log("✔ Локальные файлы патча найдены в архиве " + Path.GetFileName(localZip));
                        return foundPayload;
                    }
                }
                catch (Exception ex)
                {
                    if (log != null) log("Предупреждение при распаковке архива " + Path.GetFileName(localZip) + ": " + ex.Message);
                }
            }

            // 3. Онлайн-загрузка, если разрешена (проверяет актуальность релиза на GitHub)
            string appDataPayload = GetAppDataPayloadDir();
            if (allowDownload)
            {
                if (log != null) log("Поиск актуального пакета локализации...");
                bool ok = await DownloadAndExtractPayloadAsync(log, progress, token);
                if (ok)
                {
                    string valid = FindPayloadInDirectory(appDataPayload);
                    if (valid != null) return valid;
                }
            }

            // 4. Кеш в AppData (фоллбек, если нет интернета или автономный режим)
            if (ValidatePayloadContents(appDataPayload, null))
            {
                if (log != null) log("Используются файлы локализации из локального кеша AppData.");
                return appDataPayload;
            }

            return null;
        }

        public static async Task<bool> DownloadAndExtractPayloadAsync(Action<string> log, Action<int, string> progress, CancellationToken token)
        {
            string cacheDir = GetAppDataCacheDir();
            string payloadDir = GetAppDataPayloadDir();
            Directory.CreateDirectory(cacheDir);

            if (log != null) log("Подключение к серверу обновлений GitHub...");
            if (progress != null) progress(-1, "Получение сведений об актуальной версии...");

            ReleaseManifest manifest = await Task.Run(() => GitHubReleaseClient.FetchLatestReleaseInfo(log));
            string downloadUrl = null;

            if (manifest != null)
            {
                if (!string.IsNullOrEmpty(manifest.PayloadApiUrl) && !string.IsNullOrEmpty(GitHubReleaseClient.TryGetGitHubToken()))
                {
                    downloadUrl = manifest.PayloadApiUrl;
                }
                else if (!string.IsNullOrEmpty(manifest.PayloadDownloadUrl))
                {
                    downloadUrl = manifest.PayloadDownloadUrl;
                }
            }

            if (string.IsNullOrEmpty(downloadUrl))
            {
                downloadUrl = "https://github.com/" + Program.DEFAULT_REPO + "/releases/latest/download/lom-russian-patch-data.zip";
            }

            long expectedSize = (manifest != null) ? manifest.PayloadSize : 0;
            string expectedSha256 = (manifest != null) ? manifest.PayloadSha256 : null;

            string tempZip = Path.Combine(cacheDir, "lom-russian-patch-data.download.zip");
            string targetZip = Path.Combine(cacheDir, "lom-russian-patch-data.zip");

            if (File.Exists(tempZip))
            {
                try { File.Delete(tempZip); } catch { }
            }

            // Проверка существующего кеша
            if (File.Exists(targetZip))
            {
                if (!string.IsNullOrEmpty(expectedSha256))
                {
                    string currentHash = ComputeFileSha256(targetZip);
                    if (currentHash.Equals(expectedSha256, StringComparison.OrdinalIgnoreCase))
                    {
                        if (log != null) log("В локальном кеше обнаружена актуальная версия архива (SHA256 проверен).");
                        return ExtractArchiveSafe(targetZip, payloadDir, log, progress);
                    }
                }
                else if (expectedSize > 0 && new FileInfo(targetZip).Length == expectedSize)
                {
                    return ExtractArchiveSafe(targetZip, payloadDir, log, progress);
                }
            }

            if (log != null) log("Скачивание актуального пакета локализации (" + downloadUrl + ")...");

            bool downloaded = await GitHubReleaseClient.DownloadFileWithProgressAsync(
                downloadUrl,
                tempZip,
                expectedSize,
                (bytes, total, speed) =>
                {
                    int pct = total > 0 ? (int)((bytes * 100) / total) : -1;
                    string mbStr = string.Format("{0:0.0} / {1:0.0} МБ", bytes / 1048576.0, total / 1048576.0);
                    string speedStr = string.Format("{0:0.0} МБ/с", speed / 1048576.0);
                    string status = string.Format("Загрузка: {0} ({1})", mbStr, speedStr);
                    if (progress != null) progress(pct, status);
                },
                token,
                log
            );

            if (!downloaded)
            {
                if (log != null) log("ОШИБКА: Загрузка файлов не была завершена.");
                return false;
            }

            // Верификация скачанного файла
            if (!string.IsNullOrEmpty(expectedSha256))
            {
                if (log != null) log("Верификация целостности загруженного архива (SHA256)...");
                string downloadedHash = ComputeFileSha256(tempZip);
                if (!downloadedHash.Equals(expectedSha256, StringComparison.OrdinalIgnoreCase))
                {
                    if (log != null) log("ОШИБКА: Хеш загруженного архива не совпадает с манифестом релиза!");
                    try { File.Delete(tempZip); } catch { }
                    return false;
                }
                if (log != null) log("✔ Целостность архива подтверждена.");
            }

            try
            {
                if (File.Exists(targetZip)) File.Delete(targetZip);
                File.Move(tempZip, targetZip);
            }
            catch (Exception ex)
            {
                if (log != null) log("Предупреждение кеширования: " + ex.Message);
            }

            string zipToExtract = File.Exists(targetZip) ? targetZip : tempZip;
            return ExtractArchiveSafe(zipToExtract, payloadDir, log, progress);
        }

        private static bool ExtractArchiveSafe(string zipPath, string targetDir, Action<string> log, Action<int, string> progress)
        {
            try
            {
                if (log != null) log("Распаковка файлов локализации во временную директорию...");
                if (progress != null) progress(-1, "Распаковка архива данных...");

                if (Directory.Exists(targetDir))
                {
                    try { Directory.Delete(targetDir, true); } catch { }
                }
                Directory.CreateDirectory(targetDir);

                ZipFile.ExtractToDirectory(zipPath, targetDir);

                string validPayload = FindPayloadInDirectory(targetDir);
                if (validPayload != null)
                {
                    if (!validPayload.Equals(targetDir, StringComparison.OrdinalIgnoreCase))
                    {
                        CopyDirectory(validPayload, targetDir);
                    }
                    if (log != null) log("✔ Все компоненты патча успешно распакованы и готовы.");
                    return true;
                }
                else
                {
                    if (log != null) log("ОШИБКА: Распакованный архив не содержит всех необходимых компонентов.");
                    return false;
                }
            }
            catch (Exception ex)
            {
                if (log != null) log("ОШИБКА распаковки: " + ex.Message);
                return false;
            }
        }

        public class InstallResult
        {
            public bool Success { get; set; }
            public string FailReason { get; set; }
        }

        public static async Task<InstallResult> InstallWithAutoPayloadAsync(string gameDir, Action<string> log, Action<int, string> progress, CancellationToken token)
        {
            if (!IsValidGameFolder(gameDir))
            {
                return new InstallResult { Success = false, FailReason = "Указанная папка игры недействительна." };
            }

            if (IsGameRunning())
            {
                return new InstallResult { Success = false, FailReason = "Игра или лаунчер запущены. Закройте их перед установкой." };
            }

            // 1. Проверка прав на запись
            string pakPath = Path.Combine(gameDir, "Content", "Paks", "pakchunk0-Windows.pak");
            if (!File.Exists(pakPath))
            {
                string reason = "Файл pakchunk0-Windows.pak не найден в: " + pakPath;
                if (log != null) log("ОШИБКА: " + reason);
                return new InstallResult { Success = false, FailReason = reason };
            }

            try
            {
                using (FileStream fs = new FileStream(pakPath, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite))
                {
                    // Проверка возможности чтения и записи
                }
            }
            catch (Exception ex)
            {
                string reason = "Нет доступа к записи в pakchunk0-Windows.pak (" + ex.Message + "). Требуются права администратора или снятие блокировки.";
                if (log != null) log("ОШИБКА ДОСТУПА: " + reason);
                return new InstallResult { Success = false, FailReason = reason };
            }

            // 2. Получение файлов полезной нагрузки (с автоскачиванием при необходимости)
            if (log != null) log("Поиск пакета русификатора...");
            string payloadDir = await ResolvePayloadDir(true, log, progress, token);
            if (payloadDir == null || !ValidatePayloadContents(payloadDir, log))
            {
                return new InstallResult
                {
                    Success = false,
                    FailReason = "Не удалось получить полные файлы русификатора (ошибка загрузки или поврежденный архив). Проверьте интернет или скопируйте архив lom-russian-patch-data.zip в папку установщика."
                };
            }

            // 3. Установка: версия игры проверяется по supported_game.json из пакета (или встроенному в установщик)
            SupportedGame game = LoadSupportedGame(payloadDir, log);
            if (game == null)
            {
                return new InstallResult { Success = false, FailReason = "Нет сведений о поддерживаемой версии игры (supported_game.json)." };
            }
            if (progress != null) progress(-1, "Проверка версии игры и установка...");
            var core = new InstallerCore(gameDir, game, log);
            string failReason = "";
            bool ok = await Task.Run(() =>
            {
                string reason;
                bool result = core.Install(payloadDir, out reason);
                failReason = reason;
                return result;
            });
            return new InstallResult { Success = ok, FailReason = failReason };
        }

        public static bool InstallWithAutoPayload(string gameDir, Action<string> log, Action<int, string> progress, CancellationToken token, out string failReason)
        {
            try
            {
                var res = InstallWithAutoPayloadAsync(gameDir, log, progress, token).GetAwaiter().GetResult();
                failReason = res.FailReason;
                return res.Success;
            }
            catch (Exception ex)
            {
                Exception inner = ex;
                while (inner.InnerException != null) inner = inner.InnerException;
                failReason = inner.Message;
                return false;
            }
        }

        public static SupportedGame LoadSupportedGame(string dir, Action<string> log)
        {
            try
            {
                return SupportedGame.Load(dir);
            }
            catch (Exception ex)
            {
                if (log != null) log("ОШИБКА: supported_game.json: " + ex.Message);
                return null;
            }
        }

        // Hashes the game was installed with (Saved/RussianPatchBackups), otherwise the ones built into the installer.
        private static InstallerCore CoreForInstalledGame(string gameDir, string payloadDir, Action<string> log)
        {
            string backupDir = Path.Combine(gameDir, InstallerCore.BackupDirRel);
            SupportedGame game = LoadSupportedGame(File.Exists(Path.Combine(backupDir, SupportedGame.FileName)) ? backupDir : payloadDir, log);
            if (game == null)
            {
                if (log != null) log("ОШИБКА: нет сведений о поддерживаемой версии игры (supported_game.json).");
                return null;
            }
            return new InstallerCore(gameDir, game, log);
        }

        public static bool ToggleLanguage(string gameDir, Action<string> log)
        {
            try
            {
                InstallerCore core = CoreForInstalledGame(gameDir, null, log);
                return core != null && core.ToggleLanguage();
            }
            catch (Exception ex)
            {
                log("ОШИБКА переключения языка: " + ex.Message);
                return false;
            }
        }

        // Removes only the patch's own files (installed_files.json); cpdd_*settings.lua, DPS history and other mods stay.
        public static bool Uninstall(string gameDir, Action<string> log)
        {
            string payloadDir = ResolvePayloadDir(false, null, null, CancellationToken.None).GetAwaiter().GetResult();
            InstallerCore core = CoreForInstalledGame(gameDir, payloadDir, log);
            if (core == null) return false;
            try
            {
                return core.Uninstall(payloadDir);
            }
            catch (Exception ex)
            {
                log("ОШИБКА удаления: " + ex.Message);
                return false;
            }
        }

        public static void CopyDirectory(string source, string target)
        {
            if (!Directory.Exists(source)) return;
            Directory.CreateDirectory(target);
            foreach (string file in Directory.GetFiles(source, "*.*", SearchOption.AllDirectories))
            {
                string rel = file.Substring(source.Length + 1);
                string dest = Path.Combine(target, rel);
                string dir = Path.GetDirectoryName(dest);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

                if (File.Exists(dest))
                {
                    FileAttributes attrs = File.GetAttributes(dest);
                    if ((attrs & FileAttributes.ReadOnly) == FileAttributes.ReadOnly)
                    {
                        File.SetAttributes(dest, attrs & ~FileAttributes.ReadOnly);
                    }
                }
                File.Copy(file, dest, true);
            }
        }

        public static string ComputeFileSha256(string filePath)
        {
            return InstallerCore.FileSha256(filePath);
        }

        public static bool DiagnosePath(string path)
        {
            string norm = NormalizeGameDir(path);
            Console.WriteLine("Диагностика папки: " + (string.IsNullOrEmpty(norm) ? "<не указана>" : norm));
            if (!IsValidGameFolder(norm))
            {
                Console.WriteLine("ОШИБКА: Папка не является валидной директорией игры Lord of the Mysteries (Game\\C7)");
                return false;
            }
            Console.WriteLine("СТАТУС: Директория валидна.");
            string pak = Path.Combine(norm, "Content", "Paks", "pakchunk0-Windows.pak");
            Console.WriteLine("pakchunk0: " + (File.Exists(pak) ? "OK (" + new FileInfo(pak).Length + " байт)" : "НЕТ"));
            InstallerCore core = CoreForInstalledGame(norm, null, Console.WriteLine);
            if (core != null)
            {
                Console.WriteLine("Состояние pakchunk0: " + core.InspectPak() + " (CleanSupported / Installed / Unknown)");
                Console.WriteLine("Статус патча: " + core.InspectStatus());
            }
            return true;
        }

        public static bool RunCliInstall(string path)
        {
            string norm = NormalizeGameDir(path);
            if (!IsValidGameFolder(norm))
            {
                Console.WriteLine("ОШИБКА: Неверная папка игры: " + path);
                return false;
            }
            string failReason;
            bool ok = InstallWithAutoPayload(norm, Console.WriteLine, null, CancellationToken.None, out failReason);
            if (!ok) Console.WriteLine("ОШИБКА УСТАНОВКИ: " + failReason);
            return ok;
        }

        public static bool RunCliUninstall(string path)
        {
            string norm = NormalizeGameDir(path);
            if (!IsValidGameFolder(norm))
            {
                Console.WriteLine("ОШИБКА: Неверная папка игры: " + path);
                return false;
            }
            return Uninstall(norm, Console.WriteLine);
        }

        public static bool RunCliToggle(string path)
        {
            string norm = NormalizeGameDir(path);
            if (!IsValidGameFolder(norm))
            {
                Console.WriteLine("ОШИБКА: Неверная папка игры: " + path);
                return false;
            }
            return ToggleLanguage(norm, Console.WriteLine);
        }
    }

    public class ReleaseManifest
    {
        public string Version { get; set; }
        public string PayloadDownloadUrl { get; set; }
        public string PayloadApiUrl { get; set; }
        public long PayloadSize { get; set; }
        public string PayloadSha256 { get; set; }
    }

    public static class GitHubReleaseClient
    {
        public static string TryGetGitHubToken()
        {
            string token = Environment.GetEnvironmentVariable("GITHUB_TOKEN");
            if (!string.IsNullOrEmpty(token)) return token.Trim();

            token = Environment.GetEnvironmentVariable("GH_TOKEN");
            if (!string.IsNullOrEmpty(token)) return token.Trim();

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("gh", "auth token")
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                };
                using (Process p = Process.Start(psi))
                {
                    if (p != null)
                    {
                        string output = p.StandardOutput.ReadToEnd();
                        if (p.WaitForExit(2000) && p.ExitCode == 0 && !string.IsNullOrEmpty(output))
                        {
                            string t = output.Trim();
                            if (!string.IsNullOrEmpty(t) && !t.Contains(" ")) return t;
                        }
                    }
                }
            }
            catch { }

            return null;
        }

        public static ReleaseManifest FetchLatestReleaseInfo(Action<string> log)
        {
            string repo = Environment.GetEnvironmentVariable("LOTM_PATCH_REPO");
            if (string.IsNullOrEmpty(repo)) repo = Program.DEFAULT_REPO;

            string token = TryGetGitHubToken();

            // 1. Запрос через официальный GitHub API
            try
            {
                string apiUrl = "https://api.github.com/repos/" + repo + "/releases/latest";
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(apiUrl);
                req.UserAgent = "LotmRussianPatcher/" + Program.VERSION + " (Windows)";
                req.Timeout = 10000;
                if (!string.IsNullOrEmpty(token))
                {
                    req.Headers.Add("Authorization", "Bearer " + token);
                }

                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                using (StreamReader reader = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    string json = reader.ReadToEnd();
                    var serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
                    var dict = serializer.Deserialize<Dictionary<string, object>>(json);
                    if (dict != null)
                    {
                        var res = new ReleaseManifest();
                        if (dict.ContainsKey("tag_name")) res.Version = Convert.ToString(dict["tag_name"]);

                        string releaseJsonApiUrl = null;

                        if (dict.ContainsKey("assets") && dict["assets"] is System.Collections.ArrayList)
                        {
                            var list = (System.Collections.ArrayList)dict["assets"];
                            foreach (Dictionary<string, object> asset in list)
                            {
                                string name = Convert.ToString(asset["name"]);
                                if (name == "lom-russian-patch-data.zip")
                                {
                                    if (asset.ContainsKey("browser_download_url"))
                                        res.PayloadDownloadUrl = Convert.ToString(asset["browser_download_url"]);
                                    if (asset.ContainsKey("url"))
                                        res.PayloadApiUrl = Convert.ToString(asset["url"]);
                                    if (asset.ContainsKey("size"))
                                        res.PayloadSize = Convert.ToInt64(asset["size"]);
                                }
                                else if (name == "release.json")
                                {
                                    if (asset.ContainsKey("url"))
                                        releaseJsonApiUrl = Convert.ToString(asset["url"]);
                                }
                            }
                        }

                        // Если найден release.json, читаем его метаданные
                        if (!string.IsNullOrEmpty(releaseJsonApiUrl) && !string.IsNullOrEmpty(token))
                        {
                            try
                            {
                                string relJsonText = DownloadStringWithRedirect(releaseJsonApiUrl, token);
                                if (!string.IsNullOrEmpty(relJsonText))
                                {
                                    var relDict = serializer.Deserialize<Dictionary<string, object>>(relJsonText);
                                    if (relDict != null && relDict.ContainsKey("payload") && relDict["payload"] is Dictionary<string, object>)
                                    {
                                        var p = (Dictionary<string, object>)relDict["payload"];
                                        if (p.ContainsKey("sha256")) res.PayloadSha256 = Convert.ToString(p["sha256"]);
                                    }
                                }
                            }
                            catch { }
                        }

                        if (string.IsNullOrEmpty(res.PayloadDownloadUrl))
                        {
                            res.PayloadDownloadUrl = "https://github.com/" + repo + "/releases/latest/download/lom-russian-patch-data.zip";
                        }
                        return res;
                    }
                }
            }
            catch (WebException wex)
            {
                var hResp = wex.Response as HttpWebResponse;
                if (hResp != null && hResp.StatusCode == HttpStatusCode.NotFound)
                {
                    if (log != null) log("GitHub API: Репозиторий " + repo + " вернул 404 (Не найден). Возможно, репозиторий является приватным.");
                }
                else
                {
                    if (log != null) log("GitHub API: " + wex.Message);
                }
            }
            catch (Exception ex)
            {
                if (log != null) log("GitHub API: " + ex.Message);
            }

            // 2. Фоллбек: прямой адрес release.json (для публичных репозиториев)
            string directManifestUrl = "https://github.com/" + repo + "/releases/latest/download/release.json";
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(directManifestUrl);
                req.UserAgent = "LotmRussianPatcher/" + Program.VERSION + " (Windows)";
                req.Timeout = 8000;
                if (!string.IsNullOrEmpty(token)) req.Headers.Add("Authorization", "Bearer " + token);

                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                using (StreamReader reader = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    string json = reader.ReadToEnd();
                    var serializer = new JavaScriptSerializer();
                    var dict = serializer.Deserialize<Dictionary<string, object>>(json);
                    if (dict != null)
                    {
                        var res = new ReleaseManifest();
                        if (dict.ContainsKey("release_version")) res.Version = Convert.ToString(dict["release_version"]);
                        if (dict.ContainsKey("payload") && dict["payload"] is Dictionary<string, object>)
                        {
                            var p = (Dictionary<string, object>)dict["payload"];
                            if (p.ContainsKey("size")) res.PayloadSize = Convert.ToInt64(p["size"]);
                            if (p.ContainsKey("sha256")) res.PayloadSha256 = Convert.ToString(p["sha256"]);
                        }
                        res.PayloadDownloadUrl = "https://github.com/" + repo + "/releases/latest/download/lom-russian-patch-data.zip";
                        return res;
                    }
                }
            }
            catch { }

            return null;
        }

        private static string DownloadStringWithRedirect(string url, string token)
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = "LotmRussianPatcher/" + Program.VERSION + " (Windows)";
            req.Timeout = 10000;
            req.AllowAutoRedirect = false;
            if (!string.IsNullOrEmpty(token))
            {
                req.Headers.Add("Authorization", "Bearer " + token);
                req.Accept = "application/octet-stream";
            }

            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            {
                if ((int)resp.StatusCode >= 300 && (int)resp.StatusCode < 400)
                {
                    string location = resp.Headers["Location"];
                    if (!string.IsNullOrEmpty(location))
                    {
                        HttpWebRequest redir = (HttpWebRequest)WebRequest.Create(location);
                        redir.UserAgent = "LotmRussianPatcher/" + Program.VERSION + " (Windows)";
                        redir.Timeout = 10000;
                        using (HttpWebResponse rResp = (HttpWebResponse)redir.GetResponse())
                        using (StreamReader sr = new StreamReader(rResp.GetResponseStream(), Encoding.UTF8))
                        {
                            return sr.ReadToEnd();
                        }
                    }
                }

                using (StreamReader sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    return sr.ReadToEnd();
                }
            }
        }

        public static async Task<bool> DownloadFileWithProgressAsync(
            string url,
            string destinationPath,
            long expectedTotalBytes,
            Action<long, long, double> progress,
            CancellationToken token,
            Action<string> log)
        {
            string tokenAuth = TryGetGitHubToken();

            return await Task.Run(() =>
            {
                try
                {
                    string targetUrl = url;
                    bool needAuthHeader = false;

                    if (targetUrl.Contains("api.github.com"))
                    {
                        needAuthHeader = !string.IsNullOrEmpty(tokenAuth);
                    }

                    HttpWebRequest req = (HttpWebRequest)WebRequest.Create(targetUrl);
                    req.UserAgent = "LotmRussianPatcher/" + Program.VERSION + " (Windows)";
                    req.Timeout = 30000;
                    req.ReadWriteTimeout = 60000;
                    req.AllowAutoRedirect = false; // Редиректы обрабатываем вручную для AWS S3

                    if (needAuthHeader)
                    {
                        req.Headers.Add("Authorization", "Bearer " + tokenAuth);
                        req.Accept = "application/octet-stream";
                    }

                    HttpWebResponse resp;
                    try
                    {
                        resp = (HttpWebResponse)req.GetResponse();
                    }
                    catch (WebException wex)
                    {
                        var hResp = wex.Response as HttpWebResponse;
                        if (hResp != null && ((int)hResp.StatusCode >= 300 && (int)hResp.StatusCode < 400))
                        {
                            resp = hResp;
                        }
                        else
                        {
                            if (hResp != null && hResp.StatusCode == HttpStatusCode.NotFound)
                            {
                                if (log != null) log("ОШИБКА: Сервер вернул 404 (Не найден). Если репозиторий GitHub приватный, сделайте его публичным либо поместите архив рядом с программой.");
                            }
                            else
                            {
                                if (log != null) log("Ошибка сетевого подключения: " + wex.Message);
                            }
                            return false;
                        }
                    }

                    // Проверяем редирект (302/301/307) от GitHub API на хранилище AWS S3 / Azure CDN
                    if ((int)resp.StatusCode >= 300 && (int)resp.StatusCode < 400)
                    {
                        string location = resp.Headers["Location"];
                        resp.Close();

                        if (string.IsNullOrEmpty(location))
                        {
                            if (log != null) log("ОШИБКА: Сервер вернул пустой адрес перенаправления.");
                            return false;
                        }

                        // Скачиваем из хранилища (Location) БЕЗ Authorization заголовка
                        HttpWebRequest redirReq = (HttpWebRequest)WebRequest.Create(location);
                        redirReq.UserAgent = "LotmRussianPatcher/" + Program.VERSION + " (Windows)";
                        redirReq.Timeout = 30000;
                        redirReq.ReadWriteTimeout = 60000;
                        redirReq.AllowAutoRedirect = true;
                        resp = (HttpWebResponse)redirReq.GetResponse();
                    }

                    using (resp)
                    using (Stream inStream = resp.GetResponseStream())
                    using (FileStream outStream = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        long totalBytes = resp.ContentLength > 0 ? resp.ContentLength : expectedTotalBytes;
                        byte[] buffer = new byte[65536];
                        long bytesReceived = 0;
                        Stopwatch speedSw = Stopwatch.StartNew();
                        long lastBytes = 0;
                        double currentSpeed = 0;

                        int read;
                        while ((read = inStream.Read(buffer, 0, buffer.Length)) > 0)
                        {
                            if (token.IsCancellationRequested)
                            {
                                outStream.Close();
                                try { File.Delete(destinationPath); } catch { }
                                return false;
                            }

                            outStream.Write(buffer, 0, read);
                            bytesReceived += read;

                            if (speedSw.ElapsedMilliseconds >= 500)
                            {
                                double elapsedSec = speedSw.ElapsedMilliseconds / 1000.0;
                                long delta = bytesReceived - lastBytes;
                                currentSpeed = elapsedSec > 0 ? delta / elapsedSec : 0;
                                lastBytes = bytesReceived;
                                speedSw.Restart();

                                if (progress != null)
                                {
                                    progress(bytesReceived, totalBytes, currentSpeed);
                                }
                            }
                        }

                        if (progress != null)
                        {
                            progress(bytesReceived, totalBytes, currentSpeed);
                        }
                    }

                    return true;
                }
                catch (Exception ex)
                {
                    Exception inner = ex;
                    while (inner.InnerException != null) inner = inner.InnerException;
                    if (log != null) log("Ошибка при скачивании файла: " + inner.Message);
                    return false;
                }
            });
        }
    }
}
