using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Scripts;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Transfers;

/// <summary>
/// The target's half of a transfer. <c>check</c> collects every reason the host would refuse a manifest and
/// writes nothing. <c>begin</c> stages an import in the library; each <c>part</c> is read from standard input
/// into the staging, an archive extracted and verified or an image loaded and compared with the manifest's
/// id; <c>finish</c> decides everything again, then registers the instance under a new id and unwinds only
/// what it created when anything fails, leaving the staging for <c>abort</c>. Nothing here adopts a
/// backups directory it did not make.
/// </summary>
public sealed partial class TransferImportService(OperationHost host)
{
    private const string TreePartId = "tree";

    // =============================================================================================
    // Check
    // =============================================================================================

    /// <summary>What a check found, with what the import will use.</summary>
    private sealed record CheckOutcome(
        List<ImportRefusal> Refusals, LibraryRecord? Library, string? Blueprint, string BlueprintAction)
    {
        public ImportVerdict ToVerdict() => new()
        {
            Ok = Refusals.Count == 0,
            Refusals = Refusals,
            Library = Library?.Name,
            Blueprint = Blueprint,
        };
    }

    /// <summary>Every reason this host would refuse the manifest, all of them listed; nothing is written.</summary>
    /// <param name="manifest">The manifest.</param>
    /// <param name="library">The library to place the instance in; the default, or the only one, when null.</param>
    /// <param name="blueprintSuffix">The label that lets a custom blueprint that collides with another of the same name be installed beside it.</param>
    /// <param name="cancellationToken">Cancellation of the command.</param>
    public async Task<ImportVerdict> CheckAsync(
        TransferManifest manifest, string? library, string? blueprintSuffix, CancellationToken cancellationToken) =>
        (await DecideAsync(manifest, library, blueprintSuffix, staged: false, cancellationToken).ConfigureAwait(false)).ToVerdict();

    private async Task<CheckOutcome> DecideAsync(
        TransferManifest manifest, string? libraryName, string? suffix, bool staged, CancellationToken cancellationToken)
    {
        var refusals = new List<ImportRefusal>();
        if (ManifestProblem(manifest) is { } problem)
        {
            refusals.Add(Refusal(ImportRefusalCodes.InvalidManifest, problem));
            return new CheckOutcome(refusals, null, null, string.Empty);
        }

        LibraryRecord? library = ChooseLibrary(libraryName, refusals);

        if (!string.Equals(manifest.EngineVersion, host.EngineVersion, StringComparison.Ordinal))
        {
            refusals.Add(Refusal(
                ImportRefusalCodes.EngineVersionMismatch,
                $"The source runs engine {manifest.EngineVersion} and this host runs {host.EngineVersion}",
                ExitCodes.TransferVersionMismatch));
        }

        foreach (string requirement in manifest.Requirements.Distinct(StringComparer.Ordinal))
        {
            if (!host.Requirements.IsPresent(requirement))
                refusals.Add(Refusal(ImportRefusalCodes.RequirementMissing, $"This host lacks {requirement}", ExitCodes.TransferRequirementMissing));
        }

        (string blueprint, string action) = ResolveBlueprint(manifest, suffix, refusals);

        // A staged import has its bytes already: the tree is on disk and the images are loaded.
        if (!staged) await CheckSpaceAsync(manifest, library, refusals, cancellationToken).ConfigureAwait(false);

        CheckPorts(manifest, refusals);
        return new CheckOutcome(refusals, library, blueprint, action);
    }

    private static string? ManifestProblem(TransferManifest manifest)
    {
        if (manifest.SchemaVersion != SchemaVersions.TransferManifest)
            return $"The manifest has schemaVersion {manifest.SchemaVersion}; this engine reads {SchemaVersions.TransferManifest}";
        if (!InstanceIds.IsValid(manifest.Instance.Id)) return "The manifest names no valid instance id";
        if (!BlueprintParser.IsValidName(manifest.Blueprint.Name)) return "The manifest names no valid blueprint";
        if (manifest.Parts.Count(p => p.Kind == TransferPartKind.Tree) != 1 || manifest.Parts.All(p => p.Id != TreePartId))
            return "The manifest must carry exactly one tree part, named 'tree'";
        if (manifest.Parts.Select(p => p.Id).Distinct(StringComparer.Ordinal).Count() != manifest.Parts.Count)
            return "The manifest names a part twice";

        foreach (TransferPart part in manifest.Parts.Where(p => p.Kind == TransferPartKind.Image))
        {
            if (!ImagePartId().IsMatch(part.Id) || string.IsNullOrEmpty(part.Ref) || string.IsNullOrEmpty(part.ImageId))
                return $"The image part '{part.Id}' needs an id 'image-N', a reference and an image id";
        }

        if (manifest.Parts.Any(p => p.Kind == TransferPartKind.Tree && p.Files is null)) return "The tree part needs its file count";
        return null;
    }

