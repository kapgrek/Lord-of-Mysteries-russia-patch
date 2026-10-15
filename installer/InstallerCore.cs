using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

namespace LotmRussianPatcher
{
    public enum GamePatchStatus
    {
        InvalidPath,
        NotInstalled,
        InstalledActive,
        InstalledDisabled
    }

    // State of the whole pakchunk0 compared with supported_game.json.
    public enum PakState
    {
        Missing,
        CleanSupported,   // sha256 of the whole pak = a supported clean base
        Installed,        // sha256 of the whole pak = clean base + bridge block
        Unknown           // anything else: other game build or a modified pak
    }

    public class BasePak
    {
        public string Name;
        public string Sha256;
        public long Size;
    }

    // Launch block of a hotpatch pakchunk0 in Saved/kscache/<ver>/ (CPDD release.json external_bridge.cache_launch).
    // The offset is not fixed: the block is found by its first 64 bytes and checked by sha256.
    public class CacheLaunch
    {
        public string ManifestSha256;
        public string PakName = "pakchunk0-Windows.pak";
        public int Size;
        public string CleanSha256;
        public string InstalledSha256;
        public string Payload = "bridge/cache-startup.oodle";
        public string OriginalHeadHex;
        public string InstalledHeadHex;
    }

    // State of the hotpatch pakchunk0 in Saved/kscache (it overrides the launch block of the base pak).
    public enum CacheState
    {
        NoCachePak,       // no Saved/kscache/<ver>/pakchunk0: only the base pak counts
        UnsupportedBuild, // the cache pak exists, but its manifest is not the one cache_launch was made for
        Clean,            // exactly one clean launch block found
        Installed,        // exactly one bridge block found
        NotFound,         // supported manifest, but no block
        Ambiguous         // more than one candidate block
    }

    public class CacheInfo
    {
        public CacheState State = CacheState.NoCachePak;
        public string Version;
        public string PakPath;
        public long Offset = -1;
        public string Detail = "";
    }

    // Supported game state, the same fields as CPDD release.json (supported_base_paks + launch_block + cache_launch).
    public class SupportedGame
    {
        public const string FileName = "supported_game.json";
        public const string ResourceName = "LotmRussianPatcher.supported_game.json";

        public string Source;
        public string GameBuild;
        public List<BasePak> BasePaks = new List<BasePak>();
        public string PakRelativePath = "Content/Paks/pakchunk0-Windows.pak";
        public long Offset;
        public int BlockSize;
        public string CleanBlockSha256;
        public string InstalledBlockSha256;
        public string InstalledPakSha256;
        public long InstalledPakSize;
        public CacheLaunch Cache;   // null: the release knows no hotpatch pakchunk0

        public static SupportedGame Parse(string json)
        {
            var serializer = new JavaScriptSerializer();
            var root = serializer.Deserialize<Dictionary<string, object>>(json);
            if (root == null) throw new InvalidDataException("supported_game.json is empty");

            var game = new SupportedGame();
            game.Source = GetString(root, "source");
            game.GameBuild = GetString(root, "game_build");

            object paks;
            if (root.TryGetValue("supported_base_paks", out paks) && paks is IEnumerable)
            {
                foreach (object item in (IEnumerable)paks)
                {
                    var d = item as Dictionary<string, object>;
                    if (d == null) continue;
                    game.BasePaks.Add(new BasePak { Name = GetString(d, "name"), Sha256 = GetString(d, "sha256").ToLowerInvariant(), Size = GetLong(d, "size") });
                }
            }

            object lbObj;
            var lb = root.TryGetValue("launch_block", out lbObj) ? lbObj as Dictionary<string, object> : null;
            if (lb == null) throw new InvalidDataException("supported_game.json: launch_block is missing");
            string rel = GetString(lb, "pak_relative_path");
            if (!string.IsNullOrEmpty(rel)) game.PakRelativePath = rel;
            game.Offset = GetLong(lb, "offset");
            game.BlockSize = (int)GetLong(lb, "size");
            game.CleanBlockSha256 = GetString(lb, "clean_sha256").ToLowerInvariant();
            game.InstalledBlockSha256 = GetString(lb, "installed_sha256").ToLowerInvariant();
            game.InstalledPakSha256 = GetString(lb, "installed_pak_sha256").ToLowerInvariant();
            game.InstalledPakSize = GetLong(lb, "installed_pak_size");

            if (game.BasePaks.Count == 0 || game.Offset <= 0 || game.BlockSize <= 0
                || game.CleanBlockSha256.Length != 64 || game.InstalledBlockSha256.Length != 64
                || game.InstalledPakSha256.Length != 64 || game.InstalledPakSize <= 0)
            {
                throw new InvalidDataException("supported_game.json: incomplete supported_base_paks / launch_block");
            }

            object clObj;
            var cl = root.TryGetValue("cache_launch", out clObj) ? clObj as Dictionary<string, object> : null;
            if (cl != null)
            {
                var c = new CacheLaunch();
                c.ManifestSha256 = GetString(cl, "manifest_sha256").ToLowerInvariant();
                string pakName = GetString(cl, "pak_name");
                if (!string.IsNullOrEmpty(pakName)) c.PakName = pakName;
                c.Size = (int)GetLong(cl, "size");
                c.CleanSha256 = GetString(cl, "clean_sha256").ToLowerInvariant();
                c.InstalledSha256 = GetString(cl, "installed_sha256").ToLowerInvariant();
                string payload = GetString(cl, "payload");
                if (!string.IsNullOrEmpty(payload)) c.Payload = payload;
                c.OriginalHeadHex = GetString(cl, "original_head_hex").ToLowerInvariant();
                c.InstalledHeadHex = GetString(cl, "installed_head_hex").ToLowerInvariant();
                if (c.ManifestSha256.Length != 64 || c.Size < 64 || c.CleanSha256.Length != 64 || c.InstalledSha256.Length != 64
                    || c.OriginalHeadHex.Length != 128 || c.InstalledHeadHex.Length != 128
                    || c.PakName.IndexOfAny(new[] { '/', '\\', ':' }) >= 0 || c.Payload.Contains(".."))
                {
                    throw new InvalidDataException("supported_game.json: incomplete cache_launch");
                }
                game.Cache = c;
            }
            return game;
        }

