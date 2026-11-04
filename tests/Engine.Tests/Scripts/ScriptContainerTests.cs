using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.Testing;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>A container instance's script, against a fake docker with compose and buildx.</summary>
public class ScriptContainerTests
{
    private const string Running = """[{"Service":"s","State":"running"}]""";

    private static ScriptWorld World(Func<Contracts.Instances.InstanceConfig, Contracts.Instances.InstanceConfig>? shape = null)
    {
        ScriptWorld world = ScriptWorld.Container(c => (shape ?? (x => x))(c with { StopCommandTimeoutSeconds = 1 }));
        world.Script("docker/images", "example/img:latest\n");
        world.Script("docker/services", "svc\n");
        return world;
    }

    private static void RunningState(ScriptWorld world)
    {
        world.Script("docker/ps.json", Running);
        world.Script("docker/container-id", "cid0123456789abcdef\n");
    }

    private static string[][] Compose(ScriptWorld world, params string[] verb) =>
        [.. world.Calls("docker/log").Where(c => c.Length > 3 && c[0] == "compose" && c[3..].Take(verb.Length).SequenceEqual(verb))];

    // --- run state ---

    [Fact]
    public async Task IsActive_IsComposesAnswer_NotAFile()
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.PidFile, "cid0123456789abcdef\n");

        Assert.Equal(1, (await world.RunAsync("is-active")).Exit);
        Assert.False(File.Exists(world.PidFile), "a pid file compose does not stand behind is removed");

        RunningState(world);
        ScriptRun active = await world.RunAsync("is-active");
        Assert.Equal(0, active.Exit);
        Assert.Equal("Active\n", active.Out);
    }

    [Fact]
    public async Task EveryComposeCall_RunsFromTheWorkingDirectory_AgainstTheInstancesComposeFile()
    {
        using ScriptWorld world = World();

        await world.RunAsync("is-active");

        Assert.Equal(world.WorkingDirectory, world.Recorded("docker/cwd").Last());
        Assert.Equal(Path.Combine(world.WorkingDirectory, "g-1.docker-compose.yml"), world.Calls("docker/log").Last(c => c.Length > 2 && c[1] == "-f")[2]);
    }

    // --- start ---

    [Fact]
    public async Task StartDetached_BringsTheProjectUp_AndRecordsTheContainerId()
    {
        using ScriptWorld world = World();

        ScriptRun run = await world.RunAsync("start", "-d");

        Assert.Equal(0, run.Exit);
        Assert.Single(Compose(world, "up", "-d"));
        Assert.Equal("cid0123456789abcdef\n", File.ReadAllText(world.PidFile));
    }

    [Fact]
    public async Task StartDetached_RefusesAnInstanceThatIsAlreadyRunning()
    {
        using ScriptWorld world = World();
        RunningState(world);

        ScriptRun run = await world.RunAsync("start", "-d");

        Assert.Equal(1, run.Exit);
        Assert.Contains("already running", run.Err, StringComparison.Ordinal);
        Assert.Empty(Compose(world, "up"));
    }

    [Fact]
    public async Task StartDetached_FailsWhenComposeFails()
    {
        using ScriptWorld world = World();
        world.Script("docker/fail-up", "1");

        ScriptRun run = await world.RunAsync("start", "-d");

        Assert.Equal(1, run.Exit);
        Assert.Contains("Failed to start the container", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task StartDetached_RotatesTheLog_AndNeedsNoWatchdog()
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.LogFile, "last run\n");
        File.SetLastWriteTimeUtc(world.LogFile, new DateTime(2026, 3, 4, 5, 6, 7, DateTimeKind.Utc));

        Assert.Equal(0, (await world.RunAsync("start", "-d")).Exit);

        Assert.Equal("last run\n", File.ReadAllText(Path.Combine(world.Logs, "g-1.2026-03-04T05:06:07.log")));
    }

    [Fact]
    public async Task Start_WithoutDocker_SaysSoRatherThanFailingTheScriptsLoad()
    {
        using ScriptWorld world = World();
        File.Delete(Path.Combine(world.Bin, "docker"));

        ScriptRun help = await world.RunAsync("help");
        ScriptRun start = await world.RunAsync("start", "-d");

        Assert.Equal(0, help.Exit);
        Assert.Equal(1, start.Exit);
        Assert.Contains("docker is not installed", start.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task StartDetached_UpdatesFirst_WhenTheInstanceUpdatesBeforeStart()
    {
        using ScriptWorld world = World(c => c with { AutoUpdateBeforeStart = true });
        File.WriteAllText(Path.Combine(world.Saves, "w.sav"), "w");

        Assert.Equal(0, (await world.RunAsync("start", "-d")).Exit);

        Assert.Single(Compose(world, "pull"));
        Assert.Single(Directory.GetDirectories(world.BackupsDirectory));
    }

    // --- stop ---

    [Fact]
    public async Task Stop_SavesAndSendsTheStopCommandThroughTheCommandPipe_RecordsTheLifecycleThenTakesTheProjectDown()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.ServeCommandFifo();

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(0, run.Exit);
        await Eventually.Holds(() => world.Recorded("container-input").SequenceEqual(["save", "stop"]), "the entrypoint read both commands");
        string lifecycle = Assert.Single(File.ReadAllLines(Path.Combine(world.Events, "lifecycle.ndjson")));
        Assert.Matches(@"^\{""type"":""instance_stopping"",""ts"":""\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z""\}$", lifecycle);
        Assert.True(File.Exists(world.Fake("docker/lifecycle-before-down")), "instance_stopping is recorded before compose down");
        Assert.Equal(["--timeout", "1"], Compose(world, "down").Single()[4..6]);
    }

    [Fact]
    public async Task Stop_WithNoSaveAndNoGraceful_SendsNothing_AndStillTakesTheProjectDown()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.ServeCommandFifo();

        Assert.Equal(0, (await world.RunAsync("stop", "--no-save", "--no-graceful")).Exit);

        Assert.Empty(world.Recorded("container-input"));
        Assert.Single(Compose(world, "down"));
    }

    [Fact]
    public async Task Stop_OfAContainerThatIsNotRunning_SucceedsAndTouchesNothing()
    {
        using ScriptWorld world = World();

        Assert.Equal(0, (await world.RunAsync("stop")).Exit);

        Assert.Empty(Compose(world, "down"));
        Assert.False(File.Exists(Path.Combine(world.Events, "lifecycle.ndjson")));
    }

    [Fact]
    public async Task Stop_FailsWhenComposeDownFails()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.Script("docker/fail-down", "1");

        ScriptRun run = await world.RunAsync("stop", "--no-save", "--no-graceful");

        Assert.Equal(1, run.Exit);
    }

    [Fact]
    public async Task Stop_ProceedsToComposeDown_WhenTheCommandPipeIsMissing()
    {
        using ScriptWorld world = World();
        RunningState(world);

        ScriptRun run = await world.RunAsync("stop");

        Assert.Equal(0, run.Exit);
        Assert.Contains("did not reach the container", run.Err, StringComparison.Ordinal);
        Assert.Single(Compose(world, "down"));
    }

    [Fact]
    public async Task Restart_StopsThenStarts()
    {
        using ScriptWorld world = World();
        RunningState(world);

        Assert.Equal(0, (await world.RunAsync("restart")).Exit);

        Assert.Single(Compose(world, "down"));
        Assert.Single(Compose(world, "up", "-d"));
    }

    [Fact]
    public async Task Kill_KillsTheContainer_ThenRemovesOrphans()
    {
        using ScriptWorld world = World();
        RunningState(world);

        Assert.Equal(0, (await world.RunAsync("kill")).Exit);

        Assert.Contains(world.Calls("docker/log"), c => c[0] == "kill" && c[1] == "cid0123456789abcdef");
        Assert.Single(Compose(world, "down", "--remove-orphans"));
    }

    [Fact]
    public async Task Kill_FallsBackToComposeKill_WhenDockerKillFails()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.Script("docker/fail-dockerkill", "1");

        Assert.Equal(0, (await world.RunAsync("kill")).Exit);

        Assert.Single(Compose(world, "kill"));
    }

    [Fact]
    public async Task Kill_Fails_WhenNeitherDockerNorComposeCanKill()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.Script("docker/fail-dockerkill", "1");
        world.Script("docker/fail-kill", "1");

        Assert.Equal(1, (await world.RunAsync("kill")).Exit);
    }

    // --- console ---

    [Fact]
    public async Task Input_GoesThroughTheCommandPipe_WhenTheContainerRuns()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.ServeCommandFifo();

        Assert.Equal(0, (await world.RunAsync("input", "say hi")).Exit);
        Assert.Equal(0, (await world.RunAsync("announce", "hello all")).Exit);
        Assert.Equal(0, (await world.RunAsync("kick", "Bob")).Exit);
        Assert.Equal(0, (await world.RunAsync("save")).Exit);

        await Eventually.Holds(
            () => world.Recorded("container-input").SequenceEqual(["say hi", "say hello all", "kick Bob", "save"]), "the entrypoint read every line");
    }

    [Fact]
    public async Task Input_RefusesWhenTheContainerIsNotRunning()
    {
        using ScriptWorld world = World();
        world.ServeCommandFifo();

        ScriptRun run = await world.RunAsync("input", "say hi");

        Assert.Equal(1, run.Exit);
        Assert.Contains("not running", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Input_RefusesWhenThereIsNoCommandPipe()
    {
        using ScriptWorld world = World();
        RunningState(world);

        ScriptRun run = await world.RunAsync("input", "say hi");

        Assert.Equal(1, run.Exit);
        Assert.Contains("command.fifo", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Input_StillRejectsWhatCouldTurnALineIntoSomethingElse()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.ServeCommandFifo();

        Assert.Equal(1, (await world.RunAsync("input", "say $(id)")).Exit);
    }

    [Fact]
    public async Task Attach_OpensAShellInTheComposeService()
    {
        using ScriptWorld world = World();
        RunningState(world);

        Assert.Equal(0, (await world.RunAsync("attach")).Exit);

        Assert.Equal(["svc", "/bin/sh"], Compose(world, "exec").Single()[3..].Skip(1).ToArray());
    }

    [Fact]
    public async Task Attach_RefusesWhenNothingRuns()
    {
        using ScriptWorld world = World();

        Assert.Equal(1, (await world.RunAsync("attach")).Exit);
    }

    // --- logs, download, deploy ---

    [Fact]
    public async Task Logs_AreComposes()
    {
        using ScriptWorld world = World();
        world.Script("docker/logs", "line a\nline b\n");

        ScriptRun run = await world.RunAsync("logs", "-n", "5");

        Assert.Equal("line a\nline b\n", run.Out);
        Assert.Single(Compose(world, "logs", "--tail=5"));
    }

    [Fact]
    public async Task Download_PullsTheImages_AndDeployPlacesNothing()
    {
        using ScriptWorld world = World();

        Assert.Equal(0, (await world.RunAsync("download")).Exit);
        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        Assert.Single(Compose(world, "pull"));
    }

    [Fact]
    public async Task Download_FailsWhenThePullFails()
    {
        using ScriptWorld world = World();
        world.Script("docker/fail-pull", "1");

        Assert.Equal(1, (await world.RunAsync("download")).Exit);
    }

    // --- versions ---

    [Fact]
    public async Task TheInstalledVersion_IsUnknown_Spelled_Unknown()
    {
        using ScriptWorld world = World();

        Assert.Equal("unknown\n", (await world.RunAsync("version")).Out);
    }

    [Fact]
    public async Task OneImage_GivesItsFullDigest_AsTheLatestVersion()
    {
        using ScriptWorld world = World();
        world.Script("docker/remote/example_img_latest", "sha256:aaaa\n");

        ScriptRun run = await world.RunAsync("version", "--latest");

        Assert.Equal("sha256:aaaa\n", run.Out);
        Assert.Equal(["buildx", "imagetools", "inspect", "example/img:latest"], world.Calls("docker/log").Single(c => c[0] == "buildx")[..4]);
    }

    [Fact]
    public async Task SeveralImages_GiveTheirSortedShortDigestsJoinedWithAPlus()
    {
        using ScriptWorld world = World();
        world.Script("docker/images", "b/img:1\na/img:1\n");
        world.Script("docker/remote/b_img_1", "sha256:" + new string('b', 64) + "\n");
        world.Script("docker/remote/a_img_1", "sha256:" + new string('c', 64) + "\n");

        ScriptRun run = await world.RunAsync("version", "--latest");

        Assert.Equal(new string('b', 12) + "+" + new string('c', 12) + "\n", run.Out);
    }

    [Fact]
    public async Task CheckUpdate_HasThreeOutcomes_WithTheRegistrysAnswerNeverGuessed()
    {
        using ScriptWorld world = World();
        world.Script("docker/remote/example_img_latest", "sha256:new\n");
        File.WriteAllText(world.VersionFile, "sha256:old\n");

        Assert.Equal("available sha256:new\n", (await world.RunAsync("check-update")).Out);

        File.WriteAllText(world.VersionFile, "sha256:new\n");
        Assert.Equal("current sha256:new\n", (await world.RunAsync("check-update")).Out);

        File.Delete(world.Fake("docker/remote/example_img_latest"));
        ScriptRun unknown = await world.RunAsync("check-update");
        Assert.Equal(1, unknown.Exit);
        Assert.Equal("unknown\n", unknown.Out);
    }

    [Fact]
    public async Task CheckUpdate_IsUnknown_WhenOnlySomeOfSeveralImagesAnswer()
    {
        // A partial reading is not a version: it would claim "up to date" on the strength of the images that answered.
        using ScriptWorld world = World();
        world.Script("docker/images", "a/img:1\nb/img:1\n");
        world.Script("docker/remote/a_img_1", "sha256:" + new string('a', 64) + "\n");

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
    }

    [Fact]
    public async Task CheckUpdate_IsUnknown_WhenComposeCannotResolveTheImages()
    {
        using ScriptWorld world = World();
        File.Delete(world.Fake("docker/images"));

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
    }

    // --- update ---

    [Fact]
    public async Task Update_TakesABackup_Pulls_CreatesTheContainers_AndRecordsThePulledDigest()
    {
        using ScriptWorld world = World();
        File.WriteAllText(Path.Combine(world.Saves, "w.sav"), "w");
        world.Script("docker/local/example_img_latest", "example/img@sha256:pulled\n");

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(0, run.Exit);
        Assert.Equal("updated sha256:pulled\n", run.Out);
        Assert.Equal("sha256:pulled\n", File.ReadAllText(world.VersionFile));
        Assert.Single(Compose(world, "pull"));
        Assert.Single(Compose(world, "create"));
        Assert.Empty(Compose(world, "up"));
        Backup backup = Assert.Single(Engine.Backups.BackupReader.List(world.BackupsDirectory).Backups);
        Assert.Equal(BackupReason.PreUpdate, backup.Reason);
    }

    [Fact]
    public async Task Update_OfARunningInstance_RecreatesItsContainers()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.Script("docker/local/example_img_latest", "example/img@sha256:pulled\n");
        File.WriteAllText(Path.Combine(world.Saves, "w.sav"), "w");

        Assert.Equal(0, (await world.RunAsync("update", "--run-state", "active")).Exit);

        Assert.Single(Compose(world, "up", "-d", "--force-recreate"));
    }

    [Fact]
    public async Task Update_ReportsItsPhases_ThroughTheEmitCommand()
    {
        using ScriptWorld world = World();
        world.Script("docker/local/example_img_latest", "example/img@sha256:pulled\n");
        File.WriteAllText(Path.Combine(world.Saves, "w.sav"), "w");
        FakeScripts.Install(world.Sandbox.Root, "emitter", $"#!/usr/bin/env bash\necho \"$1 $2\" >>\"{world.Fake("emitted")}\"\n");

        ScriptRun run = await world.RunAsync("update", "--emit-cmd", Path.Combine(world.Sandbox.Root, "emitter"));

        Assert.Equal(0, run.Exit);
        Assert.Equal(
            ["server.download.started g-1", "server.download.finished g-1", "server.deploy.started g-1", "server.deploy.finished g-1"],
            world.Recorded("emitted"));
    }

    [Fact]
    public async Task Update_FailsWhenThePullFails_ReportingDownloadFailed()
    {
        // A failed update reports download.failed and exits non-zero.
        using ScriptWorld world = World();
        File.WriteAllText(Path.Combine(world.Saves, "w.sav"), "w");
        world.Script("docker/fail-pull", "1");
        FakeScripts.Install(world.Sandbox.Root, "emitter", $"#!/usr/bin/env bash\necho \"$1 $2\" >>\"{world.Fake("emitted")}\"\n");

        ScriptRun run = await world.RunAsync("update", "--emit-cmd", Path.Combine(world.Sandbox.Root, "emitter"));

        Assert.NotEqual(0, run.Exit);
        Assert.Equal(["server.download.started g-1", "server.download.failed g-1"], world.Recorded("emitted"));
        Assert.False(File.Exists(world.VersionFile));
    }

    [Fact]
    public async Task Update_FailsWhenTheContainersCannotBeRecreated_ReportingDeployFailed()
    {
        using ScriptWorld world = World();
        File.WriteAllText(Path.Combine(world.Saves, "w.sav"), "w");
        world.Script("docker/fail-create", "1");
        FakeScripts.Install(world.Sandbox.Root, "emitter", $"#!/usr/bin/env bash\necho \"$1 $2\" >>\"{world.Fake("emitted")}\"\n");

        ScriptRun run = await world.RunAsync("update", "--emit-cmd", Path.Combine(world.Sandbox.Root, "emitter"));

        Assert.NotEqual(0, run.Exit);
        Assert.Contains("server.deploy.failed g-1", world.Recorded("emitted"));
    }

    [Fact]
    public async Task Update_RecordsNoVersion_WhenThePulledDigestCannotBeRead()
    {
        using ScriptWorld world = World();
        File.WriteAllText(Path.Combine(world.Saves, "w.sav"), "w");
        File.WriteAllText(world.VersionFile, "sha256:stale\n");

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(0, run.Exit);
        Assert.False(File.Exists(world.VersionFile), "a stale digest would read as a completed update");
        Assert.Equal("updated unknown\n", run.Out);
    }

    [Fact]
    public async Task Update_AbandonsTheUpdate_WhenTheBackupBeforeItFails()
    {
        using ScriptWorld world = World();
        // Nothing to back up: the working directory's install and saves are empty.

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(1, run.Exit);
        Assert.Empty(Compose(world, "pull"));
    }

    // --- status ---

    [Fact]
    public async Task Status_OfARunningContainer_ReportsTheRealHostPidFromDocker_NeverAHashOfItsId()
    {
        // The pid is the container process as the host sees it, measured by docker inspect and never derived from the container id.
        using ScriptWorld world = World();
        RunningState(world);
        world.Script("docker/inspect", "running 4242 2026-03-04T05:06:07.123456789Z\n");
        world.Script("docker/logs", "a\nb\nc\nd\n");

        ScriptRun run = await world.RunAsync("status", "--json", "--fast");

        ScriptStatus status = ScriptJson.Status(run.Out);
        Assert.True(status.Status);
        Assert.Equal(4242, status.Process.Pid);
        Assert.Equal("running", status.Process.Status);
        Assert.Equal("2026-03-04T05:06:07Z", status.Process.StartTime);
        Assert.Equal("container", status.Configuration.Runtime);
        Assert.Equal(["a", "b", "c", "d"], status.RecentLogs);
    }

    [Fact]
    public async Task TheTextStatus_OfARunningContainer_AddsItsIdAndWhatDockerMeasuresOfItsResources()
    {
        using ScriptWorld world = World();
        RunningState(world);
        world.Script("docker/inspect", "running 4242 2026-03-04T05:06:07Z\n");
        world.Script("docker/stats", "CPU: 3.2%, Memory: 1GiB / 8GiB (12.5%), PIDs: 41\n");

        ScriptRun run = await world.RunAsync("status", "--fast");

        Assert.Equal(0, run.Exit);
        Assert.Contains("Container ID: cid0123456789abcdef", run.Out, StringComparison.Ordinal);
        Assert.Contains("Resources: CPU: 3.2%, Memory: 1GiB / 8GiB (12.5%), PIDs: 41", run.Out, StringComparison.Ordinal);
        Assert.Contains("Process ID: 4242", run.Out, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Status_OfAStoppedContainer_HasNoProcess_AndReadsTheNewestRotatedLog()
    {
        using ScriptWorld world = World();
        Directory.CreateDirectory(world.Logs);
        File.WriteAllText(Path.Combine(world.Logs, "g-1.2026-02-01T00:00:00.log"), "old output\n");

        ScriptStatus status = ScriptJson.Status((await world.RunAsync("status", "--json", "--fast")).Out);

        Assert.False(status.Status);
        Assert.Null(status.Process.Pid);
        Assert.Equal(["old output"], status.RecentLogs);
    }

    [Fact]
    public async Task Status_Json_OfAContainer_CarriesTheSameThreeOutcomesAsANativeOne()
    {
        using ScriptWorld world = World();
        world.Script("docker/remote/example_img_latest", "sha256:new\n");
        File.WriteAllText(world.VersionFile, "sha256:old\n");

        ScriptStatus status = ScriptJson.Status((await world.RunAsync("status", "--json")).Out);

        Assert.True(status.Version.Checked);
        Assert.True(status.Version.UpdatesAvailable);
        Assert.Equal("sha256:new", status.Version.Latest);
    }
}
