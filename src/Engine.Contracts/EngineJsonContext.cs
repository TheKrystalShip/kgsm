using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Paths;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;

namespace TheKrystalShip.KGSM.Engine.Contracts;

/// <summary>
/// The source-generated serializer for every file the engine writes and every shape it emits. JSON is
/// camelCase; a null is written as <c>null</c>, because null means unknown and an absent key would mean
/// nothing was asked. The event journal's payloads have a context of their own
/// (<see cref="Events.EngineEventJsonContext"/>).
/// </summary>
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    WriteIndented = false,
    UseStringEnumConverter = false)]
[JsonSerializable(typeof(InstanceConfig))]
[JsonSerializable(typeof(InstanceRegistryFile))]
[JsonSerializable(typeof(LibraryRegistryFile))]
[JsonSerializable(typeof(LibraryMarker))]
[JsonSerializable(typeof(Library))]
[JsonSerializable(typeof(IReadOnlyList<Library>))]
[JsonSerializable(typeof(BackupManifest))]
[JsonSerializable(typeof(Backup))]
[JsonSerializable(typeof(BackupListing))]
[JsonSerializable(typeof(Blueprint))]
[JsonSerializable(typeof(BlueprintValidation))]
[JsonSerializable(typeof(BlueprintRequirements))]
[JsonSerializable(typeof(BlueprintResolution))]
[JsonSerializable(typeof(BlueprintListing))]
[JsonSerializable(typeof(IReadOnlyList<BlueprintListing>))]
[JsonSerializable(typeof(PathsReport))]
[JsonSerializable(typeof(ErrorReport))]
[JsonSerializable(typeof(EngineVersionReport))]
[JsonSerializable(typeof(EngineSetting))]
[JsonSerializable(typeof(IReadOnlyList<EngineSetting>))]
[JsonSerializable(typeof(InstanceSummary))]
[JsonSerializable(typeof(IReadOnlyList<InstanceSummary>))]
[JsonSerializable(typeof(InstanceInfo))]
[JsonSerializable(typeof(InstanceStatus))]
[JsonSerializable(typeof(LogTail))]
[JsonSerializable(typeof(ConfigEntry))]
[JsonSerializable(typeof(IReadOnlyList<ConfigEntry>))]
[JsonSerializable(typeof(ScriptRepairReport))]
[JsonSerializable(typeof(LaunchPlaceholderReport))]
[JsonSerializable(typeof(PortUse))]
[JsonSerializable(typeof(IReadOnlyList<PortUse>))]
[JsonSerializable(typeof(PortConflict))]
[JsonSerializable(typeof(IReadOnlyList<PortConflict>))]
public sealed partial class EngineJsonContext : JsonSerializerContext;
