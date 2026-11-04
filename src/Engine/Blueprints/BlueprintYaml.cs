using YamlDotNet.Serialization;

namespace TheKrystalShip.KGSM.Engine.Blueprints;

// The on-disk shape of a blueprint file, field for field. Every scalar is read as text and typed by
// BlueprintParser, because blueprints write the same field as "", null, a number or a bool, and a failed
// conversion has to become a validation error rather than a thrown parse. These types are internal;
// callers see Contracts.Blueprints.Blueprint.

[YamlSerializable]
internal sealed class BlueprintYamlFile
{
    public string? SchemaVersion { get; set; }

    public string? Name { get; set; }

    public string? Runtime { get; set; }

    public BlueprintYamlMetadata? Metadata { get; set; }

    public string? PlayerJoinedRegex { get; set; }

    public string? PlayerLeftRegex { get; set; }

    public string? RconPort { get; set; }

    public string? RconPassword { get; set; }

    public string? RconPollIntervalSeconds { get; set; }

    public string? RconPlayersCommand { get; set; }

    public string? RconPlayersRegex { get; set; }

    public string? KickCommand { get; set; }

    public string? BanCommand { get; set; }

    public string? UnbanCommand { get; set; }

    public string? BroadcastCommand { get; set; }

    public BlueprintYamlNative? Native { get; set; }

    public BlueprintYamlContainer? Container { get; set; }
}

[YamlSerializable]
internal sealed class BlueprintYamlMetadata
{
    public string? DisplayName { get; set; }

    public string? Description { get; set; }

    public string? RawgSlug { get; set; }

    public string? MaxPlayers { get; set; }

    public string? MinRamMb { get; set; }

    public string? RecommendedRamMb { get; set; }

    public string? BaseDiskMb { get; set; }
}

[YamlSerializable]
internal sealed class BlueprintYamlNative
{
    public string? Ports { get; set; }

    public string? SteamAppId { get; set; }

    public string? ClientSteamAppId { get; set; }

    public string? SteamcmdArguments { get; set; }

    public string? IsSteamAccountRequired { get; set; }

    public string? Platform { get; set; }

    public string? LevelName { get; set; }

    public string? ExecutableSubdirectory { get; set; }

    public string? ExecutableFile { get; set; }

    public string? ExecutableArguments { get; set; }

    public string? StopCommand { get; set; }

    public string? SaveCommand { get; set; }

    public string? StartupSuccessRegex { get; set; }
}

[YamlSerializable]
internal sealed class BlueprintYamlContainer
{
    public string? Compose { get; set; }
}

// The compose document a container blueprint embeds: only what validation reads.

[YamlSerializable]
internal sealed class ComposeYamlFile
{
    public Dictionary<string, ComposeYamlService?>? Services { get; set; }
}

[YamlSerializable]
internal sealed class ComposeYamlService
{
    public string? NetworkMode { get; set; }
}

[YamlStaticContext]
[YamlSerializable(typeof(BlueprintYamlFile))]
[YamlSerializable(typeof(ComposeYamlFile))]
public partial class BlueprintYamlContext : YamlDotNet.Serialization.StaticContext;
