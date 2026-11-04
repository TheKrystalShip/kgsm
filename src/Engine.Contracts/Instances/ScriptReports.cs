using System.Text.Json.Serialization;

namespace TheKrystalShip.KGSM.Engine.Contracts.Instances;

/// <summary>What repairing one instance's management script came to.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<ScriptRepairOutcome>))]
public enum ScriptRepairOutcome
{
    /// <summary>The script was rewritten.</summary>
    [JsonStringEnumMemberName("regenerated")]
    Regenerated = 0,

    /// <summary>The script was current and left alone.</summary>
    [JsonStringEnumMemberName("current")]
    Current = 1,

    /// <summary>The instance has no readable config, so no script can be built for it.</summary>
    [JsonStringEnumMemberName("skipped")]
    Skipped = 2,

    /// <summary>The script could not be written: its hooks file is not acceptable, the instance is busy or the disk refused.</summary>
    [JsonStringEnumMemberName("failed")]
    Failed = 3,
}

/// <summary>One instance's repair.</summary>
public sealed record ScriptRepairEntry
{
    public required string Id { get; init; }

    public required ScriptRepairOutcome Outcome { get; init; }

    /// <summary>Why the script was stale, or why it was skipped or failed; null for a current script.</summary>
    public string? Detail { get; init; }
}

/// <summary>The result of <c>kgsm instance repair</c>.</summary>
public sealed record ScriptRepairReport
{
    public required IReadOnlyList<ScriptRepairEntry> Instances { get; init; }
}

/// <summary>The values a launch argument may name, as <c>kgsm engine placeholders</c> reports them.</summary>
public sealed record LaunchPlaceholderReport
{
    /// <summary>The keys, in ordinal order; the blueprint's <c>$instance_&lt;snake_case&gt;</c> spells each in snake case.</summary>
    public required IReadOnlyList<string> Keys { get; init; }
}
