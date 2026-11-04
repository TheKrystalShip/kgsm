using System.Net.Sockets;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>
/// A native instance the watchdog runs has no pid file. When its control socket exists the script asks it,
/// over the socket with curl; otherwise the pid file is the whole answer.
/// </summary>
public class ScriptWatchdogTests
{
    private static ScriptWorld World() => ScriptWorld.Native(realCurl: true);

    private static string Ok(string instance, string verb) => $$"""{"instance":"{{instance}}","ok":true,"message":"{{verb}}ped"}""";

    [Fact]
    public async Task IsActive_AsksTheWatchdog_WhenItsSocketExists()
    {
        using ScriptWorld world = World();
        FakeWatchdogServer watchdog = world.StartWatchdog();
        watchdog.Track(ScriptWorld.Id, populated: true, pid: 4242);

        ScriptRun run = await world.RunAsync("is-active");

        Assert.Equal(0, run.Exit);
        Assert.Equal("Active\n", run.Out);
        Assert.Contains(new WatchdogRequest("GET", "/status/g-1"), watchdog.Requests);
        Assert.False(File.Exists(world.PidFile));
    }

    [Fact]
    public async Task IsActive_IsInactive_WhenTheWatchdogTracksTheInstanceAndNothingRuns()
    {
        using ScriptWorld world = World();
        world.StartWatchdog().Track(ScriptWorld.Id, populated: false);

        ScriptRun run = await world.RunAsync("is-active");

        Assert.Equal(1, run.Exit);
        Assert.Equal("Inactive\n", run.Out);
    }

    [Fact]
    public async Task IsActive_FallsBackToThePidFile_WhenTheWatchdogDoesNotTrackTheInstance()
    {
        using ScriptWorld world = World();
        FakeWatchdogServer watchdog = world.StartWatchdog();
        await world.StartGameAsync();

        ScriptRun run = await world.RunAsync("is-active");

        Assert.Equal(0, run.Exit);
        Assert.Contains(new WatchdogRequest("GET", "/status/g-1"), watchdog.Requests);
    }

    [Fact]
    public async Task IsActive_FallsBackToThePidFile_WhenTheSocketIsStaleAndNothingAnswers()
    {
        using ScriptWorld world = World();
        // Bound and never listening: the file exists and every connection is refused.
        using var bound = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        bound.Bind(new UnixDomainSocketEndPoint(world.SocketPath));

        Assert.True(File.Exists(world.SocketPath));
        await world.StartGameAsync();

        ScriptRun run = await world.RunAsync("is-active");

        Assert.Equal(0, run.Exit);
        Assert.Equal("Active\n", run.Out);
    }

    [Fact]
    public async Task IsActive_UsesOnlyThePidFile_WhenThereIsNoSocket()
    {
        using ScriptWorld world = World();

        Assert.Equal(1, (await world.RunAsync("is-active")).Exit);
        await world.StartGameAsync();
        Assert.Equal(0, (await world.RunAsync("is-active")).Exit);
    }

    [Fact]
    public async Task TheEnvironmentOverridesTheSocketTheScriptWasBuiltWith()
    {
        using ScriptWorld world = World();
        world.StartWatchdog().Track(ScriptWorld.Id, populated: true, pid: 1);
        world.Environment["KGSM_WATCHDOG_SOCKET"] = Path.Combine(world.Sandbox.Root, "nowhere.sock");

        Assert.Equal(1, (await world.RunAsync("is-active")).Exit);
    }

    [Fact]
    public async Task Status_ReportsTheWatchdogsPidAndSpawnTime()
    {
        using ScriptWorld world = World();
        world.StartWatchdog().Track(ScriptWorld.Id, populated: true, pid: 4242, spawnedAt: "2026-03-04T05:06:07Z");

        ScriptRun run = await world.RunAsync("status", "--json", "--fast");

        ScriptStatus status = ScriptJson.Status(run.Out);
        Assert.True(status.Status);
        Assert.Equal(4242, status.Process.Pid);
        Assert.Equal("running", status.Process.Status);
        Assert.Equal("2026-03-04T05:06:07Z", status.Process.StartTime);
    }

