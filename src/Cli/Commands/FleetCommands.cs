using TheKrystalShip.KGSM.ComponentConfig;
using System.CommandLine;
using System.Globalization;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Backups;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Network;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>The <c>library</c>, <c>backup</c> and <c>port</c> nouns, read side.</summary>
internal static class FleetCommands
{
    public static Command Library(CommandHost host)
    {
        var library = new Command("library", "Storage roots instances are placed in.");
        library.Subcommands.Add(LibraryList(host));
        FleetWriteCommands.AddLibraryVerbs(library, host);
        return library;
    }

    [Action("kgsm:server.read", "See servers", DeclaredEffect.Read, DeclaredScope.Instance)]
    private static Command LibraryList(CommandHost host) =>
        new Command("list", "Every library with its state, free and total bytes, and instance count.")
            .Act(host, "library list", context =>
            {
                IReadOnlyList<Library> libraries = context.Services.Libraries.List(context.Services.Instances.Registered());
                return Task.FromResult<Outcome>(new Result<IReadOnlyList<Library>>(
                    libraries, EngineJsonContext.Default.IReadOnlyListLibrary, RenderLibraries));
            });

    public static Command Backup(CommandHost host)
    {
        var backup = new Command("backup", "Instance backups.");
        backup.Subcommands.Add(BackupList(host));
        FleetWriteCommands.AddBackupVerbs(backup, host);
        return backup;
    }

    [Action("kgsm:server.backups.read", "See backups", DeclaredEffect.Read, DeclaredScope.Instance)]
    private static Command BackupList(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        return new Command("list", "An instance's backups, newest first.") { reference }
            .Act(host, "backup list", context =>
            {
                InstanceDescription? instance = CommandBuilder.Resolve(context, context.Parse.GetValue(reference)!, out Outcome? failure);
                if (instance is null) return Task.FromResult(failure!);
                if (instance.Config is null)
                    return Task.FromResult<Outcome>(Failure.Of(ErrorCodes.Failed, instance.ConfigProblem ?? "the instance's config cannot be read"));

                BackupListing listing = BackupReader.List(instance.Config.BackupsDirectory);
                return Task.FromResult<Outcome>(new Result<BackupListing>(listing, EngineJsonContext.Default.BackupListing, RenderBackups));
            });
    }

    public static Command Port(CommandHost host)
    {
        var port = new Command("port", "Ports instances declare.");
        port.Subcommands.Add(PortList(host));
        port.Subcommands.Add(PortConflicts(host));
        return port;
    }

    [Action("kgsm:server.read", "See servers", DeclaredEffect.Read, DeclaredScope.Instance)]
    private static Command PortList(CommandHost host) =>
        new Command("list", "Every port range every instance declares.")
            .Act(host, "port list", context =>
            {
                IReadOnlyList<PortUse> used = PortSpecs.Used(context.Services.Instances.List());
                return Task.FromResult<Outcome>(new Result<IReadOnlyList<PortUse>>(
                    used, EngineJsonContext.Default.IReadOnlyListPortUse, RenderUsed));
            });

    [Action("kgsm:server.read", "See servers", DeclaredEffect.Read, DeclaredScope.Instance)]
    private static Command PortConflicts(CommandHost host) =>
        new Command("conflicts", "Instances whose declared ports overlap.")
            .Act(host, "port conflicts", context =>
            {
                IReadOnlyList<PortConflict> conflicts = PortSpecs.Conflicts(PortSpecs.Used(context.Services.Instances.List()));
                return Task.FromResult<Outcome>(new Result<IReadOnlyList<PortConflict>>(
                    conflicts, EngineJsonContext.Default.IReadOnlyListPortConflict, RenderConflicts));
            });

    private static string RenderLibraries(IReadOnlyList<Library> libraries) => libraries.Count == 0
        ? "No libraries are registered."
        : Table.Render(
            ["NAME", "STATE", "INSTANCES", "FREE", "TOTAL", "PATH"],
            libraries.Select(l => new[]
            {
                l.Name,
                l.State.ToString().ToLowerInvariant(),
                l.InstanceCount.ToString(CultureInfo.InvariantCulture),
                Bytes(l.FreeBytes),
                Bytes(l.TotalBytes),
                l.Path,
            }));

    private static string RenderBackups(BackupListing listing)
    {
        string table = listing.Backups.Count == 0
            ? "No backups."
            : Table.Render(
                ["ID", "CREATED", "REASON", "RETENTION", "SIZE"],
                listing.Backups.Select(b => new[]
                {
                    b.Id,
                    b.CreatedAt.UtcDateTime.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
                    b.Reason is { } reason ? Reason(reason) : "-",
                    b.Retention.ToString().ToLowerInvariant(),
                    Bytes(b.SizeBytes),
                }));

        return listing.Skipped.Count == 0
            ? table
            : table + "\n\nskipped:\n" + string.Join('\n', listing.Skipped.Select(s => $"  {s.Directory}: {s.Reason}"));
    }

    private static string Reason(BackupReason reason) => reason switch
    {
        BackupReason.Manual => "manual",
        BackupReason.Scheduled => "scheduled",
        BackupReason.PreUpdate => "pre-update",
        BackupReason.PreRestore => "pre-restore",
        BackupReason.Incident => "incident",
        _ => reason.ToString().ToLowerInvariant(),
    };

    private static string RenderUsed(IReadOnlyList<PortUse> used) => used.Count == 0
        ? "No instance declares a port."
        : Table.Render(
            ["PORT", "PROTOCOL", "INSTANCE"],
            used.Select(u => new[] { Span(u.Start, u.End), u.Protocol.ToString().ToLowerInvariant(), u.Instance }));

    private static string RenderConflicts(IReadOnlyList<PortConflict> conflicts) => conflicts.Count == 0
        ? "No instances share a port."
        : Table.Render(
            ["PORT", "PROTOCOL", "INSTANCES"],
            conflicts.Select(c => new[] { Span(c.Start, c.End), c.Protocol.ToString().ToLowerInvariant(), string.Join(", ", c.Instances) }));

    private static string Span(int start, int end) =>
        start == end ? start.ToString(CultureInfo.InvariantCulture) : $"{start}-{end}";

    private static string Bytes(long? bytes)
    {
        if (bytes is not { } value) return "-";
        string[] units = ["B", "KiB", "MiB", "GiB", "TiB"];
        double size = value;
        int unit = 0;
        while (size >= 1024 && unit < units.Length - 1)
        {
            size /= 1024;
            unit++;
        }

        return unit == 0 ? $"{value} B" : size.ToString("0.#", CultureInfo.InvariantCulture) + " " + units[unit];
    }
}
