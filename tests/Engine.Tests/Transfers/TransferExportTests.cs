using System.Formats.Tar;
using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Transfers;

/// <summary><c>transfer export</c>: the manifest, the lock it takes, the parts it streams and the commit.</summary>
public class TransferExportTests
{
    [Fact]
    public async Task Manifest_WithoutALock_DescribesTheInstance_AndLocksNothing()
    {
        var world = TransferWorld.Create();
        (InstanceDescription instance, string wd) = world.AddNative();

        CliRun run = await world.Manifest("fx-1", token: null);

        Assert.Equal(0, run.Exit);
        TransferManifest manifest = TransferWorld.ReadManifest(run.Out);
        Assert.Equal(1, manifest.SchemaVersion);
        Assert.Equal(Journal.EngineVersion.Current, manifest.EngineVersion);
        Assert.Equal("fx-1", manifest.Instance.Id);
        Assert.Equal("factorio", manifest.Instance.Blueprint);
        Assert.Equal(BlueprintRuntime.Native, manifest.Instance.Runtime);
        Assert.Null(manifest.Instance.DisplayName);
        Assert.False(manifest.Instance.Autostart);
        Assert.True(manifest.Instance.HasRun);
        Assert.Equal("main", manifest.Instance.Library);
        Assert.Equal(new PortRange { Start = 34197, End = 34197, Protocol = PortProtocol.Tcp }, manifest.Instance.Ports.FirstOrDefault());
        Assert.False(manifest.Blueprint.Custom);
        Assert.NotEmpty(manifest.Blueprint.Sha256);
        Assert.Empty(manifest.Requirements);

        TransferPart tree = Assert.Single(manifest.Parts);
        Assert.Equal("tree", tree.Id);
        Assert.Equal(TransferPartKind.Tree, tree.Kind);
        string[] files = [.. Directory.EnumerateFiles(wd, "*", SearchOption.AllDirectories), .. Directory.EnumerateFiles(instance.Config!.BackupsDirectory, "*", SearchOption.AllDirectories)];
        Assert.Equal(files.Length, tree.Files);
        Assert.Equal(files.Sum(f => new FileInfo(f).Length), tree.Bytes);
        Assert.Null(TransferLock.Holder(instance.Layout));
    }

    [Fact]
    public async Task Manifest_ReportsTheDisplayName_OnlyWhenOneIsSet()
    {
        var world = TransferWorld.Create();
        world.AddNative("fx-1", c => c with { DisplayName = "The Factory" });

        TransferManifest manifest = TransferWorld.ReadManifest((await world.Manifest("fx-1", token: null)).Out);

        Assert.Equal("The Factory", manifest.Instance.DisplayName);
    }

    [Fact]
    public async Task Manifest_UnderAToken_LocksTheInstance_RemembersAutostart_AndSwitchesItOff()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        (InstanceDescription instance, _) = world.AddNative();

        TransferManifest manifest = await world.LockedManifest();

