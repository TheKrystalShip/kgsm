using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Status;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Moves a stopped instance to another library. Both libraries must be online, the target outside the
/// engine's registry directory and with room for the instance. A move inside one device is a rename;
/// otherwise the tree is copied, and a copy that was cut short resumes where it stopped. The source is
/// untouched until the instance has been registered at its new place and, if it had ever run, started
/// there once; a failure puts everything back.
/// </summary>
public sealed class MoveService(OperationHost host)
{
    public async Task<MoveReport> MoveAsync(InstanceDescription instance, string targetName, CancellationToken cancellationToken)
    {
        ILogger log = host.Logger("move");
        InstanceConfig config = Guards.ForChange(instance, "move");

        LibraryRecord target = host.Libraries.Registered().FirstOrDefault(l => l.Name == targetName)
            ?? throw OperationException.NotFound($"No library '{targetName}' is registered.");
        LibraryRecord source = instance.Library
            ?? throw OperationException.Refused($"'{instance.Id}' lies under no registered library");

        if (source.Id == target.Id) throw OperationException.Refused($"'{instance.Id}' is already in the library '{source.Name}'");
        if (LibraryCatalog.StateOf(target) != LibraryState.Online)
            throw OperationException.Refused($"the library '{target.Name}' is offline: {target.Path} is not there or is not that library");
        if (LibraryRules.OverlapsRegistry(target.Path, host.Paths.DataDirectory))
            throw OperationException.Refused($"the library '{target.Name}' overlaps the engine's registry directory");

        string destination = InstanceLayout.WorkingDirectoryFor(target.Path, instance.Blueprint, instance.Id);
        if (Directory.Exists(destination) || File.Exists(destination)) throw OperationException.Refused($"{destination} already exists");

        string? compose = null;
        if (config.Runtime == BlueprintRuntime.Container)
        {
            Blueprint blueprint = host.Blueprints.Read(config.Blueprint)?.Blueprint
                ?? throw OperationException.Refused($"the blueprint '{config.Blueprint}' of '{instance.Id}' is not readable, so its compose file cannot be rendered at the new place");
            compose = ComposeRenderer.Render(blueprint.Container!.Compose, config, new InstanceLayout(destination, instance.Id, config.ExecutableSubdirectory));
        }

        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        InstanceProcess process = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);
        if (process.State == RunState.Running)
            throw new OperationException(ErrorCodes.Running, $"'{instance.Id}' is running; stop it before moving it", ExitCodes.InstanceRunning);
        if (process.State == RunState.Unknown)
            throw OperationException.Refused($"whether '{instance.Id}' is running cannot be measured ({process.Detail ?? "no answer"})");

        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        bool rename = FileSystem.SameDevice(instance.WorkingDirectory, Path.GetDirectoryName(destination)!);
        if (!rename) CheckSpace(instance, target);

        bool hadRun = HadRun(instance.Layout);
        string method = rename ? "rename" : "copy";
        bool renamed = false;

        try
        {
            if (rename)
            {
                try
                {
                    Directory.Move(instance.WorkingDirectory, destination);
                    renamed = true;
                }
                catch (IOException ex)
                {
                    // A rename across two mounts of one device fails; the tree is copied instead.
                    log.LogInformation("The rename of {Id} failed ({Problem}); copying instead", instance.Id, ex.Message);
                    method = "copy";
                }
            }

            if (!renamed) CopyIntoPlace(instance.WorkingDirectory, destination, cancellationToken);

            if (compose is not null) File.WriteAllText(new InstanceLayout(destination, instance.Id).ComposeFile, compose, new System.Text.UTF8Encoding(false));
            host.Registry.Place(instance.Id, target.Id, destination);

            if (hadRun) await VerifyStartsAsync(instance.Id, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log.LogError(ex, "The move of {Id} to {Library} failed; putting it back", instance.Id, target.Name);
            PutBack(instance, source, destination, renamed, log);
            throw;
        }

        if (!renamed) TryDelete(instance.WorkingDirectory, log);
        FileSystem.RemoveEmptyInstanceParents(instance.WorkingDirectory);

        host.Events.Append(new Moved { InstanceName = instance.Id, FromLibrary = source.Name, ToLibrary = target.Name });
        return new MoveReport
        {
            Id = instance.Id,
            FromLibrary = source.Name,
            ToLibrary = target.Name,
            WorkingDirectory = destination,
            Method = method,
        };
    }

    private void CopyIntoPlace(string from, string to, CancellationToken cancellationToken)
    {
        string staging = Path.Combine(Path.GetDirectoryName(to)!, $".{Path.GetFileName(to)}.moving");
        FileSystem.CopyTree(from, staging, cancellationToken);
        Directory.Move(staging, to);
    }

    private void PutBack(InstanceDescription instance, LibraryRecord source, string destination, bool renamed, ILogger log)
    {
        try
        {
            if (host.Instances.Registered().TryGetValue(instance.Id, out var entry) && entry.WorkingDirectory != instance.WorkingDirectory)
                host.Registry.Place(instance.Id, source.Id, instance.WorkingDirectory);

            if (renamed && Directory.Exists(destination) && !Directory.Exists(instance.WorkingDirectory))
                Directory.Move(destination, instance.WorkingDirectory);
            else if (!renamed && Directory.Exists(destination) && Directory.Exists(instance.WorkingDirectory))
                Directory.Delete(destination, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or EngineException)
        {
            log.LogError(ex, "Could not put {Id} back at {Directory}; its files are at {Destination}", instance.Id, instance.WorkingDirectory, destination);
        }
    }

    /// <summary>Starts the instance at its new place and stops it again: the proof that it works there.</summary>
    private async Task VerifyStartsAsync(string id, CancellationToken cancellationToken)
    {
        InstanceDescription moved = host.Instances.Find(id)
            ?? throw new OperationException(ErrorCodes.Failed, $"'{id}' is not registered after the move");

        LifecycleService lifecycle = host.Lifecycle;
        await lifecycle.StartCoreAsync(moved, force: false, announce: false, cancellationToken).ConfigureAwait(false);
        await lifecycle.StopCoreAsync(moved, announce: false, cancellationToken).ConfigureAwait(false);
    }

    private void CheckSpace(InstanceDescription instance, LibraryRecord target)
    {
        long needed = DiskUsage.Of(instance.WorkingDirectory) ?? 0;
        long free;
        try
        {
            free = new DriveInfo(target.Path).AvailableFreeSpace;
        }
        catch (Exception ex) when (ex is IOException or ArgumentException or UnauthorizedAccessException)
        {
            return;
        }

        if (free < needed)
        {
            throw new OperationException(
                ErrorCodes.InsufficientDisk,
                $"the library '{target.Name}' has {free / (1024 * 1024)} MiB free and '{instance.Id}' holds {needed / (1024 * 1024)} MiB",
                ExitCodes.InsufficientDisk);
        }
    }

    /// <summary>
    /// Whether the instance has run: a native one leaves its log (or a rotated one), a container the
    /// lifecycle record its script appends to when it stops.
    /// </summary>
    private static bool HadRun(InstanceLayout layout) =>
        File.Exists(layout.LogFile)
        || File.Exists(Path.Combine(layout.EventsDirectory, "lifecycle.ndjson"))
        || (Directory.Exists(layout.LogsDirectory) && Directory.EnumerateFileSystemEntries(layout.LogsDirectory).Any());

    private static void TryDelete(string directory, ILogger log)
    {
        try
        {
            Directory.Delete(directory, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            log.LogWarning(ex, "The moved instance's old directory {Directory} could not be deleted; remove it by hand", directory);
        }
    }
}
