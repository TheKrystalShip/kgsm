using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;

namespace TheKrystalShip.KGSM.Engine.Contracts.Instances;

/// <summary>
/// An instance's configuration file: <c>&lt;working directory&gt;/&lt;id&gt;.config.json</c>, written by the
/// engine and read by the instance's management script with <c>jq</c>.
/// </summary>
/// <remarks>
/// Every key is present in a file the engine writes, so a key that is missing is a refusal and never a
/// silent default. Values are literal by construction. A path other than the backups directory is derived from the
/// registry and the file's own location and is never stored. A launch argument carries
/// <c>{key}</c> placeholders named by this type's camelCase keys, with <c>{{</c> and <c>}}</c> for
/// literal braces.
/// </remarks>
public sealed record InstanceConfig
{
    public required int SchemaVersion { get; init; }

    /// <summary>The instance id.</summary>
    public required string Name { get; init; }

    /// <summary>A label chosen by a person; empty reads as <see cref="Name"/>.</summary>
    public required string DisplayName { get; init; }

    /// <summary>The <c>name:</c> of the blueprint the instance was installed from.</summary>
    public required string Blueprint { get; init; }

    public required BlueprintRuntime Runtime { get; init; }

    public DateTimeOffset? InstallDatetime { get; init; }

    /// <summary>What tells this install apart from any other under the same name; never changes.</summary>
    public required string InstallNonce { get; init; }

    /// <summary>The one stored path: the backups directory, outside the working directory.</summary>
    public required string BackupsDirectory { get; init; }

    public required string Platform { get; init; }

    public required bool AutoUpdateBeforeStart { get; init; }

    /// <summary>The cgroup CPU weight class: <c>low</c>, <c>normal</c> or <c>high</c>.</summary>
    public required string CpuPriority { get; init; }

    /// <summary>The memory cap in MiB; zero is uncapped.</summary>
    public required int MemoryCapMb { get; init; }

    /// <summary>The packed maintenance windows (<c>reference/maintenance-windows.md</c>).</summary>
    public required string MaintenanceWindows { get; init; }

    public string? MaintenanceWindowsAuthor { get; init; }

    public string? MaintenanceWindowsAuthorName { get; init; }

    public required string Timezone { get; init; }

    public required int BackupRetention { get; init; }

    public required string AnnounceLeadMinutes { get; init; }

    public required string AnnounceMaintenanceMessage { get; init; }

    public required string AnnounceMaintenanceCancelledMessage { get; init; }

    public required bool CrashRestart { get; init; }

    public required int CrashMaxRestarts { get; init; }

    public required string StartupSuccessRegex { get; init; }

    public required string PlayerJoinedRegex { get; init; }

    public required string PlayerLeftRegex { get; init; }

    public int? RconPort { get; init; }

    public required string RconPassword { get; init; }

    public required int RconPollIntervalSeconds { get; init; }

    public required string RconPlayersCommand { get; init; }

    public required string RconPlayersRegex { get; init; }

    public required string LevelName { get; init; }

    public required string ExecutableFile { get; init; }

    public required string ExecutableSubdirectory { get; init; }

    /// <summary>The launch arguments with <c>{key}</c> placeholders.</summary>
    public required string ExecutableArguments { get; init; }

    public required long SteamAppId { get; init; }

    public required long ClientSteamAppId { get; init; }

    public required string SteamcmdArguments { get; init; }

    public required bool IsSteamAccountRequired { get; init; }

    /// <summary>Ports in UFW format, pipe-separated.</summary>
    public required string Ports { get; init; }

    public required bool EnableFirewallManagement { get; init; }

    public required bool EnablePortForwarding { get; init; }

    public required int DownloadTimeoutSeconds { get; init; }

    public required string StopCommand { get; init; }

    public required string SaveCommand { get; init; }

    public required int SaveCommandTimeoutSeconds { get; init; }

    public required int StopCommandTimeoutSeconds { get; init; }

    public required string KickCommand { get; init; }

    public required string BanCommand { get; init; }

    public required string UnbanCommand { get; init; }

    public required string BroadcastCommand { get; init; }

    public required bool CompressBackups { get; init; }

    /// <summary>The operator's free-text note about the server (mods, rules, a heads-up before joining); null when none is set.</summary>
    public string? Note { get; init; }

    /// <summary>Who wrote the note last, as <c>provider:name</c>, taken from the engine's actor; null with no note.</summary>
    public string? NoteUpdatedBy { get; init; }

    /// <summary>When the note was last written.</summary>
    public DateTimeOffset? NoteUpdatedAt { get; init; }

    /// <summary>What a display shows: the display name, or the id when none is set.</summary>
    public string Label => string.IsNullOrEmpty(DisplayName) ? Name : DisplayName;
}

/// <summary>The instance registry file, <c>instances.json</c> in the data home.</summary>
public sealed record InstanceRegistryFile
{
    public required int SchemaVersion { get; init; }

    /// <summary>Instances by id. An id is unique across the host.</summary>
    public required SortedDictionary<string, InstanceRegistryEntry> Instances { get; init; }
}

/// <summary>One registered instance.</summary>
public sealed record InstanceRegistryEntry
{
    /// <summary>The <c>name:</c> of the instance's blueprint.</summary>
    public required string Blueprint { get; init; }

    /// <summary>The id of the library the instance is placed in.</summary>
    public required string Library { get; init; }

    /// <summary>The instance's working directory, <c>&lt;library&gt;/instances/&lt;blueprint&gt;/&lt;id&gt;</c>.</summary>
    public required string WorkingDirectory { get; init; }
}
