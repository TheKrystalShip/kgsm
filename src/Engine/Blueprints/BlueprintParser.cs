using System.Globalization;
using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using YamlDotNet.Core;
using YamlDotNet.Serialization;

namespace TheKrystalShip.KGSM.Engine.Blueprints;

/// <summary>What reading one blueprint file produced: the blueprint when it is valid, and every problem when it is not.</summary>
public sealed record BlueprintParseResult(Blueprint? Blueprint, BlueprintValidation Validation)
{
    public bool Valid => Validation.Valid;
}

/// <summary>
/// Reads a blueprint file through the static YAML context and checks it against every rule. All problems
/// are collected, not the first, so a person fixing a file sees the whole list at once.
/// </summary>
public sealed class BlueprintParser(ILogger<BlueprintParser>? logger = null)
{
    private static readonly IDeserializer Deserializer = new StaticDeserializerBuilder(new BlueprintYamlContext())
        .WithNamingConvention(YamlDotNet.Serialization.NamingConventions.UnderscoredNamingConvention.Instance)
        .IgnoreUnmatchedProperties()
        .Build();

    /// <summary>Reads and validates the file at <paramref name="path"/>.</summary>
    public BlueprintParseResult ParseFile(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);

        string text;
        try
        {
            text = File.ReadAllText(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return Fail(path, $"Blueprint file cannot be read: {path}");
        }

        return Parse(text, path);
    }

    /// <summary>Validates blueprint text. <paramref name="path"/> names the source in messages.</summary>
    public BlueprintParseResult Parse(string text, string path)
    {
        if (string.IsNullOrWhiteSpace(text))
            return Fail(path, $"Blueprint file is empty: {path}");

        BlueprintYamlFile? file;
        try
        {
            file = Deserializer.Deserialize<BlueprintYamlFile?>(text);
        }
        catch (YamlException ex)
        {
            logger?.LogWarning("Blueprint {Path} is not valid YAML: {Detail}", path, ex.Message);
            return Fail(path, $"Invalid YAML syntax in blueprint: {path}");
        }

        if (file is null)
            return Fail(path, $"Blueprint file is empty: {path}");

        var errors = new List<string>();
        Blueprint? blueprint = Build(file, path, errors);

        var validation = new BlueprintValidation { Valid = errors.Count == 0, Path = path, Errors = errors };
        return new BlueprintParseResult(errors.Count == 0 ? blueprint : null, validation);
    }

    private static BlueprintParseResult Fail(string path, string error) =>
        new(null, new BlueprintValidation { Valid = false, Path = path, Errors = [error] });

    private Blueprint? Build(BlueprintYamlFile file, string path, List<string> errors)
    {
        string name = file.Name?.Trim() ?? string.Empty;
        if (name.Length == 0)
            errors.Add($"Blueprint missing required field 'name': {path}");
        else if (!IsValidName(name))
            errors.Add($"Blueprint 'name' must be lowercase letters, digits, '.', '_' or '-' and start with a letter or digit: {path}");

        if (file.SchemaVersion is { Length: > 0 } version && version != SchemaVersions.Blueprint.ToString(CultureInfo.InvariantCulture))
            errors.Add($"Blueprint schema_version '{version}' is not supported (expected {SchemaVersions.Blueprint}): {path}");

        BlueprintMetadata metadata = BuildMetadata(file.Metadata, path, errors);
        int? rconPort = Number(file.RconPort, "rcon_port", path, errors);
        int? rconPoll = Number(file.RconPollIntervalSeconds, "rcon_poll_interval_seconds", path, errors);

        NativeBlueprint? native = null;
        ContainerBlueprint? container = null;
        BlueprintRuntime? runtime = null;

        switch (file.Runtime?.Trim())
        {
            case "native":
                runtime = BlueprintRuntime.Native;
                native = BuildNative(file.Native, path, errors);
                break;

            case "container":
                runtime = BlueprintRuntime.Container;
                container = BuildContainer(file.Container, path, errors);
                break;

            default:
                errors.Add($"Blueprint has invalid or missing 'runtime' (expected native|container): {path}");
                break;
        }

        if (errors.Count > 0 || runtime is null) return null;

        return new Blueprint
        {
            Name = name,
            Runtime = runtime.Value,
            Metadata = metadata,
            PlayerJoinedRegex = file.PlayerJoinedRegex ?? string.Empty,
            PlayerLeftRegex = file.PlayerLeftRegex ?? string.Empty,
            RconPort = rconPort,
            RconPassword = file.RconPassword ?? string.Empty,
            RconPollIntervalSeconds = rconPoll,
            RconPlayersCommand = file.RconPlayersCommand ?? string.Empty,
            RconPlayersRegex = file.RconPlayersRegex ?? string.Empty,
            KickCommand = file.KickCommand ?? string.Empty,
            BanCommand = file.BanCommand ?? string.Empty,
            UnbanCommand = file.UnbanCommand ?? string.Empty,
            BroadcastCommand = file.BroadcastCommand ?? string.Empty,
            Native = native,
            Container = container,
        };
    }