        // supported_game.json next to the payload (it ships in the data zip), otherwise the copy built into the installer.
        public static SupportedGame Load(string payloadDir)
        {
            if (!string.IsNullOrEmpty(payloadDir))
            {
                string path = Path.Combine(payloadDir, FileName);
                if (File.Exists(path)) return Parse(File.ReadAllText(path, Encoding.UTF8));
            }
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
            {
                if (s == null) return null;
                using (var reader = new StreamReader(s, Encoding.UTF8)) return Parse(reader.ReadToEnd());
            }
        }

        public string ToJson()
        {
            var sb = new StringBuilder();
            sb.Append("{\n  \"source\": \"").Append(Escape(Source)).Append("\",\n");
            sb.Append("  \"game_build\": \"").Append(Escape(GameBuild)).Append("\",\n  \"supported_base_paks\": [\n");
            for (int i = 0; i < BasePaks.Count; i++)
            {
                sb.AppendFormat("    {{ \"name\": \"{0}\", \"sha256\": \"{1}\", \"size\": {2} }}{3}\n",
                    Escape(BasePaks[i].Name), BasePaks[i].Sha256, BasePaks[i].Size, i + 1 < BasePaks.Count ? "," : "");
            }
            sb.Append("  ],\n  \"launch_block\": {\n");
            sb.Append("    \"pak_relative_path\": \"").Append(Escape(PakRelativePath)).Append("\",\n");
            sb.Append("    \"offset\": ").Append(Offset).Append(",\n");
            sb.Append("    \"size\": ").Append(BlockSize).Append(",\n");
            sb.Append("    \"clean_sha256\": \"").Append(CleanBlockSha256).Append("\",\n");
            sb.Append("    \"installed_sha256\": \"").Append(InstalledBlockSha256).Append("\",\n");
            sb.Append("    \"installed_pak_sha256\": \"").Append(InstalledPakSha256).Append("\",\n");
            sb.Append("    \"installed_pak_size\": ").Append(InstalledPakSize).Append("\n  }");
            if (Cache != null)
            {
                sb.Append(",\n  \"cache_launch\": {\n");
                sb.Append("    \"manifest_sha256\": \"").Append(Cache.ManifestSha256).Append("\",\n");
                sb.Append("    \"pak_name\": \"").Append(Escape(Cache.PakName)).Append("\",\n");
                sb.Append("    \"size\": ").Append(Cache.Size).Append(",\n");
                sb.Append("    \"clean_sha256\": \"").Append(Cache.CleanSha256).Append("\",\n");
                sb.Append("    \"installed_sha256\": \"").Append(Cache.InstalledSha256).Append("\",\n");
                sb.Append("    \"payload\": \"").Append(Escape(Cache.Payload)).Append("\",\n");
                sb.Append("    \"original_head_hex\": \"").Append(Cache.OriginalHeadHex).Append("\",\n");
                sb.Append("    \"installed_head_hex\": \"").Append(Cache.InstalledHeadHex).Append("\"\n  }");
            }
            sb.Append("\n}\n");
            return sb.ToString();
        }

        private static string Escape(string s)
        {
            return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        private static string GetString(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) && v != null ? Convert.ToString(v) : "";
        }

