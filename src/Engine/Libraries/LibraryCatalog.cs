using System.Security.Cryptography;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Libraries;

/// <summary>
/// Reads the library registry and measures each library against its disk. A library is <b>online</b> when its
/// root exists and carries a marker whose id is the registered one; anything else is <b>offline</b>. The
/// state is measured on every call and never cached, because a disk's presence changes between two
/// invocations. Offline is a state, not an error: an unplugged disk is a measured absence.
/// </summary>
public sealed class LibraryCatalog(EnginePaths paths)
{
    /// <summary>The registered libraries in file order; an absent registry is an empty one.</summary>
    public IReadOnlyList<LibraryRecord> Registered()
    {
        LibraryRegistryFile? file = ContractFile.ReadIfExists(
            paths.LibraryRegistryFile, EngineJsonContext.Default.LibraryRegistryFile, SchemaVersions.LibraryRegistry, f => f.SchemaVersion);
        return file?.Libraries ?? [];
    }

    /// <summary>The marker in a root, or null when the root has none or its marker is unreadable or of a version this engine does not know.</summary>
    public static LibraryMarker? ReadMarker(string root)
    {
        try
        {
            return ContractFile.ReadIfExists(
                Path.Combine(root, LibraryRules.MarkerFileName), EngineJsonContext.Default.LibraryMarker,
                SchemaVersions.LibraryMarker, m => m.SchemaVersion);
        }
        catch (EngineException)
        {
            return null;
        }
    }

    public static LibraryState StateOf(LibraryRecord library) =>
        Directory.Exists(library.Path) && ReadMarker(library.Path)?.Id == library.Id
            ? LibraryState.Online
            : LibraryState.Offline;

    /// <summary>Where an instance's library stands: <c>unregistered</c> when it lies under no registered root.</summary>
    public static InstanceLibraryState InstanceStateOf(LibraryRecord? library) => library is null
        ? InstanceLibraryState.Unregistered
        : StateOf(library) == LibraryState.Online ? InstanceLibraryState.Online : InstanceLibraryState.Offline;

    /// <summary>
    /// Every library with its state, free and total bytes, and instance count. An offline library reports
    /// no figures, because nothing measured them.
    /// </summary>
    public IReadOnlyList<Library> List(IReadOnlyDictionary<string, InstanceRegistryEntry> instances)
    {
        IReadOnlyList<LibraryRecord> libraries = Registered();
        var listing = new List<Library>(libraries.Count);

        foreach (LibraryRecord record in libraries)
        {
            LibraryState state = StateOf(record);
            (long free, long total)? space = state == LibraryState.Online ? MeasureSpace(record.Path) : null;

            listing.Add(new Library
            {
                Name = record.Name,
                Id = record.Id,
                Path = record.Path,
                State = state,
                FreeBytes = space?.free,
                TotalBytes = space?.total,
                InstanceCount = instances.Values.Count(i => LibraryRules.Membership(libraries, i.WorkingDirectory)?.Id == record.Id),
            });
        }

        return listing;
    }

    /// <summary>Mints a library id: 16 lowercase hex characters from the kernel's random source.</summary>
    public static string NewId() => Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(8));

    private static (long free, long total)? MeasureSpace(string root)
    {
        try
        {
            var drive = new DriveInfo(root);
            return (drive.AvailableFreeSpace, drive.TotalSize);
        }
        catch (Exception ex) when (ex is IOException or ArgumentException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
