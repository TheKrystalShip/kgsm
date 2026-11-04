using Microsoft.Extensions.Logging.Abstractions;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Instances;

namespace TheKrystalShip.KGSM.Engine.Tests;

/// <summary>A container blueprint's compose file renders without a shell: only the instance's own references are substituted.</summary>
public class ComposeRendererTests
{
    private static readonly InstanceLayout Layout = new("/lib/instances/gc/gc-1", "gc-1");

    private static string Render(string compose, Func<Contracts.Instances.InstanceConfig, Contracts.Instances.InstanceConfig>? shape = null)
    {
        var config = Sandbox.NewConfig("gc", "gc-1", "/backups/gc-1") with { Runtime = BlueprintRuntime.Container };
        return ComposeRenderer.Render(compose, shape is null ? config : shape(config), Layout);
    }

    [Fact]
    public void BracedAndBareReferences_AreSubstituted()
    {
        Assert.Equal("name: gc-1 level: world one", Render("name: ${instance_name} level: $instance_level_name"));
    }

    [Theory]
    [InlineData("${instance_working_dir}", "/lib/instances/gc/gc-1")]
    [InlineData("${instance_install_dir}", "/lib/instances/gc/gc-1/install")]
    [InlineData("${instance_saves_dir}", "/lib/instances/gc/gc-1/saves")]
    [InlineData("${instance_logs_dir}", "/lib/instances/gc/gc-1/logs")]
    [InlineData("${instance_temp_dir}", "/lib/instances/gc/gc-1/temp")]
    [InlineData("${instance_events_dir}", "/lib/instances/gc/gc-1/events")]
    [InlineData("${instance_backups_dir}", "/backups/gc-1")]
    [InlineData("${instance_auto_update}", "false")]
    [InlineData("${instance_player_joined_regex_b64}", "")]
    public void EveryPathAndFlagAContainerBlueprintNames_ComesFromTheInstance(string reference, string expected)
    {
        Assert.Equal(expected, Render(reference));
    }

    [Fact]
    public void TheAutoUpdateFlag_IsTheInstancesAsTrueOrFalse()
    {
        Assert.Equal("true", Render("${instance_auto_update}", c => c with { AutoUpdateBeforeStart = true }));
    }

    [Fact]
    public void ThePresencePatterns_AreBase64OfTheConfigsRegexes()
    {
        string rendered = Render(
            "${instance_player_joined_regex_b64}|${instance_player_left_regex_b64}",
            c => c with { PlayerJoinedRegex = @"(?<name>\w+) joined", PlayerLeftRegex = "left" });

        Assert.Equal(
            Convert.ToBase64String("(?<name>\\w+) joined"u8) + "|" + Convert.ToBase64String("left"u8),
            rendered);
    }

    [Fact]
    public void EveryOtherDollar_IsLeftForCompose()
    {
        const string Compose = "a: $HOME b: ${PORT:-7777} c: $$instance_name d: ${instance_name:-x} e: $(date) f: $5 g: ${}";

        Assert.Equal(Compose, Render(Compose));
    }

    [Fact]
    public void ADoubledDollar_IsComposesEscape_NotAReference()
    {
        Assert.Equal("literal $$instance_name and gc-1", Render("literal $$instance_name and $instance_name"));
    }

    [Fact]
    public void AReferenceToAnUnknownKey_FailsTheRender()
    {
        var failure = Assert.Throws<ComposeException>(() => Render("x: ${instance_nothing_here}"));

        Assert.Contains("$instance_nothing_here", failure.Message, StringComparison.Ordinal);
        Assert.Equal("compose", failure.Code);
    }

    [Fact]
    public void AValueIsNeverExpandedOrSubstitutedAgain()
    {
        string rendered = Render("n: ${instance_name} l: ${instance_level_name}", c => c with { LevelName = "$(id) ${instance_name} `x` $$" });

        Assert.Equal("n: gc-1 l: $(id) ${instance_name} `x` $$", rendered);
    }

    [Fact]
    public void ADocumentWithNoReferences_IsReturnedByteForByte()
    {
        const string Compose = "services:\n  s:\n    image: ghcr.io/x/y:latest\n    command: [\"sh\", \"-c\", \"echo $$HOME\"]\n";

        Assert.Equal(Compose, Render(Compose));
    }

    [Fact]
    public void EveryBundledContainerBlueprint_RendersWithoutAnUnknownKey()
    {
        var parser = new BlueprintParser(NullLogger<BlueprintParser>.Instance);
        string[] files = [.. Directory.GetFiles(Path.Combine(AppContext.BaseDirectory, "blueprints"), "*.bp.yaml")];
        int containers = 0;

        foreach (string file in files)
        {
            Blueprint? blueprint = parser.ParseFile(file).Blueprint;
            if (blueprint?.Container is not { } container) continue;

            containers++;
            string rendered = Render(container.Compose);
            Assert.DoesNotContain("instance_", rendered.Replace("container_name", string.Empty, StringComparison.Ordinal), StringComparison.Ordinal);
        }

        Assert.True(containers > 0, "the test found no container blueprint");
    }
}
