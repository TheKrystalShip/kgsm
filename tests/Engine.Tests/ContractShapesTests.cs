using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;

namespace TheKrystalShip.KGSM.Engine.Tests;

/// <summary>The JSON the engine emits and stores is camelCase, with unknown spelled null and enums spelled in lowercase words.</summary>
public class ContractShapesTests
{
    [Fact]
    public void AnOfflineLibrary_ReportsUnmeasuredFiguresAsNull()
    {
        var library = new Library { Name = "usb", Id = "abc", Path = "/mnt/usb", State = LibraryState.Offline, InstanceCount = 2 };

        string json = JsonSerializer.Serialize(library, EngineJsonContext.Default.Library);

        Assert.Equal("""{"name":"usb","id":"abc","path":"/mnt/usb","state":"offline","freeBytes":null,"totalBytes":null,"instanceCount":2}""", json);
    }

    [Fact]
    public void ABlueprint_SerializesItsRuntimeAndUnknownFiguresInTheDocumentedWords()
    {
        var blueprint = new Blueprint
        {
            Name = "g",
            Runtime = BlueprintRuntime.Container,
            Metadata = new BlueprintMetadata(),
            Container = new ContainerBlueprint { Compose = "services: {}" },
        };

        string json = JsonSerializer.Serialize(blueprint, EngineJsonContext.Default.Blueprint);

        Assert.Contains("\"runtime\":\"container\"", json, StringComparison.Ordinal);
        Assert.Contains("\"maxPlayers\":null", json, StringComparison.Ordinal);
        Assert.Contains("\"native\":null", json, StringComparison.Ordinal);
    }

    [Fact]
    public void AValidationReport_KeepsItsFieldNames()
    {
        var report = new BlueprintValidation { Valid = false, Path = "/p", Errors = ["one", "two"] };

        Assert.Equal("""{"valid":false,"path":"/p","errors":["one","two"]}""", JsonSerializer.Serialize(report, EngineJsonContext.Default.BlueprintValidation));
    }

    [Fact]
    public void ARequirementsReport_ListsEachRequirementWithWhetherItIsPresent()
    {
        var report = new BlueprintRequirements
        {
            Blueprint = "g",
            Requirements = [new RequirementState("steamcmd", true), new RequirementState("steam-credentials", false)],
        };

        Assert.Equal(
            """{"blueprint":"g","requirements":[{"id":"steamcmd","present":true},{"id":"steam-credentials","present":false}]}""",
            JsonSerializer.Serialize(report, EngineJsonContext.Default.BlueprintRequirements));
    }

    [Fact]
    public void ABackupManifest_SpellsItsEnumsInWords()
    {
        var manifest = new BackupManifest
        {
            SchemaVersion = 1,
            Id = "b",
            CreatedAt = new DateTimeOffset(2026, 1, 2, 3, 4, 5, TimeSpan.Zero),
            Reason = BackupReason.PreRestore,
            Retention = BackupRetention.Pinned,
            Consistency = BackupConsistency.Hot,
            Compressed = false,
            Sources = ["saves"],
            SizeBytes = 1,
            FileCount = 1,
        };

        string json = JsonSerializer.Serialize(manifest, EngineJsonContext.Default.BackupManifest);

        Assert.Contains("\"reason\":\"pre-restore\"", json, StringComparison.Ordinal);
        Assert.Contains("\"retention\":\"pinned\"", json, StringComparison.Ordinal);
        Assert.Contains("\"consistency\":\"hot\"", json, StringComparison.Ordinal);
        Assert.Contains("\"sha256\":null", json, StringComparison.Ordinal);
    }
}
