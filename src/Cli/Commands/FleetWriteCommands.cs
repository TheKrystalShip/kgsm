using TheKrystalShip.KGSM.ComponentConfig;
using System.CommandLine;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Operations;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>The <c>backup</c> and <c>library</c> nouns, write side.</summary>
internal static class FleetWriteCommands
{
    public static void AddBackupVerbs(Command backup, CommandHost host)
    {
        backup.Subcommands.Add(Create(host));
        backup.Subcommands.Add(Restore(host));
        backup.Subcommands.Add(Delete(host));
        backup.Subcommands.Add(Prune(host));
        backup.Subcommands.Add(Pin(host, "pin", pinned: true, "Keep a backup out of prune's reach."));
        backup.Subcommands.Add(Pin(host, "unpin", pinned: false, "Hand a pinned backup back to prune."));
    }

    public static void AddLibraryVerbs(Command library, CommandHost host)
    {
        library.Subcommands.Add(Add(host));
        library.Subcommands.Add(Remove(host));
        library.Subcommands.Add(Rename(host));
    }

    [Action("kgsm:server.backups.create", "Back up servers", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Create(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var reason = new Option<string>("--reason") { Description = "Why: manual, scheduled, pre-update, pre-restore or incident.", DefaultValueFactory = _ => "manual" };
        var retention = new Option<string>("--retention") { Description = "prunable, or pinned to keep it out of prune's reach.", DefaultValueFactory = _ => "prunable" };

        return new Command("create", "Take a backup of an instance.") { reference, reason, retention }
            .ActOnInstance(host, "backup create", reference, async (context, instance) =>
            {
                if (!TryReason(context.Parse.GetValue(reason)!, out BackupReason why))
                    return Failure.Usage("--reason is manual, scheduled, pre-update, pre-restore or incident");
                if (!TryRetention(context.Parse.GetValue(retention)!, out BackupRetention keep))
                    return Failure.Usage("--retention is prunable or pinned");

                BackupCreateReport report = await new BackupService(context.Services.Operations)
                    .CreateAsync(instance, why, keep, context.Cancellation).ConfigureAwait(false);
                return new Result<BackupCreateReport>(
                    report, EngineJsonContext.Default.BackupCreateReport, r => r.Backup.Id);
            });
    }

    [Action("kgsm:server.backups.restore", "Restore backups", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Restore(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var id = new Argument<string>("backup") { Description = "The backup's id." };
        return new Command("restore", "Replace an instance's data with a backup, after a safety backup of what is there.") { reference, id }
            .ActOnInstance(host, "backup restore", reference, async (context, instance) =>
            {
                string backupId = context.Parse.GetValue(id)!;
                if (context.Confirm($"Restore '{backupId}' over the data of '{instance.Id}'?") is { } declined) return declined;

                BackupRestoreReport report = await new BackupService(context.Services.Operations)
                    .RestoreAsync(instance, backupId, context.Cancellation).ConfigureAwait(false);
                return new Result<BackupRestoreReport>(
                    report, EngineJsonContext.Default.BackupRestoreReport,
                    r => $"{r.Restored} restored" + (r.SafetyBackup is { } safety ? $"\nsafety backup of the data it replaced: {safety}" : string.Empty));
            });
    }

    [Action("kgsm:server.backups.manage", "Pin, prune and delete backups", DeclaredEffect.Write, DeclaredScope.Instance)]
    private static Command Delete(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var id = new Argument<string>("backup") { Description = "The backup's id." };
        return new Command("delete", "Delete one backup.") { reference, id }
            .ActOnInstance(host, "backup delete", reference, (context, instance) =>
            {
                string backupId = context.Parse.GetValue(id)!;
                if (context.Confirm($"Delete the backup '{backupId}'?") is { } declined) return Task.FromResult(declined);

                new BackupService(context.Services.Operations).Delete(instance, backupId);
                return Task.FromResult<Outcome>(new Result<ActionReport>(
                    new ActionReport { Action = "delete", Subject = backupId, Message = "deleted" },
                    EngineJsonContext.Default.ActionReport, r => $"{r.Subject} deleted"));
            });
    }

    [Action("kgsm:server.backups.manage", "Pin, prune and delete backups", DeclaredEffect.Write, DeclaredScope.Instance)]
    private static Command Prune(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var keep = new Option<int?>("--keep") { Description = "How many prunable backups to keep; the instance's backupRetention when omitted." };
        return new Command("prune", "Delete the backups beyond the newest few; pinned ones and the newest pre-update one are never deleted.") { reference, keep }
            .ActOnInstance(host, "backup prune", reference, (context, instance) =>
            {
                int window = context.Parse.GetValue(keep) ?? instance.Config?.BackupRetention ?? 3;
                if (context.Confirm($"Prune the backups of '{instance.Id}', keeping the newest {window}?") is { } declined) return Task.FromResult(declined);

                BackupPruneReport report = new BackupService(context.Services.Operations).Prune(instance, window);
                return Task.FromResult<Outcome>(new Result<BackupPruneReport>(
                    report, EngineJsonContext.Default.BackupPruneReport,
                    r => r.Deleted.Count == 0
                        ? $"nothing to prune (keeping {r.Kept}, {r.Pinned} pinned)"
                        : $"pruned {r.Deleted.Count}: {string.Join(", ", r.Deleted)}"));
            });
    }

    [Action("kgsm:server.backups.manage", "Pin, prune and delete backups", DeclaredEffect.Write, DeclaredScope.Instance)]
    private static Command Pin(CommandHost host, string verb, bool pinned, string description)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var id = new Argument<string>("backup") { Description = "The backup's id." };
        return new Command(verb, description) { reference, id }
            .ActOnInstance(host, $"backup {verb}", reference, async (context, instance) =>
            {
                ActionReport report = await new BackupService(context.Services.Operations)
                    .PinAsync(instance, context.Parse.GetValue(id)!, pinned, context.Cancellation).ConfigureAwait(false);
                return new Result<ActionReport>(report, EngineJsonContext.Default.ActionReport, r => $"{r.Subject}: {r.Message}");
            });
    }

    [Action("kgsm:libraries.manage", "Add, rename and remove libraries", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command Add(CommandHost host)
    {
        var name = new Argument<string>("name") { Description = "Lowercase letters, digits and hyphens." };
        var path = new Argument<string>("path") { Description = "The library's root directory; created when it is not there." };
        return new Command("add", "Register a library.") { name, path }
            .Act(host, "library add", context =>
            {
                LibraryChangeReport report = new LibraryService(context.Services.Operations).Add(context.Parse.GetValue(name)!, context.Parse.GetValue(path)!);
                return Task.FromResult<Outcome>(new Result<LibraryChangeReport>(
                    report, EngineJsonContext.Default.LibraryChangeReport, r => $"{r.Name} registered at {r.Path}"));
            });
    }

    [Action("kgsm:libraries.manage", "Add, rename and remove libraries", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command Remove(CommandHost host)
    {
        var name = new Argument<string>("name") { Description = "The library to deregister." };
        var force = new Option<bool>("--force") { Description = "Deregister it and leave the instances in it unregistered." };
        var drain = new Option<string>("--drain") { Description = "Move its instances to this library first, one at a time." };
        return new Command("remove", "Deregister a library. Its files are never deleted.") { name, force, drain }
            .Act(host, "library remove", async context =>
            {
                string target = context.Parse.GetValue(name)!;
                if (context.Confirm($"Deregister the library '{target}'?") is { } declined) return declined;

                LibraryChangeReport report = await new LibraryService(context.Services.Operations)
                    .RemoveAsync(target, context.Parse.GetValue(force), context.Parse.GetValue(drain), context.Cancellation).ConfigureAwait(false);
                return new Result<LibraryChangeReport>(
                    report, EngineJsonContext.Default.LibraryChangeReport,
                    r => $"{r.Name} deregistered; its files are left at {r.Path}"
                        + (r.Instances.Count > 0 ? $"\ninstances: {string.Join(", ", r.Instances)}" : string.Empty));
            });
    }

    [Action("kgsm:libraries.manage", "Add, rename and remove libraries", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command Rename(CommandHost host)
    {
        var from = new Argument<string>("name") { Description = "The library's current name." };
        var to = new Argument<string>("new-name") { Description = "Its new name." };
        return new Command("rename", "Rename a library; no instance is touched.") { from, to }
            .Act(host, "library rename", context =>
            {
                LibraryChangeReport report = new LibraryService(context.Services.Operations).Rename(context.Parse.GetValue(from)!, context.Parse.GetValue(to)!);
                return Task.FromResult<Outcome>(new Result<LibraryChangeReport>(
                    report, EngineJsonContext.Default.LibraryChangeReport, r => $"renamed to {r.Name}"));
            });
    }

    private static bool TryReason(string text, out BackupReason reason)
    {
        BackupReason? parsed = text switch
        {
            "manual" => BackupReason.Manual,
            "scheduled" => BackupReason.Scheduled,
            "pre-update" => BackupReason.PreUpdate,
            "pre-restore" => BackupReason.PreRestore,
            "incident" => BackupReason.Incident,
            _ => null,
        };
        reason = parsed.GetValueOrDefault();
        return parsed is not null;
    }

    private static bool TryRetention(string text, out BackupRetention retention)
    {
        retention = text == "pinned" ? BackupRetention.Pinned : BackupRetention.Prunable;
        return text is "pinned" or "prunable";
    }
}
