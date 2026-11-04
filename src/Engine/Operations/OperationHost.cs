using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Locks;
using TheKrystalShip.KGSM.Engine.Paths;
using TheKrystalShip.KGSM.Engine.Scripts;
using TheKrystalShip.KGSM.Engine.Settings;
using TheKrystalShip.KGSM.Engine.Status;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Everything the write operations stand on, wired for one command: the modules that read, the locks, the
/// journal, and the doors to the outside world (the instance's script, the watchdog, the container
/// runtime, the firewall authority). Each door is an interface, so an operation runs against fakes.
/// </summary>
public sealed class OperationHost
{
    public required EnginePaths Paths { get; init; }

    public required EngineSettings Settings { get; init; }

    public required LibraryCatalog Libraries { get; init; }

    public required InstanceStore Instances { get; init; }

    public required BlueprintCatalog Blueprints { get; init; }

    public required EngineLocks Locks { get; init; }

    public required EventRecorder Events { get; init; }

    public required ScriptClient Script { get; init; }

    public required IWatchdogControl Watchdog { get; init; }

    public required IFirewallClient Firewall { get; init; }

    public required InstanceStatusReader Status { get; init; }

    public required ScriptRepairer Repairer { get; init; }

    public required IRequirementProbe Requirements { get; init; }

    public required TimeProvider Clock { get; init; }

    public required ILoggerFactory Loggers { get; init; }

    /// <summary>The binary that is running, which an instance's script calls back to report update phases; null when it is unknown.</summary>
    public string? BinaryPath { get; init; }

    /// <summary>How long a start or stop waits for the run state to show it; measured in real time.</summary>
    public TimeSpan SettleTimeout { get; init; } = TimeSpan.FromSeconds(15);

    public ILogger Logger(string category) => Loggers.CreateLogger(category);

    public InstanceRegistry Registry => new(Paths, Locks, Instances);

    public LifecycleService Lifecycle => new(this);

    /// <summary>The instance's run state, measured now.</summary>
    public async Task<InstanceProcess> MeasureAsync(InstanceDescription instance, CancellationToken cancellationToken) =>
        (await Status.ReadAsync(instance, measureDisk: false, cancellationToken).ConfigureAwait(false)).Process;

    /// <summary>The backups directory for an instance named <paramref name="id"/>: below the configured root, or the data home's.</summary>
    public string BackupsDirectoryFor(string id) =>
        Path.Combine(string.IsNullOrWhiteSpace(Settings.Backups.Directory) ? Paths.DefaultBackupsDirectory : Settings.Backups.Directory, id);
}

/// <summary>The checks nearly every operation makes before it touches an instance.</summary>
public static class Guards
{
    /// <summary>The instance's config, or a refusal that says why there is none.</summary>
    public static InstanceConfig Config(InstanceDescription instance) =>
        instance.Config ?? throw new OperationException(ErrorCodes.Failed, instance.ConfigProblem ?? "the instance's config cannot be read");

    /// <summary>Refuses an instance whose library's disk is not there.</summary>
    public static void Online(InstanceDescription instance, string action)
    {
        if (instance.LibraryState == InstanceLibraryState.Offline)
            throw OperationException.Refused($"{action} is refused: the library '{instance.Library?.Name}' of '{instance.Id}' is offline");
    }

    /// <summary>The checks of an action that changes an instance: a readable config, an online library, no transfer lock.</summary>
    public static InstanceConfig ForChange(InstanceDescription instance, string action)
    {
        InstanceConfig config = Config(instance);
        Online(instance, action);
        TransferLock.Require(instance, action);
        return config;
    }
}
