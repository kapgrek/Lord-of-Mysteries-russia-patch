using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace LotmRussianPatcher
{
    // Self-update of the installer (TASK-040): the cache logic of the game lives in this exe, the data in the zip.
    // When GitHub has a release newer than AppInfo.Version, the window downloads its exe (patcher_asset of release.json),
    // checks size and SHA-256, renames the running exe to .old, puts the new one in its place and restarts.
    // Every function takes its paths as parameters: tools/InstallerCoreTests.cs runs them in temp/.
    public static class SelfUpdate
    {
        public const string DefaultExeName = "Lord-of-Mysteries-Russian-Patch.exe";
        public const string UpdatedFromArg = "--updated-from";
        public const string NoSelfUpdateArg = "--no-self-update";

        public static string UpdatedFrom;    // --updated-from <version>: this run was started by a self-update
        public static bool DisabledByArg;    // --no-self-update
        public static string LatestVersion;  // latest GitHub release, if known
        public static bool Failed;           // a newer release is known, but this exe was not replaced

        // Tests replace the network with a local copy.
        public static Func<string, string, long, Action<long, long, double>, CancellationToken, Action<string>, Task<bool>> Download
            = GitHubReleaseClient.DownloadFileWithProgressAsync;

        // %LOCALAPPDATA%\LotmRussianPatch\installer: used when the folder of the exe is not writable.
        public static string FallbackDir { get { return Path.Combine(PayloadSource.AppDataRoot, "installer"); } }

        public static string CurrentExe { get { return Process.GetCurrentProcess().MainModule.FileName; } }

        public static string ExeName(ReleaseManifest m)
        {
            string name = m != null && !string.IsNullOrEmpty(m.PatcherName) ? Path.GetFileName(m.PatcherName) : null;
            return string.IsNullOrEmpty(name) ? DefaultExeName : name;
        }

        // Only with a sha256 from release.json: an unchecked exe is never started.
        public static bool IsNewer(ReleaseManifest m)
        {
            return m != null && !string.IsNullOrEmpty(m.PatcherSha256) && !string.IsNullOrEmpty(m.PatcherDownloadUrl)
                && PatcherBackend.CompareVersions(m.Version, AppInfo.Version) > 0;
        }

        // Why the newer release is not installed by this run, or null when the update may go ahead.
        public static string SkipReason(ReleaseManifest m)
        {
            if (!string.IsNullOrEmpty(PayloadSource.ExplicitPayload)) return "Самообновление отключено: задан --payload.";
            if (DisabledByArg) return "Самообновление отключено: задан " + NoSelfUpdateArg + ".";
            if (GitHubReleaseClient.RepoOverridden) return "Самообновление отключено: задана переменная LOTM_PATCH_REPO.";
            if (!string.IsNullOrEmpty(UpdatedFrom))
                return "Самообновление уже выполнялось, но версия не сменилась (" + AppInfo.Version + ", на GitHub " + m.Version + "): скачайте установщик вручную.";
            return null;
        }

        // Text for the places that used to say "Дождитесь обновления русификатора"; null when no release is newer than this exe.
        public static string NewerReleaseText()
        {
            if (string.IsNullOrEmpty(LatestVersion) || PatcherBackend.CompareVersions(LatestVersion, AppInfo.Version) <= 0) return null;
            return Failed
                ? "Вышла версия " + LatestVersion + ", но установщик не смог обновиться сам: скачайте " + DefaultExeName
                    + " со страницы релиза https://github.com/" + AppInfo.Repo + "/releases/latest."
                : "Вышла версия " + LatestVersion + " — установщик обновится при следующем запуске.";
        }

        // Downloads the exe of the release into newFile and checks size and SHA-256 against release.json; null on any failure.
        public static async Task<string> DownloadAsync(ReleaseManifest m, string newFile, Action<string> log, Action<int, string> progress, CancellationToken token)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(newFile));
                if (File.Exists(newFile)) File.Delete(newFile);
            }
            catch (Exception ex)
            {
                if (log != null) log("Не удалось подготовить " + newFile + ": " + ex.Message);
                return null;
            }
            bool ok = await Download(m.PatcherDownloadUrl, newFile, m.PatcherSize,
                (bytes, total, speed) =>
                {
                    int pct = total > 0 ? (int)((bytes * 100) / total) : -1;
                    if (progress != null) progress(pct, string.Format("Установщик {0:0.0} / {1:0.0} МБ", bytes / 1048576.0, total / 1048576.0));
                }, token, log);
            if (!ok || !File.Exists(newFile))
            {
                TryDelete(newFile);
                if (log != null) log("ОШИБКА: новый установщик не скачан.");
                return null;
            }
            long size = new FileInfo(newFile).Length;
            if (m.PatcherSize > 0 && size != m.PatcherSize)
            {
                TryDelete(newFile);
                if (log != null) log("Размер нового установщика (" + size + ") не совпадает с release.json (" + m.PatcherSize + "), обновление пропущено.");
                return null;
            }
            if (!InstallerCore.FileSha256(newFile).Equals(m.PatcherSha256, StringComparison.OrdinalIgnoreCase))
            {
                TryDelete(newFile);
                if (log != null) log("SHA-256 нового установщика не совпадает с release.json, обновление пропущено.");
                return null;
            }
            if (log != null) log("✔ SHA-256 нового установщика совпадает с release.json.");
            return newFile;
        }

        // Windows allows renaming a running exe: currentExe -> .old, newFile -> currentExe.
        // Returns the exe to start, or null with currentExe left in place.
        public static string Swap(string currentExe, string newFile, Action<string> log)
        {
            string old = currentExe + ".old";
            try
            {
                if (File.Exists(old)) File.Delete(old);
                File.Move(currentExe, old);
            }
            catch (Exception ex)
            {
                if (log != null) log("Не удалось переименовать " + Path.GetFileName(currentExe) + ": " + ex.Message);
                return null;
            }
            try
            {
                File.Move(newFile, currentExe);
                return currentExe;
            }
            catch (Exception ex)
            {
                if (log != null) log("Не удалось поставить новый установщик на место старого: " + ex.Message);
                try { File.Move(old, currentExe); }
                catch (Exception back) { if (log != null) log("ОШИБКА: старый установщик остался в " + old + ": " + back.Message); }
                return null;
            }
        }

        // The folder of the exe is not writable (Program Files, read-only media): the new exe goes to FallbackDir.
        public static string PlaceInFallback(string newFile, string name, Action<string> log)
        {
            try
            {
                Directory.CreateDirectory(FallbackDir);
                string target = Path.Combine(FallbackDir, name);
                string placed;
                if (File.Exists(target)) placed = Swap(target, newFile, log);
                else { File.Move(newFile, target); placed = target; }
                if (placed != null && log != null) log("Новая версия сохранена в " + placed + ", дальше запускайте её.");
                return placed;
            }
            catch (Exception ex)
            {
                if (log != null) log("Не удалось сохранить новый установщик в " + FallbackDir + ": " + ex.Message);
                return null;
            }
        }

        // Download, check and swap; the exe to start, or null (currentExe untouched).
        public static async Task<string> PrepareAsync(ReleaseManifest m, string currentExe, Action<string> log, Action<int, string> progress, CancellationToken token)
        {
            string name = ExeName(m);
            string newFile = currentExe + ".new";
            bool besideExe = CanCreate(newFile);
            if (!besideExe) newFile = Path.Combine(FallbackDir, name + ".new");
            string downloaded = await DownloadAsync(m, newFile, log, progress, token);
            if (downloaded == null) return null;
            string exe = besideExe ? Swap(currentExe, downloaded, log) : null;
            if (exe == null) exe = PlaceInFallback(downloaded, name, log);
            if (exe == null) TryDelete(downloaded);
            return exe;
        }

        public static bool Restart(string exe, Action<string> log)
        {
            try
            {
                var psi = new ProcessStartInfo(exe, UpdatedFromArg + " \"" + AppInfo.Version + "\"")
                {
                    UseShellExecute = false,
                    WorkingDirectory = Path.GetDirectoryName(exe)
                };
                Process.Start(psi);
                return true;
            }
            catch (Exception ex)
            {
                if (log != null) log("Не удалось запустить " + exe + ": " + ex.Message);
                return false;
            }
        }

        // One attempt to remove <exe>.old and <exe>.new; false while one of them is still busy.
        public static bool CleanupOld(string currentExe)
        {
            bool a = TryDelete(currentExe + ".old");
            bool b = TryDelete(currentExe + ".new");
            return a && b;
        }

        // At start: the previous process may still hold the .old exe for a moment, so retry for ~3 s off the UI thread.
        public static void CleanupOldInBackground(string currentExe)
        {
            if (CleanupOld(currentExe)) return;
            Task.Run(async () =>
            {
                for (int i = 0; i < 12 && !CleanupOld(currentExe); i++) await Task.Delay(250);
            });
        }

        private static bool CanCreate(string path)
        {
            try
            {
                using (new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None)) { }
                return true;
            }
            catch (UnauthorizedAccessException) { return false; }
            catch (IOException) { return false; }
        }

        private static bool TryDelete(string path)
        {
            try
            {
                if (File.Exists(path)) File.Delete(path);
                return true;
            }
            catch { return false; }
        }
    }
}
