using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

/// <summary>Uninstall, update and update checks.</summary>
public class UninstallTests
{
    private static ErrorReport Error(CliRun run) =>
        JsonSerializer.Deserialize(run.Err, EngineJsonContext.Default.ErrorReport) ?? throw new InvalidOperationException("null");

    [Fact]
    public async Task Uninstall_WithoutATerminalAndWithoutYes_IsRefusedWithExitTwo_AndChangesNothing()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();

        CliRun run = await fx.Run("instance", "uninstall", "g-1");

        Assert.Equal(2, run.Exit);
        Assert.Contains("--yes", run.Err, StringComparison.Ordinal);
        Assert.True(Directory.Exists(instance.WorkingDirectory));
        Assert.True(fx.IsRegistered("g-1"));
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Uninstall_AtATerminal_AsksFirst_AndANoChangesNothing()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Session.Interactive = true;
        string? asked = null;
        fx.Session.Ask = question =>
        {
            asked = question;
            return false;
        };

        CliRun run = await fx.Run("instance", "uninstall", "g-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("g-1", asked, StringComparison.Ordinal);
        Assert.True(fx.IsRegistered("g-1"));
    }

    [Fact]
    public async Task Uninstall_RemovesTheFilesAndTheEntry_KeepsTheBackups_AndWritesItsBracket()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();
        Directory.CreateDirectory(fx.Backups("g-1"));
        File.WriteAllText(Path.Combine(fx.Backups("g-1"), "kept"), "x");

        CliRun run = await fx.Run("instance", "uninstall", "g-1", "--yes");

        Assert.Equal(0, run.Exit);
        Assert.False(Directory.Exists(instance.WorkingDirectory));
        Assert.False(fx.IsRegistered("g-1"));
        Assert.Equal([Path.Combine(fx.Main.Path, ".kgsm-library")], Directory.EnumerateFileSystemEntries(fx.Main.Path));
        Assert.True(File.Exists(Path.Combine(fx.Backups("g-1"), "kept")));
        Assert.Equal(["server.uninstall.started", "server.uninstalled", "server.uninstall.finished"], fx.Events());
        Assert.Contains("nonce-g-1", fx.JournalText().Single(l => l.Contains("server.uninstalled", StringComparison.Ordinal)), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Uninstall_WithPurge_AlsoDeletesTheBackups()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        Directory.CreateDirectory(fx.Backups("g-1"));

        await fx.Run("instance", "uninstall", "g-1", "--yes", "--purge-backups");

        Assert.False(Directory.Exists(fx.Backups("g-1")));
    }

