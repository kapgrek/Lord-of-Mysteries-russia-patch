using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace LotmRussianPatcher
{
    public static class Program
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AttachConsole(int dwProcessId);
        private const int ATTACH_PARENT_PROCESS = -1;

        public const string VERSION = AppInfo.Version;
        public const string DEFAULT_REPO = AppInfo.Repo;

        [STAThread]
        public static int Main(string[] args)
        {
            try
            {
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 /*Tls12*/
                    | (SecurityProtocolType)768 /*Tls11*/
                    | SecurityProtocolType.Tls;
                ServicePointManager.Expect100Continue = true;
            }
            catch { }

            // --payload <folder|zip> may come with any command and with the window.
            var rest = new List<string>();
            for (int i = 0; args != null && i < args.Length; i++)
            {
                if (args[i].Equals("--payload", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) PayloadSource.ExplicitPayload = args[++i];
                else rest.Add(args[i]);
            }

            if (rest.Count > 0)
            {
                try
                {
                    AttachConsole(ATTACH_PARENT_PROCESS);
                    var writer = new StreamWriter(Console.OpenStandardOutput(), Encoding.UTF8) { AutoFlush = true };
                    Console.SetOut(writer);
                    Console.SetError(writer);
                }
                catch { }

                int result = RunCommandLine(rest.ToArray());
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
                Console.WriteLine("  (без аргументов)             Окно установщика");
                Console.WriteLine("  --payload <папка|zip>        Локальный пакет вместо GitHub (с окном и с любой командой)");
                Console.WriteLine("  --verify-bundle --payload …  Проверка пакета (owned_files.json)");
                Console.WriteLine("  --diagnose <путь_к_игре>     Диагностика папки игры");
                Console.WriteLine("  --install <путь_к_игре>      Установка без окна");
                Console.WriteLine("  --uninstall <путь_к_игре>    Удаление русификатора");
                Console.WriteLine("  --download-payload           Скачать последний пакет с GitHub в кеш");
                return 0;
            }

            if (cmd == "--smoke-ui")
            {
                Console.WriteLine("UI_SMOKE_OK native=csharp version=" + VERSION);
                return 0;
            }

            if (cmd == "--verify-bundle") return PatcherBackend.RunCliVerifyBundle();

            if (cmd == "--download-payload")
            {
                ReleaseManifest manifest = PayloadSource.FetchManifest(Console.WriteLine);
                PayloadInfo p = PayloadSource.DownloadAsync(manifest, Console.WriteLine, (pct, s) => Console.Write("\r" + s + "   "), CancellationToken.None).GetAwaiter().GetResult();
                Console.WriteLine();
                if (p == null) { Console.WriteLine("ОШИБКА: Не удалось загрузить пакет."); return 1; }
                Console.WriteLine("УСПЕХ: " + p.Origin + " -> " + p.Dir);
                return 0;
            }

            string path = args.Length > 1 ? args[1] : "";
            if (cmd == "--diagnose") return PatcherBackend.DiagnosePath(path) ? 0 : 1;
            if (cmd == "--install") return PatcherBackend.RunCliInstall(path) ? 0 : 1;
            if (cmd == "--uninstall") return PatcherBackend.RunCliUninstall(path) ? 0 : 1;

            // A bare argument is the game folder to install into.
            return PatcherBackend.RunCliInstall(args[0]) ? 0 : 1;
        }
    }
    public class MainForm : Form
    {
        private TextBox txtGamePath;
        private Button btnBrowse;
        private Button btnAutoDetect;
        private Button btnInstall;
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
                btnRestore.Enabled = false;
                return;
            }

            btnInstall.Enabled = true;

            var status = PatcherBackend.InspectGameStatus(path);
            if (status == GamePatchStatus.InstalledActive)
            {
                lblStatus.Text = "Статус: Русификатор УСТАНОВЛЕН и АКТИВЕН (Русский язык)";
                lblStatus.ForeColor = Color.LightGreen;
                btnRestore.Enabled = true;
            }
            else if (status == GamePatchStatus.InstalledDisabled)
            {
                lblStatus.Text = "Статус: НУЖНО ВОССТАНОВИТЬ ЗАПУСК (нажмите «Установить»)";
                lblStatus.ForeColor = Color.Gold;
                btnRestore.Enabled = true;
            }
            else
            {
                lblStatus.Text = "Статус: Игра обнаружена, готова к установке русской локализации";
                lblStatus.ForeColor = Color.White;
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

            if (PatcherBackend.RunningBlocker() != null)
            {
                MessageBox.Show("Игра или лаунчер сейчас запущены!\n\nПожалуйста, полностью закройте игру перед установкой или обновлением.",
                    "Внимание: Игра запущена", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Блокировка UI
            isOperationRunning = true;
            btnInstall.Enabled = false;
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
                var result = await PatcherBackend.InstallAsync(gamePath, null, Log, UpdateProgressUI, token);
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

        private async void BtnRestore_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!PatcherBackend.IsValidGameFolder(gamePath)) return;

            if (PatcherBackend.RunningBlocker() != null)
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
}
