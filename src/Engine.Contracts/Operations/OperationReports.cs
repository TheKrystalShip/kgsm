using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;

namespace TheKrystalShip.KGSM.Engine.Contracts.Operations;

/// <summary>What an install made.</summary>
public sealed record InstallReport
{
    public required string Id { get; init; }

    public required string Blueprint { get; init; }

    public required string Library { get; init; }

    public required string WorkingDirectory { get; init; }

    /// <summary>The version the install recorded; null when the game has no version to name.</summary>
    public string? Version { get; init; }

    /// <summary>The start that followed, when one was asked for.</summary>
    public LifecycleReport? Start { get; init; }
}

/// <summary>How a start, stop or restart was carried out, and what it found.</summary>
public sealed record LifecycleReport
{
    public required string Id { get; init; }

    /// <summary><c>start</c>, <c>stop</c> or <c>restart</c>.</summary>
    public required string Action { get; init; }

    /// <summary>The measured run state after the action.</summary>
    public required RunState State { get; init; }

    /// <summary>Whether the run state moved: false when the instance was already as asked.</summary>
    public required bool Changed { get; init; }

    /// <summary><c>watchdog</c> when the watchdog carried the action out, <c>script</c> when the instance's own management script did.</summary>
    public required string Via { get; init; }

    /// <summary>Whether the watchdog supervises the instance after the action. A start through the script is unsupervised.</summary>
    public required bool Supervised { get; init; }

    public string? Message { get; init; }
}

/// <summary>What an uninstall removed.</summary>
public sealed record UninstallReport
{
    public required string Id { get; init; }

    /// <summary>Whether a running instance was stopped first.</summary>
    public required bool Stopped { get; init; }

    /// <summary>Whether the working directory was deleted; false for an instance whose library is offline, which is only deregistered.</summary>
    public required bool FilesRemoved { get; init; }

    public required bool BackupsRemoved { get; init; }
}

/// <summary>What an update did.</summary>
public sealed record UpdateReport
{
    public required string Id { get; init; }

    /// <summary><c>updated</c> or <c>current</c>.</summary>
    public required string Outcome { get; init; }

    public string? PreviousVersion { get; init; }

    public string? Version { get; init; }

    /// <summary>The backup taken before the update; null when none was needed.</summary>
    public string? Backup { get; init; }
}

/// <summary>What an update check found.</summary>
public sealed record UpdateCheckReport
{
    public required string Id { get; init; }

    /// <summary><c>available</c>, <c>current</c> or <c>unknown</c>.</summary>
    public required string Outcome { get; init; }

    public string? Current { get; init; }

    public string? Latest { get; init; }

    /// <summary>Whether this check wrote <c>server.update.available</c>.</summary>
    public required bool Announced { get; init; }
}

/// <summary>An instance moved between libraries.</summary>
public sealed record MoveReport
{
    public required string Id { get; init; }

    public required string FromLibrary { get; init; }

    public required string ToLibrary { get; init; }

    public required string WorkingDirectory { get; init; }

    /// <summary><c>rename</c> when both libraries are on one mount, <c>copy</c> otherwise.</summary>
    public required string Method { get; init; }
}

/// <summary>A config key set.</summary>
public sealed record ConfigSetReport
{
    public required string Instance { get; init; }

    public required string Key { get; init; }

    public string? Value { get; init; }

    /// <summary>False when the key already held that value.</summary>
    public required bool Changed { get; init; }
}

/// <summary>An action that has a sentence for a result: a console line sent, a backup pinned.</summary>
public sealed record ActionReport
{
    public required string Action { get; init; }

    public required string Subject { get; init; }

    public required string Message { get; init; }
}

/// <summary>A backup created.</summary>
public sealed record BackupCreateReport
{
    public required Backup Backup { get; init; }
}

/// <summary>A backup restored.</summary>
public sealed record BackupRestoreReport
{
    public required string Restored { get; init; }

    /// <summary>The backup taken of the current data first; null when the data was empty.</summary>
    public string? SafetyBackup { get; init; }
}

/// <summary>What a prune kept and deleted.</summary>
public sealed record BackupPruneReport
{
    public required IReadOnlyList<string> Deleted { get; init; }

    public required int Kept { get; init; }

    public required int Pinned { get; init; }
}

/// <summary>A blueprint file written or removed.</summary>
public sealed record BlueprintWriteReport
{
    public required string Name { get; init; }

    public required string Path { get; init; }

    public required BlueprintTier Tier { get; init; }

    /// <summary>For a write: whether the file shadows a system blueprint. For a delete: whether a system blueprint is visible again.</summary>
    public required bool SystemBlueprintInvolved { get; init; }
}

/// <summary>A library registered, renamed or deregistered.</summary>
public sealed record LibraryChangeReport
{
    public required string Name { get; init; }

    public required string Id { get; init; }

    public required string Path { get; init; }

    /// <summary>The instances moved out or left unregistered by a removal.</summary>
    public IReadOnlyList<string> Instances { get; init; } = [];
}

/// <summary>An event written by <c>kgsm event emit</c>.</summary>
public sealed record EmitReport
{
    public required string EventType { get; init; }

    public required string Subject { get; init; }
}

/// <summary>Where the journal is and what it holds.</summary>
public sealed record JournalStatusReport
{
    public required string Directory { get; init; }

    public required int RetentionDays { get; init; }

    public required bool Exists { get; init; }

    public required bool Writable { get; init; }

    public required int Segments { get; init; }

    public required long Events { get; init; }

    public required long SizeBytes { get; init; }

    public string? Oldest { get; init; }

    public string? Newest { get; init; }
}

/// <summary>The segments a prune deleted.</summary>
public sealed record JournalPruneReport
{
    public required string Directory { get; init; }

    public required int RetentionDays { get; init; }

    /// <summary>The oldest day kept, as <c>YYYY-MM-DD</c>; null when retention is off.</summary>
    public string? Cutoff { get; init; }

    public required IReadOnlyList<string> Pruned { get; init; }
}

/// <summary>One line of a segment that is not a well-formed event.</summary>
public sealed record JournalProblem(string Segment, int Line, string Problem);

/// <summary>Whether every segment is well-formed.</summary>
public sealed record JournalVerifyReport
{
    public required string Directory { get; init; }

    public required int Segments { get; init; }

    public required long Lines { get; init; }

    public required IReadOnlyList<JournalProblem> Problems { get; init; }

    [JsonIgnore]
    public bool WellFormed => Problems.Count == 0;
}
