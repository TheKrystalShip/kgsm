using System.Security.Cryptography;
using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>What <c>instance install</c> was asked for.</summary>
/// <param name="Blueprint">The blueprint's file name without <c>.bp.yaml</c>.</param>
/// <param name="Id">The instance id; generated when null.</param>
/// <param name="DisplayName">A label for the instance.</param>
/// <param name="Library">The library to place it in; the default library, or the only one, when null.</param>
/// <param name="Version">The version to install; the latest when null.</param>
/// <param name="Start">Whether to start the instance once it is installed.</param>
/// <param name="SkipSpaceCheck">Downgrades a shortage of disk to a warning.</param>
public sealed record InstallRequest(
    string Blueprint, string? Id = null, string? DisplayName = null, string? Library = null,
    string? Version = null, bool Start = false, bool SkipSpaceCheck = false);

/// <summary>
/// Installs an instance. Everything that can be refused is refused before anything is created. From the
/// first directory on, every step registers its undo, and a failure at any step removes what the install
/// made (the registry entry, the working directory and the backups directory), writes
/// <c>server.install.failed</c>, and closes the bracket with <c>server.install.finished</c>.
/// </summary>
public sealed class InstallService(OperationHost host)
{
    private const long Mebibyte = 1024 * 1024;

    public async Task<InstallReport> InstallAsync(InstallRequest request, CancellationToken cancellationToken)
    {
        ILogger log = host.Logger("install");

        if (request.Id is not null && !InstanceIds.IsValid(request.Id))
            throw OperationException.Invalid($"'{request.Id}' is not an instance id: letters, digits, '.', '_' and '-', starting with a letter or digit, at most {InstanceIds.MaxLength} characters");
        if (!BlueprintParser.IsValidName(request.Blueprint))
            throw OperationException.Invalid($"'{request.Blueprint}' is not a blueprint file name");

        BlueprintParseResult parsed = host.Blueprints.Read(request.Blueprint)
            ?? throw OperationException.NotFound($"No blueprint '{request.Blueprint}' exists.");
        Blueprint blueprint = parsed.Blueprint
            ?? throw OperationException.Invalid($"blueprint '{request.Blueprint}' is not valid", parsed.Validation.Errors);

        BlueprintRequirements requirements = BlueprintRequirementRules.Evaluate(blueprint, host.Requirements);
        if (!requirements.Satisfied)
        {
            throw OperationException.Refused(
                $"'{blueprint.Name}' needs what this host lacks",
                [.. requirements.Requirements.Where(r => !r.Present).Select(r => $"missing: {r.Id}")]);
        }

        if (!host.Events.IsWritable())
            throw new OperationException("journal", $"the journal at {host.Events.Directory} is not writable, so the install would leave no record");

        new LibraryService(host).EnsureFirst();
        LibraryRecord library = ChooseLibrary(request.Library);
        CheckSpace(library, blueprint, request.SkipSpaceCheck, log);

        IReadOnlyDictionary<string, InstanceRegistryEntry> registered = host.Instances.Registered();
        string id = request.Id ?? InstanceIds.Generate(blueprint.Name, host.Settings.Instances.IdSuffixLength, registered.ContainsKey)
            ?? throw OperationException.Refused($"every {host.Settings.Instances.IdSuffixLength}-character suffix of '{blueprint.Name}' is taken; raise Instances:IdSuffixLength");
        if (registered.ContainsKey(id)) throw OperationException.Refused($"an instance '{id}' is already registered");

        string workingDirectory = InstanceLayout.WorkingDirectoryFor(library.Path, blueprint.Name, id);
        string backupsDirectory = host.BackupsDirectoryFor(id);
        if (Directory.Exists(workingDirectory) || File.Exists(workingDirectory))
            throw OperationException.Refused($"{workingDirectory} already exists");
        if (Directory.Exists(backupsDirectory) || File.Exists(backupsDirectory))
            throw OperationException.Refused($"{backupsDirectory} already exists; an install never adopts backups it did not make");

        // Everything the install adds to the config is derived before the first file is made, so a
        // blueprint whose launch arguments name a value an instance lacks fails here, with nothing to undo.
        string displayName = DisplayNames.Normalize(request.DisplayName);
        InstanceConfig config = InstanceConfigFactory.Create(
            blueprint, host.Settings, id, displayName, backupsDirectory, host.Clock.GetUtcNow(),
            Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16)));
        var layout = new InstanceLayout(workingDirectory, id, config.ExecutableSubdirectory);
        HookFile? hooks = blueprint.Runtime == BlueprintRuntime.Native ? HookFiles.Find(host.Paths, blueprint.Name) : null;
        string script = ScriptGenerator.Render(config, hooks, host.Settings.Watchdog.Socket);
        string? compose = blueprint.Runtime == BlueprintRuntime.Container
            ? ComposeRenderer.Render(blueprint.Container!.Compose, config, layout)
            : null;

        using IDisposable held = host.Locks.AcquireInstance(id);

        var undo = new Stack<(string What, Action Do)>();
        var events = host.Events;
        events.Append(new InstallStarted { InstanceName = id, Blueprint = blueprint.Name });

        string version;
        try
        {
            CreateDirectories(layout, backupsDirectory, config, undo);
            events.Append(new InstallDirectoriesCreated { InstanceName = id });

            ContractFile.Write(layout.ConfigFile, config, EngineJsonContext.Default.InstanceConfig);
            ScriptFile.Write(layout.ManagementScript, script);
            if (compose is not null) File.WriteAllText(layout.ComposeFile, compose, new System.Text.UTF8Encoding(false));
            events.Append(new InstallFilesCreated { InstanceName = id });

            var instance = new InstanceDescription
            {
                Id = id,
                Blueprint = blueprint.Name,
                WorkingDirectory = workingDirectory,
                Library = library,
                LibraryState = InstanceLibraryState.Online,
                Config = config,
            };

            version = await FetchAsync(instance, request.Version, cancellationToken).ConfigureAwait(false);

            host.Registry.Add(id, new InstanceRegistryEntry { Blueprint = blueprint.Name, Library = library.Id, WorkingDirectory = workingDirectory });
            undo.Push(("the registry entry", () => host.Registry.Remove(id)));

            events.Append(new Installed { InstanceName = id, Blueprint = blueprint.Name, Library = library.Name });
            events.Append(new InstallFinished { InstanceName = id, Blueprint = blueprint.Name });
            undo.Clear();
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Install of {Id} from {Blueprint} failed; rolling back", id, blueprint.Name);
            Rollback(undo, log);

            events.Append(new InstallFailed { InstanceName = id, Blueprint = blueprint.Name });
            events.Append(new InstallFinished { InstanceName = id, Blueprint = blueprint.Name });
            throw;
        }

        // The install is complete and recorded. A start that follows is its own operation with its own
        // lock, and its failure leaves the installed instance where it is.
        held.Dispose();
        return await FinishAsync(id, blueprint.Name, library.Name, workingDirectory, version, request.Start, cancellationToken).ConfigureAwait(false);
    }

    private async Task<InstallReport> FinishAsync(
        string id, string blueprint, string library, string workingDirectory, string version, bool start,
        CancellationToken cancellationToken)
    {
        LifecycleReport? started = null;
        if (start)
        {
            InstanceDescription instance = host.Instances.Find(id)!;
            try
            {
                started = await host.Lifecycle.StartAsync(instance, force: false, cancellationToken).ConfigureAwait(false);
            }
            catch (EngineException ex)
            {
                throw new OperationException(ex.Code, $"'{id}' is installed, and could not be started: {ex.Message}", ex.ExitCode, inner: ex);
            }
        }

        return new InstallReport
        {
            Id = id,
            Blueprint = blueprint,
            Library = library,
            WorkingDirectory = workingDirectory,
            Version = version,
            Start = started,
        };
    }

    /// <summary>Resolves the version, downloads and deploys it, and records it.</summary>
    private async Task<string> FetchAsync(InstanceDescription instance, string? requested, CancellationToken cancellationToken)
    {
        string id = instance.Id;
        string version = requested
            ?? (await host.Script.RequireAsync(instance, ["version", "--latest"], "resolving the latest version", cancellationToken).ConfigureAwait(false)).LastOutputLine;
        if (version.Length == 0) throw new OperationException(ErrorCodes.Failed, $"the latest version of '{instance.Blueprint}' could not be resolved");

        host.Events.Append(new DownloadStarted { InstanceName = id });
        try
        {
            await host.Script.RequireAsync(instance, ["download", version], "download", cancellationToken).ConfigureAwait(false);
        }
        catch (Exception)
        {
            host.Events.Append(new DownloadFailed { InstanceName = id });
            throw;
        }

        host.Events.Append(new DownloadFinished { InstanceName = id });

        host.Events.Append(new DeployStarted { InstanceName = id });
        try
        {
            await host.Script.RequireAsync(instance, ["deploy"], "deploy", cancellationToken).ConfigureAwait(false);
        }
        catch (Exception)
        {
            host.Events.Append(new DeployFailed { InstanceName = id });
            throw;
        }

        host.Events.Append(new DeployFinished { InstanceName = id });

        await host.Script.RequireAsync(instance, ["version", "--save", version], "recording the version", cancellationToken).ConfigureAwait(false);
        if (requested is null)
            await host.Script.RequireAsync(instance, ["version", "--save-latest", version], "recording the latest version", cancellationToken).ConfigureAwait(false);

        return version;
    }

    private void CreateDirectories(InstanceLayout layout, string backupsDirectory, InstanceConfig config, Stack<(string What, Action Do)> undo)
    {
        // The directories above the working directory (<library>/instances and <library>/instances/<blueprint>)
        // are shared with other instances; the install removes the ones it made once they are empty.
        string blueprintDirectory = Path.GetDirectoryName(layout.WorkingDirectory)!;
        string instancesDirectory = Path.GetDirectoryName(blueprintDirectory)!;
        bool madeInstances = !Directory.Exists(instancesDirectory);
        bool madeBlueprint = !Directory.Exists(blueprintDirectory);
        Directory.CreateDirectory(blueprintDirectory);
        if (madeInstances) undo.Push(("the library's instances directory", () => RemoveIfEmpty(instancesDirectory)));
        if (madeBlueprint) undo.Push(("the blueprint's directory", () => RemoveIfEmpty(blueprintDirectory)));

        string[] working = [layout.WorkingDirectory, layout.InstallDirectory, layout.SavesDirectory, layout.LogsDirectory, layout.TempDirectory];

        Directory.CreateDirectory(layout.WorkingDirectory);
        undo.Push(("the working directory", () => Directory.Delete(layout.WorkingDirectory, recursive: true)));
        foreach (string directory in working.Skip(1)) Directory.CreateDirectory(directory);
        if (config.Runtime == BlueprintRuntime.Container) Directory.CreateDirectory(layout.EventsDirectory);

        Directory.CreateDirectory(Path.GetDirectoryName(backupsDirectory)!);
        Directory.CreateDirectory(backupsDirectory);
        undo.Push(("the backups directory", () => Directory.Delete(backupsDirectory, recursive: true)));
    }

    private static void RemoveIfEmpty(string directory)
    {
        if (Directory.Exists(directory) && !Directory.EnumerateFileSystemEntries(directory).Any()) Directory.Delete(directory);
    }

    private static void Rollback(Stack<(string What, Action Do)> undo, ILogger log)
    {
        while (undo.Count > 0)
        {
            (string what, Action action) = undo.Pop();
            try
            {
                action();
                log.LogInformation("Rolled back {What}", what);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or EngineException)
            {
                log.LogError(ex, "Could not roll back {What}; remove it by hand", what);
            }
        }
    }

    private LibraryRecord ChooseLibrary(string? requested)
    {
        PlacementChoice choice = LibraryRules.ChoosePlacement(
            host.Libraries.Registered(), LibraryCatalog.StateOf, requested, host.Settings.Libraries.DefaultLibrary);
        if (!choice.Ok) throw OperationException.Refused(choice.Refusal!);

        LibraryRecord library = choice.Library!;
        if (LibraryRules.OverlapsRegistry(library.Path, host.Paths.DataDirectory))
            throw OperationException.Refused($"library '{library.Name}' overlaps the engine's registry directory");
        return library;
    }

    private void CheckSpace(LibraryRecord library, Blueprint blueprint, bool skip, ILogger log)
    {
        long needed = ((blueprint.Metadata.BaseDiskMb ?? 0) + (long)host.Settings.Libraries.InstallFreeSpaceMarginMb) * Mebibyte;
        long free;
        try
        {
            free = new DriveInfo(library.Path).AvailableFreeSpace;
        }
        catch (Exception ex) when (ex is IOException or ArgumentException or UnauthorizedAccessException)
        {
            log.LogWarning("The free space of {Library} could not be measured: {Problem}", library.Name, ex.Message);
            return;
        }

        if (free >= needed) return;

        string shortage = $"library '{library.Name}' has {free / Mebibyte} MiB free and '{blueprint.Name}' needs {needed / Mebibyte} MiB (its disk figure plus the margin)";
        if (skip)
        {
            log.LogWarning("{Shortage}; installing anyway", shortage);
            return;
        }

        throw new OperationException(ErrorCodes.InsufficientDisk, shortage, ExitCodes.InsufficientDisk, ["--skip-space-check installs anyway"]);
    }
}

/// <summary>Display names are one line of text: control characters are dropped and the ends are trimmed.</summary>
public static class DisplayNames
{
    public static string Normalize(string? text)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        return new string([.. text.Where(c => !char.IsControl(c))]).Trim();
    }
}
