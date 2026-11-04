using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Start, stop and restart. A native instance goes through the watchdog when it is ready; when it is
/// absent or not ready the instance's own script starts it unsupervised, and the report says so. A
/// container always goes through its script. Each verb is bracketed by <c>*.started</c> and
/// <c>*.finished</c>, with the fact in the middle written only when the run state really moved,
/// measured before and after.
/// </summary>
public sealed class LifecycleService(OperationHost host)
{
    private static readonly TimeSpan SettleStep = TimeSpan.FromMilliseconds(200);

    public async Task<LifecycleReport> StartAsync(InstanceDescription instance, bool force, CancellationToken cancellationToken)
    {
        Guards.ForChange(instance, "start");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        host.Events.Append(new StartStarted { InstanceName = instance.Id });
        try
        {
            return await StartCoreAsync(instance, force, announce: true, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            host.Events.Append(new StartFinished { InstanceName = instance.Id });
        }
    }

    public async Task<LifecycleReport> StopAsync(InstanceDescription instance, CancellationToken cancellationToken)
    {
        Guards.Config(instance);
        Guards.Online(instance, "stop");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        host.Events.Append(new StopStarted { InstanceName = instance.Id });
        try
        {
            return await StopCoreAsync(instance, announce: true, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            host.Events.Append(new StopFinished { InstanceName = instance.Id });
        }
    }

    public async Task<LifecycleReport> RestartAsync(InstanceDescription instance, bool force, CancellationToken cancellationToken)
    {
        Guards.ForChange(instance, "restart");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        host.Events.Append(new RestartStarted { InstanceName = instance.Id });
        try
        {
            LifecycleReport stopped = await StopCoreAsync(instance, announce: false, cancellationToken).ConfigureAwait(false);
            if (stopped.Changed) host.Events.Append(new RestartStopped { InstanceName = instance.Id });

            LifecycleReport started = await StartCoreAsync(instance, force, announce: false, cancellationToken).ConfigureAwait(false);
            host.Events.Append(new Restarted { InstanceName = instance.Id });
            return started with { Action = "restart", Changed = true };
        }
        finally
        {
            host.Events.Append(new RestartFinished { InstanceName = instance.Id });
        }
    }

    /// <summary>Starts an instance under the caller's lock, with the firewall opened first.</summary>
    internal async Task<LifecycleReport> StartCoreAsync(InstanceDescription instance, bool force, bool announce, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.Config(instance);
        InstanceProcess before = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);

        if (before.State == RunState.Running)
        {
            return new LifecycleReport
            {
                Id = instance.Id,
                Action = "start",
                State = RunState.Running,
                Changed = false,
                Via = before.Source == RunStateSource.Watchdog ? "watchdog" : "script",
                Supervised = before.Source == RunStateSource.Watchdog,
                Message = "already running",
            };
        }

        await OpenFirewallAsync(instance.Id, config, cancellationToken).ConfigureAwait(false);

        bool supervised = await WatchdogReadyAsync(config, cancellationToken).ConfigureAwait(false);
        if (supervised)
        {
            ActionResult result = await host.Watchdog.StartAsync(instance.Id, force, host.Events.Provenance.Origin, cancellationToken).ConfigureAwait(false);
            if (!result.Ok) throw RefusalOf(result);
        }
        else
        {
            await host.Script.RequireAsync(instance, ["start", "-d"], "start", cancellationToken).ConfigureAwait(false);
        }

        InstanceProcess after = await SettleAsync(instance, RunState.Running, cancellationToken).ConfigureAwait(false);
        if (after.State != RunState.Running)
            throw new OperationException(ErrorCodes.Failed, $"'{instance.Id}' was started and is not running ({after.Detail ?? after.State.ToString().ToLowerInvariant()})");

        if (announce) host.Events.Append(new Started { InstanceName = instance.Id });

        return new LifecycleReport
        {
            Id = instance.Id,
            Action = "start",
            State = RunState.Running,
            Changed = true,
            Via = supervised ? "watchdog" : "script",
            Supervised = supervised,
            Message = supervised ? null : config.Runtime == BlueprintRuntime.Native ? "started without the watchdog, unsupervised" : null,
        };
    }

    /// <summary>
    /// Stops an instance under the caller's lock, whoever runs it: the watchdog for an instance it
    /// supervises, otherwise the instance's own script, which reads its pid file or asks the runtime.
    /// </summary>
    internal async Task<LifecycleReport> StopCoreAsync(InstanceDescription instance, bool announce, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.Config(instance);
        InstanceProcess before = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);

        if (before.State == RunState.Stopped)
        {
            return new LifecycleReport
            {
                Id = instance.Id,
                Action = "stop",
                State = RunState.Stopped,
                Changed = false,
                Via = before.Source == RunStateSource.Watchdog ? "watchdog" : "script",
                Supervised = false,
                Message = "not running",
            };
        }

        bool viaWatchdog = await SupervisedByWatchdogAsync(instance.Id, config, cancellationToken).ConfigureAwait(false);
        if (viaWatchdog)
        {
            ActionResult result = await host.Watchdog.StopAsync(instance.Id, host.Events.Provenance.Origin, cancellationToken).ConfigureAwait(false);
            if (!result.Ok) throw new OperationException(ErrorCodes.Failed, $"the watchdog did not stop '{instance.Id}': {result.Message}");
        }
        else
        {
            await host.Script.RequireAsync(instance, ["stop"], "stop", cancellationToken).ConfigureAwait(false);
        }

        InstanceProcess after = await SettleAsync(instance, RunState.Stopped, cancellationToken).ConfigureAwait(false);
        if (after.State == RunState.Running)
            throw new OperationException(ErrorCodes.Failed, $"'{instance.Id}' is still running after it was stopped");

        await CloseFirewallAsync(instance.Id, config, cancellationToken).ConfigureAwait(false);

        bool moved = before.State == RunState.Running;
        if (moved && announce) host.Events.Append(new Stopped { InstanceName = instance.Id });

        return new LifecycleReport
        {
            Id = instance.Id,
            Action = "stop",
            State = after.State,
            Changed = moved,
            Via = viaWatchdog ? "watchdog" : "script",
            Supervised = false,
        };
    }

