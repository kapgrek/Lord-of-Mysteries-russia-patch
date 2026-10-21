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
            bool okRoot = PayloadSource.FindPayloadRoot(payload) == payload;
            string cacheFile = game.Cache == null ? null : Path.Combine(payload, game.Cache.Payload.Replace('/', '\\'));
            bool okCache = game.Cache != null && File.Exists(cacheFile) && InstallerCore.FileSha256(cacheFile) == game.Cache.InstalledSha256;
            Console.WriteLine("files=" + files.Count + " owned_files=" + (okOwned ? "OK" : "FAIL " + why) + " supported_game=" + game.GameBuild
                + " bridge=" + (okBridge ? "OK" : "FAIL") + " cache_bridge=" + (okCache ? "OK" : "FAIL") + " payload_root=" + (okRoot ? "OK" : "FAIL"));
            return okOwned && okBridge && okCache && okRoot ? 0 : 1;
        }
        if (args.Length == 2 && args[0] == "--probe-cache")
        {
            // InspectCache on a copy of a real game folder (temp/real-kscache/C7) with installer/supported_game.json.
            string game = Path.GetFullPath(args[1]);
            if (!IsUnder(game, tempDir)) { Console.Error.WriteLine("Refusing to read outside " + tempDir); return 2; }
            var sg = SupportedGame.Parse(File.ReadAllText(Path.Combine(repo, @"installer\supported_game.json")));
            CacheInfo ci = new InstallerCore(game, sg, null).InspectCache();
            Console.WriteLine("State: " + ci.State + ", Offset: " + ci.Offset + ", Version: " + ci.Version + ", AssetsVersion: " + ci.AssetsVersion
                + ", Entry: " + (ci.EntryRelPath ?? "-") + ", PakSize: " + ci.PakSize);
            Console.WriteLine("Hits: " + InstallerCore.DescribeHits(ci.Hits, 50));
            Console.WriteLine("Detail: " + ci.Detail);
            return 0;
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
        // Never the real %LOCALAPPDATA%\AbsoluteRU or Desktop.
        InstallerLog.Dir = Path.Combine(testRoot, "installer-log");
        LogCollector.DesktopDir = Path.Combine(testRoot, "desktop");

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
        Run("kscache: install writes the bridge into the cache pak and the base pak", CacheInstall);
        Run("kscache: second install does not write either pak", CacheReinstall);
        Run("kscache: uninstall restores the cache block and the base block", CacheUninstall);
        Run("kscache: unknown manifest -> 'game updated', nothing written", CacheUnknownManifest);
        Run("kscache: two matching blocks -> refused, nothing written", CacheTwoMatches);
        Run("kscache: bridge already in the cache (no record) -> not rewritten", CacheAlreadyInstalled);
        Run("kscache: no pakchunk0 in the cache -> base pak only", CacheNoPak);
        Run("kscache: base pak write fails -> cache block rolled back", CacheRollback);
        Run("kscache: game re-downloads the cache pak -> status not active, uninstall leaves it", CacheReplacedByGame);
        Run("local.cache: dead + live copy -> Clean at the live one, dead untouched", CacheDeadAndLive);
        Run("local.cache: three copies, live last -> Clean at the last", CacheThreeLiveLast);
        Run("local.cache: the only copy is dead -> NotFound, nothing written", CacheOnlyDead);
        Run("local.cache: two live copies -> Ambiguous", CacheTwoLive);
        Run("local.cache: missing / truncated / bad len -> old behaviour", CacheBrokenLocalCache);
        Run("local.cache: record in a dead copy -> reinstall to the live one, uninstall restores both", CacheRecordInDeadCopy);
        Run("incremental hotpatch: bridge in the older folder by entry_id -> Installed, nothing written", CacheIncrementalInstalled);
        Run("incremental hotpatch: clean block in the older folder -> bridge written there, uninstall restores", CacheIncrementalClean);
        Run("entry_id: record found, foreign bytes -> NotFound, nothing written", CacheEntryForeignBytes);
        Run("entry_id: two records with the prefix -> Ambiguous", CacheEntryTwoRecords);
        Run("other manifest, live clean block in the AssetsVersion folder -> Clean", CacheManifestChangedBlockClean);
        Run("supported_game.json: old backup with launch_block still works", OldBackupFormat);
        Run("supported_game.json: format 2, min_installer_version", Format2AndMinInstaller);
        Run("options: cpdd_patcher_settings.lua defaults, CPDD format, round trip", OptionsSettingsRoundTrip);
        Run("options: foreign cpdd_patcher_settings.lua is not overwritten", OptionsForeignSettings);
        Run("options: Visual Clarity block in Engine.ini", OptionsVisualClarity);
        Run("options: uninstall keeps settings, removes Visual Clarity", OptionsUninstall);
        Run("payload: nothing is guessed next to the exe", PayloadNoGuessing);
        Run("payload: exact data zip next to the exe, release.json check", PayloadSideZip);
        Run("payload: --payload folder / zip", PayloadExplicit);
        Run("payload: cache only with matching release.json", PayloadCache);
        Run("versions: installed Init.lua VERSION and comparison", VersionsCompare);
        Run("self-update: IsNewer, skip reasons, texts", SelfUpdateIsNewer);
        Run("self-update: release.json patcher_asset (build/release.json and sample)", SelfUpdateReleaseJson);
        Run("self-update: wrong SHA-256 / size -> null, .new removed, exe intact", SelfUpdateBadDownload);
        Run("self-update: swap -> new exe in place, old one is .old, cleanup", SelfUpdateSwap);
        Run("self-update: exe locked -> rollback, new exe in the AppData fallback", SelfUpdateLockedFallback);
        Run("self-update: CleanupOld with free and busy files", SelfUpdateCleanup);
        Run("logs: 3 newest C7*.log + info.txt, rerun, open file, no logs", LogCollectorCopies);
        Run("logs: exe folder not writable -> Desktop", LogCollectorFallback);
        Run("installer.log: header, lines, rotation over 1 MB", InstallerLogWrites);
        Run("markup: MainWindow.xaml / HowToPlayWindow.xaml load, all names found", InSta(MarkupLoads));
        Run("links.json: embedded links valid, bad ones dropped", LinksValidation);
        Run("HowToPlay.md -> FlowDocument: sections, lists, links, image", InSta(HowToPlayParses));

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
        Assert(g.Cache != null && g.Cache.Size == 5258 && g.Cache.PakName == "pakchunk0-Windows.pak", "cache_launch size / pak name");
        string cacheBridge = Path.Combine(repo, @"patch_payload\" + g.Cache.Payload.Replace('/', '\\'));
        Assert(File.Exists(cacheBridge) && InstallerCore.FileSha256(cacheBridge) == g.Cache.InstalledSha256, "cache-startup.oodle in patch_payload = cache_launch.installed_sha256");
        Assert(File.Exists(cacheBridge) && Hex(File.ReadAllBytes(cacheBridge), 64) == g.Cache.InstalledHeadHex, "installed_head_hex = first 64 bytes of cache-startup.oodle");
        Assert(g.Cache.ManifestSha256 == "6d23b1cf198b17efe9e2e132d1f6420d2f6dfdf439ba8d61534901d1f6d00b24", "manifest of build 2218968");
        Assert(g.Cache.EntryId == "e5b5a377c686bc9e96abc007", "cache_launch.entry_id from CPDD release.json");
        Assert(SupportedGame.Parse(g.ToJson()).Cache.EntryId == g.Cache.EntryId, "entry_id survives the round trip");
        Assert(SupportedGame.Parse(g.ToJson()).ToJson() == g.ToJson(), "ToJson round trip");
        Assert(SupportedGame.Parse(g.ToJson()).Cache.OriginalHeadHex == g.Cache.OriginalHeadHex, "cache_launch survives the round trip");
        string raw = File.ReadAllText(Path.Combine(repo, @"installer\supported_game.json"));
        Assert(g.Format == 2 && raw.Contains("\"base_launch_block\"") && !raw.Contains("\"launch_block\""), "format 2: base_launch_block, no launch_block (installers before 3.1.1 refuse)");
        Assert(g.MinInstallerVersion == "3.1.1-RU" && PatcherBackend.InstallerTooOld(g) == null, "min_installer_version 3.1.1-RU, this installer passes");
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

    // ------------------------------------------------------------ kscache (hotpatch pakchunk0)

    const int CacheBlockSize = 5258;
    const string CacheVersion = "777001";
    const string ManifestId = "555001";

    class CacheFixture
    {
        public byte[] CleanPak, Original, Bridge, Manifest;
        public long Offset;
        public string PakPath, ManifestPath;
    }

    // Saved/kscache: AssetsVersion.txt, package_<id>.manifest, <ver>/pakchunk0-Windows.pak of random bytes
    // with the clean launch block at a random offset (copies > 1 puts it there several times).
    static CacheFixture AddCache(Fixture f, int copies)
    {
        int len = 1200 * 1024 + rng.Next(1, 4096);
        var offsets = new List<long>();
        // Just past the first 1 MB read: the 64-byte head is found only through the carried-over tail.
        offsets.Add((1 << 20) + rng.Next(1, 60));
        for (int i = 1; i < copies; i++) offsets.Add(len - (CacheBlockSize + 11) * i);
        return AddCacheAt(f, len, offsets.ToArray());
    }

    // The clean block at every given offset; c.Offset = the first one.
    static CacheFixture AddCacheAt(Fixture f, int pakLength, params long[] offsets)
    {
        var c = new CacheFixture();
        string ks = f.G(InstallerCore.KsCacheRel);
        c.Original = RandomBytes(CacheBlockSize);
        c.Bridge = RandomBytes(CacheBlockSize);
        c.Manifest = RandomBytes(4096);
        c.CleanPak = RandomBytes(pakLength);
        c.Offset = offsets[0];
        foreach (long at in offsets) Array.Copy(c.Original, 0, c.CleanPak, at, CacheBlockSize);
        c.PakPath = Path.Combine(ks, CacheVersion, "pakchunk0-Windows.pak");
        c.ManifestPath = Path.Combine(ks, "package_" + ManifestId + ".manifest");
        WriteText(Path.Combine(ks, "AssetsVersion.txt"), "1." + ManifestId + "." + CacheVersion + ".Online_Shipping\n");
        WriteBytes(c.ManifestPath, c.Manifest);
        WriteBytes(c.PakPath, c.CleanPak);
        WriteBytes(Path.Combine(ks, CacheVersion, "pakchunk9999-Windows.ucas"), RandomBytes(1024));

        f.Game.Cache = new CacheLaunch
        {
            ManifestSha256 = InstallerCore.Sha256(c.Manifest),
            Size = CacheBlockSize,
            CleanSha256 = InstallerCore.Sha256(c.Original),
            InstalledSha256 = InstallerCore.Sha256(c.Bridge),
            OriginalHeadHex = Hex(c.Original, 64),
            InstalledHeadHex = Hex(c.Bridge, 64)
        };
        WriteBytes(Path.Combine(f.PayloadDir, @"bridge\cache-startup.oodle"), c.Bridge);
        return c;
    }

    // Saved/kscache/local.cache in the launcher format: [16 key][int64 offset][int32 len][path + NUL].
    // Chunks of the cache pak cover [liveFrom, end) every `step` bytes, plus a chunk starting at each of `blockStarts`
    // (as in the real file: the launch block is one chunk). Foreign records around them, as the launcher writes.
    static void WriteLocalCache(Fixture f, long liveFrom, long end, int step, params long[] blockStarts)
    {
        var starts = new SortedSet<long>();
        for (long s = liveFrom; s < end; s += step) starts.Add(s);
        foreach (long b in blockStarts) { starts.Add(b); if (b + CacheBlockSize < end) starts.Add(b + CacheBlockSize); }
        var ms = new MemoryStream();
        Action<long, string> rec = (off, path) =>
        {
            byte[] p = Encoding.UTF8.GetBytes(path + "\0");
            ms.Write(RandomBytes(16), 0, 16);
            ms.Write(BitConverter.GetBytes(off), 0, 8);
            ms.Write(BitConverter.GetBytes(p.Length), 0, 4);
            ms.Write(p, 0, p.Length);
        };
        rec(0, "24/74d9e11cd25d1fb300000008_" + CacheVersion);
        rec(4096, CacheVersion + "/pakchunk9999-Windows.ucas");
        foreach (long s in starts) rec(s, CacheVersion + "/pakchunk0-Windows.pak");
        rec(0, "88/ffd9e11cd25d1fb300000001_" + CacheVersion);
        WriteBytes(Path.Combine(f.G(InstallerCore.KsCacheRel), KsLocalCache.FileName), ms.ToArray());
    }

    static byte[] CacheInstalledPak(CacheFixture c)
    {
        byte[] pak = (byte[])c.CleanPak.Clone();
        Array.Copy(c.Bridge, 0, pak, c.Offset, CacheBlockSize);
        return pak;
    }

    static void CacheInstall()
    {
        var f = NewFixture("cache-install");
        var c = AddCache(f, 1);
        var core = f.Core();
        CacheInfo before = core.InspectCache();
        Assert(before.State == CacheState.Clean && before.Offset == c.Offset && before.Version == CacheVersion, "cache before = Clean at the inserted offset: " + before.State + " " + before.Offset);
        string reason;
        Assert(core.Install(f.PayloadDir, out reason), "install: " + reason);
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(CacheInstalledPak(c)), "cache pak = clean + bridge at the offset, nothing else changed");
        Assert(InstallerCore.FileSha256(f.PakPath) == f.Game.InstalledPakSha256, "base pak = installed_pak_sha256");
        string backup = Path.Combine(core.BackupDir, "cache-launch-" + CacheVersion + ".block");
        Assert(File.Exists(backup) && InstallerCore.FileSha256(backup) == f.Game.Cache.CleanSha256, "cache backup = clean block");
        Assert(File.Exists(Path.ChangeExtension(backup, ".json")), "cache record with the offset");
        CacheInfo after = core.InspectCache();
        Assert(after.State == CacheState.Installed && after.Offset == c.Offset, "cache after = Installed");
        Assert(core.InspectStatus() == GamePatchStatus.InstalledActive, "status InstalledActive");
        Assert(core.VerifyInstallation(), "VerifyInstallation");
        Assert(f.Log.Exists(s => s.Contains(@"kscache\" + CacheVersion)), "log names the cache folder");
        var saved = SupportedGame.Load(core.BackupDir);
        Assert(saved != null && saved.Cache != null && saved.ToJson() == f.Game.ToJson(), "supported_game.json with cache_launch saved next to the backup");
    }

    static void CacheReinstall()
    {
        var f = NewFixture("cache-reinstall");
        var c = AddCache(f, 1);
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "first install: " + reason);
        DateTime mtime = new DateTime(2020, 1, 1);
        File.SetLastWriteTimeUtc(c.PakPath, mtime);
        File.SetLastWriteTimeUtc(f.PakPath, mtime);
        string cacheSha = InstallerCore.FileSha256(c.PakPath);
        Assert(f.Core().Install(f.PayloadDir, out reason), "second install: " + reason);
        Assert(File.GetLastWriteTimeUtc(c.PakPath) == mtime && InstallerCore.FileSha256(c.PakPath) == cacheSha, "cache pak not written");
        Assert(File.GetLastWriteTimeUtc(f.PakPath) == mtime, "base pak not written");
    }

    static void CacheUninstall()
    {
        var f = NewFixture("cache-uninstall");
        var c = AddCache(f, 1);
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        var core = f.Core();
        Assert(core.Uninstall(f.PayloadDir), "uninstall ok");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak), "cache pak = clean");
        Assert(InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "base pak = clean");
        Assert(!Directory.Exists(core.BackupDir), "backup dir removed");
        Assert(File.Exists(c.ManifestPath) && File.Exists(Path.Combine(f.G(InstallerCore.KsCacheRel), CacheVersion, "pakchunk9999-Windows.ucas")), "other cache files intact");
        Assert(core.InspectStatus() == GamePatchStatus.NotInstalled, "status NotInstalled");
        AssertForeignFilesIntact(f);
    }

    static void CacheUnknownManifest()
    {
        var f = NewFixture("cache-manifest");
        var c = AddCache(f, 1);
        WriteBytes(c.ManifestPath, RandomBytes(4096));   // the game updated: another manifest
        WriteBytes(c.PakPath, RandomBytes(c.CleanPak.Length));   // ... and the launch block is gone
        c.CleanPak = File.ReadAllBytes(c.PakPath);
        var core = f.Core();
        Assert(core.InspectCache().State == CacheState.UnsupportedBuild, "cache state UnsupportedBuild");
        string reason;
        Assert(!core.Install(f.PayloadDir, out reason), "install refused");
        Assert(reason.Contains("Игра обновилась"), "reason: game updated: " + reason);
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak), "cache pak unchanged");
        Assert(InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "base pak unchanged");
        Assert(!Directory.Exists(core.BackupDir) && !File.Exists(f.G(InstallerCore.InitRel)), "nothing written");

        f.Game.Cache = null;   // a release without cache_launch: the cache pak still blocks the install
        Assert(f.Core().InspectCache().State == CacheState.UnsupportedBuild, "no cache_launch -> UnsupportedBuild");
        Assert(!f.Core().Install(f.PayloadDir, out reason) && reason.Contains("Игра обновилась"), "no cache_launch: refused");
    }

    static void CacheTwoMatches()
    {
        var f = NewFixture("cache-two");
        var c = AddCache(f, 2);
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Ambiguous, "cache state Ambiguous");
        long second = c.CleanPak.Length - (CacheBlockSize + 11);
        Assert(info.PakSize == c.CleanPak.Length, "PakSize = cache pak length");
        Assert(info.Hits.Count == 2 && info.Hits[0].Offset == c.Offset && info.Hits[1].Offset == second
            && info.Hits.TrueForAll(h => h.Kind == CacheHit.Clean), "Hits: two clean, sorted by offset");
        Assert(info.Detail.Contains("размер пака " + c.CleanPak.Length) && info.Detail.Contains(c.Offset + " чистый") && info.Detail.Contains(second + " чистый"),
            "Detail has the pak size and both offsets: " + info.Detail);
        string reason;
        Assert(!core.Install(f.PayloadDir, out reason), "install refused: " + reason);
        Assert(reason.Contains(c.Offset.ToString()), "refusal names the offsets");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak), "cache pak unchanged");
        Assert(InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "base pak unchanged");
        Assert(!Directory.Exists(core.BackupDir), "nothing written");
    }

    static void CacheAlreadyInstalled()
    {
        var f = NewFixture("cache-already");
        var c = AddCache(f, 1);
        WriteBytes(c.PakPath, CacheInstalledPak(c));   // bridge written by another installer (CPDD)
        DateTime mtime = new DateTime(2020, 1, 1);
        File.SetLastWriteTimeUtc(c.PakPath, mtime);
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Installed && info.Offset == c.Offset, "cache state Installed (found by installed_head_hex)");
        string reason;
        Assert(core.Install(f.PayloadDir, out reason), "install: " + reason);
        Assert(File.GetLastWriteTimeUtc(c.PakPath) == mtime, "cache pak not written");
        Assert(core.InspectStatus() == GamePatchStatus.InstalledActive, "status InstalledActive");
        Assert(!File.Exists(Path.Combine(core.BackupDir, "cache-launch-" + CacheVersion + ".block")), "no backup of a block we did not write");
    }

    static void CacheNoPak()
    {
        var f = NewFixture("cache-nopak");
        var c = AddCache(f, 1);
        File.Delete(c.PakPath);   // older hotpatches had no pakchunk0 in the cache
        var core = f.Core();
        Assert(core.InspectCache().State == CacheState.NoCachePak, "cache state NoCachePak");
        string reason;
        Assert(core.Install(f.PayloadDir, out reason), "install: " + reason);
        Assert(InstallerCore.FileSha256(f.PakPath) == f.Game.InstalledPakSha256, "base pak installed");
        Assert(core.InspectStatus() == GamePatchStatus.InstalledActive, "status by the base pak");
        Assert(core.Uninstall(f.PayloadDir), "uninstall");
        Assert(InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "base pak clean");
    }

    static void CacheRollback()
    {
        var f = NewFixture("cache-rollback");
        var c = AddCache(f, 1);
        string reason;
        bool ok;
        // Another process holds the base pak: reads are allowed, the write fails.
        using (new FileStream(f.PakPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            ok = f.Core().Install(f.PayloadDir, out reason);
        }
        Assert(!ok, "install fails: " + reason);
        Assert(reason.Contains("кеше обновления возвращён"), "reason says the cache was rolled back: " + reason);
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak), "cache pak = clean again");
        Assert(InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "base pak unchanged");
        Assert(!File.Exists(Path.Combine(f.Core().BackupDir, "cache-launch-" + CacheVersion + ".json")), "cache record removed");
    }

    static void CacheReplacedByGame()
    {
        var f = NewFixture("cache-replaced");
        var c = AddCache(f, 1);
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        WriteBytes(c.PakPath, c.CleanPak);   // the launcher restored the cache pak
        var core = f.Core();
        Assert(core.InspectCache().State == CacheState.Clean, "cache clean again");
        Assert(core.InspectStatus() == GamePatchStatus.NotInstalled, "bridge only in the base pak = not active");
        Assert(core.Uninstall(f.PayloadDir), "uninstall");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak), "cache pak untouched");
        Assert(InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "base pak restored");
    }

    // ------------------------------------------------------------ kscache: live copy by local.cache (TASK-038)

    const int Half = 600 * 1024;
    const int ChunkStep = 64 * 1024;

    static void AssertBlock(CacheFixture c, long at, byte[] expected, string what)
    {
        byte[] b = new byte[CacheBlockSize];
        using (var fs = new FileStream(c.PakPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) { fs.Position = at; fs.Read(b, 0, b.Length); }
        Assert(InstallerCore.Sha256(b) == InstallerCore.Sha256(expected), what);
    }

    static void CacheDeadAndLive()
    {
        var f = NewFixture("cache-dead-live");
        long dead = 300000 + rng.Next(1, 999), live = Half + 200000 + rng.Next(1, 999);
        var c = AddCacheAt(f, 2 * Half, dead, live);
        WriteLocalCache(f, Half, 2 * Half, ChunkStep, live);
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Clean && info.Offset == live, "Clean at the live copy: " + info.State + " " + info.Offset + " " + info.Detail);
        Assert(info.Hits.Count == 2 && info.Hits[0].Live == false && info.Hits[1].Live == true, "Hits: dead + live");
        Assert(InstallerCore.DescribeHits(info.Hits, 10) == dead + " чистый мёртвый, " + live + " чистый живой", "hits text: " + InstallerCore.DescribeHits(info.Hits, 10));
        string reason;
        Assert(core.Install(f.PayloadDir, out reason), "install: " + reason);
        AssertBlock(c, live, c.Bridge, "bridge in the live copy");
        AssertBlock(c, dead, c.Original, "dead copy untouched");
        Assert(core.InspectCache().State == CacheState.Installed, "Installed after the install");
        Assert(core.Uninstall(f.PayloadDir), "uninstall");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak), "cache pak clean again");
    }

    static void CacheThreeLiveLast()
    {
        var f = NewFixture("cache-three");
        long a = 100000, b = Half + 100000, last = 2 * Half + 100000 + rng.Next(1, 999);
        var c = AddCacheAt(f, 3 * Half, a, b, last);
        WriteLocalCache(f, 2 * Half, 3 * Half, ChunkStep, last);
        CacheInfo info = f.Core().InspectCache();
        Assert(info.State == CacheState.Clean && info.Offset == last, "Clean at the last copy: " + info.Detail);
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        AssertBlock(c, last, c.Bridge, "bridge in the last copy");
        AssertBlock(c, a, c.Original, "first copy untouched");
        AssertBlock(c, b, c.Original, "second copy untouched");
    }

    static void CacheOnlyDead()
    {
        var f = NewFixture("cache-only-dead");
        var c = AddCacheAt(f, 2 * Half, 250000);
        WriteLocalCache(f, Half, 2 * Half, ChunkStep);
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.NotFound && info.Detail.Contains("среди живых данных") && info.Detail.Contains("мёртвых копий: 1"), "NotFound: " + info.Detail);
        string reason;
        Assert(!core.Install(f.PayloadDir, out reason), "install refused: " + reason);
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak) && !Directory.Exists(core.BackupDir), "nothing written");
    }

    static void CacheTwoLive()
    {
        var f = NewFixture("cache-two-live");
        long b1 = Half + 70000, b2 = Half + 400000;
        var c = AddCacheAt(f, 2 * Half, 100000, b1, b2);
        WriteLocalCache(f, Half, 2 * Half, ChunkStep, b1, b2);
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Ambiguous && info.Detail.Contains("найдено 2 живых"), "Ambiguous over two live copies: " + info.Detail);
        string reason;
        Assert(!core.Install(f.PayloadDir, out reason), "install refused");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak) && !Directory.Exists(core.BackupDir), "nothing written");
    }

    static void CacheBrokenLocalCache()
    {
        var f = NewFixture("cache-broken-index");
        long dead = 300000, live = Half + 200000;
        var c = AddCacheAt(f, 2 * Half, dead, live);
        string idx = Path.Combine(f.G(InstallerCore.KsCacheRel), KsLocalCache.FileName);
        WriteLocalCache(f, Half, 2 * Half, ChunkStep, live);
        byte[] good = File.ReadAllBytes(idx);

        byte[] cut = new byte[good.Length - 3];
        Array.Copy(good, cut, cut.Length);
        WriteBytes(idx, cut);
        Assert(KsLocalCache.ChunkStarts(idx, CacheVersion + "/pakchunk0-Windows.pak") == null, "truncated local.cache -> null");
        CacheInfo info = f.Core().InspectCache();
        Assert(info.State == CacheState.Ambiguous && info.Detail.Contains("local.cache не прочитан"), "truncated: Ambiguous as before: " + info.Detail);

        byte[] badLen = (byte[])good.Clone();
        Array.Copy(BitConverter.GetBytes(100000), 0, badLen, 24, 4);   // first record: path length out of range
        WriteBytes(idx, badLen);
        Assert(KsLocalCache.ChunkStarts(idx, CacheVersion + "/pakchunk0-Windows.pak") == null, "bad len -> null");
        Assert(f.Core().InspectCache().State == CacheState.Ambiguous, "bad len: Ambiguous");

        WriteBytes(idx, good);
        List<long> starts = KsLocalCache.ChunkStarts(idx, CacheVersion + "/PAKCHUNK0-Windows.pak");
        Assert(starts != null && starts.Count > 0 && starts[0] == Half, "good index parses (case-insensitive name), sorted");
        Assert(KsLocalCache.ChunkStarts(idx, "999/pakchunk0-Windows.pak").Count == 0, "no records for another version -> empty list");
        File.Delete(idx);
        Assert(f.Core().InspectCache().State == CacheState.Ambiguous, "no local.cache: Ambiguous");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak), "pak untouched");
    }

    // Our bridge was written, then the launcher appended a fresh pak behind the old data: the record points
    // into the dead half. Not Installed; reinstall moves the bridge to the live copy; uninstall restores both.
    static void CacheRecordInDeadCopy()
    {
        var f = NewFixture("cache-record-dead");
        long first = 300000 + rng.Next(1, 999);
        var c = AddCacheAt(f, Half, first);
        WriteLocalCache(f, 0, Half, ChunkStep, first);
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "first install: " + reason);
        AssertBlock(c, first, c.Bridge, "bridge at the first copy");

        long live = Half + 150000 + rng.Next(1, 999);
        byte[] fresh = RandomBytes(Half);
        Array.Copy(c.Original, 0, fresh, live - Half, CacheBlockSize);
        byte[] oldPart = File.ReadAllBytes(c.PakPath);
        byte[] pak = new byte[2 * Half];
        Array.Copy(oldPart, pak, Half);
        Array.Copy(fresh, 0, pak, Half, Half);
        WriteBytes(c.PakPath, pak);
        WriteLocalCache(f, Half, 2 * Half, ChunkStep, live);

        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Clean && info.Offset == live, "record in the dead half -> Clean at the live copy: " + info.State + " " + info.Detail);
        Assert(info.Hits.Exists(h => h.Offset == first && h.Kind == CacheHit.Bridge && h.Live == false), "dead bridge reported");
        Assert(core.InspectStatus() == GamePatchStatus.NotInstalled, "status not active");
        Assert(core.Install(f.PayloadDir, out reason), "reinstall: " + reason);
        AssertBlock(c, live, c.Bridge, "bridge in the live copy");
        AssertBlock(c, first, c.Original, "dead copy returned to the original");
        Assert(core.InspectStatus() == GamePatchStatus.InstalledActive, "status active");
        Assert(core.Uninstall(f.PayloadDir), "uninstall");
        AssertBlock(c, live, c.Original, "live copy restored");
        AssertBlock(c, first, c.Original, "dead copy still original");
        Assert(!Directory.Exists(core.BackupDir), "backup dir removed");
    }

    // ------------------------------------------------------------ kscache: incremental hotpatch, entry_id (TASK-039)

    const string OldCacheVersion = "777000";

    // local.cache with explicit keys: (key, offset, "<ver>/<file>").
    static void WriteLocalCacheRecords(Fixture f, List<Tuple<byte[], long, string>> records)
    {
        var ms = new MemoryStream();
        foreach (var r in records)
        {
            byte[] p = Encoding.UTF8.GetBytes(r.Item3 + "\0");
            ms.Write(r.Item1, 0, 16);
            ms.Write(BitConverter.GetBytes(r.Item2), 0, 8);
            ms.Write(BitConverter.GetBytes(p.Length), 0, 4);
            ms.Write(p, 0, p.Length);
        }
        WriteBytes(Path.Combine(f.G(InstallerCore.KsCacheRel), KsLocalCache.FileName), ms.ToArray());
    }

    static byte[] EntryKey(byte[] prefix)
    {
        byte[] key = RandomBytes(16);
        Array.Copy(prefix, key, prefix.Length);
        return key;
    }

    // Build 777000 holds the launch block (kscache/777000/pakchunk0), hotpatch 777001 is incremental:
    // AssetsVersion.txt names 777001, its pakchunk0 is a small delta pak without the block, the manifest is new.
    // local.cache: chunks of both paks, the launch block record keyed with entry_id + 4 random bytes.
    static CacheFixture AddIncremental(Fixture f, bool bridgeInstalled, out byte[] deltaPak)
    {
        long at = 300000 + rng.Next(1, 999);
        var c = AddCacheAt(f, Half, at);
        string ks = f.G(InstallerCore.KsCacheRel);
        string oldPak = Path.Combine(ks, OldCacheVersion, "pakchunk0-Windows.pak");
        WriteBytes(oldPak, bridgeInstalled ? CacheInstalledPak(c) : c.CleanPak);
        c.PakPath = oldPak;
        deltaPak = RandomBytes(300 * 1024);
        WriteBytes(Path.Combine(ks, CacheVersion, "pakchunk0-Windows.pak"), deltaPak);
        WriteBytes(c.ManifestPath, RandomBytes(4096));   // the manifest changes with every hotpatch

        byte[] entry = RandomBytes(12);
        f.Game.Cache.EntryId = Hex(entry, 12);
        var records = new List<Tuple<byte[], long, string>>();
        records.Add(Tuple.Create(RandomBytes(16), 0L, "24/74d9e11cd25d1fb300000008_" + CacheVersion));
        for (long s = 0; s < Half; s += ChunkStep) if (s < at || s >= at + CacheBlockSize) records.Add(Tuple.Create(RandomBytes(16), s, OldCacheVersion + "/pakchunk0-Windows.pak"));
        records.Add(Tuple.Create(EntryKey(entry), at, OldCacheVersion + "/pakchunk0-Windows.pak"));
        records.Add(Tuple.Create(RandomBytes(16), at + CacheBlockSize, OldCacheVersion + "/pakchunk0-Windows.pak"));
        records.Add(Tuple.Create(RandomBytes(16), 0L, CacheVersion + "/pakchunk0-Windows.pak"));
        records.Add(Tuple.Create(RandomBytes(16), 150000L, CacheVersion + "/pakchunk0-Windows.pak"));
        WriteLocalCacheRecords(f, records);
        return c;
    }

    static void CacheIncrementalInstalled()
    {
        var f = NewFixture("cache-incr-installed");
        byte[] delta;
        var c = AddIncremental(f, true, out delta);
        DateTime mtime = new DateTime(2020, 1, 1);
        File.SetLastWriteTimeUtc(c.PakPath, mtime);
        string deltaPath = Path.Combine(f.G(InstallerCore.KsCacheRel), CacheVersion, "pakchunk0-Windows.pak");
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Installed && info.Version == OldCacheVersion && info.AssetsVersion == CacheVersion && info.Offset == c.Offset,
            "Installed in the older folder: " + info.State + " " + info.Version + " " + info.Offset + " " + info.Detail);
        Assert(info.EntryRelPath == OldCacheVersion + "/pakchunk0-Windows.pak" && info.Detail.Contains("кеш обновления " + CacheVersion), "detail names both versions: " + info.Detail);
        Assert(LogCollector.DescribeCache(info).Contains("AssetsVersion " + CacheVersion), "DescribeCache names AssetsVersion");
        string reason;
        Assert(core.Install(f.PayloadDir, out reason), "install: " + reason);
        Assert(File.GetLastWriteTimeUtc(c.PakPath) == mtime && InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(CacheInstalledPak(c)), "block pak not written");
        Assert(InstallerCore.FileSha256(deltaPath) == InstallerCore.Sha256(delta), "delta pak not written");
        Assert(Directory.GetFiles(core.BackupDir, "cache-launch-*").Length == 0, "no cache record or backup");
        Assert(f.Log.Exists(s => s.Contains(@"Мост уже установлен в Saved\kscache\" + OldCacheVersion + " (кеш обновления " + CacheVersion + ", блок найден по local.cache)")), "log line [2/6]");
        Assert(core.InspectStatus() == GamePatchStatus.InstalledActive, "status InstalledActive");
    }

    static void CacheIncrementalClean()
    {
        var f = NewFixture("cache-incr-clean");
        byte[] delta;
        var c = AddIncremental(f, false, out delta);
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Clean && info.Version == OldCacheVersion && info.Offset == c.Offset, "Clean in the older folder: " + info.State + " " + info.Detail);
        string reason;
        Assert(core.Install(f.PayloadDir, out reason), "install: " + reason);
        AssertBlock(c, c.Offset, c.Bridge, "bridge in the older folder at the record offset");
        Assert(File.Exists(Path.Combine(core.BackupDir, "cache-launch-" + OldCacheVersion + ".json")), "cache-launch-" + OldCacheVersion + ".json created");
        Assert(!File.Exists(Path.Combine(core.BackupDir, "cache-launch-" + CacheVersion + ".json")), "no record for the AssetsVersion folder");
        Assert(InstallerCore.FileSha256(Path.Combine(f.G(InstallerCore.KsCacheRel), CacheVersion, "pakchunk0-Windows.pak")) == InstallerCore.Sha256(delta), "delta pak not written");
        Assert(core.InspectCache().State == CacheState.Installed, "Installed after the install");
        Assert(core.VerifyInstallation(), "VerifyInstallation");
        Assert(core.Uninstall(f.PayloadDir), "uninstall");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak), "older pak clean again");
        Assert(!Directory.Exists(core.BackupDir), "backup dir removed");
    }

    static void CacheEntryForeignBytes()
    {
        var f = NewFixture("cache-entry-foreign");
        byte[] delta;
        var c = AddIncremental(f, false, out delta);
        byte[] pak = (byte[])c.CleanPak.Clone();
        Array.Copy(RandomBytes(CacheBlockSize), 0, pak, c.Offset, CacheBlockSize);   // the launcher re-downloaded the block
        WriteBytes(c.PakPath, pak);
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.NotFound && info.Detail.Contains("байты не совпадают") && info.Detail.Contains(OldCacheVersion + "/pakchunk0-Windows.pak:" + c.Offset),
            "NotFound: " + info.State + " " + info.Detail);
        string reason;
        Assert(!core.Install(f.PayloadDir, out reason), "install refused: " + reason);
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(pak) && !Directory.Exists(core.BackupDir), "nothing written");
    }

    static void CacheEntryTwoRecords()
    {
        var f = NewFixture("cache-entry-two");
        byte[] delta;
        var c = AddIncremental(f, false, out delta);
        byte[] entry = FromHexT(f.Game.Cache.EntryId);
        string idx = Path.Combine(f.G(InstallerCore.KsCacheRel), KsLocalCache.FileName);
        var records = new List<Tuple<byte[], long, string>>();
        foreach (var e in KsLocalCache.Load(idx)) records.Add(Tuple.Create(e.Key, e.Offset, e.RelPath));
        records.Add(Tuple.Create(EntryKey(entry), 0L, CacheVersion + "/pakchunk0-Windows.pak"));
        WriteLocalCacheRecords(f, records);
        Assert(KsLocalCache.FindByKeyPrefix(idx, entry).Count == 2, "FindByKeyPrefix: two records");
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Ambiguous && info.Detail.Contains(OldCacheVersion + "/pakchunk0-Windows.pak:" + c.Offset), "Ambiguous: " + info.Detail);
        string reason;
        Assert(!core.Install(f.PayloadDir, out reason), "install refused");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak) && !Directory.Exists(core.BackupDir), "nothing written");
    }

    static void CacheManifestChangedBlockClean()
    {
        var f = NewFixture("cache-manifest-clean");
        long live = Half + 200000 + rng.Next(1, 999);
        var c = AddCacheAt(f, 2 * Half, live);
        WriteLocalCache(f, Half, 2 * Half, ChunkStep, live);
        WriteBytes(c.ManifestPath, RandomBytes(4096));
        f.Game.Cache.EntryId = Hex(RandomBytes(12), 12);   // entry_id known, but no such record: the head search decides
        var core = f.Core();
        CacheInfo info = core.InspectCache();
        Assert(info.State == CacheState.Clean && info.Offset == live && info.Version == CacheVersion && info.EntryRelPath == null, "Clean: " + info.State + " " + info.Detail);
        Assert(info.Detail.Contains("манифест") && info.Detail.Contains("совпал по sha256"), "detail notes the other manifest: " + info.Detail);
        string reason;
        Assert(core.Install(f.PayloadDir, out reason), "install: " + reason);
        AssertBlock(c, live, c.Bridge, "bridge written");
        Assert(core.InspectCache().State == CacheState.Installed, "Installed after the install");
    }

    static byte[] FromHexT(string hex)
    {
        byte[] b = new byte[hex.Length / 2];
        for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        return b;
    }

    // Saved\RussianPatchBackups\supported_game.json written by 3.1.0 and older (format 1, "launch_block").
    static void OldBackupFormat()
    {
        var f = NewFixture("old-backup-format");
        var c = AddCache(f, 1);
        string reason;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        string backup = Path.Combine(f.Core().BackupDir, SupportedGame.FileName);
        string v1 = File.ReadAllText(backup).Replace("\"base_launch_block\"", "\"launch_block\"").Replace("  \"format\": 2,\n", "");
        Assert(!v1.Contains("base_launch_block") && !v1.Contains("\"format\""), "format-1 file prepared");
        WriteText(backup, v1);
        SupportedGame old = SupportedGame.Load(f.Core().BackupDir);
        Assert(old != null && old.Format == 0 && old.Offset == Offset && old.Cache != null, "format 1 parsed");
        Assert(PatcherBackend.CoreForInstalledGame(f.GameDir, null, null).InspectStatus() == GamePatchStatus.InstalledActive, "status from the old backup file");
        InstallerCore core = PatcherBackend.CoreForInstalledGame(f.GameDir, f.PayloadDir, null);
        Assert(core != null && core.Uninstall(f.PayloadDir), "uninstall with the old backup file");
        Assert(InstallerCore.FileSha256(c.PakPath) == InstallerCore.Sha256(c.CleanPak) && InstallerCore.FileSha256(f.PakPath) == InstallerCore.Sha256(f.CleanPak), "both paks restored");
    }

    static void Format2AndMinInstaller()
    {
        var f = NewFixture("format2");
        string json = f.Game.ToJson();
        Assert(json.Contains("\"format\": 2") && json.Contains("\"base_launch_block\"") && !json.Contains("\"launch_block\""), "ToJson: format 2, no launch_block key");
        Assert(SupportedGame.Parse(json).Format == 2 && SupportedGame.Parse(json).Offset == Offset, "format 2 parses");

        Assert(PatcherBackend.InstallerTooOld(f.Game) == null, "no min_installer_version -> ok");
        f.Game.MinInstallerVersion = AppInfo.Version;
        Assert(PatcherBackend.InstallerTooOld(SupportedGame.Parse(f.Game.ToJson())) == null, "min = this version -> ok (round trip)");
        f.Game.MinInstallerVersion = "3.0.0";
        Assert(PatcherBackend.InstallerTooOld(f.Game) == null, "older min -> ok");
        f.Game.MinInstallerVersion = "v99.0.0-RU";
        string why = PatcherBackend.InstallerTooOld(SupportedGame.Parse(f.Game.ToJson()));
        Assert(why != null && why.Contains("Нужна новая версия установщика") && why.Contains("releases/latest"), "newer min -> refusal: " + why);
    }

    static string Hex(byte[] data, int count)
    {
        var sb = new StringBuilder(count * 2);
        for (int i = 0; i < count; i++) sb.Append(data[i].ToString("x2"));
        return sb.ToString();
    }

    // ------------------------------------------------------------ options (installer/GameOptions.cs)

    static string OptionsGame(string name)
    {
        string dir = Path.Combine(testRoot, name, "game");
        AssertUnderTemp(dir);
        Directory.CreateDirectory(dir);
        return dir;
    }

    static void OptionsSettingsRoundTrip()
    {
        string game = OptionsGame("options-settings");
        var opt = new GameOptions(game, null);
        string error;
        var state = opt.Read(out error);
        Assert(error == null && state.DpsMode == DpsMeterMode.Advanced && !state.DesktopChat && !state.VisualClarity, "no files -> advanced / chat off / no Visual Clarity");

        Assert(GameOptions.FormatSettings(DpsMeterMode.External, true) == "return {\n    DpsMeterMode = \"external\",\n    DesktopChatUI = true,\n}\n", "CPDD format byte for byte");
        foreach (DpsMeterMode mode in new[] { DpsMeterMode.Off, DpsMeterMode.Native, DpsMeterMode.Advanced, DpsMeterMode.External })
        {
            foreach (bool chat in new[] { false, true })
            {
                Assert(opt.WriteSettings(mode, chat, out error), "write " + mode + "/" + chat + ": " + error);
                byte[] raw = File.ReadAllBytes(opt.SettingsPath);
                Assert(Encoding.UTF8.GetString(raw) == GameOptions.FormatSettings(mode, chat) && raw[0] == (byte)'r', "file = CPDD format, no BOM (" + mode + "/" + chat + ")");
                DpsMeterMode m; bool c;
                Assert(opt.TryReadSettings(out m, out c, out error) && m == mode && c == chat, "read back " + mode + "/" + chat);
            }
        }
        // Old CPDD one-key files are understood and rewritten.
        WriteText(opt.SettingsPath, "return { DpsMeterMode = \"off\" }\n");
        DpsMeterMode m2; bool c2;
        Assert(opt.TryReadSettings(out m2, out c2, out error) && m2 == DpsMeterMode.Off && !c2, "old CPDD format read");
        Assert(opt.WriteSettings(DpsMeterMode.Native, false, out error) && File.ReadAllText(opt.SettingsPath) == GameOptions.FormatSettings(DpsMeterMode.Native, false), "old format rewritten");
        Assert(!File.Exists(Path.Combine(game, @"Saved\Mods\lua\cpdd_user_settings.lua")), "cpdd_user_settings.lua not created");
    }

    static void OptionsForeignSettings()
    {
        string game = OptionsGame("options-foreign");
        var opt = new GameOptions(game, null);
        foreach (string foreign in new[] {
            "return {\n    DpsMeterMode = \"advanced\",\n    DesktopChatUI = false,\n    MyKey = 1,\n}\n",
            "return {\n    DpsMeterMode = \"turbo\",\n}\n",
            "local x = 1\nreturn { DpsMeterMode = \"off\" }\n",
            "return {\n    DpsMeterMode = \"off\",\n" })
        {
            WriteText(opt.SettingsPath, foreign);
            string error;
            Assert(!opt.WriteSettings(DpsMeterMode.External, true, out error) && error != null && error.Contains("изменён вручную"), "refused: " + foreign.Replace("\n", " "));
            Assert(File.ReadAllText(opt.SettingsPath) == foreign, "file unchanged");
            opt.Read(out error);
            Assert(error != null, "Read reports the foreign file");
        }
    }

    static void OptionsVisualClarity()
    {
        string game = OptionsGame("options-vc");
        var opt = new GameOptions(game, null);
        string ini = opt.EngineIniPath;
        string error;

        // No Engine.ini: created with the block, removed again on disable.
        Assert(opt.SetVisualClarity(true, out error), "enable without Engine.ini: " + error);
        Assert(File.ReadAllText(ini) == GameOptions.VisualClarityBlock, "Engine.ini = CPDD block byte for byte");
        bool vc;
        Assert(opt.TryReadVisualClarity(out vc, out error) && vc, "state: enabled");
        Assert(opt.SetVisualClarity(true, out error) && File.ReadAllText(ini) == GameOptions.VisualClarityBlock, "enable twice: no duplicate");
        Assert(opt.SetVisualClarity(false, out error), "disable: " + error);
        Assert(!File.Exists(ini), "Engine.ini created by us is deleted");
        Assert(!File.Exists(opt.OptionsStatePath), "options.json removed");

        // Existing Engine.ini (LF): appended after one blank line, disable restores the bytes.
        string original = "[Core.System]\nPaths=../../../Engine/Content\n";
        WriteText(ini, original);
        Assert(opt.SetVisualClarity(true, out error), "enable on existing file: " + error);
        string after = File.ReadAllText(ini);
        Assert(after == original + "\n" + GameOptions.VisualClarityBlock, "block appended, other lines byte for byte");
        Assert(opt.SetVisualClarity(true, out error) && File.ReadAllText(ini) == after, "enable again: no duplicate");
        Assert(opt.SetVisualClarity(false, out error) && File.ReadAllText(ini) == original, "disable returns the original bytes");
        Assert(File.Exists(ini), "foreign Engine.ini is kept");

        // Block in the middle is replaced in place.
        string middle = "[A]\nx=1\n\n" + GameOptions.VisualClarityBlock.Replace("r.Fog=0\n", "r.Fog=1\n") + "[B]\ny=2\n";
        WriteText(ini, middle);
        Assert(opt.SetVisualClarity(true, out error) && File.ReadAllText(ini) == "[A]\nx=1\n\n" + GameOptions.VisualClarityBlock + "[B]\ny=2\n", "old block replaced in place");
        Assert(opt.SetVisualClarity(false, out error) && File.ReadAllText(ini) == "[A]\nx=1\n[B]\ny=2\n", "block and one blank line removed");

        // CRLF is kept.
        string crlf = "[Core.System]\r\nPaths=x\r\n";
        WriteText(ini, crlf);
        Assert(opt.SetVisualClarity(true, out error), "enable on CRLF: " + error);
        after = File.ReadAllText(ini);
        Assert(after == crlf + "\r\n" + GameOptions.VisualClarityBlock.Replace("\n", "\r\n"), "CRLF block");
        Assert(opt.SetVisualClarity(false, out error) && File.ReadAllText(ini) == crlf, "CRLF restored");

        // UTF-16 and broken blocks: refused, file unchanged.
        byte[] utf16 = Encoding.Unicode.GetPreamble();
        byte[] body = Encoding.Unicode.GetBytes("[Core.System]\r\n");
        byte[] u16 = new byte[utf16.Length + body.Length];
        utf16.CopyTo(u16, 0); body.CopyTo(u16, utf16.Length);
        WriteBytes(ini, u16);
        Assert(!opt.SetVisualClarity(true, out error) && error.Contains("UTF-16"), "UTF-16 refused");
        Assert(InstallerCore.Sha256(File.ReadAllBytes(ini)) == InstallerCore.Sha256(u16), "UTF-16 file unchanged");
        WriteBytes(ini, new byte[] { 0x5B, 0x41, 0x5D, 0x0A, 0xC3, 0x28, 0x0A });
        Assert(!opt.SetVisualClarity(true, out error) && error.Contains("UTF-8"), "invalid UTF-8 refused");

        foreach (string broken in new[] {
            "[A]\n" + GameOptions.BeginMarker + "\nr.Fog=0\n",
            "[A]\n" + GameOptions.VisualClarityBlock + GameOptions.VisualClarityBlock,
            "[A]\n" + GameOptions.EndMarker + "\n" + GameOptions.BeginMarker + "\n" })
        {
            WriteText(ini, broken);
            Assert(!opt.SetVisualClarity(true, out error) && error.Contains("повреждённый"), "broken block refused (enable)");
            Assert(!opt.SetVisualClarity(false, out error), "broken block refused (disable)");
            Assert(File.ReadAllText(ini) == broken, "broken file unchanged");
        }
    }

    static void OptionsUninstall()
    {
        var f = NewFixture("options-uninstall");
        string reason, error;
        Assert(f.Core().Install(f.PayloadDir, out reason), "install: " + reason);
        var opt = new GameOptions(f.GameDir, null);
        var desired = new GameOptionsState { DpsMode = DpsMeterMode.Native, DesktopChat = true, VisualClarity = true };
        var errors = new List<string>();
        Assert(opt.Apply(desired, errors), "apply: " + string.Join("; ", errors.ToArray()));
        Assert(opt.Read(out error).SameAs(desired) && error == null, "read back = applied");

        Assert(opt.RemoveManagedBlocks(out error), "remove managed blocks: " + error);
        Assert(f.Core().Uninstall(f.PayloadDir), "uninstall");
        Assert(File.ReadAllText(f.G(GameOptions.SettingsRel)) == GameOptions.FormatSettings(DpsMeterMode.Native, true), "cpdd_patcher_settings.lua stays");
        Assert(File.Exists(f.G(@"Saved\Mods\lua\cpdd_user_settings.lua")), "cpdd_user_settings.lua stays");
        Assert(File.ReadAllText(f.G(GameOptions.EngineIniRel)) == "[Core.System]\n", "Engine.ini: block removed, foreign lines intact");
        Assert(!Directory.Exists(f.G(InstallerCore.BackupDirRel)), "backup dir removed");
    }

    // ------------------------------------------------------------ payload (installer/PayloadSource.cs)

    // Isolated PayloadSource: exe dir, %LOCALAPPDATA% and %TEMP% inside the test folder, no network.
    static string PayloadSandbox(string name, Fixture f)
    {
        string root = Path.Combine(testRoot, name);
        AssertUnderTemp(root);
        PayloadSource.ExplicitPayload = null;
        PayloadSource.ExeDir = Path.Combine(root, "exe");
        PayloadSource.AppDataRoot = Path.Combine(root, "appdata");
        PayloadSource.ExtractRoot = Path.Combine(root, "extract");
        PayloadSource.FetchManifest = log => null;
        Directory.CreateDirectory(PayloadSource.ExeDir);
        return root;
    }

    static string MakeDataZip(Fixture f, string zipPath)
    {
        AssertUnderTemp(zipPath);
        WriteOwnedFiles(f.PayloadDir);
        WriteText(Path.Combine(f.PayloadDir, SupportedGame.FileName), f.Game.ToJson());
        Directory.CreateDirectory(Path.GetDirectoryName(zipPath));
        if (File.Exists(zipPath)) File.Delete(zipPath);
        System.IO.Compression.ZipFile.CreateFromDirectory(f.PayloadDir, zipPath);
        return InstallerCore.FileSha256(zipPath);
    }

    static PayloadInfo Resolve(bool allowDownload)
    {
        return PayloadSource.ResolveAsync(allowDownload, null, null, System.Threading.CancellationToken.None).GetAwaiter().GetResult();
    }

    static void PayloadNoGuessing()
    {
        var f = NewFixture("payload-guess");
        PayloadSandbox("payload-guess", f);
        MakePayload(f, Path.Combine(PayloadSource.ExeDir, "patch_payload"), false);
        MakePayload(f, Path.Combine(PayloadSource.ExeDir, "data"), false);
        MakePayload(f, Path.Combine(PayloadSource.ExeDir, "..", "patch_payload"), false);
        MakeDataZip(f, Path.Combine(PayloadSource.ExeDir, "Lord-of-Mysteries-Russian-Patch-v2.9.0-RU.zip"));
        MakeDataZip(f, Path.Combine(PayloadSource.ExeDir, "lom-russian-patch-data (1).zip"));
        Assert(Resolve(true) == null, "patch_payload/data folders and other zip names are not used");
        Assert(PayloadSource.ResolveOffline(null) == null, "offline: nothing");
    }

    static void PayloadSideZip()
    {
        var f = NewFixture("payload-side");
        PayloadSandbox("payload-side", f);
        string sha = MakeDataZip(f, Path.Combine(PayloadSource.ExeDir, PayloadSource.DataZipName));
        var logs = new List<string>();
        PayloadInfo p = PayloadSource.ResolveAsync(true, s => logs.Add(s), null, System.Threading.CancellationToken.None).GetAwaiter().GetResult();
        Assert(p != null && p.IsLocal && PayloadSource.ValidatePayloadContents(p.Dir, null), "exact name next to the exe is used");
        Assert(logs.Exists(s => s.Contains("проверка по release.json недоступна")), "log says release.json is unavailable");
        Assert(p != null && p.Dir.StartsWith(PayloadSource.ExtractRoot, StringComparison.OrdinalIgnoreCase), "extracted into ExtractRoot");

        PayloadSource.FetchManifest = log => new ReleaseManifest { Version = "vTEST", PayloadSha256 = sha, PayloadDownloadUrl = "file:///nonexistent" };
        p = Resolve(true);
        Assert(p != null && p.IsLocal, "matching release.json: side zip used");

        PayloadSource.FetchManifest = log => new ReleaseManifest { Version = "vNEWER", PayloadSha256 = new string('0', 64), PayloadDownloadUrl = "file:///nonexistent" };
        Assert(Resolve(true) == null, "sha256 differs from the latest release: side zip not used (download fails offline)");
    }

    static void PayloadExplicit()
    {
        var f = NewFixture("payload-explicit");
        string root = PayloadSandbox("payload-explicit", f);
        string error;
        string noBridge = Path.Combine(root, "no-bridge");
        WriteText(Path.Combine(noBridge, InstallerCore.BootstrapRel), "-- boot\n");
        WriteText(Path.Combine(noBridge, InstallerCore.InitRel), "-- init\n");
        Assert(PayloadSource.PrepareExplicit(noBridge, null, out error) == null && error.Contains("--payload"), "folder without bridge/ refused");
        Assert(PayloadSource.PrepareExplicit(Path.Combine(root, "missing"), null, out error) == null, "missing path refused");

        PayloadInfo p = PayloadSource.PrepareExplicit(f.PayloadDir, null, out error);
        Assert(p != null && p.Dir == Path.GetFullPath(f.PayloadDir) && p.Origin.StartsWith("Локальный пакет"), "folder used in place");

        string zip = Path.Combine(root, "any-name.zip");
        MakeDataZip(f, zip);
        PayloadSource.ExplicitPayload = zip;
        p = Resolve(true);
        Assert(p != null && p.IsLocal, "--payload zip extracted");
        string why;
        Assert(p != null && InstallerCore.VerifyOwnedFiles(p.Dir, InstallerCore.GetPayloadFiles(p.Dir), out why), "extracted zip passes owned_files.json");
        string reason = "no payload";
        Assert(p != null && f.Core().Install(p.Dir, out reason), "install from the extracted zip: " + reason);
        PayloadSource.ExplicitPayload = null;
    }

    static void PayloadCache()
    {
        var f = NewFixture("payload-cache");
        PayloadSandbox("payload-cache", f);
        string zip = Path.Combine(PayloadSource.CacheDir, PayloadSource.DataZipName);
        string sha = MakeDataZip(f, zip);
        string rel = Path.Combine(PayloadSource.CacheDir, PayloadSource.ReleaseJsonName);
        Assert(Resolve(false) == null, "cache without release.json is not used");
        WriteText(rel, "{\"release_version\": \"vCACHED\", \"payload\": {\"name\": \"lom-russian-patch-data.zip\", \"sha256\": \"" + new string('1', 64) + "\", \"size\": 1}}");
        Assert(Resolve(false) == null, "cache with another sha256 is not used");
        WriteText(rel, "{\"release_version\": \"vCACHED\", \"payload\": {\"name\": \"lom-russian-patch-data.zip\", \"sha256\": \"" + sha + "\", \"size\": 1}}");
        PayloadInfo p = Resolve(false);
        Assert(p != null && !p.IsLocal && p.Origin.Contains("vCACHED") && PayloadSource.ValidatePayloadContents(p.Dir, null), "matching cache used");
        Assert(PayloadSource.ResolveOffline(null) != null, "offline (uninstall) uses the verified cache");
    }

    static void VersionsCompare()
    {
        var f = NewFixture("versions");
        Assert(PatcherBackend.InstalledVersion(f.GameDir) == null, "no Init.lua -> null");
        WriteText(f.G(InstallerCore.InitRel), "-- header\nlocal M = {}\nlocal VERSION = \"2.9.10-RU\"\n");
        Assert(PatcherBackend.InstalledVersion(f.GameDir) == "2.9.10-RU", "VERSION read from Init.lua");
        Assert(PatcherBackend.CompareVersions("2.9.10-RU", "v3.0.0-RU") < 0, "2.9.10 < 3.0.0");
        Assert(PatcherBackend.CompareVersions("v3.0.1-RU", "3.0.0-RU") > 0, "3.0.1 > 3.0.0");
        Assert(PatcherBackend.CompareVersions("3.0.0-RU", "v3.0.0-RU") == 0, "tag vs version equal");
    }

    // ------------------------------------------------------------ logs (installer/LogCollector.cs)

    static string LogsGame(string name, int count)
    {
        string game = OptionsGame(name);
        DateTime t = new DateTime(2026, 10, 1, 12, 0, 0, DateTimeKind.Utc);
        for (int i = 0; i < count; i++)
        {
            string p = Path.Combine(game, @"Saved\Logs", i == 0 ? "C7.log" : "C7-backup-2026.10.0" + i + ".log");
            WriteText(p, "log " + i + "\n");
            File.SetLastWriteTimeUtc(p, t.AddHours(-i));   // C7.log newest, then backup-1, backup-2...
        }
        WriteText(Path.Combine(game, @"Saved\Logs\other.txt"), "x\n");
        return game;
    }

    static void LogCollectorCopies()
    {
        string game = LogsGame("logs-copy", 5);
        string exe = Path.Combine(testRoot, "logs-copy", "exe");
        LogCollector.DesktopDir = Path.Combine(testRoot, "logs-copy", "desktop");
        string folder = Path.Combine(exe, LogCollector.FolderName);
        WriteText(Path.Combine(folder, "C7-stale.log"), "old\n");
        WriteText(Path.Combine(folder, "keep.txt"), "foreign\n");

        LogCollectResult r;
        // C7.log is held open for writing as the running game does.
        using (var hold = new FileStream(Path.Combine(game, @"Saved\Logs\C7.log"), FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite))
        {
            r = LogCollector.Collect(game, exe);
        }
        Assert(r.Error == null && r.Folder == folder && !r.UsedFallback, "collected next to the exe: " + r.Error);
        var logs = new List<string>(Directory.GetFiles(folder, "*.log"));
        logs.Sort(StringComparer.OrdinalIgnoreCase);
        Assert(logs.Count == 3, "exactly 3 logs, stale one removed: " + logs.Count);
        Assert(File.Exists(Path.Combine(folder, "C7.log")) && File.Exists(Path.Combine(folder, "C7-backup-2026.10.01.log"))
            && File.Exists(Path.Combine(folder, "C7-backup-2026.10.02.log")), "the 3 newest by LastWriteTime");
        Assert(File.ReadAllText(Path.Combine(folder, "C7.log")) == "log 0\n", "open C7.log copied");
        Assert(File.Exists(Path.Combine(folder, "keep.txt")), "foreign file in the folder kept");
        string info = File.ReadAllText(Path.Combine(folder, LogCollector.InfoName));
        Assert(info.Contains(AppInfo.Version) && info.Contains("Версия игры") && info.Contains("AssetsVersion.txt: нет файла"), "info.txt with the version section");
        Assert(info.Contains("Кеш обновления (InspectCache): NoCachePak"), "info.txt has InspectCache");

        r = LogCollector.Collect(game, exe);
        Assert(r.Error == null && Directory.GetFiles(folder, "*.log").Length == 3, "rerun leaves 3 logs");

        r = LogCollector.Collect(OptionsGame("logs-none"), exe);
        Assert(r.Error != null && r.Error.Contains("Запустите игру") && r.Folder == null, "no Saved\\Logs -> error, no exception");
        Assert(LogCollector.MaskUser(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + @"\x") == @"%USERPROFILE%\x", "user profile masked");
    }

    // ------------------------------------------------------------ self-update (installer/SelfUpdate.cs)

    // exe dir and %LOCALAPPDATA% inside the test folder; the "download" copies a local file.
    static string SelfUpdateSandbox(string name, out string exe)
    {
        string root = PayloadSandbox(name, null);
        exe = Path.Combine(PayloadSource.ExeDir, SelfUpdate.DefaultExeName);
        WriteText(exe, "old installer\n");
        SelfUpdate.Download = (url, dest, size, progress, token, log) =>
        {
            File.Copy(url, dest, true);
            return System.Threading.Tasks.Task.FromResult(true);
        };
        return root;
    }

    static ReleaseManifest SelfUpdateRelease(string root, string content)
    {
        string file = Path.Combine(root, "release", SelfUpdate.DefaultExeName);
        WriteText(file, content);
        return new ReleaseManifest
        {
            Version = "v9.0.0-RU", PatcherName = SelfUpdate.DefaultExeName, PatcherDownloadUrl = file,
            PatcherSize = new FileInfo(file).Length, PatcherSha256 = InstallerCore.FileSha256(file)
        };
    }

    static void ResetSelfUpdate()
    {
        SelfUpdate.UpdatedFrom = null;
        SelfUpdate.DisabledByArg = false;
        SelfUpdate.LatestVersion = null;
        SelfUpdate.Failed = false;
        SelfUpdate.Download = GitHubReleaseClient.DownloadFileWithProgressAsync;
        PayloadSource.ExplicitPayload = null;
    }

    static string Prepare(ReleaseManifest m, string exe, List<string> log)
    {
        return SelfUpdate.PrepareAsync(m, exe, s => log.Add(s), null, System.Threading.CancellationToken.None).GetAwaiter().GetResult();
    }

    static void SelfUpdateIsNewer()
    {
        ResetSelfUpdate();
        string sha = new string('a', 64);
        Func<string, ReleaseManifest> rel = v => new ReleaseManifest { Version = v, PatcherSha256 = sha, PatcherDownloadUrl = "https://example.invalid/x.exe" };
        Assert(SelfUpdate.IsNewer(rel("v9.0.0-RU")), "v9.0.0-RU > " + AppInfo.Version);
        Assert(SelfUpdate.IsNewer(rel("3.1.3-RU")) == (PatcherBackend.CompareVersions("3.1.3-RU", AppInfo.Version) > 0), "3.1.3-RU against " + AppInfo.Version);
        Assert(PatcherBackend.CompareVersions("v3.1.3-RU", "3.1.2-RU") > 0, "v-prefixed tag: 3.1.3 > 3.1.2");
        Assert(!SelfUpdate.IsNewer(rel("v" + AppInfo.Version)), "same version (v-prefixed tag) -> no");
        Assert(!SelfUpdate.IsNewer(rel("v3.0.0-RU")), "older -> no");
        Assert(!SelfUpdate.IsNewer(new ReleaseManifest { Version = "v9.0.0-RU", PatcherDownloadUrl = "https://example.invalid/x.exe" }), "no sha256 -> no");
        Assert(!SelfUpdate.IsNewer(null), "no manifest -> no");

        ReleaseManifest m = rel("v9.0.0-RU");
        if (!GitHubReleaseClient.RepoOverridden) Assert(SelfUpdate.SkipReason(m) == null, "window, no flags -> update allowed");
        SelfUpdate.UpdatedFrom = "3.1.2-RU";
        string loop = SelfUpdate.SkipReason(m);
        Assert(loop != null && loop.Contains("вручную"), "--updated-from and still newer -> loop guard: " + loop);
        SelfUpdate.UpdatedFrom = null;
        SelfUpdate.DisabledByArg = true;
        Assert(SelfUpdate.SkipReason(m) != null, "--no-self-update -> skipped");
        SelfUpdate.DisabledByArg = false;
        PayloadSource.ExplicitPayload = "x";
        Assert(SelfUpdate.SkipReason(m) != null, "--payload -> skipped");
        PayloadSource.ExplicitPayload = null;

        Assert(SelfUpdate.NewerReleaseText() == null, "no latest version -> 'Дождитесь' stays");
        SelfUpdate.LatestVersion = "v" + AppInfo.Version;
        Assert(SelfUpdate.NewerReleaseText() == null, "latest = this exe -> 'Дождитесь' stays");
        SelfUpdate.LatestVersion = "v9.0.0-RU";
        string text = SelfUpdate.NewerReleaseText();
        Assert(text != null && text.Contains("Вышла версия v9.0.0-RU") && text.Contains("обновится при следующем запуске"), "newer release text: " + text);
        SelfUpdate.Failed = true;
        text = SelfUpdate.NewerReleaseText();
        Assert(text != null && text.Contains("не смог обновиться сам") && text.Contains("releases/latest"), "failed update text: " + text);
        var g = new SupportedGame { MinInstallerVersion = "99.0.0-RU" };
        string why = PatcherBackend.InstallerTooOld(g);
        Assert(why != null && why.Contains("Вышла версия v9.0.0-RU") && why.Contains("Файлы игры не изменены"), "InstallerTooOld with a newer release: " + why);
        ResetSelfUpdate();
    }

    static void SelfUpdateReleaseJson()
    {
        string repo = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
        string built = Path.Combine(repo, @"build\release.json");
        if (File.Exists(built))
        {
            ReleaseManifest b = ReleaseManifest.FromReleaseJson(File.ReadAllText(built, Encoding.UTF8));
            Assert(b != null && b.PatcherName == SelfUpdate.DefaultExeName && b.PatcherSize > 0
                && b.PatcherSha256 != null && System.Text.RegularExpressions.Regex.IsMatch(b.PatcherSha256, "^[0-9a-f]{64}$"), "build/release.json: patcher_asset name, size, sha256");
            Assert(b != null && !string.IsNullOrEmpty(b.ReleaseTag), "build/release.json: release_tag");
        }
        else Console.WriteLine("  note: build/release.json not found, only the sample is checked");

        string upper = new string('A', 64);
        ReleaseManifest s = ReleaseManifest.FromReleaseJson("{\"release_version\": \"v3.1.3-RU\", \"release_tag\": \"v3.1.3-RU\", \"format_version\": 2,"
            + " \"patcher_asset\": {\"name\": \"Lord-of-Mysteries-Russian-Patch.exe\", \"sha256\": \"" + upper + "\", \"size\": 733984},"
            + " \"payload\": {\"name\": \"lom-russian-patch-data.zip\", \"sha256\": \"" + new string('b', 64) + "\", \"size\": 1}}");
        Assert(s != null && s.PatcherSha256 == new string('a', 64) && s.PatcherSize == 733984 && s.ReleaseTag == "v3.1.3-RU", "sample: sha256 lower-cased, size, tag");
        ReleaseManifest old = ReleaseManifest.FromReleaseJson("{\"release_version\": \"v3.0.0-RU\", \"payload\": {\"sha256\": \"" + new string('b', 64) + "\", \"size\": 1}}");
        Assert(old != null && old.PatcherSha256 == null && !SelfUpdate.IsNewer(old), "release.json without patcher_asset -> no self-update");
        Assert(SelfUpdate.ExeName(old) == SelfUpdate.DefaultExeName && SelfUpdate.ExeName(new ReleaseManifest { PatcherName = @"..\evil\x.exe" }) == "x.exe", "exe name: default, no path parts");
    }

    static void SelfUpdateBadDownload()
    {
        ResetSelfUpdate();
        string exe;
        string root = SelfUpdateSandbox("selfupdate-sha", out exe);
        ReleaseManifest m = SelfUpdateRelease(root, "new installer\n");
        var log = new List<string>();

        m.PatcherSha256 = new string('0', 64);
        Assert(Prepare(m, exe, log) == null, "foreign sha256 -> null");
        Assert(log.Exists(s => s.Contains("SHA-256 нового установщика не совпадает с release.json")), "log names the sha256 mismatch");
        Assert(!File.Exists(exe + ".new") && !File.Exists(exe + ".old") && File.ReadAllText(exe) == "old installer\n", ".new removed, exe intact");

        m = SelfUpdateRelease(root, "new installer\n");
        m.PatcherSize += 1;
        log.Clear();
        Assert(Prepare(m, exe, log) == null && log.Exists(s => s.Contains("Размер нового установщика")), "wrong size -> null");
        Assert(!File.Exists(exe + ".new") && File.ReadAllText(exe) == "old installer\n", "wrong size: .new removed, exe intact");

        SelfUpdate.Download = (url, dest, size, progress, token, l) => System.Threading.Tasks.Task.FromResult(false);
        m = SelfUpdateRelease(root, "new installer\n");
        Assert(Prepare(m, exe, log) == null && File.ReadAllText(exe) == "old installer\n" && !File.Exists(exe + ".new"), "download failed -> null, exe intact");
        ResetSelfUpdate();
    }

    static void SelfUpdateSwap()
    {
        ResetSelfUpdate();
        string exe;
        string root = SelfUpdateSandbox("selfupdate-swap", out exe);
        ReleaseManifest m = SelfUpdateRelease(root, "new installer\n");
        var log = new List<string>();
        string started = Prepare(m, exe, log);
        Assert(started == exe, "the exe to start is the original path: " + started + " / " + string.Join(" | ", log.ToArray()));
        Assert(File.ReadAllText(exe) == "new installer\n", "new content in place of the exe");
        Assert(File.Exists(exe + ".old") && File.ReadAllText(exe + ".old") == "old installer\n", "old exe kept as .old");
        Assert(!File.Exists(exe + ".new"), "no .new left");
        Assert(!Directory.Exists(SelfUpdate.FallbackDir), "fallback not used");

        // A second update replaces the stale .old.
        m = SelfUpdateRelease(root, "newer installer\n");
        Assert(Prepare(m, exe, log) == exe && File.ReadAllText(exe + ".old") == "new installer\n", "second swap: previous exe becomes .old");
        Assert(SelfUpdate.CleanupOld(exe) && !File.Exists(exe + ".old") && File.ReadAllText(exe) == "newer installer\n", "cleanup removes .old, exe stays");
        ResetSelfUpdate();
    }

    static void SelfUpdateLockedFallback()
    {
        ResetSelfUpdate();
        string exe;
        string root = SelfUpdateSandbox("selfupdate-locked", out exe);
        ReleaseManifest m = SelfUpdateRelease(root, "new installer\n");
        var log = new List<string>();
        string started;
        using (new FileStream(exe, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            started = Prepare(m, exe, log);
        }
        string fallback = Path.Combine(SelfUpdate.FallbackDir, SelfUpdate.DefaultExeName);
        Assert(started == fallback && File.ReadAllText(fallback) == "new installer\n", "new exe in the fallback folder: " + started);
        Assert(fallback.StartsWith(PayloadSource.AppDataRoot, StringComparison.OrdinalIgnoreCase), "fallback under the (test) AppDataRoot");
        Assert(File.ReadAllText(exe) == "old installer\n" && !File.Exists(exe + ".old") && !File.Exists(exe + ".new"), "original exe intact, no .old/.new");
        Assert(log.Exists(s => s.Contains("Новая версия сохранена в") && s.Contains("дальше запускайте её")), "log points to the fallback exe");

        // The new file cannot be moved into place: the original is renamed back.
        string newFile = exe + ".new";
        WriteText(newFile, "new installer\n");
        using (new FileStream(newFile, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            Assert(SelfUpdate.Swap(exe, newFile, s => log.Add(s)) == null, "second step fails -> null");
        }
        Assert(File.ReadAllText(exe) == "old installer\n" && !File.Exists(exe + ".old"), "rollback: original exe back in place");
        ResetSelfUpdate();
    }

    static void SelfUpdateCleanup()
    {
        string exe;
        SelfUpdateSandbox("selfupdate-cleanup", out exe);
        Assert(SelfUpdate.CleanupOld(exe), "nothing to clean -> true");
        WriteText(exe + ".old", "old\n");
        WriteText(exe + ".new", "new\n");
        Assert(SelfUpdate.CleanupOld(exe) && !File.Exists(exe + ".old") && !File.Exists(exe + ".new"), "free .old/.new removed");
        WriteText(exe + ".old", "old\n");
        bool busyResult;
        using (new FileStream(exe + ".old", FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            busyResult = SelfUpdate.CleanupOld(exe);
        }
        Assert(!busyResult && File.Exists(exe + ".old"), "busy .old: false, no exception");
        Assert(SelfUpdate.CleanupOld(exe) && File.Exists(exe), "freed later -> removed, exe stays");
        ResetSelfUpdate();
    }

    static void InstallerLogWrites()
    {
        string saved = InstallerLog.Dir;
        InstallerLog.Dir = Path.Combine(testRoot, "installer-log-test");
        try
        {
            InstallerLog.Start();
            InstallerLog.Append("строка журнала");
            string text = File.ReadAllText(InstallerLog.LogPath);
            Assert(text.Contains("=== AbsoluteRU " + AppInfo.Version + " запущен ===") && text.Contains(" строка журнала\n"), "header and line written");
            Assert(System.Text.RegularExpressions.Regex.IsMatch(text, @"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d ="), "yyyy-MM-dd HH:mm:ss prefix");
            Assert(File.ReadAllBytes(InstallerLog.LogPath)[0] == (byte)'2', "UTF-8 without BOM");

            WriteText(InstallerLog.OldLogPath, "older\n");
            using (var fs = new FileStream(InstallerLog.LogPath, FileMode.Append)) fs.Write(new byte[InstallerLog.MaxSize], 0, (int)InstallerLog.MaxSize);
            InstallerLog.Start();
            Assert(new FileInfo(InstallerLog.OldLogPath).Length > InstallerLog.MaxSize, "big log renamed to installer.old.log (old .old replaced)");
            Assert(new FileInfo(InstallerLog.LogPath).Length < 200 && File.ReadAllText(InstallerLog.LogPath).Contains("запущен"), "new log starts with the header");

            // LogCollector takes both journals.
            string game = LogsGame("logs-journal", 1);
            LogCollectResult r = LogCollector.Collect(game, Path.Combine(testRoot, "logs-journal", "exe"));
            Assert(r.Error == null && r.Files.Contains(InstallerLog.FileName) && r.Files.Contains(InstallerLog.OldFileName), "installer.log and installer.old.log copied: " + string.Join(",", r.Files.ToArray()));

            Directory.Delete(InstallerLog.Dir, true);
            WriteText(Path.Combine(testRoot, "installer-log-blocker"), "x");
            InstallerLog.Dir = Path.Combine(testRoot, "installer-log-blocker");   // a file: every write fails
            InstallerLog.Start();
            InstallerLog.Append("no throw");
            Assert(true, "write errors are swallowed");
        }
        finally { InstallerLog.Dir = saved; }
    }

    static void LogCollectorFallback()
    {
        string game = LogsGame("logs-fallback", 2);
        string notADir = Path.Combine(testRoot, "logs-fallback", "exe-is-a-file");
        WriteText(notADir, "file\n");   // outRoot\AbsoluteRU_logs cannot be created
        LogCollector.DesktopDir = Path.Combine(testRoot, "logs-fallback", "desktop");
        LogCollectResult r = LogCollector.Collect(game, notADir);
        Assert(r.Error == null && r.UsedFallback && r.Folder == Path.Combine(LogCollector.DesktopDir, LogCollector.FolderName), "fallback to the Desktop: " + r.Error);
        Assert(r.Files.Count == 2 && File.Exists(Path.Combine(r.Folder, "C7.log")), "2 logs on the Desktop");
    }

    // ------------------------------------------------------------ UI: markup, links, "Как играть" (installer/Ui)

    // WPF objects need an STA thread; exceptions are rethrown into Run.
    static Action InSta(Action test)
    {
        return () =>
        {
            Exception error = null;
            var t = new System.Threading.Thread(() => { try { test(); } catch (Exception ex) { error = ex; } });
            t.SetApartmentState(System.Threading.ApartmentState.STA);
            t.Start();
            t.Join();
            if (error != null) throw error;
        };
    }

    static void MarkupLoads()
    {
        PayloadSource.ExplicitPayload = null;
        UiKit.EnsureApplication();
        var main = (System.Windows.Window)UiKit.LoadXaml(MainWindow.XamlResource);
        foreach (string name in MainWindow.ElementNames) Assert(main.FindName(name) != null, "MainWindow.xaml has " + name);
        var how = (System.Windows.Window)UiKit.LoadXaml(HowToPlayWindow.XamlResource);
        foreach (string name in HowToPlayWindow.ElementNames) Assert(how.FindName(name) != null, "HowToPlayWindow.xaml has " + name);
        // The constructor binds every element with its type and wires links; it does not touch any game folder.
        System.Windows.Window created = MainWindow.Create();
        Assert(created != null && created.Title.Contains(AppInfo.Version), "MainWindow.Create() binds the markup");
        Assert(UiKit.LoadImage(UiKit.IconResource) != null, "app.ico resource decodes");
        created.Close();
    }

    static void LinksValidation()
    {
        var links = Links.Load();
        Assert(links.Count == 6, "6 embedded links: " + links.Count);
        Assert(Links.Get(Links.TelegramChannel) == "https://t.me/LoM_ru_patch", "telegram_channel");
        Assert(Links.Get(Links.TelegramAuthor) == "https://t.me/AbsoluteGrek", "telegram_author");
        Assert(Links.Get(Links.TelegramDm) == "https://t.me/KapGrek", "telegram_dm");
        Assert(Links.Get(Links.Boosty) == "https://boosty.to/kapgrek", "boosty");
        Assert(Links.Get(Links.CpddDiscord) == "https://discord.gg/yyds", "cpdd_discord");
        Assert(Links.Get(Links.Github) == "https://github.com/" + AppInfo.Repo, "github");

        var parsed = Links.Parse("{\"a\": \"http://t.me/x\", \"b\": \"https://evil.com/x\", \"c\": \"javascript:alert(1)\", \"d\": \"\", " +
            "\"e\": \"https://t.me.evil.com/x\", \"f\": \"https://user@t.me/x\", \"g\": \"https://t.me:8443/x\", \"h\": \"https://www.github.com/x\", \"i\": 5}");
        Assert(parsed.Count == 1 && parsed.ContainsKey("h"), "only https on allowed hosts survives: " + string.Join(",", new List<string>(parsed.Keys).ToArray()));
        Assert(Links.Parse("not json").Count == 0, "broken json -> no links");
        Assert(Links.Parse("{\"telegram_channel\": \"\"}").Count == 0, "empty value -> button hidden");
    }

    static void CountBlocks(System.Windows.Documents.BlockCollection blocks, Dictionary<string, int> counts)
    {
        foreach (System.Windows.Documents.Block b in blocks)
        {
            var p = b as System.Windows.Documents.Paragraph;
            var list = b as System.Windows.Documents.List;
            var steps = b as System.Windows.Documents.Section;
            if (b.Tag is string) Bump(counts, (string)b.Tag);   // h1, h2, img, ol (steps section), ul
            if (p != null) CountInlines(p.Inlines, counts);
            if (list != null)
            {
                foreach (System.Windows.Documents.ListItem item in list.ListItems)
                {
                    Bump(counts, "li");
                    CountBlocks(item.Blocks, counts);
                }
            }
            if (steps != null)
            {
                foreach (System.Windows.Documents.Block item in steps.Blocks)
                {
                    Bump(counts, "li");
                    var ip = item as System.Windows.Documents.Paragraph;
                    if (ip != null) CountInlines(ip.Inlines, counts);
                }
            }
        }
    }

    static void CountInlines(System.Windows.Documents.InlineCollection inlines, Dictionary<string, int> counts)
    {
        foreach (System.Windows.Documents.Inline i in inlines)
        {
            if (i is System.Windows.Documents.Hyperlink) Bump(counts, "a");
            if (i is System.Windows.Documents.Bold) Bump(counts, "b");
            var span = i as System.Windows.Documents.Span;
            if (span != null) CountInlines(span.Inlines, counts);
        }
    }

    static void Bump(Dictionary<string, int> counts, string key)
    {
        int n;
        counts.TryGetValue(key, out n);
        counts[key] = n + 1;
    }

    static int Count(Dictionary<string, int> counts, string key)
    {
        int n;
        return counts.TryGetValue(key, out n) ? n : 0;
    }

    static void HowToPlayParses()
    {
        UiKit.EnsureApplication();
        string md = "# A\n\ntext **bold** [ok](https://t.me/x) [bad](http://t.me/x) [js](javascript:alert(1)) [evil](https://evil.com/)\nnext line\n\n## B\n\n" +
            "1. one\n2. two\n\n![](img/pic.png)\n\n3. three\n\n- a\n- b\n\n![](img/missing.png)\n";
        var pic = System.Windows.Media.Imaging.BitmapSource.Create(2, 2, 96, 96, System.Windows.Media.PixelFormats.Gray8, null, new byte[4], 2);
        var doc = HowToPlayWindow.BuildDocument(md, name => name == "pic.png" ? pic : null);
        var c = new Dictionary<string, int>();
        CountBlocks(doc.Blocks, c);
        Assert(Count(c, "h1") == 1 && Count(c, "h2") == 1, "one section, one subsection");
        Assert(Count(c, "ol") == 2 && Count(c, "ul") == 1 && Count(c, "li") == 5, "lists: 2 numbered, 1 bulleted, 5 items");
        Assert(Count(c, "a") == 1, "only the https t.me link is a hyperlink (http, javascript:, foreign host stay text)");
        Assert(Count(c, "b") == 1, "bold");
        Assert(Count(c, "img") == 1, "known image shown, missing one skipped");
        List<string> numbers = StepNumbers(doc);
        Assert(string.Join(",", numbers.ToArray()) == "1,2,3", "step numbers as written, across the image: " + string.Join(",", numbers.ToArray()));
        string docText = new System.Windows.Documents.TextRange(doc.ContentStart, doc.ContentEnd).Text;
        Assert(docText.Contains("bad") && !docText.Contains("javascript"), "blocked link keeps its label, not the url");

        // The real text built into the installer.
        doc = HowToPlayWindow.BuildDocument(HowToPlayWindow.LoadText(), name => UiKit.LoadImage(HowToPlayWindow.ImageResourcePrefix + name));
        c = new Dictionary<string, int>();
        CountBlocks(doc.Blocks, c);
        Assert(Count(c, "h1") == 4, "HowToPlay.md: 4 sections, got " + Count(c, "h1"));
        Assert(Count(c, "li") == 10 + 4 + 2 + 4, "HowToPlay.md: 10 steps and 10 items, got " + Count(c, "li"));
        Assert(Count(c, "a") == 7, "HowToPlay.md: 7 links (launcher, ID document, channel x2, KapGrek, AbsoluteGrek, Boosty), got " + Count(c, "a"));
        Assert(Count(c, "img") == 1, "HowToPlay.md: QR login picture");
        numbers = StepNumbers(doc);
        Assert(string.Join(",", numbers.ToArray()) == "9,8,7,6,5,4,3,2,1,0", "HowToPlay.md: countdown 9 -> 0, got " + string.Join(",", numbers.ToArray()));
    }

    static List<string> StepNumbers(System.Windows.Documents.FlowDocument doc)
    {
        var numbers = new List<string>();
        foreach (var b in doc.Blocks)
        {
            var steps = b as System.Windows.Documents.Section;
            if (steps == null) continue;
            foreach (var item in steps.Blocks) numbers.Add((string)item.Tag);
        }
        return numbers;
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
