using TheKrystalShip.KGSM.ComponentConfig;

namespace TheKrystalShip.KGSM.Engine.Settings;

/// <summary>
/// The engine's configurable surface, shaped 1:1 with <c>kgsm.settings.json</c>. The file beside the
/// binary declares every key with its default and is the lowest-precedence source; a person's overrides
/// are <c>kgsm/kgsm.settings.json</c> in the config home; the environment (<c>Section__Key</c>) overrides
/// one key of either. The settings hold no secret: Steam credentials live in <c>/etc/kgsm/kgsm.env</c>.
/// </summary>
public sealed class EngineSettings
{
    public LibrariesSettings Libraries { get; set; } = new();

    public InstancesSettings Instances { get; set; } = new();

    public BackupsSettings Backups { get; set; } = new();

    public JournalSettings Journal { get; set; } = new();

    public CgroupSettings Cgroup { get; set; } = new();

    public WatchdogSettings Watchdog { get; set; } = new();

    public FirewallSettings Firewall { get; set; } = new();

    public DownloadsSettings Downloads { get; set; } = new();

    public LoggingSettings Logging { get; set; } = new();
}

/// <summary>Where instances are placed.</summary>
[ConfigSection(Section)]
public sealed class LibrariesSettings
{
    public const string Section = "Libraries";

    /// <summary>The library an install uses when none is named. Empty means the only registered library.</summary>
    /// <panel>The library a new instance is placed in when the install names none. Empty uses the only
    /// registered library, and an install is refused when several exist and none is chosen.</panel>
    [ConfigField("defaultLibrary", "Default library", Group = "libraries")]
    public string DefaultLibrary { get; set; } = string.Empty;

    /// <summary>Room an install requires beyond the blueprint's declared base disk figure.</summary>
    /// <panel>Free space an install requires beyond the game's declared disk footprint before it
    /// proceeds.</panel>
    [ConfigField("installFreeSpaceMarginMb", "Install free-space margin", Group = "libraries",
        Min = Floors.Zero, Unit = "MB")]
    public int InstallFreeSpaceMarginMb { get; set; } = 1024;

    public static class Floors
    {
        public const int Zero = 0;
    }
}

/// <summary>Instance identity and the defaults copied into a new instance.</summary>
[ConfigSection(Section)]
public sealed class InstancesSettings
{
    public const string Section = "Instances";

    /// <summary>Length of the random suffix a generated instance id ends in.</summary>
    /// <panel>How many characters the random suffix of a generated instance id has.</panel>
    [ConfigField("idSuffixLength", "Instance id suffix length", Group = "instances",
        Min = Floors.IdSuffixLength, Max = Floors.MaxIdSuffixLength)]
    public int IdSuffixLength { get; set; } = 2;

    /// <summary>Seconds to wait after sending the save command.</summary>
    /// <panel>How long a backup or stop waits after sending a game its save command. Copied into a new
    /// instance.</panel>
    [ConfigField("saveCommandTimeoutSeconds", "Save command timeout", Group = "instances",
        Min = Floors.Zero, Unit = "s")]
    public int SaveCommandTimeoutSeconds { get; set; } = 5;

    /// <summary>Seconds to wait after sending the stop command before escalating.</summary>
    /// <panel>How long a stop waits for the game to exit after its stop command before it escalates.
    /// Copied into a new instance.</panel>
    [ConfigField("stopCommandTimeoutSeconds", "Stop command timeout", Group = "instances",
        Min = Floors.Zero, Unit = "s")]
    public int StopCommandTimeoutSeconds { get; set; } = 30;

    /// <summary>Whether a start first updates the game.</summary>
    /// <panel>Whether a new instance checks for and applies a game update every time it starts.</panel>
    [ConfigField("autoUpdateBeforeStart", "Update before start", Group = "instances")]
    public bool AutoUpdateBeforeStart { get; set; }

    /// <summary>The packed maintenance windows copied into a new instance.</summary>
    /// <panel>Maintenance windows a new instance starts with, written schedule then tasks, for example
    /// daily@05:00/backup. Empty means no maintenance.</panel>
    [ConfigField("maintenanceWindows", "Maintenance windows", Group = "instances")]
    public string MaintenanceWindows { get; set; } = string.Empty;

