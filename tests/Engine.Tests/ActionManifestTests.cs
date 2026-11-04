using System.Text.Json;
using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Engine.Contracts;

namespace TheKrystalShip.KGSM.Engine.Tests;

internal sealed record ManifestFile(int SchemaVersion, string Component, string? Version, List<ManifestAction> Actions);

internal sealed record ManifestAction(string Id, string Title, string Effect, string Scope, bool? Self);

[JsonSerializable(typeof(ManifestFile))]
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = true)]
internal sealed partial class ManifestJson : JsonSerializerContext;

/// <summary>
/// The engine's action manifest is generated from the commands that declare their actions. Until the bash
/// engine is gone, the hand-written manifest is the other record of the same ids, and the two must agree.
/// </summary>
public class ActionManifestTests
{
    private static ManifestFile Read(string name) =>
        JsonSerializer.Deserialize(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "actions", name)), ManifestJson.Default.ManifestFile)
            ?? throw new InvalidOperationException(name);

    [Fact]
    public void TheGeneratedManifest_IsTheHandWrittenOne_InIdsEffectsAndScopes()
    {
        ManifestFile generated = Read("generated.actions.json");
        ManifestFile handwritten = Read("handwritten.actions.json");

        Assert.Equal("kgsm", generated.Component);
        Assert.Equal(handwritten.Component, generated.Component);
        Assert.Equal(
            handwritten.Actions.Select(a => (a.Id, a.Effect, a.Scope)).OrderBy(a => a.Id, StringComparer.Ordinal),
            generated.Actions.Select(a => (a.Id, a.Effect, a.Scope)).OrderBy(a => a.Id, StringComparer.Ordinal));
    }

    [Fact]
    public void TheGeneratedManifest_KeepsTheTitles_AndIsSortedById()
    {
        ManifestFile generated = Read("generated.actions.json");
        ManifestFile handwritten = Read("handwritten.actions.json");

        Assert.Equal(
            handwritten.Actions.OrderBy(a => a.Id, StringComparer.Ordinal).Select(a => a.Title),
            generated.Actions.Select(a => a.Title));
        Assert.Equal(generated.Actions.Select(a => a.Id).Order(StringComparer.Ordinal), generated.Actions.Select(a => a.Id));
        Assert.All(generated.Actions, a => Assert.Null(a.Self));
    }

    [Fact]
    public void TheGeneratedManifest_CarriesNoStandardSurface_BecauseTheEngineHasNoUnitToConfigureOrRestart()
    {
        ManifestFile generated = Read("generated.actions.json");

        Assert.DoesNotContain(generated.Actions, a => a.Id is "config.read" or "config.write" or "journal.read" or "lifecycle.restart");
    }

    [Fact]
    public void TheConstantsTheBuildWrites_AreTheManifestsActions_ByTheirWireIds()
    {
        string[] constants = typeof(EngineActions)
            .GetFields()
            .Where(f => f.IsLiteral && f.Name != nameof(EngineActions.Component))
            .Select(f => (string)f.GetRawConstantValue()!)
            .Order(StringComparer.Ordinal)
            .ToArray();

        Assert.Equal("kgsm", EngineActions.Component);
        Assert.Equal(Read("generated.actions.json").Actions.Select(a => $"kgsm:{a.Id}").Order(StringComparer.Ordinal), constants);
        Assert.Equal("kgsm:server.start", EngineActions.ServerStart);
        Assert.Equal("kgsm:server.backups.read", EngineActions.ServerBackupsRead);
        Assert.Equal("kgsm:engine.config.write", EngineActions.EngineConfigWrite);
    }
}
