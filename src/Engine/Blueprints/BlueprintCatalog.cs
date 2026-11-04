using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Blueprints;

/// <summary>
/// Finds and reads blueprints. Blueprint files are flat <c>*.bp.yaml</c> in two directories, the user's and
/// the system's; a user file shadows a system file of the same file name. A blueprint's own <c>name:</c>
/// field is the key its per-game hooks bind to, so several files may share one name and one hook set.
/// </summary>
public sealed class BlueprintCatalog(EnginePaths paths, BlueprintParser parser)
{
    /// <summary>Where a file name could resolve to, user first, with whether a file is there.</summary>
    public BlueprintResolution Find(string key)
    {
        RequireKey(key);

        BlueprintCandidate[] candidates =
        [
            Candidate(BlueprintTier.User, paths.UserBlueprintsDirectory, key),
            Candidate(BlueprintTier.System, paths.SystemBlueprintsDirectory, key),
        ];

        BlueprintCandidate? winner = candidates.FirstOrDefault(c => c.Exists);

        return new BlueprintResolution
        {
            Name = key,
            Resolved = winner?.Path,
            Tier = winner?.Tier,
            Candidates = candidates,
        };
    }

    /// <summary>Reads the blueprint a file name resolves to, or null when no file exists under it.</summary>
    public BlueprintParseResult? Read(string key)
    {
        BlueprintResolution resolution = Find(key);
        return resolution.Resolved is null ? null : parser.ParseFile(resolution.Resolved);
    }

    /// <summary>Every blueprint file by file name, shadowing applied, ordered by name. A file that does not validate is listed with its errors.</summary>
    public IReadOnlyList<BlueprintListing> List()
    {
        var byKey = new SortedDictionary<string, (BlueprintTier Tier, string Path)>(StringComparer.Ordinal);

        foreach ((BlueprintTier tier, string directory) in new[]
        {
            (BlueprintTier.System, paths.SystemBlueprintsDirectory),
            (BlueprintTier.User, paths.UserBlueprintsDirectory),
        })
        {
            if (!Directory.Exists(directory)) continue;

            foreach (string file in Directory.EnumerateFiles(directory, "*" + EnginePaths.BlueprintFileSuffix))
            {
                string key = Path.GetFileName(file)[..^EnginePaths.BlueprintFileSuffix.Length];
                byKey[key] = (tier, file);
            }
        }

        var listing = new List<BlueprintListing>(byKey.Count);
        foreach ((string key, (BlueprintTier tier, string path)) in byKey)
        {
            BlueprintParseResult result = parser.ParseFile(path);
            listing.Add(new BlueprintListing
            {
                Key = key,
                Tier = tier,
                Path = path,
                Blueprint = result.Blueprint,
                Errors = result.Validation.Errors,
            });
        }

        return listing;
    }

    /// <summary>
    /// The hooks file for a game: <c>overrides/&lt;name&gt;/hooks.sh</c>, found by the blueprint's <c>name:</c>.
    /// A user file replaces the system file whole. Null when the game has none.
    /// </summary>
    public string? FindHooks(string blueprintName) => Scripts.HookFiles.FindPath(paths, blueprintName);

    private static BlueprintCandidate Candidate(BlueprintTier tier, string directory, string key)
    {
        string path = Path.Combine(directory, key + EnginePaths.BlueprintFileSuffix);
        return new BlueprintCandidate { Tier = tier, Path = path, Exists = File.Exists(path) };
    }

    private static void RequireKey(string key)
    {
        if (!BlueprintParser.IsValidName(key))
            throw new ArgumentException($"'{key}' is not a blueprint file name.", nameof(key));
    }
}
