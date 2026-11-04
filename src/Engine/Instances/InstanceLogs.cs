using System.Text;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>Reads the last lines of an instance's output without reading the whole file.</summary>
public static class InstanceLogs
{
    /// <summary>The last <paramref name="count"/> lines of a file, oldest first; none when the file is absent or <paramref name="count"/> is zero.</summary>
    public static IReadOnlyList<string> Tail(string file, int count)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        if (count == 0 || !File.Exists(file)) return [];

        try
        {
            using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, bufferSize: 1);
            long position = stream.Length;
            var chunks = new List<byte[]>();
            int newlines = 0;
            const int chunkSize = 16 * 1024;

            // Walk back one chunk at a time until the lines asked for (and the partial one before them)
            // are in hand.
            while (position > 0 && newlines <= count)
            {
                int take = (int)Math.Min(chunkSize, position);
                position -= take;
                stream.Seek(position, SeekOrigin.Begin);

                byte[] chunk = new byte[take];
                stream.ReadExactly(chunk);
                chunks.Add(chunk);
                newlines += chunk.Count(b => b == (byte)'\n');
            }

            chunks.Reverse();
            string text = Encoding.UTF8.GetString(chunks.SelectMany(c => c).ToArray());
            string[] lines = text.Split('\n');

            // A trailing newline ends the last line rather than starting an empty one; a read that stopped
            // mid-file starts on a partial line, which is not returned.
            int first = position > 0 ? 1 : 0;
            int last = lines.Length > 0 && lines[^1].Length == 0 ? lines.Length - 1 : lines.Length;
            IEnumerable<string> whole = lines.Skip(first).Take(Math.Max(0, last - first)).Select(l => l.TrimEnd('\r'));
            return [.. whole.TakeLast(count)];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    /// <summary>The live log's last lines; when there is no live log, the newest rotated one's; otherwise none.</summary>
    public static (string? File, IReadOnlyList<string> Lines) Recent(InstanceLayout layout, int count)
    {
        string? source = SourceFile(layout);
        return source is null ? (null, []) : (source, Tail(source, count));
    }

    /// <summary>The file the instance's output is read from: the live log, else the newest rotated log.</summary>
    public static string? SourceFile(InstanceLayout layout)
    {
        if (File.Exists(layout.LogFile)) return layout.LogFile;
        if (!Directory.Exists(layout.LogsDirectory)) return null;

        return new DirectoryInfo(layout.LogsDirectory)
            .EnumerateFiles($"{layout.Id}.*.log")
            .OrderByDescending(f => f.LastWriteTimeUtc)
            .ThenByDescending(f => f.Name, StringComparer.Ordinal)
            .Select(f => f.FullName)
            .FirstOrDefault();
    }
}
