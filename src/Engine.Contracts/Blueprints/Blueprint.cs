using System.Text.Json.Serialization;

namespace TheKrystalShip.KGSM.Engine.Contracts.Blueprints;

/// <summary>How a game server runs.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<BlueprintRuntime>))]
public enum BlueprintRuntime
{
    [JsonStringEnumMemberName("native")]
    Native = 0,

    [JsonStringEnumMemberName("container")]
    Container = 1,
}

/// <summary>
/// A blueprint as the engine reads it: the typed content of one <c>*.bp.yaml</c> file. Text a blueprint
/// leaves unset is empty; a figure it leaves unset is null, which means unknown and never zero.
/// </summary>
public sealed record Blueprint
{
    public required string Name { get; init; }

    public required BlueprintRuntime Runtime { get; init; }

    public required BlueprintMetadata Metadata { get; init; }

    public string PlayerJoinedRegex { get; init; } = string.Empty;

    public string PlayerLeftRegex { get; init; } = string.Empty;

    /// <summary>The game server's RCON port; null leaves RCON presence detection off.</summary>
    public int? RconPort { get; init; }

    public string RconPassword { get; init; } = string.Empty;

    public int? RconPollIntervalSeconds { get; init; }

    public string RconPlayersCommand { get; init; } = string.Empty;

    public string RconPlayersRegex { get; init; } = string.Empty;

    public string KickCommand { get; init; } = string.Empty;

    public string BanCommand { get; init; } = string.Empty;

    public string UnbanCommand { get; init; } = string.Empty;

    public string BroadcastCommand { get; init; } = string.Empty;

    /// <summary>Present for a native blueprint.</summary>
    public NativeBlueprint? Native { get; init; }

    /// <summary>Present for a container blueprint.</summary>
    public ContainerBlueprint? Container { get; init; }
}

/// <summary>Advisory presentation figures. Every value may be null, meaning unknown or unbounded.</summary>
public sealed record BlueprintMetadata
{
    public string? DisplayName { get; init; }

    public string? Description { get; init; }

    public string? RawgSlug { get; init; }

    public int? MaxPlayers { get; init; }

    public int? MinRamMb { get; init; }

    public int? RecommendedRamMb { get; init; }

    public int? BaseDiskMb { get; init; }
}

/// <summary>The <c>native:</c> block.</summary>
public sealed record NativeBlueprint
{
    /// <summary>Ports in UFW format, pipe-separated.</summary>
    public string Ports { get; init; } = string.Empty;

    public long SteamAppId { get; init; }

    public long ClientSteamAppId { get; init; }

    public string SteamcmdArguments { get; init; } = string.Empty;

    public bool IsSteamAccountRequired { get; init; }

    public string Platform { get; init; } = string.Empty;

    public string LevelName { get; init; } = string.Empty;

    public string ExecutableSubdirectory { get; init; } = string.Empty;

    public required string ExecutableFile { get; init; }

    /// <summary>The launch arguments, with the blueprint's <c>$instance_&lt;key&gt;</c> references as written.</summary>
    public string ExecutableArguments { get; init; } = string.Empty;

    public string StopCommand { get; init; } = string.Empty;

    public string SaveCommand { get; init; } = string.Empty;

    public string StartupSuccessRegex { get; init; } = string.Empty;
}

/// <summary>The <c>container:</c> block.</summary>
public sealed record ContainerBlueprint
{
    /// <summary>The compose document, byte for byte as the blueprint carries it.</summary>
    public required string Compose { get; init; }
}
