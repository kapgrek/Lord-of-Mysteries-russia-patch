using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace LotmRussianPatcher
{
    public class PayloadInfo
    {
        public string Dir;
        public string Origin;      // shown in the window and the log
        public bool IsLocal;       // --payload or the zip next to the exe
    }

    // Where the patch files come from, in this order (TASK-015 §4.4):
    // 1. --payload <folder|zip>; 2. lom-russian-patch-data.zip next to the exe (exact name);
    // 3. the latest GitHub release; 4. the cache in %LOCALAPPDATA%, only if its zip matches the saved release.json.
    // Nothing else is searched: no repository path, no Downloads, no *patch*.zip guesses.
    public static class PayloadSource
    {
        public const string DataZipName = "lom-russian-patch-data.zip";
        public const string ReleaseJsonName = "release.json";
        private const string SourceMarker = ".source-sha256";

        public static string ExplicitPayload;   // --payload
        public static string ExeDir = AppDomain.CurrentDomain.BaseDirectory;
        public static string AppDataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LotmRussianPatch");
        public static string ExtractRoot = Path.Combine(Path.GetTempPath(), "LotmRussianPatch");
        // Tests replace the network with a stub; null = no release info.
        public static Func<Action<string>, ReleaseManifest> FetchManifest = GitHubReleaseClient.FetchLatestReleaseInfo;

        public static string CacheDir { get { return Path.Combine(AppDataRoot, "cache"); } }
        public static string CachedPayloadDir { get { return Path.Combine(AppDataRoot, "payload"); } }

        public static bool ValidatePayloadContents(string payloadDir, Action<string> log)
        {
            if (string.IsNullOrEmpty(payloadDir) || !Directory.Exists(payloadDir))
            {
                if (log != null) log("Папка пакета не найдена: " + payloadDir);
                return false;
            }
            foreach (string rel in new[] { InstallerCore.BridgeBlockPayloadRel, InstallerCore.BootstrapRel, InstallerCore.InitRel })
            {
                string path = Path.Combine(payloadDir, rel);
                if (!File.Exists(path) || new FileInfo(path).Length == 0)
                {
                    if (log != null) log("В пакете нет файла " + rel + " (" + payloadDir + ").");
                    return false;
                }
            }
            return true;
        }

        // The payload is the zip root or its only top folder (a zip made from the patch_payload folder).
        public static string FindPayloadRoot(string dir)
        {
            if (ValidatePayloadContents(dir, null)) return dir;
            if (!Directory.Exists(dir)) return null;
            string[] subs = Directory.GetDirectories(dir);
            if (subs.Length == 1 && Directory.GetFiles(dir).Length == 0 && ValidatePayloadContents(subs[0], null)) return subs[0];
            return null;
        }

        // --payload: a folder is used in place, a zip is extracted anew (keyed by its sha256).
        public static PayloadInfo PrepareExplicit(string path, Action<string> log, out string error)
        {
            error = null;
            string full = Path.GetFullPath(path.Trim('"'));
            if (Directory.Exists(full))
            {
                if (!ValidatePayloadContents(full, log)) { error = "--payload: папка не похожа на пакет русификатора: " + full; return null; }
                return new PayloadInfo { Dir = full, Origin = "Локальный пакет: " + full, IsLocal = true };
            }
            if (File.Exists(full) && full.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            {
                string dir = ExtractZip(full, "local", log, out error);
                if (dir == null) return null;
                return new PayloadInfo { Dir = dir, Origin = "Локальный пакет: " + full, IsLocal = true };
            }
            error = "--payload: нет такой папки или zip-архива: " + full;
            return null;
        }

        // Extracts into ExtractRoot\<prefix>-<sha16>, always from scratch.
        public static string ExtractZip(string zipPath, string prefix, Action<string> log, out string error)
        {
            error = null;
            try
            {
                string sha = InstallerCore.FileSha256(zipPath);
                string target = Path.Combine(ExtractRoot, prefix + "-" + sha.Substring(0, 16));
                if (Directory.Exists(target)) Directory.Delete(target, true);
                Directory.CreateDirectory(target);
                if (log != null) log("Распаковка " + Path.GetFileName(zipPath) + "...");
                ZipFile.ExtractToDirectory(zipPath, target);
                string root = FindPayloadRoot(target);
                if (root == null) { error = "В архиве " + Path.GetFileName(zipPath) + " нет пакета русификатора (bridge/, Saved/Mods/bootstrap.lua)."; return null; }
                return root;
            }
            catch (Exception ex)
            {
                error = "Не удалось распаковать " + Path.GetFileName(zipPath) + ": " + ex.Message;
                return null;
            }
        }

        public static async Task<PayloadInfo> ResolveAsync(bool allowDownload, Action<string> log, Action<int, string> progress, CancellationToken token)
        {
            string error;
            if (!string.IsNullOrEmpty(ExplicitPayload))
            {
                PayloadInfo p = PrepareExplicit(ExplicitPayload, log, out error);
                if (p == null && log != null) log("ОШИБКА: " + error);
                return p;
            }

            ReleaseManifest manifest = null;
            if (allowDownload)
            {
                if (progress != null) progress(-1, "Получение сведений о последней версии...");
                manifest = await Task.Run(() => FetchManifest(log));
            }

            // Zip from the release bundle, next to the installer.
            string sideZip = Path.Combine(ExeDir, DataZipName);
            if (File.Exists(sideZip))
            {
                string sha = InstallerCore.FileSha256(sideZip);
                if (manifest != null && !string.IsNullOrEmpty(manifest.PayloadSha256) && !sha.Equals(manifest.PayloadSha256, StringComparison.OrdinalIgnoreCase))
                {
                    if (log != null) log(DataZipName + " рядом с установщиком не совпадает с последним релизом " + manifest.Version + ": будет скачан актуальный пакет.");
                }
                else
                {
                    if (log != null) log(manifest != null && !string.IsNullOrEmpty(manifest.PayloadSha256)
                        ? DataZipName + " рядом с установщиком совпадает с релизом " + manifest.Version + " (SHA-256)."
                        : DataZipName + " рядом с установщиком: проверка по release.json недоступна.");
                    string dir = ExtractZip(sideZip, "side", log, out error);
                    if (dir != null) return new PayloadInfo { Dir = dir, Origin = "Архив рядом с установщиком: " + sideZip, IsLocal = true };
                    if (log != null) log("ОШИБКА: " + error);
                }
            }

            if (allowDownload)
            {
                PayloadInfo downloaded = await DownloadAsync(manifest, log, progress, token);
                if (downloaded != null) return downloaded;
            }

            PayloadInfo cached = ResolveCache(log);
            if (cached != null) return cached;
            return null;
        }

        // Uninstall and other offline uses: --payload or the verified cache, never the network.
        public static PayloadInfo ResolveOffline(Action<string> log)
        {
            if (!string.IsNullOrEmpty(ExplicitPayload))
            {
                string error;
                return PrepareExplicit(ExplicitPayload, log, out error);
            }
            return ResolveCache(null);
        }

        // The cached zip counts only when it matches the release.json saved next to it.
        public static PayloadInfo ResolveCache(Action<string> log)
        {
            string zip = Path.Combine(CacheDir, DataZipName);
            string rel = Path.Combine(CacheDir, ReleaseJsonName);
            if (!File.Exists(zip) || !File.Exists(rel)) return null;
            ReleaseManifest saved = ReleaseManifest.FromReleaseJson(File.ReadAllText(rel, Encoding.UTF8));
            if (saved == null || string.IsNullOrEmpty(saved.PayloadSha256)) return null;
            string sha = InstallerCore.FileSha256(zip);
            if (!sha.Equals(saved.PayloadSha256, StringComparison.OrdinalIgnoreCase))
            {
                if (log != null) log("Кеш пакета не совпадает с сохранённым release.json и не используется.");
                return null;
            }
            string dir = PrepareCachedPayload(zip, sha, log);
            if (dir == null) return null;
            if (log != null) log("Используется пакет из кеша: " + saved.Version);
            return new PayloadInfo { Dir = dir, Origin = "Кеш пакета " + saved.Version, IsLocal = false };
        }

        private static string PrepareCachedPayload(string zip, string sha, Action<string> log)
        {
            string target = CachedPayloadDir;
            string marker = Path.Combine(target, SourceMarker);
            if (File.Exists(marker) && File.ReadAllText(marker).Trim() == sha && ValidatePayloadContents(target, null)) return target;
            try
            {
                if (Directory.Exists(target)) Directory.Delete(target, true);
                Directory.CreateDirectory(target);
                if (log != null) log("Распаковка пакета...");
                ZipFile.ExtractToDirectory(zip, target);
                if (!ValidatePayloadContents(target, log)) return null;
                File.WriteAllText(marker, sha + "\n", new UTF8Encoding(false));
                return target;
            }
            catch (Exception ex)
            {
                if (log != null) log("ОШИБКА распаковки: " + ex.Message);
                return null;
            }
        }

        public static async Task<PayloadInfo> DownloadAsync(ReleaseManifest manifest, Action<string> log, Action<int, string> progress, CancellationToken token)
        {
            if (manifest == null)
            {
                if (log != null) log("Сведения о последнем релизе недоступны (нет интернета или GitHub не отвечает).");
                return null;
            }
            Directory.CreateDirectory(CacheDir);
            string zip = Path.Combine(CacheDir, DataZipName);
            string rel = Path.Combine(CacheDir, ReleaseJsonName);
            bool known = !string.IsNullOrEmpty(manifest.PayloadSha256);

            if (known && File.Exists(zip) && InstallerCore.FileSha256(zip).Equals(manifest.PayloadSha256, StringComparison.OrdinalIgnoreCase))
            {
                if (log != null) log("Пакет " + manifest.Version + " уже скачан (SHA-256 совпадает).");
            }
            else
            {
                string tmp = zip + ".download";
                if (File.Exists(tmp)) File.Delete(tmp);
                if (log != null) log("Скачивание пакета " + manifest.Version + "...");
                bool ok = await GitHubReleaseClient.DownloadFileWithProgressAsync(manifest.PayloadDownloadUrl, tmp, manifest.PayloadSize,
                    (bytes, total, speed) =>
                    {
                        int pct = total > 0 ? (int)((bytes * 100) / total) : -1;
                        if (progress != null) progress(pct, string.Format("Загрузка {0:0.0} / {1:0.0} МБ ({2:0.0} МБ/с)", bytes / 1048576.0, total / 1048576.0, speed / 1048576.0));
                    }, token, log);
                if (!ok)
                {
                    if (log != null) log("ОШИБКА: загрузка не завершена.");
                    return null;
                }
                if (known)
                {
                    if (!InstallerCore.FileSha256(tmp).Equals(manifest.PayloadSha256, StringComparison.OrdinalIgnoreCase))
                    {
                        File.Delete(tmp);
                        if (log != null) log("ОШИБКА: SHA-256 скачанного архива не совпадает с release.json.");
                        return null;
                    }
                    if (log != null) log("✔ SHA-256 архива совпадает с release.json.");
                }
                else if (log != null) log("Внимание: release.json недоступен, SHA-256 архива не проверен.");
                if (File.Exists(zip)) File.Delete(zip);
                File.Move(tmp, zip);
            }

            if (File.Exists(rel)) File.Delete(rel);
            if (known && manifest.ReleaseJsonText != null) File.WriteAllText(rel, manifest.ReleaseJsonText, new UTF8Encoding(false));
            string dir = PrepareCachedPayload(zip, InstallerCore.FileSha256(zip), log);
            if (dir == null) return null;
            return new PayloadInfo { Dir = dir, Origin = "GitHub, релиз " + manifest.Version, IsLocal = false };
        }
    }

    public class ReleaseManifest
    {
        public string Version;
        public string PayloadDownloadUrl;
        public string PayloadApiUrl;
        public long PayloadSize;
        public string PayloadSha256;
        public string ReleaseJsonText;   // release.json as downloaded, saved next to the cached zip

        // release.json written by tools/PackageRelease.ps1.
        public static ReleaseManifest FromReleaseJson(string json)
        {
            try
            {
                var dict = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(json);
                if (dict == null) return null;
                var res = new ReleaseManifest { ReleaseJsonText = json };
                if (dict.ContainsKey("release_version")) res.Version = Convert.ToString(dict["release_version"]);
                var p = dict.ContainsKey("payload") ? dict["payload"] as Dictionary<string, object> : null;
                if (p != null)
                {
                    if (p.ContainsKey("size")) res.PayloadSize = Convert.ToInt64(p["size"]);
                    if (p.ContainsKey("sha256")) res.PayloadSha256 = Convert.ToString(p["sha256"]).ToLowerInvariant();
                }
                return res;
            }
            catch { return null; }
        }
    }

    public static class GitHubReleaseClient
    {
        // Only from the environment (a private repository on the developer PC); the installer never runs `gh`.
        public static string TryGetGitHubToken()
        {
            string token = Environment.GetEnvironmentVariable("GITHUB_TOKEN");
            if (string.IsNullOrEmpty(token)) token = Environment.GetEnvironmentVariable("GH_TOKEN");
            return string.IsNullOrEmpty(token) ? null : token.Trim();
        }

        private static string RepoName()
        {
            string repo = Environment.GetEnvironmentVariable("LOTM_PATCH_REPO");
            return string.IsNullOrEmpty(repo) ? AppInfo.Repo : repo;
        }

        public static ReleaseManifest FetchLatestReleaseInfo(Action<string> log)
        {
            string repo = RepoName();
            string token = TryGetGitHubToken();
            string latestZip = "https://github.com/" + repo + "/releases/latest/download/" + PayloadSource.DataZipName;
            string latestJson = "https://github.com/" + repo + "/releases/latest/download/" + PayloadSource.ReleaseJsonName;
            try
            {
                string json = DownloadString("https://api.github.com/repos/" + repo + "/releases/latest", token, false);
                var dict = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(json);
                var res = new ReleaseManifest();
                if (dict.ContainsKey("tag_name")) res.Version = Convert.ToString(dict["tag_name"]);
                string relJsonUrl = null, relJsonApi = null;
                var assets = dict.ContainsKey("assets") ? dict["assets"] as IEnumerable : null;
                if (assets != null)
                {
                    foreach (object o in assets)
                    {
                        var asset = o as Dictionary<string, object>;
                        if (asset == null) continue;
                        string name = Convert.ToString(asset["name"]);
                        if (name == PayloadSource.DataZipName)
                        {
                            res.PayloadDownloadUrl = Convert.ToString(asset["browser_download_url"]);
                            res.PayloadApiUrl = Convert.ToString(asset["url"]);
                            res.PayloadSize = Convert.ToInt64(asset["size"]);
                        }
                        else if (name == PayloadSource.ReleaseJsonName)
                        {
                            relJsonUrl = Convert.ToString(asset["browser_download_url"]);
                            relJsonApi = Convert.ToString(asset["url"]);
                        }
                    }
                }
                if (relJsonUrl != null)
                {
                    try
                    {
                        string text = token != null ? DownloadString(relJsonApi, token, true) : DownloadString(relJsonUrl, null, false);
                        ReleaseManifest rel = ReleaseManifest.FromReleaseJson(text);
                        if (rel != null)
                        {
                            res.PayloadSha256 = rel.PayloadSha256;
                            res.ReleaseJsonText = text;
                        }
                    }
                    catch (Exception ex)
                    {
                        if (log != null) log("release.json недоступен: " + ex.Message);
                    }
                }
                if (token != null && !string.IsNullOrEmpty(res.PayloadApiUrl)) res.PayloadDownloadUrl = res.PayloadApiUrl;
                if (string.IsNullOrEmpty(res.PayloadDownloadUrl)) res.PayloadDownloadUrl = latestZip;
                return res;
            }
            catch (Exception ex)
            {
                if (log != null) log("GitHub API: " + ex.Message);
            }

            // Fallback without the API (rate limit): the release.json of the latest release.
            try
            {
                string text = DownloadString(latestJson, null, false);
                ReleaseManifest res = ReleaseManifest.FromReleaseJson(text);
                if (res != null) res.PayloadDownloadUrl = latestZip;
                return res;
            }
            catch { return null; }
        }

        // asset=true: API asset URL with the token; the storage redirect is followed without Authorization.
        private static string DownloadString(string url, string token, bool asset)
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = AppInfo.UserAgent;
            req.Timeout = 10000;
            req.AllowAutoRedirect = !asset;
            if (token != null) req.Headers.Add("Authorization", "Bearer " + token);
            if (asset) req.Accept = "application/octet-stream";
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            {
                if (asset && (int)resp.StatusCode >= 300 && (int)resp.StatusCode < 400)
                {
                    return DownloadString(resp.Headers["Location"], null, false);
                }
                using (var sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8)) return sr.ReadToEnd();
            }
        }

        public static async Task<bool> DownloadFileWithProgressAsync(string url, string destinationPath, long expectedTotalBytes,
            Action<long, long, double> progress, CancellationToken token, Action<string> log)
        {
            string auth = TryGetGitHubToken();
            return await Task.Run(() =>
            {
                try
                {
                    bool api = url.Contains("api.github.com");
                    HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
                    req.UserAgent = AppInfo.UserAgent;
                    req.Timeout = 30000;
                    req.ReadWriteTimeout = 60000;
                    req.AllowAutoRedirect = false;   // storage redirects are followed by hand, without Authorization
                    if (api && auth != null)
                    {
                        req.Headers.Add("Authorization", "Bearer " + auth);
                        req.Accept = "application/octet-stream";
                    }

                    HttpWebResponse resp;
                    try { resp = (HttpWebResponse)req.GetResponse(); }
                    catch (WebException wex)
                    {
                        var h = wex.Response as HttpWebResponse;
                        if (h == null || (int)h.StatusCode < 300 || (int)h.StatusCode >= 400)
                        {
                            if (log != null) log(h != null && h.StatusCode == HttpStatusCode.NotFound
                                ? "ОШИБКА: GitHub вернул 404 (файл релиза не найден)."
                                : "Ошибка сети: " + wex.Message);
                            return false;
                        }
                        resp = h;
                    }

                    if ((int)resp.StatusCode >= 300 && (int)resp.StatusCode < 400)
                    {
                        string location = resp.Headers["Location"];
                        resp.Close();
                        if (string.IsNullOrEmpty(location)) { if (log != null) log("ОШИБКА: пустой адрес перенаправления."); return false; }
                        HttpWebRequest redir = (HttpWebRequest)WebRequest.Create(location);
                        redir.UserAgent = AppInfo.UserAgent;
                        redir.Timeout = 30000;
                        redir.ReadWriteTimeout = 60000;
                        redir.AllowAutoRedirect = true;
                        resp = (HttpWebResponse)redir.GetResponse();
                    }

                    using (resp)
                    using (Stream input = resp.GetResponseStream())
                    using (var output = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        long total = resp.ContentLength > 0 ? resp.ContentLength : expectedTotalBytes;
                        byte[] buffer = new byte[65536];
                        long received = 0, lastBytes = 0;
                        double speed = 0;
                        Stopwatch sw = Stopwatch.StartNew();
                        int read;
                        while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                        {
                            if (token.IsCancellationRequested)
                            {
                                output.Close();
                                try { File.Delete(destinationPath); } catch { }
                                return false;
                            }
                            output.Write(buffer, 0, read);
                            received += read;
                            if (sw.ElapsedMilliseconds >= 500)
                            {
                                speed = (received - lastBytes) / (sw.ElapsedMilliseconds / 1000.0);
                                lastBytes = received;
                                sw.Restart();
                                if (progress != null) progress(received, total, speed);
                            }
                        }
                        if (progress != null) progress(received, total, speed);
                    }
                    return true;
                }
                catch (Exception ex)
                {
                    Exception inner = ex;
                    while (inner.InnerException != null) inner = inner.InnerException;
                    if (log != null) log("Ошибка при скачивании: " + inner.Message);
                    return false;
                }
            });
        }
    }
}
