using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Looks after the engine's journal directory: what it holds, which whole segments are past the retention
/// window, and whether every line of every segment is one JSON object. A segment is appended to and deleted
/// whole, and nothing here rewrites one.
/// </summary>
public sealed partial class JournalMaintenance(string directory, int retentionDays, TimeProvider clock)
{
    public JournalStatusReport Status()
    {
        if (!Directory.Exists(directory))
        {
            return new JournalStatusReport
            {
                Directory = directory, RetentionDays = retentionDays, Exists = false, Writable = false,
                Segments = 0, Events = 0, SizeBytes = 0,
            };
        }

        string[] segments = Segments();
        long events = 0;
        long size = 0;
        foreach (string segment in segments)
        {
            byte[] bytes = File.ReadAllBytes(Path.Combine(directory, segment));
            size += bytes.Length;
            events += bytes.Count(b => b == (byte)'\n');
        }

        return new JournalStatusReport
        {
            Directory = directory,
            RetentionDays = retentionDays,
            Exists = true,
            Writable = new EventRecorder(new Journal.EventJournalWriter(new Journal.EventJournalOptions { Directory = directory }), directory, default).IsWritable(),
            Segments = segments.Length,
            Events = events,
            SizeBytes = size,
            Oldest = segments.FirstOrDefault(),
            Newest = segments.LastOrDefault(),
        };
    }

    /// <summary>
    /// Deletes the segments dated before the retention window. The age comes from the segment's name, never
    /// its modification time, which a restore or a copy changes without any event moving. A file whose name
    /// is not a date is left alone. Retention of zero or less keeps everything.
    /// </summary>
    public JournalPruneReport Prune()
    {
        if (retentionDays <= 0 || !Directory.Exists(directory))
            return new JournalPruneReport { Directory = directory, RetentionDays = retentionDays, Cutoff = null, Pruned = [] };

        string cutoff = clock.GetUtcNow().UtcDateTime.AddDays(-retentionDays).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var pruned = new List<string>();

        foreach (string segment in Segments())
        {
            string stem = segment[..^".ndjson".Length];
            if (!DatePattern().IsMatch(stem) || string.CompareOrdinal(stem, cutoff) >= 0) continue;

            File.Delete(Path.Combine(directory, segment));
            pruned.Add(segment);
        }

        return new JournalPruneReport { Directory = directory, RetentionDays = retentionDays, Cutoff = cutoff, Pruned = pruned };
    }

    /// <summary>
    /// Checks every line of every segment: it must be one JSON object. An empty line, a run of NUL bytes
    /// where a line was going to be, and a last line with no terminator (the torn write) are problems too.
    /// </summary>
    public JournalVerifyReport Verify()
    {
        var problems = new List<JournalProblem>();
        long lines = 0;
        string[] segments = Directory.Exists(directory) ? Segments() : [];

        foreach (string segment in segments)
        {
            byte[] bytes = File.ReadAllBytes(Path.Combine(directory, segment));
            int number = 0;
            int start = 0;

            while (start < bytes.Length)
            {
                int end = Array.IndexOf(bytes, (byte)'\n', start);
                bool terminated = end >= 0;
                if (!terminated) end = bytes.Length;

                number++;
                lines++;
                ReadOnlySpan<byte> line = bytes.AsSpan(start, end - start);

                if (line.Length == 0) problems.Add(new JournalProblem(segment, number, "empty line"));
                else if (line.Contains((byte)0)) problems.Add(new JournalProblem(segment, number, "holds NUL bytes, the hole a machine going down mid-append leaves"));
                else if (!IsJsonObject(line)) problems.Add(new JournalProblem(segment, number, "is not one JSON object"));

                if (!terminated) problems.Add(new JournalProblem(segment, number, "the last line has no terminator; it is a torn write"));
                start = end + 1;
            }
        }

        return new JournalVerifyReport { Directory = directory, Segments = segments.Length, Lines = lines, Problems = problems };
    }

    private string[] Segments() =>
        [.. Directory.EnumerateFiles(directory, "*.ndjson").Select(Path.GetFileName).OfType<string>().Order(StringComparer.Ordinal)];

    private static bool IsJsonObject(ReadOnlySpan<byte> line)
    {
        try
        {
            var reader = new Utf8JsonReader(line);
            if (!reader.Read() || reader.TokenType != JsonTokenType.StartObject) return false;

            reader.Skip();
            return !reader.Read();
        }
        catch (JsonException)
        {
            return false;
        }
    }

    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2}$")]
    private static partial Regex DatePattern();
}
