using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Scripts;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Transfers;

/// <summary><c>transfer import finish</c>: the instance it builds, the checks it makes again, and the unwind of a failure.</summary>
public class TransferFinishTests
{
    private static async Task<(TransferWorld World, string ImportId, InstanceConfig SourceConfig, TransferManifest Manifest)> StagedNative(bool ran = true)
    {
        var world = TransferWorld.Create();
        (InstanceDescription source, _) = world.AddNative(ran: ran);
        (string importId, TransferManifest manifest) = await world.Stage();
        return (world, importId, source.Config!, manifest);
    }

    [Fact]
    public async Task Finish_RegistersTheInstanceUnderANewId_WithItsFilesRenamedAndItsConfigRewritten()
    {
        (TransferWorld world, string importId, InstanceConfig source, _) = await StagedNative();

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.NotEqual("fx-1", imported.Instance);
        Assert.StartsWith("factorio-", imported.Instance, StringComparison.Ordinal);
        Assert.Equal("factorio", imported.Blueprint);
        Assert.Equal("main", imported.Library);

        InstanceDescription instance = world.Target.Find(imported.Instance);
        Assert.Equal(Path.Combine(world.Target.Main.Path, "instances", "factorio", imported.Instance), instance.WorkingDirectory);
        InstanceConfig config = instance.Config!;
        Assert.Equal(imported.Instance, config.Name);
        Assert.Equal("factorio", config.Blueprint);
        Assert.NotEqual(source.InstallNonce, config.InstallNonce);
        Assert.Equal(world.Target.Backups(imported.Instance), config.BackupsDirectory);
        Assert.Equal(source.StopCommand, config.StopCommand);
        Assert.Equal(source.ExecutableArguments, config.ExecutableArguments);

        InstanceLayout layout = instance.Layout;
        Assert.True(File.Exists(layout.ConfigFile));
        Assert.True(File.Exists(layout.ManagementScript));
        Assert.Equal("1.0.0\n", File.ReadAllText(layout.VersionFile));
        Assert.Equal("1.0.0\n", File.ReadAllText(layout.LatestVersionFile));
        Assert.Equal("started\n", File.ReadAllText(layout.LogFile));
        Assert.Equal("the world", File.ReadAllText(Path.Combine(layout.SavesDirectory, "world.zip")));
        Assert.Empty(Directory.EnumerateFiles(instance.WorkingDirectory, "fx-1*", SearchOption.TopDirectoryOnly));
        Assert.Empty(Directory.EnumerateFiles(instance.WorkingDirectory, ".fx-1*", SearchOption.TopDirectoryOnly));
    }

    [Fact]
    public async Task Finish_RewritesNoPath_TheInstanceHoldsOnlyItsOwnBackupsDirectory()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        InstanceDescription instance = world.Target.Find(imported.Instance);
        string text = File.ReadAllText(instance.Layout.ConfigFile) + File.ReadAllText(instance.Layout.ManagementScript);
        Assert.DoesNotContain(world.Source.Sandbox.Root, text, StringComparison.Ordinal);
        Assert.DoesNotContain("fx-1", text, StringComparison.Ordinal);
        Assert.Contains(instance.Config!.BackupsDirectory, text, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Finish_RegeneratesTheScript_FromTheTemplateAndTheGamesHooks()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        world.Target.Sandbox.WriteFile(Path.Combine(world.Target.Sandbox.Paths.SystemOverridesDirectory, "factorio", "hooks.sh"), "kgsm_hook_latest_version() { echo 3; }\n");

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        InstanceDescription instance = world.Target.Find(imported.Instance);
        ScriptHeader header = ScriptHeader.Parse(File.ReadAllText(instance.Layout.ManagementScript))!;
        Assert.Equal(ScriptTemplate.Version, header.TemplateVersion);
        Assert.Equal(HookFiles.Find(world.Target.Sandbox.Paths, "factorio")!.Digest, header.HooksDigest);
        Assert.Null(world.Target.Session.Processes.Calls.FirstOrDefault(c => c.FileName.EndsWith("fx-1.manage.sh", StringComparison.Ordinal)));
    }

    [Fact]
    public async Task Finish_MovesTheBackupsIntoADirectoryOfItsOwn_AndTheSourceIsUntouched()
    {
        (TransferWorld world, string importId, InstanceConfig source, _) = await StagedNative();

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        string backups = world.Target.Find(imported.Instance).Config!.BackupsDirectory;
        Assert.Single(Directory.EnumerateDirectories(backups));
        Assert.True(File.Exists(Directory.EnumerateDirectories(backups).Single() + "/manifest.json"));
        Assert.True(world.Source.IsRegistered("fx-1"));
        Assert.Single(Directory.EnumerateDirectories(source.BackupsDirectory));
    }

