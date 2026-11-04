using System.CommandLine;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Operations;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>The <c>blueprint</c> noun, write side: create, update and delete a user blueprint.</summary>
internal static class BlueprintWriteCommands
{
    public static void AddTo(Command blueprint, CommandHost host)
    {
        blueprint.Subcommands.Add(Write(host, "create", "Add a user blueprint from a YAML file or standard input.", update: false));
        blueprint.Subcommands.Add(Write(host, "update", "Replace a user blueprint from a YAML file or standard input.", update: true));

        var name = new Argument<string>("blueprint") { Description = "The user blueprint's file name without .bp.yaml." };
        blueprint.Subcommands.Add(new Command("delete", "Remove a user blueprint; a system blueprint it shadowed shows again.") { name }
            .Act(host, "blueprint delete", context =>
            {
                string key = context.Parse.GetValue(name)!;
                if (context.Confirm($"Delete the user blueprint '{key}'?") is { } declined) return Task.FromResult(declined);

                BlueprintWriteReport report = new BlueprintWriter(context.Services.Operations).Delete(key);
                return Task.FromResult<Outcome>(new Result<BlueprintWriteReport>(
                    report, EngineJsonContext.Default.BlueprintWriteReport,
                    r => $"{r.Name} deleted" + (r.SystemBlueprintInvolved ? "; the system blueprint of that name is visible again" : string.Empty)));
            }));
    }

    private static Command Write(CommandHost host, string verb, string description, bool update)
    {
        var name = new Argument<string>("blueprint") { Description = "The file name without .bp.yaml." };
        var file = new Option<string>("--file") { Description = "The YAML file; standard input when omitted or '-'." };

        return new Command(verb, description) { name, file }
            .Act(host, $"blueprint {verb}", async context =>
            {
                string? path = context.Parse.GetValue(file);
                string yaml;
                try
                {
                    yaml = path is null or "-"
                        ? await context.Input.ReadToEndAsync(context.Cancellation).ConfigureAwait(false)
                        : await File.ReadAllTextAsync(path, context.Cancellation).ConfigureAwait(false);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    return Failure.Of(ErrorCodes.Failed, $"{path} cannot be read: {ex.Message}");
                }

                var writer = new BlueprintWriter(context.Services.Operations);
                string key = context.Parse.GetValue(name)!;
                BlueprintWriteReport report = update ? writer.Update(key, yaml) : writer.Create(key, yaml);

                return new Result<BlueprintWriteReport>(
                    report, EngineJsonContext.Default.BlueprintWriteReport,
                    r => $"{r.Name} {(update ? "updated" : "created")} at {r.Path}"
                        + (r.SystemBlueprintInvolved ? "\nit shadows the system blueprint of that name" : string.Empty));
            });
    }
}
