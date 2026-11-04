using TheKrystalShip.Testing;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>A native instance's lifecycle, run by a real generated script against a fake game.</summary>
public class ScriptLifecycleTests
{
    [Fact]
    public async Task IsActive_ReportsInactive_WhenNothingRuns()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("is-active");

        Assert.Equal(1, run.Exit);
        Assert.Equal("Inactive\n", run.Out);
    }

    [Fact]
    public async Task StartDetached_LaunchesTheGameWithResolvedArguments_FromItsLaunchDirectory()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { ExecutableSubdirectory = "bin", LevelName = "my world" });
        Directory.CreateDirectory(Path.Combine(world.Install, "bin"));
        File.Move(Path.Combine(world.Install, "server"), Path.Combine(world.Install, "bin", "server"));

        await world.StartGameAsync();

        Assert.Equal(["--save", $"{world.Saves}/my world", "--name", ScriptWorld.Id], world.GameArguments());
        Assert.Equal(Path.Combine(world.Install, "bin"), world.Recorded("game/cwd").Single());
        Assert.Equal(world.GamePid().ToString(), File.ReadAllText(world.PidFile).Trim());
        Assert.Equal("Active\n", (await world.RunAsync("is-active")).Out);
    }

    [Fact]
    public async Task StartDetached_ConnectsTheConsolePipeToTheGamesStdin_AndItsOutputToTheLog()
    {
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();

        Assert.True((await world.RunAsync("input", "hello world")).Exit == 0);

        await Eventually.Holds(() => world.Recorded("game/input").Contains("hello world"), "the game read the line");
        Assert.True(File.Exists(world.LogFile));
    }

    [Fact]
    public async Task StartDetached_RefusesAnInstanceThatIsAlreadyRunning()
    {
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();
        int pid = world.GamePid();

        ScriptRun second = await world.RunAsync("start", "-d");

        Assert.Equal(1, second.Exit);
        Assert.Contains("already running", second.Err, StringComparison.Ordinal);
        Assert.Equal(pid, world.GamePid());
    }

    [Fact]
    public async Task StartDetached_RotatesTheLastRunsLog_ByItsLastWrite()
    {
        using ScriptWorld world = ScriptWorld.Native();
        File.WriteAllText(world.LogFile, "previous run\n");
        File.SetLastWriteTimeUtc(world.LogFile, new DateTime(2026, 3, 4, 5, 6, 7, DateTimeKind.Utc));

        await world.StartGameAsync();

        string rotated = Path.Combine(world.Logs, $"{ScriptWorld.Id}.2026-03-04T05:06:07.log");
        Assert.Equal("previous run\n", File.ReadAllText(rotated));
    }

    [Fact]
    public async Task StartDetached_NeverOverwritesARotatedLog_WhenTwoRunsEndInOneSecond()
    {
        using ScriptWorld world = ScriptWorld.Native();
        Directory.CreateDirectory(world.Logs);
        string taken = Path.Combine(world.Logs, $"{ScriptWorld.Id}.2026-03-04T05:06:07.log");
        File.WriteAllText(taken, "first run\n");
        File.WriteAllText(world.LogFile, "second run\n");
        File.SetLastWriteTimeUtc(world.LogFile, new DateTime(2026, 3, 4, 5, 6, 7, DateTimeKind.Utc));

        await world.StartGameAsync();

        Assert.Equal("first run\n", File.ReadAllText(taken));
        string[] rotated = [.. Directory.GetFiles(world.Logs).Where(f => f != taken)];
        Assert.Equal("second run\n", File.ReadAllText(Assert.Single(rotated)));
    }

    [Fact]
    public async Task StartDetached_FailsBeforeLaunching_WhenALaunchArgumentNamesAnUnknownKey()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { ExecutableArguments = "--x {nothing}" });

        ScriptRun run = await world.RunAsync("start", "-d");

        Assert.Equal(1, run.Exit);
        Assert.Contains("{nothing}", run.Err, StringComparison.Ordinal);
        Assert.False(File.Exists(world.Fake("game/started")));
        Assert.False(File.Exists(world.PidFile));
        Assert.False(File.Exists(world.InputFifo));
    }

    [Fact]
    public async Task StartDetached_FailsClearly_WhenTheExecutableIsMissing()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { ExecutableFile = "./absent" });

        ScriptRun run = await world.RunAsync("start", "-d");

        Assert.Equal(1, run.Exit);
        Assert.Contains("not an executable file", run.Err, StringComparison.Ordinal);
        Assert.False(File.Exists(world.PidFile));
    }

    [Fact]
    public async Task StartDetached_ReturnsOnlyTheScriptsOutput_SoACallerReadingItsPipesIsNeverHeld()
    {
        using ScriptWorld world = ScriptWorld.Native();

        // RunAsync reads stdout and stderr to the end: it returns only because the game and its keepalive
        // hold neither pipe.
        ScriptRun run = await world.RunAsync("start", "-d");

        Assert.Equal(0, run.Exit);
        Assert.Equal(string.Empty, run.Out);
    }

    [Fact]
    public async Task IsActive_RemovesAStalePidFile_AndReportsInactive()
    {
        using ScriptWorld world = ScriptWorld.Native();
        File.WriteAllText(world.PidFile, "999999\n");

        ScriptRun run = await world.RunAsync("is-active");

        Assert.Equal(1, run.Exit);
        Assert.False(File.Exists(world.PidFile));
    }

    [Fact]
    public async Task IsActive_RemovesAPidFileThatIsNotANumber()
    {
        using ScriptWorld world = ScriptWorld.Native();
        File.WriteAllText(world.PidFile, "not-a-pid\n");

        Assert.Equal(1, (await world.RunAsync("is-active")).Exit);
        Assert.False(File.Exists(world.PidFile));
    }

    // --- stop: the save command, the stop command, then TERM, then KILL ---

    [Fact]
    public async Task Stop_SendsTheSaveCommandThenTheStopCommand_AndTheGameExitsOnItsOwn()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.Script("game/stop-token", "stop\n");
        await world.StartGameAsync();
        int pid = world.GamePid();

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["save", "stop"], world.Recorded("game/input"));
        Assert.True(File.Exists(world.Fake("game/exited-by-token")), "the game left by its own stop command, not by a signal");
        Assert.False(ProcessTable.Alive(pid));
        Assert.False(File.Exists(world.PidFile));
        Assert.False(File.Exists(world.InputFifo));
    }

    [Fact]
    public async Task Stop_IsGracefulFromTheScript_WhereTheBashScriptSkippedBothCommands()
    {
        // A stop with no flags saves, sends the stop command and waits; it does not go straight to TERM.
        using ScriptWorld world = ScriptWorld.Native();
        world.Script("game/stop-token", "stop\n");
        await world.StartGameAsync();

        await world.RunAsync("stop");

        Assert.Contains("save", world.Recorded("game/input"));
        Assert.Contains("stop", world.Recorded("game/input"));
    }

    [Fact]
    public async Task Stop_WithNoSave_SendsOnlyTheStopCommand()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.Script("game/stop-token", "stop\n");
        await world.StartGameAsync();

        Assert.Equal(0, (await world.RunAsync("stop", "--no-save")).Exit);

        Assert.Equal(["stop"], world.Recorded("game/input"));
    }

    [Fact]
    public async Task Stop_WithNoGraceful_SendsNoCommandAndEndsTheProcessWithTerm()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.Script("game/stop-token", "stop\n");
        await world.StartGameAsync();
        int pid = world.GamePid();

        ScriptRun run = await world.RunAsync("stop", "--no-save", "--no-graceful");

        Assert.Equal(0, run.Exit);
        Assert.Empty(world.Recorded("game/input"));
        Assert.False(File.Exists(world.Fake("game/exited-by-token")));
        Assert.False(ProcessTable.Alive(pid));
    }

    [Fact]
    public async Task Stop_EscalatesToTerm_WhenTheGameIgnoresItsStopCommand()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { StopCommandTimeoutSeconds = 1 });
        await world.StartGameAsync();
        int pid = world.GamePid();

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(0, run.Exit);
        Assert.Contains("did not exit", run.Err, StringComparison.Ordinal);
        Assert.False(ProcessTable.Alive(pid));
        Assert.DoesNotContain("sending KILL", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Stop_EscalatesToKill_WhenTheGameIgnoresBothItsStopCommandAndTerm()
    {
        // A game that ignores both its stop command and TERM is ended with KILL.
        using ScriptWorld world = ScriptWorld.Native(c => c with { StopCommandTimeoutSeconds = 1 });
        world.Script("game/ignore-term", "1");
        await world.StartGameAsync();
        int pid = world.GamePid();

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(0, run.Exit);
        Assert.Contains("sending KILL", run.Err, StringComparison.Ordinal);
        Assert.False(ProcessTable.Alive(pid));
        Assert.False(File.Exists(world.PidFile));
    }

    [Fact]
    public async Task Stop_EndsTheGamesChildrenToo()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { StopCommandTimeoutSeconds = 1 });
        world.Script("game/spawn-child", "1");
        world.Script("game/ignore-term", "1");
        await world.StartGameAsync();
        await Eventually.Holds(() => File.Exists(world.Fake("game/child.pid")), "the child started");
        int child = world.ChildPid();
        Assert.True(ProcessTable.Alive(child));

        Assert.Equal(0, (await world.RunAsync("stop")).Exit);

        Assert.False(ProcessTable.Alive(child));
    }

    [Fact]
    public async Task Stop_EndsAChildThatOutlivesTheGameAfterItsStopCommand()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.Script("game/stop-token", "stop\n");
        world.Script("game/spawn-child", "1");
        await world.StartGameAsync();
        await Eventually.Holds(() => File.Exists(world.Fake("game/child.pid")), "the child started");
        int child = world.ChildPid();

        Assert.Equal(0, (await world.RunAsync("stop")).Exit);

        Assert.False(ProcessTable.Alive(child));
    }

    [Fact]
    public async Task Stop_OfAnInstanceThatIsNotRunning_SucceedsAndTouchesNothing()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(0, run.Exit);
        Assert.Contains("not running", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Stop_RefusesAnArgumentItDoesNotKnow()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("stop", "--now");

        Assert.Equal(8, run.Exit);
    }

    [Fact]
    public async Task Stop_WithNoStopCommandDeclared_GoesStraightToTerm()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { StopCommand = string.Empty, SaveCommand = string.Empty });
        await world.StartGameAsync();
        int pid = world.GamePid();

        Assert.Equal(0, (await world.RunAsync("stop")).Exit);

        Assert.False(ProcessTable.Alive(pid));
        Assert.Empty(world.Recorded("game/input"));
    }

    [Fact]
    public async Task Restart_StopsTheGameAndStartsANewOne()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.Script("game/stop-token", "stop\n");
        await world.StartGameAsync();
        int first = world.GamePid();
        File.Delete(world.Fake("game/started"));

        ScriptRun run = await world.RunAsync("restart");

        Assert.Equal(0, run.Exit);
        await Eventually.Holds(() => File.Exists(world.Fake("game/started")), "the second game started");
        Assert.NotEqual(first, world.GamePid());
        Assert.False(ProcessTable.Alive(first));
    }

    [Fact]
    public async Task Kill_EndsTheGameAtOnceWithKill_WhateverItIgnores()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.Script("game/ignore-term", "1");
        world.Script("game/spawn-child", "1");
        await world.StartGameAsync();
        await Eventually.Holds(() => File.Exists(world.Fake("game/child.pid")), "the child started");
        int pid = world.GamePid();
        int child = world.ChildPid();

        ScriptRun run = await world.RunAsync("kill");

        Assert.Equal(0, run.Exit);
        Assert.False(ProcessTable.Alive(pid));
        Assert.False(ProcessTable.Alive(child));
        Assert.False(File.Exists(world.PidFile));
    }

    [Fact]
    public async Task Kill_WithNothingRunning_FailsAndSaysSo()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("kill");

        Assert.Equal(1, run.Exit);
        Assert.Contains("No live PID file", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task StartDetached_RunsAnUpdateFirst_WhenTheInstanceUpdatesBeforeStart()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { AutoUpdateBeforeStart = true, SteamAppId = 1234 });
        world.Script("steam/buildid", "777\n");
        File.WriteAllText(world.VersionFile, "100\n");
        File.WriteAllText(Path.Combine(world.Install, "old.txt"), "old");

        await world.StartGameAsync();

        Assert.Equal("777", File.ReadAllText(world.VersionFile).Trim());
        Assert.True(File.Exists(Path.Combine(world.Install, "game.bin")));
        Assert.Single(Directory.GetDirectories(world.BackupsDirectory));
    }

    [Fact]
    public async Task StartDetached_DoesNotStart_WhenTheUpdateBeforeItFails()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { AutoUpdateBeforeStart = true, SteamAppId = 1234 });
        world.Script("steam/no-buildid", "1");

        ScriptRun run = await world.RunAsync("start", "-d");

        Assert.Equal(1, run.Exit);
        Assert.False(File.Exists(world.Fake("game/started")));
    }

    // --- attach ---

    [Fact]
    public async Task Attach_RefusesWhenNothingRuns()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("attach");

        Assert.Equal(1, run.Exit);
        Assert.Contains("not running", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Attach_SendsTheLinesYouTypeToTheGame_UntilDetach_AndTheGameKeepsRunning()
    {
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();

        ScriptRun run = await world.RunWithInputAsync("say hello\n\nsay again\n.detach\nsay never\n", "attach");

        Assert.Equal(0, run.Exit);
        await Eventually.Holds(() => world.Recorded("game/input").SequenceEqual(["say hello", "say again"]), "the game read what was typed before .detach");
        Assert.True(ProcessTable.Alive(world.GamePid()));
    }

    [Fact]
    public async Task Attach_NeverSendsALineThatWouldBeShellSyntax()
    {
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();

        ScriptRun run = await world.RunWithInputAsync("say $(id)\nsay ok\n.detach\n", "attach");

        Assert.Equal(0, run.Exit);
        Assert.Contains("Input rejected", run.Err, StringComparison.Ordinal);
        await Eventually.Holds(() => world.Recorded("game/input").SequenceEqual(["say ok"]), "only the safe line reached the game");
    }

    [Fact]
    public async Task Start_WithoutDetached_StartsInTheBackgroundThenAttaches()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunWithInputAsync("say typed\n.detach\n", "start");

        Assert.Equal(0, run.Exit);
        await Eventually.Holds(() => world.Recorded("game/input").Contains("say typed"), "the game read the typed line");
        Assert.Equal("Active\n", (await world.RunAsync("is-active")).Out);
    }

    [Fact]
    public async Task Start_RefusesAnArgumentItDoesNotKnow()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(8, (await world.RunAsync("start", "--fast")).Exit);
        Assert.Equal(8, (await world.RunAsync("start", "extra")).Exit);
    }
}