    private static BlueprintMetadata BuildMetadata(BlueprintYamlMetadata? yaml, string path, List<string> errors)
    {
        if (yaml is null) return new BlueprintMetadata();

        return new BlueprintMetadata
        {
            DisplayName = yaml.DisplayName,
            Description = yaml.Description,
            RawgSlug = yaml.RawgSlug,
            MaxPlayers = Number(yaml.MaxPlayers, "metadata.max_players", path, errors),
            MinRamMb = Number(yaml.MinRamMb, "metadata.min_ram_mb", path, errors),
            RecommendedRamMb = Number(yaml.RecommendedRamMb, "metadata.recommended_ram_mb", path, errors),
            BaseDiskMb = Number(yaml.BaseDiskMb, "metadata.base_disk_mb", path, errors),
        };
    }

    private static NativeBlueprint? BuildNative(BlueprintYamlNative? yaml, string path, List<string> errors)
    {
        string executable = yaml?.ExecutableFile?.Trim() ?? string.Empty;
        if (executable.Length == 0)
        {
            errors.Add($"Native blueprint missing required field 'native.executable_file': {path}");
            return null;
        }

        long? steamAppId = Long(yaml!.SteamAppId, "native.steam_app_id", path, errors);
        long? clientSteamAppId = Long(yaml.ClientSteamAppId, "native.client_steam_app_id", path, errors);
        bool? account = Bool(yaml.IsSteamAccountRequired, "native.is_steam_account_required", path, errors);

        return new NativeBlueprint
        {
            Ports = yaml.Ports ?? string.Empty,
            SteamAppId = steamAppId ?? 0,
            ClientSteamAppId = clientSteamAppId ?? 0,
            SteamcmdArguments = yaml.SteamcmdArguments ?? string.Empty,
            IsSteamAccountRequired = account ?? false,
            Platform = yaml.Platform ?? string.Empty,
            LevelName = yaml.LevelName ?? string.Empty,
            ExecutableSubdirectory = yaml.ExecutableSubdirectory ?? string.Empty,
            ExecutableFile = executable,
            ExecutableArguments = yaml.ExecutableArguments ?? string.Empty,
            StopCommand = yaml.StopCommand ?? string.Empty,
            SaveCommand = yaml.SaveCommand ?? string.Empty,
            StartupSuccessRegex = yaml.StartupSuccessRegex ?? string.Empty,
        };
    }

    private ContainerBlueprint? BuildContainer(BlueprintYamlContainer? yaml, string path, List<string> errors)
    {
        string compose = yaml?.Compose ?? string.Empty;
        if (string.IsNullOrWhiteSpace(compose))
        {
            errors.Add($"Container blueprint missing required field 'container.compose': {path}");
            return null;
        }

        ComposeYamlFile? document;
        try
        {
            document = Deserializer.Deserialize<ComposeYamlFile?>(compose);
        }
        catch (YamlException ex)
        {
            logger?.LogWarning("The compose of blueprint {Path} is not valid YAML: {Detail}", path, ex.Message);
            errors.Add($"Container blueprint 'container.compose' is not valid YAML: {path}");
            return null;
        }

        if (document?.Services is not { Count: > 0 } services)
        {
            errors.Add($"Container blueprint 'container.compose' defines no services: {path}");
            return null;
        }

        // Containers are host-networked: under host networking the compose `ports:` block is not a publish,
        // so the host firewall governs the instance exactly as it does a native one. A bridge service with
        // the same ports would be published through a chain the host firewall does not filter.
        if (services.Values.Any(service => service?.NetworkMode != "host"))
        {
            errors.Add(
                "Container blueprint service missing 'network_mode: host' (KGSM containers are host-networked; "
                + $"a bridge service's published ports bypass the host firewall): {path}");
        }

        return new ContainerBlueprint { Compose = compose };
    }

    /// <summary>A blueprint name is a safe file and directory name: lowercase letters, digits, '.', '_' and '-'.</summary>
    public static bool IsValidName(string name)
    {
        if (name.Length == 0 || name.Length > 64) return false;
        if (!(char.IsAsciiLetterLower(name[0]) || char.IsAsciiDigit(name[0]))) return false;

        return name.All(c => char.IsAsciiLetterLower(c) || char.IsAsciiDigit(c) || c is '.' or '_' or '-');
    }

    private static int? Number(string? text, string field, string path, List<string> errors)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        if (int.TryParse(text.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out int value)) return value;

        errors.Add($"Blueprint field '{field}' must be a whole number or empty, not '{text}': {path}");
        return null;
    }

    private static long? Long(string? text, string field, string path, List<string> errors)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        if (long.TryParse(text.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out long value)) return value;

        errors.Add($"Blueprint field '{field}' must be a whole number or empty, not '{text}': {path}");
        return null;
    }

    private static bool? Bool(string? text, string field, string path, List<string> errors)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;

        switch (text.Trim().ToLowerInvariant())
        {
            case "true": return true;
            case "false": return false;
            default:
                errors.Add($"Blueprint field '{field}' must be true or false, not '{text}': {path}");
                return null;
        }
    }
}