        private static long GetLong(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) && v != null ? Convert.ToInt64(v) : 0;
        }
    }

    // Install / update / uninstall for one game folder. Knows nothing about UI or downloads.
    // InstalledDisabled (CPDDTranslation.lua.disabled left by the old RU<->EN toggle) breaks the game start;
    // a normal Install repairs it.
    public class InstallerCore
    {
        public const string BackupDirRel = @"Saved\RussianPatchBackups";
        public const string BlockBackupName = "launch-original.block";
        public const string InstalledListName = "installed_files.json";
        public const string LegacyBackupDirRel = @"Saved\Mods\Backup";
        public const string LegacyBlockBackupName = "LaunchInstance.original.block";
        public const string OwnedFilesName = "owned_files.json";
        public const string BridgeRel = @"Binaries\Win64\lua\Launch\Base\CPDDTranslation.lua";
        public const string BootstrapRel = @"Saved\Mods\bootstrap.lua";
        public const string InitRel = @"Saved\Mods\lua\mods\cpdd_runtime_fixes\Init.lua";
        public const string BridgeBlockPayloadRel = @"bridge\LaunchInstance.native-bridge.padded.oodle";
        public const string BakedTextRel = @"Saved\Mods\BakedText";
        public const string KsCacheRel = @"Saved\kscache";
        public const string AssetsVersionName = "AssetsVersion.txt";
        public const string CacheBackupPrefix = "cache-launch-";

        private static readonly string[] PayloadRoots = { "Binaries", "Saved" };

        private readonly string gameDir;
        private readonly SupportedGame game;
        private readonly Action<string> log;

        public InstallerCore(string gameDir, SupportedGame game, Action<string> log)
        {
            if (string.IsNullOrEmpty(gameDir)) throw new ArgumentException("gameDir");
            if (game == null) throw new ArgumentNullException("game");
            this.gameDir = Path.GetFullPath(gameDir);
            this.game = game;
            this.log = log ?? (s => { });
        }

        public string GameDir { get { return gameDir; } }
        public string PakPath { get { return Path.Combine(gameDir, game.PakRelativePath.Replace('/', '\\')); } }
        public string BackupDir { get { return Path.Combine(gameDir, BackupDirRel); } }
        public string BlockBackupPath { get { return Path.Combine(BackupDir, BlockBackupName); } }
        public string InstalledListPath { get { return Path.Combine(BackupDir, InstalledListName); } }
        private string Game(string rel) { return Path.Combine(gameDir, rel); }
        private string CacheBackupPath(string version) { return Path.Combine(BackupDir, CacheBackupPrefix + version + ".block"); }
        private string CacheRecordPath(string version) { return Path.Combine(BackupDir, CacheBackupPrefix + version + ".json"); }

        // ------------------------------------------------------------ kscache (hotpatch pakchunk0)

        // Saved/kscache/AssetsVersion.txt = "1.<manifest>.<cache version>.Online_Shipping".
        // Returns the cache pak path when it exists, otherwise null.
        public static string FindCachePak(string gameDir, string pakName, out string version, out string manifestId)
        {
            version = null;
            manifestId = null;
            string ks = Path.Combine(gameDir, KsCacheRel);
            string verFile = Path.Combine(ks, AssetsVersionName);
            if (!File.Exists(verFile)) return null;
            string[] parts = File.ReadAllText(verFile).Trim().Split('.');
            if (parts.Length < 3 || !IsDigits(parts[1]) || !IsDigits(parts[2])) return null;
            manifestId = parts[1];
            version = parts[2];
            string pak = Path.Combine(ks, version, pakName ?? "pakchunk0-Windows.pak");
            return File.Exists(pak) ? pak : null;
        }

        public CacheInfo InspectCache()
        {
            var info = new CacheInfo();
            string version, manifestId;
            string pak = FindCachePak(gameDir, game.Cache != null ? game.Cache.PakName : null, out version, out manifestId);
            info.Version = version;
            if (pak == null) return info;
            info.PakPath = pak;

            // A bridge we wrote ourselves: the record keeps the offset, so no scan is needed.
            long recorded = ReadCacheRecordOffset(version, pak);
            if (recorded >= 0) { info.State = CacheState.Installed; info.Offset = recorded; return info; }

            CacheLaunch c = game.Cache;
            if (c == null)
            {
                info.State = CacheState.UnsupportedBuild;
                info.Detail = "в сведениях о версии нет блока запуска для кеша обновления";
                return info;
            }
            string manifest = Path.Combine(gameDir, KsCacheRel, "package_" + manifestId + ".manifest");
            if (!File.Exists(manifest) || FileSha256(manifest) != c.ManifestSha256)
            {
                info.State = CacheState.UnsupportedBuild;
                info.Detail = "манифест package_" + manifestId + ".manifest не совпадает с поддерживаемым";
                return info;
            }

            byte[] originalHead = FromHex(c.OriginalHeadHex);
            byte[] installedHead = FromHex(c.InstalledHeadHex);
            List<long>[] hits = FindAll(pak, new[] { originalHead, installedHead });
            var clean = new List<long>();
            var installed = new List<long>();
            using (var fs = new FileStream(pak, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                foreach (long at in hits[0]) { byte[] b = ReadAt(fs, at, c.Size); if (b != null && Sha256(b) == c.CleanSha256) clean.Add(at); }
                foreach (long at in hits[1]) { byte[] b = ReadAt(fs, at, c.Size); if (b != null && Sha256(b) == c.InstalledSha256) installed.Add(at); }
            }
            int total = clean.Count + installed.Count;
            if (total == 0)
            {
                info.State = CacheState.NotFound;
                info.Detail = "блок запуска не найден в " + KsCacheRel + "\\" + version + "\\" + c.PakName;
            }
            else if (total > 1)
            {
                info.State = CacheState.Ambiguous;
                info.Detail = "найдено " + total + " подходящих блоков запуска в " + KsCacheRel + "\\" + version + "\\" + c.PakName;
            }
            else
            {
                info.State = clean.Count == 1 ? CacheState.Clean : CacheState.Installed;
                info.Offset = clean.Count == 1 ? clean[0] : installed[0];
            }
            return info;
        }

        // Offset from Saved/RussianPatchBackups/cache-launch-<ver>.json when the bridge is still there, otherwise -1.
        private long ReadCacheRecordOffset(string version, string pak)
        {
            CacheRecord r = ReadCacheRecord(CacheRecordPath(version));
            if (r == null || !string.Equals(Game(r.Pak), pak, StringComparison.OrdinalIgnoreCase)) return -1;
            using (var fs = new FileStream(pak, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                byte[] b = ReadAt(fs, r.Offset, r.Size);
                return b != null && Sha256(b) == r.InstalledSha256 ? r.Offset : -1;
            }
        }

        private class CacheRecord
        {
            public string Version, Pak, CleanSha256, InstalledSha256;
            public long Offset;
            public int Size;
        }

        private static CacheRecord ReadCacheRecord(string path)
        {
            if (!File.Exists(path)) return null;
            try
            {
                var d = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(path, Encoding.UTF8));
                var r = new CacheRecord
                {
                    Version = Convert.ToString(d["version"]),
                    Pak = Convert.ToString(d["pak"]).Replace('/', '\\'),
                    Offset = Convert.ToInt64(d["offset"]),
                    Size = Convert.ToInt32(d["size"]),
                    CleanSha256 = Convert.ToString(d["clean_sha256"]).ToLowerInvariant(),
                    InstalledSha256 = Convert.ToString(d["installed_sha256"]).ToLowerInvariant()
                };
                // A tampered record must not point outside Saved\kscache.
                if (!IsSafeRelativePath(r.Pak) || !r.Pak.StartsWith(KsCacheRel + "\\", StringComparison.OrdinalIgnoreCase)
                    || r.Offset < 0 || r.Size <= 0 || r.CleanSha256.Length != 64 || r.InstalledSha256.Length != 64) return null;
                return r;
            }
            catch (Exception) { return null; }
        }

        private void WriteCacheRecord(CacheInfo cache)
        {
            string rel = cache.PakPath.Substring(gameDir.TrimEnd('\\').Length + 1).Replace('\\', '/');
            var sb = new StringBuilder();
            sb.Append("{\n  \"version\": \"").Append(cache.Version).Append("\",\n");
            sb.Append("  \"pak\": \"").Append(rel.Replace("\"", "\\\"")).Append("\",\n");
            sb.Append("  \"offset\": ").Append(cache.Offset).Append(",\n");
            sb.Append("  \"size\": ").Append(game.Cache.Size).Append(",\n");
            sb.Append("  \"clean_sha256\": \"").Append(game.Cache.CleanSha256).Append("\",\n");
            sb.Append("  \"installed_sha256\": \"").Append(game.Cache.InstalledSha256).Append("\"\n}\n");
            File.WriteAllText(CacheRecordPath(cache.Version), sb.ToString(), new UTF8Encoding(false));
        }

        // Writes the cache bridge over the clean block found by InspectCache; the original goes to the backup first.
        private bool WriteCacheBlock(CacheInfo cache, byte[] bridge, out string failReason)
        {
            failReason = "";
            CacheLaunch c = game.Cache;
            byte[] original;
            using (var fs = new FileStream(cache.PakPath, FileMode.Open, FileAccess.ReadWrite, FileShare.Read))
            {
                original = ReadAt(fs, cache.Offset, c.Size);
                if (original == null || Sha256(original) != c.CleanSha256)
                {
                    failReason = "Блок запуска в кеше обновления изменился во время установки. Файлы игры не изменены.";
                    return false;
                }
                Directory.CreateDirectory(BackupDir);
                File.WriteAllBytes(CacheBackupPath(cache.Version), original);
                WriteCacheRecord(cache);

                fs.Position = cache.Offset;
                fs.Write(bridge, 0, bridge.Length);
                fs.Flush(true);
            }
            if (ReadBlockSha256(cache.PakPath, cache.Offset, c.Size) != c.InstalledSha256)
            {
                WriteBlock(cache.PakPath, cache.Offset, original);
                DeleteFile(CacheRecordPath(cache.Version));
                DeleteFile(CacheBackupPath(cache.Version));
                failReason = "После записи моста в кеш обновления блок не совпал с installed_sha256; оригинальный блок возвращён.";
                return false;
            }
            log("  -> Мост записан в " + KsCacheRel + "\\" + cache.Version + "\\" + c.PakName + " (смещение " + cache.Offset
                + "). Резервная копия блока: " + BackupDirRel + "\\" + CacheBackupPrefix + cache.Version + ".block");
            return true;
        }

        // Restores every cache block recorded in Saved/RussianPatchBackups. true when nothing of ours is left in the cache.
        private bool RestoreCacheBlocks()
        {
            if (!Directory.Exists(BackupDir)) return true;
            bool ok = true;
            foreach (string recordPath in Directory.GetFiles(BackupDir, CacheBackupPrefix + "*.json"))
            {
                string blockPath = Path.ChangeExtension(recordPath, ".block");
                CacheRecord r = ReadCacheRecord(recordPath);
                if (r == null) { log("  -> Повреждена запись " + Path.GetFileName(recordPath) + ": кеш не изменён."); ok = false; continue; }
                string pak = Game(r.Pak);
                if (!File.Exists(pak))
                {
                    log("  -> Кеш обновления " + r.Version + " удалён игрой: восстанавливать нечего.");
                    DeleteFile(recordPath);
                    DeleteFile(blockPath);
                    continue;
                }
                string current = ReadBlockSha256(pak, r.Offset, r.Size);
                if (current == r.CleanSha256)
                {
                    log("  -> Блок запуска в кеше " + r.Version + " уже оригинальный.");
                    DeleteFile(recordPath);
                    DeleteFile(blockPath);
                    continue;
                }
                if (current != r.InstalledSha256)
                {
                    log("  -> В кеше " + r.Version + " неизвестные данные на месте блока запуска (игра перекачала пак?): кеш не изменён.");
                    ok = false;
                    continue;
                }
                byte[] original = File.Exists(blockPath) ? File.ReadAllBytes(blockPath) : null;
                if (original == null || original.Length != r.Size || Sha256(original) != r.CleanSha256)
                {
                    log("  -> Нет корректной резервной копии блока кеша " + r.Version + ": кеш не изменён. Для отката используйте «Проверить файлы» в лаунчере.");
                    ok = false;
                    continue;
                }
                WriteBlock(pak, r.Offset, original);
                if (ReadBlockSha256(pak, r.Offset, r.Size) != r.CleanSha256)
                {
                    log("  -> ОШИБКА: после восстановления блок кеша " + r.Version + " не совпал с оригиналом.");
                    ok = false;
                    continue;
                }
                log("  -> Оригинальный блок запуска в кеше " + r.Version + " восстановлен.");
                DeleteFile(recordPath);
                DeleteFile(blockPath);
            }
            return ok;
        }

        // Positions of every pattern (all of the same length) in the file, streamed in 1 MB chunks (the cache pak is ~112 MB).
        private static List<long>[] FindAll(string path, byte[][] patterns)
        {
            var hits = new List<long>[patterns.Length];
            int m = patterns[0].Length;
            for (int p = 0; p < patterns.Length; p++)
            {
                if (patterns[p].Length != m) throw new ArgumentException("patterns of different length");
                hits[p] = new List<long>();
            }
            byte[] buf = new byte[(1 << 20) + m];
            int carry = 0;
            long bufStart = 0;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 1 << 16))
            {
                while (true)
                {
                    int n = fs.Read(buf, carry, buf.Length - carry);
                    if (n <= 0) break;
                    int len = carry + n;
                    for (int p = 0; p < patterns.Length; p++)
                    {
                        byte[] pat = patterns[p];
                        // Positions up to len - m only: the rest is scanned again with the next chunk.
                        int last = len - m;
                        byte first = pat[0];
                        for (int i = 0; i <= last; i++)
                        {
                            if (buf[i] != first) continue;
                            int j = 1;
                            while (j < pat.Length && buf[i + j] == pat[j]) j++;
                            if (j == pat.Length) hits[p].Add(bufStart + i);
                        }
                    }
                    int keep = Math.Min(m - 1, len);
                    Buffer.BlockCopy(buf, len - keep, buf, 0, keep);
                    bufStart += len - keep;
                    carry = keep;
                }
            }
            return hits;
        }

        private static string ReadBlockSha256(string path, long offset, int size)
        {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                byte[] b = ReadAt(fs, offset, size);
                return b == null ? null : Sha256(b);
            }
        }

        private static void WriteBlock(string path, long offset, byte[] data)
        {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.Read))
            {
                fs.Position = offset;
                fs.Write(data, 0, data.Length);
                fs.Flush(true);
            }
        }

        private static bool IsDigits(string s)
        {
            if (string.IsNullOrEmpty(s)) return false;
            foreach (char ch in s) if (ch < '0' || ch > '9') return false;
            return true;
        }

        private static byte[] FromHex(string hex)
        {
            byte[] b = new byte[hex.Length / 2];
            for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            return b;
        }

        // ------------------------------------------------------------ state

        public PakState InspectPak()
        {
            string pak = PakPath;
            if (!File.Exists(pak)) return PakState.Missing;
            long size = new FileInfo(pak).Length;
            bool sizeKnown = size == game.InstalledPakSize;
            foreach (var b in game.BasePaks) if (b.Size == size) sizeKnown = true;
            if (!sizeKnown) return PakState.Unknown;

            string sha = FileSha256(pak);
            if (sha == game.InstalledPakSha256 && size == game.InstalledPakSize) return PakState.Installed;
            foreach (var b in game.BasePaks)
            {
                if (sha == b.Sha256 && size == b.Size) return PakState.CleanSupported;
            }
            return PakState.Unknown;
        }

        // sha256 of the launch block at the known offset, or null if the pak is missing or too small.
        public string ReadLaunchBlockSha256()
        {
            string pak = PakPath;
            if (!File.Exists(pak)) return null;
            using (var fs = new FileStream(pak, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                byte[] block = ReadAt(fs, game.Offset, game.BlockSize);
                return block == null ? null : Sha256(block);
            }
        }

        public GamePatchStatus InspectStatus()
        {
            if (!Directory.Exists(gameDir)) return GamePatchStatus.InvalidPath;
            string bridge = Game(BridgeRel);
            string bridgeDisabled = bridge + ".disabled";
            string bootstrap = Game(BootstrapRel);

            // A hotpatch pakchunk0 in Saved/kscache overrides the base pak: the bridge counts only there.
            bool bridgeInPak = false;
            try
            {
                CacheInfo cache = InspectCache();
                bridgeInPak = cache.State == CacheState.NoCachePak
                    ? ReadLaunchBlockSha256() == game.InstalledBlockSha256
                    : cache.State == CacheState.Installed;
            }
            catch (IOException) { }
            bool modsPresent = (File.Exists(bridge) || File.Exists(bridgeDisabled)) && File.Exists(bootstrap);
            if (!bridgeInPak && !modsPresent) return GamePatchStatus.NotInstalled;

            if (File.Exists(bridgeDisabled) && !File.Exists(bridge)) return GamePatchStatus.InstalledDisabled;
            if (File.Exists(bootstrap))
            {
                try
                {
                    if (File.ReadAllText(bootstrap, Encoding.UTF8).Contains("RussianLocalization = false")) return GamePatchStatus.InstalledDisabled;
                }
                catch (IOException) { }
            }
            return bridgeInPak && File.Exists(bridge) ? GamePatchStatus.InstalledActive : GamePatchStatus.NotInstalled;
        }

        // ------------------------------------------------------------ install / update

        public bool Install(string payloadDir, out string failReason)
        {
            failReason = "";
            payloadDir = Path.GetFullPath(payloadDir);

            // 1. Payload: the bridge block must be exactly the one supported_game.json expects.
            string bridgeFile = Path.Combine(payloadDir, BridgeBlockPayloadRel);
            if (!File.Exists(bridgeFile)) { failReason = "В пакете нет блока моста: " + bridgeFile; return false; }
            byte[] bridge = File.ReadAllBytes(bridgeFile);
            if (bridge.Length != game.BlockSize || Sha256(bridge) != game.InstalledBlockSha256)
            {
                failReason = "Блок моста в пакете не совпадает с supported_game.json (размер " + bridge.Length + ", sha256 " + Sha256(bridge) + ").";
                return false;
            }
            byte[] cacheBridge = null;
            if (game.Cache != null)
            {
                string cacheFile = Path.Combine(payloadDir, game.Cache.Payload.Replace('/', '\\'));
                if (!File.Exists(cacheFile)) { failReason = "В пакете нет блока моста для кеша обновления: " + cacheFile; return false; }
                cacheBridge = File.ReadAllBytes(cacheFile);
                if (cacheBridge.Length != game.Cache.Size || Sha256(cacheBridge) != game.Cache.InstalledSha256)
                {
                    failReason = "Блок моста для кеша обновления в пакете не совпадает с supported_game.json (размер " + cacheBridge.Length + ").";
                    return false;
                }
            }
            List<string> files = GetPayloadFiles(payloadDir);
            if (files.Count == 0) { failReason = "В пакете нет файлов Binaries/ и Saved/."; return false; }
            if (!VerifyOwnedFiles(payloadDir, files, out failReason)) return false;

            // 2. Game version: never write anything into an unknown pak.
            log("[1/6] Проверка версии игры (SHA-256 всего pakchunk0)...");
            PakState state = InspectPak();
            if (state == PakState.Missing) { failReason = "Файл не найден: " + PakPath; return false; }
            if (state == PakState.Unknown)
            {
                failReason = "Версия игры не поддерживается этим русификатором (ожидается сборка " + game.GameBuild
                    + "). Файлы игры не изменены. Дождитесь обновления русификатора или проверьте файлы игры в лаунчере.";
                log("ОТКАЗ: " + failReason);
                return false;
            }
            log(state == PakState.CleanSupported
                ? "  -> Чистая поддерживаемая сборка игры " + game.GameBuild + "."
                : "  -> Мост уже установлен (pakchunk0 = установленное состояние), блок не перезаписывается.");

            // 3. Hotpatch pakchunk0 in Saved/kscache: all checks before anything is written.
            log("[2/6] Проверка кеша обновления (" + KsCacheRel + ")...");
            CacheInfo cache = InspectCache();
            switch (cache.State)
            {
                case CacheState.NoCachePak:
                    log("  -> В кеше обновления нет pakchunk0: мост нужен только в базовом pakchunk0.");
                    break;
                case CacheState.UnsupportedBuild:
                    failReason = "Игра обновилась, нужна новая версия русификатора (" + cache.Detail + "). Файлы игры не изменены.";
                    log("ОТКАЗ: " + failReason);
                    return false;
                case CacheState.NotFound:
                case CacheState.Ambiguous:
                    failReason = "Версия игры не поддерживается: " + cache.Detail + ". Файлы игры не изменены. Проверьте файлы игры в лаунчере.";
                    log("ОТКАЗ: " + failReason);
                    return false;
                case CacheState.Clean:
                    log("  -> Чистый блок запуска найден в " + KsCacheRel + "\\" + cache.Version + " (смещение " + cache.Offset + ").");
                    break;
                case CacheState.Installed:
                    log("  -> Мост уже установлен в " + KsCacheRel + "\\" + cache.Version + ", блок не перезаписывается.");
                    break;
            }

            MigrateLegacyBackup();

            // 4. Launch blocks: the cache first, the base pak second; a failed base write rolls the cache back.
            log("[3/6] Блоки запуска...");
            if (cache.State == CacheState.Clean)
            {
                if (!WriteCacheBlock(cache, cacheBridge, out failReason)) return false;
            }
            if (state == PakState.CleanSupported)
            {
                bool written;
                string why;
                try { written = WriteBridgeBlock(bridge, out why); }
                catch (Exception ex) { written = false; why = "Ошибка записи pakchunk0: " + ex.Message; }
                if (!written)
                {
                    failReason = why;
                    if (cache.State == CacheState.Clean)
                    {
                        RestoreCacheBlocks();
                        failReason += " Блок в кеше обновления возвращён.";
                    }
                    return false;
                }
            }
            else if (!HasValidBlockBackup())
            {
                log("  -> Внимание: резервной копии оригинального блока нет (мост ставился другим установщиком). При удалении русификатора блок восстановить не получится; для отката используйте «Проверить файлы» в лаунчере.");
            }

            // 4. Files: copy the new set, then delete files of the previous version that are gone now.
            log("[4/6] Копирование файлов русификатора (" + files.Count + ")...");
            List<string> previous = ReadInstalledList();
            foreach (string rel in files) CopyFile(Path.Combine(payloadDir, rel), Game(rel));
            DeleteFile(Game(BridgeRel) + ".disabled");
            if (previous != null)
            {
                var current = new HashSet<string>(files, StringComparer.OrdinalIgnoreCase);
                var stale = new List<string>();
                foreach (string rel in previous) if (!current.Contains(rel)) stale.Add(rel);
                foreach (string rel in stale) DeleteFile(Game(rel));
                PruneEmptyDirectories(stale);
                if (stale.Count > 0) log("  -> Удалено файлов прошлой версии: " + stale.Count);
            }
            WriteInstalledList(files);
            // Uninstall must use the hashes this version was installed with, even if a newer installer runs it.
            File.WriteAllText(Path.Combine(BackupDir, SupportedGame.FileName), game.ToJson(), new UTF8Encoding(false));

            // 5. BakedText.
            log("[5/6] BakedText (IoStore)...");
            if (!PatchBakedText(Path.Combine(payloadDir, BakedTextRel)))
            {
                log("  -> Предупреждение: часть блоков BakedText пропущена (контейнер другой версии или уже изменён).");
            }

            log("[6/6] Финальная проверка...");
            if (!VerifyInstallation())
            {
                failReason = "Финальная проверка установленного патча не прошла.";
                return false;
            }
            log("✔ Установка завершена.");
            return true;
        }

        private bool WriteBridgeBlock(byte[] bridge, out string failReason)
        {
            failReason = "";
            byte[] original;
            using (var fs = new FileStream(PakPath, FileMode.Open, FileAccess.ReadWrite, FileShare.Read))
            {
                original = ReadAt(fs, game.Offset, game.BlockSize);
                if (original == null || Sha256(original) != game.CleanBlockSha256)
                {
                    failReason = "Блок запуска в pakchunk0 не совпадает с оригиналом (clean_sha256). Файлы игры не изменены.";
                    return false;
                }
                Directory.CreateDirectory(BackupDir);
                if (!HasValidBlockBackup()) File.WriteAllBytes(BlockBackupPath, original);

                fs.Position = game.Offset;
                fs.Write(bridge, 0, bridge.Length);
                fs.Flush(true);
            }

            string after = FileSha256(PakPath);
            if (after != game.InstalledPakSha256)
            {
                using (var fs = new FileStream(PakPath, FileMode.Open, FileAccess.Write, FileShare.Read))
                {
                    fs.Position = game.Offset;
                    fs.Write(original, 0, original.Length);
                    fs.Flush(true);
                }
                failReason = "После записи моста pakchunk0 не совпал с installed_pak_sha256; оригинальный блок возвращён.";
                return false;
            }
            log("  -> Мост записан, pakchunk0 = installed_pak_sha256. Резервная копия блока: " + BackupDirRel + "\\" + BlockBackupName);
            return true;
        }

        private bool HasValidBlockBackup()
        {
            string path = BlockBackupPath;
            if (!File.Exists(path)) return false;
            byte[] data = File.ReadAllBytes(path);
            return data.Length == game.BlockSize && Sha256(data) == game.CleanBlockSha256;
        }

        // Old installers kept the block in Saved/Mods/Backup (deleted together with Saved/Mods).
        public void MigrateLegacyBackup()
        {
            string legacyDir = Game(LegacyBackupDirRel);
            string legacy = Path.Combine(legacyDir, LegacyBlockBackupName);
            if (!File.Exists(legacy)) return;
            Directory.CreateDirectory(BackupDir);
            if (!HasValidBlockBackup())
            {
                if (File.Exists(BlockBackupPath)) File.Delete(BlockBackupPath);
                File.Move(legacy, BlockBackupPath);
                log("  -> Резервная копия блока перенесена из Saved/Mods/Backup в " + BackupDirRel + ".");
            }
            else
            {
                File.Delete(legacy);
            }
            if (Directory.GetFileSystemEntries(legacyDir).Length == 0) Directory.Delete(legacyDir);
        }

        public bool VerifyInstallation()
        {
            if (ReadLaunchBlockSha256() != game.InstalledBlockSha256) { log("Проверка: в pakchunk0 нет блока моста."); return false; }
            CacheInfo cache = InspectCache();
            if (cache.State != CacheState.NoCachePak && cache.State != CacheState.Installed)
            {
                log("Проверка: в кеше обновления " + KsCacheRel + "\\" + cache.Version + " нет блока моста (" + cache.State + ").");
                return false;
            }
            foreach (string rel in new[] { BridgeRel, BootstrapRel, InitRel })
            {
                string path = Game(rel);
                if (!File.Exists(path) || new FileInfo(path).Length == 0) { log("Проверка: нет файла " + rel); return false; }
            }
            List<string> installed = ReadInstalledList();
            if (installed == null) { log("Проверка: нет списка файлов " + InstalledListName); return false; }
            foreach (string rel in installed)
            {
                if (!File.Exists(Game(rel))) { log("Проверка: нет файла " + rel); return false; }
            }
            log("  -> Проверено: мост в pakchunk0" + (cache.State == CacheState.Installed ? " и в кеше обновления " + cache.Version : "")
                + ", файлов русификатора: " + installed.Count);
            return true;
        }

        // ------------------------------------------------------------ uninstall

        // Removes only our files. The launch block is restored only when the current block is the bridge
        // and the backup is the clean original. cpdd_*settings.lua, DPS meter history and foreign files stay.
        public bool Uninstall(string payloadDir)
        {
            bool ok = true;
            MigrateLegacyBackup();

            log("[1/3] BakedText...");
            string bakedDir = Game(BakedTextRel);
            if (!File.Exists(Path.Combine(bakedDir, "manifest.json")) && !string.IsNullOrEmpty(payloadDir))
            {
                bakedDir = Path.Combine(payloadDir, BakedTextRel);
            }
            RestoreBakedText(bakedDir);

            log("[2/3] Блоки запуска (кеш обновления и pakchunk0)...");
            if (!RestoreCacheBlocks()) ok = false;
            bool blockClean = RestoreLaunchBlock();
            if (!blockClean) ok = false;

            log("[3/3] Файлы русификатора...");
            List<string> owned = ReadInstalledList();
            if (owned == null && !string.IsNullOrEmpty(payloadDir) && Directory.Exists(payloadDir))
            {
                owned = GetPayloadFiles(payloadDir);
                log("  -> Списка установленных файлов нет (установка старой версией): удаляются файлы из текущего пакета.");
            }
            if (owned == null)
            {
                log("  -> Список файлов русификатора не найден, файлы не удаляются.");
                ok = false;
            }
            else
            {
                foreach (string rel in owned) DeleteFile(Game(rel));
                DeleteFile(Game(BridgeRel) + ".disabled");
                var all = new List<string>(owned);
                all.Add(BridgeRel);
                PruneEmptyDirectories(all);
                log("  -> Удалено файлов: " + owned.Count);
            }

            DeleteFile(InstalledListPath);
            if (blockClean)
            {
                DeleteFile(BlockBackupPath);
                DeleteFile(Path.Combine(BackupDir, SupportedGame.FileName));
            }
            if (Directory.Exists(BackupDir) && Directory.GetFileSystemEntries(BackupDir).Length == 0) Directory.Delete(BackupDir);
            log(ok ? "✔ Русификатор удалён." : "Русификатор удалён с предупреждениями (см. выше).");
            return ok;
        }

        // true when the block is the clean original afterwards.
        private bool RestoreLaunchBlock()
        {
            string pak = PakPath;
            if (!File.Exists(pak)) { log("  -> pakchunk0 не найден, пропуск."); return false; }
            string current = ReadLaunchBlockSha256();
            if (current == game.CleanBlockSha256) { log("  -> Блок запуска уже оригинальный."); return true; }
            if (current != game.InstalledBlockSha256)
            {
                log("  -> В блоке запуска неизвестные данные (игра обновлена?): pakchunk0 не изменён. Проверьте файлы игры в лаунчере.");
                return false;
            }
            if (!HasValidBlockBackup())
            {
                log("  -> Нет корректной резервной копии оригинального блока: pakchunk0 не изменён. Для отката используйте «Проверить файлы» в лаунчере.");
                return false;
            }
            byte[] original = File.ReadAllBytes(BlockBackupPath);
            using (var fs = new FileStream(pak, FileMode.Open, FileAccess.ReadWrite, FileShare.Read))
            {
                fs.Position = game.Offset;
                fs.Write(original, 0, original.Length);
                fs.Flush(true);
            }
            if (ReadLaunchBlockSha256() != game.CleanBlockSha256)
            {
                log("  -> ОШИБКА: после восстановления блок не совпал с оригиналом.");
                return false;
            }
            log("  -> Оригинальный блок pakchunk0 восстановлен.");
            return true;
        }

        // ------------------------------------------------------------ owned files

        public static List<string> GetPayloadFiles(string payloadDir)
        {
            var list = new List<string>();
            string root = Path.GetFullPath(payloadDir).TrimEnd('\\');
            foreach (string top in PayloadRoots)
            {
                string dir = Path.Combine(root, top);
                if (!Directory.Exists(dir)) continue;
                foreach (string f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
                {
                    list.Add(f.Substring(root.Length + 1));
                }
            }
            list.Sort(StringComparer.OrdinalIgnoreCase);
            return list;
        }

        // owned_files.json (written into the data zip by tools/PackageRelease.ps1): [{path, sha256, size}].
        public static bool VerifyOwnedFiles(string payloadDir, List<string> files, out string failReason)
        {
            failReason = "";
            string path = Path.Combine(payloadDir, OwnedFilesName);
            if (!File.Exists(path)) return true;
            var serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            var root = serializer.Deserialize<Dictionary<string, object>>(File.ReadAllText(path, Encoding.UTF8));
            object listObj;
            if (root == null || !root.TryGetValue("files", out listObj) || !(listObj is IEnumerable))
            {
                failReason = OwnedFilesName + " повреждён.";
                return false;
            }
            var expected = new Dictionary<string, Dictionary<string, object>>(StringComparer.OrdinalIgnoreCase);
            foreach (object item in (IEnumerable)listObj)
            {
                var d = item as Dictionary<string, object>;
                if (d != null) expected[Convert.ToString(d["path"]).Replace('/', '\\')] = d;
            }
            if (expected.Count != files.Count)
            {
                failReason = "Состав пакета не совпадает с " + OwnedFilesName + " (" + files.Count + " файлов вместо " + expected.Count + ").";
                return false;
            }
            foreach (string rel in files)
            {
                Dictionary<string, object> d;
                if (!expected.TryGetValue(rel, out d)) { failReason = "Лишний файл в пакете: " + rel; return false; }
                string full = Path.Combine(payloadDir, rel);
                if (new FileInfo(full).Length != Convert.ToInt64(d["size"]) || FileSha256(full) != Convert.ToString(d["sha256"]).ToLowerInvariant())
                {
                    failReason = "Файл пакета повреждён: " + rel;
                    return false;
                }
            }
            return true;
        }

        public List<string> ReadInstalledList()
        {
            string path = InstalledListPath;
            if (!File.Exists(path)) return null;
            var serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            var root = serializer.Deserialize<Dictionary<string, object>>(File.ReadAllText(path, Encoding.UTF8));
            object listObj;
            if (root == null || !root.TryGetValue("files", out listObj) || !(listObj is IEnumerable)) return null;
            var list = new List<string>();
            foreach (object item in (IEnumerable)listObj)
            {
                string rel = Convert.ToString(item).Replace('/', '\\');
                if (IsSafeRelativePath(rel)) list.Add(rel);
            }
            return list;
        }

        private void WriteInstalledList(List<string> files)
        {
            Directory.CreateDirectory(BackupDir);
            var sb = new StringBuilder();
            sb.Append("{\n  \"format\": 1,\n  \"files\": [\n");
            for (int i = 0; i < files.Count; i++)
            {
                sb.Append("    \"").Append(files[i].Replace('\\', '/').Replace("\"", "\\\"")).Append('"');
                sb.Append(i + 1 < files.Count ? ",\n" : "\n");
            }
            sb.Append("  ]\n}\n");
            File.WriteAllText(InstalledListPath, sb.ToString(), new UTF8Encoding(false));
        }

        // Only Saved\... and Binaries\... relative paths without "..": a tampered list must not reach other folders.
        public static bool IsSafeRelativePath(string rel)
        {
            if (string.IsNullOrEmpty(rel) || Path.IsPathRooted(rel) || rel.Contains(":")) return false;
            foreach (string part in rel.Split('\\')) if (part == ".." || part == "." || part.Length == 0) return false;
            return rel.StartsWith(@"Saved\", StringComparison.OrdinalIgnoreCase) || rel.StartsWith(@"Binaries\", StringComparison.OrdinalIgnoreCase);
        }

        private void PruneEmptyDirectories(IEnumerable<string> removedFiles)
        {
            string saved = Game("Saved");
            string binaries = Game("Binaries");
            var dirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string rel in removedFiles) dirs.Add(Path.GetDirectoryName(Game(rel)));
            var ordered = new List<string>(dirs);
            ordered.Sort((a, b) => b.Length.CompareTo(a.Length));
            foreach (string start in ordered)
            {
                string dir = start;
                while (dir != null && dir.Length > saved.Length
                    && (dir.StartsWith(saved + "\\", StringComparison.OrdinalIgnoreCase) || dir.StartsWith(binaries + "\\", StringComparison.OrdinalIgnoreCase))
                    && !dir.Equals(Game(@"Binaries\Win64"), StringComparison.OrdinalIgnoreCase)
                    && Directory.Exists(dir) && Directory.GetFileSystemEntries(dir).Length == 0)
                {
                    Directory.Delete(dir);
                    dir = Path.GetDirectoryName(dir);
                }
            }
        }

        private static void CopyFile(string source, string target)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(target));
            if (File.Exists(target))
            {
                FileAttributes attrs = File.GetAttributes(target);
                if ((attrs & FileAttributes.ReadOnly) != 0) File.SetAttributes(target, attrs & ~FileAttributes.ReadOnly);
            }
            File.Copy(source, target, true);
        }

        private static void DeleteFile(string path)
        {
            if (!File.Exists(path)) return;
            FileAttributes attrs = File.GetAttributes(path);
            if ((attrs & FileAttributes.ReadOnly) != 0) File.SetAttributes(path, attrs & ~FileAttributes.ReadOnly);
            File.Delete(path);
        }

        // ------------------------------------------------------------ BakedText

        public class BakedManifest
        {
            public List<BakedBlock> blocks { get; set; }
        }

        public class BakedBlock
        {
            public string container { get; set; }
            public long container_size { get; set; }
            public long offset { get; set; }
            public int size { get; set; }
            public long original_offset { get; set; }
            public long replacement_offset { get; set; }
            public string original_sha256 { get; set; }
            public string replacement_sha256 { get; set; }
        }

        public bool PatchBakedText(string bakedDir)
        {
            return ProcessBakedText(bakedDir, true);
        }

        public bool RestoreBakedText(string bakedDir)
        {
            return ProcessBakedText(bakedDir, false);
        }

        // apply=true: original -> replacement; apply=false: replacement -> original.
        // Blocks are written only when the container has the manifest size and the current bytes match the expected hash.
        private bool ProcessBakedText(string bakedDir, bool apply)
        {
            string manifestPath = Path.Combine(bakedDir, "manifest.json");
            string blocksPath = Path.Combine(bakedDir, "blocks.bin");
            if (!File.Exists(manifestPath) || !File.Exists(blocksPath)) { log("  -> BakedText не найден, пропуск."); return true; }

            var serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            BakedManifest manifest = serializer.Deserialize<BakedManifest>(File.ReadAllText(manifestPath, Encoding.UTF8));
            var byContainer = new Dictionary<string, List<BakedBlock>>();
            foreach (var b in manifest.blocks)
            {
                if (!byContainer.ContainsKey(b.container)) byContainer[b.container] = new List<BakedBlock>();
                byContainer[b.container].Add(b);
            }

            int written = 0, already = 0, mismatched = 0, skippedContainers = 0;
            using (var bin = new FileStream(blocksPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                foreach (var kvp in byContainer)
                {
                    string path = Path.Combine(gameDir, kvp.Key.Replace('/', '\\'));
                    if (!File.Exists(path)) continue;
                    long expectedSize = kvp.Value[0].container_size;
                    if (expectedSize > 0 && new FileInfo(path).Length != expectedSize)
                    {
                        skippedContainers++;
                        log("  -> Пропущен контейнер другой версии: " + kvp.Key + " (размер " + new FileInfo(path).Length + ", ожидался " + expectedSize + ")");
                        continue;
                    }
                    using (var cs = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.Read))
                    {
                        foreach (var b in kvp.Value)
                        {
                            byte[] current = ReadAt(cs, b.offset, b.size);
                            string sha = current == null ? "" : Sha256(current);
                            string target = apply ? b.replacement_sha256 : b.original_sha256;
                            string source = apply ? b.original_sha256 : b.replacement_sha256;
                            if (sha.Equals(target, StringComparison.OrdinalIgnoreCase)) { already++; continue; }
                            if (!sha.Equals(source, StringComparison.OrdinalIgnoreCase)) { mismatched++; continue; }
                            byte[] data = ReadAt(bin, apply ? b.replacement_offset : b.original_offset, b.size);
                            cs.Position = b.offset;
                            cs.Write(data, 0, data.Length);
                            written++;
                        }
                    }
                }
            }
            log(string.Format("  -> BakedText: {0} {1}, уже было {2}, несовпадений {3}, пропущено контейнеров {4}.",
                apply ? "внедрено" : "восстановлено", written, already, mismatched, skippedContainers));
            return mismatched == 0 && skippedContainers == 0;
        }

        // ------------------------------------------------------------ helpers

        private static byte[] ReadAt(Stream s, long offset, int size)
        {
            if (s.Length < offset + size) return null;
            s.Position = offset;
            byte[] buf = new byte[size];
            int total = 0;
            while (total < size)
            {
                int n = s.Read(buf, total, size - total);
                if (n <= 0) return null;
                total += n;
            }
            return buf;
        }

        public static string Sha256(byte[] data)
        {
            using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(data));
        }

        public static string FileSha256(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 1 << 20))
            {
                return Hex(sha.ComputeHash(fs));
            }
        }

        private static string Hex(byte[] hash)
        {
            var sb = new StringBuilder(hash.Length * 2);
            foreach (byte b in hash) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
    }
}
