using TheKrystalShip.KGSM.ComponentConfig;
using System.CommandLine;
using System.Globalization;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>The <c>blueprint</c> noun, read side: list, show, find, validate and requirements.</summary>
internal static class BlueprintCommands
{
    public static Command Build(CommandHost host)
    {
        var blueprint = new Command("blueprint", "Game server blueprints.");
        blueprint.Subcommands.Add(List(host));
        blueprint.Subcommands.Add(Show(host));
        blueprint.Subcommands.Add(Find(host));
        blueprint.Subcommands.Add(Validate(host));
        blueprint.Subcommands.Add(Requirements(host));
        BlueprintWriteCommands.AddTo(blueprint, host);
        return blueprint;
    }

    private static Argument<string> Name() =>
        new("blueprint") { Description = "The blueprint's file name without .bp.yaml." };

    [Action("kgsm:library.read", "See the blueprint catalog", DeclaredEffect.Read, DeclaredScope.Cluster)]
    private static Command List(CommandHost host)
    {
        var onlySystem = new Option<bool>("--default") { Description = "Only the blueprints that ship with the engine." };
        var onlyUser = new Option<bool>("--custom") { Description = "Only the blueprints a person added." };
        return new Command("list", "Every blueprint file, a user file shadowing a system file of the same name.") { onlySystem, onlyUser }
            .Act(host, "blueprint list", context =>
            {
                bool system = context.Parse.GetValue(onlySystem);
                bool user = context.Parse.GetValue(onlyUser);
                if (system && user) return Task.FromResult<Outcome>(Failure.Usage("--default and --custom exclude each other"));

                IReadOnlyList<BlueprintListing> listing =
                [
                    .. context.Services.Blueprints.List().Where(b =>
                        (!system || b.Tier == BlueprintTier.System) && (!user || b.Tier == BlueprintTier.User)),
                ];

                return Task.FromResult<Outcome>(new Result<IReadOnlyList<BlueprintListing>>(
                    listing, EngineJsonContext.Default.IReadOnlyListBlueprintListing, Render));
            });
    }

    [Action("kgsm:library.read", "See the blueprint catalog", DeclaredEffect.Read, DeclaredScope.Cluster)]
    private static Command Show(CommandHost host)
    {
        Argument<string> name = Name();
        return new Command("show", "A blueprint's content.") { name }
            .Act(host, "blueprint show", context =>
            {
                string key = context.Parse.GetValue(name)!;
                if (!BlueprintParser.IsValidName(key)) return Task.FromResult<Outcome>(Failure.Usage($"'{key}' is not a blueprint file name"));

                BlueprintParseResult? parsed = context.Services.Blueprints.Read(key);
                if (parsed is null) return Task.FromResult<Outcome>(Failure.NotFound($"No blueprint '{key}' exists."));
                if (parsed.Blueprint is null)
                    return Task.FromResult<Outcome>(Failure.Of(ErrorCodes.Invalid, $"Blueprint '{key}' does not validate.", ExitCodes.Failure, parsed.Validation.Errors));

                return Task.FromResult<Outcome>(new Result<Blueprint>(parsed.Blueprint, EngineJsonContext.Default.Blueprint, RenderBlueprint));
            });
    }

    [Action("kgsm:library.read", "See the blueprint catalog", DeclaredEffect.Read, DeclaredScope.Cluster)]
    private static Command Find(CommandHost host)
    {
        Argument<string> name = Name();
        return new Command("find", "Where a blueprint name resolves, with every candidate path.") { name }
            .Act(host, "blueprint find", context =>
            {
                string key = context.Parse.GetValue(name)!;
                if (!BlueprintParser.IsValidName(key)) return Task.FromResult<Outcome>(Failure.Usage($"'{key}' is not a blueprint file name"));

                BlueprintResolution resolution = context.Services.Blueprints.Find(key);
                return Task.FromResult<Outcome>(resolution.Resolved is null
                    ? Failure.NotFound($"No blueprint '{key}' exists.")
                    : new Result<BlueprintResolution>(resolution, EngineJsonContext.Default.BlueprintResolution, RenderResolution));
            });
    }

