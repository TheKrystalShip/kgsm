using TheKrystalShip.KGSM.ComponentConfig;
using System.CommandLine;
using System.Text.Json;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Transfers;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>
/// The <c>transfer</c> noun: moving a stopped instance to another node. The source side is
/// <c>export</c>, the target side <c>import</c>; a part travels as raw bytes on standard output and
/// standard input, so these are the only commands that write or read anything but a result.
/// </summary>
internal static class TransferCommands
{
    public static Command Build(CommandHost host)
    {
        var transfer = new Command("transfer", "Move a stopped instance to another node.");
        transfer.Subcommands.Add(Export(host));
        transfer.Subcommands.Add(Import(host));
        return transfer;
    }

    [Action("kgsm:server.export", "Transfer servers out", DeclaredEffect.Write, DeclaredScope.Instance)]
    private static Command Export(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var manifest = new Option<bool>("--manifest") { Description = "Print the instance's manifest; with --lock, lock the instance first." };
        var part = new Option<string>("--part") { Description = "Stream one part (tree, image-1, ...) to standard output." };
        var commit = new Option<bool>("--commit") { Description = "Remove the instance, its backups and the images no other instance uses." };
        var token = new Option<string>("--lock") { Description = "The transfer's lock token." };

        return new Command("export", "Describe and stream a stopped instance for a transfer.") { reference, manifest, part, commit, token }
            .ActOnInstance(host, "transfer export", reference, async (context, instance) =>
            {
                bool wantsManifest = context.Parse.GetValue(manifest);
                string? partId = context.Parse.GetValue(part);
                bool wantsCommit = context.Parse.GetValue(commit);
                string? lockToken = context.Parse.GetValue(token);

                int modes = (wantsManifest ? 1 : 0) + (partId is not null ? 1 : 0) + (wantsCommit ? 1 : 0);
                if (modes != 1) return Failure.Usage("Choose exactly one of --manifest, --part <id> or --commit.");
                if (!wantsManifest && lockToken is null) return Failure.Usage("--lock <token> is required to stream a part or commit.");

                var service = new TransferExportService(context.Services.Operations);
                if (wantsManifest)
                {
                    TransferManifest result = await service.ManifestAsync(instance, lockToken, context.Cancellation).ConfigureAwait(false);
                    return new Result<TransferManifest>(result, EngineJsonContext.Default.TransferManifest, RenderManifest);
                }

                if (partId is not null)
                {
                    await service.PartAsync(instance, partId, lockToken!, context.RawOutput, context.Cancellation).ConfigureAwait(false);
                    return new Streamed(ExitCodes.Success);
                }

                // The lock token is the consent: only the transfer that holds the instance can commit it.
                ExportCommitReport committed = await service.CommitAsync(instance, lockToken!, context.Cancellation).ConfigureAwait(false);
                return new Result<ExportCommitReport>(
                    committed, EngineJsonContext.Default.ExportCommitReport,
                    r => $"{r.Instance} exported and removed" + (r.ImagesRemoved.Count > 0 ? $"; images removed: {string.Join(", ", r.ImagesRemoved)}" : string.Empty));
            });
    }

    private static Command Import(CommandHost host)
    {
        var import = new Command("import", "Build an instance from an export.");
        import.Subcommands.Add(Manifested(host, "check", "List every reason this host would refuse the manifest read from standard input.", begin: false));
        import.Subcommands.Add(Manifested(host, "begin", "Check the manifest read from standard input and stage the import.", begin: true));
        import.Subcommands.Add(Part(host));
        import.Subcommands.Add(Finish(host));
        import.Subcommands.Add(Abort(host));
        import.Subcommands.Add(List(host));
        return import;
    }

