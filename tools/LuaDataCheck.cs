// LuaDataCheck.cs - offline check of the Init.lua data-literal parser (TASK-032).
//
//   tools/LuaDataCheck.exe [-Root <repo>] [-Dir <folder with .lua data files>]
//
// Every RuntimeTextGemini_*.lua, LanguageSourceIndex_*.lua and WidgetNameIndex.lua is read twice:
//   1. LuaReader  - a reader with Lua 5.1 lexer/constructor semantics (llex.c read_string, strtod numbers,
//                   long strings and comments, positional fields flushed every 50 items like OP_SETLIST);
//   2. PortParser - a line-by-line port of runtimeFixes.parseDataLiteral from Init.lua.
// The resulting tables are compared byte for byte (strings as raw bytes). Exit code 0 only when every file
// parses with both and there are 0 differences. No Lua interpreter is needed (python/lua are not installed).
// C# 5 (csc .NET 4): no string interpolation.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

public static class LuaDataCheck {
    // Lua strings are bytes: Latin-1 maps every byte to one char 1:1.
    static readonly Encoding Bytes = Encoding.GetEncoding(28591);

    public static int Main(string[] args) {
        string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
        string dir = null;
        for (int i = 0; i + 1 < args.Length; i++) {
            if (args[i] == "-Root") root = Path.GetFullPath(args[++i]);
            else if (args[i] == "-Dir") dir = Path.GetFullPath(args[++i]);
        }
        if (dir == null) dir = Path.Combine(root, @"patch_payload\Saved\Mods\lua\mods\cpdd_runtime_fixes");

        List<string> files = new List<string>();
        files.AddRange(Directory.GetFiles(dir, "RuntimeTextGemini_*.lua"));
        files.AddRange(Directory.GetFiles(dir, "LanguageSourceIndex_*.lua"));
        if (File.Exists(Path.Combine(dir, "WidgetNameIndex.lua"))) files.Add(Path.Combine(dir, "WidgetNameIndex.lua"));
        files.Sort(StringComparer.Ordinal);

        int failed = 0, differences = 0;
        long entries = 0;
        foreach (string file in files) {
            string text = Bytes.GetString(File.ReadAllBytes(file));
            string name = Path.GetFileName(file);
            object reference, port;
            try { reference = new LuaReader(text).ReadChunk(); }
            catch (Exception e) { Console.WriteLine("FAIL lua    " + name + ": " + e.Message); failed++; continue; }
            try { port = new PortParser(text).Parse(); }
            catch (Exception e) { Console.WriteLine("FAIL parser " + name + ": " + e.Message); failed++; continue; }
            Dictionary<object, object> table = reference as Dictionary<object, object>;
            if (table != null) entries += table.Count;
            List<string> diffs = new List<string>();
            Compare(reference, port, "", diffs);
            if (diffs.Count > 0) {
                differences += diffs.Count;
                Console.WriteLine("DIFF " + name + ": " + diffs.Count);
                for (int i = 0; i < Math.Min(5, diffs.Count); i++) Console.WriteLine("  " + diffs[i]);
            }
        }
        Console.WriteLine("Files: " + files.Count + ", entries: " + entries + ", parse failures: " + failed + ", differences: " + differences);
        return failed == 0 && differences == 0 && files.Count > 0 ? 0 : 1;
    }

    static string Show(object v) {
        if (v == null) return "nil";
        string s = v as string;
        if (s != null) {
            string u = Encoding.UTF8.GetString(Bytes.GetBytes(s));
            return "\"" + (u.Length > 60 ? u.Substring(0, 60) + "..." : u) + "\"";
        }
        if (v is double) return ((double)v).ToString("R", CultureInfo.InvariantCulture);
        if (v is Dictionary<object, object>) return "table";
        return v.ToString();
    }

