using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Registers, renames and deregisters libraries. Every registry write holds the global lock, and the
/// refusals are all decided before a directory is created. A library's files are never deleted.
/// </summary>
public sealed class LibraryService(OperationHost host)
{
    /// <summary>The name the first library is registered under.</summary>
    public const string DefaultName = "default";

    public LibraryChangeReport Add(string name, string root)
    {
        using IDisposable held = host.Locks.AcquireGlobal();

        IReadOnlyList<LibraryRecord> existing = host.Libraries.Registered();
        string canonical = LibraryRules.Canonical(root);
        LibraryMarker? marker = Directory.Exists(canonical) ? LibraryCatalog.ReadMarker(canonical) : null;

        IReadOnlyList<string> refusals = LibraryRules.AddRefusals(existing, name, canonical, marker?.Id, host.Paths.DataDirectory);
        if (refusals.Count > 0) throw OperationException.Refused(refusals[0], [.. refusals.Skip(1)]);

        Directory.CreateDirectory(canonical);
        var record = new LibraryRecord { Name = name, Id = marker?.Id ?? LibraryCatalog.NewId(), Path = canonical };
        WriteMarker(record);
        WriteRegistry([.. existing, record]);

        host.Events.Append(new LibraryAdded { LibraryName = name, Path = canonical });
        return Report(record);
    }

    /// <summary>The first library, registered at <c>$XDG_DATA_HOME/kgsm-library</c> when the host has none.</summary>
    public void EnsureFirst()
    {
        if (host.Libraries.Registered().Count > 0) return;
        Add(DefaultName, Path.Combine(host.Paths.DataHome, "kgsm-library"));
    }

    public LibraryChangeReport Rename(string from, string to)
    {
        using IDisposable held = host.Locks.AcquireGlobal();

        IReadOnlyList<LibraryRecord> existing = host.Libraries.Registered();
        IReadOnlyList<string> refusals = LibraryRules.RenameRefusals(existing, from, to);
        if (refusals.Count > 0) throw OperationException.Refused(refusals[0], [.. refusals.Skip(1)]);

        LibraryRecord renamed = existing.First(l => l.Name == from) with { Name = to };
        WriteRegistry([.. existing.Select(l => l.Name == from ? renamed : l)]);

        if (LibraryCatalog.StateOf(renamed) == LibraryState.Online) WriteMarker(renamed);

        host.Events.Append(new LibraryRenamed { LibraryName = to, OldName = from, Path = renamed.Path });
        return Report(renamed);
    }

    /// <summary>
    /// Deregisters a library. While instances live in it the removal is refused, unless they are drained to
    /// <paramref name="drainTarget"/> one at a time, or <paramref name="force"/> leaves them unregistered.
    /// </summary>
    public async Task<LibraryChangeReport> RemoveAsync(string name, bool force, string? drainTarget, CancellationToken cancellationToken)
    {
        LibraryRecord library = host.Libraries.Registered().FirstOrDefault(l => l.Name == name)
            ?? throw OperationException.NotFound($"No library '{name}' is registered.");

        if (force && drainTarget is not null) throw OperationException.Invalid("--force and --drain exclude each other");
        if (drainTarget == name) throw OperationException.Invalid("a library cannot be drained into itself");

        IReadOnlyList<string> blockers = LibraryRules.RemovalBlockers(library, host.Instances.Registered());
        var affected = new List<string>();

        if (blockers.Count > 0 && drainTarget is not null)
        {
            var move = new MoveService(host);
            foreach (string id in blockers)
            {
                InstanceDescription instance = host.Instances.Find(id)!;
                await move.MoveAsync(instance, drainTarget, cancellationToken).ConfigureAwait(false);
                affected.Add(id);
            }
        }
        else if (blockers.Count > 0 && !force)
        {
            throw OperationException.Refused(
                $"library '{name}' still holds {blockers.Count} instance(s): {string.Join(", ", blockers)}",
                ["move them with --drain <library>, or deregister the library and leave them unregistered with --force"]);
        }
        else
        {
            affected.AddRange(blockers);
        }

        using IDisposable held = host.Locks.AcquireGlobal();
        IReadOnlyList<LibraryRecord> existing = host.Libraries.Registered();
        WriteRegistry([.. existing.Where(l => l.Id != library.Id)]);

        host.Events.Append(new LibraryRemoved { LibraryName = name, Path = library.Path });
        return Report(library) with { Instances = drainTarget is null ? affected : [] };
    }

    private void WriteRegistry(IReadOnlyList<LibraryRecord> libraries) =>
        ContractFile.Write(
            host.Paths.LibraryRegistryFile,
            new LibraryRegistryFile { SchemaVersion = SchemaVersions.LibraryRegistry, Libraries = [.. libraries] },
            EngineJsonContext.Default.LibraryRegistryFile);

    private static void WriteMarker(LibraryRecord library) =>
        ContractFile.Write(
            Path.Combine(library.Path, LibraryRules.MarkerFileName),
            new LibraryMarker { SchemaVersion = SchemaVersions.LibraryMarker, Id = library.Id, Name = library.Name },
            EngineJsonContext.Default.LibraryMarker);

    private static LibraryChangeReport Report(LibraryRecord library) =>
        new() { Name = library.Name, Id = library.Id, Path = library.Path };
}
