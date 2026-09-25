using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace LotmRussianPatcher
{
    // Same modes as the CPDD installer: Saved/Mods/lua/cpdd_patcher_settings.lua -> DpsMeterMode (bootstrap.lua apply_feature_settings).
    public enum DpsMeterMode
    {
        Native,     // "native": the game's own Statistics button everywhere
        Advanced,   // "advanced": DpsMeter.lua panels (default)
        External,   // "external": DpsTelemetry.lua -> Lord of Mysteries Combat Meter.exe
        Off         // "off": no meters
    }

    public class GameOptionsState
    {
        public DpsMeterMode DpsMode = DpsMeterMode.Advanced;
        public bool DesktopChat;
        public bool VisualClarity;

        public bool SameAs(GameOptionsState other)
        {
            return other != null && DpsMode == other.DpsMode && DesktopChat == other.DesktopChat && VisualClarity == other.VisualClarity;
        }
    }

    // CPDD options in the game folder. Knows nothing about UI; covered by tools/InstallerCoreTests.cs.
    public class GameOptions
    {
        public const string SettingsRel = @"Saved\Mods\lua\cpdd_patcher_settings.lua";
        public const string EngineIniRel = @"Saved\Config\Windows\Engine.ini";
        public const string OptionsStateRel = @"Saved\RussianPatchBackups\options.json";
        public const string CombatMeterRel = @"Saved\Mods\ExternalDpsMeter\Lord of Mysteries Combat Meter.exe";
        public const string CombatMeterProcess = "Lord of Mysteries Combat Meter";

        public const string BeginMarker = "; BEGIN CPDD VISUAL CLARITY PATCH";
        public const string EndMarker = "; END CPDD VISUAL CLARITY PATCH";

        // Byte for byte the block of the CPDD installer 2.6.1 (LF); EngineIniBridge.lua reads it.
        public const string VisualClarityBlock =
            "; BEGIN CPDD VISUAL CLARITY PATCH\n" +
            "; Managed by the Lord of Mysteries English Patcher. Disable the option to remove this block.\n" +
            "[/Script/Engine.RendererSettings]\n" +
            "r.DynamicGlobalIlluminationMethod=0\n" +
            "r.ReflectionMethod=0\n" +
            "\n" +
            "[ConsoleVariables]\n" +
            "r.MotionBlurQuality=0\n" +
            "r.DefaultFeature.MotionBlur=0\n" +
            "r.LensFlareQuality=0\n" +
            "r.DefaultFeature.LensFlare=0\n" +
            "r.BloomQuality=0\n" +
            "r.DefaultFeature.Bloom=0\n" +
            "r.LightShaftQuality=0\n" +
            "r.RefractionQuality=0\n" +
            "r.Refraction.OffsetQuality=0\n" +
            "r.DistanceFieldAO=0\n" +
            "r.AOQuality=0\n" +
            "r.AmbientOcclusionLevels=0\n" +
            "r.AmbientOcclusionMaxQuality=0\n" +
            "r.Fog=0\n" +
            "r.VolumetricFog=0\n" +
            "r.VolumetricCloud=0\n" +
            "; END CPDD VISUAL CLARITY PATCH\n";

        private static readonly Regex ModeEntry = new Regex("^DpsMeterMode\\s*=\\s*\"(off|native|advanced|external)\"$");
        private static readonly Regex ChatEntry = new Regex("^DesktopChatUI\\s*=\\s*(true|false)$");
        private static readonly Regex TableFile = new Regex("^\\s*return\\s*\\{(?<body>[^{}]*)\\}\\s*$");
        private static readonly Regex LineComment = new Regex("--[^\\n]*");

        private readonly string gameDir;
        private readonly Action<string> log;

        public GameOptions(string gameDir, Action<string> log)
        {
            if (string.IsNullOrEmpty(gameDir)) throw new ArgumentException("gameDir");
            this.gameDir = Path.GetFullPath(gameDir);
            this.log = log ?? (s => { });
        }

        public string SettingsPath { get { return Path.Combine(gameDir, SettingsRel); } }
        public string EngineIniPath { get { return Path.Combine(gameDir, EngineIniRel); } }
        public string OptionsStatePath { get { return Path.Combine(gameDir, OptionsStateRel); } }
        public string CombatMeterPath { get { return Path.Combine(gameDir, CombatMeterRel); } }

        // ------------------------------------------------------------ state

        // Missing files = CPDD defaults (bootstrap.lua): advanced, chat off, no Visual Clarity.
        // error is set when a file exists but cannot be understood; the defaults are returned for it.
        public GameOptionsState Read(out string error)
        {
            error = null;
            var state = new GameOptionsState();
            string settingsError;
            DpsMeterMode mode;
            bool chat;
            if (TryReadSettings(out mode, out chat, out settingsError))
            {
                state.DpsMode = mode;
                state.DesktopChat = chat;
            }
            else error = settingsError;

            string iniError;
            bool vc;
            if (TryReadVisualClarity(out vc, out iniError)) state.VisualClarity = vc;
            else error = error == null ? iniError : error + " " + iniError;
            return state;
        }

        // Writes what differs from the files. Every part is tried; errors are collected.
        public bool Apply(GameOptionsState desired, List<string> errors)
        {
            bool ok = true;
            string error;
            if (!WriteSettings(desired.DpsMode, desired.DesktopChat, out error)) { ok = false; errors.Add(error); }
            if (!SetVisualClarity(desired.VisualClarity, out error)) { ok = false; errors.Add(error); }
            return ok;
        }

        // ------------------------------------------------------------ cpdd_patcher_settings.lua

        public static string ModeName(DpsMeterMode mode)
        {
            switch (mode)
            {
                case DpsMeterMode.Native: return "native";
                case DpsMeterMode.External: return "external";
                case DpsMeterMode.Off: return "off";
                default: return "advanced";
            }
        }

        private static DpsMeterMode ParseMode(string name)
        {
            switch (name)
            {
                case "native": return DpsMeterMode.Native;
                case "external": return DpsMeterMode.External;
                case "off": return DpsMeterMode.Off;
                default: return DpsMeterMode.Advanced;
            }
        }

        // Exactly the file the CPDD installer writes.
        public static string FormatSettings(DpsMeterMode mode, bool desktopChat)
        {
            return "return {\n    DpsMeterMode = \"" + ModeName(mode) + "\",\n    DesktopChatUI = " + (desktopChat ? "true" : "false") + ",\n}\n";
        }

        // Accepts `return { ... }` with only DpsMeterMode / DesktopChatUI entries (the CPDD formats, old one-key files included).
        public static bool ParseSettings(string text, out DpsMeterMode mode, out bool desktopChat)
        {
            mode = DpsMeterMode.Advanced;
            desktopChat = false;
            if (text == null) return false;
            if (text.Length > 0 && text[0] == '\uFEFF') text = text.Substring(1);
            Match m = TableFile.Match(LineComment.Replace(text.Replace("\r\n", "\n"), ""));
            if (!m.Success) return false;
            bool seenMode = false, seenChat = false;
            foreach (string raw in m.Groups["body"].Value.Split(',', ';'))
            {
                string entry = raw.Trim();
                if (entry.Length == 0) continue;
                Match e = ModeEntry.Match(entry);
                if (e.Success && !seenMode) { mode = ParseMode(e.Groups[1].Value); seenMode = true; continue; }
                e = ChatEntry.Match(entry);
                if (e.Success && !seenChat) { desktopChat = e.Groups[1].Value == "true"; seenChat = true; continue; }
                return false;
            }
            return true;
        }

        public bool TryReadSettings(out DpsMeterMode mode, out bool desktopChat, out string error)
        {
            error = null;
            mode = DpsMeterMode.Advanced;
            desktopChat = false;
            string path = SettingsPath;
            if (!File.Exists(path)) return true;
            string text;
            if (!TryReadUtf8(path, out text) || !ParseSettings(text, out mode, out desktopChat))
            {
                error = "Файл изменён вручную и не распознан: " + SettingsRel + ".";
                return false;
            }
            return true;
        }

        // Refuses to overwrite a file it does not understand (foreign keys, syntax); cpdd_user_settings.lua is never touched.
        public bool WriteSettings(DpsMeterMode mode, bool desktopChat, out string error)
        {
            error = null;
            string path = SettingsPath;
            string wanted = FormatSettings(mode, desktopChat);
            if (File.Exists(path))
            {
                string text;
                DpsMeterMode oldMode;
                bool oldChat;
                if (!TryReadUtf8(path, out text) || !ParseSettings(text, out oldMode, out oldChat))
                {
                    error = "Файл изменён вручную: " + SettingsRel + ". Настройки DPS и чата не записаны; удалите файл или исправьте его.";
                    log("ОШИБКА: " + error);
                    return false;
                }
                if (text == wanted) return true;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, wanted, new UTF8Encoding(false));
            log("  -> Настройки: DpsMeterMode = \"" + ModeName(mode) + "\", DesktopChatUI = " + (desktopChat ? "true" : "false") + ".");
            return true;
        }

        // ------------------------------------------------------------ Engine.ini: Visual Clarity

        private class IniText
        {
            public bool Exists;
            public bool Bom;
            public string NewLine = "\n";
            public string Text = "";
            public int BlockStart = -1;   // index of the BEGIN line
            public int BlockEnd = -1;     // index after the END line (including its line break)
        }

        public bool TryReadVisualClarity(out bool enabled, out string error)
        {
            enabled = false;
            IniText ini;
            if (!LoadIni(out ini, out error)) return false;
            enabled = ini.BlockStart >= 0;
            return true;
        }

        public bool SetVisualClarity(bool enable, out string error)
        {
            IniText ini;
            if (!LoadIni(out ini, out error))
            {
                log("ОШИБКА: " + error);
                return false;
            }
            string path = EngineIniPath;
            string block = VisualClarityBlock.Replace("\n", ini.NewLine);

            if (enable)
            {
                string text;
                if (ini.BlockStart >= 0)
                {
                    text = ini.Text.Substring(0, ini.BlockStart) + block + ini.Text.Substring(ini.BlockEnd);
                }
                else if (ini.Text.Length == 0)
                {
                    text = block;
                }
                else
                {
                    string head = ini.Text;
                    if (!head.EndsWith("\n")) head += ini.NewLine;
                    text = head + ini.NewLine + block;
                }
                if (ini.Exists && text == ini.Text) return true;
                if (!ini.Exists) WriteOptionsState(true);
                WriteIni(path, text, ini.Bom);
                log("  -> Чистая картинка: блок записан в " + EngineIniRel + ".");
                return true;
            }

            if (ini.BlockStart < 0) return true;
            string prefix = ini.Text.Substring(0, ini.BlockStart);
            string nl2 = ini.NewLine + ini.NewLine;
            if (prefix.EndsWith(nl2)) prefix = prefix.Substring(0, prefix.Length - ini.NewLine.Length);
            string rest = prefix + ini.Text.Substring(ini.BlockEnd);
            if (rest.Length == 0 && ReadOptionsState())
            {
                File.Delete(path);
                WriteOptionsState(false);
                log("  -> Чистая картинка: блок удалён, " + EngineIniRel + " (создан установщиком) удалён.");
                return true;
            }
            WriteIni(path, rest, ini.Bom);
            log("  -> Чистая картинка: блок удалён из " + EngineIniRel + ".");
            return true;
        }

        private bool LoadIni(out IniText ini, out string error)
        {
            ini = new IniText();
            error = null;
            string path = EngineIniPath;
            if (!File.Exists(path)) return true;
            ini.Exists = true;
            byte[] raw = File.ReadAllBytes(path);
            if (raw.Length >= 2 && ((raw[0] == 0xFF && raw[1] == 0xFE) || (raw[0] == 0xFE && raw[1] == 0xFF)))
            {
                error = EngineIniRel + " в кодировке UTF-16: настройка «Чистая картинка» не изменена.";
                return false;
            }
            ini.Bom = raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF;
            try
            {
                int skip = ini.Bom ? 3 : 0;
                ini.Text = new UTF8Encoding(false, true).GetString(raw, skip, raw.Length - skip);
            }
            catch (DecoderFallbackException)
            {
                error = EngineIniRel + " не в UTF-8: настройка «Чистая картинка» не изменена.";
                return false;
            }
            if (ini.Text.Contains("\r\n")) ini.NewLine = "\r\n";

            // Marker lines only (a marker inside another line does not count).
            var begins = new List<int>();
            var ends = new List<int>();
            int pos = 0;
            while (pos < ini.Text.Length)
            {
                int nl = ini.Text.IndexOf('\n', pos);
                int next = nl < 0 ? ini.Text.Length : nl + 1;
                string line = ini.Text.Substring(pos, (nl < 0 ? ini.Text.Length : nl) - pos).TrimEnd('\r').Trim();
                if (line == BeginMarker) begins.Add(pos);
                else if (line == EndMarker) ends.Add(next);
                pos = next;
            }
            if (begins.Count == 0 && ends.Count == 0) return true;
            if (begins.Count != 1 || ends.Count != 1 || ends[0] <= begins[0])
            {
                error = EngineIniRel + ": повреждённый блок «Чистая картинка» (BEGIN/END). Файл не изменён.";
                return false;
            }
            ini.BlockStart = begins[0];
            ini.BlockEnd = ends[0];
            return true;
        }

        private static void WriteIni(string path, string text, bool bom)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, text, new UTF8Encoding(bom));
        }

        // options.json remembers that Engine.ini was created by us, so turning the option off may delete it.
        private bool ReadOptionsState()
        {
            string path = OptionsStatePath;
            return File.Exists(path) && File.ReadAllText(path, Encoding.UTF8).Contains("\"engine_ini_created\": true");
        }

        private void WriteOptionsState(bool engineIniCreated)
        {
            string path = OptionsStatePath;
            if (!engineIniCreated)
            {
                if (File.Exists(path)) File.Delete(path);
                return;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, "{\n  \"engine_ini_created\": true\n}\n", new UTF8Encoding(false));
        }

        // ------------------------------------------------------------ uninstall / external meter

        // Uninstall: the managed Visual Clarity block goes, cpdd_*settings.lua stay (as with CPDD).
        public bool RemoveManagedBlocks(out string error)
        {
            bool ok = SetVisualClarity(false, out error);
            if (ok) WriteOptionsState(false);
            return ok;
        }

        public bool CombatMeterExists { get { return File.Exists(CombatMeterPath); } }

        private static bool TryReadUtf8(string path, out string text)
        {
            text = null;
            try
            {
                byte[] raw = File.ReadAllBytes(path);
                int skip = raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF ? 3 : 0;
                text = new UTF8Encoding(false, true).GetString(raw, skip, raw.Length - skip);
                return true;
            }
            catch (DecoderFallbackException) { return false; }
        }
    }
}
