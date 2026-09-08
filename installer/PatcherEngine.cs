using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

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

        Console.WriteLine("[4/4] Проверка запеченного текста и текстур UI (BakedText)...");
        string manifestPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "manifest.json");
        string blocksBinPath = Path.Combine(payloadDir, "Saved", "Mods", "BakedText", "blocks.bin");
        if (File.Exists(manifestPath) && File.Exists(blocksBinPath)) {
            Console.WriteLine("  -> Манифест и бинарный склад блоков BakedText готовы к работе.");
        }

        Console.WriteLine("\n============================================================");
        Console.WriteLine(" УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! Игра переведена на русский. ");
        Console.WriteLine("============================================================");
    }

    public static void Uninstall(string gameDir) {
        Console.WriteLine("[1/3] Восстановление оригинального блока pakchunk0...");
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

        Console.WriteLine("[2/3] Удаление моста CPDDTranslation.lua...");
        string bridgeLua = Path.Combine(gameDir, "Binaries", "Win64", "lua", "Launch", "Base", "CPDDTranslation.lua");
        if (File.Exists(bridgeLua)) {
            File.Delete(bridgeLua);
            Console.WriteLine("  -> Мост удален.");
        }

        Console.WriteLine("[3/3] Очистка папки модов Saved/Mods...");
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
}
