using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Accounts;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Engine.Tests.Cli;

/// <summary><c>kgsm instance repair</c> and <c>kgsm engine placeholders</c>, and the promise that no read writes a script.</summary>
public class CliRepairTests
{
    private static ScriptRepairReport Report(string json) =>
        JsonSerializer.Deserialize(json, EngineJsonContext.Default.ScriptRepairReport) ?? throw new InvalidOperationException("null");

    private static (CliSession Session, string Script1) Session()
    {
        var sandbox = Sandbox.Create();
        var session = new CliSession(sandbox);
        var library = sandbox.AddLibrary("main");
        (string wd, _) = sandbox.AddInstance(library, "g", "g-1");
        return (session, new InstanceLayout(wd, "g-1").ManagementScript);
    }

    [Fact]
    public async Task RepairOfOneInstance_WritesItsScript_AndSaysSo()
    {
        var (session, script) = Session();

        CliRun run = await session.RunAsync("instance", "repair", "g-1");

        Assert.Equal(0, run.Exit);
        Assert.Contains("regenerated", run.Out, StringComparison.Ordinal);
        Assert.True(File.Exists(script));
        Assert.Contains(session.Sandbox.Root + "/run/control.sock", File.ReadAllText(script), StringComparison.Ordinal);
    }

    [Fact]
    public async Task RepairOfOneInstance_RewritesAScriptThatIsCurrent()
    {
        var (session, script) = Session();
        await session.RunAsync("instance", "repair", "g-1");
        File.AppendAllText(script, "\n# a hand edit\n");

        CliRun run = await session.RunAsync("instance", "repair", "g-1", "--json");

        Assert.Equal(ScriptRepairOutcome.Regenerated, Assert.Single(Report(run.Out).Instances).Outcome);
        Assert.DoesNotContain("a hand edit", File.ReadAllText(script), StringComparison.Ordinal);
    }

    [Fact]
    public async Task RepairAll_TouchesOnlyTheStaleScripts()
    {
        var sandbox = Sandbox.Create();
        var session = new CliSession(sandbox);
        var library = sandbox.AddLibrary("main");
        (string current, _) = sandbox.AddInstance(library, "g", "g-1");
        (string missing, _) = sandbox.AddInstance(library, "g", "g-2");
        (string stale, _) = sandbox.AddInstance(library, "g", "g-3");
        await session.RunAsync("instance", "repair", "g-1");
        await session.RunAsync("instance", "repair", "g-3");
        string currentScript = new InstanceLayout(current, "g-1").ManagementScript;
        string staleScript = new InstanceLayout(stale, "g-3").ManagementScript;
        File.WriteAllText(staleScript, File.ReadAllText(staleScript).Replace($"template={ScriptTemplate.Version}", "template=0", StringComparison.Ordinal));
        File.SetLastWriteTimeUtc(currentScript, new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));

        CliRun run = await session.RunAsync("instance", "repair", "--all", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal(
            new[] { ("g-1", ScriptRepairOutcome.Current), ("g-2", ScriptRepairOutcome.Regenerated), ("g-3", ScriptRepairOutcome.Regenerated) },
            Report(run.Out).Instances.Select(i => (i.Id, i.Outcome)));
        Assert.Equal(new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc), File.GetLastWriteTimeUtc(currentScript));
        Assert.True(File.Exists(new InstanceLayout(missing, "g-2").ManagementScript));
    }

    [Fact]
    public async Task RepairAll_ReportsAFailure_AndStillRepairsTheRest()
    {
        var sandbox = Sandbox.Create();
        var session = new CliSession(sandbox);
        var library = sandbox.AddLibrary("main");
        sandbox.AddInstance(library, "g", "g-1");
        sandbox.AddInstance(library, "rogue", "r-1");
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemOverridesDirectory, "rogue", "hooks.sh"), "evil() { :; }\n");

        CliRun run = await session.RunAsync("instance", "repair", "--all", "--json");

        Assert.Equal(1, run.Exit);
        ScriptRepairReport report = Report(run.Out);
        Assert.Equal(ScriptRepairOutcome.Regenerated, report.Instances.Single(i => i.Id == "g-1").Outcome);
        ScriptRepairEntry failed = report.Instances.Single(i => i.Id == "r-1");
        Assert.Equal(ScriptRepairOutcome.Failed, failed.Outcome);
        Assert.Contains("'evil'", failed.Detail, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Repair_NeedsOneInstanceOrAll_NotNeitherNorBoth()
    {
        var (session, _) = Session();

        CliRun neither = await session.RunAsync("instance", "repair");
        CliRun both = await session.RunAsync("instance", "repair", "g-1", "--all");

        Assert.Equal(2, neither.Exit);
        Assert.Equal(2, both.Exit);
        Assert.Equal(string.Empty, neither.Out);
    }

    [Fact]
    public async Task RepairOfAnUnknownInstance_IsNotFound()
    {
        var (session, _) = Session();

        CliRun run = await session.RunAsync("instance", "repair", "nope");

        Assert.Equal(25, run.Exit);
    }

    [Fact]
    public async Task Repair_TakesTheRegistryAccountGate()
    {
        var (session, script) = Session();
        session.AccountGate = (_, _) => new AccountVerdict(false, "owner", "run it as the owner");

        CliRun run = await session.RunAsync("instance", "repair", "g-1");

        Assert.NotEqual(0, run.Exit);
        Assert.False(File.Exists(script));
    }

    [Fact]
    public async Task NoReadCommand_WritesAnything_ANewScriptIncluded()
    {
        var (session, script) = Session();
        string working = Path.GetDirectoryName(script)!;
        string[] before = Snapshot(session.Sandbox.Root);

        await session.RunAsync("instance", "list");
        await session.RunAsync("instance", "show", "g-1");
        await session.RunAsync("instance", "status", "g-1", "--disk");
        await session.RunAsync("instance", "logs", "g-1");
        await session.RunAsync("instance", "config", "list", "g-1");
        await session.RunAsync("instance", "config", "get", "g-1", "levelName");

        Assert.False(File.Exists(script));
        Assert.Empty(Directory.GetFiles(working, "*.manage.sh*"));
        string[] after = Snapshot(session.Sandbox.Root);
        Assert.Empty(after.Except(before).Where(f => !f.StartsWith(session.Sandbox.Paths.StateHome, StringComparison.Ordinal)));
    }

    // --- the launch placeholders ---

    [Fact]
    public async Task Placeholders_ListTheKeysALaunchArgumentMayName_OnePerLine()
    {
        var (session, _) = Session();

        CliRun run = await session.RunAsync("engine", "placeholders");

        Assert.Equal(0, run.Exit);
        Assert.Equal(InstancePlaceholders.Keys.Order(StringComparer.Ordinal), run.Out.Split('\n', StringSplitOptions.RemoveEmptyEntries));
    }

    [Fact]
    public async Task Placeholders_AreJson_ForAScriptToRead_AndNeedTheGateNoMoreThanVersionDoes()
    {
        var (session, _) = Session();
        session.AccountGate = (_, _) => new AccountVerdict(false, "owner", "not yours");

        CliRun run = await session.RunAsync("engine", "placeholders", "--json");

        Assert.Equal(0, run.Exit);
        LaunchPlaceholderReport report = JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.LaunchPlaceholderReport)!;
        Assert.Equal(InstancePlaceholders.Keys.Order(StringComparer.Ordinal), report.Keys);
        Assert.StartsWith("{\"keys\":[", run.Out, StringComparison.Ordinal);
    }

    private static string[] Snapshot(string root) =>
        [.. Directory.EnumerateFileSystemEntries(root, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal)];
}
