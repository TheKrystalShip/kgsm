using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace TheKrystalShip.KGSM.Engine.Contracts.Events;

/// <summary>How much an event matters. One scale, spelled the same on every journal line.</summary>
public enum EventSeverity
{
    Info = 0,
    Warn = 1,
    Danger = 2,
}

/// <summary>How an event went. <c>success</c> is an outcome and never a severity.</summary>
public enum EventOutcome
{
    Neutral = 0,
    Success = 1,
    Failure = 2,
}

/// <summary>
/// Whether an event is a fact worth a row in an audit feed, or a bracket around a run that no feed
/// renders. A catalog states this; a consumer decides what to do with it.
/// </summary>
public enum EventWeight
{
    Fact = 0,
    Phase = 1,
}

/// <summary>What an event is about. Decides which identifying field its payload carries.</summary>
public enum EventSubject
{
    Instance = 0,
    Blueprint = 1,
    Library = 2,
}

/// <summary>What a payload field's data is, never who may see it.</summary>
public enum FieldSensitivity
{
    /// <summary>Safe wherever events are read.</summary>
    Public = 0,

    /// <summary>Identifies a natural person.</summary>
    Personal = 1,

    /// <summary>Content that acts on a server and may carry a credential.</summary>
    Privileged = 2,

    /// <summary>May identify a person depending on something the event does not carry. A reader that
    /// cannot resolve it treats it as <see cref="Personal"/>.</summary>
    Conditional = 3,
}

/// <summary>How a payload field's value is shaped, separate from its sensitivity.</summary>
public enum FieldShape
{
    Text = 0,
    Number = 1,
    Opaque = 2,
    Structured = 3,
}

/// <summary>One classified payload field.</summary>
public sealed record EventField(string Name, FieldSensitivity Sensitivity = FieldSensitivity.Public, FieldShape Shape = FieldShape.Text);

/// <summary>What the producer says about an event as a kind: its weight, how it went, how much it matters.</summary>
public readonly record struct EventTraits(
    EventWeight Weight,
    EventOutcome Outcome = EventOutcome.Neutral,
    EventSeverity Severity = EventSeverity.Info)
{
    public static EventTraits Phase => new(EventWeight.Phase);

    public static EventTraits Fact(EventOutcome outcome = EventOutcome.Neutral, EventSeverity severity = EventSeverity.Info) =>
        new(EventWeight.Fact, outcome, severity);
}

/// <summary>The wire spelling of the scales.</summary>
public static class EventWire
{
    public static string ToWire(this EventSeverity severity) => severity switch
    {
        EventSeverity.Warn => "warn",
        EventSeverity.Danger => "danger",
        _ => "info",
    };

    public static string ToWire(this EventOutcome outcome) => outcome switch
    {
        EventOutcome.Success => "success",
        EventOutcome.Failure => "failure",
        _ => "neutral",
    };
}

/// <summary>
/// A dotted, lowercase event name of at least two segments, each made of lowercase letters, digits and
/// underscores and starting with a letter. A hyphen reads as an underscore.
/// </summary>
public readonly struct EventName : IEquatable<EventName>
{
    private readonly string? _value;

    private EventName(string value) => _value = value;

    public string Value => _value ?? string.Empty;

    public bool IsEmpty => string.IsNullOrEmpty(_value);

    /// <summary>The leading segment, which places the event in the vocabulary.</summary>
    public string Namespace
    {
        get
        {
            if (_value is null) return string.Empty;
            int dot = _value.IndexOf('.', StringComparison.Ordinal);
            return dot < 0 ? _value : _value[..dot];
        }
    }

    public static EventName Parse(string value) =>
        TryParse(value, out EventName name)
            ? name
            : throw new ArgumentException(
                $"'{value}' is not a valid event name: expected at least two dot-separated segments of lowercase "
                + "letters, digits and underscores, each starting with a letter.", nameof(value));

    public static bool TryParse(string? value, out EventName name)
    {
        name = default;
        if (string.IsNullOrWhiteSpace(value)) return false;

        string normalized = value.Replace('-', '_');
        if (!IsWellFormed(normalized)) return false;

        name = new EventName(normalized);
        return true;
    }

    public static bool IsWellFormed(string? value)
    {
        if (string.IsNullOrEmpty(value) || !value.Contains('.', StringComparison.Ordinal)) return false;

        bool startOfSegment = true;
        foreach (char c in value)
        {
            if (c == '.')
            {
                if (startOfSegment) return false;
                startOfSegment = true;
                continue;
            }

            if (startOfSegment)
            {
                if (c is < 'a' or > 'z') return false;
                startOfSegment = false;
                continue;
            }

            if (c is not ((>= 'a' and <= 'z') or (>= '0' and <= '9') or '_')) return false;
        }

        return !startOfSegment;
    }

    public bool Equals(EventName other) => string.Equals(Value, other.Value, StringComparison.Ordinal);

    public override bool Equals(object? obj) => obj is EventName other && Equals(other);

    public override int GetHashCode() => StringComparer.Ordinal.GetHashCode(Value);

    public override string ToString() => Value;

    public static bool operator ==(EventName left, EventName right) => left.Equals(right);

    public static bool operator !=(EventName left, EventName right) => !left.Equals(right);
}

/// <summary>The root of every event payload the engine writes.</summary>
public abstract record EngineEventData;

/// <summary>
/// An engine event type: the payload declares its own name, traits and serialization metadata, so a
/// call site passes a payload and a raw string cannot reach the writer.
/// </summary>
public interface IEngineEvent<TSelf> where TSelf : EngineEventData, IEngineEvent<TSelf>
{
    static abstract EventName Name { get; }

    static abstract EventSubject Subject { get; }

    static abstract EventTraits Traits { get; }

    static abstract JsonTypeInfo<TSelf> TypeInfo { get; }

    /// <summary>The classified payload fields, apart from the subject's identifying one.</summary>
    static virtual IReadOnlyList<EventField> Fields => [];
}

/// <summary>An event about one instance.</summary>
public abstract record InstanceEventData : EngineEventData
{
    [JsonPropertyOrder(-1)]
    public required string InstanceName { get; init; }
}

/// <summary>An event about a blueprint file rather than an instance.</summary>
public abstract record BlueprintEventData : EngineEventData
{
    [JsonPropertyOrder(-1)]
    public required string BlueprintName { get; init; }
}

/// <summary>An event about a placement root.</summary>
public abstract record LibraryEventData : EngineEventData
{
    [JsonPropertyOrder(-1)]
    public required string LibraryName { get; init; }
}

/// <summary>Which directory a blueprint file sits in.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<BlueprintTier>))]
public enum BlueprintTier
{
    [JsonStringEnumMemberName("system")]
    System = 0,

    [JsonStringEnumMemberName("user")]
    User = 1,
}
