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
    // The key identifies a chunk: an incremental hotpatch keeps the record of an unchanged chunk in the older
    // <ver> folder, and CPDD cache_launch.entry_id is the key prefix of the launch block record (TASK-039).
    // The format was derived from one file: any deviation means "unknown format" (null), never a partial list.
    public static class KsLocalCache
    {
        public const string FileName = "local.cache";
        public const int KeySize = 16;
        private const int MinPath = 2, MaxPath = 512;

        public class Entry
        {
            public byte[] Key;
            public long Offset;
            public string RelPath;   // "<ver>/<file name>", '/'-separated as the launcher writes it
        }

        // Every record of the file, null when the file is missing or does not parse exactly to its end.
        public static List<Entry> Load(string localCachePath)
        {
            if (!File.Exists(localCachePath)) return null;
            byte[] data;
            using (var fs = new FileStream(localCachePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (fs.Length > 256L << 20) return null;   // ~12 MB in practice
                data = new byte[fs.Length];
                int read = 0;
                while (read < data.Length)
                {
                    int n = fs.Read(data, read, data.Length - read);
                    if (n <= 0) return null;
                    read += n;
                }
            }
            var entries = new List<Entry>();
            long p = 0;
            while (p < data.Length)
            {
                if (p + KeySize + 12 > data.Length) return null;
                long offset = BitConverter.ToInt64(data, (int)p + KeySize);
                int len = BitConverter.ToInt32(data, (int)p + KeySize + 8);
                if (len < MinPath || len > MaxPath || offset < 0) return null;
                long pathAt = p + KeySize + 12;
                if (pathAt + len > data.Length || data[pathAt + len - 1] != 0) return null;
                var key = new byte[KeySize];
                Buffer.BlockCopy(data, (int)p, key, 0, KeySize);
                entries.Add(new Entry { Key = key, Offset = offset, RelPath = Encoding.UTF8.GetString(data, (int)pathAt, len - 1) });
                p = pathAt + len;
            }
            return p == data.Length ? entries : null;
        }

        // Sorted chunk start offsets of relPath ("<ver>/<pak name>"), an empty list when the index has no such file,
        // null when the file is missing or does not parse exactly to its end.
        public static List<long> ChunkStarts(string localCachePath, string relPath)
        {
            return ChunkStarts(Load(localCachePath), relPath);
        }

        public static List<long> ChunkStarts(List<Entry> entries, string relPath)
        {
            if (entries == null) return null;
            string want = relPath.Replace('\\', '/');
            var starts = new List<long>();
            // Case-insensitive: the launcher writes the names as the pak names (pakchunk0-Windows.pak).
            foreach (Entry e in entries) if (string.Equals(e.RelPath, want, StringComparison.OrdinalIgnoreCase)) starts.Add(e.Offset);
            starts.Sort();
            return starts;
        }

        // Records whose key starts with keyPrefix (CPDD entry_id, up to 16 bytes); null when the file is not read.
        public static List<Entry> FindByKeyPrefix(string localCachePath, byte[] keyPrefix)
        {
            return FindByKeyPrefix(Load(localCachePath), keyPrefix);
        }

        public static List<Entry> FindByKeyPrefix(List<Entry> entries, byte[] keyPrefix)
        {
            if (entries == null) return null;
            if (keyPrefix == null || keyPrefix.Length == 0 || keyPrefix.Length > KeySize) throw new ArgumentException("keyPrefix");
            var found = new List<Entry>();
            foreach (Entry e in entries)
            {
                int i = 0;
                while (i < keyPrefix.Length && e.Key[i] == keyPrefix[i]) i++;
                if (i == keyPrefix.Length) found.Add(e);
            }
            return found;
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
    }
}
