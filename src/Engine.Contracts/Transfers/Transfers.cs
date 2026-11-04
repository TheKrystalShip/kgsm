using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Network;

namespace TheKrystalShip.KGSM.Engine.Contracts.Transfers;

/// <summary>
/// What <c>transfer export --manifest</c> prints and <c>transfer import check|begin</c> read from standard
/// input: one instance, its blueprint, what the target must have, and the parts that travel. A consumer
/// passes it between nodes as it received it and never re-shapes it.
/// </summary>
public sealed record TransferManifest
{
    public required int SchemaVersion { get; init; }

    /// <summary>The engine version that wrote the manifest. A target on any other version refuses.</summary>
    public required string EngineVersion { get; init; }

    public required TransferInstance Instance { get; init; }

    public required TransferBlueprint Blueprint { get; init; }

    /// <summary>The requirement ids the target must have: <c>container-runtime</c>, <c>steamcmd</c>, <c>steam-credentials</c>.</summary>
    public required IReadOnlyList<string> Requirements { get; init; }

    /// <summary>The parts that travel: the tree first, then one per container image.</summary>
    public required IReadOnlyList<TransferPart> Parts { get; init; }
}

/// <summary>The instance section of a <see cref="TransferManifest"/>.</summary>
public sealed record TransferInstance
{
    /// <summary>The id on the source; the target registers the instance under a new one.</summary>
    public required string Id { get; init; }

    public required string Blueprint { get; init; }

    public required BlueprintRuntime Runtime { get; init; }

    /// <summary>The display name; null when none is set.</summary>
    public string? DisplayName { get; init; }

    /// <summary>The autostart flag as found before the lock switched it off.</summary>
    public required bool Autostart { get; init; }

    /// <summary>Whether the instance ever ran, which decides whether the import starts it once to prove it.</summary>
    public required bool HasRun { get; init; }

    /// <summary>The source's library name, for a person reading the manifest.</summary>
    public required string Library { get; init; }

    /// <summary>The ports the instance declares; tcp and udp are separate entries.</summary>
    public required IReadOnlyList<PortRange> Ports { get; init; }
}

/// <summary>The blueprint section of a <see cref="TransferManifest"/>.</summary>
public sealed record TransferBlueprint
{
    public required string Name { get; init; }

    /// <summary>True when the blueprint is the person's own file, which then travels in the tree part with its hooks.</summary>
    public required bool Custom { get; init; }

    /// <summary>The SHA-256 of the blueprint file, which tells a same-named file on the target apart; empty when the source could not read one.</summary>
    public required string Sha256 { get; init; }
}

/// <summary>What a part carries.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<TransferPartKind>))]
public enum TransferPartKind
{
    /// <summary>The working directory, the backups, and for a custom blueprint its file and hooks, as a tar stream.</summary>
    [JsonStringEnumMemberName("tree")]
    Tree = 0,

    /// <summary>One container image, as the container runtime saves it.</summary>
    [JsonStringEnumMemberName("image")]
    Image = 1,
}

/// <summary>One part of a <see cref="TransferManifest"/>.</summary>
public sealed record TransferPart
{
    /// <summary><c>tree</c>, or <c>image-N</c>.</summary>
    public required string Id { get; init; }

    public required TransferPartKind Kind { get; init; }

    /// <summary>The tree's bytes of regular files, or the room an image takes once loaded.</summary>
    public required long Bytes { get; init; }

    /// <summary>The tree's count of entries that are not directories; null on an image.</summary>
    public long? Files { get; init; }

    /// <summary>An image's reference; null on the tree.</summary>
    public string? Ref { get; init; }

    /// <summary>
    /// The digest of the image's layer chain, which the target compares after loading. It is the same on any
    /// host and in any image store, unlike the id a runtime reports; null on the tree.
    /// </summary>
    public string? ImageId { get; init; }
}

/// <summary>One reason a target refuses an import.</summary>
public sealed record ImportRefusal
{
    /// <summary>The exit status the refusal stands for: a contract code where there is one, otherwise 1.</summary>
    public required int ExitCode { get; init; }

    /// <summary>One of <see cref="ImportRefusalCodes"/>.</summary>
    public required string Code { get; init; }

    public required string Detail { get; init; }
}

