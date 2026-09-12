using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

namespace LotmDiagnostics
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
                Console.WriteLine("Lord of the Mysteries — Утилита сбора логов и дампа текстур v2.6-RU");
                Console.WriteLine("Использование:");
                Console.WriteLine("  --smoke                      Проверка работоспособности приложения");
                Console.WriteLine("  --deploy [путь_к_игре]       Развернуть логгер и дампер текстур в игру");
                Console.WriteLine("  --collect [путь_к_игре]      Собрать все логи и сдампленные текстуры в архив");
                return 0;
            }

            if (cmd == "--smoke")
            {
                Console.WriteLine("DIAGNOSTIC_TOOL_SMOKE_OK csharp=winforms target=.net40");
                return 0;
            }

            string gamePath = args.Length > 1 ? args[1] : DiagnosticEngine.AutoDetectGamePath();
            if (string.IsNullOrEmpty(gamePath) || !Directory.Exists(gamePath))
            {
                Console.WriteLine("ERROR: Game directory not found or invalid: " + gamePath);
                return 1;
            }

            if (cmd == "--deploy")
            {
                bool ok = DiagnosticEngine.DeployDiagnostics(gamePath, Console.WriteLine);
                return ok ? 0 : 1;
            }

            if (cmd == "--collect")
            {
                string outZip = DiagnosticEngine.CollectReport(gamePath, Console.WriteLine);
                return !string.IsNullOrEmpty(outZip) ? 0 : 1;
            }

            Console.WriteLine("Неизвестная команда: " + cmd);
            return 1;
        }
    }

    public static class DiagnosticEngine
    {
        public const int PAK_OFFSET = 427225161;
        public const int PAK_BLOCK_SIZE = 4660;
        public const string ORIGINAL_PAK_SHA256 = "566e72d677fc974ab172eb71a34cdc6623f1e0dd19d978de812a76a1820b7fc7";
        public const string PATCHED_PAK_SHA256 = "c031726986e09358bb18ff8a2b8ee5f0b4e65ce8ae8331eed2d7575c80b7efa9";

        public static string AutoDetectGamePath()
        {
            // 1. Проверяем запущенные процессы
            try
            {
                foreach (string procName in new[] { "C7-Win64-Shipping", "C7", "Lord of Mysteries" })
                {
                    Process[] procs = Process.GetProcessesByName(procName);
                    if (procs.Length > 0 && procs[0].MainModule != null)
                    {
                        string exePath = procs[0].MainModule.FileName;
                        string dir = Path.GetDirectoryName(exePath);
                        // Проверяем вверх по дереву папок
                        for (int i = 0; i < 4 && !string.IsNullOrEmpty(dir); i++)
                        {
                            if (IsValidGameDir(dir)) return dir;
                            dir = Path.GetDirectoryName(dir);
                        }
                    }
                }
            }
            catch { }

            // 2. Стандартные пути установки
            string[] candidates = {
                @"D:\Games\GMZZLauncher\Game\C7",
                @"D:\Game\Lord of Mysteries",
                @"D:\Games\Lord of Mysteries",
                @"D:\Lord of Mysteries",
                @"C:\Games\GMZZLauncher\Game\C7",
                @"C:\Game\Lord of Mysteries",
                @"C:\Games\Lord of Mysteries",
                @"C:\Program Files\Lord of Mysteries",
                @"C:\Program Files (x86)\Lord of Mysteries"
            };

            foreach (string p in candidates)
            {
                if (IsValidGameDir(p)) return p;
            }

            // 3. Поиск по реестру Windows
            try
            {
                string[] regKeys = {
                    @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                    @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
                };
                foreach (string rk in regKeys)
                {
                    using (RegistryKey baseKey = Registry.LocalMachine.OpenSubKey(rk))
                    {
                        if (baseKey == null) continue;
                        foreach (string subKeyName in baseKey.GetSubKeyNames())
                        {
                            using (RegistryKey subKey = baseKey.OpenSubKey(subKeyName))
                            {
                                if (subKey == null) continue;
                                object dispName = subKey.GetValue("DisplayName");
                                object instDir = subKey.GetValue("InstallLocation");
                                if (dispName != null && dispName.ToString().IndexOf("Mysteries", StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    if (instDir != null && IsValidGameDir(instDir.ToString()))
                                        return instDir.ToString();
                                }
                            }
                        }
                    }
                }
            }
            catch { }

            return "";
        }

        public static bool IsValidGameDir(string dir)
        {
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return false;
            if (File.Exists(Path.Combine(dir, "Content", "Paks", "pakchunk0-Windows.pak"))) return true;
            if (Directory.Exists(Path.Combine(dir, "Content", "Paks"))) return true;
            if (File.Exists(Path.Combine(dir, "Game", "C7", "Content", "Paks", "pakchunk0-Windows.pak"))) return true;
            return false;
        }

        public static string NormalizeGameDir(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return "";
            raw = raw.Trim('"', ' ', '\t');
            if (File.Exists(Path.Combine(raw, "Game", "C7", "Content", "Paks", "pakchunk0-Windows.pak")))
            {
                return Path.Combine(raw, "Game", "C7");
            }
            return raw;
        }

        public static string CheckPakStatus(string gameDir)
        {
            string pakPath = Path.Combine(gameDir, "Content", "Paks", "pakchunk0-Windows.pak");
            if (!File.Exists(pakPath)) return "PAK_NOT_FOUND";

            try
            {
                using (FileStream fs = new FileStream(pakPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    if (fs.Length < PAK_OFFSET + PAK_BLOCK_SIZE) return "PAK_CORRUPTED";
                    fs.Position = PAK_OFFSET;
                    byte[] buf = new byte[PAK_BLOCK_SIZE];
                    fs.Read(buf, 0, PAK_BLOCK_SIZE);

                    using (SHA256 sha = SHA256.Create())
                    {
                        byte[] hash = sha.ComputeHash(buf);
                        StringBuilder sb = new StringBuilder();
                        foreach (byte b in hash) sb.Append(b.ToString("x2"));
                        string h = sb.ToString();

                        if (h == PATCHED_PAK_SHA256) return "PATCHED";
                        if (h == ORIGINAL_PAK_SHA256) return "ORIGINAL";
                        return "MODIFIED (" + h.Substring(0, 8) + "...)";
                    }
                }
            }
            catch (Exception ex)
            {
                return "ERROR: " + ex.Message;
            }
        }

        public static string ResolvePayloadDir()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] candidates = {
                Path.Combine(baseDir, "patch_payload"),
                Path.Combine(baseDir, "..", "patch_payload"),
                @"d:\gameDev\AbsoluteRU\patch_payload"
            };

            foreach (string c in candidates)
            {
                try
                {
                    string full = Path.GetFullPath(c);
                    if (Directory.Exists(full) && File.Exists(Path.Combine(full, "Saved", "Mods", "bootstrap.lua")))
                    {
                        return full;
                    }
                }
                catch { }
            }
            return "";
        }

        public static bool DeployDiagnostics(string gameDir, Action<string> log)
        {
            log("=== Развертывание логгера и дампера текстур ===");
            gameDir = NormalizeGameDir(gameDir);

            if (!IsValidGameDir(gameDir))
            {
                log("ОШИБКА: Некорректная папка игры: " + gameDir);
                return false;
            }

            string payloadDir = ResolvePayloadDir();
            if (string.IsNullOrEmpty(payloadDir))
            {
                log("ОШИБКА: Не найдена папка patch_payload с файлами мода!");
                return false;
            }

            try
            {
                string targetModsDir = Path.Combine(gameDir, "Saved", "Mods");
                string targetFixesDir = Path.Combine(targetModsDir, "lua", "mods", "cpdd_runtime_fixes");
                string targetLogsDir = Path.Combine(targetModsDir, "Logs");
                string targetDumpDir = Path.Combine(targetModsDir, "DumpedTextures");

                Directory.CreateDirectory(targetFixesDir);
                Directory.CreateDirectory(targetLogsDir);
                Directory.CreateDirectory(targetDumpDir);

                // 1. Копируем TextureDumper.lua
                string dumperSource = Path.Combine(payloadDir, "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes", "TextureDumper.lua");
                string dumperDest = Path.Combine(targetFixesDir, "TextureDumper.lua");
                if (File.Exists(dumperSource))
                {
                    File.Copy(dumperSource, dumperDest, true);
                    log("[OK] TextureDumper.lua скопирован в: " + dumperDest);
                }

                // 2. Копируем TextDiagnostics.lua
                string diagSource = Path.Combine(payloadDir, "Saved", "Mods", "lua", "mods", "cpdd_runtime_fixes", "TextDiagnostics.lua");
                string diagDest = Path.Combine(targetFixesDir, "TextDiagnostics.lua");
                if (File.Exists(diagSource))
                {
                    File.Copy(diagSource, diagDest, true);
                    log("[OK] TextDiagnostics.lua скопирован в: " + diagDest);
                }

                // 3. Создаем/обновляем cpdd_diagnostic_config.json
                string configPath = Path.Combine(targetModsDir, "cpdd_diagnostic_config.json");
                string configJson = "{\n  \"texture_dump_dir\": \"" + targetDumpDir.Replace("\\", "/") + "\",\n  \"log_dir\": \"" + targetLogsDir.Replace("\\", "/") + "\"\n}\n";
                File.WriteAllText(configPath, configJson, Encoding.UTF8);
                log("[OK] cpdd_diagnostic_config.json настроен.");

                // 4. Копируем/обновляем cpdd_user_settings.lua
                string userSettingsSource = Path.Combine(payloadDir, "Saved", "Mods", "lua", "cpdd_user_settings.lua");
                string userSettingsDest = Path.Combine(targetModsDir, "lua", "cpdd_user_settings.lua");
                if (File.Exists(userSettingsSource))
                {
                    File.Copy(userSettingsSource, userSettingsDest, true);
                    log("[OK] cpdd_user_settings.lua активирован (DiagnosticsMode=true, PerformanceMode=false).");
                }

                // 5. Регистрируем модули в manifest.lua
                string manifestPath = Path.Combine(targetModsDir, "manifest.lua");
                if (File.Exists(manifestPath))
                {
                    string content = File.ReadAllText(manifestPath, Encoding.UTF8);
                    bool changed = false;

                    if (!content.Contains("mods.cpdd_runtime_fixes.TextDiagnostics"))
                    {
                        content = Regex.Replace(content, @"(""mods\.cpdd_runtime_fixes\.Init"",?)", "$1\n        \"mods.cpdd_runtime_fixes.TextDiagnostics\",");
                        changed = true;
                    }
                    if (!content.Contains("mods.cpdd_runtime_fixes.TextureDumper"))
                    {
                        content = Regex.Replace(content, @"(""mods\.cpdd_runtime_fixes\.TextDiagnostics"",?)", "$1\n        \"mods.cpdd_runtime_fixes.TextureDumper\",");
                        changed = true;
                    }

                    if (changed)
                    {
                        File.WriteAllText(manifestPath, content, Encoding.UTF8);
                        log("[OK] manifest.lua обновлен: модули диагностики и дампа зарегистрированы.");
                    }
                    else
                    {
                        log("[OK] manifest.lua уже содержит необходимые модули.");
                    }
                }

                // 6. Проверяем статус pak-файла
                string pakStatus = CheckPakStatus(gameDir);
                if (pakStatus == "ORIGINAL")
                {
                    log("\n[ВНИМАНИЕ] Файл pakchunk0-Windows.pak в исходном (не пропатченном) состоянии!");
                    log("  Мод-лоадер не сможет запуститься без активации моста.");
                    log("  Рекомендуется запустить установщик Lord-of-Mysteries-Russian-Patch.exe и нажать 'Установить'.");
                }
                else if (pakStatus == "PATCHED")
                {
                    log("[OK] Мост No-Injection Bootstrap активен в pakchunk0-Windows.pak.");
                }

                log("\nРазвертывание успешно завершено! Теперь запустите игру.");
                log("Модули будут автоматически перехватывать строки и выгружать текстуры во время игры.");
                return true;
            }
            catch (Exception ex)
            {
                log("ОШИБКА при развертывании: " + ex.Message);
                return false;
            }
        }

        public static string CollectReport(string gameDir, Action<string> log)
        {
            log("=== Сбор логов и сдампленных текстур ===");
            gameDir = NormalizeGameDir(gameDir);

            string timeStamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");

            // Папка для отчета
            string outBaseDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "temp");
            if (!Directory.Exists(outBaseDir))
            {
                outBaseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "LOTM_Diagnostics");
            }
            string reportDir = Path.Combine(outBaseDir, "LOTM_Report_" + timeStamp);
            string texturesSubDir = Path.Combine(reportDir, "DumpedTextures");
            string logsSubDir = Path.Combine(reportDir, "Logs");

            Directory.CreateDirectory(reportDir);
            Directory.CreateDirectory(texturesSubDir);
            Directory.CreateDirectory(logsSubDir);

            int logsCopied = 0;
            int texturesCopied = 0;

            // 1. Копируем наш специализированный лог lom_diagnostics.log
            string diagLogPath = Path.Combine(gameDir, "Saved", "Mods", "Logs", "lom_diagnostics.log");
            if (File.Exists(diagLogPath))
            {
                try
                {
                    File.Copy(diagLogPath, Path.Combine(logsSubDir, "lom_diagnostics.log"), true);
                    logsCopied++;
                    log("[OK] Скопирован lom_diagnostics.log (" + new FileInfo(diagLogPath).Length + " байт)");
                }
                catch (Exception ex)
                {
                    log("[WARN] Ошибка копирования lom_diagnostics.log: " + ex.Message);
                }
            }
            else
            {
                log("[WARN] Файл Saved/Mods/Logs/lom_diagnostics.log пока не создан (игра еще не запускалась с логгером).");
            }

            // 2. Копируем нативные логи UE5 из Saved/Logs
            string ue5LogsDir = Path.Combine(gameDir, "Saved", "Logs");
            if (Directory.Exists(ue5LogsDir))
            {
                foreach (string logFile in Directory.GetFiles(ue5LogsDir, "*.log"))
                {
                    try
                    {
                        string fn = Path.GetFileName(logFile);
                        File.Copy(logFile, Path.Combine(logsSubDir, "Game_" + fn), true);
                        logsCopied++;
                        log("[OK] Скопирован лог UE5: " + fn);
                    }
                    catch { }
                }
            }

            // 3. Копируем логи из %LOCALAPPDATA% (если есть)
            try
            {
                string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string[] candidates = {
                    Path.Combine(localApp, "C7", "Saved", "Logs"),
                    Path.Combine(localApp, "LordOfMysteries", "Saved", "Logs")
                };
                foreach (string cand in candidates)
                {
                    if (Directory.Exists(cand))
                    {
                        foreach (string lf in Directory.GetFiles(cand, "*.log"))
                        {
                            string fn = Path.GetFileName(lf);
                            File.Copy(lf, Path.Combine(logsSubDir, "LocalApp_" + fn), true);
                            logsCopied++;
                        }
                    }
                }
            }
            catch { }

            // 4. Копируем текстуры из Saved/Mods/DumpedTextures
            string dumpDir = Path.Combine(gameDir, "Saved", "Mods", "DumpedTextures");
            if (Directory.Exists(dumpDir))
            {
                string[] pngs = Directory.GetFiles(dumpDir, "*.png");
                foreach (string png in pngs)
                {
                    try
                    {
                        File.Copy(png, Path.Combine(texturesSubDir, Path.GetFileName(png)), true);
                        texturesCopied++;
                    }
                    catch { }
                }

                string indexJson = Path.Combine(dumpDir, "dump_index.json");
                if (File.Exists(indexJson))
                {
                    File.Copy(indexJson, Path.Combine(texturesSubDir, "dump_index.json"), true);
                }
                log("[OK] Скопировано текстур PNG: " + texturesCopied);
            }
            else
            {
                log("[INFO] Папка сдампленных текстур пуста или не создана.");
            }

            // 5. Генерируем сводный отчет diagnostic_summary.txt
            string summaryPath = Path.Combine(reportDir, "diagnostic_summary.txt");
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("============================================================");
            sb.AppendLine("   Lord of the Mysteries — Отчет диагностики и дампов UI   ");
            sb.AppendLine("                      Версия 2.6-RU                         ");
            sb.AppendLine("============================================================\n");
            sb.AppendLine("Дата и время сбора: " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            sb.AppendLine("Директория игры:    " + gameDir);
            sb.AppendLine("Статус pakchunk0:   " + CheckPakStatus(gameDir));
            sb.AppendLine("Собрано логов:      " + logsCopied);
            sb.AppendLine("Сдамплено текстур:  " + texturesCopied);
            sb.AppendLine();

            // Анализ файла лога диагностики (если есть)
            string collectedDiagLog = Path.Combine(logsSubDir, "lom_diagnostics.log");
            if (File.Exists(collectedDiagLog))
            {
                sb.AppendLine("--- АНАЛИЗ ПЕРЕХВАТА СТРОК ЛОКАЛИЗАЦИИ ---");
                try
                {
                    string[] lines = File.ReadAllLines(collectedDiagLog, Encoding.UTF8);
                    int totalEng = 0;
                    List<string> sampleEng = new List<string>();
                    foreach (string line in lines)
                    {
                        if (line.Contains("[SUMMARY]"))
                        {
                            sb.AppendLine("Последняя сводка: " + line.Substring(line.IndexOf("[SUMMARY]")));
                        }
                        if (line.Contains("[ENGLISH_RAW]"))
                        {
                            totalEng++;
                            if (sampleEng.Count < 30) sampleEng.Add(line.Substring(line.IndexOf("[ENGLISH_RAW]")));
                        }
                    }
                    sb.AppendLine("Зафиксировано уникальных английских строк на экране: " + totalEng);
                    if (sampleEng.Count > 0)
                    {
                        sb.AppendLine("\nПримеры английских строк из рантайма:");
                        foreach (string s in sampleEng) sb.AppendLine("  * " + s);
                    }
                }
                catch (Exception ex)
                {
                    sb.AppendLine("Ошибка анализа лога: " + ex.Message);
                }
            }
            else
            {
                sb.AppendLine("[ВНИМАНИЕ] Лог lom_diagnostics.log отсутствует!");
                sb.AppendLine("Возможные причины:");
                sb.AppendLine("  1. Игра еще не запускалась после развертывания логгера.");
                sb.AppendLine("  2. Файл pakchunk0-Windows.pak не пропатчен (мод-лоадер не вызвался).");
                sb.AppendLine("  3. Клиент игры запущен из другой директории.");
            }

            File.WriteAllText(summaryPath, sb.ToString(), Encoding.UTF8);
            log("[OK] Сводный отчет записан: " + summaryPath);

            // 6. Упаковка в ZIP-архив
            string zipPath = Path.Combine(outBaseDir, "LOTM_Diagnostics_" + timeStamp + ".zip");
            try
            {
                if (File.Exists(zipPath)) File.Delete(zipPath);
                ZipFile.CreateFromDirectory(reportDir, zipPath, CompressionLevel.Optimal, false);
                log("[OK] Создан архив: " + zipPath + " (" + (new FileInfo(zipPath).Length / 1024) + " КБ)");
            }
            catch (Exception ex)
            {
                log("[WARN] Ошибка упаковки в zip: " + ex.Message);
            }

            log("\n============================================================");
            log("СБОР ЗАВЕРШЕН!");
            log("Папка с результатами: " + reportDir);
            if (File.Exists(zipPath)) log("Архив для отправки:  " + zipPath);
            log("============================================================\n");

            // Открываем папку в проводнике
            try
            {
                Process.Start("explorer.exe", "/select,\"" + (File.Exists(zipPath) ? zipPath : summaryPath) + "\"");
            }
            catch { }

            return File.Exists(zipPath) ? zipPath : reportDir;
        }
    }

    public class MainForm : Form
    {
        private TextBox txtGamePath;
        private Button btnBrowse;
        private Button btnAutoDetect;
        private Label lblPakStatus;
        private Button btnDeploy;
        private Button btnLaunch;
        private Button btnCollect;
        private RichTextBox rtbConsole;

        public MainForm()
        {
            InitializeComponent();
            CheckGameAndStatus();
        }

        private void InitializeComponent()
        {
            this.Text = "Lord of the Mysteries — Диагностика, Сбор логов и Дамп текстур v2.6-RU";
            this.Size = new Size(760, 640);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.BackColor = Color.FromArgb(20, 24, 30);
            this.ForeColor = Color.FromArgb(220, 225, 235);
            this.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);

            // Попытка загрузки иконки
            try
            {
                string iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.ico");
                if (!File.Exists(iconPath)) iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "installer", "app.ico");
                if (File.Exists(iconPath)) this.Icon = new Icon(iconPath);
            }
            catch { }

            // Шапка
            Panel pnlHeader = new Panel
            {
                Location = new Point(0, 0),
                Size = new Size(760, 75),
                BackColor = Color.FromArgb(28, 33, 42)
            };

            Label lblTitle = new Label
            {
                Text = "Повелитель Тайн — Диагностика & Дампер Текстур",
                Font = new Font("Segoe UI", 14f, FontStyle.Bold),
                ForeColor = Color.FromArgb(212, 175, 55),
                Location = new Point(20, 12),
                AutoSize = true
            };

            Label lblSub = new Label
            {
                Text = "Автоматический сбор логов перехвата строк и дамп текстур UI прямо во время игры",
                Font = new Font("Segoe UI", 8.5f, FontStyle.Regular),
                ForeColor = Color.FromArgb(160, 170, 185),
                Location = new Point(22, 42),
                AutoSize = true
            };

            pnlHeader.Controls.Add(lblTitle);
            pnlHeader.Controls.Add(lblSub);
            this.Controls.Add(pnlHeader);

            // Путь к игре
            Label lblPath = new Label
            {
                Text = "Папка с игрой (директория с Content\\Paks или Game\\C7):",
                Location = new Point(20, 88),
                AutoSize = true
            };
            this.Controls.Add(lblPath);

            txtGamePath = new TextBox
            {
                Location = new Point(20, 112),
                Size = new Size(510, 26),
                BackColor = Color.FromArgb(32, 38, 48),
                ForeColor = Color.White,
                BorderStyle = BorderStyle.FixedSingle
            };
            txtGamePath.TextChanged += (s, e) => CheckGameAndStatus();
            this.Controls.Add(txtGamePath);

            btnBrowse = new Button
            {
                Text = "Обзор...",
                Location = new Point(540, 111),
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
                Location = new Point(638, 111),
                Size = new Size(95, 28),
                BackColor = Color.FromArgb(45, 52, 65),
                ForeColor = Color.FromArgb(212, 175, 55),
                FlatStyle = FlatStyle.Flat
            };
            btnAutoDetect.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 98);
            btnAutoDetect.Click += (s, e) => AutoDetect();
            this.Controls.Add(btnAutoDetect);

            // Статус
            lblPakStatus = new Label
            {
                Text = "Статус: Определение директории игры...",
                Location = new Point(20, 148),
                Size = new Size(715, 22),
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(212, 175, 55)
            };
            this.Controls.Add(lblPakStatus);

            // Кнопки действий
            btnDeploy = new Button
            {
                Text = "⚡ 1. Развернуть логгер и дампер",
                Location = new Point(20, 180),
                Size = new Size(230, 42),
                BackColor = Color.FromArgb(35, 75, 55),
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                FlatStyle = FlatStyle.Flat,
                Cursor = Cursors.Hand
            };
            btnDeploy.FlatAppearance.BorderColor = Color.FromArgb(50, 120, 85);
            btnDeploy.Click += BtnDeploy_Click;
            this.Controls.Add(btnDeploy);

            btnLaunch = new Button
            {
                Text = "▶ 2. Запустить игру",
                Location = new Point(260, 180),
                Size = new Size(190, 42),
                BackColor = Color.FromArgb(45, 55, 75),
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                FlatStyle = FlatStyle.Flat,
                Cursor = Cursors.Hand
            };
            btnLaunch.FlatAppearance.BorderColor = Color.FromArgb(70, 90, 130);
            btnLaunch.Click += BtnLaunch_Click;
            this.Controls.Add(btnLaunch);

            btnCollect = new Button
            {
                Text = "📦 3. Собрать логи и текстуры",
                Location = new Point(460, 180),
                Size = new Size(273, 42),
                BackColor = Color.FromArgb(130, 95, 25),
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                FlatStyle = FlatStyle.Flat,
                Cursor = Cursors.Hand
            };
            btnCollect.FlatAppearance.BorderColor = Color.FromArgb(180, 135, 45);
            btnCollect.Click += BtnCollect_Click;
            this.Controls.Add(btnCollect);

            // Консоль логов
            rtbConsole = new RichTextBox
            {
                Location = new Point(20, 235),
                Size = new Size(713, 350),
                BackColor = Color.FromArgb(12, 14, 18),
                ForeColor = Color.FromArgb(200, 210, 225),
                Font = new Font("Consolas", 9f),
                ReadOnly = true,
                BorderStyle = BorderStyle.FixedSingle
            };
            this.Controls.Add(rtbConsole);

            AutoDetect();
        }

        private void AutoDetect()
        {
            string detected = DiagnosticEngine.AutoDetectGamePath();
            if (!string.IsNullOrEmpty(detected))
            {
                txtGamePath.Text = detected;
                LogConsole("[Автопоиск] Найдена папка с игрой: " + detected);
            }
            else
            {
                LogConsole("[Автопоиск] Стандартная папка не найдена. Пожалуйста, укажите путь вручную через 'Обзор...'.");
            }
        }

        private void CheckGameAndStatus()
        {
            string gameDir = DiagnosticEngine.NormalizeGameDir(txtGamePath.Text);
            if (string.IsNullOrEmpty(gameDir) || !DiagnosticEngine.IsValidGameDir(gameDir))
            {
                lblPakStatus.Text = "Статус: Укажите корректную папку игры";
                lblPakStatus.ForeColor = Color.FromArgb(220, 100, 100);
                return;
            }

            string status = DiagnosticEngine.CheckPakStatus(gameDir);
            if (status == "PATCHED")
            {
                lblPakStatus.Text = "Статус: Патч активен (pakchunk0 пропатчен) • Готово к диагностике";
                lblPakStatus.ForeColor = Color.FromArgb(100, 210, 130);
            }
            else if (status == "ORIGINAL")
            {
                lblPakStatus.Text = "Статус: Игра в исходном виде (Патч не установлен!)";
                lblPakStatus.ForeColor = Color.FromArgb(220, 170, 70);
            }
            else
            {
                lblPakStatus.Text = "Статус: pakchunk0: " + status;
                lblPakStatus.ForeColor = Color.FromArgb(220, 170, 70);
            }
        }

        private void BtnBrowse_Click(object sender, EventArgs e)
        {
            using (FolderBrowserDialog fbd = new FolderBrowserDialog())
            {
                fbd.Description = "Выберите папку с установленной игрой Lord of the Mysteries";
                if (fbd.ShowDialog() == DialogResult.OK)
                {
                    txtGamePath.Text = fbd.SelectedPath;
                }
            }
        }

        private void BtnDeploy_Click(object sender, EventArgs e)
        {
            string gameDir = DiagnosticEngine.NormalizeGameDir(txtGamePath.Text);
            if (!DiagnosticEngine.IsValidGameDir(gameDir))
            {
                MessageBox.Show(this, "Пожалуйста, сначала выберите корректную папку игры.", "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            btnDeploy.Enabled = false;
            DiagnosticEngine.DeployDiagnostics(gameDir, LogConsole);
            btnDeploy.Enabled = true;
            CheckGameAndStatus();
        }

        private void BtnLaunch_Click(object sender, EventArgs e)
        {
            string gameDir = DiagnosticEngine.NormalizeGameDir(txtGamePath.Text);
            string[] possibleExes = {
                Path.Combine(gameDir, "Binaries", "Win64", "C7-Win64-Shipping.exe"),
                Path.Combine(gameDir, "Game", "C7", "Binaries", "Win64", "C7-Win64-Shipping.exe"),
                Path.Combine(gameDir, "..", "Launcher", "GMZZLauncher.exe"),
                Path.Combine(gameDir, "Lord of Mysteries.exe")
            };

            string targetExe = null;
            foreach (string exe in possibleExes)
            {
                if (File.Exists(exe))
                {
                    targetExe = exe;
                    break;
                }
            }

            if (targetExe != null)
            {
                try
                {
                    LogConsole("[Запуск] Запуск: " + targetExe);
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = targetExe,
                        WorkingDirectory = Path.GetDirectoryName(targetExe)
                    });
                }
                catch (Exception ex)
                {
                    LogConsole("[ОШИБКА] Не удалось запустить игру: " + ex.Message);
                }
            }
            else
            {
                LogConsole("[ИНФО] Исполняемый файл игры не найден в стандартных путях. Запустите игру через ваш официальный лаунчер.");
                MessageBox.Show(this, "Пожалуйста, запустите игру через ваш привычный лаунчер. Модули логов уже активны и будут перехватывать данные.", "Запустите игру", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void BtnCollect_Click(object sender, EventArgs e)
        {
            string gameDir = DiagnosticEngine.NormalizeGameDir(txtGamePath.Text);
            if (!DiagnosticEngine.IsValidGameDir(gameDir))
            {
                MessageBox.Show(this, "Пожалуйста, сначала выберите корректную папку игры.", "Ошибка", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            btnCollect.Enabled = false;
            string res = DiagnosticEngine.CollectReport(gameDir, LogConsole);
            btnCollect.Enabled = true;

            if (!string.IsNullOrEmpty(res))
            {
                MessageBox.Show(this, "Сбор успешно завершен!\n\nПапка с отчетом и архивом открыта в Проводнике.\nОтправьте созданный ZIP-архив агенту для анализа.", "Успех", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void LogConsole(string msg)
        {
            if (rtbConsole.InvokeRequired)
            {
                rtbConsole.Invoke(new Action<string>(LogConsole), msg);
                return;
            }

            rtbConsole.AppendText(msg + "\n");
            rtbConsole.SelectionStart = rtbConsole.Text.Length;
            rtbConsole.ScrollToCaret();
        }
    }
}