    /// <summary>Lead times in minutes before a disruptive window, comma-separated.</summary>
    /// <panel>Minutes before a disruptive maintenance window at which a new instance tells its players,
    /// for example 15,5,1. Empty announces nothing.</panel>
    [ConfigField("announceLeadMinutes", "Announcement lead times", Group = "instances")]
    public string AnnounceLeadMinutes { get; set; } = string.Empty;

    /// <summary>What each lead-time announcement says. Carries {minutes}, {reason} and {instance}.</summary>
    /// <panel>What each lead-time announcement says. The words {minutes}, {reason} and {instance} are
    /// replaced.</panel>
    [ConfigField("announceMaintenanceMessage", "Announcement message", Group = "instances")]
    public string AnnounceMaintenanceMessage { get; set; } = "Server restart in {minutes} min";

    /// <summary>What is said when an announced window is abandoned.</summary>
    /// <panel>What players are told when an announced maintenance window is abandoned.</panel>
    [ConfigField("announceMaintenanceCancelledMessage", "Cancellation message", Group = "instances")]
    public string AnnounceMaintenanceCancelledMessage { get; set; } = "Server restart cancelled";

    /// <summary>Whether a new instance's firewall rules are managed by the engine.</summary>
    /// <panel>Whether a new instance has its host firewall rules opened and closed with it.</panel>
    [ConfigField("enableFirewallManagement", "Manage firewall", Group = "instances")]
    public bool EnableFirewallManagement { get; set; }

    /// <summary>Whether a new instance's ports are forwarded on the router.</summary>
    /// <panel>Whether a new instance has its ports forwarded on the router while it runs.</panel>
    [ConfigField("enablePortForwarding", "Forward ports", Group = "instances")]
    public bool EnablePortForwarding { get; set; }

    public static class Floors
    {
        public const int Zero = 0;

        public const int IdSuffixLength = 1;

        public const int MaxIdSuffixLength = 16;
    }
}

/// <summary>Where and how backups are kept.</summary>
[ConfigSection(Section)]
public sealed class BackupsSettings
{
    public const string Section = "Backups";

    /// <summary>The backups root. Empty means the data home's <c>backups/</c>.</summary>
    /// <panel>Directory every instance's backups are kept under. Empty uses the engine's data directory.
    /// Existing instances keep the directory they were installed with.</panel>
    [ConfigField("backupsDirectory", "Backups directory", Group = "backups", Type = ConfigType.Path,
        Risk = ConfigRisk.Wiring)]
    public string Directory { get; set; } = string.Empty;

    /// <summary>Whether a new backup is a compressed archive.</summary>
    /// <panel>Whether new backups are compressed archives rather than plain copies.</panel>
    [ConfigField("compressBackups", "Compress backups", Group = "backups")]
    public bool Compress { get; set; } = true;
}

/// <summary>The engine's event journal.</summary>
[ConfigSection(Section)]
public sealed class JournalSettings
{
    public const string Section = "Journal";

    /// <summary>The directory the daily segments are appended to.</summary>
    /// <panel>Directory the engine's event journal is written to. Readers find the journal here.</panel>
    [ConfigField("journalDirectory", "Journal directory", Group = "journal", Type = ConfigType.Path,
        Risk = ConfigRisk.Wiring)]
    public string Directory { get; set; } = "/var/lib/kgsm/events";

    /// <summary>Days of segments kept. Zero or less keeps everything.</summary>
    /// <panel>How many days of event journal are kept. Zero keeps everything.</panel>
    [ConfigField("journalRetentionDays", "Journal retention", Group = "journal", Unit = "days",
        Risk = ConfigRisk.Destructive)]
    public int RetentionDays { get; set; } = 90;
}

/// <summary>Where the watchdog's cgroup tree sits, for an instance's derived cgroup path.</summary>
[ConfigSection(Section)]
public sealed class CgroupSettings
{
    public const string Section = "Cgroup";

