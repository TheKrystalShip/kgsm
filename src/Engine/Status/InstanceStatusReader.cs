using TheKrystalShip.KGSM.Engine.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Status;

/// <summary>
/// Builds an instance's status from what can be measured. A native instance's run state comes from the
/// watchdog's control socket (health, then the instance's state, both read from the body), a container's
/// from <c>docker compose ps</c>. Where the answer cannot be had the state is unknown, never stopped: an
/// absence of an answer is not an answer.
/// </summary>
public sealed class InstanceStatusReader(
    IWatchdogProbe watchdog, IContainerRuntime containers, bool watchdogEnabled = true, Func<int, bool>? processAlive = null)
{
    private const int RecentLogLines = 3;

    private readonly Func<int, bool> _processAlive = processAlive ?? (pid => Directory.Exists($"/proc/{pid}"));

    /// <summary>
    /// The instance's status. <paramref name="measureDisk"/> walks the working directory for its size, which
    /// costs time in proportion to the number of files in it; without it the size is unknown.
    /// </summary>
    public async Task<InstanceStatus> ReadAsync(InstanceDescription instance, bool measureDisk, CancellationToken cancellationToken)
    {
        InstanceLayout layout = instance.Layout;
        InstanceConfig? config = instance.Config;
        bool offline = instance.LibraryState == InstanceLibraryState.Offline;

        InstanceProcess process = offline
            ? new InstanceProcess
            {
                State = RunState.Unknown,
                Source = RunStateSource.None,
                Detail = $"library '{instance.Library!.Name}' is offline",
            }
            : config?.Runtime == BlueprintRuntime.Container
                ? await ContainerProcessAsync(layout, cancellationToken).ConfigureAwait(false)
                : await NativeProcessAsync(instance.Id, layout, cancellationToken).ConfigureAwait(false);

        IReadOnlyList<string> backups = config is null || offline
            ? []
            : [.. BackupReader.List(config.BackupsDirectory).Backups.Select(b => b.Id)];

        return new InstanceStatus
        {
            Id = instance.Id,
            Process = process,
            Version = offline ? new InstanceVersion { Checked = false } : InstanceVersions.Read(layout),
            Configuration = new InstanceConfiguration
            {
                Blueprint = instance.Blueprint,
                Runtime = config?.Runtime,
                Directory = instance.WorkingDirectory,
                Ports = PortSpecs.Parse(config?.Ports),
            },
            LibraryState = instance.LibraryState,
            DiskUsageBytes = measureDisk && !offline ? DiskUsage.Of(instance.WorkingDirectory) : null,
            Backups = backups,
            RecentLogs = offline ? [] : InstanceLogs.Recent(layout, RecentLogLines).Lines,
        };
    }

    /// <summary>A native instance's run state: the watchdog's answer, with the pid file the management script writes as the witness for a run outside its supervision.</summary>
    private async Task<InstanceProcess> NativeProcessAsync(string id, InstanceLayout layout, CancellationToken cancellationToken)
    {
        InstanceProcess? unsupervised = PidFileProcess(layout);

        if (!watchdogEnabled || !watchdog.SocketPresent)
        {
            // No daemon is meant to be here, so the pid file the management script writes is the whole answer.
            return unsupervised ?? new InstanceProcess
            {
                State = RunState.Stopped,
                Source = RunStateSource.PidFile,
                Detail = "no watchdog on this host and no live pid file",
            };
        }

        try
        {
            WatchdogHealth health = await watchdog.HealthAsync(cancellationToken).ConfigureAwait(false);
            if (!health.Reachable)
                return unsupervised ?? Unknown($"the watchdog socket does not answer: {health.Detail}");

            InstanceState? state = await watchdog.StatusAsync(id, cancellationToken).ConfigureAwait(false);
            if (state is null)
            {
                return unsupervised is not null
                    ? unsupervised with { Detail = "running outside the watchdog's supervision" }
                    : new InstanceProcess
                    {
                        State = RunState.Stopped,
                        Source = RunStateSource.Watchdog,
                        Detail = "the watchdog does not track this instance",
                    };
            }

            RunState runState = state.Phase == "unknown" ? RunState.Unknown : state.Populated ? RunState.Running : RunState.Stopped;
            return new InstanceProcess
            {
                State = runState,
                Source = RunStateSource.Watchdog,
                Pid = state.Populated ? state.Pid : null,
                StartTime = state.Populated && state.SpawnedAt is { } spawned ? new DateTimeOffset(DateTime.SpecifyKind(spawned, DateTimeKind.Utc)) : null,
                Phase = state.Phase,
                Detail = health.Ready ? null : $"the watchdog is not ready: {health.Detail}",
            };
        }
        catch (WatchdogUnavailableException ex)
        {
            return unsupervised ?? Unknown(ex.Message);
        }
    }

    private async Task<InstanceProcess> ContainerProcessAsync(InstanceLayout layout, CancellationToken cancellationToken)
    {
        if (!File.Exists(layout.ComposeFile)) return Unknown("the compose file is missing");

        ComposeAnswer answer = await containers.ListRunningAsync(layout.ComposeFile, cancellationToken).ConfigureAwait(false);
        if (answer.Services is null) return Unknown(answer.Problem!);

        bool running = answer.Services.Any(s => s.State.Equals("running", StringComparison.OrdinalIgnoreCase));
        return new InstanceProcess
        {
            State = running ? RunState.Running : RunState.Stopped,
            Source = RunStateSource.Compose,
        };
    }

    private InstanceProcess? PidFileProcess(InstanceLayout layout)
    {
        try
        {
            if (!File.Exists(layout.PidFile)) return null;
            return int.TryParse(File.ReadAllText(layout.PidFile).Trim(), out int pid) && pid > 0 && _processAlive(pid)
                ? new InstanceProcess { State = RunState.Running, Source = RunStateSource.PidFile, Pid = pid }
                : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static InstanceProcess Unknown(string detail) =>
        new() { State = RunState.Unknown, Source = RunStateSource.None, Detail = detail };
}

/// <summary>Measures the bytes a directory tree holds.</summary>
public static class DiskUsage
{
    /// <summary>The sum of the sizes of the regular files under <paramref name="directory"/>; symbolic links are not followed.</summary>
    public static long? Of(string directory)
    {
        if (!Directory.Exists(directory)) return null;

        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint,
            ReturnSpecialDirectories = false,
        };

        long total = 0;
        foreach (long length in new System.IO.Enumeration.FileSystemEnumerable<long>(
            directory, (ref System.IO.Enumeration.FileSystemEntry entry) => entry.Length, options)
        {
            ShouldIncludePredicate = (ref System.IO.Enumeration.FileSystemEntry entry) => !entry.IsDirectory,
        })
        {
            total += length;
        }

        return total;
    }
}