    [Fact]
    public async Task Uninstall_StopsWhatRuns_BeforeAnyFileIsDeleted_ThroughTheScript()
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);
        string pidAtStop = string.Empty;
        Func<ProcessCall, ProcessResult> inner = fx.Session.Processes.Handler;
        fx.Session.Processes.Handler = call =>
        {
            if (call.Arguments[0] == "stop") pidAtStop = Directory.Exists(instance.WorkingDirectory) ? "files-still-there" : "files-gone";
            return inner(call);
        };

        CliRun run = await fx.Run("instance", "uninstall", "g-1", "--yes");

        Assert.Equal(0, run.Exit);
        Assert.Equal("files-still-there", pidAtStop);
        Assert.Equal(["server.uninstall.started", "server.stopped", "server.uninstalled", "server.uninstall.finished"], fx.Events());
    }

    [Fact]
    public async Task Uninstall_OfASupervisedInstance_StopsItThroughTheWatchdog_AndDropsItFromSupervision()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        fx.Session.Watchdog.SocketPresent = true;
        int pid = fx.Script.Run("g-1", wd);
        fx.Session.Watchdog.Tracked["g-1"] = FakeWatchdog.State("g-1", populated: true, pid);
        fx.Session.Watchdog.OnStop = id =>
        {
            fx.Session.Watchdog.Tracked[id] = FakeWatchdog.State(id, populated: false, phase: "stopped");
            File.Delete(new InstanceLayout(wd, id).PidFile);
        };

        CliRun run = await fx.Run("instance", "uninstall", "g-1", "--yes");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["stop g-1", "forget g-1"], fx.Session.Watchdog.Actions);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Uninstall_OfARunningContainer_StopsItThroughItsScript()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance("c-1", "vrising", shape: c => c with { Runtime = BlueprintRuntime.Container });
        File.WriteAllText(instance.Layout.ComposeFile, "services: {}\n");
        fx.Session.Containers.Answer = Engine.Status.ComposeAnswer.Of([new Engine.Status.ComposeService("c-1", "running")]);
        Func<ProcessCall, ProcessResult> inner = fx.Session.Processes.Handler;
        fx.Session.Processes.Handler = call =>
        {
            if (call.Arguments[0] == "stop") fx.Session.Containers.Answer = Engine.Status.ComposeAnswer.Of([]);
            return inner(call);
        };

        CliRun run = await fx.Run("instance", "uninstall", "c-1", "--yes");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["c-1 stop"], fx.Script.Calls);
        Assert.False(Directory.Exists(instance.WorkingDirectory));
    }

    [Fact]
    public async Task Uninstall_WhenTheInstanceWillNotStop_FailsWithTheBracketClosed_AndDeletesNothing()
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);
        fx.Script.Failures["stop"] = "stuck";

        CliRun run = await fx.Run("instance", "uninstall", "g-1", "--yes");

        Assert.Equal(1, run.Exit);
        Assert.True(Directory.Exists(instance.WorkingDirectory));
        Assert.True(fx.IsRegistered("g-1"));
        Assert.Equal(["server.uninstall.started", "server.uninstall.failed", "server.uninstall.finished"], fx.Events());
    }

    [Fact]
    public async Task Uninstall_OfAnInstanceWhoseRunStateIsUnknown_NeedsForce_AndDeletesNothingWithout()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance("c-1", "vrising", shape: c => c with { Runtime = BlueprintRuntime.Container });
        fx.Session.Containers.Answer = Engine.Status.ComposeAnswer.Unavailable("docker is not installed");

        CliRun refused = await fx.Run("instance", "uninstall", "c-1", "--yes");
        Assert.Equal(1, refused.Exit);
        Assert.True(Directory.Exists(instance.WorkingDirectory));

        CliRun forced = await fx.Run("instance", "uninstall", "c-1", "--yes", "--force");
        Assert.Equal(0, forced.Exit);
        Assert.False(Directory.Exists(instance.WorkingDirectory));
    }

    [Fact]
    public async Task Uninstall_OfAnInstanceInAnOfflineLibrary_NeedsForce_AndThenOnlyDeregisters()
    {
        var fx = OpsFixture.Create();
        var away = fx.Sandbox.AddLibrary("away");
        var (instance, _) = fx.AddInstance("g-1", library: away);
        string moved = away.Path + "-unplugged";
        Directory.Move(away.Path, moved);

        CliRun refused = await fx.Run("instance", "uninstall", "g-1", "--yes");
        CliRun forced = await fx.Run("instance", "uninstall", "g-1", "--yes", "--force");

        Assert.Equal(1, refused.Exit);
        Assert.Equal(0, forced.Exit);
        Assert.False(fx.IsRegistered("g-1"));
        Assert.True(Directory.Exists(Path.Combine(moved, "instances", "g", "g-1")));
        Assert.Equal(instance.WorkingDirectory.Replace(away.Path, moved, StringComparison.Ordinal), Path.Combine(moved, "instances", "g", "g-1"));
    }

    [Fact]
    public async Task Uninstall_OfAnInstanceATransferHolds_IsRefused_UnlessTheTransfersOwnTokenIsGiven()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();
        File.WriteAllText(instance.Layout.TransferLockFile, "token-1\n");

        CliRun other = await fx.Run("instance", "uninstall", "g-1", "--yes", "--transfer-token", "token-2", "--json");
        CliRun held = await fx.Run("instance", "uninstall", "g-1", "--yes", "--json");
        CliRun own = await fx.Run("instance", "uninstall", "g-1", "--yes", "--transfer-token", "token-1");

        Assert.Equal(59, other.Exit);
        Assert.Equal(59, held.Exit);
        Assert.Equal(ErrorCodes.Locked, Error(held).Code);
        Assert.Equal(0, own.Exit);
    }

    [Fact]
    public async Task Uninstall_ClosesTheFirewallRule_AndRefusesToDeleteWhenTheAuthorityIsUnreachable()
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance(shape: c => c with { EnableFirewallManagement = true, Ports = "7777/tcp" });
        fx.Simulate("g-1", wd);
        fx.Session.Firewall.Verdict = new FirewallVerdict(false, true, "no socket");

        CliRun refused = await fx.Run("instance", "uninstall", "g-1", "--yes");
        Assert.Equal(49, refused.Exit);
        Assert.True(Directory.Exists(instance.WorkingDirectory));

        fx.Session.Firewall.Verdict = FirewallVerdict.Success;
        CliRun run = await fx.Run("instance", "uninstall", "g-1", "--yes");
        Assert.Equal(0, run.Exit);
        Assert.Contains("remove g-1", fx.Session.Firewall.Calls);
    }

    [Fact]
    public async Task Uninstall_OfAnUnknownInstance_IsNotFound()
    {
        var fx = OpsFixture.Create();

        CliRun run = await fx.Run("instance", "uninstall", "nope", "--yes");

        Assert.Equal(25, run.Exit);
    }
}

