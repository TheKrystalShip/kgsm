using TheKrystalShip.KGSM.Engine.Instances;
using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Uninstalls an instance. Whatever runs is stopped first, by whoever runs it (the watchdog for a
/// supervised native instance, the instance's own script for a container or an unsupervised process), and
/// no file is deleted while anything is running. Backups are kept unless asked to go.
/// </summary>
public sealed class UninstallService(OperationHost host)
{
    /// <param name="instance">The instance.</param>
    /// <param name="force">Lets an instance whose run state or config cannot be read be removed, and an instance in an offline library be deregistered.</param>
    /// <param name="purgeBackups">Also deletes the instance's backups.</param>
    /// <param name="transferToken">The token of the transfer that holds the instance, which passes its own lock.</param>
    /// <param name="cancellationToken">Cancellation of the command.</param>
    public async Task<UninstallReport> UninstallAsync(
        InstanceDescription instance, bool force, bool purgeBackups, string? transferToken, CancellationToken cancellationToken)
    {
        ILogger log = host.Logger("uninstall");
        bool offline = instance.LibraryState == InstanceLibraryState.Offline;

        if (offline && !force)
            throw OperationException.Refused($"the library '{instance.Library?.Name}' of '{instance.Id}' is offline; --force deregisters the instance and leaves its files");
        if (!offline) TransferLock.Require(instance, "uninstall", transferToken);
        if (!offline && instance.Config is null && !force)
            throw OperationException.Refused($"'{instance.Id}' has no readable config ({instance.ConfigProblem}); --force removes it anyway");

        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        host.Events.Append(new UninstallStarted { InstanceName = instance.Id });
        try
        {
            bool stopped = false;
            if (!offline && instance.Config is not null) stopped = await StopWhateverRunsAsync(instance, force, cancellationToken).ConfigureAwait(false);

            bool filesRemoved = false;
            if (!offline && Directory.Exists(instance.WorkingDirectory))
            {
                Directory.Delete(instance.WorkingDirectory, recursive: true);
                FileSystem.RemoveEmptyInstanceParents(instance.WorkingDirectory);
                filesRemoved = true;
                log.LogInformation("Deleted {Directory}", instance.WorkingDirectory);
            }

            host.Registry.Remove(instance.Id);

            bool backupsRemoved = false;
            if (purgeBackups && instance.Config is { } config && Directory.Exists(config.BackupsDirectory))
            {
                Directory.Delete(config.BackupsDirectory, recursive: true);
                backupsRemoved = true;
            }

            host.Events.Append(new Uninstalled { InstanceName = instance.Id, InstallNonce = instance.Config?.InstallNonce });
            return new UninstallReport { Id = instance.Id, Stopped = stopped, FilesRemoved = filesRemoved, BackupsRemoved = backupsRemoved };
        }
        catch (Exception)
        {
            host.Events.Append(new UninstallFailed { InstanceName = instance.Id });
            throw;
        }
        finally
        {
            host.Events.Append(new UninstallFinished { InstanceName = instance.Id });
        }
    }

    /// <returns>Whether something was running and was stopped.</returns>
    private async Task<bool> StopWhateverRunsAsync(InstanceDescription instance, bool force, CancellationToken cancellationToken)
    {
        InstanceProcess process = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);
        if (process.State == RunState.Unknown && !force)
        {
            throw OperationException.Refused(
                $"whether '{instance.Id}' is running cannot be measured ({process.Detail ?? "no answer"}), so no file is deleted; --force removes it anyway");
        }

        LifecycleService lifecycle = host.Lifecycle;
        bool stopped = false;
        if (process.State != RunState.Stopped)
        {
            LifecycleReport report = await lifecycle.StopCoreAsync(instance, announce: true, cancellationToken).ConfigureAwait(false);
            stopped = report.Changed;
        }

        if (await lifecycle.WatchdogReadyAsync(instance.Config!, cancellationToken).ConfigureAwait(false))
        {
            try
            {
                if (await host.Watchdog.StatusAsync(instance.Id, cancellationToken).ConfigureAwait(false) is not null)
                {
                    ActionResult forgotten = await host.Watchdog.ForgetAsync(instance.Id, cancellationToken).ConfigureAwait(false);
                    if (!forgotten.Ok) throw new OperationException(ErrorCodes.Failed, $"the watchdog still holds '{instance.Id}': {forgotten.Message}");
                }
            }
            catch (WatchdogUnavailableException ex)
            {
                host.Logger("uninstall").LogWarning("The watchdog could not be asked to forget {Id}: {Problem}", instance.Id, ex.Message);
            }
        }

        await lifecycle.CloseFirewallAsync(instance.Id, instance.Config!, cancellationToken).ConfigureAwait(false);
        return stopped;
    }
}
