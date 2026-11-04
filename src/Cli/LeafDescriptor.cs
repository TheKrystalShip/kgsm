using TheKrystalShip.KGSM.ComponentConfig;

// What the Control Panel shows about the engine's settings, declared beside the host that publishes them.
// TheKrystalShip.KGSM.ComponentConfig reads the settings sections out of the core assembly and writes
// kgsm.leaf.json from them; the binary never reads any of this.

[assembly: Leaf(
    id: "engine",
    displayName: "Engine",
    unit: "kgsm-journal-prune.service",
    role: "The command-line engine that installs, configures and manages game server instances.",
    OnDemand = true)]

[assembly: ConfigSectionAssembly("TheKrystalShip.KGSM.Engine")]

[assembly: ConfigGroup("libraries", "Libraries", 1)]
[assembly: ConfigGroup("instances", "Instance defaults", 2)]
[assembly: ConfigGroup("backups", "Backups", 3)]
[assembly: ConfigGroup("journal", "Event journal", 4)]
[assembly: ConfigGroup("cgroup", "Cgroup layout", 5)]
[assembly: ConfigGroup("watchdog", "Watchdog", 6)]
[assembly: ConfigGroup("firewall", "Firewall", 7)]
[assembly: ConfigGroup("downloads", "Downloads", 8)]
[assembly: ConfigGroup("logging", "Logging", 9)]

// Lowest precedence first: the settings file beside the binary declares the whole surface.
[assembly: ConfigFloorSource("appsettings", "/usr/bin/kgsm.settings.json")]

[assembly: ConfigFrameworkNamespace("Logging__LogLevel__",
    "per-category filtering is open-ended: any category name is a valid key")]

[assembly: ConfigFrameworkField("logLevel", "Logging__LogLevel__Default", "Log level",
    Description = "Minimum severity the engine writes to its log file.",
    Group = "logging",
    Type = ConfigType.Enum,
    Values = ["Trace", "Debug", "Information", "Warning", "Error", "Critical"])]

[assembly: ConfigFrameworkField("logMaxSizeKb", "Logging__File__MaxSizeKb", "Log rotation size",
    Description = "Size at which the engine's log file is rotated.",
    Group = "logging",
    Type = ConfigType.Int,
    Min = 1,
    Unit = "KB",
    Default = "10240")]

[assembly: ConfigFrameworkField("logMaxFiles", "Logging__File__MaxFiles", "Rotated log files",
    Description = "How many rotated log files are kept beside the current one. Zero keeps none.",
    Group = "logging",
    Type = ConfigType.Int,
    Min = 0,
    Default = "5")]
