using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

/// <summary>Start, stop and restart: who carries them out, what is recorded, and the firewall around them.</summary>
public class LifecycleTests
{
    private static LifecycleReport Report(CliRun run) =>
        JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.LifecycleReport) ?? throw new InvalidOperationException("null");

    private static ErrorReport Error(CliRun run) =>
        JsonSerializer.Deserialize(run.Err, EngineJsonContext.Default.ErrorReport) ?? throw new InvalidOperationException("null");

    private static void UseTheWatchdog(OpsFixture fx)
    {
        fx.Session.Watchdog.SocketPresent = true;
        fx.Session.Watchdog.OnStart = id =>
        {
            InstanceDescription instance = fx.Find(id);
            int pid = fx.Script.Run(id, instance.WorkingDirectory);
            fx.Session.Watchdog.Tracked[id] = FakeWatchdog.State(id, populated: true, pid);
        };
        fx.Session.Watchdog.OnStop = id =>
        {
            fx.Session.Watchdog.Tracked[id] = FakeWatchdog.State(id, populated: false, phase: "stopped");
            File.Delete(new InstanceLayout(fx.Find(id).WorkingDirectory, id).PidFile);
        };
    }

    // --- start ---

    [Fact]
    public async Task Start_WithoutAWatchdog_RunsTheScript_AndSaysTheInstanceIsUnsupervised()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal(0, run.Exit);
        LifecycleReport report = Report(run);
        Assert.Equal("script", report.Via);
        Assert.False(report.Supervised);
        Assert.Equal(RunState.Running, report.State);
        Assert.True(report.Changed);
        Assert.Equal(["g-1 start -d"], fx.Script.Calls);
        Assert.Equal(["server.start.started", "server.started", "server.start.finished"], fx.Events());
    }

    [Fact]
    public async Task Start_TextSaysUnsupervised()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "start", "g-1");

        Assert.Equal("g-1 started (unsupervised)\n", run.Out);
    }

    [Fact]
    public async Task Start_OfARunningInstance_ChangesNothing_AndWritesNoFact()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal(0, run.Exit);
        Assert.False(Report(run).Changed);
        Assert.Empty(fx.Script.Calls);
        Assert.Equal(["server.start.started", "server.start.finished"], fx.Events());
    }

    [Fact]
    public async Task Start_ThroughTheReadyWatchdog_AsksItWithTheOrigin_AndNeverRunsTheScript()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        UseTheWatchdog(fx);

        CliRun run = await fx.Run("--origin", "ui", "instance", "start", "g-1", "--force", "--json");

        Assert.Equal(0, run.Exit);
        LifecycleReport report = Report(run);
        Assert.Equal("watchdog", report.Via);
        Assert.True(report.Supervised);
        Assert.Equal(["start g-1 --force"], fx.Session.Watchdog.Actions);
        Assert.Equal(["ui"], fx.Session.Watchdog.Origins);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Start_WhenTheWatchdogHasNoRoom_ExitsFiftyOne_AndWritesNoFact()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        UseTheWatchdog(fx);
        fx.Session.Watchdog.StartResult = new ActionResult("", false, "11 GiB needed, 2 GiB free", ActionRefusal.NoRoom);

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal(51, run.Exit);
        Assert.Equal(ErrorCodes.InsufficientMemory, Error(run).Code);
        Assert.Equal(["server.start.started", "server.start.finished"], fx.Events());
    }

    [Fact]
    public async Task Start_WhenTheWatchdogDoesNotAnswerHealth_FallsBackToTheScript()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Session.Watchdog.SocketPresent = true;
        fx.Session.Watchdog.Health = new Watchdog.Client.WatchdogHealth(false, false, "connection refused");

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal("script", Report(run).Via);
        Assert.Empty(fx.Session.Watchdog.Actions);
    }

    [Fact]
    public async Task Start_WhenTheWatchdogIsNotReady_FallsBackToTheScript()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Session.Watchdog.SocketPresent = true;
        fx.Session.Watchdog.Health = new Watchdog.Client.WatchdogHealth(true, false, "not in its slice");

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal("script", Report(run).Via);
    }

    [Fact]
    public async Task Start_OfAContainer_AlwaysGoesThroughItsScript_EvenWithAReadyWatchdog()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance("c-1", "vrising", shape: c => c with { Runtime = BlueprintRuntime.Container });
        File.WriteAllText(instance.Layout.ComposeFile, "services: {}\n");
        UseTheWatchdog(fx);
        fx.Session.Containers.Answer = Engine.Status.ComposeAnswer.Of([]);
        Func<ProcessCall, ProcessResult> inner = fx.Session.Processes.Handler;
        fx.Session.Processes.Handler = call =>
        {
            if (call.Arguments[0] == "start")
                fx.Session.Containers.Answer = Engine.Status.ComposeAnswer.Of([new Engine.Status.ComposeService("c-1", "running")]);
            return inner(call);
        };

        CliRun run = await fx.Run("instance", "start", "c-1", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["c-1 start -d"], fx.Script.Calls);
        Assert.Empty(fx.Session.Watchdog.Actions);
    }

    [Fact]
    public async Task Start_OfAnInstanceThatNeverComesUp_Fails_AndWritesNoFact()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Script.StartsTheProcess = false;

        CliRun run = await fx.Run("instance", "start", "g-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("is not running", run.Err, StringComparison.Ordinal);
        Assert.DoesNotContain("server.started", fx.Events());
        Assert.Equal("server.start.finished", fx.Events()[^1]);
    }

    [Fact]
    public async Task Start_OfAnInstanceInAnOfflineLibrary_IsRefused()
    {
        var fx = OpsFixture.Create();
        var away = fx.Sandbox.AddLibrary("away");
        fx.AddInstance("g-1", library: away);
        Directory.Delete(away.Path, recursive: true);

        CliRun run = await fx.Run("instance", "start", "g-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("offline", run.Err, StringComparison.Ordinal);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Start_OfAnInstanceATransferHolds_ExitsFiftyNine()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();
        TransferLock.Place(instance.Layout, "token-1", autostart: false);

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal(59, run.Exit);
        Assert.Equal(ErrorCodes.Locked, Error(run).Code);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Start_WhileAnotherCommandHoldsTheInstance_FailsFastWithBusy()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        using IDisposable held = new Engine.Locks.EngineLocks(fx.Sandbox.Paths).AcquireInstance("g-1");

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal(1, run.Exit);
        Assert.Equal("busy", Error(run).Code);
    }

    [Fact]
    public async Task AnInstanceIsFoundByItsDisplayName_AndAnAmbiguousOneIsRefused()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance("g-1", shape: c => c with { DisplayName = "Alpha" });
        fx.AddInstance("g-2", shape: c => c with { DisplayName = "Beta" });
        fx.AddInstance("g-3", shape: c => c with { DisplayName = "Beta" });

        CliRun byName = await fx.Run("instance", "start", "Alpha");
        CliRun ambiguous = await fx.Run("instance", "start", "Beta");

        Assert.Equal(0, byName.Exit);
        Assert.Equal(1, ambiguous.Exit);
        Assert.Contains("g-2", ambiguous.Err, StringComparison.Ordinal);
    }

    // --- the firewall ---

    private static OpsFixture WithFirewall(string ports = "34197/udp|27015:27020/tcp")
    {
        var fx = OpsFixture.Create();
        fx.AddInstance(shape: c => c with { EnableFirewallManagement = true, Ports = ports });
        return fx;
    }

    [Fact]
    public async Task Start_OpensThePorts_BeforeTheInstanceStarts()
    {
        var fx = WithFirewall();

        CliRun run = await fx.Run("instance", "start", "g-1");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["ensure-open g-1 34197/udp 27015:27020/tcp"], fx.Session.Firewall.Calls);
    }

    [Fact]
    public async Task Start_WithAnUnreachableAuthority_ExitsFortyNine_AndDoesNotStart()
    {
        var fx = WithFirewall();
        fx.Session.Firewall.Verdict = new FirewallVerdict(false, true, "no socket");

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal(49, run.Exit);
        Assert.Equal(ErrorCodes.FirewallUnreachable, Error(run).Code);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Start_WithAnAuthorityThatRejectsTheRule_ExitsNineteen()
    {
        var fx = WithFirewall();
        fx.Session.Firewall.Verdict = new FirewallVerdict(false, false, "ufw said no");

        CliRun run = await fx.Run("instance", "start", "g-1", "--json");

        Assert.Equal(19, run.Exit);
        Assert.Equal(ErrorCodes.FirewallFailed, Error(run).Code);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Start_WithFirewallManagementOff_NeverAsksTheAuthority()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance(shape: c => c with { Ports = "7777/tcp" });

        await fx.Run("instance", "start", "g-1");

        Assert.Empty(fx.Session.Firewall.Calls);
    }

    [Fact]
    public async Task Stop_ClosesThePorts_AfterTheInstanceStopped()
    {
        var fx = WithFirewall();
        await fx.Run("instance", "start", "g-1");

        CliRun run = await fx.Run("instance", "stop", "g-1");

        Assert.Equal(0, run.Exit);
        Assert.Equal("remove g-1", fx.Session.Firewall.Calls[^1]);
    }

    [Fact]
    public async Task Stop_WhoseFirewallRemovalIsRefused_ReportsItAfterTheInstanceIsDown()
    {
        var fx = WithFirewall();
        await fx.Run("instance", "start", "g-1");
        fx.Session.Firewall.Verdict = new FirewallVerdict(false, true, "gone");

        CliRun run = await fx.Run("instance", "stop", "g-1");

        Assert.Equal(49, run.Exit);
        Assert.Contains("\"state\":\"stopped\"", (await fx.Run("instance", "status", "g-1", "--json")).Out, StringComparison.Ordinal);
    }

    // --- stop ---

    [Fact]
    public async Task Stop_OfAScriptStartedInstance_RunsTheScript_AndWritesTheFactOnlyForARealTransition()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        await fx.Run("instance", "start", "g-1");

        CliRun first = await fx.Run("instance", "stop", "g-1", "--json");
        CliRun second = await fx.Run("instance", "stop", "g-1", "--json");

        Assert.True(Report(first).Changed);
        Assert.False(Report(second).Changed);
        Assert.Equal(1, fx.Events().Count(e => e == "server.stopped"));
        Assert.Equal(2, fx.Events().Count(e => e == "server.stop.finished"));
        Assert.Equal("script", Report(first).Via);
        Assert.Equal(["g-1 start -d", "g-1 stop"], fx.Script.Calls);
    }

    [Fact]
    public async Task Stop_OfAnInstanceTheWatchdogSupervises_GoesThroughTheWatchdog()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        UseTheWatchdog(fx);
        await fx.Run("--origin", "api", "instance", "start", "g-1");

        CliRun run = await fx.Run("--origin", "api", "instance", "stop", "g-1", "--json");

        Assert.Equal("watchdog", Report(run).Via);
        Assert.Equal(["start g-1", "stop g-1"], fx.Session.Watchdog.Actions);
        Assert.Equal(["api", "api"], fx.Session.Watchdog.Origins);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Stop_OfAnInstanceTheWatchdogDoesNotTrack_GoesThroughTheScript_EvenWithAReadyWatchdog()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        UseTheWatchdog(fx);
        fx.Simulate("g-1", wd);

        CliRun run = await fx.Run("instance", "stop", "g-1", "--json");

        Assert.Equal("script", Report(run).Via);
        Assert.Equal(["g-1 stop"], fx.Script.Calls);
        Assert.Empty(fx.Session.Watchdog.Actions);
    }

    [Fact]
    public async Task Stop_OfAnInstanceThatStaysRunning_Fails()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);
        fx.Script.Failures["stop"] = "did not stop";

        CliRun run = await fx.Run("instance", "stop", "g-1");

        Assert.Equal(1, run.Exit);
        Assert.DoesNotContain("server.stopped", fx.Events());
        Assert.Equal("server.stop.finished", fx.Events()[^1]);
    }

    [Fact]
    public async Task Stop_IsNotRefusedByATransferLock_ASafeInstanceMayAlwaysBeStopped()
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);
        TransferLock.Place(instance.Layout, "token-1", autostart: false);

        CliRun run = await fx.Run("instance", "stop", "g-1");

        Assert.Equal(0, run.Exit);
    }

    // --- restart ---

    [Fact]
    public async Task Restart_WritesItsBracket_WithTheMiddleBetweenStopAndStart()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);

        CliRun run = await fx.Run("instance", "restart", "g-1");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["g-1 stop", "g-1 start -d"], fx.Script.Calls);
        Assert.Equal(["server.restart.started", "server.restart.stopped", "server.restarted", "server.restart.finished"], fx.Events());
    }

    [Fact]
    public async Task Restart_OfAStoppedInstance_JustStartsIt_WithoutAMiddle()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        await fx.Run("instance", "restart", "g-1");

        Assert.Equal(["server.restart.started", "server.restarted", "server.restart.finished"], fx.Events());
    }

    [Fact]
    public async Task Restart_ThatFailsToStart_StillClosesItsBracket_WithoutTheFact()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);
        fx.Script.Failures["start"] = "port in use";

        CliRun run = await fx.Run("instance", "restart", "g-1");

        Assert.Equal(1, run.Exit);
        Assert.Equal(["server.restart.started", "server.restart.stopped", "server.restart.finished"], fx.Events());
    }
}