    /// <summary>The library asked for, else the configured default, else the only one; a reason is appended when none can take the instance.</summary>
    private LibraryRecord? ChooseLibrary(string? requested, List<ImportRefusal> refusals)
    {
        IReadOnlyList<LibraryRecord> registered = host.Libraries.Registered();
        string? wanted = !string.IsNullOrEmpty(requested) ? requested
            : !string.IsNullOrEmpty(host.Settings.Libraries.DefaultLibrary) ? host.Settings.Libraries.DefaultLibrary
            : null;

        LibraryRecord? chosen;
        if (wanted is not null)
        {
            chosen = registered.FirstOrDefault(l => l.Name == wanted);
            if (chosen is null)
            {
                refusals.Add(Refusal(ImportRefusalCodes.LibraryNotFound, $"No library named '{wanted}' is registered"));
                return null;
            }
        }
        else if (registered.Count == 1)
        {
            chosen = registered[0];
        }
        else
        {
            refusals.Add(Refusal(
                ImportRefusalCodes.LibraryNotFound,
                registered.Count == 0 ? "No library is registered" : "Several libraries are registered and none was chosen"));
            return null;
        }

        if (LibraryCatalog.StateOf(chosen) != LibraryState.Online)
        {
            refusals.Add(Refusal(ImportRefusalCodes.LibraryOffline, $"Library '{chosen.Name}' is not reachable at {chosen.Path}"));
            return null;
        }

        if (LibraryRules.OverlapsRegistry(chosen.Path, host.Paths.DataDirectory))
        {
            refusals.Add(Refusal(ImportRefusalCodes.LibraryOverlapsRegistry, $"Library '{chosen.Name}' places servers inside the instance registry"));
            return null;
        }

        return chosen;
    }

