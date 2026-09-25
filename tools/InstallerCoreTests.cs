// InstallerCoreTests - scenario tests for installer/InstallerCore.cs on synthetic game folders.
// Build: tools/BuildTools.ps1 -Only InstallerCoreTests. Run: tools/InstallerCoreTests.exe
// Works only inside <repo>/temp/installer-tests: fake paks are random bytes, the real game is never touched.
using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using LotmRussianPatcher;

public static class InstallerCoreTests
{
    const long PakSize = 256 * 1024;
    const long Offset = 100003;
    const int BlockSize = 4660;
    const string ContainerRel = @"Content\Paks\pakchunk9999-Windows.ucas";

    static string testRoot;
    static int passed, failed;
    static readonly Random rng = new Random(20260925);

    public static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        string repo = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
        string tempDir = Path.Combine(repo, "temp");
        testRoot = Path.Combine(tempDir, "installer-tests");
        if (args.Length == 2 && args[0] == "--check-payload")
        {
            // Check an extracted data zip (tools/PackageRelease.ps1 layout) the way the installer does.
            string payload = Path.GetFullPath(args[1]);
            if (!IsUnder(payload, tempDir)) { Console.Error.WriteLine("Refusing to read outside " + tempDir); return 2; }
            string why;
            var files = InstallerCore.GetPayloadFiles(payload);
            bool okOwned = InstallerCore.VerifyOwnedFiles(payload, files, out why);
            var game = SupportedGame.Load(payload);
            bool okBridge = InstallerCore.FileSha256(Path.Combine(payload, InstallerCore.BridgeBlockPayloadRel)) == game.InstalledBlockSha256;
            Console.WriteLine("files=" + files.Count + " owned_files=" + (okOwned ? "OK" : "FAIL " + why) + " supported_game=" + game.GameBuild + " bridge=" + (okBridge ? "OK" : "FAIL"));
            return okOwned && okBridge ? 0 : 1;
        }
        if (args.Length > 0) testRoot = Path.GetFullPath(args[0]);
        if (!IsUnder(testRoot, tempDir))
        {
            Console.Error.WriteLine("Refusing to run outside " + tempDir + ": " + testRoot);
            return 2;
        }
        if (Directory.Exists(testRoot)) Directory.Delete(testRoot, true);
        Directory.CreateDirectory(testRoot);
        Console.WriteLine("InstallerCoreTests in " + testRoot);

        Run("installer/supported_game.json parses and matches the bridge", RealSupportedGameParses);
        Run("clean pak: installs, pak = installed_pak_sha256, backup = clean", CleanInstall);
        Run("installed pak: install does not write the pak", InstalledPakNotWritten);
        Run("unknown pak: refuses, pak unchanged, nothing copied", UnknownPakRefused);
        Run("unknown pak of the supported size: refuses", UnknownSameSizeRefused);
        Run("bridge block in payload differs: refuses", BadBridgeRefused);
        Run("owned_files.json mismatch: refuses", OwnedFilesMismatchRefused);
        Run("update removes files of the previous version only", UpdateRemovesStale);
        Run("uninstall restores block and removes only own files", UninstallRestores);
        Run("uninstall: tampered backup -> pak untouched", UninstallTamperedBackup);
        Run("uninstall: unknown block -> pak untouched", UninstallUnknownBlock);
        Run("legacy Saved/Mods/Backup is migrated", LegacyBackupMigrated);
        Run("old toggle state (.disabled): install repairs the start", RepairDisabledStart);
        Run("BakedText: container_size mismatch is skipped", BakedTextSizeMismatch);
        Run("unsafe paths in installed_files.json are ignored", UnsafeInstalledList);

