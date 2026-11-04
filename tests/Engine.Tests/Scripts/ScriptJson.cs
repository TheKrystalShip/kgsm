using System.Text.Json;
using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>The shape of <c>status --json</c>, as a script prints it.</summary>
internal sealed record ScriptStatus(
    string InstanceName,
    bool Status,
    ScriptProcess Process,
    ScriptVersion Version,
    ScriptConfiguration Configuration,
    ScriptResources Resources,
    string[] Backups,
    string[] RecentLogs);

internal sealed record ScriptProcess(int? Pid, string? Status, string? StartTime);

internal sealed record ScriptVersion(string? Current, string? Latest, bool Checked, bool? UpdatesAvailable, string? CheckedAt);

internal sealed record ScriptConfiguration(string Blueprint, string Runtime, string Directory, string? Ports);

internal sealed record ScriptResources(long? DiskUsageBytes);

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(ScriptStatus))]
[JsonSerializable(typeof(BackupManifest[]))]
internal sealed partial class ScriptTestJson : JsonSerializerContext;

internal static class ScriptJson
{
    public static ScriptStatus Status(string json) =>
        JsonSerializer.Deserialize(json, ScriptTestJson.Default.ScriptStatus) ?? throw new InvalidOperationException("status printed null");

    public static BackupManifest[] Manifests(string json) =>
        JsonSerializer.Deserialize(json, ScriptTestJson.Default.BackupManifestArray) ?? throw new InvalidOperationException("backups printed null");

    /// <summary>A backup's manifest, read as the engine reads it.</summary>
    public static BackupManifest Manifest(ScriptWorld world, string id) =>
        ContractFile.Read(
            Path.Combine(world.BackupsDirectory, id, "manifest.json"), EngineJsonContext.Default.BackupManifest,
            SchemaVersions.BackupManifest, m => m.SchemaVersion);
}
