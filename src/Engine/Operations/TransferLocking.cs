using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Takes and releases the transfer lock. Taking it records the autostart flag the instance had and
/// switches boot autostart off, which is all it takes to keep the watchdog from starting the instance;
/// releasing it restores the flag. The lock file is written before autostart is touched, so a lock that is
/// interrupted part-way is a lock that can be released and restored.
/// </summary>
public sealed class TransferLocking(OperationHost host)
{
    /// <summary>
    /// Whether an instance starts at boot: the watchdog's boot set is the only autostart there is. A host
    /// that runs no watchdog has no autostart, so the honest answer there is false. A host whose watchdog
    /// socket exists but does not answer has an answer that cannot be read, and that is an error and not a guess.
    /// </summary>
    /// <exception cref="OperationException">The watchdog is expected here and does not answer.</exception>
    public async Task<bool> ReadAutostartAsync(InstanceConfig config, string id, CancellationToken cancellationToken)
    {
        if (config.Runtime != BlueprintRuntime.Native) return false;
        if (await host.Lifecycle.WatchdogReadyAsync(config, cancellationToken).ConfigureAwait(false))
        {
            try
            {
                return (await host.Watchdog.EnabledAsync(cancellationToken).ConfigureAwait(false)).Contains(id, StringComparer.Ordinal);
            }
            catch (WatchdogUnavailableException ex)
            {
                throw new OperationException(ErrorCodes.Failed, $"whether '{id}' starts at boot cannot be read: {ex.Message}", inner: ex);
            }
        }

        if (host.Settings.Watchdog.Enabled && host.Watchdog.SocketPresent)
            throw new OperationException(ErrorCodes.Failed, $"the watchdog is present and not ready, so whether '{id}' starts at boot cannot be read");
        return false;
    }

    /// <summary>
    /// Takes the lock, or confirms that this token already holds it. Runs under the instance's lock.
    /// </summary>
    /// <returns>True when this call placed the lock; false when the token already held it.</returns>
    /// <exception cref="TransferLockedException">Another token holds the lock.</exception>
    public async Task<bool> TakeAsync(InstanceDescription instance, string token, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.Config(instance);
        if (!TransferLock.IsValidToken(token))
            throw OperationException.Invalid("a lock token is 1 to 128 characters of letters, digits and _ . : @ -");

        string? holder = TransferLock.Holder(instance.Layout);
        if (holder is not null)
        {
            if (string.Equals(holder, token, StringComparison.Ordinal)) return false;
            throw new TransferLockedException(instance.Id, "lock");
        }

        bool autostart = await ReadAutostartAsync(config, instance.Id, cancellationToken).ConfigureAwait(false);
        TransferLock.Place(instance.Layout, token, autostart);

        if (autostart)
        {
            try
            {
                ActionResult result = await host.Watchdog.DisableAsync(instance.Id, cancellationToken).ConfigureAwait(false);
                if (!result.Ok) throw new OperationException(ErrorCodes.Failed, $"the watchdog did not switch autostart off for '{instance.Id}': {result.Message}");
            }
            catch (Exception ex) when (ex is OperationException or WatchdogUnavailableException)
            {
                TransferLock.Delete(instance.Layout);
                throw ex is WatchdogUnavailableException
                    ? new OperationException(ErrorCodes.Failed, $"autostart of '{instance.Id}' could not be switched off: {ex.Message}", inner: ex)
                    : ex;
            }
        }

        host.Logger("transfer").LogInformation("Locked {Id} for transfer {Token} (autostart was {Autostart})", instance.Id, token, autostart);
        return true;
    }

    /// <summary>
    /// Releases the lock and restores the autostart flag it found. An instance that is not locked is released.
    /// Runs under the instance's lock.
    /// </summary>
    /// <param name="instance">The instance.</param>
    /// <param name="token">The holder's token; null releases whoever holds it.</param>
    /// <param name="cancellationToken">Cancellation of the command.</param>
    /// <returns>Whether there was a lock to release.</returns>
    public async Task<bool> ReleaseAsync(InstanceDescription instance, string? token, CancellationToken cancellationToken)
    {
        string? holder = TransferLock.Holder(instance.Layout);
        if (holder is null) return false;
        if (token is not null && !string.Equals(holder, token, StringComparison.Ordinal))
            throw new TransferLockedException(instance.Id, "unlock");

        TransferLockRecord? record = null;
        try
        {
            record = TransferLock.Read(instance.Layout);
        }
        catch (EngineException ex)
        {
            host.Logger("transfer").LogWarning("The lock on {Id} cannot be read ({Problem}); releasing it without restoring autostart", instance.Id, ex.Message);
        }

        if (record is { Autostart: true } && instance.Config is { } config && config.Runtime == BlueprintRuntime.Native)
        {
            try
            {
                ActionResult result = await host.Watchdog.EnableAsync(instance.Id, cancellationToken).ConfigureAwait(false);
                if (!result.Ok)
                    throw new OperationException(ErrorCodes.Failed, $"autostart of '{instance.Id}' could not be restored: {result.Message}; the lock is kept");
            }
            catch (WatchdogUnavailableException ex)
            {
                throw new OperationException(ErrorCodes.Failed, $"autostart of '{instance.Id}' could not be restored: {ex.Message}; the lock is kept", inner: ex);
            }
        }

        TransferLock.Delete(instance.Layout);
        return true;
    }
}
