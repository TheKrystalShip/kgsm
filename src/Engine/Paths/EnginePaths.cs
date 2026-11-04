using TheKrystalShip.KGSM.Engine.Contracts.Paths;

namespace TheKrystalShip.KGSM.Engine.Paths;

/// <summary>
/// Every directory and file the engine resolves, following the XDG Base Directory specification: a
/// person's settings in the config home, the registries, user blueprints, user overrides and default
/// backups root in the data home, the log in the state home, and the system blueprints, system
/// overrides and shipped settings beside the binary.
/// </summary>
public sealed class EnginePaths
{
    public const string AppDirectoryName = "kgsm";

    public const string SettingsFileName = "kgsm.settings.json";

    public const string LogFileName = "kgsm.log";

    public const string BlueprintFileSuffix = ".bp.yaml";

    /// <summary>Steam credentials: <c>STEAM_USERNAME</c> and <c>STEAM_PASSWORD</c>, readable by the engine's account only.</summary>
    public const string SteamCredentialsFilePath = "/etc/kgsm/kgsm.env";

    private EnginePaths(string home, string configHome, string dataHome, string stateHome, string installRoot)
    {
        Home = home;
        ConfigHome = configHome;
        DataHome = dataHome;
        StateHome = stateHome;
        InstallRoot = installRoot;
    }

    public string Home { get; }

    /// <summary><c>$XDG_CONFIG_HOME</c>, or <c>~/.config</c>.</summary>
    public string ConfigHome { get; }

    /// <summary><c>$XDG_DATA_HOME</c>, or <c>~/.local/share</c>.</summary>
    public string DataHome { get; }

    /// <summary><c>$XDG_STATE_HOME</c>, or <c>~/.local/state</c>.</summary>
    public string StateHome { get; }

    /// <summary>The directory the binary sits in.</summary>
    public string InstallRoot { get; }

    public string UserSettingsFile => Path.Combine(ConfigHome, AppDirectoryName, SettingsFileName);

    public string SystemSettingsFile => Path.Combine(InstallRoot, SettingsFileName);

    /// <summary>The engine's data directory, <c>&lt;data home&gt;/kgsm</c>.</summary>
    public string DataDirectory => Path.Combine(DataHome, AppDirectoryName);

    public string InstanceRegistryFile => Path.Combine(DataDirectory, "instances.json");

    public string LibraryRegistryFile => Path.Combine(DataDirectory, "libraries.json");

    public string UserBlueprintsDirectory => Path.Combine(DataDirectory, "blueprints");

    public string SystemBlueprintsDirectory => Path.Combine(InstallRoot, "blueprints");

    public string UserOverridesDirectory => Path.Combine(DataDirectory, "overrides");

    public string SystemOverridesDirectory => Path.Combine(InstallRoot, "overrides");

    /// <summary>The backups root used when the settings name none.</summary>
    public string DefaultBackupsDirectory => Path.Combine(DataDirectory, "backups");

    public string LogDirectory => Path.Combine(StateHome, AppDirectoryName, "logs");

    public string LogFile => Path.Combine(LogDirectory, LogFileName);

    /// <summary>Where the lock files live.</summary>
    public string LocksDirectory => Path.Combine(StateHome, AppDirectoryName, "locks");

    /// <summary>
    /// Resolves the layout from an environment lookup. An XDG variable that is unset, empty or not an
    /// absolute path is ignored, as the specification says, and its fallback under the home directory used.
    /// </summary>
    /// <param name="environment">Looks a variable up; null when unset.</param>
    /// <param name="installRoot">The directory the binary sits in.</param>
    /// <param name="homeFallback">The home directory when <c>HOME</c> is unset or relative.</param>
    public static EnginePaths Resolve(Func<string, string?> environment, string installRoot, string homeFallback)
    {
        ArgumentNullException.ThrowIfNull(environment);
        ArgumentException.ThrowIfNullOrWhiteSpace(installRoot);
        ArgumentException.ThrowIfNullOrWhiteSpace(homeFallback);

        string home = Absolute(environment("HOME")) ?? homeFallback;

        return new EnginePaths(
            home,
            Absolute(environment("XDG_CONFIG_HOME")) ?? Path.Combine(home, ".config"),
            Absolute(environment("XDG_DATA_HOME")) ?? Path.Combine(home, ".local", "share"),
            Absolute(environment("XDG_STATE_HOME")) ?? Path.Combine(home, ".local", "state"),
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(installRoot)));
    }

    /// <summary>The layout of the running process: its environment, with the binary's own directory as the install root.</summary>
    public static EnginePaths FromProcess() => Resolve(
        Environment.GetEnvironmentVariable,
        AppContext.BaseDirectory,
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));

    public PathsReport ToReport() => new()
    {
        ConfigHome = ConfigHome,
        DataHome = DataHome,
        StateHome = StateHome,
        InstallRoot = InstallRoot,
        UserSettingsFile = UserSettingsFile,
        SystemSettingsFile = SystemSettingsFile,
        InstanceRegistryFile = InstanceRegistryFile,
        LibraryRegistryFile = LibraryRegistryFile,
        UserBlueprintsDirectory = UserBlueprintsDirectory,
        SystemBlueprintsDirectory = SystemBlueprintsDirectory,
        UserOverridesDirectory = UserOverridesDirectory,
        SystemOverridesDirectory = SystemOverridesDirectory,
        DefaultBackupsDirectory = DefaultBackupsDirectory,
        LogDirectory = LogDirectory,
        LogFile = LogFile,
        LocksDirectory = LocksDirectory,
        SteamCredentialsFile = SteamCredentialsFilePath,
    };

    private static string? Absolute(string? value) =>
        !string.IsNullOrEmpty(value) && Path.IsPathRooted(value) ? value : null;
}
