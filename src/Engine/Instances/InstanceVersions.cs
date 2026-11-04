using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>
/// Reads an instance's installed version and the record of its last update check. The record is two lines,
/// the latest version and the time it was fetched; without one nothing has been checked, and an update is
/// neither available nor ruled out.
/// </summary>
public static class InstanceVersions
{
    public static InstanceVersion Read(InstanceLayout layout)
    {
        string? current = FirstLine(layout.VersionFile);
        string[] latestRecord = Lines(layout.LatestVersionFile);
        string? latest = latestRecord.Length > 0 && latestRecord[0].Length > 0 ? latestRecord[0] : null;

        DateTimeOffset? checkedAt = latestRecord.Length > 1
            && DateTimeOffset.TryParse(latestRecord[1], CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out DateTimeOffset at)
            ? at
            : null;

        return new InstanceVersion
        {
            Current = current,
            Latest = latest,
            Checked = latest is not null,
            UpdatesAvailable = latest is null || current is null ? null : !string.Equals(latest, current, StringComparison.Ordinal),
            CheckedAt = checkedAt,
        };
    }

    private static string? FirstLine(string file) => Lines(file) is { Length: > 0 } lines && lines[0].Length > 0 ? lines[0] : null;

    private static string[] Lines(string file)
    {
        try
        {
            return File.Exists(file)
                ? [.. File.ReadAllLines(file).Select(l => l.Trim())]
                : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }
}