        Console.WriteLine();
        Console.WriteLine("passed " + passed + ", failed " + failed);
        return failed == 0 ? 0 : 1;
    }

    // ------------------------------------------------------------ fixture

    class Fixture
    {
        public string GameDir, PayloadDir;
        public byte[] CleanPak, Bridge;
        public SupportedGame Game;
        public List<string> Log = new List<string>();
        public InstallerCore Core() { return new InstallerCore(GameDir, Game, s => Log.Add(s)); }
        public string PakPath { get { return Path.Combine(GameDir, @"Content\Paks\pakchunk0-Windows.pak"); } }
        public string G(string rel) { return Path.Combine(GameDir, rel); }
    }

    static Fixture NewFixture(string name)
    {
        var f = new Fixture();
        string dir = Path.Combine(testRoot, name);
        f.GameDir = Path.Combine(dir, "game");
        f.PayloadDir = Path.Combine(dir, "payload");
        AssertUnderTemp(f.GameDir);

        f.CleanPak = RandomBytes((int)PakSize);
        f.Bridge = RandomBytes(BlockSize);
        byte[] installedPak = (byte[])f.CleanPak.Clone();
        Array.Copy(f.Bridge, 0, installedPak, Offset, BlockSize);
        byte[] cleanBlock = new byte[BlockSize];
        Array.Copy(f.CleanPak, Offset, cleanBlock, 0, BlockSize);

        f.Game = new SupportedGame
        {
            Source = "test",
            GameBuild = "0.0.test",
            Offset = Offset,
            BlockSize = BlockSize,
            CleanBlockSha256 = InstallerCore.Sha256(cleanBlock),
            InstalledBlockSha256 = InstallerCore.Sha256(f.Bridge),
            InstalledPakSha256 = InstallerCore.Sha256(installedPak),
            InstalledPakSize = PakSize
        };
        f.Game.BasePaks.Add(new BasePak { Name = "test base", Sha256 = InstallerCore.Sha256(f.CleanPak), Size = PakSize });

        WriteBytes(f.PakPath, f.CleanPak);
        Directory.CreateDirectory(f.G(@"Binaries\Win64\lua\Launch\Base"));
        WriteBytes(f.G(@"Binaries\Win64\C7-Win64-Shipping.exe.stub"), RandomBytes(64));
        // Foreign files that must survive install, update and uninstall.
        WriteText(f.G(@"Saved\Mods\lua\cpdd_patcher_settings.lua"), "return {\n    DpsMeterMode = \"external\",\n    DesktopChatUI = true,\n}\n");
        WriteText(f.G(@"Saved\Mods\lua\cpdd_user_settings.lua"), "return { StatisticsEverywhere = false }\n");
        WriteText(f.G(@"Saved\Mods\dps-meter-position-v2.txt"), "10,20\n");
        WriteText(f.G(@"Saved\Mods\other_mod\foreign.lua"), "return {}\n");
        WriteText(f.G(@"Saved\Config\Windows\Engine.ini"), "[Core.System]\n");

        MakePayload(f, f.PayloadDir, true);
        return f;
    }

    static void MakePayload(Fixture f, string dir, bool withExtra)
    {
        WriteBytes(Path.Combine(dir, InstallerCore.BridgeBlockPayloadRel), f.Bridge);
        WriteText(Path.Combine(dir, InstallerCore.BridgeRel), "-- bridge\n");
        WriteText(Path.Combine(dir, InstallerCore.BootstrapRel), "local Loader = {\n    Version = \"0.4.5-RU\",\n    Language = \"ru\",\n    RussianLocalization = true,\n}\n");
        WriteText(Path.Combine(dir, InstallerCore.InitRel), "-- init\n");
        WriteText(Path.Combine(dir, @"Saved\Mods\lua\mods\cpdd_runtime_fixes\RuntimeTextGemini_000.lua"), "return {}\n");
        if (withExtra) WriteText(Path.Combine(dir, @"Saved\Mods\lua\mods\cpdd_runtime_fixes\Obsolete_v1.lua"), "return {}\n");
    }

    static void WriteOwnedFiles(string payloadDir)
    {
        var sb = new StringBuilder("{\n  \"files\": [\n");
        var files = InstallerCore.GetPayloadFiles(payloadDir);
        for (int i = 0; i < files.Count; i++)
        {
            string full = Path.Combine(payloadDir, files[i]);
            sb.AppendFormat("    {{ \"path\": \"{0}\", \"sha256\": \"{1}\", \"size\": {2} }}{3}\n",
                files[i].Replace('\\', '/'), InstallerCore.FileSha256(full), new FileInfo(full).Length, i + 1 < files.Count ? "," : "");
        }
        sb.Append("  ]\n}\n");
        WriteText(Path.Combine(payloadDir, InstallerCore.OwnedFilesName), sb.ToString());
    }

    // ------------------------------------------------------------ scenarios

    static void CleanInstall()
    {
        var f = NewFixture("clean");
        WriteOwnedFiles(f.PayloadDir);
        var core = f.Core();
        Assert(core.InspectPak() == PakState.CleanSupported, "pak state before = CleanSupported");
        string reason;
        Assert(core.Install(f.PayloadDir, out reason), "install succeeds: " + reason);
        Assert(InstallerCore.FileSha256(f.PakPath) == f.Game.InstalledPakSha256, "pak = installed_pak_sha256");
        Assert(core.InspectPak() == PakState.Installed, "pak state after = Installed");
        Assert(InstallerCore.FileSha256(core.BlockBackupPath) == f.Game.CleanBlockSha256, "backup in Saved/RussianPatchBackups = clean block");
        Assert(File.Exists(f.G(InstallerCore.BridgeRel)) && File.Exists(f.G(InstallerCore.InitRel)), "files copied");
        Assert(core.ReadInstalledList().Count == 5, "installed_files.json lists the 5 payload files");
        Assert(core.InspectStatus() == GamePatchStatus.InstalledActive, "status InstalledActive");
        var saved = SupportedGame.Load(core.BackupDir);
        Assert(saved != null && saved.ToJson() == f.Game.ToJson(), "supported_game.json saved next to the backup (round trip)");
    }

    static void RealSupportedGameParses()
    {
        string repo = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
        var g = SupportedGame.Parse(File.ReadAllText(Path.Combine(repo, @"installer\supported_game.json")));
        Assert(g.GameBuild == "1.2018737.2044036", "game_build");
        Assert(g.Offset == 427225161 && g.BlockSize == 4660, "launch block offset/size");
        Assert(g.InstalledBlockSha256 == InstallerCore.FileSha256(Path.Combine(repo, @"patch_payload\bridge\LaunchInstance.native-bridge.padded.oodle")), "bridge in patch_payload = installed_sha256");
        Assert(g.BasePaks.Count == 1 && g.BasePaks[0].Size == 446910011, "supported base pak");
        Assert(SupportedGame.Parse(g.ToJson()).ToJson() == g.ToJson(), "ToJson round trip");
    }

    static void InstalledPakNotWritten()
    {
        var f = NewFixture("installed");
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "first install: " + reason);
        DateTime mtime = new DateTime(2020, 1, 1);
        File.SetLastWriteTimeUtc(f.PakPath, mtime);
        string before = InstallerCore.FileSha256(f.PakPath);
        Assert(f.Core().Install(f.PayloadDir, out reason), "second install: " + reason);
        Assert(File.GetLastWriteTimeUtc(f.PakPath) == mtime, "pak mtime unchanged (not opened for write)");
        Assert(InstallerCore.FileSha256(f.PakPath) == before, "pak sha unchanged");
    }

    static void UnknownPakRefused()
    {
        var f = NewFixture("unknown");
        byte[] other = RandomBytes((int)PakSize + 17);
        WriteBytes(f.PakPath, other);
        string before = InstallerCore.FileSha256(f.PakPath);
        var core = f.Core();
        Assert(core.InspectPak() == PakState.Unknown, "pak state Unknown");
        string reason;
        Assert(!core.Install(f.PayloadDir, out reason), "install refused");
        Assert(reason.Contains("не поддерживается"), "reason explains unsupported version: " + reason);
        Assert(InstallerCore.FileSha256(f.PakPath) == before, "pak sha before = after");
        Assert(!File.Exists(f.G(InstallerCore.BridgeRel)) && !File.Exists(f.G(InstallerCore.InitRel)), "no files copied");
        Assert(!Directory.Exists(core.BackupDir), "no backup dir created");
    }

    static void UnknownSameSizeRefused()
    {
        var f = NewFixture("unknown-same-size");
        byte[] other = (byte[])f.CleanPak.Clone();
        other[5] ^= 0xFF;   // same size, different content outside the launch block
        WriteBytes(f.PakPath, other);
        string before = InstallerCore.FileSha256(f.PakPath);
        string reason;
        Assert(!f.Core().Install(f.PayloadDir, out reason), "install refused");
        Assert(InstallerCore.FileSha256(f.PakPath) == before, "pak sha before = after");
    }

    static void BadBridgeRefused()
    {
        var f = NewFixture("bad-bridge");
        WriteBytes(Path.Combine(f.PayloadDir, InstallerCore.BridgeBlockPayloadRel), RandomBytes(BlockSize));
        string before = InstallerCore.FileSha256(f.PakPath);
        string reason;
        Assert(!f.Core().Install(f.PayloadDir, out reason), "install refused: " + reason);
        Assert(InstallerCore.FileSha256(f.PakPath) == before, "pak unchanged");
    }

    static void OwnedFilesMismatchRefused()
    {
        var f = NewFixture("owned-mismatch");
        WriteOwnedFiles(f.PayloadDir);
        WriteText(Path.Combine(f.PayloadDir, InstallerCore.InitRel), "-- corrupted\n");
        string before = InstallerCore.FileSha256(f.PakPath);
        string reason;
        Assert(!f.Core().Install(f.PayloadDir, out reason), "install refused: " + reason);
        Assert(InstallerCore.FileSha256(f.PakPath) == before, "pak unchanged");
    }

    static void UpdateRemovesStale()
    {
        var f = NewFixture("update");
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "v1 install: " + reason);
        string obsolete = f.G(@"Saved\Mods\lua\mods\cpdd_runtime_fixes\Obsolete_v1.lua");
        Assert(File.Exists(obsolete), "v1 file installed");

        string v2 = Path.Combine(testRoot, "update", "payload-v2");
        MakePayload(f, v2, false);
        WriteText(Path.Combine(v2, @"Saved\Mods\lua\mods\cpdd_runtime_fixes\New_v2.lua"), "return {}\n");
        Assert(f.Core().Install(v2, out reason), "v2 install: " + reason);
        Assert(!File.Exists(obsolete), "file of v1 missing in v2 is deleted");
        Assert(File.Exists(f.G(@"Saved\Mods\lua\mods\cpdd_runtime_fixes\New_v2.lua")), "new v2 file installed");
        AssertForeignFilesIntact(f);
    }

    static void UninstallRestores()
    {
        var f = NewFixture("uninstall");
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        var core = f.Core();
        Assert(core.Uninstall(f.PayloadDir), "uninstall ok");
        Assert(InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "pak = clean base");
        Assert(!File.Exists(f.G(InstallerCore.BridgeRel)) && !File.Exists(f.G(InstallerCore.BootstrapRel)) && !File.Exists(f.G(InstallerCore.InitRel)), "own files removed");
        Assert(!Directory.Exists(f.G(@"Saved\Mods\lua\mods\cpdd_runtime_fixes")), "empty own directory removed");
        Assert(!Directory.Exists(core.BackupDir), "backup dir removed");
        Assert(File.Exists(f.G(@"Binaries\Win64\C7-Win64-Shipping.exe.stub")), "game binaries intact");
        AssertForeignFilesIntact(f);
        Assert(core.InspectStatus() == GamePatchStatus.NotInstalled, "status NotInstalled");
    }

    static void UninstallTamperedBackup()
    {
        var f = NewFixture("uninstall-tampered");
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        var core = f.Core();
        WriteBytes(core.BlockBackupPath, RandomBytes(BlockSize));
        string before = InstallerCore.FileSha256(f.PakPath);
        Assert(!core.Uninstall(f.PayloadDir), "uninstall reports a warning");
        Assert(InstallerCore.FileSha256(f.PakPath) == before, "pak untouched");
        Assert(!File.Exists(f.G(InstallerCore.InitRel)), "own files still removed");
        AssertForeignFilesIntact(f);
    }

    static void UninstallUnknownBlock()
    {
        var f = NewFixture("uninstall-unknown");
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        byte[] updated = RandomBytes((int)PakSize);   // the game updated its pak after installation
        WriteBytes(f.PakPath, updated);
        string before = InstallerCore.FileSha256(f.PakPath);
        Assert(!f.Core().Uninstall(f.PayloadDir), "uninstall reports a warning");
        Assert(InstallerCore.FileSha256(f.PakPath) == before, "pak untouched");
    }

    static void LegacyBackupMigrated()
    {
        var f = NewFixture("legacy");
        byte[] cleanBlock = new byte[BlockSize];
        Array.Copy(f.CleanPak, Offset, cleanBlock, 0, BlockSize);
        // State left by an old installer: bridge in the pak, backup in Saved/Mods/Backup, no installed_files.json.
        byte[] installedPak = (byte[])f.CleanPak.Clone();
        Array.Copy(f.Bridge, 0, installedPak, Offset, BlockSize);
        WriteBytes(f.PakPath, installedPak);
        WriteBytes(f.G(@"Saved\Mods\Backup\LaunchInstance.original.block"), cleanBlock);

        string reason;
        var core = f.Core();
        Assert(core.Install(f.PayloadDir, out reason), "install over legacy: " + reason);
        Assert(!Directory.Exists(f.G(@"Saved\Mods\Backup")), "legacy backup dir removed");
        Assert(InstallerCore.FileSha256(core.BlockBackupPath) == f.Game.CleanBlockSha256, "backup moved to Saved/RussianPatchBackups");
        Assert(core.Uninstall(f.PayloadDir), "uninstall");
        Assert(InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "pak restored from migrated backup");
    }

    // State left by the old RU->EN toggle (the game did not start): .disabled bridge + RussianLocalization = false.
    static void RepairDisabledStart()
    {
        var f = NewFixture("repair-disabled");
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        string bridge = f.G(InstallerCore.BridgeRel);
        File.Move(bridge, bridge + ".disabled");
        string boot = File.ReadAllText(f.G(InstallerCore.BootstrapRel)).Replace("RussianLocalization = true", "RussianLocalization = false").Replace("Language = \"ru\"", "Language = \"en\"");
        WriteText(f.G(InstallerCore.BootstrapRel), boot);
        var core = f.Core();
        Assert(core.InspectStatus() == GamePatchStatus.InstalledDisabled, "old toggle state = InstalledDisabled");

        string pakBefore = InstallerCore.FileSha256(f.PakPath);
        DateTime mtime = new DateTime(2020, 1, 1);
        File.SetLastWriteTimeUtc(f.PakPath, mtime);
        Assert(core.Install(f.PayloadDir, out reason), "repair = normal install: " + reason);
        Assert(File.Exists(bridge) && !File.Exists(bridge + ".disabled"), "CPDDTranslation.lua back, .disabled removed");
        Assert(File.ReadAllText(f.G(InstallerCore.BootstrapRel)).Contains("RussianLocalization = true"), "bootstrap.lua from the payload");
        Assert(core.InspectStatus() == GamePatchStatus.InstalledActive, "status InstalledActive");
        Assert(InstallerCore.FileSha256(f.PakPath) == pakBefore && File.GetLastWriteTimeUtc(f.PakPath) == mtime, "pakchunk0 not written");
        AssertForeignFilesIntact(f);

        // Uninstall from the broken state removes the .disabled bridge as well.
        File.Move(bridge, bridge + ".disabled");
        Assert(core.Uninstall(f.PayloadDir), "uninstall while disabled");
        Assert(!File.Exists(bridge + ".disabled"), ".disabled bridge removed");
    }

    static void BakedTextSizeMismatch()
    {
        var f = NewFixture("baked");
        byte[] container = RandomBytes(8192);
        byte[] original = new byte[512];
        Array.Copy(container, 1024, original, 0, 512);
        byte[] replacement = RandomBytes(512);
        byte[] bin = new byte[1024];
        Array.Copy(original, 0, bin, 0, 512);
        Array.Copy(replacement, 0, bin, 512, 512);
        string baked = Path.Combine(f.PayloadDir, InstallerCore.BakedTextRel);
        WriteBytes(Path.Combine(baked, "blocks.bin"), bin);
        string manifestTemplate = "{{\"blocks\": [{{\"container\": \"Content/Paks/pakchunk9999-Windows.ucas\", \"container_size\": {0}, \"offset\": 1024, \"original_offset\": 0, \"original_sha256\": \"{1}\", \"replacement_offset\": 512, \"replacement_sha256\": \"{2}\", \"size\": 512}}]}}";
        WriteText(Path.Combine(baked, "manifest.json"), string.Format(manifestTemplate, container.Length + 1, InstallerCore.Sha256(original), InstallerCore.Sha256(replacement)));
        WriteBytes(f.G(ContainerRel), container);

        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install (BakedText skip is a warning): " + reason);
        Assert(InstallerCore.FileSha256(f.G(ContainerRel)) == InstallerCore.Sha256(container), "container of another size untouched");

        // Matching size: the block is patched and restored on uninstall.
        WriteText(Path.Combine(baked, "manifest.json"), string.Format(manifestTemplate, container.Length, InstallerCore.Sha256(original), InstallerCore.Sha256(replacement)));
        Assert(f.Core().Install(f.PayloadDir, out reason), "install with matching size: " + reason);
        Assert(InstallerCore.FileSha256(f.G(ContainerRel)) != InstallerCore.Sha256(container), "container patched");
        Assert(f.Core().Uninstall(f.PayloadDir), "uninstall");
        Assert(InstallerCore.FileSha256(f.G(ContainerRel)) == InstallerCore.Sha256(container), "container restored");
    }

    static void UnsafeInstalledList()
    {
        var f = NewFixture("unsafe-list");
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        string victim = Path.Combine(testRoot, "unsafe-list", "victim.txt");
        WriteText(victim, "keep\n");
        var core = f.Core();
        WriteText(core.InstalledListPath, "{\"files\": [\"../victim.txt\", \"..\\\\victim.txt\", \"C:/Windows/win.ini\", \"Content/Paks/pakchunk0-Windows.pak\", \"Saved/Mods/bootstrap.lua\"]}");
        Assert(core.ReadInstalledList().Count == 1, "only the Saved/ path is accepted");
        core.Uninstall(f.PayloadDir);
        Assert(File.Exists(victim), "file outside the game folder untouched");
        Assert(File.Exists(f.PakPath), "pak not deleted");
    }

    // ------------------------------------------------------------ helpers

    static void AssertForeignFilesIntact(Fixture f)
    {
        Assert(File.ReadAllText(f.G(@"Saved\Mods\lua\cpdd_patcher_settings.lua")).Contains("DpsMeterMode = \"external\""), "cpdd_patcher_settings.lua intact");
        Assert(File.Exists(f.G(@"Saved\Mods\lua\cpdd_user_settings.lua")), "cpdd_user_settings.lua intact");
        Assert(File.Exists(f.G(@"Saved\Mods\dps-meter-position-v2.txt")), "DPS meter history intact");
        Assert(File.Exists(f.G(@"Saved\Mods\other_mod\foreign.lua")), "foreign mod intact");
        Assert(File.Exists(f.G(@"Saved\Config\Windows\Engine.ini")), "Engine.ini intact");
    }

    static void Run(string name, Action test)
    {
        int before = failed;
        try { test(); }
        catch (Exception ex) { failed++; Console.WriteLine("  EXCEPTION " + ex.GetType().Name + ": " + ex.Message); }
        Console.WriteLine((failed == before ? "[PASS] " : "[FAIL] ") + name);
    }

    static void Assert(bool condition, string what)
    {
        if (condition) { passed++; return; }
        failed++;
        Console.WriteLine("  failed: " + what);
    }

    static bool IsUnder(string path, string dir)
    {
        string p = Path.GetFullPath(path).TrimEnd('\\') + "\\";
        string d = Path.GetFullPath(dir).TrimEnd('\\') + "\\";
        return p.StartsWith(d, StringComparison.OrdinalIgnoreCase) && p.Length > d.Length;
    }

    static void AssertUnderTemp(string path)
    {
        if (!IsUnder(path, testRoot)) throw new InvalidOperationException("path outside the test root: " + path);
    }

    static byte[] RandomBytes(int n)
    {
        byte[] b = new byte[n];
        rng.NextBytes(b);
        return b;
    }

    static void WriteBytes(string path, byte[] data)
    {
        AssertUnderTemp(path);
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllBytes(path, data);
    }

    static void WriteText(string path, string text)
    {
        AssertUnderTemp(path);
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllText(path, text, new UTF8Encoding(false));
    }
}
