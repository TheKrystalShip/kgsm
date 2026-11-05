namespace TheKrystalShip.KGSM.Engine.Contracts.Blueprints;

/// <summary>
/// A draft of a native-runtime blueprint: the typed input a surface fills in instead of writing YAML. Every
/// field mirrors one native blueprint field one-for-one; the engine core renders it into a
/// <c>&lt;name&gt;.bp.yaml</c> string and validates the result when it is written.
/// </summary>
public sealed record NativeBlueprintDraft
{
    /// <summary>
    /// The blueprint's unique name — lowercase, <c>[a-z0-9_-]</c> only, no path separators. Both the
    /// file's basename (<c>&lt;name&gt;.bp.yaml</c>) and the in-file <c>name:</c> field. Also the
    /// override-binding key (not used by this DTO, but load-bearing for the engine).
    /// </summary>
    public required string Name { get; init; }

    /// <summary>
    /// Optional regex matched against the server's log output to detect a player joining, or
    /// <see langword="null"/> to leave player-presence detection disabled (the common case — author this
    /// only from REAL, observed server output, never guessed). See the top-level
    /// <c>player_joined_regex</c> field in <c>templates/blueprint.tp</c> for the full authoring contract
    /// (optional named groups <c>(?&lt;id&gt;...)</c>/<c>(?&lt;name&gt;...)</c>).
    /// </summary>
    public string? PlayerJoinedRegex { get; init; }

    /// <summary>
    /// Optional regex matched against the server's log output to detect a player leaving; see
    /// <see cref="PlayerJoinedRegex"/>.
    /// </summary>
    public string? PlayerLeftRegex { get; init; }

    /// <summary>
    /// Advisory presentation metadata. Every key is always emitted in the generated file; any field left
    /// <see langword="null"/> here renders as YAML <c>null</c> — never a fabricated placeholder value.
    /// Defaults to an all-<see langword="null"/> instance (every field unknown) when not supplied.
    /// </summary>
    public NativeBlueprintMetadataDraft Metadata { get; init; } = new();

    /// <summary>
    /// The native-runtime fields — see <see cref="NativeBlueprintNativeDraft"/>.
    /// </summary>
    public required NativeBlueprintNativeDraft Native { get; init; }
}

/// <summary>
/// The <c>metadata:</c> block of a native blueprint draft — advisory, presentation-oriented, and
/// entirely nullable. Mirrors <see cref="BlueprintMetadata"/> (the READ side's shape for the same block)
/// field-for-field; kept as a separate type because a draft is caller-authored input, not
/// engine-reported output. <see langword="null"/> always means "unknown" and is NEVER replaced by a
/// fabricated <c>0</c> — see <see cref="BlueprintMetadata"/>'s remarks for the full rationale.
/// </summary>
public sealed record NativeBlueprintMetadataDraft
{
    /// <summary>The human-friendly game name (e.g. "7 Days to Die"), or null if unverified.</summary>
    public string? DisplayName { get; init; }

    /// <summary>A short description of the game/server, or null if unverified.</summary>
    public string? Description { get; init; }

    /// <summary>The game's slug on RAWG.io, or null unless it was actually verified to resolve to this
    /// game (see <see cref="BlueprintMetadata.RawgSlug"/> — a wrong slug is misattribution).</summary>
    public string? RawgSlug { get; init; }

    /// <summary>The maximum number of players, or null if unbounded/configurable/unknown.</summary>
    public int? MaxPlayers { get; init; }

    /// <summary>The advisory minimum RAM in megabytes, or null if unknown.</summary>
    public int? MinRamMb { get; init; }

    /// <summary>The advisory recommended RAM in megabytes, or null if unknown.</summary>
    public int? RecommendedRamMb { get; init; }

    /// <summary>The advisory base install footprint in megabytes, or null if unknown.</summary>
    public int? BaseDiskMb { get; init; }
}

/// <summary>
/// The <c>native:</c> block of a native blueprint draft. <see cref="ExecutableFile"/> is the only
/// strictly required native field (per <c>templates/blueprint.tp</c>); every other field defaults to the
/// same value the template documents for an unset/no-op field, so a minimal draft renders a
/// structurally valid (if mostly inert) blueprint.
/// </summary>
public sealed record NativeBlueprintNativeDraft
{
    /// <summary>Port(s) in UFW format, single string, pipe-separated (e.g.
    /// <c>"2456:2458/tcp|2456:2458/udp"</c>). Empty if not yet known.</summary>
    public string Ports { get; init; } = string.Empty;

    /// <summary>The Steam App ID of the DEDICATED SERVER, or 0 if not a Steam download.</summary>
    public int SteamAppId { get; init; }

    /// <summary>The client Steam App ID players launch to connect, or 0 if not Steam.</summary>
    public int ClientSteamAppId { get; init; }

    /// <summary>Extra steamcmd arguments (e.g. <c>"+beta &lt;branch&gt;"</c>); empty if none.</summary>
    public string SteamcmdArguments { get; init; } = string.Empty;

    /// <summary>Only relevant when <see cref="SteamAppId"/> is non-zero: true if a Steam account is
    /// required to download the dedicated server.</summary>
    public bool IsSteamAccountRequired { get; init; }

    /// <summary>Target platform: <c>linux</c> | <c>windows</c> | <c>macos</c>. Defaults to
    /// <c>"linux"</c> — the scope this authority targets (see the type header note).</summary>
    public string Platform { get; init; } = "linux";

    /// <summary>Default world/save/level name. Defaults to <c>"default"</c>, matching the template.</summary>
    public string LevelName { get; init; } = "default";

    /// <summary>Optional subdirectory (relative to the install dir) the binary runs from; empty if the
    /// binary sits at the install root.</summary>
    public string ExecutableSubdirectory { get; init; } = string.Empty;

    /// <summary>
    /// The executable that starts the server. The ONE strictly required native field — a blank value
    /// is an invalid draft, refused before anything is written.
    /// </summary>
    public required string ExecutableFile { get; init; }

    /// <summary>Arguments passed to the executable; may reference <c>$instance_*</c> variables the
    /// engine resolves at instance-creation time. Empty if none.</summary>
    public string ExecutableArguments { get; init; } = string.Empty;

    /// <summary>Optional command sent to the input socket to gracefully stop the server; empty if none.</summary>
    public string StopCommand { get; init; } = string.Empty;

    /// <summary>Optional command sent to the input socket to save the game state; empty if none.</summary>
    public string SaveCommand { get; init; } = string.Empty;

    /// <summary>Optional regex matched against server output to detect successful startup — also the
    /// verification readiness signal for the assistant's blueprint-authoring pipeline. Empty means the
    /// engine waits for the server to listen on its ports instead.</summary>
    public string StartupSuccessRegex { get; init; } = string.Empty;
}
