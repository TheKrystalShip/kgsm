using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

/// <summary><c>kgsm instance config set</c>.</summary>
public class ConfigSetTests
{
    private static ErrorReport Error(CliRun run) =>
        JsonSerializer.Deserialize(run.Err, EngineJsonContext.Default.ErrorReport) ?? throw new InvalidOperationException("null");

    [Fact]
    public async Task Set_ChangesTheKey_WritesTheFileWhole_AndJournalsTheKeyAndNeverTheValue()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "config", "set", "g-1", "rconPassword", "hunter2-secret");

        Assert.Equal(0, run.Exit);
        Assert.Equal("hunter2-secret", fx.Find("g-1").Config!.RconPassword);
        Assert.Equal(["config.changed"], fx.Events());
        string line = fx.JournalText().Single();
        Assert.Contains("\"Key\":\"rconPassword\"", line, StringComparison.Ordinal);
        Assert.DoesNotContain("hunter2-secret", line, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Set_AValueTheKeyAlreadyHolds_ChangesNothing_AndWritesNoEvent()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "config", "set", "g-1", "levelName", "world one", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Contains("\"changed\":false", run.Out, StringComparison.Ordinal);
        Assert.Empty(fx.Events());
    }

    [Theory]
    [InlineData("name")]
    [InlineData("blueprint")]
    [InlineData("runtime")]
    [InlineData("platform")]
    [InlineData("installNonce")]
    [InlineData("backupsDirectory")]
    [InlineData("steamAppId")]
    [InlineData("ports")]
    [InlineData("executableFile")]
    [InlineData("enableFirewallManagement")]
    [InlineData("maintenanceWindowsAuthor")]
    public async Task Set_RefusesAProtectedKey(string key)
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "config", "set", "g-1", key, "x");

        Assert.Equal(1, run.Exit);
        Assert.Contains("protected", run.Err, StringComparison.Ordinal);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Set_OfAKeyThatDoesNotExist_IsNotFound()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "config", "set", "g-1", "bogus", "x");

        Assert.Equal(25, run.Exit);
    }

    [Theory]
    [InlineData("crashRestart", "maybe")]
    [InlineData("crashMaxRestarts", "-1")]
    [InlineData("crashMaxRestarts", "many")]
    [InlineData("backupRetention", "0")]
    [InlineData("cpuPriority", "ludicrous")]
    [InlineData("timezone", "Mars/Olympus")]
    [InlineData("rconPort", "70000")]
    [InlineData("announceLeadMinutes", "15,soon")]
    [InlineData("levelName", "two\nlines")]
    [InlineData("executableArguments", "--name {nobodyKnowsThis}")]
    [InlineData("executableArguments", "--name {open")]
    [InlineData("maintenanceWindows", "whenever")]
    public async Task Set_RefusesAValueThatIsNotWhatTheKeyMeans_AndChangesNothing(string key, string value)
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        string before = File.ReadAllText(fx.Find("g-1").Layout.ConfigFile);

        CliRun run = await fx.Run("instance", "config", "set", "g-1", key, value);

        Assert.Equal(1, run.Exit);
        Assert.Equal(before, File.ReadAllText(fx.Find("g-1").Layout.ConfigFile));
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Set_ParsesEachTypeFromItsText()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        await fx.Run("instance", "config", "set", "g-1", "crashRestart", "FALSE");
        await fx.Run("instance", "config", "set", "g-1", "memoryCapMb", "4096");
        await fx.Run("instance", "config", "set", "g-1", "rconPort", "25575");
        await fx.Run("instance", "config", "set", "g-1", "cpuPriority", "high");
        await fx.Run("instance", "config", "set", "g-1", "timezone", "Europe/Madrid");
        await fx.Run("instance", "config", "set", "g-1", "executableArguments", "--save {savesDir}/{levelName} {{literal}}");

        InstanceConfig config = fx.Find("g-1").Config!;
        Assert.False(config.CrashRestart);
        Assert.Equal(4096, config.MemoryCapMb);
        Assert.Equal(25575, config.RconPort);
        Assert.Equal("high", config.CpuPriority);
        Assert.Equal("Europe/Madrid", config.Timezone);
        Assert.Equal("--save {savesDir}/{levelName} {{literal}}", config.ExecutableArguments);
    }

    [Fact]
    public async Task Set_OfAnEmptyRconPort_ClearsIt()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance(shape: c => c with { RconPort = 25575 });

        await fx.Run("instance", "config", "set", "g-1", "rconPort", "");

        Assert.Null(fx.Find("g-1").Config!.RconPort);
    }

    [Fact]
    public async Task Set_OfTheDisplayName_NormalizesIt_AndWritesTheRenameAsWell()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        await fx.Run("instance", "config", "set", "g-1", "displayName", "  Pretty\tName  ");

        Assert.Equal("PrettyName", fx.Find("g-1").Config!.DisplayName);
        Assert.Equal(["config.changed", "server.renamed"], fx.Events());
        string renamed = fx.JournalText()[1];
        Assert.Contains("\"OldDisplayName\":\"g-1\"", renamed, StringComparison.Ordinal);
        Assert.Contains("\"NewDisplayName\":\"PrettyName\"", renamed, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Set_OfMaintenanceWindows_StoresTheCanonicalForm_AndRecordsWhoWroteThem()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "config", "set", "g-1", "maintenanceWindows", "daily@05:00/restart,backup",
            "--author", "discord:haru", "--author-name", "Haru");

        Assert.Equal(0, run.Exit);
        InstanceConfig config = fx.Find("g-1").Config!;
        Assert.Equal("daily@05:00/backup,restart", config.MaintenanceWindows);
        Assert.Equal("discord:haru", config.MaintenanceWindowsAuthor);
        Assert.Equal("Haru", config.MaintenanceWindowsAuthorName);

        await fx.Run("instance", "config", "set", "g-1", "maintenanceWindows", "daily@06:00/backup");
        InstanceConfig cleared = fx.Find("g-1").Config!;
        Assert.Null(cleared.MaintenanceWindowsAuthor);
        Assert.Null(cleared.MaintenanceWindowsAuthorName);
    }

    [Fact]
    public async Task Set_RefusesAnAuthorOnAnyOtherKey_AndAnAuthorThatIsNotAnActor()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun other = await fx.Run("instance", "config", "set", "g-1", "levelName", "x", "--author", "discord:haru");
        CliRun malformed = await fx.Run("instance", "config", "set", "g-1", "maintenanceWindows", "daily@05:00/backup", "--author", "haru");

        Assert.Equal(1, other.Exit);
        Assert.Equal(1, malformed.Exit);
    }

    [Fact]
    public async Task Set_OnALockedInstance_ExitsFiftyNine()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();
        File.WriteAllText(instance.Layout.TransferLockFile, "t");

        CliRun run = await fx.Run("instance", "config", "set", "g-1", "levelName", "x", "--json");

        Assert.Equal(59, run.Exit);
        Assert.Equal(ErrorCodes.Locked, Error(run).Code);
    }
}

