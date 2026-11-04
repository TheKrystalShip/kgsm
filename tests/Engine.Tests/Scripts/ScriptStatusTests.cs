using System.Text.RegularExpressions;
using TheKrystalShip.Testing;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>What <c>status</c> reports for a native instance, and what it refuses to claim.</summary>
public partial class ScriptStatusTests
{
    private static ScriptWorld World(Func<Contracts.Instances.InstanceConfig, Contracts.Instances.InstanceConfig>? shape = null)
    {
        ScriptWorld world = ScriptWorld.Native(c => (shape ?? (x => x))(c with { SteamAppId = 1234, Ports = "7777/udp" }));
        world.Script("steam/buildid", "500\n");
        return world;
    }

    private static async Task<ScriptStatus> StatusAsync(ScriptWorld world, params string[] options)
    {
        ScriptRun run = await world.RunAsync(["status", "--json", .. options]);
        Assert.True(run.Exit == 0, run.Err);
        return ScriptJson.Status(run.Out);
    }

    [Fact]
    public async Task AStoppedInstance_ReportsItsConfigurationAndNoProcess()
    {
        using ScriptWorld world = World();

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.Equal(ScriptWorld.Id, status.InstanceName);
        Assert.False(status.Status);
        Assert.Null(status.Process.Pid);
        Assert.Null(status.Process.Status);
        Assert.Null(status.Process.StartTime);
        Assert.Equal("g", status.Configuration.Blueprint);
        Assert.Equal("native", status.Configuration.Runtime);
        Assert.Equal(world.WorkingDirectory, status.Configuration.Directory);
        Assert.Equal("7777/udp", status.Configuration.Ports);
    }

    [Fact]
    public async Task ARunningInstance_ReportsItsRealPidStateAndStartInUtc()
    {
        using ScriptWorld world = World();
        await world.StartGameAsync();

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.True(status.Status);
        Assert.Equal(world.GamePid(), status.Process.Pid);
        Assert.False(string.IsNullOrEmpty(status.Process.Status));
        Assert.Matches(IsoUtc(), status.Process.StartTime);
    }

    // --- disk, in bytes ---

    [Fact]
    public async Task DiskUsage_IsAnIntegerNumberOfBytes_NotAHumanString()
    {
        // Disk usage is a number of bytes, never a human string such as "1.2M".
        using ScriptWorld world = World();
        File.WriteAllBytes(Path.Combine(world.Install, "big.bin"), new byte[300_000]);

        ScriptRun run = await world.RunAsync("status", "--json", "--fast");
        ScriptStatus status = ScriptJson.Status(run.Out);

        Assert.True(status.Resources.DiskUsageBytes >= 300_000, run.Out);
        Assert.Contains("\"diskUsageBytes\":", run.Out, StringComparison.Ordinal);
        Assert.DoesNotContain("disk_usage", run.Out, StringComparison.Ordinal);
    }

    // --- versions ---

    [Fact]
    public async Task AnUnknownInstalledVersion_IsNull_NotAWord()
    {
        using ScriptWorld world = World();

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.Null(status.Version.Current);
    }

