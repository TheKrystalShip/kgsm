using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Status;
using TheKrystalShip.KGSM.Watchdog.Client;

namespace TheKrystalShip.KGSM.Engine.Tests.Cli;

public class StatusTests
{
    private static (CliSession Session, string Directory) NewInstance(Func<InstanceConfig, InstanceConfig>? shape = null)
    {
        var sandbox = Sandbox.Create();
        var session = new CliSession(sandbox);
        var (directory, _) = sandbox.AddInstance(sandbox.AddLibrary("main"), "factorio", "factorio-a", shape);
        return (session, directory);
    }

    private static InstanceStatus Parse(CliRun run) =>
        JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.InstanceStatus)!;

    private static Task<CliRun> Status(CliSession session, params string[] extra) =>
        session.RunAsync(["instance", "status", "factorio-a", "--json", .. extra]);

    // --- native run state: the watchdog's answer, read from the body ---

    [Fact]
    public async Task ATrackedPopulatedInstance_IsRunning_WithItsPidAndStartTime()
    {
        var (session, _) = NewInstance();
        var spawned = new DateTime(2026, 11, 4, 8, 30, 0, DateTimeKind.Utc);
        session.Watchdog.Tracked["factorio-a"] = FakeWatchdog.State("factorio-a", populated: true, pid: 4242, spawnedAt: spawned);

        InstanceProcess process = Parse(await Status(session)).Process;

        Assert.Equal((RunState.Running, RunStateSource.Watchdog, 4242, "running"), (process.State, process.Source, process.Pid, process.Phase));
        Assert.Equal(new DateTimeOffset(spawned), process.StartTime);
    }

    [Fact]
    public async Task ATrackedEmptyInstance_IsStopped_AndAGivenUpOneStillStoppedWithItsPhase()
    {
        var (session, _) = NewInstance();
        session.Watchdog.Tracked["factorio-a"] = FakeWatchdog.State("factorio-a", populated: false, phase: "failed");

        InstanceProcess process = Parse(await Status(session)).Process;

        Assert.Equal((RunState.Stopped, "failed", (int?)null), (process.State, process.Phase, process.Pid));
    }

    [Fact]
    public async Task APhaseTheWatchdogCannotMeasure_IsUnknown_NeverStopped()
    {
        var (session, _) = NewInstance();
        session.Watchdog.Tracked["factorio-a"] = FakeWatchdog.State("factorio-a", populated: false, phase: "unknown");

        Assert.Equal(RunState.Unknown, Parse(await Status(session)).Process.State);
    }

    [Fact]
    public async Task AnInstanceTheWatchdogDoesNotTrack_IsStopped_UnlessItsPidFileNamesALiveProcess()
    {
        var (session, directory) = NewInstance();

        InstanceProcess none = Parse(await Status(session)).Process;
        File.WriteAllText(Path.Combine(directory, ".factorio-a.pid"), "777\n");
        InstanceProcess stale = Parse(await Status(session)).Process;
        session.ProcessAlive = pid => pid == 777;
        InstanceProcess live = Parse(await Status(session)).Process;

        Assert.Equal((RunState.Stopped, RunStateSource.Watchdog), (none.State, none.Source));
        Assert.Equal(RunState.Stopped, stale.State);
        Assert.Equal((RunState.Running, RunStateSource.PidFile, 777), (live.State, live.Source, live.Pid));
        Assert.Contains("outside the watchdog", live.Detail);
    }

    [Fact]
    public async Task AWatchdogThatIsNotThere_LeavesTheRunStateToThePidFile()
    {
        var (session, directory) = NewInstance();
        session.Watchdog.SocketPresent = false;

        InstanceProcess stopped = Parse(await Status(session)).Process;
        File.WriteAllText(Path.Combine(directory, ".factorio-a.pid"), "777");
        session.ProcessAlive = _ => true;
        InstanceProcess running = Parse(await Status(session)).Process;

        Assert.Equal((RunState.Stopped, RunStateSource.PidFile), (stopped.State, stopped.Source));
        Assert.Equal(RunState.Running, running.State);
        Assert.Equal(0, session.Watchdog.Calls);
    }

    [Fact]
    public async Task AWatchdogThatIsDisabled_IsNeverAsked()
    {
        var (session, _) = NewInstance();
        session.Extra["Watchdog__Enabled"] = "false";
        session.Watchdog.Tracked["factorio-a"] = FakeWatchdog.State("factorio-a", populated: true, pid: 1);

        InstanceProcess process = Parse(await Status(session)).Process;

        Assert.Equal((RunState.Stopped, RunStateSource.PidFile), (process.State, process.Source));
        Assert.Equal(0, session.Watchdog.Calls);
    }

    [Fact]
    public async Task AWatchdogSocketThatDoesNotAnswer_IsUnknown_NeverStopped()
    {
        var (session, _) = NewInstance();
        session.Watchdog.Health = new WatchdogHealth(false, false, "connection refused");

        InstanceProcess process = Parse(await Status(session)).Process;

        Assert.Equal((RunState.Unknown, RunStateSource.None), (process.State, process.Source));
        Assert.Contains("connection refused", process.Detail);
    }

    [Fact]
    public async Task AWatchdogThatStopsAnsweringMidRead_IsUnknown()
    {
        var (session, _) = NewInstance();
        session.Watchdog.ThrowOnStatus = true;

        Assert.Equal(RunState.Unknown, Parse(await Status(session)).Process.State);
    }

    [Fact]
    public async Task AWatchdogThatIsNotReady_StillAnswersForTheInstance_AndSaysSo()
    {
        var (session, _) = NewInstance();
        session.Watchdog.Health = new WatchdogHealth(true, false, "not in the slice");
        session.Watchdog.Tracked["factorio-a"] = FakeWatchdog.State("factorio-a", populated: true, pid: 9);

        InstanceProcess process = Parse(await Status(session)).Process;

        Assert.Equal(RunState.Running, process.State);
        Assert.Contains("not in the slice", process.Detail);
    }

    // --- container run state: the runtime's answer ---

    [Fact]
    public async Task AContainer_IsRunning_WhenComposeListsARunningService_AndStoppedWhenItListsNone()
    {
        var (session, directory) = NewInstance(c => c with { Runtime = BlueprintRuntime.Container });
        File.WriteAllText(Path.Combine(directory, "factorio-a.docker-compose.yml"), "services: {}");

        session.Containers.Answer = ComposeAnswer.Of([new ComposeService("game", "running")]);
        InstanceProcess running = Parse(await Status(session)).Process;
        session.Containers.Answer = ComposeAnswer.Of([]);
        InstanceProcess stopped = Parse(await Status(session)).Process;

        Assert.Equal((RunState.Running, RunStateSource.Compose), (running.State, running.Source));
        Assert.Equal(RunState.Stopped, stopped.State);
        Assert.Equal(0, session.Watchdog.Calls);
    }

    [Fact]
    public async Task AContainerWhoseRuntimeCannotBeAsked_IsUnknown()
    {
        var (session, directory) = NewInstance(c => c with { Runtime = BlueprintRuntime.Container });
        File.WriteAllText(Path.Combine(directory, "factorio-a.docker-compose.yml"), "services: {}");
        session.Containers.Answer = ComposeAnswer.Unavailable("docker is not installed");

        InstanceProcess process = Parse(await Status(session)).Process;

        Assert.Equal(RunState.Unknown, process.State);
        Assert.Equal("docker is not installed", process.Detail);
    }

    [Fact]
    public void ComposePsOutput_IsReadAsLinesAndAsAnArray()
    {
        ComposeAnswer lines = DockerCompose.Parse("{\"Service\":\"game\",\"State\":\"running\"}\n{\"Service\":\"db\",\"State\":\"exited\"}\n");
        ComposeAnswer array = DockerCompose.Parse("[{\"Name\":\"x-game-1\",\"State\":\"running\"}]");
        ComposeAnswer empty = DockerCompose.Parse("");
        ComposeAnswer garbage = DockerCompose.Parse("not json");

        Assert.Equal([("game", "running"), ("db", "exited")], lines.Services!.Select(s => (s.Name, s.State)));
        Assert.Equal("running", Assert.Single(array.Services!).State);
        Assert.Empty(empty.Services!);
        Assert.Null(garbage.Services);
    }

    // --- the rest of the document ---

    [Fact]
    public async Task AnOfflineLibrary_ReportsUnknownWithoutAskingAnything()
    {
        var sandbox = Sandbox.Create();
        var session = new CliSession(sandbox);
        sandbox.AddInstance(sandbox.AddLibrary("away", withMarker: false), "factorio", "factorio-a");

        InstanceStatus status = Parse(await Status(session, "--disk"));

        Assert.Equal((RunState.Unknown, RunStateSource.None), (status.Process.State, status.Process.Source));
        Assert.Equal(InstanceLibraryState.Offline, status.LibraryState);
        Assert.Null(status.DiskUsageBytes);
        Assert.Equal(0, session.Watchdog.Calls);
    }

    [Fact]
    public async Task TheVersion_IsTheInstalledOne_AndWithoutACheckOnRecordNoUpdateIsClaimedOrRuledOut()
    {
        var (session, directory) = NewInstance();
        File.WriteAllText(Path.Combine(directory, ".factorio-a.version"), "2.0.1\n");

        InstanceVersion unchecked_ = Parse(await Status(session)).Version;
        File.WriteAllText(Path.Combine(directory, ".factorio-a.latest"), "2.0.1\n2026-10-04T09:38:41Z\n");
        InstanceVersion current = Parse(await Status(session)).Version;
        File.WriteAllText(Path.Combine(directory, ".factorio-a.latest"), "2.0.2\n2026-10-04T09:38:41Z\n");
        InstanceVersion behind = Parse(await Status(session)).Version;

        Assert.Equal(("2.0.1", false, (bool?)null, (string?)null), (unchecked_.Current, unchecked_.Checked, unchecked_.UpdatesAvailable, unchecked_.Latest));
        Assert.Equal((true, (bool?)false), (current.Checked, current.UpdatesAvailable));
        Assert.Equal(new DateTimeOffset(2026, 10, 4, 9, 38, 41, TimeSpan.Zero), current.CheckedAt);
        Assert.Equal(((bool?)true, "2.0.2"), (behind.UpdatesAvailable, behind.Latest));
    }

    [Fact]
    public async Task Backups_AreListedByIdNewestFirst_AndRecentLogsAreTheLastThreeLines()
    {
        var (session, directory) = NewInstance();
        string backups = Path.Combine(session.Sandbox.Root, "backups", "factorio-a");
        foreach ((string id, string at) in new[] { ("b-1", "2026-01-01T00:00:00Z"), ("b-2", "2026-01-02T00:00:00Z") })
        {
            session.Sandbox.WriteFile(Path.Combine(backups, id, "manifest.json"),
                $$"""{"schemaVersion":1,"id":"{{id}}","createdAt":"{{at}}","compressed":false,"sources":[],"sizeBytes":0,"fileCount":0}""");
        }

        File.WriteAllLines(Path.Combine(directory, "factorio-a.log"), ["a", "b", "c", "d"]);

        InstanceStatus status = Parse(await Status(session));

        Assert.Equal(["b-2", "b-1"], status.Backups);
        Assert.Equal(["b", "c", "d"], status.RecentLogs);
    }

    [Fact]
    public async Task WithNoLiveLog_TheNewestRotatedLogIsTheSource()
    {
        var (session, directory) = NewInstance();
        string logs = Path.Combine(directory, "logs");
        Directory.CreateDirectory(logs);
        File.WriteAllText(Path.Combine(logs, "factorio-a.2026-01-01T00:00:00.log"), "old\n");
        File.WriteAllText(Path.Combine(logs, "factorio-a.2026-02-01T00:00:00.log"), "newer\n");
        File.SetLastWriteTimeUtc(Path.Combine(logs, "factorio-a.2026-01-01T00:00:00.log"), new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        File.SetLastWriteTimeUtc(Path.Combine(logs, "factorio-a.2026-02-01T00:00:00.log"), new DateTime(2026, 2, 1, 0, 0, 0, DateTimeKind.Utc));

        Assert.Equal(["newer"], Parse(await Status(session)).RecentLogs);
    }

    [Fact]
    public async Task DiskUsage_IsMeasuredInBytesOnlyWhenAsked()
    {
        var (session, directory) = NewInstance();
        Directory.CreateDirectory(Path.Combine(directory, "install"));
        File.WriteAllBytes(Path.Combine(directory, "install", "big.bin"), new byte[4096]);
        File.WriteAllBytes(Path.Combine(directory, "saves.dat"), new byte[100]);
        long configBytes = new FileInfo(Path.Combine(directory, "factorio-a.config.json")).Length;

        InstanceStatus without = Parse(await Status(session));
        InstanceStatus with = Parse(await Status(session, "--disk"));

        Assert.Null(without.DiskUsageBytes);
        Assert.Equal(4096 + 100 + configBytes, with.DiskUsageBytes);
    }

    [Fact]
    public async Task TheText_NamesTheStateAndTheWayItWasLearned()
    {
        var (session, _) = NewInstance();
        session.Watchdog.Tracked["factorio-a"] = FakeWatchdog.State("factorio-a", populated: true, pid: 4242);

        CliRun run = await session.RunAsync("instance", "status", "factorio-a");

        Assert.Contains("running (pid 4242)", run.Out);
        Assert.Contains("watchdog", run.Out);
        Assert.Contains("not checked", run.Out);
    }
}
