using System.Text.Json.Serialization;

namespace TheKrystalShip.KGSM.Engine.Contracts.Reports;

/// <summary>The engine's own release number, as <c>kgsm engine version</c> reports it.</summary>
public sealed record EngineVersionReport
{
    public required string Version { get; init; }
}

/// <summary>Which source set a setting's value.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SettingSource>))]
public enum SettingSource
{
    /// <summary><c>kgsm.settings.json</c> beside the binary, which declares the whole surface.</summary>
    [JsonStringEnumMemberName("default")]
    Default = 0,

    /// <summary>The person's <c>kgsm/kgsm.settings.json</c> in the config home.</summary>
    [JsonStringEnumMemberName("user")]
    User = 1,

    /// <summary>A <c>Section__Key</c> environment variable.</summary>
    [JsonStringEnumMemberName("environment")]
    Environment = 2,
}

/// <summary>One engine setting: its key (<c>Section:Key</c>), the value it resolves to, and the source that set it.</summary>
public sealed record EngineSetting
{
    public required string Key { get; init; }

    public required string Value { get; init; }

    public required SettingSource Source { get; init; }
}

/// <summary>What setting one engine setting did.</summary>
public sealed record SettingSetReport
{
    public required string Key { get; init; }

    /// <summary>What the person's settings file now holds for the key.</summary>
    public required string Stored { get; init; }

    /// <summary>Whether the file changed.</summary>
    public required bool Changed { get; init; }

    /// <summary>The setting as the engine now resolves it; an environment variable still wins over the file.</summary>
    public required EngineSetting Effective { get; init; }
}
