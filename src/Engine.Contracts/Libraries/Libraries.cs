using System.Text.Json.Serialization;

namespace TheKrystalShip.KGSM.Engine.Contracts.Libraries;

/// <summary>Whether a library's disk is there right now.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<LibraryState>))]
public enum LibraryState
{
    [JsonStringEnumMemberName("online")]
    Online = 0,

    [JsonStringEnumMemberName("offline")]
    Offline = 1,
}

/// <summary>Where an instance's library stands.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<InstanceLibraryState>))]
public enum InstanceLibraryState
{
    [JsonStringEnumMemberName("online")]
    Online = 0,

    [JsonStringEnumMemberName("offline")]
    Offline = 1,

    /// <summary>The instance lies under no registered library.</summary>
    [JsonStringEnumMemberName("unregistered")]
    Unregistered = 2,
}

/// <summary>The library registry file, <c>libraries.json</c> in the data home.</summary>
public sealed record LibraryRegistryFile
{
    public required int SchemaVersion { get; init; }

    public required List<LibraryRecord> Libraries { get; init; }
}

/// <summary>One registered library.</summary>
public sealed record LibraryRecord
{
    public required string Name { get; init; }

    /// <summary>Generated once and never changed; it travels with the disk.</summary>
    public required string Id { get; init; }

    /// <summary>The canonical root.</summary>
    public required string Path { get; init; }
}

/// <summary>The marker <c>.kgsm-library</c> in a library root: proof that the root in front of you is the library the registry means.</summary>
public sealed record LibraryMarker
{
    public required int SchemaVersion { get; init; }

    public required string Id { get; init; }

    public required string Name { get; init; }
}

/// <summary>A library as a listing reports it. Figures a measurement could not make are null.</summary>
public sealed record Library
{
    public required string Name { get; init; }

    public required string Id { get; init; }

    public required string Path { get; init; }

    public required LibraryState State { get; init; }

    public long? FreeBytes { get; init; }

    public long? TotalBytes { get; init; }

    public required int InstanceCount { get; init; }
}
