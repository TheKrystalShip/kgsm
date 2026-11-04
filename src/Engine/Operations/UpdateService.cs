using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Backups;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Updates an instance and checks whether an update exists. The update itself runs in the instance's
/// script, which takes the backup first, downloads, deploys and records the version, reporting its phases
/// back through the binary's own <c>event emit</c>. The binary brackets the run, records the backups the
/// script made and writes the outcome.
/// </summary>
public sealed class UpdateService(OperationHost host)
{
    public async Task<UpdateReport> UpdateAsync(InstanceDescription instance, CancellationToken cancellationToken)
    {
        ILogger log = host.Logger("update");
        InstanceConfig config = Guards.ForChange(instance, "update");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        host.Events.Append(new UpdateStarted { InstanceName = instance.Id });
        try
        {
            InstanceProcess process = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);
            if (config.Runtime == BlueprintRuntime.Native && process.State == RunState.Running)
                throw new OperationException(ErrorCodes.Running, $"'{instance.Id}' is running; stop it before updating", ExitCodes.InstanceRunning);

            string runState = process.State switch
            {
                RunState.Running => "active",
                RunState.Stopped => "inactive",
                _ => "unknown",
            };

            string? before = InstanceVersions.Read(instance.Layout).Current;
            HashSet<string> known = [.. BackupReader.List(config.BackupsDirectory).Backups.Select(b => b.Id)];

            List<string> arguments = ["update", "--run-state", runState];
            if (EmitCommand() is { } emit)
            {
                arguments.Add("--emit-cmd");
                arguments.Add(emit);
            }
            else
            {
                log.LogWarning("The binary's path holds whitespace, which the script cannot split; the update's download and deploy phases are not journaled");
            }

            ProcessResult result = await host.Script.RequireAsync(instance, arguments, "update", cancellationToken).ConfigureAwait(false);
            string[] outcome = result.LastOutputLine.Split(' ', 2, StringSplitOptions.TrimEntries);

            string? taken = RecordNewBackups(instance, config, known);

            if (outcome[0] == "updated" && outcome.Length == 2)
            {
                string after = outcome[1];
                host.Events.Append(new Updated { InstanceName = instance.Id, OldVersion = before ?? "unknown", NewVersion = after });
                return new UpdateReport { Id = instance.Id, Outcome = "updated", PreviousVersion = before, Version = after, Backup = taken };
            }

            if (outcome[0] == "current" && outcome.Length == 2)
                return new UpdateReport { Id = instance.Id, Outcome = "current", PreviousVersion = before, Version = outcome[1], Backup = taken };

            throw new OperationException(ErrorCodes.Failed, $"the update of '{instance.Id}' reported '{result.LastOutputLine}', which is neither 'updated <version>' nor 'current <version>'");
        }
        catch (Exception)
        {
            host.Events.Append(new UpdateFailed { InstanceName = instance.Id });
            throw;
        }
        finally
        {
            host.Events.Append(new UpdateFinished { InstanceName = instance.Id });
        }
    }

    /// <summary>
    /// Asks upstream whether a newer version exists. With <paramref name="announce"/> the answer is recorded
    /// as the latest version and, once per new version, written as <c>server.update.available</c>.
    /// </summary>
    public async Task<UpdateCheckReport> CheckAsync(InstanceDescription instance, bool announce, CancellationToken cancellationToken)
    {
        Guards.Config(instance);
        Guards.Online(instance, "check-update");
        if (announce) TransferLock.Require(instance, "check-update --emit");

        InstanceVersion recorded = InstanceVersions.Read(instance.Layout);
        ProcessResult result = await host.Script.RunAsync(instance, ["check-update"], cancellationToken).ConfigureAwait(false);

        string[] words = result.LastOutputLine.Split(' ', 2, StringSplitOptions.TrimEntries);
        if (words[0] == "unknown" || (!result.Succeeded && words[0] != "available" && words[0] != "current"))
            return new UpdateCheckReport { Id = instance.Id, Outcome = "unknown", Current = recorded.Current, Latest = null, Announced = false };

        if (words.Length != 2 || words[0] is not ("available" or "current"))
            throw new OperationException(ErrorCodes.Failed, $"the update check of '{instance.Id}' reported '{result.LastOutputLine}'");

        string latest = words[1];
        bool announced = false;

        if (announce)
        {
            using IDisposable held = host.Locks.AcquireInstance(instance.Id);
            await host.Script.RequireAsync(instance, ["version", "--save-latest", latest], "recording the latest version", cancellationToken).ConfigureAwait(false);

            if (words[0] == "available" && !string.Equals(recorded.Latest, latest, StringComparison.Ordinal))
            {
                host.Events.Append(new UpdateAvailable
                {
                    InstanceName = instance.Id,
                    CurrentVersion = recorded.Current ?? "unknown",
                    LatestVersion = latest,
                });
                announced = true;
            }
        }

        return new UpdateCheckReport { Id = instance.Id, Outcome = words[0], Current = recorded.Current, Latest = latest, Announced = announced };
    }

    /// <summary>Writes <c>backup.created</c> for every backup that appeared while the script ran; returns the newest id.</summary>
    internal string? RecordNewBackups(InstanceDescription instance, InstanceConfig config, ISet<string> known)
    {
        string? newest = null;
        foreach (Backup backup in BackupReader.List(config.BackupsDirectory).Backups.Where(b => !known.Contains(b.Id)).OrderBy(b => b.CreatedAt))
        {
            host.Events.Append(new BackupCreated { InstanceName = instance.Id, Source = backup.Id, Version = backup.Version ?? "unknown" });
            newest = backup.Id;
        }

        return newest;
    }

    /// <summary>The command the script runs to report a phase, or null when the binary's path cannot be split on whitespace.</summary>
    private string? EmitCommand() =>
        host.BinaryPath is { Length: > 0 } path && !path.Any(char.IsWhiteSpace) ? $"{path} event emit" : null;
}