    /// <summary>The cgroup v2 mount point.</summary>
    /// <panel>Where the cgroup v2 hierarchy is mounted.</panel>
    [ConfigField("cgroupMountPoint", "Cgroup v2 mount point", Group = "cgroup", Type = ConfigType.Path,
        Risk = ConfigRisk.Wiring)]
    public string MountPoint { get; set; } = "/sys/fs/cgroup";

    /// <summary>The watchdog's cgroup relative to the mount point.</summary>
    /// <panel>The watchdog's cgroup below the mount point. An instance's cgroup path is derived from
    /// it.</panel>
    [ConfigField("cgroupBaseName", "Watchdog cgroup", Group = "cgroup", Risk = ConfigRisk.Wiring)]
    public string BaseName { get; set; } = "kgsm.slice/kgsm-watchdog.service";
}

/// <summary>How the engine reaches the watchdog.</summary>
[ConfigSection(Section)]
public sealed class WatchdogSettings
{
    public const string Section = "Watchdog";

    /// <summary>The watchdog's control socket.</summary>
    /// <panel>Unix socket the engine reaches the watchdog on to start and stop native instances.</panel>
    [ConfigField("watchdogSocket", "Watchdog socket", Group = "watchdog", Type = ConfigType.Path,
        Risk = ConfigRisk.Wiring)]
    public string Socket { get; set; } = "/run/kgsm-watchdog/control.sock";

    /// <summary>Whether native lifecycle routes to the watchdog when it is ready.</summary>
    /// <panel>Whether starts and stops of native instances go through the watchdog. Off starts them
    /// unsupervised.</panel>
    [ConfigField("watchdogEnabled", "Use the watchdog", Group = "watchdog", Risk = ConfigRisk.Wiring)]
    public bool Enabled { get; set; } = true;
}

/// <summary>How the engine reaches the firewall authority.</summary>
[ConfigSection(Section)]
public sealed class FirewallSettings
{
    public const string Section = "Firewall";

    /// <summary>The firewall client executable.</summary>
    /// <panel>The firewall client the engine runs to open and close an instance's ports.</panel>
    [ConfigField("firewallClient", "Firewall client", Group = "firewall", Risk = ConfigRisk.Wiring)]
    public string Client { get; set; } = "kgsm-firewall";

    /// <summary>The firewall authority's socket.</summary>
    /// <panel>Unix socket of the firewall authority.</panel>
    [ConfigField("firewallSocket", "Firewall socket", Group = "firewall", Type = ConfigType.Path,
        Risk = ConfigRisk.Wiring)]
    public string Socket { get; set; } = "/run/kgsm-firewall/firewall.sock";
}

/// <summary>Game file downloads.</summary>
[ConfigSection(Section)]
public sealed class DownloadsSettings
{
    public const string Section = "Downloads";

    /// <summary>Seconds a download waits on a stalled connection. Exposed to hooks.</summary>
    /// <panel>How long a game file download waits on a stalled connection before it gives up.</panel>
    [ConfigField("downloadTimeoutSeconds", "Download timeout", Group = "downloads", Min = Floors.TimeoutSeconds,
        Unit = "s")]
    public int TimeoutSeconds { get; set; } = 60;

    public static class Floors
    {
        public const int TimeoutSeconds = 1;
    }
}

/// <summary>The engine's logging. The level is <c>Logging:LogLevel:Default</c>.</summary>
public sealed class LoggingSettings
{
    public FileLogSettings File { get; set; } = new();
}

/// <summary>
/// The engine's log file. Its two keys are described by the host that publishes the descriptor, because
/// the descriptor model has no nested section of its own.
/// </summary>
public sealed class FileLogSettings
{
    /// <summary>Size at which <c>kgsm.log</c> rotates.</summary>
    public int MaxSizeKb { get; set; } = 10240;

    /// <summary>Rotated files kept beside the current one.</summary>
    public int MaxFiles { get; set; } = 5;

    public static class Floors
    {
        public const int MaxSizeKb = 1;

        public const int MaxFiles = 0;
    }
}
