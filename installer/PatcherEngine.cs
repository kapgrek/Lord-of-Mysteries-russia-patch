using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

public class PatcherEngine {
    public const int PAK_OFFSET = 427225161;
    public const int PAK_BLOCK_SIZE = 4660;
    public const string ORIGINAL_PAK_SHA256 = "566e72d677fc974ab172eb71a34cdc6623f1e0dd19d978de812a76a1820b7fc7";
    public const string PATCHED_PAK_SHA256 = "c031726986e09358bb18ff8a2b8ee5f0b4e65ce8ae8331eed2d7575c80b7efa9";

    public static void Main(string[] args) {
        Console.OutputEncoding = Encoding.UTF8;
        Console.WriteLine("============================================================");
        Console.WriteLine("   Lord of the Mysteries — Установщик русской локализации   ");
        Console.WriteLine("                      Версия 2.6-RU                         ");
        Console.WriteLine("============================================================\n");

        if (args.Length == 0) {
            Console.WriteLine("Использование: PatcherEngine.exe <путь_к_папке_игры> [install|uninstall]");
            return;
        }

        string gameDir = args[0];
        string action = args.Length > 1 ? args[1].ToLower() : "install";

        if (!Directory.Exists(gameDir)) {
            Console.WriteLine("ОШИБКА: Папка игры не существует: " + gameDir);
            return;
        }

        if (action == "uninstall") {
            Uninstall(gameDir);
        } else {
            Install(gameDir);
        }
    }

