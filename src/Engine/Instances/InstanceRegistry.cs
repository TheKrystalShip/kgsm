using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Locks;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>
/// Writes the instance registry. Every change takes the global lock for the length of one read, edit and
/// atomic replace of <c>instances.json</c>, so two commands never overwrite each other's entry.
/// </summary>
public sealed class InstanceRegistry(EnginePaths paths, EngineLocks locks, InstanceStore store)
{
    /// <summary>Registers an instance under an id no instance on the host has.</summary>
    /// <exception cref="OperationException">The id is taken.</exception>
    public void Add(string id, InstanceRegistryEntry entry) => Edit(entries =>
    {
        if (!entries.TryAdd(id, entry)) throw OperationException.Refused($"an instance '{id}' is already registered");
    });

    /// <summary>Removes an instance's entry; false when there was none.</summary>
    public bool Remove(string id)
    {
        bool removed = false;
        Edit(entries => removed = entries.Remove(id));
        return removed;
    }

    /// <summary>Points an existing entry at a new library and working directory.</summary>
    /// <exception cref="OperationException">No such instance is registered.</exception>
    public void Place(string id, string libraryId, string workingDirectory) => Edit(entries =>
    {
        if (!entries.TryGetValue(id, out InstanceRegistryEntry? entry))
            throw OperationException.NotFound($"No instance '{id}' is registered.");

        entries[id] = entry with { Library = libraryId, WorkingDirectory = workingDirectory };
    });

    private void Edit(Action<SortedDictionary<string, InstanceRegistryEntry>> change)
    {
        using IDisposable held = locks.AcquireGlobal();

        var entries = new SortedDictionary<string, InstanceRegistryEntry>(store.Registered().ToDictionary(e => e.Key, e => e.Value), StringComparer.Ordinal);
        change(entries);

        ContractFile.Write(
            paths.InstanceRegistryFile,
            new InstanceRegistryFile { SchemaVersion = SchemaVersions.InstanceRegistry, Instances = entries },
            EngineJsonContext.Default.InstanceRegistryFile);
    }
}
