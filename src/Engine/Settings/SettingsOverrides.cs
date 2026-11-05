using System.Text.Json.Serialization;

namespace TheKrystalShip.KGSM.Engine.Settings;

/// <summary>
/// The person's settings file: the same sections as <see cref="EngineSettings"/> with every value optional, so the
/// file holds only what the person set. Property names are the file's, PascalCase as the settings file spells them.
/// </summary>
internal sealed class SettingsOverrides
{
    public LibrariesOverrides? Libraries { get; set; }

    public InstancesOverrides? Instances { get; set; }

    public BackupsOverrides? Backups { get; set; }

    public JournalOverrides? Journal { get; set; }

    public CgroupOverrides? Cgroup { get; set; }

    public WatchdogOverrides? Watchdog { get; set; }

    public FirewallOverrides? Firewall { get; set; }

    public DownloadsOverrides? Downloads { get; set; }

    public LoggingOverrides? Logging { get; set; }
}

internal sealed class LibrariesOverrides
{
    public string? DefaultLibrary { get; set; }

    public int? InstallFreeSpaceMarginMb { get; set; }
}

internal sealed class InstancesOverrides
{
    public int? IdSuffixLength { get; set; }

    public int? SaveCommandTimeoutSeconds { get; set; }

    public int? StopCommandTimeoutSeconds { get; set; }

    public bool? AutoUpdateBeforeStart { get; set; }

    public string? MaintenanceWindows { get; set; }

    public string? AnnounceLeadMinutes { get; set; }

    public string? AnnounceMaintenanceMessage { get; set; }

    public string? AnnounceMaintenanceCancelledMessage { get; set; }

    public bool? EnableFirewallManagement { get; set; }

    public bool? EnablePortForwarding { get; set; }
}

internal sealed class BackupsOverrides
{
    public string? Directory { get; set; }

    public bool? Compress { get; set; }
}

internal sealed class JournalOverrides
{
    public string? Directory { get; set; }

    public int? RetentionDays { get; set; }
}

internal sealed class CgroupOverrides
{
    public string? MountPoint { get; set; }

    public string? BaseName { get; set; }
}

internal sealed class WatchdogOverrides
{
    public string? Socket { get; set; }

    public bool? Enabled { get; set; }
}

internal sealed class FirewallOverrides
{
    public string? Client { get; set; }

    public string? Socket { get; set; }
}

internal sealed class DownloadsOverrides
{
    public int? TimeoutSeconds { get; set; }
}

internal sealed class LoggingOverrides
{
    public LogLevelOverrides? LogLevel { get; set; }

    public FileLogOverrides? File { get; set; }
}

internal sealed class LogLevelOverrides
{
    public string? Default { get; set; }
}

internal sealed class FileLogOverrides
{
    public int? MaxSizeKb { get; set; }

    public int? MaxFiles { get; set; }
}

[JsonSourceGenerationOptions(WriteIndented = true, DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(SettingsOverrides))]
internal sealed partial class SettingsFileJsonContext : JsonSerializerContext;