    /// <summary>Whether the watchdog is configured, present and ready to take a native instance.</summary>
    public async Task<bool> WatchdogReadyAsync(InstanceConfig config, CancellationToken cancellationToken)
    {
        if (config.Runtime != BlueprintRuntime.Native || !host.Settings.Watchdog.Enabled || !host.Watchdog.SocketPresent) return false;

        WatchdogHealth health = await host.Watchdog.HealthAsync(cancellationToken).ConfigureAwait(false);
        return health.Reachable && health.Ready;
    }

    private async Task<bool> SupervisedByWatchdogAsync(string id, InstanceConfig config, CancellationToken cancellationToken)
    {
        if (!await WatchdogReadyAsync(config, cancellationToken).ConfigureAwait(false)) return false;

        try
        {
            InstanceState? state = await host.Watchdog.StatusAsync(id, cancellationToken).ConfigureAwait(false);
            return state is { Populated: true };
        }
        catch (WatchdogUnavailableException)
        {
            return false;
        }
    }

    private static OperationException RefusalOf(ActionResult result) => result.Refusal switch
    {
        ActionRefusal.NoRoom => new OperationException(
            ErrorCodes.InsufficientMemory, $"the node has no room to start the instance: {result.Message}", ExitCodes.InsufficientMemory),
        ActionRefusal.InstanceLocked => new TransferLockedException(result.Instance, "start"),
        _ => new OperationException(ErrorCodes.Failed, $"the watchdog did not start '{result.Instance}': {result.Message}"),
    };

    /// <summary>Measures until the run state is the wanted one, or the settle time passes. The last measurement is returned.</summary>
    private async Task<InstanceProcess> SettleAsync(InstanceDescription instance, RunState wanted, CancellationToken cancellationToken)
    {
        long started = System.Diagnostics.Stopwatch.GetTimestamp();
        while (true)
        {
            InstanceProcess process = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);
            if (process.State == wanted || System.Diagnostics.Stopwatch.GetElapsedTime(started) >= host.SettleTimeout) return process;
            await Task.Delay(SettleStep, cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task OpenFirewallAsync(string id, InstanceConfig config, CancellationToken cancellationToken)
    {
        if (!config.EnableFirewallManagement) return;

        IReadOnlyList<PortRange> ports = PortSpecs.Parse(config.Ports);
        if (ports.Count == 0) return;

        FirewallVerdict verdict = await host.Firewall.EnsureOpenAsync(id, ports, host.Events.Provenance, cancellationToken).ConfigureAwait(false);
        verdict.ThrowIfRefused($"opening the ports of '{id}'");
    }

    internal async Task CloseFirewallAsync(string id, InstanceConfig config, CancellationToken cancellationToken)
    {
        if (!config.EnableFirewallManagement) return;

        FirewallVerdict verdict = await host.Firewall.RemoveAsync(id, host.Events.Provenance, cancellationToken).ConfigureAwait(false);
        verdict.ThrowIfRefused($"closing the ports of '{id}'");
    }
}
