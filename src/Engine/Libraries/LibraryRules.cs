using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;

namespace TheKrystalShip.KGSM.Engine.Libraries;

/// <summary>
/// The pure rules of libraries: what a name may be, which root is the same, contained or overlapping,
/// which library an instance belongs to, which library a placement picks, and what stops an add, a
/// remove or a rename. Nothing here touches the disk.
/// </summary>
public static partial class LibraryRules
{
    public const string MarkerFileName = ".kgsm-library";

    [GeneratedRegex("^[a-z0-9][a-z0-9-]*$")]
    private static partial Regex NamePattern();

    /// <summary>A library name is lowercase letters, digits and hyphens, starting with a letter or digit.</summary>
    public static bool IsValidName(string? name) => name is not null && NamePattern().IsMatch(name);

    /// <summary>A path in the form comparisons use: absolute, normalised, without a trailing separator.</summary>
    public static string Canonical(string path)
    {
        string full = Path.GetFullPath(path);
        return full.Length > 1 ? full.TrimEnd(Path.DirectorySeparatorChar) : full;
    }

    /// <summary>Whether <paramref name="path"/> is <paramref name="root"/> or lies inside it.</summary>
    public static bool IsWithin(string path, string root)
    {
        string p = Canonical(path);
        string r = Canonical(root);

        if (p == r) return true;
        string prefix = r == "/" ? "/" : r + Path.DirectorySeparatorChar;
        return p.StartsWith(prefix, StringComparison.Ordinal);
    }

    /// <summary>
    /// Whether a library root overlaps the directory that holds the engine's registries: it is that
    /// directory, contains it, or lies inside it. Placement writes <c>&lt;root&gt;/instances/&lt;blueprint&gt;/&lt;id&gt;</c>,
    /// and the engine's own state must not share a tree with game data.
    /// </summary>
    public static bool OverlapsRegistry(string libraryRoot, string registryDirectory) =>
        IsWithin(libraryRoot, registryDirectory) || IsWithin(registryDirectory, libraryRoot);

    /// <summary>
    /// The library an instance belongs to: the registered library whose root is the longest prefix of the
    /// working directory, so a library nested inside another resolves to the inner one. Null when the
    /// instance lies under no registered root, which is reported rather than assigned to the nearest.
    /// </summary>
    public static LibraryRecord? Membership(IEnumerable<LibraryRecord> libraries, string workingDirectory) =>
        libraries
            .Where(library => IsWithin(workingDirectory, library.Path))
            .OrderByDescending(library => Canonical(library.Path).Length)
            .FirstOrDefault();

    /// <summary>
    /// Picks the library an install is placed in: the one named, else the configured default, else the only
    /// one registered. Refuses when none can be chosen, when it is not registered, and when it is offline.
    /// </summary>
    public static PlacementChoice ChoosePlacement(
        IReadOnlyList<LibraryRecord> libraries,
        Func<LibraryRecord, LibraryState> stateOf,
        string? requested,
        string? configuredDefault)
    {
        string? wanted = !string.IsNullOrEmpty(requested) ? requested
            : !string.IsNullOrEmpty(configuredDefault) ? configuredDefault
            : null;

        LibraryRecord? chosen;
        if (wanted is not null)
        {
            chosen = libraries.FirstOrDefault(l => l.Name == wanted);
            if (chosen is null)
                return PlacementChoice.Refused($"library '{wanted}' is not registered");
        }
        else if (libraries.Count == 1)
        {
            chosen = libraries[0];
        }
        else if (libraries.Count == 0)
        {
            return PlacementChoice.Refused("no library is registered");
        }
        else
        {
            return PlacementChoice.Refused(
                $"{libraries.Count} libraries are registered and none is chosen; name one or set the default library");
        }

        return stateOf(chosen) == LibraryState.Online
            ? PlacementChoice.Chosen(chosen)
            : PlacementChoice.Refused($"library '{chosen.Name}' is offline: {chosen.Path} is not there or is not that library");
    }

    /// <summary>What stops registering a library, or an empty list.</summary>
    /// <param name="existing">The registered libraries.</param>
    /// <param name="name">The name asked for.</param>
    /// <param name="root">The root asked for.</param>
    /// <param name="markerId">The id the root's marker carries, when it has one.</param>
    /// <param name="registryDirectory">The directory that holds the engine's registries.</param>
    public static IReadOnlyList<string> AddRefusals(
        IReadOnlyList<LibraryRecord> existing, string name, string root, string? markerId, string registryDirectory)
    {
        var refusals = new List<string>();
        string canonical = Canonical(root);

        if (!IsValidName(name))
            refusals.Add($"'{name}' is not a library name: use lowercase letters, digits and hyphens, starting with a letter or digit");

        if (existing.FirstOrDefault(l => Canonical(l.Path) == canonical) is { } sameRoot)
            refusals.Add($"{canonical} is already the library '{sameRoot.Name}'");

        if (markerId is not null && existing.FirstOrDefault(l => l.Id == markerId && Canonical(l.Path) != canonical) is { } elsewhere)
            refusals.Add($"the marker in {canonical} names the library '{elsewhere.Name}', which is registered at {elsewhere.Path}");

        if (existing.Any(l => l.Name == name))
            refusals.Add($"the name '{name}' is taken by another library");

        if (OverlapsRegistry(canonical, registryDirectory))
            refusals.Add($"{canonical} overlaps the engine's registry directory {Canonical(registryDirectory)}");

        return refusals;
    }

    /// <summary>What stops renaming a library, or an empty list.</summary>
    public static IReadOnlyList<string> RenameRefusals(IReadOnlyList<LibraryRecord> existing, string from, string to)
    {
        var refusals = new List<string>();

        if (existing.All(l => l.Name != from))
            refusals.Add($"library '{from}' is not registered");
        if (!IsValidName(to))
            refusals.Add($"'{to}' is not a library name: use lowercase letters, digits and hyphens, starting with a letter or digit");
        else if (from != to && existing.Any(l => l.Name == to))
            refusals.Add($"the name '{to}' is taken by another library");

        return refusals;
    }

    /// <summary>The instances that stop a library being removed: every one placed in it.</summary>
    public static IReadOnlyList<string> RemovalBlockers(
        LibraryRecord library, IEnumerable<KeyValuePair<string, Contracts.Instances.InstanceRegistryEntry>> instances) =>
        instances
            .Where(i => IsWithin(i.Value.WorkingDirectory, library.Path))
            .Select(i => i.Key)
            .Order(StringComparer.Ordinal)
            .ToList();
}

/// <summary>The outcome of choosing a placement library.</summary>
public sealed record PlacementChoice
{
    public LibraryRecord? Library { get; private init; }

    public string? Refusal { get; private init; }

    public bool Ok => Library is not null;

    public static PlacementChoice Chosen(LibraryRecord library) => new() { Library = library };

    public static PlacementChoice Refused(string reason) => new() { Refusal = reason };
}
