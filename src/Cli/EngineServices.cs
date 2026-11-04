using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Locks;
using TheKrystalShip.KGSM.Engine.Logging;
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
    private IWatchdogProbe? _watchdog;

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

    public InstanceStatusReader Status
    {
        get
        {
            _watchdog ??= environment.WatchdogProbe?.Invoke(Settings.Watchdog) ?? new WatchdogProbe(Settings.Watchdog.Socket);
            return new InstanceStatusReader(
                _watchdog, environment.Containers ?? new DockerCompose(), Settings.Watchdog.Enabled, environment.ProcessAlive);
        }
    }

    public void Dispose()
    {
        (_watchdog as IDisposable)?.Dispose();
        _loggers?.Dispose();
    }
}