    /// <summary>
    /// Decides what the arriving blueprint becomes: <c>use</c> (the host holds it), <c>install</c> (it travels
    /// in the tree) or <c>install-suffixed</c> (it travels, under another name). A default blueprint must
    /// already be here. A custom one that is absent is installed; one present with the same content is used;
    /// one present with other content is installed as <c>name-suffix</c>.
    /// </summary>
    private (string Name, string Action) ResolveBlueprint(TransferManifest manifest, string? suffix, List<ImportRefusal> refusals)
    {
        string name = manifest.Blueprint.Name;
        string? existing = host.Blueprints.Find(name).Resolved;
        if (existing is null)
        {
            if (manifest.Blueprint.Custom) return (name, "install");
            refusals.Add(Refusal(ImportRefusalCodes.BlueprintMissing, $"Blueprint '{name}' is not on this host"));
            return (name, string.Empty);
        }

        if (!manifest.Blueprint.Custom || Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(existing))) == manifest.Blueprint.Sha256) return (name, "use");

        if (string.IsNullOrEmpty(suffix))
        {
            refusals.Add(Refusal(ImportRefusalCodes.BlueprintCollision, $"Blueprint '{name}' exists here with different content; pass --blueprint-suffix"));
            return (name, string.Empty);
        }

        if (!BlueprintNames.IsValidSuffix(suffix))
        {
            refusals.Add(Refusal(ImportRefusalCodes.InvalidSuffix, $"Blueprint suffix '{suffix}' is not a lowercase name"));
            return (name, string.Empty);
        }

        string suffixed = $"{name}-{suffix}";
        if (!BlueprintParser.IsValidName(suffixed))
        {
            refusals.Add(Refusal(ImportRefusalCodes.InvalidSuffix, $"'{suffixed}' is not a blueprint file name"));
            return (suffixed, string.Empty);
        }

        string? held = host.Blueprints.Find(suffixed).Resolved;
        if (held is null) return (suffixed, "install-suffixed");

        // The copy already here was made by an earlier transfer when stripping the suffix gives back what travels.
        if (Sha256Of(BlueprintNames.StripSuffix(File.ReadAllText(held), suffix)) == manifest.Blueprint.Sha256) return (suffixed, "use");

        refusals.Add(Refusal(ImportRefusalCodes.BlueprintCollision, $"Blueprint '{suffixed}' exists here with different content"));
        return (suffixed, string.Empty);
    }

    private async Task CheckSpaceAsync(TransferManifest manifest, LibraryRecord? library, List<ImportRefusal> refusals, CancellationToken cancellationToken)
    {
        const long Mebibyte = 1024 * 1024;

        long treeBytes = manifest.Parts.Where(p => p.Kind == TransferPartKind.Tree).Sum(p => p.Bytes);
        long imageBytes = manifest.Parts.Where(p => p.Kind == TransferPartKind.Image).Sum(p => p.Bytes);

        if (library is not null)
        {
            long margin = (long)host.Settings.Libraries.InstallFreeSpaceMarginMb;
            long needMb = (treeBytes + Mebibyte - 1) / Mebibyte;
            try
            {
                long free = new DriveInfo(library.Path).AvailableFreeSpace;
                if (free < (needMb + margin) * Mebibyte)
                {
                    refusals.Add(Refusal(
                        ImportRefusalCodes.InsufficientDisk,
                        $"Library '{library.Name}' has {free / Mebibyte}MB free and the instance needs {needMb}MB plus a {margin}MB margin",
                        ExitCodes.InsufficientDisk));
                }
            }
            catch (Exception ex) when (ex is IOException or ArgumentException or UnauthorizedAccessException)
            {
                host.Logger("transfer").LogWarning("The free space of {Library} could not be measured: {Problem}", library.Name, ex.Message);
            }
        }

        if (imageBytes > 0 && await host.Images.FreeBytesAsync(cancellationToken).ConfigureAwait(false) is { } runtimeFree && runtimeFree < imageBytes)
        {
            refusals.Add(Refusal(
                ImportRefusalCodes.InsufficientDisk,
                $"The container runtime has {runtimeFree / Mebibyte}MB free and the images need {imageBytes / Mebibyte}MB",
                ExitCodes.InsufficientDisk));
        }
    }

    private void CheckPorts(TransferManifest manifest, List<ImportRefusal> refusals)
    {
        if (manifest.Instance.Ports.Count == 0) return;

        foreach (InstanceDescription other in host.Instances.List())
        {
            if (other.Config is null) continue;
            foreach (PortRange held in PortSpecs.Parse(other.Config.Ports))
            {
                foreach (PortRange incoming in manifest.Instance.Ports.Where(held.Overlaps))
                {
                    refusals.Add(Refusal(
                        ImportRefusalCodes.PortConflict,
                        $"Port {incoming.Start}-{incoming.End}/{ProtocolName(incoming.Protocol)} overlaps {held.Start}-{held.End}/{ProtocolName(held.Protocol)} of '{other.Id}'",
                        ExitCodes.TransferPortConflict));
                }
            }
        }
    }

    // =============================================================================================
    // Begin, part, abort, list
    // =============================================================================================

    /// <summary>
    /// Checks the manifest and, when the host accepts it, stages the import in the library.
    /// </summary>
    /// <returns>The verdict, and the import's id when the host accepted.</returns>
    public async Task<(ImportVerdict Verdict, string? ImportId)> BeginAsync(
        TransferManifest manifest, string? library, string? blueprintSuffix, CancellationToken cancellationToken)
    {
        CheckOutcome outcome = await DecideAsync(manifest, library, blueprintSuffix, staged: false, cancellationToken).ConfigureAwait(false);
        if (outcome.Refusals.Count > 0) return (outcome.ToVerdict(), null);

        LibraryRecord target = outcome.Library!;
        string id = "imp-" + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(6));
        var stage = new ImportStage(Path.Combine(ImportStage.StagingRoot(target), id), target);

        try
        {
            Directory.CreateDirectory(stage.PartsDirectory);
            Directory.CreateDirectory(stage.TreeDirectory);
            ContractFile.Write(stage.ManifestFile, manifest, EngineJsonContext.Default.TransferManifest);

            // What the host already held, so an abort removes only what this import brought.
            var images = new List<ImportStageImage>();
            foreach (TransferPart part in manifest.Parts.Where(p => p.Kind == TransferPartKind.Image))
            {
                ImageInfo? named = await host.Images.InspectAsync(part.Ref!, cancellationToken).ConfigureAwait(false);
                images.Add(new ImportStageImage
                {
                    PartId = part.Id,
                    ImageId = part.ImageId!,
                    HeldBefore = string.Equals(named?.Chain, part.ImageId, StringComparison.Ordinal),
                    PreviousId = named?.Id,
                });
            }

            ContractFile.Write(
                stage.MetaFile,
                new ImportStageMeta
                {
                    SchemaVersion = SchemaVersions.ImportStage,
                    ImportId = id,
                    Library = target.Name,
                    BlueprintSuffix = string.IsNullOrEmpty(blueprintSuffix) ? null : blueprintSuffix,
                    Began = host.Clock.GetUtcNow(),
                    Images = images,
                },
                EngineJsonContext.Default.ImportStageMeta);
        }
        catch (Exception)
        {
            TryRemove(stage);
            throw;
        }

        return (outcome.ToVerdict(), id);
    }

    /// <summary>Reads one part from <paramref name="source"/> into the staged import and checks it against the manifest.</summary>
    public async Task PartAsync(string importId, string partId, Stream source, CancellationToken cancellationToken)
    {
        ImportStage stage = Find(importId) ?? throw ImportNotFound(importId);
        TransferManifest manifest = stage.ReadManifest();
        TransferPart part = manifest.Parts.FirstOrDefault(p => p.Id == partId)
            ?? throw OperationException.NotFound($"the manifest of {importId} lists no part '{partId}'");

        if (File.Exists(stage.DoneMarker(partId))) File.Delete(stage.DoneMarker(partId));

        if (part.Kind == TransferPartKind.Tree)
        {
            // A restarted part begins from nothing.
            if (Directory.Exists(stage.TreeDirectory)) Directory.Delete(stage.TreeDirectory, recursive: true);
            Directory.CreateDirectory(stage.TreeDirectory);
            try
            {
                await TreeArchive.ExtractAsync(source, stage.TreeDirectory, cancellationToken).ConfigureAwait(false);
            }
            catch (TreeIntegrityException ex)
            {
                throw Integrity(ex.Message);
            }
        }
        else
        {
            await LoadImageAsync(part, source, cancellationToken).ConfigureAwait(false);
        }

        File.WriteAllBytes(stage.DoneMarker(partId), []);
    }

    /// <summary>
    /// Loads an image and compares the id with the manifest's. An image that loads as something else is
    /// removed again at once when this load brought it, and the reference is put back on what it named,
    /// so a refused part leaves the host as it found it.
    /// </summary>
    private async Task LoadImageAsync(TransferPart part, Stream source, CancellationToken cancellationToken)
    {
        string reference = part.Ref!;
        ImageInfo? before = await host.Images.InspectAsync(reference, cancellationToken).ConfigureAwait(false);

        var guarded = new ImageStream.Reader(source);
        string? problem = null;
        try
        {
            await host.Images.LoadAsync(guarded, cancellationToken).ConfigureAwait(false);
            await guarded.CopyToAsync(Stream.Null, cancellationToken).ConfigureAwait(false);
            problem = guarded.Problem();
        }
        catch (OperationException ex)
        {
            throw Integrity($"The image stream could not be loaded: {ex.Message}");
        }

        ImageInfo? after = await host.Images.InspectAsync(reference, cancellationToken).ConfigureAwait(false);
        if (problem is null && after is not null && string.Equals(after.Chain, part.ImageId, StringComparison.Ordinal)) return;

        if (after is not null && !string.Equals(after.Id, before?.Id, StringComparison.Ordinal))
        {
            await host.Images.RemoveAsync(after.Id, cancellationToken).ConfigureAwait(false);
            if (before is not null) await host.Images.TagAsync(before.Id, reference, cancellationToken).ConfigureAwait(false);
        }

        throw Integrity(problem is not null
            ? $"The image stream of {reference} is damaged: {problem}"
            : $"Image {reference} loaded as {after?.Chain ?? "nothing"}, the manifest says {part.ImageId}");
    }

    /// <summary>
    /// Removes a staged import, and the images it loaded and verified that the host did not hold before it
    /// began. An id nothing staged succeeds. An image the runtime would not remove keeps the staging, so the
    /// abort can be run again.
    /// </summary>
    public async Task<ImportAbortReport> AbortAsync(string importId, CancellationToken cancellationToken)
    {
        ImportStage? stage = Find(importId);
        if (stage is null) return new ImportAbortReport { ImportId = importId, Found = false, ImagesRemoved = [] };

        var removed = new List<string>();
        ImportStageMeta? meta = null;
        try
        {
            meta = stage.ReadMeta();
        }
        catch (EngineException ex)
        {
            host.Logger("transfer").LogWarning("The record of {Import} cannot be read ({Problem}); no image can be attributed to it", importId, ex.Message);
        }

        TransferManifest? manifest = null;
        try
        {
            manifest = stage.ReadManifest();
        }
        catch (EngineException)
        {
        }

        foreach (ImportStageImage image in meta?.Images ?? [])
        {
            if (image.HeldBefore || !File.Exists(stage.DoneMarker(image.PartId))) continue;

            string? reference = manifest?.Parts.FirstOrDefault(p => p.Id == image.PartId)?.Ref;
            if (reference is null) continue;

            // Only the image this import loaded: whatever the reference names now has to be the one it verified.
            ImageInfo? loaded = await host.Images.InspectAsync(reference, cancellationToken).ConfigureAwait(false);
            if (loaded is null || !string.Equals(loaded.Chain, image.ImageId, StringComparison.Ordinal)) continue;

            if (!await host.Images.RemoveAsync(loaded.Id, cancellationToken).ConfigureAwait(false))
                throw new OperationException(ErrorCodes.Failed, $"the container runtime would not remove the image {reference} that {importId} loaded; the staging is kept so the abort can be run again");
            removed.Add(reference);

            if (image.PreviousId is not null && await host.Images.InspectAsync(image.PreviousId, cancellationToken).ConfigureAwait(false) is not null)
                await host.Images.TagAsync(image.PreviousId, reference, cancellationToken).ConfigureAwait(false);
        }

        stage.Remove();
        return new ImportAbortReport { ImportId = importId, Found = true, ImagesRemoved = removed };
    }

    /// <summary>Every staged import in every online library.</summary>
    public IReadOnlyList<StagedImport> List()
    {
        var rows = new List<StagedImport>();
        foreach (LibraryRecord library in host.Libraries.Registered().Where(l => LibraryCatalog.StateOf(l) == LibraryState.Online))
        {
            string root = ImportStage.StagingRoot(library);
            if (!Directory.Exists(root)) continue;

            foreach (string directory in Directory.EnumerateDirectories(root).Order(StringComparer.Ordinal))
            {
                var stage = new ImportStage(directory, library);
                try
                {
                    TransferManifest manifest = stage.ReadManifest();
                    ImportStageMeta meta = stage.ReadMeta();
                    rows.Add(new StagedImport
                    {
                        ImportId = meta.ImportId,
                        Library = meta.Library,
                        Instance = manifest.Instance.Id,
                        Blueprint = manifest.Blueprint.Name,
                        Began = meta.Began,
                    });
                }
                catch (EngineException ex)
                {
                    host.Logger("transfer").LogWarning("The staged import {Directory} cannot be read: {Problem}", directory, ex.Message);
                }
            }
        }

        return [.. rows.OrderBy(r => r.Began).ThenBy(r => r.ImportId, StringComparer.Ordinal)];
    }

    private ImportStage? Find(string importId)
    {
        if (!ImportIdPattern().IsMatch(importId)) return null;

        foreach (LibraryRecord library in host.Libraries.Registered())
        {
            if (LibraryCatalog.StateOf(library) != LibraryState.Online) continue;
            string directory = Path.Combine(ImportStage.StagingRoot(library), importId);
            if (Directory.Exists(directory)) return new ImportStage(directory, library);
        }

        return null;
    }

    // =============================================================================================
    // Finish
    // =============================================================================================

    /// <summary>
    /// Builds the instance from a staged import. Everything the host may have changed since the begin is
    /// decided again before a file moves. The staged tree is renamed into place; every step registers its
    /// undo, and a failure at any step puts back exactly what the finish made, leaving the staging for abort.
    /// </summary>
    public async Task<ImportedInstance> FinishAsync(string importId, CancellationToken cancellationToken)
    {
        ImportStage stage = Find(importId) ?? throw ImportNotFound(importId);
        TransferManifest manifest = stage.ReadManifest();
        ImportStageMeta meta = stage.ReadMeta();
        ILogger log = host.Logger("transfer");

        // Everything the manifest lists has arrived, and the tree is the size it said.
        foreach (TransferPart part in manifest.Parts)
        {
            if (!File.Exists(stage.DoneMarker(part.Id))) throw Integrity($"Part {part.Id} has not arrived");
        }

        TransferPart treePart = manifest.Parts.First(p => p.Id == TreePartId);
        (long gotBytes, long gotFiles) = TreeArchive.Measure(TransferTree.Staged(stage.TreeDirectory));
        if (gotBytes != treePart.Bytes || gotFiles != treePart.Files)
            throw Integrity($"The tree holds {gotFiles} files and {gotBytes} bytes; the manifest says {treePart.Files} and {treePart.Bytes}");

        string oldId = manifest.Instance.Id;
        string stagedInstance = Path.Combine(stage.TreeDirectory, TransferTree.Instance);
        string stagedConfig = new InstanceLayout(stagedInstance, oldId).ConfigFile;
        if (!File.Exists(stagedConfig)) throw Integrity($"The tree carries no config for {oldId}");

        InstanceConfig sourceConfig;
        try
        {
            sourceConfig = ContractFile.Read(stagedConfig, EngineJsonContext.Default.InstanceConfig, SchemaVersions.InstanceConfig, c => c.SchemaVersion);
        }
        catch (EngineException ex)
        {
            throw Integrity(ex.Message);
        }

        // The host may have changed since the begin; its answers are decided again with nothing written.
        CheckOutcome outcome = await DecideAsync(manifest, meta.Library, meta.BlueprintSuffix, staged: true, cancellationToken).ConfigureAwait(false);
        if (outcome.Refusals.Count > 0)
        {
            ImportRefusal first = outcome.Refusals[0];
            throw new OperationException(
                first.Code.Replace('_', '-'), first.Detail, first.ExitCode, [.. outcome.Refusals.Skip(1).Select(r => r.Detail)]);
        }

        LibraryRecord library = outcome.Library!;
        string blueprintName = outcome.Blueprint!;

        var undo = new Stack<(string What, Func<Task> Do)>();
        string newId = string.Empty;
        try
        {
            string installedBlueprint = InstallBlueprint(stage, manifest, outcome, meta, undo);
            Blueprint blueprint = ReadBlueprint(blueprintName, installedBlueprint);

            IReadOnlyDictionary<string, InstanceRegistryEntry> registered = host.Instances.Registered();
            newId = InstanceIds.Generate(
                blueprintName, host.Settings.Instances.IdSuffixLength,
                candidate => registered.ContainsKey(candidate) || Directory.Exists(InstanceLayout.WorkingDirectoryFor(library.Path, blueprintName, candidate)))
                ?? throw OperationException.Refused($"every {host.Settings.Instances.IdSuffixLength}-character suffix of '{blueprintName}' is taken; raise Instances:IdSuffixLength");

            using IDisposable held = host.Locks.AcquireInstance(newId);

            string workingDirectory = InstanceLayout.WorkingDirectoryFor(library.Path, blueprintName, newId);
            string backupsDirectory = FreshBackupsDirectory(newId);

            MoveIntoPlace(stagedInstance, workingDirectory, undo, cancellationToken);

            InstanceConfig config = RenameFiles(sourceConfig, oldId, newId, blueprintName, backupsDirectory, workingDirectory, blueprint, undo);

            host.Registry.Add(newId, new InstanceRegistryEntry { Blueprint = blueprintName, Library = library.Id, WorkingDirectory = workingDirectory });
            undo.Push(("the registry entry", () => { host.Registry.Remove(newId); return Task.CompletedTask; }));

            PlaceBackups(stage, backupsDirectory, undo, cancellationToken);

            if (manifest.Instance.HasRun) await ProveStartsAsync(newId, undo, cancellationToken).ConfigureAwait(false);

            if (manifest.Instance.Autostart && config.Runtime == BlueprintRuntime.Native)
                await RestoreAutostartAsync(newId, config, cancellationToken).ConfigureAwait(false);

            host.Events.Append(new Imported { InstanceName = newId, Blueprint = blueprintName, Library = library.Name });
            undo.Clear();
        }
        catch (Exception ex)
        {
            log.LogError(ex, "The import {Import} failed to finish; putting back what it made", importId);
            await UnwindAsync(undo, log).ConfigureAwait(false);
            throw;
        }

        // What was staged has been used; the images it loaded stay.
        TryRemove(stage);
        return new ImportedInstance { Instance = newId, Blueprint = blueprintName, Library = library.Name };
    }

    /// <summary>Puts a custom blueprint and the person's hooks for its game in place; returns the blueprint file the instance will use.</summary>
    private string InstallBlueprint(
        ImportStage stage, TransferManifest manifest, CheckOutcome outcome, ImportStageMeta meta, Stack<(string What, Func<Task> Do)> undo)
    {
        string name = outcome.Blueprint!;
        if (outcome.BlueprintAction == "use") return host.Blueprints.Find(name).Resolved!;

        string sourceName = manifest.Blueprint.Name;
        string source = Path.Combine(stage.TreeDirectory, TransferTree.Blueprint, sourceName + EnginePathsSuffix);
        if (!File.Exists(source)) throw Integrity($"The tree carries no blueprint file for {sourceName}");

        string text = File.ReadAllText(source);
        if (outcome.BlueprintAction == "install-suffixed") text = BlueprintNames.AddSuffix(text, meta.BlueprintSuffix!);

        string target = Path.Combine(host.Paths.UserBlueprintsDirectory, name + EnginePathsSuffix);
        Directory.CreateDirectory(host.Paths.UserBlueprintsDirectory);
        File.WriteAllText(target, text, new UTF8Encoding(false));
        undo.Push(("the blueprint file", () => { File.Delete(target); return Task.CompletedTask; }));

        string hooksSource = Path.Combine(stage.TreeDirectory, TransferTree.Overrides, sourceName, HookFiles.FileName);
        string hooksTarget = Path.Combine(host.Paths.UserOverridesDirectory, name, HookFiles.FileName);
        if (File.Exists(hooksSource) && !File.Exists(hooksTarget))
        {
            bool madeDirectory = !Directory.Exists(Path.GetDirectoryName(hooksTarget)!);
            Directory.CreateDirectory(Path.GetDirectoryName(hooksTarget)!);
            File.Copy(hooksSource, hooksTarget);
            undo.Push(("the hooks file", () =>
            {
                File.Delete(hooksTarget);
                if (madeDirectory) Directory.Delete(Path.GetDirectoryName(hooksTarget)!);
                return Task.CompletedTask;
            }));
        }

        return target;
    }

    private const string EnginePathsSuffix = Paths.EnginePaths.BlueprintFileSuffix;

    private Blueprint ReadBlueprint(string name, string file)
    {
        BlueprintParseResult parsed = host.Blueprints.Read(name)
            ?? throw new OperationException(ErrorCodes.Failed, $"the blueprint '{name}' is not on this host after it was placed ({file})");
        return parsed.Blueprint
            ?? throw OperationException.Invalid($"the blueprint '{name}' is not valid", parsed.Validation.Errors);
    }

    /// <summary>The backups directory of the new instance: the configured place for its id, or when that name is taken by backups this import did not make, a directory of its own.</summary>
    private string FreshBackupsDirectory(string newId)
    {
        string candidate = host.BackupsDirectoryFor(newId);
        while (Directory.Exists(candidate) || File.Exists(candidate))
            candidate = host.BackupsDirectoryFor($"{newId}-{Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(4))}");
        return candidate;
    }

    /// <summary>Renames the staged working directory into the library: a rename on one device, else a copy.</summary>
    private static void MoveIntoPlace(string from, string to, Stack<(string What, Func<Task> Do)> undo, CancellationToken cancellationToken)
    {
        string parent = Path.GetDirectoryName(to)!;
        string blueprintDirectory = parent;
        string instancesDirectory = Path.GetDirectoryName(blueprintDirectory)!;
        bool madeInstances = !Directory.Exists(instancesDirectory);
        bool madeBlueprint = !Directory.Exists(blueprintDirectory);
        Directory.CreateDirectory(parent);
        if (madeInstances) undo.Push(("the library's instances directory", () => { RemoveIfEmpty(instancesDirectory); return Task.CompletedTask; }));
        if (madeBlueprint) undo.Push(("the blueprint's directory", () => { RemoveIfEmpty(blueprintDirectory); return Task.CompletedTask; }));

        if (Directory.Exists(to) || File.Exists(to)) throw OperationException.Refused($"{to} already exists");

        try
        {
            Directory.Move(from, to);
            undo.Push(("the working directory", () => { Directory.Move(to, from); return Task.CompletedTask; }));
        }
        catch (IOException) when (!Directory.Exists(to))
        {
            FileSystem.CopyTree(from, to, cancellationToken);
            undo.Push(("the working directory", () => { Directory.Delete(to, recursive: true); return Task.CompletedTask; }));
        }
    }

    /// <summary>
    /// Gives the staged files the new id: the config, the files whose names carry it, the script and, for
    /// a container, the compose file. Each step registers its undo, so a failed finish leaves the tree as
    /// it was staged.
    /// </summary>
    private InstanceConfig RenameFiles(
        InstanceConfig source, string oldId, string newId, string blueprintName, string backupsDirectory, string workingDirectory,
        Blueprint blueprint, Stack<(string What, Func<Task> Do)> undo)
    {
        var from = new InstanceLayout(workingDirectory, oldId, source.ExecutableSubdirectory);
        var to = new InstanceLayout(workingDirectory, newId, source.ExecutableSubdirectory);

        // Files that only mean something while the instance runs, or that the new id regenerates.
        foreach (string leftover in new[] { from.PidFile, from.InputFifo, from.TransferLockFile })
        {
            if (File.Exists(leftover)) File.Delete(leftover);
        }

        if (oldId != newId)
        {
            foreach ((string oldPath, string newPath) in new[] { (from.VersionFile, to.VersionFile), (from.LatestVersionFile, to.LatestVersionFile), (from.LogFile, to.LogFile) })
            {
                if (!File.Exists(oldPath)) continue;
                File.Move(oldPath, newPath);
                undo.Push(($"the rename of {Path.GetFileName(oldPath)}", () => { File.Move(newPath, oldPath); return Task.CompletedTask; }));
            }
        }

        InstanceConfig config = source with
        {
            Name = newId,
            Blueprint = blueprintName,
            BackupsDirectory = backupsDirectory,
            InstallNonce = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16)),

            // The integrations follow the host the instance lands on, not the one it left.
            EnableFirewallManagement = host.Settings.Instances.EnableFirewallManagement,
            EnablePortForwarding = host.Settings.Instances.EnablePortForwarding,
        };

        byte[] oldConfig = File.ReadAllBytes(from.ConfigFile);
        ContractFile.Write(to.ConfigFile, config, EngineJsonContext.Default.InstanceConfig);
        if (oldId != newId) File.Delete(from.ConfigFile);
        undo.Push(("the config", () =>
        {
            File.WriteAllBytes(from.ConfigFile, oldConfig);
            if (oldId != newId) File.Delete(to.ConfigFile);
            return Task.CompletedTask;
        }));

        HookFile? hooks = config.Runtime == BlueprintRuntime.Native ? HookFiles.Find(host.Paths, blueprintName) : null;
        Replace(from.ManagementScript, to.ManagementScript, ScriptGenerator.Render(config, hooks, host.Settings.Watchdog.Socket), script: true, undo);

        if (config.Runtime == BlueprintRuntime.Container)
            Replace(from.ComposeFile, to.ComposeFile, ComposeRenderer.Render(blueprint.Container!.Compose, config, to), script: false, undo);

        return config;
    }

    /// <summary>Writes the file the new id names and removes the one the old id named; the undo puts the old one back.</summary>
    private static void Replace(string oldPath, string newPath, string text, bool script, Stack<(string What, Func<Task> Do)> undo)
    {
        byte[]? previous = File.Exists(oldPath) ? File.ReadAllBytes(oldPath) : null;
        bool existedAtNew = oldPath != newPath && File.Exists(newPath);

        if (script) ScriptFile.Write(newPath, text);
        else File.WriteAllText(newPath, text, new UTF8Encoding(false));
        if (oldPath != newPath && previous is not null) File.Delete(oldPath);

        undo.Push(($"{Path.GetFileName(newPath)}", () =>
        {
            if (oldPath != newPath && !existedAtNew && File.Exists(newPath)) File.Delete(newPath);
            if (previous is not null) File.WriteAllBytes(oldPath, previous);
            else if (File.Exists(newPath)) File.Delete(newPath);
            return Task.CompletedTask;
        }));
    }

    /// <summary>The staged backups become the new instance's, in a directory this import makes; existing backups are never merged into.</summary>
    private static void PlaceBackups(ImportStage stage, string backupsDirectory, Stack<(string What, Func<Task> Do)> undo, CancellationToken cancellationToken)
    {
        string staged = Path.Combine(stage.TreeDirectory, TransferTree.Backups);
        string? parent = Path.GetDirectoryName(backupsDirectory);
        bool madeParent = parent is not null && !Directory.Exists(parent);
        if (parent is not null) Directory.CreateDirectory(parent);
        if (madeParent) undo.Push(("the backups root", () => { RemoveIfEmpty(parent!); return Task.CompletedTask; }));

        if (!Directory.Exists(staged))
        {
            Directory.CreateDirectory(backupsDirectory);
            undo.Push(("the backups directory", () => { Directory.Delete(backupsDirectory, recursive: true); return Task.CompletedTask; }));
            return;
        }

        try
        {
            Directory.Move(staged, backupsDirectory);
            undo.Push(("the backups", () => { Directory.Move(backupsDirectory, staged); return Task.CompletedTask; }));
        }
        catch (IOException) when (!Directory.Exists(backupsDirectory))
        {
            FileSystem.CopyTree(staged, backupsDirectory, cancellationToken);
            undo.Push(("the backups", () => { Directory.Delete(backupsDirectory, recursive: true); return Task.CompletedTask; }));
        }
    }

    /// <summary>Starts the instance at its new place and stops it again: the proof that it works there.</summary>
    private async Task ProveStartsAsync(string newId, Stack<(string What, Func<Task> Do)> undo, CancellationToken cancellationToken)
    {
        InstanceDescription instance = host.Instances.Find(newId)
            ?? throw new OperationException(ErrorCodes.Failed, $"'{newId}' is not registered after it was placed");

        LifecycleService lifecycle = host.Lifecycle;
        undo.Push(("the proof start", async () =>
        {
            InstanceDescription current = host.Instances.Find(newId) ?? instance;
            await lifecycle.StopCoreAsync(current, announce: false, CancellationToken.None).ConfigureAwait(false);
        }));

        try
        {
            await lifecycle.StartCoreAsync(instance, force: false, announce: false, cancellationToken).ConfigureAwait(false);
        }
        catch (EngineException ex)
        {
            throw new OperationException(ex.Code, $"the instance did not start from its new place: {ex.Message}", ex.ExitCode, inner: ex);
        }

        await lifecycle.StopCoreAsync(instance, announce: false, cancellationToken).ConfigureAwait(false);
    }

    private async Task RestoreAutostartAsync(string newId, InstanceConfig config, CancellationToken cancellationToken)
    {
        if (!await host.Lifecycle.WatchdogReadyAsync(config, cancellationToken).ConfigureAwait(false))
            throw new OperationException(ErrorCodes.Failed, $"boot autostart could not be set on '{newId}': the watchdog is not available here");

        try
        {
            ActionResult result = await host.Watchdog.EnableAsync(newId, cancellationToken).ConfigureAwait(false);
            if (!result.Ok) throw new OperationException(ErrorCodes.Failed, $"boot autostart could not be set on '{newId}': {result.Message}");
        }
        catch (WatchdogUnavailableException ex)
        {
            throw new OperationException(ErrorCodes.Failed, $"boot autostart could not be set on '{newId}': {ex.Message}", inner: ex);
        }
    }

    private static async Task UnwindAsync(Stack<(string What, Func<Task> Do)> undo, ILogger log)
    {
        while (undo.Count > 0)
        {
            (string what, Func<Task> action) = undo.Pop();
            try
            {
                await action().ConfigureAwait(false);
                log.LogInformation("Put back {What}", what);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or EngineException)
            {
                log.LogError(ex, "Could not put back {What}; remove it by hand", what);
            }
        }
    }

    private static void RemoveIfEmpty(string directory)
    {
        if (Directory.Exists(directory) && !Directory.EnumerateFileSystemEntries(directory).Any()) Directory.Delete(directory);
    }

    private void TryRemove(ImportStage stage)
    {
        try
        {
            stage.Remove();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            host.Logger("transfer").LogWarning(ex, "The staging {Directory} could not be removed; 'kgsm transfer import abort {Id}' removes it", stage.Directory, stage.Id);
        }
    }

    // =============================================================================================
    // Small pieces
    // =============================================================================================

    private static ImportRefusal Refusal(string code, string detail, int exitCode = ExitCodes.Failure) =>
        new() { ExitCode = exitCode, Code = code, Detail = detail };

    private static OperationException Integrity(string message) =>
        new(ErrorCodes.Integrity, message, ExitCodes.TransferIntegrity);

    private static OperationException ImportNotFound(string importId) =>
        new(ErrorCodes.ImportNotFound, $"No staged import '{importId}'", ExitCodes.TransferImportNotFound);

    private static string ProtocolName(PortProtocol protocol) => protocol == PortProtocol.Tcp ? "tcp" : "udp";

    private static string Sha256Of(string text) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(text)));

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$")]
    private static partial Regex ImportIdPattern();

    [GeneratedRegex("^image-[0-9]+$")]
    private static partial Regex ImagePartId();
}
