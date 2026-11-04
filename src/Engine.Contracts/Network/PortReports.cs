using System.Text.Json.Serialization;

namespace TheKrystalShip.KGSM.Engine.Contracts.Network;

/// <summary>A transport protocol a port range is open on.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<PortProtocol>))]
public enum PortProtocol
{
    [JsonStringEnumMemberName("tcp")]
    Tcp = 0,

    [JsonStringEnumMemberName("udp")]
    Udp = 1,
}

/// <summary>A range of ports on one protocol; a single port has <see cref="Start"/> equal to <see cref="End"/>.</summary>
public sealed record PortRange
{
    public required int Start { get; init; }

    public required int End { get; init; }

    public required PortProtocol Protocol { get; init; }

    public bool Overlaps(PortRange other) =>
        Protocol == other.Protocol && Start <= other.End && other.Start <= End;
}

/// <summary>A port range an instance declares.</summary>
public sealed record PortUse
{
    public required string Instance { get; init; }

    public required int Start { get; init; }

    public required int End { get; init; }

    public required PortProtocol Protocol { get; init; }
}

/// <summary>Instances whose declared ports overlap on one protocol, with the span they all contend for.</summary>
public sealed record PortConflict
{
    public required PortProtocol Protocol { get; init; }

    public required int Start { get; init; }

    public required int End { get; init; }

    public required IReadOnlyList<string> Instances { get; init; }
}
