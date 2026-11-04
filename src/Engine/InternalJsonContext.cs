using System.Text.Json.Serialization;

namespace TheKrystalShip.KGSM.Engine;

/// <summary>Serializer metadata for the engine's own internal shapes.</summary>
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(ContractFile.SchemaProbe))]
internal sealed partial class InternalJsonContext : JsonSerializerContext;
