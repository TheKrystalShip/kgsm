namespace TheKrystalShip.KGSM.Engine.Contracts.Paths;

/// <summary>Every directory and file the engine resolves, as <c>kgsm engine paths</c> reports them.</summary>
public sealed record PathsReport
{
    public required string ConfigHome { get; init; }

    public required string DataHome { get; init; }

    public required string StateHome { get; init; }

    public required string InstallRoot { get; init; }

    public required string UserSettingsFile { get; init; }

    public required string SystemSettingsFile { get; init; }

    public required string InstanceRegistryFile { get; init; }

    public required string LibraryRegistryFile { get; init; }

    public required string UserBlueprintsDirectory { get; init; }

    public required string SystemBlueprintsDirectory { get; init; }

    public required string UserOverridesDirectory { get; init; }

    public required string SystemOverridesDirectory { get; init; }

    public required string DefaultBackupsDirectory { get; init; }

    public required string LogDirectory { get; init; }

    public required string LogFile { get; init; }

    public required string LocksDirectory { get; init; }

    public required string SteamCredentialsFile { get; init; }
}
