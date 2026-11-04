namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>What an instance's working directory says about its past.</summary>
public static class InstanceHistory
{
    /// <summary>
    /// Whether the instance has run: a native one leaves its log (or a rotated one), a container the
    /// lifecycle record its script appends to when it stops.
    /// </summary>
    public static bool HasRun(InstanceLayout layout) =>
        File.Exists(layout.LogFile)
        || File.Exists(Path.Combine(layout.EventsDirectory, "lifecycle.ndjson"))
        || (Directory.Exists(layout.LogsDirectory) && Directory.EnumerateFileSystemEntries(layout.LogsDirectory).Any());
}
