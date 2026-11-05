using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>Autostart (the watchdog's boot set), the instance note and the release of a transfer lock.</summary>
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

            if (enable) host.Events.Append(new AutostartEnabled { InstanceName = instance.Id });
            else host.Events.Append(new AutostartDisabled { InstanceName = instance.Id });

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

    /// <summary>
    /// Writes the instance's note, or clears it when the body is empty. The author is the engine's actor and
    /// the time is the engine's clock; a caller supplies neither.
    /// </summary>
    public NoteReport SetNote(InstanceDescription instance, string? body)
    {
        InstanceConfig config = Guards.Config(instance);
        Guards.Online(instance, "note");
        TransferLock.Require(instance, "note");

        string clean = InstanceNote.Sanitize(body);
        if (clean.Length > InstanceNote.MaxLength)
            throw OperationException.Invalid($"the note is {clean.Length} characters; the longest is {InstanceNote.MaxLength}");

        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        if (clean.Length == 0)
        {
            bool had = config.Note is not null || config.NoteUpdatedBy is not null || config.NoteUpdatedAt is not null;
            if (had)
            {
                ContractFile.Write(
                    instance.Layout.ConfigFile, config with { Note = null, NoteUpdatedBy = null, NoteUpdatedAt = null },
                    EngineJsonContext.Default.InstanceConfig);
                host.Events.Append(new ConfigChanged { InstanceName = instance.Id, Key = "note" });
            }

            return new NoteReport { Instance = instance.Id, Changed = had };
        }

        string? actor = host.Events.Provenance.Normalized().Actor;
        DateTimeOffset now = host.Clock.GetUtcNow();
        InstanceConfig updated = config with { Note = clean, NoteUpdatedBy = actor, NoteUpdatedAt = now };
        bool changed = !string.Equals(config.Note, clean, StringComparison.Ordinal);

        ContractFile.Write(instance.Layout.ConfigFile, updated, EngineJsonContext.Default.InstanceConfig);
        if (changed) host.Events.Append(new ConfigChanged { InstanceName = instance.Id, Key = "note" });

        return new NoteReport { Instance = instance.Id, Note = clean, UpdatedBy = actor, UpdatedAt = now, Changed = changed };
    }

    /// <summary>Releases the lock a transfer left on an instance and restores the autostart flag the lock switched off.</summary>
    /// <param name="instance">The instance.</param>
    /// <param name="token">The holder's token; null releases the lock whoever holds it.</param>
    /// <param name="cancellationToken">Cancellation of the command.</param>
    public async Task<ActionReport> UnlockAsync(InstanceDescription instance, string? token, CancellationToken cancellationToken)
    {
        Guards.Online(instance, "unlock");
        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        bool released = await new TransferLocking(host).ReleaseAsync(instance, token, cancellationToken).ConfigureAwait(false);
        return new ActionReport
        {
            Action = "unlock",
            Subject = instance.Id,
            Message = released ? "the transfer lock is released" : "the instance was not locked",
        };
    }
}