    [Action("kgsm:server.import", "Transfer servers in", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command Manifested(CommandHost host, string verb, string description, bool begin)
    {
        var library = new Option<string>("--library") { Description = "The library to place the instance in; the default library, or the only one." };
        var suffix = new Option<string>("--blueprint-suffix") { Description = "Install a custom blueprint that collides with another of its name as <name>-<suffix>." };

        return new Command(verb, description) { library, suffix }.Act(host, $"transfer import {verb}", async context =>
        {
            TransferManifest? manifest = ReadManifest(context.Input.ReadToEnd());
            if (manifest is null)
            {
                return Verdict(new ImportVerdict
                {
                    Ok = false,
                    Refusals = [new ImportRefusal { ExitCode = ExitCodes.Failure, Code = ImportRefusalCodes.InvalidManifest, Detail = "Standard input is not a manifest this engine reads" }],
                });
            }

            var service = new TransferImportService(context.Services.Operations);
            string? chosen = context.Parse.GetValue(library);
            string? label = context.Parse.GetValue(suffix);

            if (!begin) return Verdict(await service.CheckAsync(manifest, chosen, label, context.Cancellation).ConfigureAwait(false));

            (ImportVerdict verdict, string? importId) = await service.BeginAsync(manifest, chosen, label, context.Cancellation).ConfigureAwait(false);
            return importId is null
                ? Verdict(verdict)
                : new Result<ImportBegun>(new ImportBegun { ImportId = importId }, EngineJsonContext.Default.ImportBegun, r => r.ImportId);
        });
    }

    [Action("kgsm:server.import", "Transfer servers in", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command Part(CommandHost host)
    {
        var importId = new Argument<string>("import-id") { Description = "The staged import." };
        var partId = new Argument<string>("part-id") { Description = "The part, as the manifest names it." };

        return new Command("part", "Read one part from standard input into a staged import.") { importId, partId }
            .Act(host, "transfer import part", async context =>
            {
                await new TransferImportService(context.Services.Operations)
                    .PartAsync(context.Parse.GetValue(importId)!, context.Parse.GetValue(partId)!, context.RawInput, context.Cancellation).ConfigureAwait(false);
                return new Result<ActionReport>(
                    new ActionReport { Action = "import part", Subject = context.Parse.GetValue(importId)!, Message = $"{context.Parse.GetValue(partId)} received" },
                    EngineJsonContext.Default.ActionReport, r => $"{r.Subject}: {r.Message}");
            });
    }

    [Action("kgsm:server.import", "Transfer servers in", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command Finish(CommandHost host)
    {
        var importId = new Argument<string>("import-id") { Description = "The staged import." };

        return new Command("finish", "Build the instance from a staged import.") { importId }
            .Act(host, "transfer import finish", async context =>
            {
                ImportedInstance imported = await new TransferImportService(context.Services.Operations)
                    .FinishAsync(context.Parse.GetValue(importId)!, context.Cancellation).ConfigureAwait(false);
                return new Result<ImportedInstance>(
                    imported, EngineJsonContext.Default.ImportedInstance,
                    r => $"Imported '{r.Instance}' from blueprint {r.Blueprint} into library '{r.Library}'");
            });
    }

    [Action("kgsm:server.import", "Transfer servers in", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command Abort(CommandHost host)
    {
        var importId = new Argument<string>("import-id") { Description = "The staged import." };

        return new Command("abort", "Remove a staged import and the images it loaded.") { importId }
            .Act(host, "transfer import abort", async context =>
            {
                ImportAbortReport report = await new TransferImportService(context.Services.Operations)
                    .AbortAsync(context.Parse.GetValue(importId)!, context.Cancellation).ConfigureAwait(false);
                return new Result<ImportAbortReport>(
                    report, EngineJsonContext.Default.ImportAbortReport,
                    r => r.Found
                        ? $"{r.ImportId} removed" + (r.ImagesRemoved.Count > 0 ? $"; images removed: {string.Join(", ", r.ImagesRemoved)}" : string.Empty)
                        : $"{r.ImportId} was not staged");
            });
    }

    [Action("kgsm:server.import", "Transfer servers in", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command List(CommandHost host) =>
        new Command("list", "List the staged imports.").Act(host, "transfer import list", context =>
        {
            IReadOnlyList<StagedImport> rows = new TransferImportService(context.Services.Operations).List();
            return Task.FromResult<Outcome>(new Result<IReadOnlyList<StagedImport>>(
                rows, EngineJsonContext.Default.IReadOnlyListStagedImport,
                r => r.Count == 0
                    ? "no staged imports"
                    : Table.Render(["IMPORT", "LIBRARY", "INSTANCE", "BLUEPRINT", "BEGAN"], r.Select(i => new[] { i.ImportId, i.Library, i.Instance, i.Blueprint, i.Began.ToString("u", System.Globalization.CultureInfo.InvariantCulture) }))));
        });

    private static TransferManifest? ReadManifest(string json)
    {
        try
        {
            return JsonSerializer.Deserialize(json, EngineJsonContext.Default.TransferManifest);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>A verdict is printed whether or not it accepts; a refusal exits with the first refusal's status.</summary>
    private static Outcome Verdict(ImportVerdict verdict) =>
        new Result<ImportVerdict>(verdict, EngineJsonContext.Default.ImportVerdict, RenderVerdict, verdict.Ok ? ExitCodes.Success : verdict.Refusals[0].ExitCode);

    private static string RenderVerdict(ImportVerdict verdict) => verdict.Ok
        ? $"accepted: library {verdict.Library}, blueprint {verdict.Blueprint}"
        : "refused:\n" + string.Join('\n', verdict.Refusals.Select(r => $"  {r.Code}: {r.Detail}"));

    private static string RenderManifest(TransferManifest manifest) =>
        Table.Fields(
        [
            ("instance", manifest.Instance.Id),
            ("blueprint", manifest.Blueprint.Name + (manifest.Blueprint.Custom ? " (custom)" : string.Empty)),
            ("runtime", manifest.Instance.Runtime.ToString().ToLowerInvariant()),
            ("engine", manifest.EngineVersion),
            ("autostart", manifest.Instance.Autostart ? "yes" : "no"),
            ("parts", string.Join(", ", manifest.Parts.Select(p => $"{p.Id} ({p.Bytes} bytes)"))),
        ]);
}
