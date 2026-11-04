using TheKrystalShip.KGSM.Engine.Instances;
using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Backups;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Backup writes. The archive itself (create and restore) is the instance's script's, so it works with the
/// binary absent; the binary brackets the run, journals the archives it wrote, and does the bookkeeping
/// that needs no game knowledge (delete, prune). Every one is refused on an instance a transfer holds.
/// </summary>
public sealed partial class BackupService(OperationHost host)
{
    public async Task<BackupCreateReport> CreateAsync(
        InstanceDescription instance, BackupReason reason, BackupRetention retention, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.ForChange(instance, "backup create");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        host.Events.Append(new BackupStarted { InstanceName = instance.Id });
        try
        {
            InstanceProcess process = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);
            ProcessResult result = await host.Script.RequireAsync(
                instance,
                ["create-backup", "--run-state", RunStateWord(process.State), "--reason", Wire(reason), "--retention", Wire(retention)],
                "backup create", cancellationToken).ConfigureAwait(false);

            string id = result.LastOutputLine;
            Backup backup = BackupReader.Find(config.BackupsDirectory, id)
                ?? throw new OperationException(ErrorCodes.Failed, $"the script reported the backup '{id}' and it is not in {config.BackupsDirectory}");

            host.Events.Append(new BackupCreated { InstanceName = instance.Id, Source = backup.Id, Version = backup.Version ?? "unknown" });
            return new BackupCreateReport { Backup = backup };
        }
        finally
        {
            host.Events.Append(new BackupFinished { InstanceName = instance.Id });
        }
    }

    public async Task<BackupRestoreReport> RestoreAsync(InstanceDescription instance, string id, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.ForChange(instance, "backup restore");
        Backup backup = Require(config, id);
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        InstanceProcess process = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);
        if (process.State == RunState.Running)
            throw new OperationException(ErrorCodes.Running, $"'{instance.Id}' is running; stop it before restoring over its data", ExitCodes.InstanceRunning);
        if (process.State == RunState.Unknown)
            throw OperationException.Refused($"whether '{instance.Id}' is running cannot be measured ({process.Detail ?? "no answer"})");

        HashSet<string> known = [.. BackupReader.List(config.BackupsDirectory).Backups.Select(b => b.Id)];

        host.Events.Append(new RestoreStarted { InstanceName = instance.Id });
        try
        {
            await host.Script.RequireAsync(instance, ["restore-backup", id, "--run-state", "inactive"], "backup restore", cancellationToken).ConfigureAwait(false);

            string? safety = new UpdateService(host).RecordNewBackups(instance, config, known);
            host.Events.Append(new BackupRestored { InstanceName = instance.Id, Source = backup.Id, Version = backup.Version ?? "unknown" });
            return new BackupRestoreReport { Restored = backup.Id, SafetyBackup = safety };
        }
        finally
        {
            host.Events.Append(new RestoreFinished { InstanceName = instance.Id });
        }
    }

    public void Delete(InstanceDescription instance, string id)
    {
        InstanceConfig config = Guards.ForChange(instance, "backup delete");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        Backup backup = Require(config, id);
        Directory.Delete(Path.Combine(config.BackupsDirectory, backup.Id), recursive: true);
        host.Events.Append(new BackupDeleted { InstanceName = instance.Id, Source = backup.Id });
    }

    /// <summary>
    /// Deletes the backups beyond the newest <paramref name="keep"/> prunable ones. A pinned backup is never
    /// deleted and never takes a slot, and neither does the newest <c>pre-update</c> backup, which is the
    /// rollback point an update took on its way in.
    /// </summary>
    public BackupPruneReport Prune(InstanceDescription instance, int keep)
    {
        InstanceConfig config = Guards.ForChange(instance, "backup prune");
        if (keep < 1) throw OperationException.Invalid("--keep is at least 1");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        IReadOnlyList<Backup> all = BackupReader.List(config.BackupsDirectory).Backups;
        int pinned = all.Count(b => b.IsPinned);
        List<Backup> window = [.. all.Where(b => !b.IsPinned)];

        int rollback = window.FindIndex(b => b.Reason == BackupReason.PreUpdate);
        if (rollback >= 0) window.RemoveAt(rollback);

        var deleted = new List<string>();
        foreach (Backup backup in window.Skip(keep))
        {
            Directory.Delete(Path.Combine(config.BackupsDirectory, backup.Id), recursive: true);
            deleted.Add(backup.Id);
        }

        // A sweep that removed nothing has nothing to record.
        if (deleted.Count > 0)
            host.Events.Append(new BackupsPruned { InstanceName = instance.Id, Deleted = deleted.Count, Kept = keep, Pinned = pinned });

        return new BackupPruneReport { Deleted = deleted, Kept = keep, Pinned = pinned };
    }

    public async Task<ActionReport> PinAsync(InstanceDescription instance, string id, bool pin, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.ForChange(instance, pin ? "backup pin" : "backup unpin");
        Backup backup = Require(config, id);
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        await host.Script.RequireAsync(instance, [pin ? "pin-backup" : "unpin-backup", backup.Id], pin ? "backup pin" : "backup unpin", cancellationToken)
            .ConfigureAwait(false);

        if (pin) host.Events.Append(new BackupPinned { InstanceName = instance.Id, Source = backup.Id });
        else host.Events.Append(new BackupUnpinned { InstanceName = instance.Id, Source = backup.Id });

        return new ActionReport { Action = pin ? "pin" : "unpin", Subject = backup.Id, Message = pin ? "kept out of prune's reach" : "handed back to prune" };
    }

    private static Backup Require(InstanceConfig config, string id)
    {
        if (!IdPattern().IsMatch(id)) throw OperationException.Invalid($"'{id}' is not a backup id");
        return BackupReader.Find(config.BackupsDirectory, id) ?? throw OperationException.NotFound($"No backup '{id}' exists for '{config.Name}'.");
    }

    private static string RunStateWord(RunState state) => state switch
    {
        RunState.Running => "active",
        RunState.Stopped => "inactive",
        _ => "unknown",
    };

    /// <summary>A reason as the script spells it.</summary>
    public static string Wire(BackupReason reason) => reason switch
    {
        BackupReason.Manual => "manual",
        BackupReason.Scheduled => "scheduled",
        BackupReason.PreUpdate => "pre-update",
        BackupReason.PreRestore => "pre-restore",
        _ => "incident",
    };

    public static string Wire(BackupRetention retention) => retention == BackupRetention.Pinned ? "pinned" : "prunable";

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$")]
    private static partial Regex IdPattern();
}
