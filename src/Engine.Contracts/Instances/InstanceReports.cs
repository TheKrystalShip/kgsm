using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Network;

namespace TheKrystalShip.KGSM.Engine.Contracts.Instances;

/// <summary>One line of <c>kgsm instance list</c>. A figure the engine could not read is null.</summary>
public sealed record InstanceSummary
{
    public required string Id { get; init; }

    /// <summary>What a display shows: the display name, or the id when none is set; the id when the config cannot be read.</summary>
    public required string Label { get; init; }

    public required string Blueprint { get; init; }

    /// <summary>Null when the config could not be read.</summary>
    public BlueprintRuntime? Runtime { get; init; }

    /// <summary>The library's name; null when the instance lies under no registered library.</summary>
    public string? Library { get; init; }

    public required InstanceLibraryState LibraryState { get; init; }

    /// <summary>Why the config could not be read; null when it could.</summary>
    public string? ConfigProblem { get; init; }
}

/// <summary>The library an instance lies in.</summary>
public sealed record InstanceLibraryRef(string Name, string Id, string Path);

/// <summary>Every path inside an instance's working directory, derived from the registry and never stored.</summary>
public sealed record InstancePaths
{
    public required string WorkingDirectory { get; init; }

    public required string ConfigFile { get; init; }

    public required string ManagementScript { get; init; }

    public required string InstallDirectory { get; init; }

    public required string SavesDirectory { get; init; }

    public required string LogsDirectory { get; init; }

    public required string TempDirectory { get; init; }

    public required string EventsDirectory { get; init; }

    public required string LaunchDirectory { get; init; }

    public required string VersionFile { get; init; }

    public required string LatestVersionFile { get; init; }

    public required string PidFile { get; init; }

    public required string InputFifo { get; init; }

    public required string LogFile { get; init; }

    public required string ComposeFile { get; init; }

    /// <summary>Null when the config could not be read, because the backups directory is the config's.</summary>
    public string? BackupsDirectory { get; init; }
}

/// <summary>An instance as <c>kgsm instance show</c> reports it: its registry entry, library, derived paths, ports and config.</summary>
public sealed record InstanceInfo
{
    public required string Id { get; init; }

    public required string Label { get; init; }

    public required string Blueprint { get; init; }

    public BlueprintRuntime? Runtime { get; init; }

    /// <summary>Null when the instance lies under no registered library.</summary>
    public InstanceLibraryRef? Library { get; init; }

    public required InstanceLibraryState LibraryState { get; init; }

    public required InstancePaths Paths { get; init; }

    /// <summary>The instance's cgroup below the cgroup mount point, which kgsm-monitor reads.</summary>
    public required string CgroupPath { get; init; }

    public required IReadOnlyList<PortRange> Ports { get; init; }

    /// <summary>Null when the config could not be read; <see cref="ConfigProblem"/> says why.</summary>
    public InstanceConfig? Config { get; init; }

    public string? ConfigProblem { get; init; }
}

/// <summary>A measured run state. Unknown is a state of its own and is never read as stopped.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<RunState>))]
public enum RunState
{
    [JsonStringEnumMemberName("running")]
    Running = 0,

    [JsonStringEnumMemberName("stopped")]
    Stopped = 1,

    [JsonStringEnumMemberName("unknown")]
    Unknown = 2,
}

/// <summary>Who answered for an instance's run state.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<RunStateSource>))]
public enum RunStateSource
{
    /// <summary>The watchdog's control socket.</summary>
    [JsonStringEnumMemberName("watchdog")]
    Watchdog = 0,

    /// <summary>The pid file the management script writes, for an instance started without the watchdog.</summary>
    [JsonStringEnumMemberName("pid-file")]
    PidFile = 1,

    /// <summary>The container runtime, through <c>docker compose ps</c>.</summary>
    [JsonStringEnumMemberName("compose")]
    Compose = 2,

    /// <summary>Nothing could be asked, so nothing is claimed.</summary>
    [JsonStringEnumMemberName("none")]
    None = 3,
}

/// <summary>An instance's run state and the process behind it.</summary>
public sealed record InstanceProcess
{
    public required RunState State { get; init; }

    public required RunStateSource Source { get; init; }

    public int? Pid { get; init; }

    /// <summary>When the current run was spawned; null when nothing is running or the watchdog adopted a run it did not spawn.</summary>
    public DateTimeOffset? StartTime { get; init; }

    /// <summary>The watchdog's supervision phase (<c>running</c>, <c>restart-pending</c>, <c>stopped</c>, <c>failed</c>, <c>maintenance</c>); null when it did not answer for this instance.</summary>
    public string? Phase { get; init; }

    /// <summary>Why the state is what it is when that needs saying: an unreachable daemon, an untracked instance.</summary>
    public string? Detail { get; init; }
}

/// <summary>The installed version and what the last update check found.</summary>
public sealed record InstanceVersion
{
    /// <summary>The installed version; null when no version file exists.</summary>
    public string? Current { get; init; }

    /// <summary>The latest version the last check found; null when no check is on record.</summary>
    public string? Latest { get; init; }

    /// <summary>Whether a check is on record. Without one, <see cref="UpdatesAvailable"/> is unknown.</summary>
    public required bool Checked { get; init; }

    /// <summary>Whether the latest version differs from the installed one; null when no check is on record.</summary>
    public bool? UpdatesAvailable { get; init; }

    public DateTimeOffset? CheckedAt { get; init; }
}

/// <summary>What was configured for an instance.</summary>
public sealed record InstanceConfiguration
{
    public required string Blueprint { get; init; }

    public BlueprintRuntime? Runtime { get; init; }

    public required string Directory { get; init; }

    public required IReadOnlyList<PortRange> Ports { get; init; }
}

/// <summary>An instance's status: one typed document.</summary>
public sealed record InstanceStatus
{
    public required string Id { get; init; }

    public required InstanceProcess Process { get; init; }

    public required InstanceVersion Version { get; init; }

    public required InstanceConfiguration Configuration { get; init; }

    public required InstanceLibraryState LibraryState { get; init; }

    /// <summary>Bytes the working directory holds; null unless measured (<c>--disk</c>) or when the library is offline.</summary>
    public long? DiskUsageBytes { get; init; }

    /// <summary>Backup ids, newest first.</summary>
    public required IReadOnlyList<string> Backups { get; init; }

    /// <summary>The last lines of the live log, else the newest rotated log, else none.</summary>
    public required IReadOnlyList<string> RecentLogs { get; init; }
}

/// <summary>Lines of an instance's output.</summary>
public sealed record LogTail
{
    public required string Instance { get; init; }

    /// <summary>The file the lines came from; null for a container, whose output the runtime holds.</summary>
    public string? File { get; init; }

    public required IReadOnlyList<string> Lines { get; init; }
}

/// <summary>One instance config key: its type, its value rendered as text, and whether <c>config set</c> may change it.</summary>
public sealed record ConfigEntry
{
    public required string Key { get; init; }

    /// <summary><c>string</c>, <c>int</c>, <c>bool</c> or <c>datetime</c>.</summary>
    public required string Type { get; init; }

    /// <summary>The value as text; null when the key is unset.</summary>
    public string? Value { get; init; }

    public required bool Settable { get; init; }
}