/// <summary><c>kgsm instance console</c>.</summary>
public class ConsoleTests
{
    private static OpsFixture Running(Func<InstanceConfig, InstanceConfig>? shape = null)
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance(shape: c => (shape ?? (x => x))(c with
        {
            BroadcastCommand = "say {message}",
            KickCommand = "kick {name}",
            BanCommand = "ban {id}",
            UnbanCommand = "unban {ip}",
        }));
        fx.Simulate("g-1", wd);
        return fx;
    }

    [Fact]
    public async Task Send_HandsTheLineToTheScript_AndJournalsIt()
    {
        var fx = Running();

        CliRun run = await fx.Run("instance", "console", "send", "g-1", "list", "players");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["g-1 input list players"], fx.Script.Calls);
        Assert.Equal(["console.input.sent"], fx.Events());
        Assert.Contains("\"Command\":\"list players\"", fx.JournalText().Single(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Send_ToAStoppedInstance_IsRefused_AndNothingIsSentOrJournaled()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "console", "send", "g-1", "list");

        Assert.Equal(1, run.Exit);
        Assert.Contains("needs a running instance", run.Err, StringComparison.Ordinal);
        Assert.Empty(fx.Script.Calls);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Send_WhoseScriptRefusesTheLine_IsAnInvalidArgument_AndWritesNoEvent()
    {
        var fx = Running();
        fx.Session.Processes.Handler = _ => new ProcessResult(8, string.Empty, "[ERROR] The command holds a character that is not allowed\n");

        CliRun run = await fx.Run("instance", "console", "send", "g-1", "rm -rf /; echo");

        Assert.Equal(1, run.Exit);
        Assert.Contains("not allowed", run.Err, StringComparison.Ordinal);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Announce_ResolvesTheBroadcastTemplate_ForTheJournal()
    {
        var fx = Running();

        CliRun run = await fx.Run("instance", "console", "announce", "g-1", "restart", "in", "5");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["g-1 announce restart in 5"], fx.Script.Calls);
        string line = fx.JournalText().Single();
        Assert.Contains("\"Message\":\"restart in 5\"", line, StringComparison.Ordinal);
        Assert.Contains("\"Command\":\"say restart in 5\"", line, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Announce_WithoutABroadcastTemplate_OrAPlaceholder_OrOverTheLimit_IsRefused()
    {
        var none = Running(c => c with { BroadcastCommand = string.Empty });
        var bare = Running(c => c with { BroadcastCommand = "say" });
        var fx = Running();

        CliRun noTemplate = await none.Run("instance", "console", "announce", "g-1", "hi");
        CliRun noPlaceholder = await bare.Run("instance", "console", "announce", "g-1", "hi");
        CliRun tooLong = await fx.Run("instance", "console", "announce", "g-1", new string('x', 1001));

        Assert.Contains("no broadcast command", noTemplate.Err, StringComparison.Ordinal);
        Assert.Contains("{message}", noPlaceholder.Err, StringComparison.Ordinal);
        Assert.Contains("longer than 1000", tooLong.Err, StringComparison.Ordinal);
        Assert.All(new[] { none, bare, fx }, f => Assert.Empty(f.Script.Calls));
    }

    [Theory]
    [InlineData("kick", "kick {name}", "player.kicked", "kick Steve")]
    [InlineData("ban", "ban {id}", "player.banned", "ban Steve")]
    [InlineData("unban", "unban {ip}", "player.unbanned", "unban Steve")]
    public async Task Moderation_ResolvesItsTemplate_AndJournalsTargetAndCommand(string verb, string template, string eventType, string command)
    {
        var fx = Running();
        _ = template;

        CliRun run = await fx.Run("instance", "console", verb, "g-1", "Steve");

        Assert.Equal(0, run.Exit);
        Assert.Equal([eventType], fx.Events());
        string line = fx.JournalText().Single();
        Assert.Contains("\"Target\":\"Steve\"", line, StringComparison.Ordinal);
        Assert.Contains($"\"Command\":\"{command}\"", line, StringComparison.Ordinal);
        Assert.Equal([$"g-1 {verb} Steve"], fx.Script.Calls);
    }

    [Fact]
    public async Task Moderation_ShortOfATemplateOrWithALineBreakInTheTarget_IsRefused()
    {
        var none = Running(c => c with { KickCommand = string.Empty });
        var fx = Running();

        CliRun noTemplate = await none.Run("instance", "console", "kick", "g-1", "Steve");
        CliRun lineBreak = await fx.Run("instance", "console", "kick", "g-1", "Steve\nop Steve");

        Assert.Equal(1, noTemplate.Exit);
        Assert.Equal(1, lineBreak.Exit);
        Assert.Empty(none.Script.Calls);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Save_SendsTheSaveCommand_AndWritesNoEvent()
    {
        var fx = Running();

        CliRun run = await fx.Run("instance", "console", "save", "g-1");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["g-1 save"], fx.Script.Calls);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task AnInstanceWhoseRunStateCannotBeMeasured_IsNotAssumedRunning()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance("c-1", "vrising", shape: c => c with { Runtime = Contracts.Blueprints.BlueprintRuntime.Container, BroadcastCommand = "say {message}" });
        fx.Session.Containers.Answer = Engine.Status.ComposeAnswer.Unavailable("docker is not installed");

        CliRun run = await fx.Run("instance", "console", "announce", "c-1", "hi");

        Assert.Equal(1, run.Exit);
        Assert.Contains("cannot be measured", run.Err, StringComparison.Ordinal);
    }
}

/// <summary><c>kgsm backup</c>, write side.</summary>
public class BackupWriteTests
{
    private static BackupCreateReport Created(CliRun run) =>
        JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.BackupCreateReport) ?? throw new InvalidOperationException("null");

    [Fact]
    public async Task Create_BracketsTheRun_PassesTheRunStateReasonAndRetention_AndJournalsTheArchive()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("backup", "create", "g-1", "--reason", "incident", "--retention", "pinned", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal(["g-1 create-backup --run-state inactive --reason incident --retention pinned"], fx.Script.Calls);
        Assert.Equal(["backup.started", "backup.created", "backup.finished"], fx.Events());
        Backup backup = Created(run).Backup;
        Assert.Equal(BackupReason.Incident, backup.Reason);
        Assert.True(backup.IsPinned);
        Assert.Contains($"\"Source\":\"{backup.Id}\"", fx.JournalText()[1], StringComparison.Ordinal);
    }

    [Fact]
    public async Task Create_OfARunningInstance_TellsTheScriptItIsActive()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        fx.Simulate("g-1", wd);

        await fx.Run("backup", "create", "g-1");

        Assert.StartsWith("g-1 create-backup --run-state active", fx.Script.Calls.Single(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Create_ThatFails_ClosesTheBracket_WithoutAFact()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Script.Failures["create-backup"] = "no space left";

        CliRun run = await fx.Run("backup", "create", "g-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("no space left", run.Err, StringComparison.Ordinal);
        Assert.Equal(["backup.started", "backup.finished"], fx.Events());
    }

    [Fact]
    public async Task Create_RefusesAReasonOutsideTheClosedSet()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("backup", "create", "g-1", "--reason", "because");

        Assert.Equal(2, run.Exit);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Restore_WithoutYes_IsRefusedWithExitTwo()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        string id = fx.Script.WriteBackup(fx.Find("g-1").WorkingDirectory, "g-1", "manual");

        CliRun run = await fx.Run("backup", "restore", "g-1", id);

        Assert.Equal(2, run.Exit);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Restore_BracketsTheRun_JournalsTheSafetyBackup_AndTheRestore()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        string id = fx.Script.WriteBackup(wd, "g-1", "manual");

        CliRun run = await fx.Run("backup", "restore", "g-1", id, "--yes", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal([$"g-1 restore-backup {id} --run-state inactive"], fx.Script.Calls);
        Assert.Equal(["backup.restore.started", "backup.created", "backup.restored", "backup.restore.finished"], fx.Events());
        BackupRestoreReport report = JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.BackupRestoreReport)!;
        Assert.Equal(id, report.Restored);
        Assert.NotNull(report.SafetyBackup);
    }

    [Fact]
    public async Task Restore_OverARunningInstance_ExitsFiftySeven()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();
        string id = fx.Script.WriteBackup(wd, "g-1", "manual");
        fx.Simulate("g-1", wd);

        CliRun run = await fx.Run("backup", "restore", "g-1", id, "--yes");

        Assert.Equal(57, run.Exit);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Restore_OfABackupThatDoesNotExist_IsNotFound_AndOfAPathIsInvalid()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun missing = await fx.Run("backup", "restore", "g-1", "g-1-nope", "--yes");
        CliRun path = await fx.Run("backup", "restore", "g-1", "../../etc", "--yes");

        Assert.Equal(25, missing.Exit);
        Assert.Equal(1, path.Exit);
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Delete_RemovesTheBackup_AndJournalsIt()
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance();
        string id = fx.Script.WriteBackup(wd, "g-1", "manual");

        CliRun refused = await fx.Run("backup", "delete", "g-1", id);
        CliRun run = await fx.Run("backup", "delete", "g-1", id, "--yes");

        Assert.Equal(2, refused.Exit);
        Assert.Equal(0, run.Exit);
        Assert.Empty(Backups.BackupReader.List(instance.Config!.BackupsDirectory).Backups);
        Assert.Equal(["backup.deleted"], fx.Events());
    }

    [Fact]
    public async Task Prune_KeepsTheNewestWindow_NeverDeletesAPinnedBackup_AndNeverLetsItTakeASlot()
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance();
        DateTimeOffset t0 = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        string pinned = fx.Script.WriteBackup(wd, "g-1", "manual", "pinned", t0);
        string oldest = fx.Script.WriteBackup(wd, "g-1", "manual", "prunable", t0.AddDays(1));
        string middle = fx.Script.WriteBackup(wd, "g-1", "manual", "prunable", t0.AddDays(2));
        string newest = fx.Script.WriteBackup(wd, "g-1", "manual", "prunable", t0.AddDays(3));

        CliRun run = await fx.Run("backup", "prune", "g-1", "--keep", "2", "--yes", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal([oldest], JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.BackupPruneReport)!.Deleted);
        Assert.Equal(
            new[] { newest, middle, pinned },
            Backups.BackupReader.List(instance.Config!.BackupsDirectory).Backups.Select(b => b.Id));
        string fact = fx.JournalText().Single();
        Assert.Contains("\"Deleted\":1", fact, StringComparison.Ordinal);
        Assert.Contains("\"Kept\":2", fact, StringComparison.Ordinal);
        Assert.Contains("\"Pinned\":1", fact, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Prune_NeverDeletesTheNewestPreUpdateBackup_AndItTakesNoSlot()
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance();
        DateTimeOffset t0 = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        string rollbackOld = fx.Script.WriteBackup(wd, "g-1", "pre-update", "prunable", t0);
        string rollback = fx.Script.WriteBackup(wd, "g-1", "pre-update", "prunable", t0.AddDays(1));
        string a = fx.Script.WriteBackup(wd, "g-1", "manual", "prunable", t0.AddDays(2));
        string b = fx.Script.WriteBackup(wd, "g-1", "manual", "prunable", t0.AddDays(3));
        string c = fx.Script.WriteBackup(wd, "g-1", "manual", "prunable", t0.AddDays(4));

        await fx.Run("backup", "prune", "g-1", "--keep", "2", "--yes");

        string[] left = [.. Backups.BackupReader.List(instance.Config!.BackupsDirectory).Backups.Select(x => x.Id)];
        Assert.Equal([c, b, rollback], left);
        Assert.DoesNotContain(a, left);
        Assert.DoesNotContain(rollbackOld, left);
    }

    [Fact]
    public async Task Prune_ThatDeletesNothing_WritesNoEvent_AndTakesTheInstancesRetentionByDefault()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance(shape: c => c with { BackupRetention = 5 });
        fx.Script.WriteBackup(wd, "g-1", "manual");

        CliRun run = await fx.Run("backup", "prune", "g-1", "--yes", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal(5, JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.BackupPruneReport)!.Kept);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Prune_RefusesAWindowBelowOne_AndNeedsYes()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun zero = await fx.Run("backup", "prune", "g-1", "--keep", "0", "--yes");
        CliRun unconfirmed = await fx.Run("backup", "prune", "g-1");

        Assert.Equal(1, zero.Exit);
        Assert.Equal(2, unconfirmed.Exit);
    }

    [Fact]
    public async Task PinAndUnpin_RewriteRetentionThroughTheScript_AndJournalIt()
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance();
        string id = fx.Script.WriteBackup(wd, "g-1", "manual");

        await fx.Run("backup", "pin", "g-1", id);
        Assert.True(Backups.BackupReader.Find(instance.Config!.BackupsDirectory, id)!.IsPinned);
        await fx.Run("backup", "unpin", "g-1", id);
        Assert.False(Backups.BackupReader.Find(instance.Config.BackupsDirectory, id)!.IsPinned);

        Assert.Equal(["backup.pinned", "backup.unpinned"], fx.Events());
    }

    [Theory]
    [InlineData("create")]
    [InlineData("prune")]
    public async Task EveryBackupChange_IsRefusedOnALockedInstance(string verb)
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();
        File.WriteAllText(instance.Layout.TransferLockFile, "t");

        CliRun run = await fx.Run("backup", verb, "g-1", "--yes");

        Assert.Equal(59, run.Exit);
    }

    [Theory]
    [InlineData("pin")]
    [InlineData("unpin")]
    [InlineData("delete")]
    [InlineData("restore")]
    public async Task EveryBackupChangeThatNamesABackup_IsRefusedOnALockedInstance(string verb)
    {
        var fx = OpsFixture.Create();
        var (instance, wd) = fx.AddInstance();
        string id = fx.Script.WriteBackup(wd, "g-1", "manual");
        File.WriteAllText(instance.Layout.TransferLockFile, "t");

        CliRun run = await fx.Run("backup", verb, "g-1", id, "--yes");

        Assert.Equal(59, run.Exit);
        Assert.Empty(fx.Script.Calls);
    }
}
