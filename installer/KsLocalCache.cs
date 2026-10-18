using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace LotmRussianPatcher
{
    // Saved/kscache/local.cache: the launcher's index of live chunks in the cache files (TASK-038).
    // Records without a header, back to back up to the end of the file:
    //   [16 bytes key][int64 offset][int32 path length incl. NUL][path UTF-8 + NUL]
    // e.g. "2218968/pakchunk0-Windows.pak". The launcher appends a re-downloaded pak to the old file without
    // truncating it, so the pak may hold dead copies of the launch block; only ranges listed here are live.
    // The format was derived from one file: any deviation means "unknown format" (null), never a partial list.
    public static class KsLocalCache
    {
        public const string FileName = "local.cache";
        private const int MinPath = 2, MaxPath = 512;

        // Sorted chunk start offsets of relPath ("<ver>/<pak name>"), an empty list when the index has no such file,
        // null when the file is missing or does not parse exactly to its end.
        public static List<long> ChunkStarts(string localCachePath, string relPath)
        {
            if (!File.Exists(localCachePath)) return null;
            byte[] data;
            using (var fs = new FileStream(localCachePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (fs.Length > 256L << 20) return null;   // ~10 MB in practice
                data = new byte[fs.Length];
                int read = 0;
                while (read < data.Length)
                {
                    int n = fs.Read(data, read, data.Length - read);
                    if (n <= 0) return null;
                    read += n;
                }
            }
            byte[] want = Encoding.UTF8.GetBytes(relPath.Replace('\\', '/'));
            var starts = new List<long>();
            long p = 0;
            while (p < data.Length)
            {
                if (p + 28 > data.Length) return null;
                long offset = BitConverter.ToInt64(data, (int)p + 16);
                int len = BitConverter.ToInt32(data, (int)p + 24);
                if (len < MinPath || len > MaxPath || offset < 0) return null;
                long pathAt = p + 28;
                if (pathAt + len > data.Length || data[pathAt + len - 1] != 0) return null;
                if (len - 1 == want.Length && SamePath(data, (int)pathAt, want)) starts.Add(offset);
                p = pathAt + len;
            }
            if (p != data.Length) return null;
            starts.Sort();
            return starts;
        }

        // A block [at, at + size) is live when it lies inside one chunk: from a start s <= at to the next start
        // (the last chunk runs to the end of the pak).
        public static bool IsLive(List<long> starts, long at, long size, long pakLength)
        {
            if (starts == null || starts.Count == 0) return false;
            int i = starts.BinarySearch(at);
            if (i < 0) i = ~i - 1;
            if (i < 0) return false;
            // Several records may share a start; take the next greater one as the end.
            int j = i + 1;
            while (j < starts.Count && starts[j] == starts[i]) j++;
            long end = j < starts.Count ? starts[j] : pakLength;
            return at + size <= end;
        }

        // ASCII case-insensitive: the launcher writes the names as the pak names (pakchunk0-Windows.pak).
        private static bool SamePath(byte[] data, int at, byte[] want)
        {
            for (int i = 0; i < want.Length; i++)
            {
                byte a = data[at + i], b = want[i];
                if (a == b) continue;
                if (a >= 'A' && a <= 'Z') a = (byte)(a + 32);
                if (b >= 'A' && b <= 'Z') b = (byte)(b + 32);
                if (a != b) return false;
            }
            return true;
        }
    }
}
