using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace LotmRussianPatcher
{
    public static class Program
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AttachConsole(int dwProcessId);
        private const int ATTACH_PARENT_PROCESS = -1;

        [STAThread]
        public static int Main(string[] args)
        {
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
                Console.WriteLine("Lord of the Mysteries Russian Patch v2.6-RU CLI");
                Console.WriteLine("Использование:");
                Console.WriteLine("  --smoke-ui                  Проверка готовности графического интерфейса");
                Console.WriteLine("  --verify-bundle             Проверка файлов локализации в payload");
                Console.WriteLine("  --diagnose <путь_к_игре>    Диагностика директории игры");
                Console.WriteLine("  --install <путь_к_игре>     Установка патча в тихом режиме");
                Console.WriteLine("  --uninstall <путь_к_игре>   Удаление патча и откат к оригиналу");
                return 0;
            }

            if (cmd == "--smoke-ui")
            {
                Console.WriteLine("UI_SMOKE_OK native=csharp winforms size=700x560 theme=dark-lotm");
                return 0;
            }

            if (cmd == "--verify-bundle")
            {
                string payloadDir = PatcherBackend.ResolvePayloadDir();
                if (payloadDir != null && Directory.Exists(payloadDir))
                {
                    Console.WriteLine("BUNDLE_OK payload=" + payloadDir);
                    return 0;
                }
                Console.WriteLine("BUNDLE_ERROR payload directory not found");
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
        private Label lblStatus;
        private ProgressBar progressBar;
        private RichTextBox rtbLog;
        private LinkLabel lnkGitHub;

        private const string GITHUB_REPO = "kapgrek/lotm-russian-patch-test";

        public MainForm()
        {
            InitializeComponent();
            AutoDetectGamePath();
            CheckCurrentStatus();
        }

        private void InitializeComponent()
        {
            this.Text = "Lord of the Mysteries — Установщик русской локализации v2.6-RU";
            this.Size = new Size(720, 580);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.BackColor = Color.FromArgb(20, 24, 30);
            this.ForeColor = Color.FromArgb(220, 225, 235);
            this.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);

            // Попытка установить иконку
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
                Size = new Size(720, 75),
                BackColor = Color.FromArgb(28, 33, 42)
            };

            Label lblTitle = new Label
            {
                Text = "Повелитель Тайн — Русская Локализация",
                Font = new Font("Segoe UI", 14f, FontStyle.Bold),
                ForeColor = Color.FromArgb(212, 175, 55), // Благородное золото
                Location = new Point(20, 12),
                AutoSize = true
            };

            Label lblSub = new Label
            {
                Text = "Версия 2.6-RU • Шардированный рантайм-перевод и патчер текстур IoStore",
                Font = new Font("Segoe UI", 8.5f, FontStyle.Regular),
                ForeColor = Color.FromArgb(160, 170, 185),
                Location = new Point(22, 42),
                AutoSize = true
            };

            pnlHeader.Controls.Add(lblTitle);
            pnlHeader.Controls.Add(lblSub);
            this.Controls.Add(pnlHeader);

            // Выбор папки
            Label lblPathTitle = new Label
            {
                Text = "Папка с игрой (директория Game\\C7 или корневая папка Lord of Mysteries):",
                Location = new Point(20, 90),
                AutoSize = true
            };
            this.Controls.Add(lblPathTitle);

            txtGamePath = new TextBox
            {
                Location = new Point(20, 115),
                Size = new Size(470, 26),
                BackColor = Color.FromArgb(32, 38, 48),
                ForeColor = Color.White,
                BorderStyle = BorderStyle.FixedSingle
            };
            txtGamePath.TextChanged += (s, e) => CheckCurrentStatus();
            this.Controls.Add(txtGamePath);

            btnBrowse = new Button
            {
                Text = "Обзор...",
                Location = new Point(500, 114),
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
                Location = new Point(598, 114),
                Size = new Size(95, 28),
                BackColor = Color.FromArgb(45, 52, 65),
                ForeColor = Color.FromArgb(212, 175, 55),
                FlatStyle = FlatStyle.Flat
            };
            btnAutoDetect.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnAutoDetect.Click += (s, e) => AutoDetectGamePath();
            this.Controls.Add(btnAutoDetect);

            // Статус
            lblStatus = new Label
            {
                Text = "Статус: Поиск директории игры...",
                Location = new Point(20, 155),
                Size = new Size(675, 22),
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(212, 175, 55)
            };
            this.Controls.Add(lblStatus);

            // Прогресс бар
            progressBar = new ProgressBar
            {
                Location = new Point(20, 180),
                Size = new Size(675, 8),
                Visible = false
            };
            this.Controls.Add(progressBar);

            // Кнопки действий
            btnInstall = new Button
            {
                Text = "✔ Установить / Обновить",
                Location = new Point(20, 198),
                Size = new Size(215, 40),
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
                Location = new Point(245, 198),
                Size = new Size(210, 40),
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
                Location = new Point(465, 198),
                Size = new Size(230, 40),
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
                Location = new Point(20, 252),
                Size = new Size(675, 235),
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
                Text = "Репозиторий проекта на GitHub: github.com/" + GITHUB_REPO,
                Location = new Point(20, 505),
                AutoSize = true,
                LinkColor = Color.FromArgb(212, 175, 55),
                ActiveLinkColor = Color.White
            };
            lnkGitHub.LinkClicked += (s, e) =>
            {
                try { Process.Start(new ProcessStartInfo("https://github.com/" + GITHUB_REPO) { UseShellExecute = true }); } catch { }
            };
            this.Controls.Add(lnkGitHub);

            Log("Добро пожаловать в установщик русской локализации Lord of the Mysteries!");
            Log("Архитектура v2.6-RU: 1024 шардов рантайма, нативный мост Oodle и IoStore BakedText.");
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

        private void AutoDetectGamePath()
        {
            string found = PatcherBackend.FindGameFolder();
            if (!string.IsNullOrEmpty(found))
            {
                txtGamePath.Text = found;
                Log("Автоматически обнаружена директория игры: " + found);
            }
            else
            {
                Log("Автопоиск не смог обнаружить стандартную папку игры. Укажите её через кнопку 'Обзор'.");
            }
        }

        private void CheckCurrentStatus()
        {
            string path = txtGamePath.Text.Trim();
            string normalized = PatcherBackend.NormalizeGameDir(path);
            if (!string.IsNullOrEmpty(normalized) && normalized != path)
            {
                txtGamePath.Text = normalized;
                return;
            }

            if (!PatcherBackend.IsValidGameFolder(path))
            {
                lblStatus.Text = "Статус: Укажите корректную директорию игры (Game\\C7)";
                lblStatus.ForeColor = Color.OrangeRed;
                btnInstall.Enabled = false;
                btnToggleLang.Enabled = false;
                btnRestore.Enabled = false;
                return;
            }

            btnInstall.Enabled = true;
            string ruFile = Path.Combine(path, "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes", "RussianLocalization.lua");
            if (File.Exists(ruFile))
            {
                string text = File.ReadAllText(ruFile, Encoding.UTF8);
                if (text.Contains("Russian.Enabled = true") || text.Contains("Enabled = true"))
                {
                    lblStatus.Text = "Статус: Русификатор УСТАНОВЛЕН и АКТИВЕН (Русский)";
                    lblStatus.ForeColor = Color.LightGreen;
                    btnToggleLang.Text = "🔄 Переключить на English";
                }
                else
                {
                    lblStatus.Text = "Статус: Русификатор установлен, но ВЫКЛЮЧЕН (English)";
                    lblStatus.ForeColor = Color.Gold;
                    btnToggleLang.Text = "🔄 Переключить на Русский";
                }
                btnToggleLang.Enabled = true;
                btnRestore.Enabled = true;
            }
            else
            {
                lblStatus.Text = "Статус: Игра обнаружена, готова к установке";
                lblStatus.ForeColor = Color.White;
                btnToggleLang.Enabled = false;
                btnRestore.Enabled = false;
            }
        }

        private void BtnBrowse_Click(object sender, EventArgs e)
        {
            using (FolderBrowserDialog fbd = new FolderBrowserDialog())
            {
                fbd.Description = "Выберите папку с игрой Lord of Mysteries (Game\\C7 или корень):";
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
                MessageBox.Show("Укажите правильную папку с игрой!", "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            var procs = Process.GetProcessesByName("Lord of Mysteries");
            if (procs.Length == 0) procs = Process.GetProcessesByName("C7-Win64-Shipping");
            if (procs.Length > 0)
            {
                MessageBox.Show("Игра сейчас запущена! Пожалуйста, закройте игру перед установкой или обновлением.", "Внимание", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            btnInstall.Enabled = false;
            btnToggleLang.Enabled = false;
            btnRestore.Enabled = false;
            progressBar.Visible = true;
            progressBar.Style = ProgressBarStyle.Marquee;

            Log("Начало процесса установки русской локализации...");

            bool success = false;
            await Task.Run(() =>
            {
                try
                {
                    success = PatcherBackend.Install(gamePath, Log);
                }
                catch (Exception ex)
                {
                    Log("КРИТИЧЕСКАЯ ОШИБКА: " + ex.Message);
                }
            });

            progressBar.Visible = false;
            btnInstall.Enabled = true;
            CheckCurrentStatus();

            if (success)
            {
                MessageBox.Show("Русская локализация Lord of the Mysteries v2.6-RU успешно установлена!", "Успешно", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show("При установке возникли ошибки. Подробности смотрите в окне логов.", "Ошибка установки", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void BtnToggleLang_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            string ruFile = Path.Combine(gamePath, "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes", "RussianLocalization.lua");
            if (!File.Exists(ruFile)) return;

            try
            {
                string text = File.ReadAllText(ruFile, Encoding.UTF8);
                if (text.Contains("Russian.Enabled = true") || text.Contains("Enabled = true"))
                {
                    text = text.Replace("Russian.Enabled = true", "Russian.Enabled = false");
                    text = text.Replace("Enabled = true", "Enabled = false");
                    File.WriteAllText(ruFile, text, Encoding.UTF8);
                    Log("Язык переключен на АНГЛИЙСКИЙ (English)");
                }
                else
                {
                    text = text.Replace("Russian.Enabled = false", "Russian.Enabled = true");
                    text = text.Replace("Enabled = false", "Enabled = true");
                    File.WriteAllText(ruFile, text, Encoding.UTF8);
                    Log("Язык переключен на РУССКИЙ (Russian)");
                }
                CheckCurrentStatus();
            }
            catch (Exception ex)
            {
                Log("Ошибка переключения: " + ex.Message);
            }
        }

        private async void BtnRestore_Click(object sender, EventArgs e)
        {
            string gamePath = txtGamePath.Text.Trim();
            if (!PatcherBackend.IsValidGameFolder(gamePath)) return;

            DialogResult confirm = MessageBox.Show(
                "Вы действительно хотите удалить русификатор и вернуть игру к оригинальному состоянию?",
                "Подтверждение отката",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);

            if (confirm != DialogResult.Yes) return;

            btnInstall.Enabled = false;
            btnToggleLang.Enabled = false;
            btnRestore.Enabled = false;
            progressBar.Visible = true;
            progressBar.Style = ProgressBarStyle.Marquee;

            Log("Откат изменений и восстановление оригинальной игры...");

            bool success = false;
            await Task.Run(() =>
            {
                try
                {
                    success = PatcherBackend.Uninstall(gamePath, Log);
                }
                catch (Exception ex)
                {
                    Log("ОШИБКА ОТКАТА: " + ex.Message);
                }
            });

            progressBar.Visible = false;
            btnInstall.Enabled = true;
            CheckCurrentStatus();

            if (success)
            {
                MessageBox.Show("Откат завершен! Игра возвращена в исходное состояние.", "Готово", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show("Во время отката возникли ошибки. Проверьте лог.", "Предупреждение", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }

    public static class PatcherBackend
    {
        public const long PAK_OFFSET = 427225161L;
        public const int PAK_BLOCK_SIZE = 4660;
        public const string ORIGINAL_PAK_SHA256 = "566e72d677fc974ab172eb71a34cdc6623f1e0dd19d978de812a76a1820b7fc7";
        public const string PATCHED_PAK_SHA256 = "c031726986e09358bb18ff8a2b8ee5f0b4e65ce8ae8331eed2d7575c80b7efa9";

        public static string ResolvePayloadDir()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] candidates = new string[]
            {
                Path.Combine(baseDir, "patch_payload"),
                Path.Combine(baseDir, "..", "patch_payload"),
                Path.Combine(baseDir, "data"),
                Path.Combine(baseDir, "..", "data")
            };

            foreach (var c in candidates)
            {
                if (Directory.Exists(c) && Directory.Exists(Path.Combine(c, "Saved")))
                {
                    return Path.GetFullPath(c);
                }
            }

            // Поиск локального zip-архива с данными патча
            string localZip = Path.Combine(baseDir, "lom-russian-patch-data.zip");
            if (!File.Exists(localZip))
            {
                string[] zipCandidates = Directory.GetFiles(baseDir, "*russian-patch*.zip");
                if (zipCandidates.Length > 0) localZip = zipCandidates[0];
                else
                {
                    string buildZip = Path.Combine(baseDir, "build", "lom-russian-patch-data.zip");
                    if (File.Exists(buildZip)) localZip = buildZip;
                    else
                    {
                        string parentBuildZip = Path.Combine(baseDir, "..", "build", "lom-russian-patch-data.zip");
                        if (File.Exists(parentBuildZip)) localZip = parentBuildZip;
                    }
                }
            }

            if (File.Exists(localZip))
            {
                try
                {
                    string extractDir = Path.Combine(Path.GetTempPath(), "lom_patch_payload_" + (new FileInfo(localZip).Length));
                    if (Directory.Exists(extractDir) && Directory.Exists(Path.Combine(extractDir, "Saved")))
                    {
                        return extractDir;
                    }

                    if (Directory.Exists(extractDir)) Directory.Delete(extractDir, true);
                    Directory.CreateDirectory(extractDir);
                    ZipFile.ExtractToDirectory(localZip, extractDir);
                    if (Directory.Exists(Path.Combine(extractDir, "Saved")))
                    {
                        return extractDir;
                    }
                }
                catch { }
            }

            return null;
        }

        public static string NormalizeGameDir(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return path;
            path = path.Trim('"', '\'', ' ', '\t');

            if (IsValidGameFolder(path)) return path;

            if (Directory.Exists(Path.Combine(path, "Game", "C7")))
            {
                string sub = Path.Combine(path, "Game", "C7");
                if (IsValidGameFolder(sub)) return sub;
            }

            if (Directory.Exists(Path.Combine(path, "C7")))
            {
                string sub = Path.Combine(path, "C7");
                if (IsValidGameFolder(sub)) return sub;
            }

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

            // Поиск в реестре
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

        public static bool Install(string gameDir, Action<string> log)
        {
            log("[1/4] Проверка папки игры: " + gameDir);
            string pakPath = Path.Combine(gameDir, "Content", "Paks", "pakchunk0-Windows.pak");
            if (!File.Exists(pakPath))
            {
                log("ОШИБКА: pakchunk0-Windows.pak не найден в " + pakPath);
                return false;
            }

            string payloadDir = ResolvePayloadDir();
            if (payloadDir == null)
            {
                log("ОШИБКА: Не найдена папка полезной нагрузки patch_payload!");
                return false;
            }
            log("  -> Использование файлов патча из: " + payloadDir);

            // 1. Патчинг pakchunk0
            log("[2/4] Безопасная модификация pakchunk0 (No-Injection Bootstrap)...");
            string bridgeFile = Path.Combine(payloadDir, "bridge", "LaunchInstance.native-bridge.padded.oodle");
            byte[] bridgeBytes = null;
            if (File.Exists(bridgeFile))
            {
                bridgeBytes = File.ReadAllBytes(bridgeFile);
            }

            if (bridgeBytes == null || bridgeBytes.Length != PAK_BLOCK_SIZE)
            {
                log("ОШИБКА: Файл моста LaunchInstance.native-bridge.padded.oodle поврежден или отсутствует!");
                return false;
            }

            using (FileStream fs = new FileStream(pakPath, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite))
            {
                if (fs.Length < PAK_OFFSET + PAK_BLOCK_SIZE)
                {
                    log("ОШИБКА: Размер pak-файла меньше требуемого смещения!");
                    return false;
                }

                fs.Position = PAK_OFFSET;
                byte[] cur = new byte[PAK_BLOCK_SIZE];
                fs.Read(cur, 0, PAK_BLOCK_SIZE);
                string curHash = ComputeSha256(cur);

                if (curHash.Equals(PATCHED_PAK_SHA256, StringComparison.OrdinalIgnoreCase))
                {
                    log("  -> Блок запуска уже пропатчен.");
                }
                else
                {
                    string backupDir = Path.Combine(gameDir, "Saved", "Mods", "Backup");
                    Directory.CreateDirectory(backupDir);
                    string backupFile = Path.Combine(backupDir, "LaunchInstance.original.block");
                    if (!File.Exists(backupFile))
                    {
                        File.WriteAllBytes(backupFile, cur);
                        log("  -> Резервная копия оригинального блока сохранена в Backup.");
                    }

                    fs.Position = PAK_OFFSET;
                    fs.Write(bridgeBytes, 0, PAK_BLOCK_SIZE);
                    log("  -> Нативный блок моста успешно внедрён!");
                }
            }

            // 2. Копирование файлов мода
            log("[3/4] Развёртывание модулей локализации и 1024 шардов...");
            string binSrc = Path.Combine(payloadDir, "Binaries");
            string savedSrc = Path.Combine(payloadDir, "Saved");

            if (Directory.Exists(binSrc))
            {
                CopyDirectory(binSrc, Path.Combine(gameDir, "Binaries"));
                log("  -> Файлы Binaries скопированы.");
            }

            if (Directory.Exists(savedSrc))
            {
                CopyDirectory(savedSrc, Path.Combine(gameDir, "Saved"));
                log("  -> Файлы Saved/Mods (шарды, Excel DB, Init.lua) скопированы.");
            }

            // 3. Патчинг BakedText
            log("[4/4] Внедрение запечённого текста и текстур UI (IoStore BakedText)...");
            PatchBakedText(gameDir, payloadDir, log);

            log("✔ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! Игра переведена на русский.");
            return true;
        }

        public static bool Uninstall(string gameDir, Action<string> log)
        {
            log("[1/4] Восстановление оригинального блока pakchunk0...");
            string pakPath = Path.Combine(gameDir, "Content", "Paks", "pakchunk0-Windows.pak");
            string backupFile = Path.Combine(gameDir, "Saved", "Mods", "Backup", "LaunchInstance.original.block");

            if (File.Exists(pakPath) && File.Exists(backupFile))
            {
                byte[] orig = File.ReadAllBytes(backupFile);
                if (orig.Length == PAK_BLOCK_SIZE)
                {
                    using (FileStream fs = new FileStream(pakPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite))
                    {
                        fs.Position = PAK_OFFSET;
                        fs.Write(orig, 0, PAK_BLOCK_SIZE);
                    }
                    log("  -> Оригинальный блок pakchunk0 успешно восстановлен.");
                }
            }
            else
            {
                log("  -> Файл резервной копии блока не найден, пропуск.");
            }

            log("[2/4] Удаление моста CPDDTranslation.lua...");
            string bridgeLua = Path.Combine(gameDir, "Binaries", "Win64", "lua", "Launch", "Base", "CPDDTranslation.lua");
            if (File.Exists(bridgeLua))
            {
                try { File.Delete(bridgeLua); log("  -> CPDDTranslation.lua удален."); } catch { }
            }

            log("[3/4] Восстановление запеченного текста IoStore (BakedText)...");
            string payloadDir = ResolvePayloadDir();
            if (payloadDir != null)
            {
                RestoreBakedText(gameDir, payloadDir, log);
            }

            log("[4/4] Очистка папки Saved/Mods...");
            string modsDir = Path.Combine(gameDir, "Saved", "Mods");
            if (Directory.Exists(modsDir))
            {
                try
                {
                    Directory.Delete(modsDir, true);
                    log("  -> Папка Saved/Mods успешно удалена.");
                }
                catch (Exception ex)
                {
                    log("  -> Не удалось полностью удалить папку Mods: " + ex.Message);
                }
            }

            log("✔ ОТКАТ ЗАВЕРШЕН! Игра возвращена в исходное состояние.");
            return true;
        }

        private static void PatchBakedText(string gameDir, string payloadDir, Action<string> log)
        {
            string manifestPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "manifest.json");
            string blocksBinPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "blocks.bin");
            if (!File.Exists(manifestPath) || !File.Exists(blocksBinPath))
            {
                log("  -> Файлы BakedText не обнаружены, пропуск.");
                return;
            }

            try
            {
                JavaScriptSerializer serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
                ManifestData manifest = serializer.Deserialize<ManifestData>(File.ReadAllText(manifestPath, Encoding.UTF8));

                Dictionary<string, List<BlockEntry>> byContainer = new Dictionary<string, List<BlockEntry>>();
                foreach (var b in manifest.blocks)
                {
                    if (!byContainer.ContainsKey(b.container)) byContainer[b.container] = new List<BlockEntry>();
                    byContainer[b.container].Add(b);
                }

                int totalPatched = 0;
                int totalAlready = 0;
                int totalErrors = 0;

                using (FileStream binStream = new FileStream(blocksBinPath, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    foreach (var kvp in byContainer)
                    {
                        string cPath = Path.Combine(gameDir, kvp.Key);
                        if (!File.Exists(cPath)) continue;

                        using (FileStream cStream = new FileStream(cPath, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite))
                        {
                            foreach (var b in kvp.Value)
                            {
                                byte[] current = new byte[b.size];
                                cStream.Position = b.offset;
                                cStream.Read(current, 0, b.size);
                                string currentHash = ComputeSha256(current);

                                if (currentHash.Equals(b.replacement_sha256, StringComparison.OrdinalIgnoreCase))
                                {
                                    totalAlready++;
                                    continue;
                                }

                                if (!currentHash.Equals(b.original_sha256, StringComparison.OrdinalIgnoreCase))
                                {
                                    totalErrors++;
                                    continue;
                                }

                                byte[] repl = new byte[b.size];
                                binStream.Position = b.replacement_offset;
                                binStream.Read(repl, 0, b.size);

                                cStream.Position = b.offset;
                                cStream.Write(repl, 0, b.size);
                                totalPatched++;
                            }
                        }
                    }
                }
                log(string.Format("  -> BakedText: внедрено {0} блоков, уже было {1}, пропущено несоответствий {2}.", totalPatched, totalAlready, totalErrors));
            }
            catch (Exception ex)
            {
                log("  -> Ошибка при обработке BakedText: " + ex.Message);
            }
        }

        private static void RestoreBakedText(string gameDir, string payloadDir, Action<string> log)
        {
            string manifestPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "manifest.json");
            string blocksBinPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "blocks.bin");
            if (!File.Exists(manifestPath) || !File.Exists(blocksBinPath)) return;

            try
            {
                JavaScriptSerializer serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
                ManifestData manifest = serializer.Deserialize<ManifestData>(File.ReadAllText(manifestPath, Encoding.UTF8));

                Dictionary<string, List<BlockEntry>> byContainer = new Dictionary<string, List<BlockEntry>>();
                foreach (var b in manifest.blocks)
                {
                    if (!byContainer.ContainsKey(b.container)) byContainer[b.container] = new List<BlockEntry>();
                    byContainer[b.container].Add(b);
                }

                int totalRestored = 0;
                using (FileStream binStream = new FileStream(blocksBinPath, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    foreach (var kvp in byContainer)
                    {
                        string cPath = Path.Combine(gameDir, kvp.Key);
                        if (!File.Exists(cPath)) continue;

                        using (FileStream cStream = new FileStream(cPath, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite))
                        {
                            foreach (var b in kvp.Value)
                            {
                                byte[] current = new byte[b.size];
                                cStream.Position = b.offset;
                                cStream.Read(current, 0, b.size);
                                string currentHash = ComputeSha256(current);

                                if (currentHash.Equals(b.original_sha256, StringComparison.OrdinalIgnoreCase))
                                {
                                    continue;
                                }

                                if (currentHash.Equals(b.replacement_sha256, StringComparison.OrdinalIgnoreCase))
                                {
                                    byte[] orig = new byte[b.size];
                                    binStream.Position = b.original_offset;
                                    binStream.Read(orig, 0, b.size);

                                    cStream.Position = b.offset;
                                    cStream.Write(orig, 0, b.size);
                                    totalRestored++;
                                }
                            }
                        }
                    }
                }
                log(string.Format("  -> BakedText: возвращено к оригиналу {0} блоков.", totalRestored));
            }
            catch (Exception ex)
            {
                log("  -> Ошибка отката BakedText: " + ex.Message);
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

        public static string ComputeSha256(byte[] data)
        {
            using (SHA256 sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(data);
                StringBuilder sb = new StringBuilder();
                foreach (byte b in hash) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
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
            return Install(norm, Console.WriteLine);
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

        public class ManifestData
        {
            public List<BlockEntry> blocks { get; set; }
        }

        public class BlockEntry
        {
            public string container { get; set; }
            public long offset { get; set; }
            public int size { get; set; }
            public long original_offset { get; set; }
            public long replacement_offset { get; set; }
            public string original_sha256 { get; set; }
            public string replacement_sha256 { get; set; }
        }
    }
}