    [Fact]
    public async Task Stop_AsksTheWatchdogToStop_AndSignalsNothingItself()
    {
        using ScriptWorld world = World();
        FakeWatchdogServer watchdog = world.StartWatchdog();
        watchdog.Track(ScriptWorld.Id, populated: true, pid: 4242);
        watchdog.Answer("POST", "/stop/g-1", 200, Ok(ScriptWorld.Id, "stop"));

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(0, run.Exit);
        Assert.Contains(new WatchdogRequest("POST", "/stop/g-1?origin=script"), watchdog.Requests);
        Assert.Empty(world.Recorded("game/input"));
    }

    [Fact]
    public async Task Stop_FailsWithTheWatchdogsReason_WhenItRefuses()
    {
        using ScriptWorld world = World();
        FakeWatchdogServer watchdog = world.StartWatchdog();
        watchdog.Track(ScriptWorld.Id, populated: true, pid: 4242);
        watchdog.Answer("POST", "/stop/g-1", 409, """{"instance":"g-1","ok":false,"message":"the instance is held"}""");

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(1, run.Exit);
        Assert.Contains("the instance is held", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Stop_SaysThatItsFlagsDoNotApplyToAnInstanceTheWatchdogStops()
    {
        using ScriptWorld world = World();
        FakeWatchdogServer watchdog = world.StartWatchdog();
        watchdog.Track(ScriptWorld.Id, populated: true, pid: 4242);
        watchdog.Answer("POST", "/stop/g-1", 200, Ok(ScriptWorld.Id, "stop"));

        ScriptRun run = await world.RunAsync("stop", "--no-save");

        Assert.Equal(0, run.Exit);
        Assert.Contains("do not apply", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Stop_UsesThePidFilePath_ForAnInstanceTheWatchdogDoesNotTrack()
    {
        using ScriptWorld world = World();
        FakeWatchdogServer watchdog = world.StartWatchdog();
        world.Script("game/stop-token", "stop\n");
        await world.StartGameAsync();

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(0, run.Exit);
        Assert.DoesNotContain(watchdog.Requests, r => r.Method == "POST");
        Assert.True(File.Exists(world.Fake("game/exited-by-token")));
    }

    [Fact]
    public async Task Restart_AsksTheWatchdogToRestart_AnInstanceItRuns()
    {
        using ScriptWorld world = World();
        FakeWatchdogServer watchdog = world.StartWatchdog();
        watchdog.Track(ScriptWorld.Id, populated: true, pid: 4242);
        watchdog.Answer("POST", "/restart/g-1", 200, Ok(ScriptWorld.Id, "restart"));

        ScriptRun run = await world.RunAsync("restart");

        Assert.Equal(0, run.Exit);
        Assert.Contains(new WatchdogRequest("POST", "/restart/g-1?origin=script"), watchdog.Requests);
        Assert.False(File.Exists(world.Fake("game/started")));
    }

    [Fact]
    public async Task Kill_OfAnInstanceTheWatchdogRuns_AsksItToStopRatherThanFightingItsSupervision()
    {
        using ScriptWorld world = World();
        FakeWatchdogServer watchdog = world.StartWatchdog();
        watchdog.Track(ScriptWorld.Id, populated: true, pid: 4242);
        watchdog.Answer("POST", "/stop/g-1", 200, Ok(ScriptWorld.Id, "stop"));

        ScriptRun run = await world.RunAsync("kill");

        Assert.Equal(0, run.Exit);
        Assert.Contains(new WatchdogRequest("POST", "/stop/g-1?origin=script"), watchdog.Requests);
    }

    [Fact]
    public async Task Backup_OfAWatchdogRunInstance_SeesItIsRunningWithoutAPidFile()
    {
        using ScriptWorld world = World();
        world.StartWatchdog().Track(ScriptWorld.Id, populated: true, pid: 4242);
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "w");

        ScriptRun run = await world.RunAsync("create-backup");

        // The save command had no console pipe to reach, so the backup is honest about being hot.
        Assert.Equal(0, run.Exit);
        Assert.Equal(["saves"], ScriptJson.Manifest(world, run.LastOutLine).Sources);
        Assert.Equal(Contracts.Backups.BackupConsistency.Hot, ScriptJson.Manifest(world, run.LastOutLine).Consistency);
    }
}