/// <summary>The refusal codes of an <see cref="ImportRefusal"/>.</summary>
public static class ImportRefusalCodes
{
    public const string InvalidManifest = "invalid_manifest";

    public const string EngineVersionMismatch = "engine_version_mismatch";

    public const string RequirementMissing = "requirement_missing";

    public const string InsufficientDisk = "insufficient_disk";

    public const string PortConflict = "port_conflict";

    public const string LibraryNotFound = "library_not_found";

    public const string LibraryOffline = "library_offline";

    public const string LibraryOverlapsRegistry = "library_overlaps_registry";

    public const string BlueprintMissing = "blueprint_missing";

    public const string BlueprintCollision = "blueprint_collision";

    public const string InvalidSuffix = "invalid_suffix";
}

/// <summary>
/// The target's answer to <c>import check</c>, and to a refused <c>import begin</c>: every refusal, none
/// hidden behind the first.
/// </summary>
public sealed record ImportVerdict
{
    public required bool Ok { get; init; }

    public required IReadOnlyList<ImportRefusal> Refusals { get; init; }

    /// <summary>The library the import resolved to; null when none could be chosen.</summary>
    public string? Library { get; init; }

    /// <summary>The blueprint name the import resolves to, suffixed when a suffix applied; null when the manifest named none.</summary>
    public string? Blueprint { get; init; }
}

/// <summary>What <c>import begin</c> prints on acceptance.</summary>
public sealed record ImportBegun
{
    public required string ImportId { get; init; }
}

/// <summary>What <c>import finish</c> prints: the instance the target now holds.</summary>
public sealed record ImportedInstance
{
    public required string Instance { get; init; }

    public required string Blueprint { get; init; }

    public required string Library { get; init; }
}

/// <summary>One staged import, a row of <c>import list</c>.</summary>
public sealed record StagedImport
{
    public required string ImportId { get; init; }

    public required string Library { get; init; }

    /// <summary>The instance id the manifest names on the source.</summary>
    public required string Instance { get; init; }

    public required string Blueprint { get; init; }

    public required DateTimeOffset Began { get; init; }
}

/// <summary>What <c>import abort</c> removed.</summary>
public sealed record ImportAbortReport
{
    public required string ImportId { get; init; }

    /// <summary>False when no staged import had that id: an abort of nothing succeeds.</summary>
    public required bool Found { get; init; }

    /// <summary>The references of the images the import had loaded and verified, which the abort removed.</summary>
    public required IReadOnlyList<string> ImagesRemoved { get; init; }
}

/// <summary>What <c>export --commit</c> removed from the source.</summary>
public sealed record ExportCommitReport
{
    public required string Instance { get; init; }

    public required bool BackupsRemoved { get; init; }

    /// <summary>The image references removed because no other instance uses them.</summary>
    public required IReadOnlyList<string> ImagesRemoved { get; init; }
}

/// <summary>The lock file a transfer places in the working directory of the instance it holds.</summary>
public sealed record TransferLockRecord
{
    public required int SchemaVersion { get; init; }

    /// <summary>The holder's token.</summary>
    public required string Token { get; init; }

    /// <summary>The autostart flag the instance had when the lock switched it off, restored on release.</summary>
    public required bool Autostart { get; init; }
}

/// <summary>The staging record of an import, <c>meta.json</c> beside the staged manifest.</summary>
public sealed record ImportStageMeta
{
    public required int SchemaVersion { get; init; }

    public required string ImportId { get; init; }

    public required string Library { get; init; }

    public string? BlueprintSuffix { get; init; }

    public required DateTimeOffset Began { get; init; }

    /// <summary>For each image part, whether the container runtime held the image before the import began.</summary>
    public required IReadOnlyList<ImportStageImage> Images { get; init; }
}

/// <summary>An image part of a staged import and whether the host already held its image.</summary>
public sealed record ImportStageImage
{
    public required string PartId { get; init; }

    /// <summary>The layer-chain digest the manifest names.</summary>
    public required string ImageId { get; init; }

    /// <summary>Whether the reference already named this image.</summary>
    public required bool HeldBefore { get; init; }

    /// <summary>The runtime's id of the image the reference named before the import, which an abort puts the reference back on; null when it named none.</summary>
    public string? PreviousId { get; init; }
}
