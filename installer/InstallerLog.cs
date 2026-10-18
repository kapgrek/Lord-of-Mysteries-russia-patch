using System;
using System.IO;
using System.Text;

namespace LotmRussianPatcher
{
    // Installer journal in %LOCALAPPDATA%\AbsoluteRU\installer.log (TASK-037): the same lines as the "ЖУРНАЛ" box
    // and the CLI. Not next to the exe (Downloads, archives, read-only) and not in the game folder (may be unknown yet).
    // Write errors are swallowed: the journal must never break the installer.
    public static class InstallerLog
    {
        public const long MaxSize = 1 << 20;
        public const string FileName = "installer.log";
        public const string OldFileName = "installer.old.log";

        public static string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AbsoluteRU");
        public static string LogPath { get { return Path.Combine(Dir, FileName); } }
        public static string OldLogPath { get { return Path.Combine(Dir, OldFileName); } }

        private static readonly object Sync = new object();
        private static readonly Encoding Utf8 = new UTF8Encoding(false);

        // Once per run: rotation over 1 MB, then the session header.
        public static void Start()
        {
            lock (Sync)
            {
                try
                {
                    if (File.Exists(LogPath) && new FileInfo(LogPath).Length > MaxSize)
                    {
                        if (File.Exists(OldLogPath)) File.Delete(OldLogPath);
                        File.Move(LogPath, OldLogPath);
                    }
                }
                catch { }
            }
            Append("=== AbsoluteRU " + AppInfo.Version + " запущен ===");
        }

        public static void Append(string line)
        {
            lock (Sync)
            {
                try
                {
                    Directory.CreateDirectory(Dir);
                    File.AppendAllText(LogPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + line + "\n", Utf8);
                }
                catch { }
            }
        }

        // Console + journal, for the CLI modes.
        public static void Cli(string line)
        {
            Console.WriteLine(line);
            Append(line);
        }
    }
}
