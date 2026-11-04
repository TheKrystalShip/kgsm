using System.Text.Json.Serialization;

namespace TheKrystalShip.KGSM.Engine.Contracts.Backups;

/// <summary>Why a backup was taken.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<BackupReason>))]
public enum BackupReason
{
    [JsonStringEnumMemberName("manual")]
    Manual = 0,

    [JsonStringEnumMemberName("scheduled")]
    Scheduled = 1,

    [JsonStringEnumMemberName("pre-update")]
    PreUpdate = 2,

    [JsonStringEnumMemberName("pre-restore")]
    PreRestore = 3,

    [JsonStringEnumMemberName("incident")]
    Incident = 4,
}

/// <summary>Whether a prune may delete a backup.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<BackupRetention>))]
public enum BackupRetention
{
    [JsonStringEnumMemberName("prunable")]
    Prunable = 0,

    [JsonStringEnumMemberName("pinned")]
    Pinned = 1,
}

/// <summary>How consistent the captured data is, as measured when it was taken.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<BackupConsistency>))]
public enum BackupConsistency
{
    /// <summary>The instance was stopped.</summary>
    [JsonStringEnumMemberName("cold")]
    Cold = 0,

    /// <summary>The instance ran and its save command succeeded.</summary>
    [JsonStringEnumMemberName("flushed")]
    Flushed = 1,

    /// <summary>The instance ran with no usable save.</summary>
    [JsonStringEnumMemberName("hot")]
    Hot = 2,
}

/// <summary>
/// A backup's <c>manifest.json</c>. The directory <c>&lt;backups&gt;/&lt;id&gt;/</c> holds it beside
/// <c>data.tar.gz</c> or <c>data/</c>.
/// </summary>
public sealed record BackupManifest
{
    public required int SchemaVersion { get; init; }

    /// <summary><c>&lt;instance&gt;-&lt;YYYYMMDDTHHMMSSZ&gt;-&lt;6 hex&gt;</c>.</summary>
    public required string Id { get; init; }

    public string? Instance { get; init; }

    public string? Blueprint { get; init; }

    public string? Version { get; init; }

    public required DateTimeOffset CreatedAt { get; init; }

    /// <summary>Null when the manifest names none.</summary>
    public BackupReason? Reason { get; init; }

    /// <summary>An absent value reads as <see cref="BackupRetention.Prunable"/>.</summary>
    public BackupRetention? Retention { get; init; }

    public required bool Compressed { get; init; }

    /// <summary>Null when unknown.</summary>
    public BackupConsistency? Consistency { get; init; }

    /// <summary>The subtrees captured: <c>install</c> and <c>saves</c>, each only when non-empty.</summary>
    public required IReadOnlyList<string> Sources { get; init; }

    public required long SizeBytes { get; init; }

    public required long FileCount { get; init; }

    /// <summary>Null for an uncompressed backup.</summary>
    public string? Sha256 { get; init; }
}

/// <summary>A backup as a listing reports it: the manifest, with retention resolved.</summary>
public sealed record Backup
{
    public required string Id { get; init; }

    public string? Instance { get; init; }

    public string? Blueprint { get; init; }

    public string? Version { get; init; }

    public required DateTimeOffset CreatedAt { get; init; }

    public BackupReason? Reason { get; init; }

    public required BackupRetention Retention { get; init; }

    public required bool Compressed { get; init; }

    public BackupConsistency? Consistency { get; init; }

    public required IReadOnlyList<string> Sources { get; init; }

    public required long SizeBytes { get; init; }

    public required long FileCount { get; init; }

    public string? Sha256 { get; init; }

    [JsonIgnore]
    public bool IsPinned => Retention == BackupRetention.Pinned;
}

/// <summary>A directory in a backups root that holds no readable manifest, and why.</summary>
public sealed record SkippedBackup(string Directory, string Reason);

/// <summary>An instance's backups, newest first, with the directories that could not be read.</summary>
public sealed record BackupListing
{
    public required IReadOnlyList<Backup> Backups { get; init; }

    public required IReadOnlyList<SkippedBackup> Skipped { get; init; }
}
