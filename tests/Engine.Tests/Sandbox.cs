using TheKrystalShip.KGSM.Engine;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Tests;

/// <summary>
/// One test's whole world: its own XDG homes, install root, journal directory and library roots under a
/// directory of its own beneath the run's temporary root. Nothing reaches a live path.
/// </summary>
internal sealed class Sandbox
{
    private Sandbox(string root)
    {
        Root = root;
        Directory.CreateDirectory(root);

        Paths = EnginePaths.Resolve(
            name => name switch
            {
                "HOME" => Path.Combine(root, "home"),
                "XDG_CONFIG_HOME" => Path.Combine(root, "config"),
                "XDG_DATA_HOME" => Path.Combine(root, "data"),
                "XDG_STATE_HOME" => Path.Combine(root, "state"),
                _ => null,
            },
            InstallRoot,
            Path.Combine(root, "home"));
    }

    public string Root { get; }

    public EnginePaths Paths { get; }

    public string InstallRoot => Path.Combine(Root, "install");

    public string JournalDirectory => Path.Combine(Root, "journal");

    public static Sandbox Create() => new(Path.Combine(Path.GetTempPath(), "kgsm-test-" + Guid.NewGuid().ToString("N")));

    /// <summary>A path under the sandbox; the directory it sits in is created.</summary>
    public string PathFor(params string[] parts)
    {
        string path = Path.Combine([Root, .. parts]);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        return path;
    }

    public string WriteFile(string path, string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
        return path;
    }

    /// <summary>Registers a library whose root exists and carries its marker.</summary>
    public LibraryRecord AddLibrary(string name, string? root = null, bool withMarker = true)
    {
        root ??= Path.Combine(Root, "libraries", name);
        Directory.CreateDirectory(root);

        var record = new LibraryRecord { Name = name, Id = LibraryCatalog.NewId(), Path = root };
        if (withMarker) WriteMarker(root, record.Id, name);

        List<LibraryRecord> all = [.. new LibraryCatalog(Paths).Registered(), record];
        ContractFile.Write(
            Paths.LibraryRegistryFile,
            new LibraryRegistryFile { SchemaVersion = SchemaVersions.LibraryRegistry, Libraries = all },
            EngineJsonContext.Default.LibraryRegistryFile);

        return record;
    }

    public static void WriteMarker(string root, string id, string name) =>
        ContractFile.Write(
            Path.Combine(root, LibraryRules.MarkerFileName),
            new LibraryMarker { SchemaVersion = SchemaVersions.LibraryMarker, Id = id, Name = name },
            EngineJsonContext.Default.LibraryMarker);

    /// <summary>Registers an instance in a library and writes its config.</summary>
    public (string WorkingDirectory, InstanceConfig Config) AddInstance(
        LibraryRecord library, string blueprint, string id, Func<InstanceConfig, InstanceConfig>? shape = null)
    {
        string workingDirectory = Path.Combine(library.Path, "instances", blueprint, id);
        Directory.CreateDirectory(workingDirectory);

        InstanceConfig config = NewConfig(blueprint, id, Path.Combine(Root, "backups", id));
        if (shape is not null) config = shape(config);
        ContractFile.Write(new Engine.Instances.InstanceLayout(workingDirectory, id).ConfigFile, config, EngineJsonContext.Default.InstanceConfig);

        Register(id, blueprint, library.Id, workingDirectory);
        return (workingDirectory, config);
    }

    public void Register(string id, string blueprint, string libraryId, string workingDirectory)
    {
        var instances = new SortedDictionary<string, InstanceRegistryEntry>(StringComparer.Ordinal);
        if (File.Exists(Paths.InstanceRegistryFile))
        {
            foreach ((string key, InstanceRegistryEntry value) in new Engine.Instances.InstanceStore(Paths, new LibraryCatalog(Paths)).Registered())
                instances[key] = value;
        }

        instances[id] = new InstanceRegistryEntry { Blueprint = blueprint, Library = libraryId, WorkingDirectory = workingDirectory };
        ContractFile.Write(
            Paths.InstanceRegistryFile,
            new InstanceRegistryFile { SchemaVersion = SchemaVersions.InstanceRegistry, Instances = instances },
            EngineJsonContext.Default.InstanceRegistryFile);
    }

    public static InstanceConfig NewConfig(string blueprint, string id, string backups) => new()
    {
        SchemaVersion = SchemaVersions.InstanceConfig,
        Name = id,
        DisplayName = string.Empty,
        Blueprint = blueprint,
        Runtime = BlueprintRuntime.Native,
        InstallNonce = "nonce-" + id,
        BackupsDirectory = backups,
        Platform = "linux",
        AutoUpdateBeforeStart = false,
        CpuPriority = "normal",
        MemoryCapMb = 0,
        MaintenanceWindows = string.Empty,
        Timezone = string.Empty,
        BackupRetention = 3,
        AnnounceLeadMinutes = string.Empty,
        AnnounceMaintenanceMessage = "Server restart in {minutes} min",
        AnnounceMaintenanceCancelledMessage = "Server restart cancelled",
        CrashRestart = true,
        CrashMaxRestarts = 5,
        StartupSuccessRegex = string.Empty,
        PlayerJoinedRegex = string.Empty,
        PlayerLeftRegex = string.Empty,
        RconPassword = string.Empty,
        RconPollIntervalSeconds = 10,
        RconPlayersCommand = string.Empty,
        RconPlayersRegex = string.Empty,
        LevelName = "world one",
        ExecutableFile = "server",
        ExecutableSubdirectory = string.Empty,
        ExecutableArguments = "--save {savesDir}/{levelName} --name {name}",
        SteamAppId = 0,
        ClientSteamAppId = 0,
        SteamcmdArguments = string.Empty,
        IsSteamAccountRequired = false,
        Ports = string.Empty,
        EnableFirewallManagement = false,
        EnablePortForwarding = false,
        DownloadTimeoutSeconds = 60,
        StopCommand = string.Empty,
        SaveCommand = string.Empty,
        SaveCommandTimeoutSeconds = 5,
        StopCommandTimeoutSeconds = 30,
        KickCommand = string.Empty,
        BanCommand = string.Empty,
        UnbanCommand = string.Empty,
        BroadcastCommand = string.Empty,
        CompressBackups = true,
    };
}
