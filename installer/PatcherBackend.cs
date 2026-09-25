using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace LotmRussianPatcher
{
    public class InstallResult
    {
        public bool Success;
        public string FailReason = "";
        public PayloadInfo Payload;
    }

    // Everything the window and the CLI do with a game folder. No UI here.
    public static class PatcherBackend
    {
        public const string PakRel = @"Content\Paks\pakchunk0-Windows.pak";
        public const string ExeRel = @"Binaries\Win64\C7-Win64-Shipping.exe";

        // The launchers may stay open (as with CPDD); the game and the Combat Meter from Saved/Mods may not.
        private static readonly string[] BlockingProcesses = { "C7-Win64-Shipping", "C7", "Lord of Mysteries", GameOptions.CombatMeterProcess };

        // CPDD installer candidates (relative to every fixed drive root) plus older layouts.
        private static readonly string[] CandidateRelPaths =
        {
            @"BiliBili\GMZZLauncher\Game\C7",
            @"GMZZLauncher\Game\C7",
            @"Program Files\GMZZLauncher\Game\C7",
            @"Program Files (x86)\GMZZLauncher\Game\C7",
            @"Games\GMZZLauncher\Game\C7",
            @"Game\GMZZLauncher\Game\C7",
            @"Lord of Mysteries\Game\C7",
            @"Games\Lord of Mysteries\Game\C7",
            @"Game\Lord of Mysteries\Game\C7",
            @"BiliBili\LoTm\Game\C7"
        };

        public static bool IsAdministrator()
        {
            try
            {
                using (var identity = System.Security.Principal.WindowsIdentity.GetCurrent())
                {
                    return new System.Security.Principal.WindowsPrincipal(identity).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
                }
            }
            catch { return false; }
        }

        // Name of a running process that blocks installation, or null.
        public static string RunningBlocker()
        {
            foreach (string name in BlockingProcesses)
            {
                try { if (Process.GetProcessesByName(name).Length > 0) return name; }
                catch { }
            }
            return null;
        }

        public static string BlockerMessage(string process)
        {
            return process == GameOptions.CombatMeterProcess
                ? "Закройте внешний счётчик урона (Lord of Mysteries Combat Meter): он запущен из папки игры."
                : "Игра запущена (" + process + "). Закройте игру; лаунчер можно оставить открытым.";
        }

        // ------------------------------------------------------------ game folder

        public static string NormalizeGameDir(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return path;
            path = path.Trim('"', '\'', ' ', '\t').TrimEnd('\\', '/');
            if (path.Length == 2 && path[1] == ':') path += "\\";
            if (IsValidGameFolder(path)) return path;
            foreach (string sub in new[] { @"Game\C7", "C7", @"GMZZLauncher\Game\C7" })
            {
                string candidate = Path.Combine(path, sub);
                if (IsValidGameFolder(candidate)) return candidate;
            }
            return path;
        }

        public static bool IsValidGameFolder(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return false;
            try
            {
                if (!Directory.Exists(path)) return false;
                return File.Exists(Path.Combine(path, PakRel)) || File.Exists(Path.Combine(path, ExeRel));
            }
            catch { return false; }
        }

        // Auto-detect wants both the pak and the game exe.
        public static bool IsCompleteGameFolder(string path)
        {
            try { return File.Exists(Path.Combine(path, PakRel)) && File.Exists(Path.Combine(path, ExeRel)); }
            catch { return false; }
        }

        // One-line result for the "ПАПКА ИГРЫ" block.
        public static string DescribeFolder(string path, out bool ok)
        {
            ok = false;
            if (string.IsNullOrWhiteSpace(path)) return "Укажите папку игры.";
            if (!Directory.Exists(path)) return "✗ Папка не найдена.";
            if (!File.Exists(Path.Combine(path, ExeRel))) return "✗ В папке нет C7-Win64-Shipping.exe — выберите папку Game\\C7.";
            if (!File.Exists(Path.Combine(path, PakRel))) return "✗ В папке нет Content\\Paks\\pakchunk0-Windows.pak.";
            ok = true;
            return "Папка игры найдена.";
        }

        public static string FindGameFolder()
        {
            string last = LoadLastGameDir();
            if (!string.IsNullOrEmpty(last) && IsCompleteGameFolder(last)) return last;

            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (drive.DriveType != DriveType.Fixed || !drive.IsReady) continue;
                    foreach (string rel in CandidateRelPaths)
                    {
                        string p = Path.Combine(drive.RootDirectory.FullName, rel);
                        if (IsCompleteGameFolder(p)) return p;
                    }
                }
                catch { }
            }

            try
            {
                foreach (RegistryKey hive in new[] { Registry.LocalMachine, Registry.CurrentUser })
                {
                    foreach (string regPath in new[] { @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" })
                    {
                        using (RegistryKey key = hive.OpenSubKey(regPath))
                        {
                            if (key == null) continue;
                            foreach (string sub in key.GetSubKeyNames())
                            {
                                if (sub.IndexOf("Lord", StringComparison.OrdinalIgnoreCase) < 0 && sub.IndexOf("GMZZ", StringComparison.OrdinalIgnoreCase) < 0
                                    && sub.IndexOf("Mysteries", StringComparison.OrdinalIgnoreCase) < 0) continue;
                                using (RegistryKey app = key.OpenSubKey(sub))
                                {
                                    object loc = app == null ? null : app.GetValue("InstallLocation");
                                    if (loc == null) continue;
                                    string n = NormalizeGameDir(loc.ToString());
                                    if (IsCompleteGameFolder(n)) return n;
                                }
                            }
                        }
                    }
                }
            }
            catch { }
            return null;
        }

        private static string SettingsPath { get { return Path.Combine(PayloadSource.AppDataRoot, "settings.json"); } }

        public static string LoadLastGameDir()
        {
            try
            {
                if (!File.Exists(SettingsPath)) return null;
                var d = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(SettingsPath, Encoding.UTF8));
                object v;
                return d != null && d.TryGetValue("last_game_dir", out v) ? Convert.ToString(v) : null;
            }
            catch { return null; }
        }

        public static void SaveLastGameDir(string gameDir)
        {
            try
            {
                Directory.CreateDirectory(PayloadSource.AppDataRoot);
                var d = new Dictionary<string, object> { { "last_game_dir", gameDir } };
                File.WriteAllText(SettingsPath, new JavaScriptSerializer().Serialize(d), new UTF8Encoding(false));
            }
            catch { }
        }

        // ------------------------------------------------------------ state

        public static SupportedGame LoadSupportedGame(string dir, Action<string> log)
        {
            try { return SupportedGame.Load(dir); }
            catch (Exception ex)
            {
                if (log != null) log("ОШИБКА: supported_game.json: " + ex.Message);
                return null;
            }
        }

        // Hashes the game was installed with (Saved/RussianPatchBackups), otherwise the ones built into the installer.
        public static InstallerCore CoreForInstalledGame(string gameDir, string payloadDir, Action<string> log)
        {
            string backupDir = Path.Combine(gameDir, InstallerCore.BackupDirRel);
            SupportedGame game = LoadSupportedGame(File.Exists(Path.Combine(backupDir, SupportedGame.FileName)) ? backupDir : payloadDir, log);
            return game == null ? null : new InstallerCore(gameDir, game, log);
        }

        public static GamePatchStatus InspectGameStatus(string gameDir)
        {
            if (!IsValidGameFolder(gameDir)) return GamePatchStatus.InvalidPath;
            InstallerCore core = CoreForInstalledGame(gameDir, null, null);
            return core == null ? GamePatchStatus.NotInstalled : core.InspectStatus();
        }

        // Game build check for the folder block (sha256 of the whole pak, 0.5-2 s: call off the UI thread).
        public static PakState InspectPak(string gameDir, out string gameBuild)
        {
            gameBuild = null;
            InstallerCore core = CoreForInstalledGame(gameDir, null, null);
            if (core == null) return PakState.Unknown;
            SupportedGame game = LoadSupportedGame(null, null);
            gameBuild = game != null ? game.GameBuild : null;
            return core.InspectPak();
        }

        // VERSION of the installed Init.lua ("2.9.10-RU"), or null.
        public static string InstalledVersion(string gameDir)
        {
            try
            {
                string init = Path.Combine(gameDir, InstallerCore.InitRel);
                if (!File.Exists(init)) return null;
                using (var reader = new StreamReader(init, Encoding.UTF8))
                {
                    for (int i = 0; i < 40; i++)
                    {
                        string line = reader.ReadLine();
                        if (line == null) break;
                        Match m = Regex.Match(line, "^local VERSION = \"([^\"]+)\"");
                        if (m.Success) return m.Groups[1].Value;
                    }
                }
            }
            catch { }
            return null;
        }

        // "2.9.10-RU" < "3.0.0-RU"; unknown formats compare as equal.
        public static int CompareVersions(string a, string b)
        {
            Version va, vb;
            if (!TryParseVersion(a, out va) || !TryParseVersion(b, out vb)) return 0;
            return va.CompareTo(vb);
        }

        private static bool TryParseVersion(string s, out Version v)
        {
            v = null;
            if (string.IsNullOrEmpty(s)) return false;
            Match m = Regex.Match(s, "(\\d+)\\.(\\d+)(?:\\.(\\d+))?");
            if (!m.Success) return false;
            v = new Version(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), m.Groups[3].Success ? int.Parse(m.Groups[3].Value) : 0);
            return true;
        }

        // ------------------------------------------------------------ actions

        // options == null: leave cpdd_patcher_settings.lua and Engine.ini as they are (CLI --install).
        public static async Task<InstallResult> InstallAsync(string gameDir, GameOptionsState options, Action<string> log, Action<int, string> progress, CancellationToken token)
        {
            var result = new InstallResult();
            if (!IsValidGameFolder(gameDir)) { result.FailReason = "Указанная папка не является папкой игры (Game\\C7)."; return result; }
            string blocker = RunningBlocker();
            if (blocker != null) { result.FailReason = BlockerMessage(blocker); return result; }

            string pakPath = Path.Combine(gameDir, PakRel);
            if (!File.Exists(pakPath)) { result.FailReason = "Файл не найден: " + pakPath; return result; }
            try
            {
                using (new FileStream(pakPath, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite)) { }
            }
            catch (Exception ex)
            {
                result.FailReason = "Нет доступа на запись к pakchunk0-Windows.pak (" + ex.Message + ")."
                    + (IsAdministrator() ? "" : " Запустите установщик от имени администратора.");
                return result;
            }

            if (log != null) log("Получение пакета русификатора...");
            PayloadInfo payload = await PayloadSource.ResolveAsync(true, log, progress, token);
            token.ThrowIfCancellationRequested();
            if (payload == null || !PayloadSource.ValidatePayloadContents(payload.Dir, log))
            {
                result.FailReason = "Не удалось получить пакет русификатора. Проверьте интернет или положите " + PayloadSource.DataZipName + " рядом с установщиком.";
                return result;
            }
            result.Payload = payload;
            if (log != null) log(payload.Origin);

            SupportedGame game = LoadSupportedGame(payload.Dir, log);
            if (game == null) { result.FailReason = "Нет сведений о поддерживаемой версии игры (supported_game.json)."; return result; }
            if (progress != null) progress(-1, "Установка...");
            var core = new InstallerCore(gameDir, game, log);
            string reason = "";
            bool ok = await Task.Run(() => core.Install(payload.Dir, out reason));
            result.FailReason = reason;
            result.Success = ok;
            if (ok)
            {
                SaveLastGameDir(gameDir);
                if (options != null)
                {
                    var errors = new List<string>();
                    if (!ApplyOptions(gameDir, options, log, errors) && log != null)
                    {
                        log("Внимание: русификатор установлен, но часть настроек не записана: " + string.Join(" ", errors.ToArray()));
                    }
                }
            }
            return result;
        }

        public static bool ApplyOptions(string gameDir, GameOptionsState options, Action<string> log, List<string> errors)
        {
            if (log != null) log("Запись настроек DPS, чата и Visual Clarity...");
            return new GameOptions(gameDir, log).Apply(options, errors);
        }

        // Removes only the patch's own files (installed_files.json) and the managed Visual Clarity block;
        // cpdd_*settings.lua, DPS history and other mods stay.
        public static bool Uninstall(string gameDir, Action<string> log)
        {
            try
            {
                string blocker = RunningBlocker();
                if (blocker != null) { if (log != null) log(BlockerMessage(blocker)); return false; }
                PayloadInfo payload = PayloadSource.ResolveOffline(null);
                string payloadDir = payload == null ? null : payload.Dir;
                InstallerCore core = CoreForInstalledGame(gameDir, payloadDir, log);
                if (core == null) { if (log != null) log("ОШИБКА: нет сведений о поддерживаемой версии игры (supported_game.json)."); return false; }
                string error;
                bool optionsOk = new GameOptions(gameDir, log).RemoveManagedBlocks(out error);
                bool ok = core.Uninstall(payloadDir);
                return ok && optionsOk;
            }
            catch (Exception ex)
            {
                if (log != null) log("ОШИБКА удаления: " + ex.Message);
                return false;
            }
        }

        public static bool LaunchCombatMeter(string gameDir, out string error)
        {
            error = null;
            string exe = new GameOptions(gameDir, null).CombatMeterPath;
            if (!File.Exists(exe)) { error = "Внешний счётчик не найден: " + exe + ". Установите русификатор."; return false; }
            try
            {
                Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(exe) });
                return true;
            }
            catch (Exception ex)
            {
                error = "Не удалось запустить внешний счётчик: " + ex.Message;
                return false;
            }
        }

        // ------------------------------------------------------------ CLI

        public static bool DiagnosePath(string path)
        {
            string norm = NormalizeGameDir(path);
            Console.WriteLine("Диагностика папки: " + (string.IsNullOrEmpty(norm) ? "<не указана>" : norm));
            bool ok;
            Console.WriteLine(DescribeFolder(norm, out ok));
            if (!IsValidGameFolder(norm)) return false;
            InstallerCore core = CoreForInstalledGame(norm, null, Console.WriteLine);
            if (core != null)
            {
                Console.WriteLine("Состояние pakchunk0: " + core.InspectPak() + " (CleanSupported / Installed / Unknown)");
                Console.WriteLine("Статус патча: " + core.InspectStatus());
                Console.WriteLine("Версия русификатора: " + (InstalledVersion(norm) ?? "-"));
            }
            string error;
            GameOptionsState o = new GameOptions(norm, null).Read(out error);
            Console.WriteLine("Настройки: DPS " + GameOptions.ModeName(o.DpsMode) + ", чат " + o.DesktopChat + ", Visual Clarity " + o.VisualClarity + (error != null ? " (" + error + ")" : ""));
            return true;
        }

        public static bool RunCliInstall(string path)
        {
            string norm = NormalizeGameDir(path);
            if (!IsValidGameFolder(norm)) { Console.WriteLine("ОШИБКА: Неверная папка игры: " + path); return false; }
            InstallResult res;
            try { res = InstallAsync(norm, null, Console.WriteLine, null, CancellationToken.None).GetAwaiter().GetResult(); }
            catch (Exception ex) { res = new InstallResult { FailReason = ex.Message }; }
            if (!res.Success) Console.WriteLine("ОШИБКА УСТАНОВКИ: " + res.FailReason);
            return res.Success;
        }

        public static bool RunCliUninstall(string path)
        {
            string norm = NormalizeGameDir(path);
            if (!IsValidGameFolder(norm)) { Console.WriteLine("ОШИБКА: Неверная папка игры: " + path); return false; }
            return Uninstall(norm, Console.WriteLine);
        }

        public static int RunCliVerifyBundle()
        {
            if (string.IsNullOrEmpty(PayloadSource.ExplicitPayload))
            {
                Console.WriteLine("BUNDLE_ERROR укажите пакет: --verify-bundle --payload <папка|zip>");
                return 1;
            }
            string error;
            PayloadInfo p = PayloadSource.PrepareExplicit(PayloadSource.ExplicitPayload, Console.WriteLine, out error);
            if (p == null) { Console.WriteLine("BUNDLE_INVALID " + error); return 1; }
            string why;
            List<string> files = InstallerCore.GetPayloadFiles(p.Dir);
            if (!InstallerCore.VerifyOwnedFiles(p.Dir, files, out why)) { Console.WriteLine("BUNDLE_INVALID " + why); return 1; }
            Console.WriteLine("BUNDLE_OK payload=" + p.Dir + " files=" + files.Count);
            return 0;
        }
    }
}