    [Action("kgsm:library.read", "See the blueprint catalog", DeclaredEffect.Read, DeclaredScope.Cluster)]
    private static Command Validate(CommandHost host)
    {
        var target = new Argument<string>("blueprint") { Description = "A blueprint's file name, or the path of a blueprint file." };
        return new Command("validate", "Check a blueprint against every rule; the verdict is printed whether or not it passes.") { target }
            .Act(host, "blueprint validate", context =>
            {
                string argument = context.Parse.GetValue(target)!;
                string path;

                if (argument.Contains('/', StringComparison.Ordinal) || argument.EndsWith(".yaml", StringComparison.Ordinal))
                {
                    path = Path.GetFullPath(argument);
                    if (!File.Exists(path)) return Task.FromResult<Outcome>(Failure.NotFound($"No blueprint file at '{path}'."));
                }
                else
                {
                    if (!BlueprintParser.IsValidName(argument)) return Task.FromResult<Outcome>(Failure.Usage($"'{argument}' is not a blueprint file name"));
                    string? resolved = context.Services.Blueprints.Find(argument).Resolved;
                    if (resolved is null) return Task.FromResult<Outcome>(Failure.NotFound($"No blueprint '{argument}' exists."));
                    path = resolved;
                }

                BlueprintValidation verdict = new BlueprintParser().ParseFile(path).Validation;
                return Task.FromResult<Outcome>(new Result<BlueprintValidation>(
                    verdict, EngineJsonContext.Default.BlueprintValidation, RenderValidation, verdict.Valid ? ExitCodes.Success : ExitCodes.Failure));
            });
    }

    [Action("kgsm:library.read", "See the blueprint catalog", DeclaredEffect.Read, DeclaredScope.Cluster)]
    private static Command Requirements(CommandHost host)
    {
        Argument<string> name = Name();
        return new Command("requirements", "What a blueprint needs from this host and whether each is present; the answer is printed whether or not it is satisfied.") { name }
            .Act(host, "blueprint requirements", context =>
            {
                string key = context.Parse.GetValue(name)!;
                if (!BlueprintParser.IsValidName(key)) return Task.FromResult<Outcome>(Failure.Usage($"'{key}' is not a blueprint file name"));

                BlueprintParseResult? parsed = context.Services.Blueprints.Read(key);
                if (parsed is null) return Task.FromResult<Outcome>(Failure.NotFound($"No blueprint '{key}' exists."));
                if (parsed.Blueprint is null)
                    return Task.FromResult<Outcome>(Failure.Of(ErrorCodes.Invalid, $"Blueprint '{key}' does not validate.", ExitCodes.Failure, parsed.Validation.Errors));

                BlueprintRequirements requirements = BlueprintRequirementRules.Evaluate(parsed.Blueprint, context.Services.Requirements);
                return Task.FromResult<Outcome>(new Result<BlueprintRequirements>(
                    requirements, EngineJsonContext.Default.BlueprintRequirements, RenderRequirements,
                    requirements.Satisfied ? ExitCodes.Success : ExitCodes.Failure));
            });
    }

    private static string Render(IReadOnlyList<BlueprintListing> listing) => listing.Count == 0
        ? "No blueprints."
        : Table.Render(
            ["BLUEPRINT", "TIER", "RUNTIME", "GAME"],
            listing.Select(b => new[]
            {
                b.Key,
                b.Tier.ToString().ToLowerInvariant(),
                b.Blueprint is { } blueprint ? blueprint.Runtime.ToString().ToLowerInvariant() : "invalid",
                b.Blueprint?.Metadata.DisplayName ?? (b.Errors.Count > 0 ? b.Errors[0] : "-"),
            }));

    private static string RenderBlueprint(Blueprint blueprint)
    {
        var fields = new List<(string, string)>
        {
            ("name", blueprint.Name),
            ("runtime", blueprint.Runtime.ToString().ToLowerInvariant()),
            ("game", CommandBuilder.Text(blueprint.Metadata.DisplayName)),
            ("description", CommandBuilder.Text(blueprint.Metadata.Description)),
            ("minimum ram", blueprint.Metadata.MinRamMb is { } min ? min.ToString(CultureInfo.InvariantCulture) + " MB" : "unknown"),
            ("base disk", blueprint.Metadata.BaseDiskMb is { } disk ? disk.ToString(CultureInfo.InvariantCulture) + " MB" : "unknown"),
        };
        if (blueprint.Native is { } native)
        {
            fields.Add(("ports", CommandBuilder.Text(native.Ports)));
            fields.Add(("executable", CommandBuilder.Text(native.ExecutableFile)));
            fields.Add(("arguments", CommandBuilder.Text(native.ExecutableArguments)));
        }

        return Table.Fields(fields);
    }

    private static string RenderResolution(BlueprintResolution resolution) =>
        $"{resolution.Resolved} ({resolution.Tier.ToString()!.ToLowerInvariant()})\n"
        + string.Join('\n', resolution.Candidates.Select(c => $"  {c.Tier.ToString().ToLowerInvariant(),-6} {(c.Exists ? "exists" : "absent")}  {c.Path}"));

    private static string RenderValidation(BlueprintValidation verdict) => verdict.Valid
        ? $"valid: {verdict.Path}"
        : $"invalid: {verdict.Path}\n" + string.Join('\n', verdict.Errors.Select(e => "  " + e));

    private static string RenderRequirements(BlueprintRequirements requirements) =>
        Table.Render(["REQUIREMENT", "PRESENT"], requirements.Requirements.Select(r => new[] { r.Id, r.Present ? "yes" : "no" }));
}