    static void Compare(object a, object b, string path, List<string> diffs) {
        Dictionary<object, object> ta = a as Dictionary<object, object>, tb = b as Dictionary<object, object>;
        if (ta != null && tb != null) {
            foreach (KeyValuePair<object, object> kv in ta) {
                object other;
                if (!tb.TryGetValue(kv.Key, out other)) diffs.Add(path + "[" + Show(kv.Key) + "] missing in parser");
                else Compare(kv.Value, other, path + "[" + Show(kv.Key) + "]", diffs);
            }
            foreach (object k in tb.Keys) if (!ta.ContainsKey(k)) diffs.Add(path + "[" + Show(k) + "] extra in parser");
            return;
        }
        if (!object.Equals(a, b)) diffs.Add(path + ": lua " + Show(a) + " vs parser " + Show(b));
    }

    // lua_str2number (Lua 5.1): strtod, or hex through strtoul; surrounding spaces allowed.
    public static bool TryLuaNumber(string s, out double value) {
        value = 0;
        string t = s.Trim(' ', '\t', '\n', '\r', '\f', '\v');
        if (t.Length == 0) return false;
        if (t.StartsWith("0x") || t.StartsWith("0X")) {
            ulong u;
            if (t.Length > 2 && ulong.TryParse(t.Substring(2), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out u)) { value = u; return true; }
            return false;
        }
        foreach (char c in t) if (!(char.IsDigit(c) || c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-')) return false;
        return double.TryParse(t, NumberStyles.Float, CultureInfo.InvariantCulture, out value);
    }

    // Values: string (bytes as Latin-1), double, bool, Dictionary<object, object>. Keys of integral doubles stay double.
    sealed class LuaReader {
        readonly string s; int p;
        public LuaReader(string text) { s = text; }
        char Cur { get { return p < s.Length ? s[p] : '\0'; } }
        Exception Err(string m) { return new Exception(m + " at byte " + (p + 1)); }

        int LongBracketLevel(int at) {
            if (at >= s.Length || s[at] != '[') return -1;
            int q = at + 1, level = 0;
            while (q < s.Length && s[q] == '=') { level++; q++; }
            return q < s.Length && s[q] == '[' ? level : -1;
        }
        string ReadLong(int level) {
            p += level + 2;
            if (Cur == '\r' || Cur == '\n') { char c = Cur; p++; if ((Cur == '\r' || Cur == '\n') && Cur != c) p++; }
            string close = "]" + new string('=', level) + "]";
            int e = s.IndexOf(close, p, StringComparison.Ordinal);
            if (e < 0) throw Err("unfinished long string");
            string r = s.Substring(p, e - p);
            p = e + close.Length;
            return r;
        }
        void Skip() {
            while (p < s.Length) {
                char c = s[p];
                if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\v') { p++; continue; }
                if (c == '-' && p + 1 < s.Length && s[p + 1] == '-') {
                    p += 2;
                    int level = LongBracketLevel(p);
                    if (level >= 0) { ReadLong(level); continue; }
                    while (p < s.Length && s[p] != '\n' && s[p] != '\r') p++;
                    continue;
                }
                return;
            }
        }
        string ReadString(char quote) {
            StringBuilder sb = new StringBuilder();
            p++;
            while (true) {
                if (p >= s.Length) throw Err("unfinished string");
                char c = s[p];
                if (c == quote) { p++; return sb.ToString(); }
                if (c == '\n' || c == '\r') throw Err("unfinished string");
                if (c != '\\') { sb.Append(c); p++; continue; }
                p++;
                char e = Cur;
                switch (e) {
                    case 'a': sb.Append('\a'); p++; break;
                    case 'b': sb.Append('\b'); p++; break;
                    case 'f': sb.Append('\f'); p++; break;
                    case 'n': sb.Append('\n'); p++; break;
                    case 'r': sb.Append('\r'); p++; break;
                    case 't': sb.Append('\t'); p++; break;
                    case 'v': sb.Append('\v'); p++; break;
                    case '\n': case '\r': sb.Append('\n'); { char c0 = e; p++; if ((Cur == '\r' || Cur == '\n') && Cur != c0) p++; } break;
                    case '\0': if (p >= s.Length) throw Err("unfinished string"); sb.Append(e); p++; break;
                    default:
                        if (!char.IsDigit(e)) { sb.Append(e); p++; break; }
                        int code = 0, n = 0;
                        while (n < 3 && p < s.Length && char.IsDigit(s[p])) { code = code * 10 + (s[p] - '0'); p++; n++; }
                        if (code > 255) throw Err("escape sequence too large");
                        sb.Append((char)code);
                        break;
                }
            }
        }
        double ReadNumber() {
            int start = p;
            while (p < s.Length && (char.IsLetterOrDigit(s[p]) || s[p] == '.' || s[p] == '_')) {
                if ((s[p] == 'e' || s[p] == 'E') && p + 1 < s.Length && (s[p + 1] == '+' || s[p + 1] == '-')) p++;
                p++;
            }
            double v;
            if (!TryLuaNumber(s.Substring(start, p - start), out v)) throw Err("malformed number");
            return v;
        }
        object ReadExp() {
            Skip();
            char c = Cur;
            if (c == '"' || c == '\'') return ReadString(c);
            if (c == '[') { int level = LongBracketLevel(p); if (level >= 0) return ReadLong(level); }
            if (c == '{') return ReadTable();
            if (c == '-') { p++; Skip(); object v = ReadExp(); if (!(v is double)) throw Err("arithmetic on non-number"); return -(double)v; }
            if (char.IsDigit(c) || (c == '.' && p + 1 < s.Length && char.IsDigit(s[p + 1]))) return ReadNumber();
            if (Word("true")) return true;
            if (Word("false")) return false;
            if (Word("nil")) return null;
            throw Err("unexpected symbol");
        }
        bool Word(string w) {
            if (string.CompareOrdinal(s, p, w, 0, w.Length) != 0) return false;
            int e = p + w.Length;
            if (e < s.Length && (char.IsLetterOrDigit(s[e]) || s[e] == '_')) return false;
            p = e;
            return true;
        }
        static object Key(object k) { return k; }
        Dictionary<object, object> ReadTable() {
            p++;
            Dictionary<object, object> t = new Dictionary<object, object>();
            List<object> pending = new List<object>();
            int arrayIndex = 0;
            while (true) {
                Skip();
                if (Cur == '}') { p++; break; }
                if (Cur == '[' && LongBracketLevel(p) < 0) {
                    p++;
                    object k = ReadExp();
                    Skip(); if (Cur != ']') throw Err("']' expected"); p++;
                    Skip(); if (Cur != '=') throw Err("'=' expected"); p++;
                    object v = ReadExp();
                    if (k == null) throw Err("table index is nil");
                    if (v == null) t.Remove(k); else t[k] = v;
                } else {
                    pending.Add(ReadExp());
                    if (pending.Count == 50) { Flush(t, pending, ref arrayIndex); }
                }
                Skip();
                if (Cur == ',' || Cur == ';') { p++; continue; }
                if (Cur == '}') { p++; break; }
                throw Err("'}' expected");
            }
            Flush(t, pending, ref arrayIndex);
            return t;
        }
        static void Flush(Dictionary<object, object> t, List<object> pending, ref int arrayIndex) {
            foreach (object v in pending) {
                arrayIndex++;
                object k = (double)arrayIndex;
                if (v == null) t.Remove(k); else t[k] = v;
            }
            pending.Clear();
        }
        public object ReadChunk() {
            Skip();
            if (!Word("return")) throw Err("'return' expected");
            object v = ReadExp();
            Skip();
            if (Cur == ';') { p++; Skip(); }
            if (p < s.Length) throw Err("'<eof>' expected");
            return v;
        }
    }

    // Port of runtimeFixes.parseDataLiteral (Init.lua). Keep it in step with the Lua code.
    sealed class PortParser {
        readonly string text; int pos; readonly int len;   // pos is 1-based like Lua
        public PortParser(string t) { text = t; len = t.Length; pos = 1; }
        Exception Fail(string m) { return new Exception(m + " at byte " + pos); }
        int Byte(int at) { return at >= 1 && at <= len ? text[at - 1] : -1; }
        string Sub(int i, int j) { if (j > len) j = len; return i > j ? "" : text.Substring(i - 1, j - i + 1); }
        int Find(Func<char, bool> pred, int init) { for (int i = Math.Max(init, 1); i <= len; i++) if (pred(text[i - 1])) return i; return 0; }

        void Skip() {
            while (true) {
                int s = Find(c => c != ' ' && c != '\t' && c != '\r' && c != '\n', pos);   // [^ \t\r\n]
                if (s == 0) { pos = len + 1; return; }
                pos = s;
                if (Sub(pos, pos + 1) != "--") return;
                int e = Find(c => c == '\n', pos);
                pos = e != 0 ? e + 1 : len + 1;
            }
        }
        string ParseString() {
            StringBuilder parts = new StringBuilder();
            pos = pos + 1;
            while (true) {
                int s = Find(c => c == '"' || c == '\\' || c == '\r' || c == '\n', pos);   // ["\\\r\n]
                if (s == 0) throw Fail("unfinished string");
                if (s > pos) parts.Append(Sub(pos, s - 1));
                int c0 = Byte(s);
                if (c0 == 34) { pos = s + 1; return parts.ToString(); }
                else if (c0 != 92) { pos = s; throw Fail("unfinished string"); }
                string mapped = Escape(Sub(s + 1, s + 1));
                if (mapped != null) { parts.Append(mapped); pos = s + 2; }
                else {
                    int n = 0;   // text:match("^%d%d?%d?", s + 1)
                    while (n < 3 && Byte(s + 1 + n) >= '0' && Byte(s + 1 + n) <= '9') n++;
                    int code = n > 0 ? int.Parse(Sub(s + 1, s + n), CultureInfo.InvariantCulture) : -1;
                    if (code < 0 || code > 255) { pos = s; throw Fail("invalid escape sequence"); }
                    parts.Append((char)code);
                    pos = s + 1 + n;
                }
            }
        }
        static string Escape(string e) {
            switch (e) {
                case "n": return "\n"; case "r": return "\r"; case "t": return "\t"; case "a": return "\a";
                case "b": return "\b"; case "f": return "\f"; case "v": return "\v";
                case "\\": return "\\"; case "\"": return "\""; case "'": return "'";
            }
            return null;
        }
        void Expect(int b, string name) { Skip(); if (Byte(pos) != b) throw Fail("'" + name + "' expected"); pos = pos + 1; }
        Dictionary<object, object> ParseTable() {
            pos = pos + 1;
            Dictionary<object, object> result = new Dictionary<object, object>();
            int index = 0;
            while (true) {
                Skip();
                int c = Byte(pos);
                if (c == 125) { pos = pos + 1; return result; }
                if (c == 91) {
                    pos = pos + 1;
                    Skip();
                    object key = ParseValue();
                    if (key == null) throw Fail("table index is nil");
                    Expect(93, "]");
                    Expect(61, "=");
                    Skip();
                    result[key] = ParseValue();
                } else {
                    index = index + 1;
                    result[(double)index] = ParseValue();
                }
                Skip();
                c = Byte(pos);
                if (c == 44 || c == 59) pos = pos + 1;
                else if (c != 125) throw Fail("'}' expected");
            }
        }
        static bool IsAlnum(int c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
        object ParseValue() {
            int c = Byte(pos);
            if (c == 34) return ParseString();
            if (c == 123) return ParseTable();
            int e = pos;   // text:match("^%-?[%w%.]+", pos)
            if (Byte(e) == '-') e++;
            int body = e;
            while (IsAlnum(Byte(e)) || Byte(e) == '.') e++;
            if (e == body) throw Fail("unexpected symbol");
            string word = Sub(pos, e - 1);
            pos = pos + word.Length;
            if (word == "true") return true;
            if (word == "false") return false;
            double number;
            if (!TryLuaNumber(word, out number)) throw Fail("malformed number '" + word + "'");
            return number;
        }
        public object Parse() {
            Skip();
            if (Sub(pos, pos + 5) != "return" || (Byte(pos + 6) == '_' || IsAlnum(Byte(pos + 6)))) throw Fail("'return' expected");
            pos = pos + 6;
            Skip();
            object value = ParseValue();
            Skip();
            if (Byte(pos) == 59) { pos = pos + 1; Skip(); }
            if (pos <= len) throw Fail("'<eof>' expected");
            return value;
        }
    }
}