public class UpdateTests
{
    private static UpdateReport Report(CliRun run) =>
        JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.UpdateReport) ?? throw new InvalidOperationException("null");

    private static UpdateCheckReport Check(CliRun run) =>
        JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.UpdateCheckReport) ?? throw new InvalidOperationException("null");

    [Fact]
    public async Task Update_HandsTheScriptTheRunStateAndTheCommandThatReportsItsPhases()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "update", "g-1", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["g-1 update --run-state inactive --emit-cmd /test/bin/kgsm event emit"], fx.Script.Calls);
        UpdateReport report = Report(run);
        Assert.Equal("updated", report.Outcome);
        Assert.Equal("1.0.0", report.PreviousVersion);
        Assert.Equal("2.0.0", report.Version);
    }

    [Fact]
    public async Task Update_BracketsTheRun_RecordsTheBackupTheScriptTook_AndTheVersionsItMoved()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "update", "g-1", "--json");

        Assert.Equal(["server.update.started", "backup.created", "server.updated", "server.update.finished"], fx.Events());
        string updated = fx.JournalText().Single(l => l.Contains("server.updated", StringComparison.Ordinal));
        Assert.Contains("\"OldVersion\":\"1.0.0\"", updated, StringComparison.Ordinal);
        Assert.Contains("\"NewVersion\":\"2.0.0\"", updated, StringComparison.Ordinal);
        Assert.NotNull(Report(run).Backup);
    }

    [Fact]
    public async Task Update_OfAnInstanceThatIsAlreadyCurrent_WritesNoUpdatedFact()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Script.UpdateOutput = "current 1.0.0";

        CliRun run = await fx.Run("instance", "update", "g-1", "--json");

        Assert.Equal("current", Report(run).Outcome);
        Assert.Equal(["server.update.started", "server.update.finished"], fx.Events());
    }

    [Fact]
    public async Task Update_OfARunningNativeInstance_ExitsFiftySeven_BeforeTheScriptRuns()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);

        CliRun run = await fx.Run("instance", "update", "g-1");

        Assert.Equal(57, run.Exit);
        Assert.Empty(fx.Script.Calls);
        Assert.Equal(["server.update.started", "server.update.failed", "server.update.finished"], fx.Events());
    }

    [Fact]
    public async Task Update_ThatFails_WritesFailedAndFinished_AndNoUpdatedFact()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Script.Failures["update"] = "Failed to download version 2.0.0";

        CliRun run = await fx.Run("instance", "update", "g-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("Failed to download", run.Err, StringComparison.Ordinal);
        Assert.Equal(["server.update.started", "server.update.failed", "server.update.finished"], fx.Events());
    }

    [Fact]
    public async Task Update_OfALockedInstance_ExitsFiftyNine()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();
        File.WriteAllText(instance.Layout.TransferLockFile, "t");

        CliRun run = await fx.Run("instance", "update", "g-1");

        Assert.Equal(59, run.Exit);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task CheckUpdate_ReportsAvailableCurrentAndUnknown_EachItsOwnResult()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        fx.Script.CheckOutput = "available 2.0.0";
        CliRun available = await fx.Run("instance", "check-update", "g-1", "--json");
        fx.Script.CheckOutput = "current 1.0.0";
        CliRun current = await fx.Run("instance", "check-update", "g-1", "--json");
        fx.Script.CheckOutput = "unknown";
        CliRun unknown = await fx.Run("instance", "check-update", "g-1", "--json");

        Assert.Equal(("available", "2.0.0", 0), (Check(available).Outcome, Check(available).Latest, available.Exit));
        Assert.Equal(("current", "1.0.0", 0), (Check(current).Outcome, Check(current).Latest, current.Exit));
        Assert.Equal(("unknown", null, 1), (Check(unknown).Outcome, Check(unknown).Latest, unknown.Exit));
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task CheckUpdate_WithEmit_RecordsTheLatestAndAnnouncesEachNewVersionOnce()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Script.CheckOutput = "available 2.0.0";

        CliRun first = await fx.Run("instance", "check-update", "g-1", "--emit", "--json");
        CliRun second = await fx.Run("instance", "check-update", "g-1", "--emit", "--json");
        fx.Script.CheckOutput = "available 3.0.0";
        CliRun third = await fx.Run("instance", "check-update", "g-1", "--emit", "--json");

        Assert.True(Check(first).Announced);
        Assert.False(Check(second).Announced);
        Assert.True(Check(third).Announced);
        Assert.Equal(["server.update.available", "server.update.available"], fx.Events());
        Assert.Contains("\"LatestVersion\":\"3.0.0\"", fx.JournalText()[^1], StringComparison.Ordinal);
        Assert.Contains("g-1 version --save-latest 2.0.0", fx.Script.Calls);
    }

    [Fact]
    public async Task CheckUpdate_WithEmit_ThatCannotReachUpstream_RecordsAndAnnouncesNothing()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Script.CheckOutput = "unknown";

        CliRun run = await fx.Run("instance", "check-update", "g-1", "--emit", "--json");

        Assert.Equal(1, run.Exit);
        Assert.Empty(fx.Events());
        Assert.DoesNotContain(fx.Script.Calls, c => c.Contains("--save-latest", StringComparison.Ordinal));
    }
}