    [Fact]
    public async Task Fast_WithNoRecordedCheck_ClaimsNothing()
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.VersionFile, "500\n");

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.False(status.Version.Checked);
        Assert.Null(status.Version.Latest);
        Assert.Null(status.Version.UpdatesAvailable);
        Assert.Null(status.Version.CheckedAt);
        Assert.Empty(world.Recorded("steam/log"));
    }

    [Theory]
    [InlineData("400", true)]
    [InlineData("500", false)]
    public async Task Fast_AnswersFromTheRecord_AndCarriesWhenItWasFetched(string installed, bool available)
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.VersionFile, installed + "\n");
        File.WriteAllText(world.LatestFile, "500\n2026-03-04T05:06:07Z\n");

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.True(status.Version.Checked);
        Assert.Equal("500", status.Version.Latest);
        Assert.Equal(available, status.Version.UpdatesAvailable);
        Assert.Equal("2026-03-04T05:06:07Z", status.Version.CheckedAt);
        Assert.Empty(world.Recorded("steam/log"));
    }

    [Fact]
    public async Task Fast_WithARecordButNoInstalledVersion_KnowsTheLatestAndNotWhetherItIsNewer()
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.LatestFile, "500\n2026-03-04T05:06:07Z\n");

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.True(status.Version.Checked);
        Assert.Equal("500", status.Version.Latest);
        Assert.Null(status.Version.UpdatesAvailable);
    }

    [Fact]
    public async Task WithoutFast_UpstreamIsAsked_AndTheCheckIsDatedNow()
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.VersionFile, "400\n");

        ScriptStatus status = await StatusAsync(world);

        Assert.True(status.Version.Checked);
        Assert.Equal("500", status.Version.Latest);
        Assert.True(status.Version.UpdatesAvailable);
        Assert.Matches(IsoUtc(), status.Version.CheckedAt);
        Assert.Single(world.Calls("steam/log"));
    }

    [Fact]
    public async Task WithoutFast_WhenUpstreamDoesNotAnswer_ItIsUncheckedNeverUpToDate()
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.VersionFile, "500\n");
        world.Script("steam/exit", "1\n");

        ScriptStatus status = await StatusAsync(world);

        Assert.False(status.Version.Checked);
        Assert.Null(status.Version.UpdatesAvailable);
        Assert.Null(status.Version.Latest);
    }

    // --- backups and logs ---

    [Fact]
    public async Task Status_ListsTheBackupIds()
    {
        using ScriptWorld world = World();
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "w");
        ScriptRun created = await world.RunAsync("create-backup");

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.Equal([created.LastOutLine], status.Backups);
    }

    [Fact]
    public async Task RecentLogs_AreTheLastThreeLinesOfTheLiveLog()
    {
        using ScriptWorld world = World();
        File.WriteAllLines(world.LogFile, ["one", "two", "three", "four"]);

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.Equal(["two", "three", "four"], status.RecentLogs);
    }

    [Fact]
    public async Task RecentLogs_FallBackToTheNewestRotatedLog_WhenTheLiveOneIsEmpty()
    {
        using ScriptWorld world = World();
        Directory.CreateDirectory(world.Logs);
        string older = Path.Combine(world.Logs, "g-1.2026-01-01T00:00:00.log");
        string newer = Path.Combine(world.Logs, "g-1.2026-02-01T00:00:00.log");
        File.WriteAllText(older, "older\n");
        File.WriteAllText(newer, "newer\n");
        File.SetLastWriteTimeUtc(older, new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        File.SetLastWriteTimeUtc(newer, new DateTime(2026, 2, 1, 0, 0, 0, DateTimeKind.Utc));

        ScriptStatus status = await StatusAsync(world, "--fast");

        Assert.Equal(["newer"], status.RecentLogs);
    }

    [Fact]
    public async Task RecentLogs_AreAnEmptyArray_WhenTheInstanceHasNeverLogged()
    {
        using ScriptWorld world = World();

        ScriptRun run = await world.RunAsync("status", "--json", "--fast");

        Assert.Contains("\"recentLogs\":[]", run.Out, StringComparison.Ordinal);
    }

    // --- text ---

    [Fact]
    public async Task TheTextStatus_SaysWhatItDidNotCheck()
    {
        using ScriptWorld world = World();

        ScriptRun fast = await world.RunAsync("status", "--fast");

        Assert.Equal(0, fast.Exit);
        Assert.Contains("Status: Inactive", fast.Out, StringComparison.Ordinal);
        Assert.Contains("Updates: Not checked (fast mode)", fast.Out, StringComparison.Ordinal);
        Assert.Contains("Version: unknown", fast.Out, StringComparison.Ordinal);
        Assert.Contains("No backups available", fast.Out, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Status_RefusesAnArgumentItDoesNotKnow()
    {
        using ScriptWorld world = World();

        Assert.Equal(8, (await world.RunAsync("status", "--verbose")).Exit);
    }

    // --- logs ---

    [Fact]
    public async Task Logs_PrintsTheTailOfTheLiveLog()
    {
        using ScriptWorld world = World();
        File.WriteAllLines(world.LogFile, Enumerable.Range(1, 30).Select(i => $"line {i}"));

        ScriptRun run = await world.RunAsync("logs", "-n", "3");

        Assert.Equal("line 28\nline 29\nline 30\n", run.Out);
    }

    [Fact]
    public async Task Logs_DefaultsToTenLines()
    {
        using ScriptWorld world = World();
        File.WriteAllLines(world.LogFile, Enumerable.Range(1, 30).Select(i => $"line {i}"));

        ScriptRun run = await world.RunAsync("logs");

        Assert.Equal(10, run.Out.Split('\n', StringSplitOptions.RemoveEmptyEntries).Length);
    }

    [Fact]
    public async Task Logs_WithNoLogFile_SaysSoAndSucceeds()
    {
        using ScriptWorld world = World();

        ScriptRun run = await world.RunAsync("logs");

        Assert.Equal(0, run.Exit);
        Assert.Contains("No log file", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Logs_RefusesANonNumericLineCount()
    {
        using ScriptWorld world = World();

        Assert.Equal(8, (await world.RunAsync("logs", "-n", "many")).Exit);
    }

    [Fact]
    public async Task Logs_Follow_PrintsWhatIsWrittenAfterwards()
    {
        using ScriptWorld world = World();
        File.WriteAllLines(world.LogFile, ["first"]);

        var start = new System.Diagnostics.ProcessStartInfo(HostTools.Find("bash")!)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardInput = true,
        };
        start.ArgumentList.Add(world.ScriptPath);
        start.ArgumentList.Add("logs");
        start.ArgumentList.Add("-f");
        start.ArgumentList.Add("-n");
        start.ArgumentList.Add("1");
        start.Environment.Clear();
        foreach ((string key, string value) in world.Environment) start.Environment[key] = value;

        using var follower = System.Diagnostics.Process.Start(start)!;
        try
        {
            Assert.Equal("first", await follower.StandardOutput.ReadLineAsync());
            File.AppendAllText(world.LogFile, "second\n");
            Assert.Equal("second", await follower.StandardOutput.ReadLineAsync());
        }
        finally
        {
            follower.Kill(entireProcessTree: true);
        }
    }

    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")]
    private static partial Regex IsoUtc();
}
