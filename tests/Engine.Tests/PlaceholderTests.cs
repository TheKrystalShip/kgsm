using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Placeholders;

namespace TheKrystalShip.KGSM.Engine.Tests;

/// <summary>
/// The launch-argument cases. The generated management script resolves the same grammar;
/// <c>ScriptPlaceholderTests</c> runs <see cref="Cases"/> against the script so the two resolvers cannot drift.
/// The values are real placeholder keys, so a script reads them from an instance config; <see cref="WorkingDirectory"/>
/// stands for the working directory each resolver runs in.
/// </summary>
public class PlaceholderTests
{
    /// <summary>What the cases use for the working directory the instance's saves lie under.</summary>
    public const string WorkingDirectory = "%WD%";

    public sealed record Case(string Name, string Template, IReadOnlyDictionary<string, string> Values, string[]? Expected, string? ErrorContains = null);

    /// <summary>The instance id the cases are written for; the script's directory is named after it.</summary>
    public const string InstanceId = "g-1";

    /// <summary>The value of <c>displayName</c> in the cases: everything a shell would act on.</summary>
    public const string Tricky = "$(rm -rf /) `id` ; | & > ' \" \\ *";

    private static readonly Dictionary<string, string> Values = new()
    {
        ["name"] = InstanceId,
        ["levelName"] = "my world",
        ["savesDir"] = WorkingDirectory + "/saves",
        ["displayName"] = Tricky,
        ["platform"] = "",
    };

    /// <summary>A text with the working directory filled in.</summary>
    public static string In(string workingDirectory, string text) => text.Replace(WorkingDirectory, workingDirectory, StringComparison.Ordinal);

    public static IReadOnlyList<Case> Cases { get; } =
    [
        new("plain text is literal", "--dedicated -port 7777", Values, ["--dedicated", "-port", "7777"]),
        new("one placeholder", "--name {name}", Values, ["--name", "g-1"]),
        new("a value with spaces stays one argument", "-world {levelName}", Values, ["-world", "my world"]),
        new("a placeholder inside an argument", "--save {savesDir}/{levelName}.wld", Values, ["--save", WorkingDirectory + "/saves/my world.wld"]),
        new("two placeholders in one argument", "{name}-{name}", Values, ["g-1-g-1"]),
        new("whitespace of any kind separates arguments", "a  b\tc\nd\re\vf\fg", Values, ["a", "b", "c", "d", "e", "f", "g"]),
        new("no arguments", "   ", Values, []),
        new("doubled braces are literal", "{{name}} }}", Values, ["{name}", "}"]),
        new("literal braces around a placeholder", "{{{name}}}", Values, ["{g-1}"]),
        new("a value is never shell syntax", "x={displayName}", Values, ["x=" + Tricky]),
        new("a dollar sign is literal and ${name} is a dollar then the value", "$HOME $(date) ${name}", Values, ["$HOME", "$(date)", "$g-1"]),
        new("a bare dollar and quotes are literal", "$HOME \"quoted\" 'single'", Values, ["$HOME", "\"quoted\"", "'single'"]),
        new("an empty value leaves an empty argument", "a{platform}b {platform}", Values, ["ab", ""]),
        new("a key with no value fails", "--x {nothing}", Values, null, "{nothing}"),
        new("a brace that opens nothing fails", "{name", Values, null, "never closes"),
        new("a brace that closes nothing fails", "name}", Values, null, "closes nothing"),
        new("braces around a non-key fail", "{a-b}", Values, null, "not a placeholder"),
        new("whitespace splits before substitution, so a split placeholder fails", "{a b}", Values, null, "never closes"),
        new("an empty placeholder fails", "{}", Values, null, "not a placeholder"),
        new("a key must start lowercase", "{Name}", Values, null, "not a placeholder"),
        new("a closing brace after a placeholder closes nothing", "{name}}", Values, null, "closes nothing"),
        new("an escaped brace then a placeholder", "{{{{name}}", Values, ["{{name}"]),
        new("an opening brace inside a key's braces is not a key", "{a{b}", Values, null, "not a placeholder"),
        new("a value that holds braces is not resolved again", "{displayName}{{x}}", Values, [Tricky + "{x}"]),
    ];

    public static TheoryData<int> CaseIndexes()
    {
        var data = new TheoryData<int>();
        for (int i = 0; i < Cases.Count; i++) data.Add(i);
        return data;
    }

    [Theory]
    [MemberData(nameof(CaseIndexes))]
    public void EachCase_ResolvesOrFailsAsDeclared(int index)
    {
        Case c = Cases[index];

        IReadOnlyDictionary<string, string> values = c.Values.ToDictionary(v => v.Key, v => In("/lib/g/g-1", v.Value));
        bool ok = LaunchArguments.TryResolve(c.Template, values, out IReadOnlyList<string> arguments, out string? error);

        if (c.Expected is { } expected)
        {
            Assert.True(ok, $"{c.Name}: {error}");
            Assert.Equal(expected.Select(e => In("/lib/g/g-1", e)), arguments);
        }
        else
        {
            Assert.False(ok, c.Name);
            Assert.Contains(c.ErrorContains!, error, StringComparison.Ordinal);
            Assert.Empty(arguments);
        }
    }