    public static void Install(string gameDir) {
        Console.WriteLine("[1/4] Проверка структуры игры в: " + gameDir);
        string pakPath = Path.Combine(gameDir, "Content", "Paks", "pakchunk0-Windows.pak");
        if (!File.Exists(pakPath)) {
            Console.WriteLine("ОШИБКА: Не найден основной pak-файл: " + pakPath);
            return;
        }

        string payloadDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "patch_payload");
        if (!Directory.Exists(payloadDir)) {
            payloadDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "patch_payload");
        }

        string bridgeBlockPath = Path.Combine(payloadDir, "bridge", "LaunchInstance.native-bridge.padded.oodle");
        if (!File.Exists(bridgeBlockPath)) {
            Console.WriteLine("ОШИБКА: Не найден блок моста: " + bridgeBlockPath);
            return;
        }

        byte[] bridgeBytes = File.ReadAllBytes(bridgeBlockPath);
        if (bridgeBytes.Length != PAK_BLOCK_SIZE) {
            Console.WriteLine("ОШИБКА: Неверный размер блока моста: " + bridgeBytes.Length);
            return;
        }

        Console.WriteLine("[2/4] Безопасная модификация pakchunk0 (No-Injection Bootstrap)...");
        using (FileStream fs = new FileStream(pakPath, FileMode.Open, FileAccess.ReadWrite)) {
            fs.Position = PAK_OFFSET;
            byte[] currentBytes = new byte[PAK_BLOCK_SIZE];
            fs.Read(currentBytes, 0, PAK_BLOCK_SIZE);

            string currentHash = ComputeSha256(currentBytes);
            if (currentHash == PATCHED_PAK_SHA256) {
                Console.WriteLine("  -> Блок запуска уже пропатчен.");
            } else if (currentHash == ORIGINAL_PAK_SHA256) {
                // Сохраняем резервную копию оригинального блока
                string backupDir = Path.Combine(gameDir, "Saved", "Mods", "Backup");
                Directory.CreateDirectory(backupDir);
                File.WriteAllBytes(Path.Combine(backupDir, "LaunchInstance.original.block"), currentBytes);

                fs.Position = PAK_OFFSET;
                fs.Write(bridgeBytes, 0, PAK_BLOCK_SIZE);
                Console.WriteLine("  -> Оригинальный блок сохранен, мост успешно установлен!");
            } else {
                Console.WriteLine("ВНИМАНИЕ: Неизвестный хеш блока (" + currentHash + "). Возможно, игра обновлена.");
                fs.Position = PAK_OFFSET;
                fs.Write(bridgeBytes, 0, PAK_BLOCK_SIZE);
            }
        }

        Console.WriteLine("[3/4] Копирование локализованных файлов (Saved/Mods, Binaries)...");
        CopyDirectory(Path.Combine(payloadDir, "Binaries"), Path.Combine(gameDir, "Binaries"));
        CopyDirectory(Path.Combine(payloadDir, "Saved"), Path.Combine(gameDir, "Saved"));

        Console.WriteLine("[4/4] Внедрение запеченного текста и текстур UI (BakedText)...");
        PatchBakedText(gameDir, payloadDir);

        Console.WriteLine("\n============================================================");
        Console.WriteLine(" УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! Игра переведена на русский. ");
        Console.WriteLine("============================================================\n");
    }

    public static void Uninstall(string gameDir) {
        Console.WriteLine("[1/4] Восстановление оригинального блока pakchunk0...");
        string pakPath = Path.Combine(gameDir, "Content", "Paks", "pakchunk0-Windows.pak");
        string backupFile = Path.Combine(gameDir, "Saved", "Mods", "Backup", "LaunchInstance.original.block");

        if (File.Exists(pakPath) && File.Exists(backupFile)) {
            byte[] orig = File.ReadAllBytes(backupFile);
            using (FileStream fs = new FileStream(pakPath, FileMode.Open, FileAccess.Write)) {
                fs.Position = PAK_OFFSET;
                fs.Write(orig, 0, orig.Length);
            }
            Console.WriteLine("  -> Оригинальный стартовый блок успешно восстановлен.");
        }

        Console.WriteLine("[2/4] Удаление моста CPDDTranslation.lua...");
        string bridgeLua = Path.Combine(gameDir, "Binaries", "Win64", "lua", "Launch", "Base", "CPDDTranslation.lua");
        if (File.Exists(bridgeLua)) {
            File.Delete(bridgeLua);
            Console.WriteLine("  -> Мост удален.");
        }

        Console.WriteLine("[3/4] Восстановление запеченного текста и текстур UI (BakedText)...");
        string payloadDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "patch_payload");
        if (!Directory.Exists(payloadDir)) {
            payloadDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "patch_payload");
        }
        RestoreBakedText(gameDir, payloadDir);

        Console.WriteLine("[4/4] Очистка папки модов Saved/Mods...");
        string modsDir = Path.Combine(gameDir, "Saved", "Mods");
        if (Directory.Exists(modsDir)) {
            try {
                Directory.Delete(modsDir, true);
                Console.WriteLine("  -> Папка модов удалена.");
            } catch (Exception ex) {
                Console.WriteLine("  -> Не удалось полностью удалить папку: " + ex.Message);
            }
        }

        Console.WriteLine("\nОткат выполнен успешно. Игра возвращена в исходное состояние.");
    }

    private static void CopyDirectory(string source, string target) {
        if (!Directory.Exists(source)) return;
        Directory.CreateDirectory(target);
        foreach (string file in Directory.GetFiles(source, "*.*", SearchOption.AllDirectories)) {
            string rel = file.Substring(source.Length + 1);
            string dest = Path.Combine(target, rel);
            Directory.CreateDirectory(Path.GetDirectoryName(dest));
            File.Copy(file, dest, true);
        }
    }

    private static string ComputeSha256(byte[] data) {
        using (SHA256 sha = SHA256.Create()) {
            byte[] hash = sha.ComputeHash(data);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < hash.Length; i++) sb.Append(hash[i].ToString("x2"));
            return sb.ToString();
        }
    }

    private static void PatchBakedText(string gameDir, string payloadDir) {
        string manifestPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "manifest.json");
        string blocksBinPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "blocks.bin");
        if (!File.Exists(manifestPath) || !File.Exists(blocksBinPath)) {
            Console.WriteLine("  -> Файлы BakedText не найдены, пропуск.");
            return;
        }

        Console.WriteLine("  -> Чтение манифеста BakedText...");
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        serializer.MaxJsonLength = int.MaxValue;
        ManifestData manifest = serializer.Deserialize<ManifestData>(File.ReadAllText(manifestPath, Encoding.UTF8));

        Dictionary<string, List<BlockEntry>> byContainer = new Dictionary<string, List<BlockEntry>>();
        foreach (BlockEntry b in manifest.blocks) {
            if (!byContainer.ContainsKey(b.container)) {
                byContainer[b.container] = new List<BlockEntry>();
            }
            byContainer[b.container].Add(b);
        }

        int totalPatched = 0;
        int totalAlready = 0;
        int totalErrors = 0;

        using (FileStream binStream = new FileStream(blocksBinPath, FileMode.Open, FileAccess.Read, FileShare.Read)) {
            foreach (var kvp in byContainer) {
                string cPath = Path.Combine(gameDir, kvp.Key);
                if (!File.Exists(cPath)) {
                    continue;
                }

                using (FileStream cStream = new FileStream(cPath, FileMode.Open, FileAccess.ReadWrite, FileShare.Read)) {
                    foreach (BlockEntry b in kvp.Value) {
                        byte[] current = new byte[b.size];
                        cStream.Position = b.offset;
                        cStream.Read(current, 0, b.size);
                        string currentHash = ComputeSha256(current);

                        if (currentHash.Equals(b.replacement_sha256, StringComparison.OrdinalIgnoreCase)) {
                            totalAlready++;
                            continue;
                        }

                        if (!currentHash.Equals(b.original_sha256, StringComparison.OrdinalIgnoreCase)) {
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

        Console.WriteLine("  -> BakedText: пропатчено {0} блоков, уже было пропатчено {1}, ошибок {2}.", totalPatched, totalAlready, totalErrors);
    }

    private static void RestoreBakedText(string gameDir, string payloadDir) {
        string manifestPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "manifest.json");
        string blocksBinPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "blocks.bin");
        if (!File.Exists(manifestPath) || !File.Exists(blocksBinPath)) {
            return;
        }

        Console.WriteLine("  -> Чтение манифеста BakedText для отката...");
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        serializer.MaxJsonLength = int.MaxValue;
        ManifestData manifest = serializer.Deserialize<ManifestData>(File.ReadAllText(manifestPath, Encoding.UTF8));

        Dictionary<string, List<BlockEntry>> byContainer = new Dictionary<string, List<BlockEntry>>();
        foreach (BlockEntry b in manifest.blocks) {
            if (!byContainer.ContainsKey(b.container)) {
                byContainer[b.container] = new List<BlockEntry>();
            }
            byContainer[b.container].Add(b);
        }

        int totalRestored = 0;
        int totalAlready = 0;
        int totalErrors = 0;

        using (FileStream binStream = new FileStream(blocksBinPath, FileMode.Open, FileAccess.Read, FileShare.Read)) {
            foreach (var kvp in byContainer) {
                string cPath = Path.Combine(gameDir, kvp.Key);
                if (!File.Exists(cPath)) {
                    continue;
                }

                using (FileStream cStream = new FileStream(cPath, FileMode.Open, FileAccess.ReadWrite, FileShare.Read)) {
                    foreach (BlockEntry b in kvp.Value) {
                        byte[] current = new byte[b.size];
                        cStream.Position = b.offset;
                        cStream.Read(current, 0, b.size);
                        string currentHash = ComputeSha256(current);

                        if (currentHash.Equals(b.original_sha256, StringComparison.OrdinalIgnoreCase)) {
                            totalAlready++;
                            continue;
                        }

                        if (!currentHash.Equals(b.replacement_sha256, StringComparison.OrdinalIgnoreCase)) {
                            totalErrors++;
                            continue;
                        }

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

        Console.WriteLine("  -> BakedText: восстановлено {0} блоков, уже было оригиналом {1}, ошибок {2}.", totalRestored, totalAlready, totalErrors);
    }

    public class ManifestData {
        public List<BlockEntry> blocks { get; set; }
    }

    public class BlockEntry {
        public string container { get; set; }
        public long offset { get; set; }
        public int size { get; set; }
        public long original_offset { get; set; }
        public long replacement_offset { get; set; }
        public string original_sha256 { get; set; }
        public string replacement_sha256 { get; set; }
    }
}
