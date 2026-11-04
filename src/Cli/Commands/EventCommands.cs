using System.CommandLine;
using System.Globalization;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Operations;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>The <c>event</c> noun: write an engine event by name, and look after the journal.</summary>
internal static class EventCommands
{
    public static Command Build(CommandHost host)
    {
        var events = new Command("event", "The engine's event journal.");

        var type = new Argument<string>("type") { Description = "An event type the engine writes, such as server.download.started." };
        var subject = new Argument<string>("subject") { Description = "The instance, blueprint or library the event is about." };
        var fields = new Option<string[]>("--field")
        {
            Description = "A payload field as Name=value; repeat for several.",
            AllowMultipleArgumentsPerToken = false,
        };
        events.Subcommands.Add(new Command("emit", "Write one of the engine's events to the journal.") { type, subject, fields }
            .Act(host, "event emit", context =>
            {
                var given = new Dictionary<string, string>(StringComparer.Ordinal);
                foreach (string field in context.Parse.GetValue(fields) ?? [])
                {
                    int equals = field.IndexOf('=', StringComparison.Ordinal);
                    if (equals <= 0) return Task.FromResult<Outcome>(Failure.Usage($"--field takes Name=value, not '{field}'"));
                    given[field[..equals]] = field[(equals + 1)..];
                }

                string name = context.Parse.GetValue(type)!;
                string about = context.Parse.GetValue(subject)!;
                EventEmission.Emit(context.Services.Operations.Events, name, about, given);

                return Task.FromResult<Outcome>(new Result<EmitReport>(
                    new EmitReport { EventType = name, Subject = about }, EngineJsonContext.Default.EmitReport, r => $"{r.EventType} written for {r.Subject}"));
            }));

        events.Subcommands.Add(Journal(host));
        return events;
    }

    private static Command Journal(CommandHost host)
    {
        var journal = new Command("journal", "The journal's segments.");

        journal.Subcommands.Add(new Command("status", "Where the journal is and what it holds.")
            .Act(host, "event journal status", context => Task.FromResult<Outcome>(new Result<JournalStatusReport>(
                Maintenance(context).Status(), EngineJsonContext.Default.JournalStatusReport, RenderStatus))));

        journal.Subcommands.Add(new Command("prune", "Delete the segments older than the retention window.")
            .Act(host, "event journal prune", context =>
            {
                JournalMaintenance maintenance = Maintenance(context);
                if (context.Confirm("Delete the journal segments past the retention window?") is { } declined) return Task.FromResult(declined);

                return Task.FromResult<Outcome>(new Result<JournalPruneReport>(
                    maintenance.Prune(), EngineJsonContext.Default.JournalPruneReport,
                    r => r.Cutoff is null
                        ? "retention is off; nothing is pruned"
                        : r.Pruned.Count == 0 ? $"no segment is older than {r.Cutoff}" : $"pruned {r.Pruned.Count}: {string.Join(", ", r.Pruned)}"));
            }));

        journal.Subcommands.Add(new Command("verify", "Check that every line of every segment is one JSON object.")
            .Act(host, "event journal verify", context =>
            {
                JournalVerifyReport report = Maintenance(context).Verify();
                return Task.FromResult<Outcome>(new Result<JournalVerifyReport>(
                    report, EngineJsonContext.Default.JournalVerifyReport, RenderVerify,
                    report.WellFormed ? ExitCodes.Success : ExitCodes.Failure));
            }));

        return journal;
    }

    private static JournalMaintenance Maintenance(CommandContext context) => new(
        context.Services.Settings.Journal.Directory, context.Services.Settings.Journal.RetentionDays, context.Services.Environment.Clock);

    private static string RenderStatus(JournalStatusReport report)
    {
        var fields = new List<(string, string)>
        {
            ("directory", report.Directory),
            ("retention", report.RetentionDays <= 0 ? "keeps everything" : $"{report.RetentionDays.ToString(CultureInfo.InvariantCulture)} days"),
            ("segments", report.Exists ? report.Segments.ToString(CultureInfo.InvariantCulture) : "0 (the directory is created by the first event)"),
        };
        if (report.Exists)
        {
            fields.Add(("events", report.Events.ToString(CultureInfo.InvariantCulture)));
            fields.Add(("size", report.SizeBytes.ToString(CultureInfo.InvariantCulture) + " bytes"));
            fields.Add(("oldest", report.Oldest ?? "-"));
            fields.Add(("newest", report.Newest ?? "-"));
            fields.Add(("writable", report.Writable ? "yes" : "no"));
        }

        return Table.Fields(fields);
    }

    private static string RenderVerify(JournalVerifyReport report) => report.WellFormed
        ? $"{report.Segments.ToString(CultureInfo.InvariantCulture)} segment(s), {report.Lines.ToString(CultureInfo.InvariantCulture)} line(s), all well-formed"
        : string.Join('\n', report.Problems.Select(p => $"{p.Segment}:{p.Line.ToString(CultureInfo.InvariantCulture)}: {p.Problem}"));
}
