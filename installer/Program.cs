using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

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

            Application app = UiKit.EnsureApplication();
            app.DispatcherUnhandledException += (s, e) =>
            {
                e.Handled = true;
                try { UiKit.Message(app.MainWindow, "Непредвиденная ошибка", e.Exception.Message, true); }
                catch { MessageBox.Show(e.Exception.ToString(), "Lord of Mysteries — установщик"); }
            };
            Window window;
            try { window = MainWindow.Create(); }
            catch (Exception ex)
            {
                MessageBox.Show("Не удалось открыть окно установщика:\n" + ex, "Lord of Mysteries — установщик");
                return 1;
            }
            return app.Run(window);
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
                Console.WriteLine("UI_SMOKE_OK native=csharp wpf version=" + VERSION);
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
}
