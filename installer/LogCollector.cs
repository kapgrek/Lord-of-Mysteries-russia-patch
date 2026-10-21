using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace LotmRussianPatcher
{
    public class LogCollectResult
    {
        public string Folder;
        public List<string> Files = new List<string>();
        public string Error;          // text for the player, null on success
        public bool UsedFallback;     // the exe folder was not writable: the Desktop was used
    }

    // "Отправить логи" (TASK-035): copies the latest Saved\Logs\C7*.log and info.txt next to the exe.
    // No upload: the player sends the folder to t.me/KapGrek himself. No WPF here, so tests can call it.
    public static class LogCollector
    {
        // Latin on purpose: the folder is zipped and sent through Telegram, and some archivers mangle Cyrillic names.
        public const string FolderName = "AbsoluteRU_logs";
        public const string InfoName = "info.txt";

        public static string DesktopDir = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);

        public static LogCollectResult Collect(string gameDir, string outRoot, int count = 3)
        {
            var result = new LogCollectResult();
            List<FileInfo> logs;
            try
            {
                string logsDir = Path.Combine(gameDir, "Saved", "Logs");
                logs = Directory.Exists(logsDir) ? new List<FileInfo>(new DirectoryInfo(logsDir).GetFiles("C7*.log")) : new List<FileInfo>();
            }
            catch (Exception ex) { result.Error = "Нет доступа к папке логов игры: " + ex.Message; return result; }
            if (logs.Count == 0) { result.Error = "Логи игры не найдены (Saved\\Logs). Запустите игру хотя бы раз."; return result; }
            logs.Sort((a, b) => b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc));
            if (logs.Count > count) logs.RemoveRange(count, logs.Count - count);

            string firstError;
            if (TryCollect(gameDir, Path.Combine(outRoot, FolderName), logs, result, out firstError)) return result;
            result.Files.Clear();
            string fallbackError;
            if (!string.IsNullOrEmpty(DesktopDir) && TryCollect(gameDir, Path.Combine(DesktopDir, FolderName), logs, result, out fallbackError))
            {
                result.UsedFallback = true;
                return result;
            }
            result.Folder = null;
            result.Error = "Нет доступа на запись ни рядом с установщиком, ни на Рабочем столе: " + firstError;
            return result;
        }

        private static bool TryCollect(string gameDir, string folder, List<FileInfo> logs, LogCollectResult result, out string error)
        {
            error = null;
            try
            {
                Directory.CreateDirectory(folder);
                // Only our own leftovers: the folder itself and foreign files stay.
                foreach (string old in Directory.GetFiles(folder, "*.log")) File.Delete(old);
                string oldInfo = Path.Combine(folder, InfoName);
                if (File.Exists(oldInfo)) File.Delete(oldInfo);

                foreach (FileInfo log in logs)
                {
                    CopyShared(log.FullName, Path.Combine(folder, log.Name));
                    result.Files.Add(log.Name);
                }
                // Installer journal (TASK-037).
                foreach (string extra in new[] { InstallerLog.LogPath, InstallerLog.OldLogPath })
                {
                    if (!File.Exists(extra)) continue;
                    CopyShared(extra, Path.Combine(folder, Path.GetFileName(extra)));
                    result.Files.Add(Path.GetFileName(extra));
                }
                File.WriteAllText(Path.Combine(folder, InfoName), BuildInfo(gameDir, folder, result.Files), new UTF8Encoding(false));
                result.Folder = folder;
                return true;
            }
            catch (Exception ex)
            {
                error = ex.Message;
                return false;
            }
        }

        // C7.log is open for writing while the game runs.
        private static void CopyShared(string source, string target)
        {
            using (var src = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var dst = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                src.CopyTo(dst);
            }
        }

        public static string BuildInfo(string gameDir, string folder, List<string> files)
        {
            var sb = new StringBuilder();
            sb.Append("AbsoluteRU: сведения для автора русификатора\n");
            Line(sb, "Установщик", () => AppInfo.Version);
            Line(sb, "Дата", () => DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss zzz"));
            Line(sb, "Папка игры", () => MaskUser(gameDir));
            Line(sb, "Установленный русификатор", () => PatcherBackend.InstalledVersion(gameDir) ?? "-");
            Line(sb, "Статус патча", () => PatcherBackend.InspectGameStatus(gameDir).ToString());
            Line(sb, "Запущенный процесс игры", () => PatcherBackend.RunningBlocker() ?? "-");

            sb.Append("\nФайлы:\n");
            foreach (string name in files)
            {
                string n = name;
                Line(sb, "  " + n, () => new FileInfo(Path.Combine(folder, n)).Length + " байт");
            }

            sb.Append("\nВерсия игры:\n");
            string ks = Path.Combine(gameDir, InstallerCore.KsCacheRel);
            Line(sb, "  AssetsVersion.txt", () =>
            {
                string p = Path.Combine(ks, InstallerCore.AssetsVersionName);
                return File.Exists(p) ? File.ReadAllText(p).Trim() : "нет файла";
            });
            Line(sb, "  Установщик рассчитан на", () =>
            {
                SupportedGame g = PatcherBackend.LoadSupportedGame(null, null);
                if (g == null) return "нет supported_game.json";
                if (g.Cache == null) return "game_build " + g.GameBuild + ", без cache_launch";
                return "game_build " + g.GameBuild + ", cache_launch.entry_id " + (g.Cache.EntryId.Length > 0 ? g.Cache.EntryId : "нет")
                    + ", cache_launch.manifest_sha256 " + g.Cache.ManifestSha256;
            });
            Line(sb, "  pakchunk0 (InspectPak)", () =>
            {
                string build;
                PakState st = PatcherBackend.InspectPak(gameDir, out build);
                return st + ", сборка " + (build ?? "?");
            });
            Line(sb, "  Кеш обновления (InspectCache)", () => DescribeCache(PatcherBackend.InspectCache(gameDir)));
            Line(sb, "  Папки хотпатчей kscache", () =>
            {
                if (!Directory.Exists(ks)) return "нет папки " + InstallerCore.KsCacheRel;
                var parts = new List<string>();
                foreach (string dir in Directory.GetDirectories(ks))
                {
                    long n;
                    string name = Path.GetFileName(dir);
                    if (!long.TryParse(name, out n) || n <= 100000) continue;
                    string pak = Path.Combine(dir, "pakchunk0-Windows.pak");
                    if (File.Exists(pak))
                    {
                        var fi = new FileInfo(pak);
                        parts.Add(name + ": pakchunk0 " + fi.Length + " байт, " + fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"));
                    }
                    else parts.Add(name + ": без pakchunk0");
                }
                return parts.Count == 0 ? "нет" : "\n    " + string.Join("\n    ", parts.ToArray());
            });
            Line(sb, "  Манифесты", () =>
            {
                if (!Directory.Exists(ks)) return "нет";
                var parts = new List<string>();
                foreach (string m in Directory.GetFiles(ks, "package_*.manifest")) parts.Add(Path.GetFileName(m) + " " + InstallerCore.FileSha256(m));
                return parts.Count == 0 ? "нет" : "\n    " + string.Join("\n    ", parts.ToArray());
            });
            return sb.ToString();
        }

        public static string DescribeCache(CacheInfo c)
        {
            var sb = new StringBuilder(c.State.ToString());
            if (c.Version != null) sb.Append(", версия ").Append(c.Version);
            if (c.AssetsVersion != null && c.AssetsVersion != c.Version) sb.Append(" (AssetsVersion ").Append(c.AssetsVersion).Append(")");
            if (c.EntryRelPath != null) sb.Append(", запись local.cache по entry_id ").Append(c.EntryRelPath);
            if (c.PakPath != null)
            {
                int k = c.PakPath.IndexOf(InstallerCore.KsCacheRel, StringComparison.OrdinalIgnoreCase);
                sb.Append(", ").Append(k >= 0 ? c.PakPath.Substring(k) : c.PakPath);
            }
            if (c.PakSize > 0) sb.Append(", размер пака ").Append(c.PakSize);
            if (c.Offset >= 0) sb.Append(", смещение ").Append(c.Offset);
            if (c.Hits.Count > 0) sb.Append(", кандидаты: ").Append(InstallerCore.DescribeHits(c.Hits, 50));
            if (c.Detail.Length > 0) sb.Append(" (").Append(c.Detail).Append(")");
            return sb.ToString();
        }

        // Every item on its own: a failing one is written as an error line, the file is still produced.
        private static void Line(StringBuilder sb, string label, Func<string> value)
        {
            string v;
            try { v = value(); }
            catch (Exception ex) { v = "ошибка: " + ex.GetType().Name + ": " + ex.Message; }
            sb.Append(label).Append(": ").Append(MaskUser(v)).Append('\n');
        }

        // No Windows user name in a file that is sent to someone else.
        public static string MaskUser(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (string.IsNullOrEmpty(profile)) return text;
            int i;
            while ((i = text.IndexOf(profile, StringComparison.OrdinalIgnoreCase)) >= 0)
                text = text.Substring(0, i) + "%USERPROFILE%" + text.Substring(i + profile.Length);
            return text;
        }
    }
}
