using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Journal;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Locks;
using TheKrystalShip.KGSM.Engine.Logging;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Paths;
using TheKrystalShip.KGSM.Engine.Scripts;
using TheKrystalShip.KGSM.Engine.Settings;
using TheKrystalShip.KGSM.Engine.Status;

namespace TheKrystalShip.KGSM.Cli;

/// <summary>
/// The engine's modules wired for one command. Each is built on first use, so a command that needs only
/// the paths reads no settings and opens no log.
/// </summary>
internal sealed class EngineServices(CliEnvironment environment) : IDisposable
{
    private EngineConfiguration? _configuration;
    private ILoggerFactory? _loggers;
    private IWatchdogControl? _watchdog;
    private OperationHost? _operations;

    public CliEnvironment Environment => environment;

    public EnginePaths Paths { get; } = environment.ResolvePaths();

    /// <exception cref="InvalidSettingsException">A setting is below its floor or unreadable.</exception>
    public EngineConfiguration Configuration => _configuration ??= EngineSettingsLoader.Load(Paths, environment.Variables);

    public EngineSettings Settings => Configuration.Settings;

    public ILoggerFactory Loggers => _loggers ??= EngineLogging.CreateFactory(Configuration, Paths, environment.Clock);

    public LibraryCatalog Libraries => new(Paths);

    public BlueprintCatalog Blueprints => new(Paths, new BlueprintParser(Loggers.CreateLogger<BlueprintParser>()));

    public InstanceStore Instances => new(Paths, Libraries, Loggers.CreateLogger<InstanceStore>());

    public ScriptRepairer ScriptRepairer => new(
        Paths, Settings.Watchdog.Socket, new EngineLocks(Paths), Loggers.CreateLogger<ScriptRepairer>());

    public IRequirementProbe Requirements => environment.Requirements
        ?? new HostRequirementProbe(environment.Variable, EnginePaths.SteamCredentialsFilePath);

    /// <summary>Who is acting; set by the command host before a command runs.</summary>
    public Provenance Provenance { get; set; }

    public IWatchdogControl Watchdog =>
        _watchdog ??= environment.WatchdogProbe?.Invoke(Settings.Watchdog) ?? new WatchdogControl(Settings.Watchdog.Socket);

    public IContainerRuntime Containers => environment.Containers ?? new DockerCompose();

    public InstanceStatusReader Status =>
        new(Watchdog, Containers, Settings.Watchdog.Enabled, environment.ProcessAlive);

    /// <summary>The write operations' world: the modules, the locks, the journal and the doors to the outside.</summary>
    public OperationHost Operations => _operations ??= BuildOperations();

    private OperationHost BuildOperations()
    {
        IProcessRunner processes = environment.Processes ?? new SystemProcessRunner();
        var writer = new EventJournalWriter(
            new EventJournalOptions { Directory = Settings.Journal.Directory },
            environment.Clock, Loggers.CreateLogger<EventJournalWriter>());

        var inherited = environment.Variables
            .Where(v => v.Value is not null && (v.Key is "HOME" or "PATH" || v.Key.StartsWith("XDG_", StringComparison.Ordinal) || v.Key.Contains("__", StringComparison.Ordinal) || v.Key.StartsWith("KGSM_", StringComparison.Ordinal)))
            .ToDictionary(v => v.Key, v => v.Value!, StringComparer.Ordinal);

        return new OperationHost
        {
            Paths = Paths,
            Settings = Settings,
            Libraries = Libraries,
            Instances = Instances,
            Blueprints = Blueprints,
            Locks = new EngineLocks(Paths),
            Events = new EventRecorder(writer, Settings.Journal.Directory, Provenance, Loggers.CreateLogger("events")),
            Script = new ScriptClient(processes, Settings.Watchdog.Socket, Provenance, inherited, Loggers.CreateLogger("script")),
            Watchdog = Watchdog,
            Firewall = environment.Firewall ?? new FirewallCli(processes, Settings.Firewall),
            Status = Status,
            Repairer = ScriptRepairer,
            Requirements = Requirements,
            Clock = environment.Clock,
            Loggers = Loggers,
            BinaryPath = environment.BinaryPath,
            SettleTimeout = environment.SettleTimeout,
        };
    }

    public void Dispose()
    {
        (_watchdog as IDisposable)?.Dispose();
        _loggers?.Dispose();
    }
}
