using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>Autostart (the watchdog's boot set) and the release of a transfer lock.</summary>
public sealed class InstanceAdminService(OperationHost host)
{
    /// <summary>Adds an instance to, or removes it from, the set the watchdog starts at boot.</summary>
    public async Task<ActionReport> SetAutostartAsync(InstanceDescription instance, bool enable, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.ForChange(instance, enable ? "enable" : "disable");
        if (config.Runtime != Contracts.Blueprints.BlueprintRuntime.Native)
            throw OperationException.Refused("autostart is the watchdog's, and the watchdog supervises native instances only");
        if (!await new LifecycleService(host).WatchdogReadyAsync(config, cancellationToken).ConfigureAwait(false))
            throw OperationException.Refused("the watchdog is not available here, so there is no autostart set to change");

        try
        {
            ActionResult result = enable
                ? await host.Watchdog.EnableAsync(instance.Id, cancellationToken).ConfigureAwait(false)
                : await host.Watchdog.DisableAsync(instance.Id, cancellationToken).ConfigureAwait(false);
            if (!result.Ok) throw new OperationException(ErrorCodes.Failed, $"the watchdog refused: {result.Message}");

            return new ActionReport
            {
                Action = enable ? "enable" : "disable",
                Subject = instance.Id,
                Message = enable ? "starts at boot" : "no longer starts at boot",
            };
        }
        catch (WatchdogUnavailableException ex)
        {
            throw new OperationException(ErrorCodes.Failed, ex.Message, inner: ex);
        }
    }

    /// <summary>Releases the lock a transfer left on an instance.</summary>
    public ActionReport Unlock(InstanceDescription instance)
    {
        Guards.Online(instance, "unlock");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        return new ActionReport
        {
            Action = "unlock",
            Subject = instance.Id,
            Message = TransferLock.Release(instance.Layout) ? "the transfer lock is released" : "the instance was not locked",
        };
    }
}