public class MoveTests
{
    [Fact]
    public async Task Move_RenamesTheTreeWithinOneDevice_RewritesNoPath_AndWritesTheFact()
    {
        var fx = OpsFixture.Create();
        var other = fx.Sandbox.AddLibrary("other");
        var (instance, wd) = fx.AddInstance();
        File.WriteAllText(Path.Combine(wd, "saves", "world"), "data");
        string configBefore = File.ReadAllText(instance.Layout.ConfigFile);

        CliRun run = await fx.Run("instance", "move", "g-1", "other");

        Assert.Equal(0, run.Exit);
        InstanceDescription moved = fx.Find("g-1");
        Assert.Equal(Path.Combine(other.Path, "instances", "g", "g-1"), moved.WorkingDirectory);
        Assert.Equal("other", moved.Library!.Name);
        Assert.False(Directory.Exists(wd));
        Assert.Equal([Path.Combine(fx.Main.Path, ".kgsm-library")], Directory.EnumerateFileSystemEntries(fx.Main.Path));
        Assert.Equal("data", File.ReadAllText(Path.Combine(moved.WorkingDirectory, "saves", "world")));
        Assert.Equal(configBefore, File.ReadAllText(moved.Layout.ConfigFile));
        Assert.Equal(["server.moved"], fx.Events());
        string fact = fx.JournalText().Single();
        Assert.Contains("\"FromLibrary\":\"main\"", fact, StringComparison.Ordinal);
        Assert.Contains("\"ToLibrary\":\"other\"", fact, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Move_OfAnInstanceThatHasRun_StartsItOnceAtTheNewPlace_AndStopsItAgain()
    {
        var fx = OpsFixture.Create();
        fx.Sandbox.AddLibrary("other");
        var (_, wd) = fx.AddInstance();
        File.WriteAllText(Path.Combine(wd, "g-1.log"), "ran once");

        CliRun run = await fx.Run("instance", "move", "g-1", "other");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["g-1 start -d", "g-1 stop"], fx.Script.Calls);
        Assert.DoesNotContain("server.started", fx.Events());
        Assert.DoesNotContain("server.stopped", fx.Events());
    }

    [Fact]
    public async Task Move_OfAnInstanceThatNeverRan_DoesNotStartIt()
    {
        var fx = OpsFixture.Create();
        fx.Sandbox.AddLibrary("other");
        fx.AddInstance();

        await fx.Run("instance", "move", "g-1", "other");

        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Move_WhoseStartAtTheNewPlaceFails_PutsEverythingBack()
    {
        var fx = OpsFixture.Create();
        fx.Sandbox.AddLibrary("other");
        var (_, wd) = fx.AddInstance();
        File.WriteAllText(Path.Combine(wd, "g-1.log"), "ran once");
        File.WriteAllText(Path.Combine(wd, "saves", "world"), "data");
        fx.Script.Failures["start"] = "cannot start here";

        CliRun run = await fx.Run("instance", "move", "g-1", "other");

        Assert.Equal(1, run.Exit);
        InstanceDescription after = fx.Find("g-1");
        Assert.Equal(wd, after.WorkingDirectory);
        Assert.Equal("main", after.Library!.Name);
        Assert.Equal("data", File.ReadAllText(Path.Combine(wd, "saves", "world")));
        Assert.DoesNotContain("server.moved", fx.Events());
    }

    [Fact]
    public async Task Move_OfARunningInstance_ExitsFiftySeven_AndMovesNothing()
    {
        var fx = OpsFixture.Create();
        fx.Sandbox.AddLibrary("other");
        var (_, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);

        CliRun run = await fx.Run("instance", "move", "g-1", "other");

        Assert.Equal(57, run.Exit);
        Assert.True(Directory.Exists(wd));
    }

    [Fact]
    public async Task Move_RefusesTheSameLibrary_AnOfflineTarget_AnUnknownTarget_AndALockedInstance()
    {
        var fx = OpsFixture.Create();
        var away = fx.Sandbox.AddLibrary("away");
        var (instance, _) = fx.AddInstance();
        Directory.Delete(away.Path, recursive: true);

        CliRun same = await fx.Run("instance", "move", "g-1", "main");
        CliRun offline = await fx.Run("instance", "move", "g-1", "away");
        CliRun unknown = await fx.Run("instance", "move", "g-1", "nowhere");
        File.WriteAllText(instance.Layout.TransferLockFile, "t");
        fx.Sandbox.AddLibrary("other");
        CliRun locked = await fx.Run("instance", "move", "g-1", "other");

        Assert.Equal(1, same.Exit);
        Assert.Contains("already in", same.Err, StringComparison.Ordinal);
        Assert.Equal(1, offline.Exit);
        Assert.Contains("offline", offline.Err, StringComparison.Ordinal);
        Assert.Equal(25, unknown.Exit);
        Assert.Equal(59, locked.Exit);
    }

    [Fact]
    public async Task Move_OfAContainer_RendersItsComposeFileAgainstTheNewPlace()
    {
        var fx = OpsFixture.Create();
        var other = fx.Sandbox.AddLibrary("other");
        await fx.Run("instance", "install", "vrising", "--id", "v-1", "--library", "main");
        string oldDirectory = fx.Find("v-1").WorkingDirectory;

        CliRun run = await fx.Run("instance", "move", "v-1", "other");

        Assert.Equal(0, run.Exit);
        string compose = File.ReadAllText(fx.Find("v-1").Layout.ComposeFile);
        Assert.Contains(other.Path, compose, StringComparison.Ordinal);
        Assert.DoesNotContain(oldDirectory, compose, StringComparison.Ordinal);
    }

    [Fact]
    public async Task LibraryRemoveWithDrain_MovesEachInstanceOut_ThenDeregistersTheLibrary()
    {
        var fx = OpsFixture.Create();
        var other = fx.Sandbox.AddLibrary("other");
        fx.AddInstance("g-1");
        fx.AddInstance("g-2");

        CliRun run = await fx.Run("library", "remove", "main", "--drain", "other", "--yes", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["other"], new Libraries.LibraryCatalog(fx.Sandbox.Paths).Registered().Select(l => l.Name));
        Assert.All(new[] { "g-1", "g-2" }, id => Assert.Equal(other.Path, fx.Find(id).Library!.Path));
        Assert.Equal(["server.moved", "server.moved", "library.removed"], fx.Events());
    }
}
