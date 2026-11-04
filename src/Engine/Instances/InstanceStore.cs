using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>An instance as the engine reads it: its registry entry, the library it lies in, and its config when that could be read.</summary>
public sealed record InstanceDescription
{
    public required string Id { get; init; }

    public required string Blueprint { get; init; }

    public required string WorkingDirectory { get; init; }

    /// <summary>The library the working directory lies under; null when under none.</summary>
    public LibraryRecord? Library { get; init; }

    public required InstanceLibraryState LibraryState { get; init; }

    /// <summary>The config, or null when it could not be read: the library is offline, or the file is missing or refused.</summary>
    public InstanceConfig? Config { get; init; }

    /// <summary>Why <see cref="Config"/> is null; null when it is not.</summary>
    public string? ConfigProblem { get; init; }

    public InstanceLayout Layout => new(WorkingDirectory, Id, Config?.ExecutableSubdirectory ?? string.Empty);
}

/// <summary>
/// Reads the instance registry (<c>instances.json</c>) and each instance's config. Nothing here writes, and
/// an instance in an offline library stays listed with what can be said without its disk.
/// </summary>
public sealed class InstanceStore(EnginePaths paths, LibraryCatalog libraries, ILogger<InstanceStore>? logger = null)
{
    /// <summary>The registry by id; an absent file is an empty registry.</summary>
    /// <exception cref="UnsupportedSchemaVersionException">The registry is of a version this engine does not know.</exception>
    public IReadOnlyDictionary<string, InstanceRegistryEntry> Registered()
    {
        InstanceRegistryFile? file = ContractFile.ReadIfExists(
            paths.InstanceRegistryFile, EngineJsonContext.Default.InstanceRegistryFile,
            SchemaVersions.InstanceRegistry, f => f.SchemaVersion);
        return file?.Instances ?? new SortedDictionary<string, InstanceRegistryEntry>(StringComparer.Ordinal);
    }

    /// <summary>Every registered instance, in id order.</summary>
    public IReadOnlyList<InstanceDescription> List()
    {
        IReadOnlyDictionary<string, InstanceRegistryEntry> registry = Registered();
        IReadOnlyList<LibraryRecord> registered = libraries.Registered();

        return registry.Select(entry => Describe(entry.Key, entry.Value, registered)).ToList();
    }

    /// <summary>One instance by id, or null when none is registered under it.</summary>
    public InstanceDescription? Find(string id)
    {
        if (!Registered().TryGetValue(id, out InstanceRegistryEntry? entry)) return null;
        return Describe(id, entry, libraries.Registered());
    }

    /// <summary>
    /// One instance by id, or else by display name. An id matches exactly; a display name matches exactly
    /// and only when no id does.
    /// </summary>
    /// <returns>The instance, or null when nothing matches.</returns>
    /// <exception cref="AmbiguousInstanceException">Several instances carry that display name.</exception>
    public InstanceDescription? Resolve(string reference)
    {
        InstanceDescription? byId = Find(reference);
        if (byId is not null) return byId;

        InstanceDescription[] named =
        [
            .. List().Where(i => i.Config is { DisplayName.Length: > 0 } c
                && string.Equals(c.DisplayName, reference, StringComparison.Ordinal)),
        ];

        return named.Length switch
        {
            0 => null,
            1 => named[0],
            _ => throw new AmbiguousInstanceException(reference, [.. named.Select(i => i.Id)]),
        };
    }

    private InstanceDescription Describe(string id, InstanceRegistryEntry entry, IReadOnlyList<LibraryRecord> registered)
    {
        LibraryRecord? library = LibraryRules.Membership(registered, entry.WorkingDirectory);
        InstanceLibraryState state = LibraryCatalog.InstanceStateOf(library);

        InstanceConfig? config = null;
        string? problem = null;

        if (state != InstanceLibraryState.Offline)
        {
            string file = new InstanceLayout(entry.WorkingDirectory, id).ConfigFile;
            try
            {
                config = ContractFile.Read(
                    file, EngineJsonContext.Default.InstanceConfig, SchemaVersions.InstanceConfig, c => c.SchemaVersion);
            }
            catch (EngineException ex)
            {
                problem = ex.Message;
                logger?.LogWarning("Instance {Id} has no readable config: {Problem}", id, ex.Message);
            }
        }
        else
        {
            problem = $"library '{library!.Name}' is offline";
        }

        return new InstanceDescription
        {
            Id = id,
            Blueprint = entry.Blueprint,
            WorkingDirectory = entry.WorkingDirectory,
            Library = library,
            LibraryState = state,
            Config = config,
            ConfigProblem = problem,
        };
    }
}
