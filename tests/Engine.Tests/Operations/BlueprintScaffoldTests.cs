using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

public class BlueprintScaffoldTests
{
    private static NativeBlueprintDraft Draft() => new()
    {
        Name = "my-game",
        PlayerJoinedRegex = "(?<name>\\w+) joined",
        Metadata = new NativeBlueprintMetadataDraft { DisplayName = "It's a game", MaxPlayers = 8 },
        Native = new NativeBlueprintNativeDraft
        {
            Ports = "27015:27016/udp|27017/tcp",
            ExecutableFile = "server.x86_64",
            ExecutableArguments = "-port 27015 -name '$instance_name'",
        },
    };

    [Fact]
    public void ARenderedDraftIsAValidBlueprint_AndReadsBackToTheSameDraft()
    {
        NativeBlueprintDraft draft = Draft();
        string yaml = BlueprintScaffold.Render(draft);

        var parsed = new BlueprintParser().Parse(yaml, "my-game.bp.yaml");
        Assert.True(parsed.Valid, string.Join("; ", parsed.Validation.Errors));

        (NativeBlueprintDraft? back, string? problem) = BlueprintScaffold.TryParse(yaml);
        Assert.Null(problem);
        Assert.Equal(draft, back);
    }

    [Fact]
    public void ADraftWithoutAnExecutable_OrWithAnUnsafeName_IsRefusedWithAReason()
    {
        string noExecutable = BlueprintScaffold.Render(Draft() with { Native = Draft().Native with { ExecutableFile = " " } });
        Assert.NotNull(BlueprintScaffold.TryParse(noExecutable).Problem);

        string unsafeName = BlueprintScaffold.Render(Draft() with { Name = "../x" });
        Assert.NotNull(BlueprintScaffold.TryParse(unsafeName).Problem);
        Assert.False(BlueprintScaffold.IsSafeName("../x"));
        Assert.True(BlueprintScaffold.IsSafeName("my-game"));
    }

    [Fact]
    public void TheAuthoringTemplateIsAValidNativeBlueprintOnceItsExampleNameIsKept()
    {
        var parsed = new BlueprintParser().Parse(BlueprintScaffold.Template, "example.bp.yaml");

        Assert.True(parsed.Valid, string.Join("; ", parsed.Validation.Errors));
        Assert.DoesNotContain("kgsm.sh", BlueprintScaffold.Template, StringComparison.Ordinal);
    }
}
