using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;

namespace TheKrystalShip.KGSM.Engine.Backups;

/// <summary>
/// Reads backups from a backups directory. A backup is a directory <c>&lt;id&gt;/</c> holding
/// <c>manifest.json</c> and either <c>data.tar.gz</c> or <c>data/</c>. Archives are staged in a hidden
/// directory beside their final place and renamed into it, so a listing never shows a partial one.
/// </summary>
public static class BackupReader
{
    public const string ManifestFileName = "manifest.json";

    /// <summary>
    /// Lists the backups in <paramref name="backupsDirectory"/>, newest first. A directory without a
    /// readable manifest, with a manifest of a version this engine does not know, or whose manifest names
    /// another id is reported in <see cref="BackupListing.Skipped"/> and never dropped silently. An absent
    /// retention reads as prunable and an absent reason as null.
    /// </summary>
    public static BackupListing List(string backupsDirectory)
    {
        var backups = new List<Backup>();
        var skipped = new List<SkippedBackup>();

        if (Directory.Exists(backupsDirectory))
        {
            foreach (string directory in Directory.EnumerateDirectories(backupsDirectory))
            {
                string id = Path.GetFileName(directory);
                if (id.StartsWith('.')) continue;

                string manifestPath = Path.Combine(directory, ManifestFileName);

                if (!File.Exists(manifestPath))
                {
                    skipped.Add(new SkippedBackup(id, "no manifest"));
                    continue;
                }

                try
                {
                    BackupManifest manifest = ContractFile.Read(
                        manifestPath, EngineJsonContext.Default.BackupManifest, SchemaVersions.BackupManifest, m => m.SchemaVersion);

                    if (manifest.Id != id)
                        skipped.Add(new SkippedBackup(id, $"its manifest names '{manifest.Id}'"));
                    else
                        backups.Add(Resolve(manifest));
                }
                catch (EngineException ex)
                {
                    skipped.Add(new SkippedBackup(id, ex.Message));
                }
            }
        }

        return new BackupListing
        {
            Backups = backups.OrderByDescending(b => b.CreatedAt).ThenByDescending(b => b.Id, StringComparer.Ordinal).ToList(),
            Skipped = skipped.OrderBy(s => s.Directory, StringComparer.Ordinal).ToList(),
        };
    }

    /// <summary>One backup by id, or null when none is listed under it.</summary>
    public static Backup? Find(string backupsDirectory, string id) =>
        List(backupsDirectory).Backups.FirstOrDefault(b => b.Id == id);

    private static Backup Resolve(BackupManifest manifest) => new()
    {
        Id = manifest.Id,
        Instance = manifest.Instance,
        Blueprint = manifest.Blueprint,
        Version = manifest.Version,
        CreatedAt = manifest.CreatedAt,
        Reason = manifest.Reason,
        Retention = manifest.Retention ?? BackupRetention.Prunable,
        Compressed = manifest.Compressed,
        Consistency = manifest.Consistency,
        Sources = manifest.Sources,
        SizeBytes = manifest.SizeBytes,
        FileCount = manifest.FileCount,
        Sha256 = manifest.Sha256,
    };
}