    [Fact]
    public void ResolveThrowsAPlaceholderException_WithTheStableCode()
    {
        var failure = Assert.Throws<PlaceholderException>(() => LaunchArguments.Resolve("{missing}", Values));

        Assert.Equal("placeholder", failure.Code);
    }

    [Fact]
    public void KeysAreListedInOrderOfFirstUse_WithoutResolving()
    {
        Assert.Equal(["savesDir", "levelName", "name"], LaunchArguments.Keys("{savesDir}/{levelName} {name} {levelName} {{x}}"));
        Assert.Empty(LaunchArguments.Keys("plain"));
    }

    // --- the blueprint's $instance_<key> spelling becomes the stored {key} spelling ---

    private static readonly IReadOnlySet<string> Known = InstancePlaceholders.Keys;

    [Theory]
    [InlineData("--start-server $instance_saves_dir/$instance_level_name", "--start-server {savesDir}/{levelName}")]
    [InlineData("-world ${instance_saves_dir}/${instance_level_name} -x", "-world {savesDir}/{levelName} -x")]
    [InlineData("$instance_install_dir/bin", "{installDir}/bin")]
    [InlineData("-Xmx4096M -jar release.jar nogui", "-Xmx4096M -jar release.jar nogui")]
    [InlineData("-cfg {\"a\":1}", "-cfg {{\"a\":1}}")]
    [InlineData("price $5 and $HOME", "price $5 and $HOME")]
    [InlineData("-name $instance_name.log", "-name {name}.log")]
    public void ABlueprintsArguments_BecomeTheStoredTemplate(string blueprint, string stored)
    {
        Assert.Equal(stored, LaunchArguments.FromBlueprint(blueprint, Known));
    }

    [Fact]
    public void ABlueprintReferenceToAnUnknownKey_FailsTheConversion()
    {
        var failure = Assert.Throws<PlaceholderException>(() => LaunchArguments.FromBlueprint("-x $instance_nothing_here", Known));

        Assert.Contains("$instance_nothing_here", failure.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void AConvertedTemplate_ResolvesBackToWhatTheBlueprintMeant()
    {
        string stored = LaunchArguments.FromBlueprint("-world $instance_saves_dir/$instance_level_name -autocreate 3 -worldname $instance_level_name", Known);

        IReadOnlyList<string> arguments = LaunchArguments.Resolve(stored, Values.ToDictionary(v => v.Key, v => In("/lib/instances/g/g-1", v.Value)));

        Assert.Equal(["-world", "/lib/instances/g/g-1/saves/my world", "-autocreate", "3", "-worldname", "my world"], arguments);
    }

    [Theory]
    [InlineData("level_name", "levelName")]
    [InlineData("saves_dir", "savesDir")]
    [InlineData("name", "name")]
    [InlineData("rcon_players_regex", "rconPlayersRegex")]
    public void SnakeCase_BecomesCamelCase(string snake, string camel)
    {
        Assert.Equal(camel, LaunchArguments.SnakeToCamel(snake));
        Assert.True(LaunchArguments.IsValidKey(camel));
    }

    // --- an instance's own values ---

    [Fact]
    public void AnInstancesValues_CoverEveryKeyABlueprintMayName()
    {
        var config = Sandbox.NewConfig("g", "g-1", "/backups/g-1");
        var layout = new InstanceLayout("/lib/instances/g/g-1", "g-1");

        IReadOnlyDictionary<string, string> values = InstancePlaceholders.Values(config, layout);

        Assert.Equal(InstancePlaceholders.Keys.Order(StringComparer.Ordinal), values.Keys.Order(StringComparer.Ordinal));
        Assert.All(InstancePlaceholders.Keys, key => Assert.True(LaunchArguments.IsValidKey(key), key));
        Assert.Equal("/lib/instances/g/g-1/saves", values["savesDir"]);
        Assert.Equal("/backups/g-1", values["backupsDir"]);
        Assert.Equal("native", values["runtime"]);
    }

    [Fact]
    public void AnInstancesLaunchArguments_ResolveFromItsConfigAndLayout()
    {
        var config = Sandbox.NewConfig("g", "g-1", "/b");
        var layout = new InstanceLayout("/lib/instances/g/g-1", "g-1");

        IReadOnlyList<string> arguments = InstancePlaceholders.ResolveLaunchArguments(config, layout);

        Assert.Equal(["--save", "/lib/instances/g/g-1/saves/world one", "--name", "g-1"], arguments);
    }

    [Fact]
    public void AValueWithShellSyntax_ReachesTheGameAsOneLiteralArgument()
    {
        var config = Sandbox.NewConfig("g", "g-1", "/b") with { LevelName = "x; touch /tmp/pwned $(id)", ExecutableArguments = "-level {levelName}" };

        IReadOnlyList<string> arguments = InstancePlaceholders.ResolveLaunchArguments(config, new InstanceLayout("/w", "g-1"));

        Assert.Equal(["-level", "x; touch /tmp/pwned $(id)"], arguments);
    }
}
