using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Placeholders;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>
/// The script and the engine core are the two resolvers of the launch-argument grammar. Both run the same
/// cases, <see cref="PlaceholderTests.Cases"/>, and the same keys.
/// </summary>
public class ScriptPlaceholderTests
{
    public static TheoryData<int> CaseIndexes() => PlaceholderTests.CaseIndexes();

    [Theory]
    [MemberData(nameof(CaseIndexes))]
    public async Task EachSharedCase_ResolvesInTheScriptAsItDoesInTheCore(int index)
    {
        PlaceholderTests.Case c = PlaceholderTests.Cases[index];
        using ScriptWorld world = ScriptWorld.Native(config => config with
        {
            LevelName = c.Values["levelName"],
            DisplayName = c.Values["displayName"],
            Platform = c.Values["platform"],
            ExecutableArguments = c.Template,
        });

        ScriptRun run = await world.RunAsync("launch-args", "--null");

        if (c.Expected is { } expected)
        {
            Assert.True(run.Exit == 0, $"{c.Name}: {run.Err}");
            string[] arguments = run.Out.Length == 0 ? [] : run.Out.Split('\0')[..^1];
            Assert.Equal(expected.Select(e => PlaceholderTests.In(world.WorkingDirectory, e)), arguments);
        }
        else
        {
            Assert.Equal(1, run.Exit);
            Assert.Contains(c.ErrorContains!, run.Err, StringComparison.Ordinal);
            Assert.Equal(string.Empty, run.Out);
        }
    }

    [Fact]
    public async Task EveryKeyTheCoreKnows_ResolvesInTheScriptToTheSameValue()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { ExecutableSubdirectory = "bin/x64", DisplayName = "My Server" });
        var layout = new InstanceLayout(world.WorkingDirectory, ScriptWorld.Id, "bin/x64");
        IReadOnlyDictionary<string, string> expected = InstancePlaceholders.Values(world.Config, layout);

        foreach (string key in InstancePlaceholders.Keys)
        {
            ScriptRun run = await RunWith(world, "{" + key + "}");

            Assert.True(run.Exit == 0, $"{key}: {run.Err}");
            Assert.Equal(expected[key], run.Out.TrimEnd('\0'));
        }
    }

    [Fact]
    public async Task AKeyOutsideTheCoresSet_HasNoValueInTheScript_EvenWhenTheConfigHoldsIt()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { ExecutableArguments = "--password {rconPassword}", RconPassword = "secret" });

        ScriptRun run = await world.RunAsync("launch-args");

        Assert.Equal(1, run.Exit);
        Assert.Contains("which has no value", run.Err, StringComparison.Ordinal);
        Assert.DoesNotContain("secret", run.Out + run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public void TheScriptCarriesTheCoresKeys_AsTheyAre()
    {
        using ScriptWorld world = ScriptWorld.Native();
        string script = File.ReadAllText(world.ScriptPath);

        Assert.Contains($"readonly KGSM_PLACEHOLDER_KEYS='{string.Join(' ', InstancePlaceholders.Keys.Order(StringComparer.Ordinal))}'", script, StringComparison.Ordinal);
    }

    private static async Task<ScriptRun> RunWith(ScriptWorld world, string template)
    {
        world.Reconfigure(c => c with { ExecutableArguments = template });
        return await world.RunAsync("launch-args", "--null");
    }
}
