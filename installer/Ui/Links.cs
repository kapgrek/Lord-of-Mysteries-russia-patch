using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Web.Script.Serialization;

namespace LotmRussianPatcher
{
    // Social and project links from installer/links.json (resource LotmRussianPatcher.links.json).
    // Only https:// on the allowed hosts; anything else is dropped and its button hidden.
    public static class Links
    {
        public const string ResourceName = "LotmRussianPatcher.links.json";
        public const string TelegramChannel = "telegram_channel";
        public const string TelegramAuthor = "telegram_author";
        public const string Boosty = "boosty";
        public const string CpddDiscord = "cpdd_discord";
        public const string Github = "github";

        // ap.wps.com: the ID confirmation document linked from HowToPlay.md.
        public static readonly string[] AllowedHosts = { "t.me", "boosty.to", "discord.gg", "github.com", "ap.wps.com" };

        public static bool IsAllowedUrl(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return false;
            Uri uri;
            if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out uri) || uri.Scheme != Uri.UriSchemeHttps) return false;
            if (!string.IsNullOrEmpty(uri.UserInfo) || !uri.IsDefaultPort) return false;
            string host = uri.Host.ToLowerInvariant();
            if (host.StartsWith("www.")) host = host.Substring(4);
            return Array.IndexOf(AllowedHosts, host) >= 0;
        }

        // Valid entries only; keys with empty or disallowed values are absent.
        public static Dictionary<string, string> Parse(string json)
        {
            var result = new Dictionary<string, string>(StringComparer.Ordinal);
            Dictionary<string, object> raw;
            try { raw = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json); }
            catch { return result; }
            if (raw == null) return result;
            foreach (var kv in raw)
            {
                string url = kv.Value as string;
                if (IsAllowedUrl(url)) result[kv.Key] = url.Trim();
            }
            return result;
        }

        private static Dictionary<string, string> loaded;

        public static Dictionary<string, string> Load()
        {
            if (loaded != null) return loaded;
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
            {
                if (s == null) return loaded = new Dictionary<string, string>();
                using (var reader = new StreamReader(s, Encoding.UTF8)) loaded = Parse(reader.ReadToEnd());
            }
            return loaded;
        }

        public static string Get(string key)
        {
            string url;
            return Load().TryGetValue(key, out url) ? url : null;
        }

        // Opens only allowed URLs in the default browser.
        public static bool Open(string url)
        {
            if (!IsAllowedUrl(url)) return false;
            try
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                return true;
            }
            catch { return false; }
        }
    }
}