    [Fact]
    public async Task Finish_OfAnInstanceThatHadRun_StartsItOnceAtItsNewPlaceAndStopsItAgain_WritingOnlyTheFact()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative(ran: true);

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.Equal([$"{imported.Instance} start -d", $"{imported.Instance} stop"], world.Target.Script.Calls);
        Assert.Equal(["server.imported"], world.Target.Events());
        Assert.False(File.Exists(world.Target.Find(imported.Instance).Layout.PidFile));
    }

    [Fact]
    public async Task Finish_OfAnInstanceThatNeverRan_DoesNotStartIt()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative(ran: false);

        world.Imported(await world.Finish(importId));

        Assert.Empty(world.Target.Script.Calls);
    }

    [Fact]
    public async Task Finish_TakesTheFirewallAndPortForwardingSettingsFromTheHost_NotTheSource()
    {
        var world = TransferWorld.Create();
        world.AddNative(shape: c => c with { EnableFirewallManagement = true, EnablePortForwarding = true });
        world.Target.Session.Extra["Instances__EnableFirewallManagement"] = "false";
        world.Target.Session.Extra["Instances__EnablePortForwarding"] = "false";
        (string importId, _) = await world.Stage();

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        InstanceConfig config = world.Target.Find(imported.Instance).Config!;
        Assert.False(config.EnableFirewallManagement);
        Assert.False(config.EnablePortForwarding);
        Assert.Empty(world.Target.Session.Firewall.Calls);
    }

    [Fact]
    public async Task Finish_OpensTheHostsFirewall_WhenTheHostManagesIt_ForTheProofStart()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        world.Target.Session.Extra["Instances__EnableFirewallManagement"] = "true";
        (string importId, _) = await world.Stage();

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.Equal(2, world.Target.Session.Firewall.Calls.Count);
        Assert.StartsWith("ensure-open " + imported.Instance, world.Target.Session.Firewall.Calls[0], StringComparison.Ordinal);
        Assert.Equal("remove " + imported.Instance, world.Target.Session.Firewall.Calls[1]);
    }

    [Fact]
    public async Task Finish_RemovesTheStaging_AndLeavesTheLoadedImages()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, _) = world.AddContainer("vr-1", ran: false);
        (string importId, _) = await world.Stage("vr-1");

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.Empty(world.Staged());
        Assert.True(world.Target.Session.Images.Held.ContainsKey(reference));
        InstanceDescription instance = world.Target.Find(imported.Instance);
        Assert.Equal(BlueprintRuntime.Container, instance.Config!.Runtime);
        Assert.True(File.Exists(instance.Layout.ComposeFile));
        Assert.Contains(imported.Instance, File.ReadAllText(instance.Layout.ComposeFile), StringComparison.Ordinal);
        Assert.DoesNotContain("vr-1", File.ReadAllText(instance.Layout.ComposeFile), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Finish_RestoresBootAutostart_ThroughTheWatchdog_OfTheNewId()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        world.Target.Session.Watchdog.SocketPresent = true;
        world.AddNative(ran: false);
        (string importId, TransferManifest manifest) = await world.Stage();
        Assert.True(manifest.Instance.Autostart);

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.Contains(imported.Instance, world.Target.Session.Watchdog.Autostart);
    }

    [Fact]
    public async Task Finish_WithoutAWatchdog_ForAnInstanceThatStartedAtBoot_FailsAndUnwinds()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        world.AddNative(ran: false);
        (string importId, _) = await world.Stage();

        CliRun run = await world.Finish(importId);

        Assert.Equal(1, run.Exit);
        Assert.Contains("autostart", TransferWorld.Error(run).Message, StringComparison.Ordinal);
        AssertUnwound(world, importId);
    }

    [Fact]
    public async Task Finish_WhenTheWatchdogRefusesAutostart_Unwinds()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        world.Target.Session.Watchdog.SocketPresent = true;
        world.Target.Session.Watchdog.RefuseEnable = true;
        world.AddNative(ran: false);
        (string importId, _) = await world.Stage();

        CliRun run = await world.Finish(importId);

        Assert.Equal(1, run.Exit);
        AssertUnwound(world, importId);
    }

    [Fact]
    public async Task Finish_NeverAdoptsBackupsThatAreAlreadyThere_EvenWhenEveryNameItCouldMintIsTaken()
    {
        var world = TransferWorld.Create();
        world.Target.Session.Extra["Instances__IdSuffixLength"] = "1";
        const string Alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
        foreach (char c in Alphabet)
        {
            Directory.CreateDirectory(world.Target.Backups($"factorio-{c}"));
            File.WriteAllText(Path.Combine(world.Target.Backups($"factorio-{c}"), "earlier.txt"), "an earlier instance's backup");
        }

        world.AddNative();
        (string importId, _) = await world.Stage();

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        string backups = world.Target.Find(imported.Instance).Config!.BackupsDirectory;
        Assert.NotEqual(world.Target.Backups(imported.Instance), backups);
        Assert.False(File.Exists(Path.Combine(backups, "earlier.txt")));
        Assert.Single(Directory.EnumerateDirectories(backups));
        foreach (char c in Alphabet)
        {
            Assert.Equal(["earlier.txt"], Directory.EnumerateFileSystemEntries(world.Target.Backups($"factorio-{c}")).Select(Path.GetFileName));
        }
    }

    [Fact]
    public async Task Finish_OfAnImportWhoseTreeCarriesNoBackups_MakesAnEmptyBackupsDirectory()
    {
        var world = TransferWorld.Create();
        (InstanceDescription source, _) = world.AddNative();
        Directory.Delete(source.Config!.BackupsDirectory, recursive: true);
        (string importId, _) = await world.Stage();

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        string backups = world.Target.Find(imported.Instance).Config!.BackupsDirectory;
        Assert.True(Directory.Exists(backups));
        Assert.Empty(Directory.EnumerateFileSystemEntries(backups));
    }

    // --- what finish decides again ---

    [Fact]
    public async Task Finish_DecidesTheBlueprintAgain_AndRefusesWhenItIsGone()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        File.Delete(Path.Combine(world.Target.Sandbox.Paths.SystemBlueprintsDirectory, "factorio.bp.yaml"));

        CliRun run = await world.Finish(importId);

        Assert.Equal(1, run.Exit);
        Assert.Equal("Blueprint 'factorio' is not on this host", TransferWorld.Error(run).Message);
        AssertUnwound(world, importId);
    }

    [Fact]
    public async Task Finish_DecidesThePortsAgain_AndRefusesWith62WhenSomethingTookThem()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        world.Target.AddInstance("late-1", "factorio", shape: c => c with { Ports = "34197/tcp" });

        CliRun run = await world.Finish(importId);

        Assert.Equal(62, run.Exit);
        Assert.Contains("late-1", TransferWorld.Error(run).Message, StringComparison.Ordinal);
        AssertUnwound(world, importId, expectedInstances: ["late-1"]);
    }

    [Fact]
    public async Task Finish_DecidesTheVersionGateAgain()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        world.Target.Session.EngineVersion = "9.9.9";

        CliRun run = await world.Finish(importId);

        Assert.Equal(60, run.Exit);
        AssertUnwound(world, importId);
    }

    [Fact]
    public async Task Finish_DecidesTheRequirementsAgain()
    {
        var world = TransferWorld.Create();
        world.AddContainer("vr-1", ran: false);
        (string importId, _) = await world.Stage("vr-1");
        world.Target.Session.Requirements = new FakeRequirements();

        CliRun run = await world.Finish(importId);

        Assert.Equal(61, run.Exit);
        AssertUnwound(world, importId);
    }

    [Fact]
    public async Task Finish_DoesNotCheckRoomAgain_BecauseTheBytesAreAlreadyOnDisk()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        world.Target.Session.Extra["Libraries__InstallFreeSpaceMarginMb"] = "999999999";

        Assert.Equal(0, (await world.Finish(importId)).Exit);
    }

    // --- integrity ---

    [Fact]
    public async Task Finish_BeforeEveryPartArrived_IsRefusedWith63()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        string importId = await world.BeginOk(await world.LockedManifest());

        CliRun run = await world.Finish(importId);

        Assert.Equal(63, run.Exit);
        Assert.Equal("Part tree has not arrived", TransferWorld.Error(run).Message);
    }

    [Fact]
    public async Task Finish_OfATreeThatIsNotTheSizeTheManifestSaid_IsRefusedWith63()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        File.Delete(Path.Combine(TransferStageTests.StageOf(world, importId), "tree", "instance", "install", "game.bin"));

        CliRun run = await world.Finish(importId);

        Assert.Equal(63, run.Exit);
        Assert.Contains("the manifest says", TransferWorld.Error(run).Message, StringComparison.Ordinal);
        Assert.Single(world.Staged());
    }

    [Fact]
    public async Task Finish_OfATreeWithoutTheInstancesConfig_IsRefusedWith63()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        File.Delete(Path.Combine(TransferStageTests.StageOf(world, importId), "tree", "instance", "fx-1.config.json"));
        // The tree is the size it said again, so only the missing config is wrong.
        File.WriteAllText(Path.Combine(TransferStageTests.StageOf(world, importId), "tree", "instance", "fx-1.config.json.x"), string.Empty);

        CliRun run = await world.Finish(importId);

        Assert.Equal(63, run.Exit);
    }

    [Fact]
    public async Task Finish_OfAnUnknownImport_IsExit64()
    {
        var world = TransferWorld.Create();

        Assert.Equal(64, (await world.Finish("imp-000000000000")).Exit);
    }

    // --- the unwind ---

    [Fact]
    public async Task Finish_WhoseProofStartFails_PutsEverythingBack_AndLeavesTheStagingForAbort()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        world.Target.Script.Failures["start"] = "the game would not start";
        string stage = TransferStageTests.StageOf(world, importId);

        CliRun run = await world.Finish(importId);

        Assert.Equal(1, run.Exit);
        Assert.Contains("did not start from its new place", TransferWorld.Error(run).Message, StringComparison.Ordinal);
        AssertUnwound(world, importId);
        Assert.True(File.Exists(Path.Combine(stage, "tree", "instance", "fx-1.config.json")));
        Assert.True(File.Exists(Path.Combine(stage, "tree", "instance", ".fx-1.version")));
        Assert.True(File.Exists(Path.Combine(stage, "tree", "instance", "fx-1.log")));
        Assert.True(Directory.Exists(Path.Combine(stage, "tree", "backups")));
        Assert.Empty(world.Target.Events());
    }

    [Fact]
    public async Task Finish_AfterAFailure_CanBeRunAgain_AndThenSucceeds()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        world.Target.Script.Failures["start"] = "the game would not start";
        Assert.Equal(1, (await world.Finish(importId)).Exit);

        world.Target.Script.Failures.Clear();
        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.True(world.Target.IsRegistered(imported.Instance));
        Assert.Empty(world.Staged());
    }

    [Fact]
    public async Task Finish_WhoseUnwindMeetsABackupsDirectoryThatIsNotItsOwn_LeavesThatDirectoryAlone()
    {
        (TransferWorld world, string importId, _, _) = await StagedNative();
        world.Target.Script.Failures["start"] = "boom";
        Directory.CreateDirectory(world.Target.Backups("untouched"));
        File.WriteAllText(Path.Combine(world.Target.Backups("untouched"), "keep.txt"), "x");

        await world.Finish(importId);

        Assert.True(File.Exists(Path.Combine(world.Target.Backups("untouched"), "keep.txt")));
    }

    [Fact]
    public async Task Finish_OfACustomBlueprint_InstallsItAndTheHooks_AndAnUnwindRemovesThem()
    {
        var world = TransferWorld.Create();
        world.AddCustom();
        (string importId, _) = await world.Stage("my-1");
        string blueprint = Path.Combine(world.Target.Sandbox.Paths.UserBlueprintsDirectory, "mygame.bp.yaml");
        string hooks = Path.Combine(world.Target.Sandbox.Paths.UserOverridesDirectory, "mygame", "hooks.sh");
        world.Target.Script.Failures["start"] = "boom";

        Assert.Equal(1, (await world.Finish(importId)).Exit);
        Assert.False(File.Exists(blueprint));
        Assert.False(File.Exists(hooks));
        Assert.False(Directory.Exists(Path.GetDirectoryName(hooks)));

        world.Target.Script.Failures.Clear();
        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.Equal("mygame", imported.Blueprint);
        Assert.True(File.Exists(blueprint));
        Assert.Equal(File.ReadAllText(Path.Combine(world.Source.Sandbox.Paths.UserBlueprintsDirectory, "mygame.bp.yaml")), File.ReadAllText(blueprint));
        Assert.Equal("kgsm_hook_latest_version() { echo 1; }\n", File.ReadAllText(hooks));
        InstanceDescription instance = world.Target.Find(imported.Instance);
        Assert.Equal(HookFiles.Find(world.Target.Sandbox.Paths, "mygame")!.Digest, ScriptHeader.Parse(File.ReadAllText(instance.Layout.ManagementScript))!.HooksDigest);
    }

    [Fact]
    public async Task Finish_OfACollidingCustomBlueprint_InstallsItUnderTheSuffixedName_WithItsHooks()
    {
        var world = TransferWorld.Create();
        world.AddCustom();
        TransferWorld.WriteCustomBlueprint(world.Target, "mygame", hooks: "kgsm_hook_latest_version() { echo 2; }\n", comment: "\n# the host's own\n");
        (string importId, _) = await world.Stage("my-1", "--blueprint-suffix", "v2");

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.Equal("mygame-v2", imported.Blueprint);
        string installed = File.ReadAllText(Path.Combine(world.Target.Sandbox.Paths.UserBlueprintsDirectory, "mygame-v2.bp.yaml"));
        Assert.Contains("name: mygame-v2", installed, StringComparison.Ordinal);
        Assert.Contains("the host's own", File.ReadAllText(Path.Combine(world.Target.Sandbox.Paths.UserBlueprintsDirectory, "mygame.bp.yaml")), StringComparison.Ordinal);
        Assert.Equal("kgsm_hook_latest_version() { echo 1; }\n", File.ReadAllText(Path.Combine(world.Target.Sandbox.Paths.UserOverridesDirectory, "mygame-v2", "hooks.sh")));
        InstanceDescription instance = world.Target.Find(imported.Instance);
        Assert.Equal("mygame-v2", instance.Config!.Blueprint);
        Assert.Equal(Path.Combine(world.Target.Main.Path, "instances", "mygame-v2", imported.Instance), instance.WorkingDirectory);
    }

    [Fact]
    public async Task Finish_OfACustomBlueprintTheHostAlreadyHolds_UsesTheHostsFileAndHooks_AndKeepsThem()
    {
        var world = TransferWorld.Create();
        world.AddCustom();
        TransferWorld.WriteCustomBlueprint(world.Target, "mygame", hooks: "kgsm_hook_latest_version() { echo 9; }\n");
        (string importId, _) = await world.Stage("my-1");

        ImportedInstance imported = world.Imported(await world.Finish(importId));

        Assert.Equal("mygame", imported.Blueprint);
        Assert.Equal("kgsm_hook_latest_version() { echo 9; }\n", File.ReadAllText(Path.Combine(world.Target.Sandbox.Paths.UserOverridesDirectory, "mygame", "hooks.sh")));
    }

    [Fact]
    public async Task ATransferEndToEnd_LeavesTheTargetWithTheInstance_AndTheSourceWithout()
    {
        var world = TransferWorld.Create();
        (InstanceDescription source, string sourceDirectory) = world.AddNative();
        (string importId, _) = await world.Stage();
        ImportedInstance imported = world.Imported(await world.Finish(importId));

        CliRun commit = await world.Commit("fx-1");

        Assert.Equal(0, commit.Exit);
        Assert.False(world.Source.IsRegistered("fx-1"));
        Assert.False(Directory.Exists(sourceDirectory));
        Assert.False(Directory.Exists(source.Config!.BackupsDirectory));
        Assert.True(world.Target.IsRegistered(imported.Instance));
        Assert.Contains("server.exported", world.Source.Events());
        Assert.Contains("server.imported", world.Target.Events());
    }

    /// <summary>A failed finish leaves the target as it found it: nothing registered, no instance directory, the staging still there.</summary>
    private static void AssertUnwound(TransferWorld world, string importId, string[]? expectedInstances = null)
    {
        Assert.Equal(expectedInstances ?? [], world.Target.Session.Sandbox.Paths.InstanceRegistryFile is { } file && File.Exists(file)
            ? new InstanceStore(world.Target.Sandbox.Paths, new Libraries.LibraryCatalog(world.Target.Sandbox.Paths)).Registered().Keys.Order(StringComparer.Ordinal).ToArray()
            : []);
        foreach (string blueprint in new[] { "factorio", "vrising" })
        {
            string directory = Path.Combine(world.Target.Main.Path, "instances", blueprint);
            Assert.Equal(
                (expectedInstances ?? []).Where(i => blueprint == "factorio").Order(StringComparer.Ordinal),
                Directory.Exists(directory) ? Directory.EnumerateDirectories(directory).Select(Path.GetFileName).Order(StringComparer.Ordinal) : []);
        }

        Assert.True(Directory.Exists(TransferStageTests.StageOf(world, importId)));
        Assert.Empty(world.Target.Events());
        if (Directory.Exists(world.Target.Sandbox.PathFor("backups")))
        {
            Assert.Empty(Directory.EnumerateDirectories(world.Target.Sandbox.PathFor("backups")).Where(d => Path.GetFileName(d).StartsWith("factorio-", StringComparison.Ordinal)));
        }
    }
}
