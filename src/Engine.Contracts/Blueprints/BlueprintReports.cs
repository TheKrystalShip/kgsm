using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Engine.Contracts.Events;

namespace TheKrystalShip.KGSM.Engine.Contracts.Blueprints;

/// <summary>The verdict of validating one blueprint file. Every problem found is listed, not the first.</summary>
public sealed record BlueprintValidation
{
    public required bool Valid { get; init; }

    public required string Path { get; init; }

    public required IReadOnlyList<string> Errors { get; init; }
}

/// <summary>What a blueprint needs from the host.</summary>
public sealed record BlueprintRequirements
{
    public required string Blueprint { get; init; }

    public required IReadOnlyList<RequirementState> Requirements { get; init; }

    /// <summary>True when every requirement is present.</summary>
    [JsonIgnore]
    public bool Satisfied => Requirements.All(r => r.Present);
}

/// <summary>One requirement and whether this host has it.</summary>
public sealed record RequirementState(string Id, bool Present);

/// <summary>The requirement ids.</summary>
public static class RequirementIds
{
    public const string ContainerRuntime = "container-runtime";

    public const string Steamcmd = "steamcmd";

    public const string SteamCredentials = "steam-credentials";
}

/// <summary>One path a blueprint name could resolve to, and whether a file is there.</summary>
public sealed record BlueprintCandidate
{
    public required BlueprintTier Tier { get; init; }

    public required string Path { get; init; }

    public required bool Exists { get; init; }
}

/// <summary>
/// Where a blueprint name resolves: the winning file and every candidate, so a broken file can still be
/// found for repair. Candidates are in precedence order, the user directory first.
/// </summary>
public sealed record BlueprintResolution
{
    public required string Name { get; init; }

    /// <summary>The winning file's path, or null when no candidate exists.</summary>
    public string? Resolved { get; init; }

    /// <summary>The tier of the winning file, or null when no candidate exists.</summary>
    public BlueprintTier? Tier { get; init; }

    public required IReadOnlyList<BlueprintCandidate> Candidates { get; init; }
}

/// <summary>A blueprint file in a listing: its file-name key, its tier, and the content or the reason it has none.</summary>
public sealed record BlueprintListing
{
    /// <summary>The file name without <c>.bp.yaml</c>; the key a user file shadows a system file by.</summary>
    public required string Key { get; init; }

    public required BlueprintTier Tier { get; init; }

    public required string Path { get; init; }

    /// <summary>The blueprint, or null when the file does not validate.</summary>
    public Blueprint? Blueprint { get; init; }

    /// <summary>Why the file has no blueprint; empty when it has one.</summary>
    public IReadOnlyList<string> Errors { get; init; } = [];
}