        Assert.True(manifest.Instance.Autostart);
        Assert.Equal(TransferWorld.Token, TransferLock.Holder(instance.Layout));
        Assert.True(TransferLock.Read(instance.Layout)!.Autostart);
        Assert.DoesNotContain("fx-1", world.Source.Session.Watchdog.Autostart);
        Assert.Contains("disable fx-1", world.Source.Session.Watchdog.Actions);
    }

    [Fact]
    public async Task Manifest_UnderTheTokenThatAlreadyHoldsTheLock_IsRepeatable_AndReportsTheFlagTheLockFound()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        world.AddNative();

        await world.LockedManifest();
        TransferManifest again = await world.LockedManifest();

        Assert.True(again.Instance.Autostart);
        Assert.Single(world.Source.Session.Watchdog.Actions, a => a == "disable fx-1");
    }

    [Fact]
    public async Task Manifest_OnAHostWithoutAWatchdog_ReportsNoAutostart()
    {
        var world = TransferWorld.Create();
        world.AddNative();

        TransferManifest manifest = await world.LockedManifest();

        Assert.False(manifest.Instance.Autostart);
        Assert.Empty(world.Source.Session.Watchdog.Actions);
    }

    [Fact]
    public async Task Manifest_WhenTheWatchdogIsThereAndSilent_IsRefused_RatherThanGuessingTheFlag()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Health = new(false, false, "no answer");
        (InstanceDescription instance, _) = world.AddNative();

        CliRun run = await world.Manifest("fx-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("cannot be read", run.Err, StringComparison.Ordinal);
        Assert.Null(TransferLock.Holder(instance.Layout));
    }

    [Fact]
    public async Task Manifest_OfARunningInstance_IsRefusedWith57_AfterTheLock_ThenTheLockIsReleasedAndAutostartRestored()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        (InstanceDescription instance, string wd) = world.AddNative();
        world.Source.Simulate("fx-1", wd);

        CliRun run = await world.Manifest("fx-1");

        Assert.Equal(57, run.Exit);
        Assert.Equal("running", TransferWorld.Error(await world.Manifest("fx-1", null)).Code);
        Assert.Null(TransferLock.Holder(instance.Layout));
        Assert.Contains("fx-1", world.Source.Session.Watchdog.Autostart);
        Assert.Equal(["disable fx-1", "enable fx-1"], world.Source.Session.Watchdog.Actions);
    }

    [Fact]
    public async Task Manifest_OfALockedInstance_IsRefusedWith59_ForAnotherTokenAndForNone()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        await world.LockedManifest();

        Assert.Equal(59, (await world.Manifest("fx-1", "someone-else")).Exit);
        Assert.Equal(59, (await world.Manifest("fx-1", token: null)).Exit);
    }

    [Fact]
    public async Task Manifest_WithATokenOutsideTheAlphabet_IsRefused()
    {
        var world = TransferWorld.Create();
        (InstanceDescription instance, _) = world.AddNative();

        CliRun run = await world.Manifest("fx-1", "not a token; rm");

        Assert.Equal(1, run.Exit);
        Assert.Equal("invalid", TransferWorld.Error(run).Code);
        Assert.Null(TransferLock.Holder(instance.Layout));
    }

    [Fact]
    public async Task Manifest_OfAnInstanceThatIsNotRegistered_IsExit25()
    {
        var world = TransferWorld.Create();

        CliRun run = await world.Manifest("nothing-1");

        Assert.Equal(25, run.Exit);
    }

    [Fact]
    public async Task Manifest_OfAnInstanceInAnOfflineLibrary_IsRefused()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        Directory.Delete(world.Source.Main.Path, recursive: true);

        CliRun run = await world.Manifest("fx-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("offline", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Manifest_OfACustomBlueprint_CarriesItsDigest_AndTheTreeCarriesItAndItsHooks()
    {
        var world = TransferWorld.Create();
        string text = File.ReadAllText(Path.Combine(world.Source.Sandbox.Paths.SystemBlueprintsDirectory, "factorio.bp.yaml")).Replace("name: factorio", "name: mygame", StringComparison.Ordinal);
        string blueprintFile = world.Source.Sandbox.WriteFile(Path.Combine(world.Source.Sandbox.Paths.UserBlueprintsDirectory, "mygame.bp.yaml"), text);
        world.Source.Sandbox.WriteFile(Path.Combine(world.Source.Sandbox.Paths.UserOverridesDirectory, "mygame", "hooks.sh"), "kgsm_hook_latest_version() { echo 1; }\n");
        world.Source.AddInstance("my-1", "mygame");

        TransferManifest manifest = await world.LockedManifest("my-1");

        Assert.True(manifest.Blueprint.Custom);
        Assert.Equal(Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(blueprintFile))), manifest.Blueprint.Sha256);

        (CliRun made, byte[] bytes) = await world.Part("my-1", "tree");
        Assert.Equal(0, made.Exit);
        string[] names = TarNames(bytes);
        Assert.Contains("blueprint/mygame.bp.yaml", names);
        Assert.Contains("overrides/mygame/hooks.sh", names);
    }

    [Fact]
    public async Task Part_StreamsTheTree_WithoutTheFilesThatOnlyMeanSomethingWhileTheInstanceRuns()
    {
        var world = TransferWorld.Create();
        (InstanceDescription instance, string wd) = world.AddNative();
        File.WriteAllText(instance.Layout.PidFile, "1\n");
        await world.LockedManifest();

        (CliRun run, byte[] bytes) = await world.Part("fx-1", "tree");

        Assert.Equal(0, run.Exit);
        Assert.Equal(string.Empty, run.Out);
        string[] names = TarNames(bytes);
        Assert.Contains("instance/fx-1.config.json", names);
        Assert.Contains("instance/install/data/map.dat", names);
        Assert.Contains("backups", names);
        Assert.DoesNotContain(names, n => n.EndsWith(".pid", StringComparison.Ordinal) || n.EndsWith("transfer-lock", StringComparison.Ordinal));
        Assert.Equal(TreeArchiveTests.DigestEntry, names[^1]);
        Assert.True(Directory.Exists(wd));
    }

    [Fact]
    public async Task Part_NeedsTheLock_FromTheSameToken_ElseExit59()
    {
        var world = TransferWorld.Create();
        world.AddNative();

        Assert.Equal(59, (await world.Part("fx-1", "tree")).Run.Exit);

        await world.LockedManifest();
        (CliRun other, byte[] bytes) = await world.Part("fx-1", "tree", "someone-else");
        Assert.Equal(59, other.Exit);
        Assert.Empty(bytes);
    }

    [Fact]
    public async Task Part_OfARunningInstance_IsRefusedWith57_EvenUnderTheLock()
    {
        var world = TransferWorld.Create();
        (_, string wd) = world.AddNative();
        await world.LockedManifest();
        world.Source.Simulate("fx-1", wd);

        (CliRun run, byte[] bytes) = await world.Part("fx-1", "tree");

        Assert.Equal(57, run.Exit);
        Assert.Empty(bytes);
    }

    [Fact]
    public async Task Part_ThatTheManifestDoesNotName_IsExit25()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        await world.LockedManifest();

        Assert.Equal(25, (await world.Part("fx-1", "image-1")).Run.Exit);
        Assert.Equal(25, (await world.Part("fx-1", "nothing")).Run.Exit);
    }

    [Fact]
    public async Task Manifest_OfAContainer_ListsOneImagePartPerReference_WithItsIdAndSize()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, ImageInfo image) = world.AddContainer();

        TransferManifest manifest = await world.LockedManifest("vr-1");

        Assert.Equal(["tree", "image-1"], manifest.Parts.Select(p => p.Id));
        TransferPart part = manifest.Parts[1];
        Assert.Equal(TransferPartKind.Image, part.Kind);
        Assert.Equal(reference, part.Ref);
        Assert.Equal(image.Chain, part.ImageId);
        Assert.Equal(image.Size, part.Bytes);
        Assert.Null(part.Files);
        Assert.Equal(["container-runtime"], manifest.Requirements);
        Assert.Equal(BlueprintRuntime.Container, manifest.Instance.Runtime);
    }

    [Fact]
    public async Task Manifest_OfAContainerWhoseImageIsGone_IsExit25_AndReleasesItsLock()
    {
        var world = TransferWorld.Create();
        (InstanceDescription instance, _, string reference, _) = world.AddContainer();
        world.Source.Session.Images.Held.Remove(reference);

        CliRun run = await world.Manifest("vr-1");

        Assert.Equal(25, run.Exit);
        Assert.Null(TransferLock.Holder(instance.Layout));
    }

    [Fact]
    public async Task Part_OfAnImage_StreamsWhatTheRuntimeSaves()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, ImageInfo image) = world.AddContainer();
        await world.LockedManifest("vr-1");

        (CliRun run, byte[] bytes) = await world.Part("vr-1", "image-1");

        Assert.Equal(0, run.Exit);
        byte[] saved = TransferWorld.Utf8($"{reference}|{image.Chain}|{image.Size}");
        Assert.Equal(saved, bytes[..saved.Length]);
        Assert.Equal(ImageStreamTests.TrailerFor(saved), bytes[saved.Length..]);
        Assert.Contains($"save {reference}", world.Source.Session.Images.Calls);
    }

    [Fact]
    public async Task Part_OfAnImage_WhenTheRuntimeCannotResolveTheCompose_Fails()
    {
        var world = TransferWorld.Create();
        (InstanceDescription instance, _, _, _) = world.AddContainer();
        await world.LockedManifest("vr-1");
        world.Source.Session.Images.Compose.Clear();

        (CliRun run, byte[] bytes) = await world.Part("vr-1", "image-1");

        Assert.Equal(1, run.Exit);
        Assert.Empty(bytes);
        Assert.NotNull(TransferLock.Holder(instance.Layout));
    }

    [Fact]
    public async Task Commit_RemovesTheInstanceItsBackupsAndTheLock_WritesTheBracketAndTheFact()
    {
        var world = TransferWorld.Create();
        (InstanceDescription instance, string wd) = world.AddNative();
        string backups = instance.Config!.BackupsDirectory;
        await world.LockedManifest();

        CliRun run = await world.Commit("fx-1");

        Assert.Equal(0, run.Exit);
        ExportCommitReport report = JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.ExportCommitReport)!;
        Assert.True(report.BackupsRemoved);
        Assert.False(world.Source.IsRegistered("fx-1"));
        Assert.False(Directory.Exists(wd));
        Assert.False(Directory.Exists(backups));
        Assert.Equal(["server.uninstall.started", "server.uninstalled", "server.uninstall.finished", "server.exported"], world.Source.Events());
    }

    [Fact]
    public async Task Commit_NeedsTheTokenThatHoldsTheLock()
    {
        var world = TransferWorld.Create();
        world.AddNative();

        Assert.Equal(59, (await world.Commit("fx-1")).Exit);

        await world.LockedManifest();
        Assert.Equal(59, (await world.Commit("fx-1", "someone-else")).Exit);
        Assert.True(world.Source.IsRegistered("fx-1"));
    }

    [Fact]
    public async Task Commit_OfARunningInstance_IsRefusedWith57_AndRemovesNothing()
    {
        var world = TransferWorld.Create();
        (_, string wd) = world.AddNative();
        await world.LockedManifest();
        world.Source.Simulate("fx-1", wd);

        CliRun run = await world.Commit("fx-1");

        Assert.Equal(57, run.Exit);
        Assert.True(Directory.Exists(wd));
        Assert.True(world.Source.IsRegistered("fx-1"));
    }

    [Fact]
    public async Task Commit_OfAnInstanceThatIsAlreadyGone_IsExit25_WhichTheDriverReadsAsDone()
    {
        var world = TransferWorld.Create();

        Assert.Equal(25, (await world.Commit("fx-1")).Exit);
    }

    [Fact]
    public async Task Commit_RemovesTheImagesNoOtherInstanceUses_AndKeepsTheShared()
    {
        var world = TransferWorld.Create();
        (InstanceDescription instance, string wd, string reference, _) = world.AddContainer();
        ImagesFor(world, "vr-2", ["shared:1"]);
        world.Source.Session.Images.Add("shared:1", "chain:bbbb2222");
        world.Source.Session.Images.Compose[instance.Layout.ComposeFile] = [reference, "shared:1"];
        await world.LockedManifest("vr-1");

        CliRun run = await world.Commit("vr-1");

        Assert.Equal(0, run.Exit);
        Assert.Equal([reference], world.Source.Session.Images.Removed);
        Assert.False(world.Source.Session.Images.Held.ContainsKey(reference));
        Assert.True(world.Source.Session.Images.Held.ContainsKey("shared:1"));
        Assert.False(Directory.Exists(wd));
    }

    [Fact]
    public async Task Commit_WhenAnotherInstancesImagesCannotBeResolved_RemovesNoImage()
    {
        var world = TransferWorld.Create();
        world.AddContainer();
        (InstanceDescription other, _) = world.Source.AddInstance("vr-2", "vrising", shape: c => c with { Runtime = BlueprintRuntime.Container });
        Assert.NotNull(other.Config);
        await world.LockedManifest("vr-1");

        CliRun run = await world.Commit("vr-1");

        Assert.Equal(0, run.Exit);
        Assert.Empty(world.Source.Session.Images.Removed);
        Assert.False(world.Source.IsRegistered("vr-1"));
    }

    [Fact]
    public async Task Export_NeedsExactlyOneMode_AndAPartNeedsAToken()
    {
        var world = TransferWorld.Create();
        world.AddNative();

        Assert.Equal(2, (await world.Source.Run("transfer", "export", "fx-1")).Exit);
        Assert.Equal(2, (await world.Source.Run("transfer", "export", "fx-1", "--manifest", "--commit", "--lock", "t")).Exit);
        Assert.Equal(2, (await world.Source.Run("transfer", "export", "fx-1", "--part", "tree")).Exit);
        Assert.Equal(2, (await world.Source.Run("transfer", "export", "fx-1", "--commit")).Exit);
    }

    private static void ImagesFor(TransferWorld world, string id, string[] references)
    {
        (_, string wd) = world.Source.AddInstance(id, "vrising", shape: c => c with { Runtime = BlueprintRuntime.Container });
        world.Source.Session.Images.Compose[new InstanceLayout(wd, id).ComposeFile] = references;
    }

    internal static string[] TarNames(byte[] bytes)
    {
        using var reader = new TarReader(new MemoryStream(bytes));
        var names = new List<string>();
        while (reader.GetNextEntry() is { } entry) names.Add(entry.Name.TrimEnd('/'));
        return [.. names];
    }
}
