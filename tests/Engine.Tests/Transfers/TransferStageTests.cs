using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;
using TheKrystalShip.KGSM.Engine.Transfers;

namespace TheKrystalShip.KGSM.Engine.Tests.Transfers;

/// <summary>Begin, part, abort and list: the staged import and what it holds, loads and removes.</summary>
public class TransferStageTests
{
    [Fact]
    public async Task Begin_StagesTheImportInTheLibrary_WithItsManifestAndItsRecord()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        TransferManifest manifest = await world.LockedManifest();

        string importId = await world.BeginOk(manifest);

        Assert.Matches("^imp-[0-9a-f]{12}$", importId);
        string stage = Path.Combine(world.Target.Main.Path, ".kgsm-import", importId);
        Assert.True(File.Exists(Path.Combine(stage, "manifest.json")));
        Assert.True(File.Exists(Path.Combine(stage, "meta.json")));
        Assert.True(Directory.Exists(Path.Combine(stage, "parts")));
        Assert.Equal(TransferWorld.Write(manifest), File.ReadAllText(Path.Combine(stage, "manifest.json")));
        Assert.Empty(world.Target.Events());
    }

    [Fact]
    public async Task Begin_OfARefusedManifest_PrintsTheVerdict_ExitsWithTheFirstRefusal_AndStagesNothing()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        TransferManifest manifest = await world.LockedManifest();
        world.Target.Session.EngineVersion = "9.9.9";

        CliRun run = await world.Begin(manifest);

        Assert.Equal(60, run.Exit);
        Assert.False(TransferWorld.Verdict(run).Ok);
        Assert.Empty(world.Staged());
    }

    [Fact]
    public async Task Begin_RemembersWhichImagesTheHostAlreadyHeld()
    {
        var world = TransferWorld.Create();
        world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        world.Target.Session.Images.Add("ghcr.io/thekrystalship/vrising:latest", manifest.Parts[1].ImageId!);

        string importId = await world.BeginOk(manifest);

        ImportStageMeta meta = ReadMeta(world, importId);
        ImportStageImage image = Assert.Single(meta.Images);
        Assert.True(image.HeldBefore);
        Assert.Equal("image-1", image.PartId);
    }

    [Fact]
    public async Task Part_ExtractsTheTree_AndMarksItArrived()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        (string importId, _) = await world.Stage();

        string stage = StageOf(world, importId);
        Assert.True(File.Exists(Path.Combine(stage, "parts", "tree.done")));
        Assert.True(File.Exists(Path.Combine(stage, "tree", "instance", "fx-1.config.json")));
        Assert.True(File.Exists(Path.Combine(stage, "tree", "instance", "install", "data", "map.dat")));
        Assert.True(Directory.Exists(Path.Combine(stage, "tree", "backups")));
    }

    [Fact]
    public async Task Part_ThatArrivesDamaged_IsRefusedWith63_LeavesNoMarker_AndAFlippedContentByteIsEnough()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        TransferManifest manifest = await world.LockedManifest();
        string importId = await world.BeginOk(manifest);
        (_, byte[] bytes) = await world.Part("fx-1", "tree");
        bytes[bytes.AsSpan().IndexOf("the world"u8) + 4] ^= 0x01;

        CliRun run = await world.Load(importId, "tree", bytes);

        Assert.Equal(63, run.Exit);
        Assert.Equal("transfer-integrity", TransferWorld.Error(run).Code);
        Assert.False(File.Exists(Path.Combine(StageOf(world, importId), "parts", "tree.done")));
    }

    [Fact]
    public async Task Part_ThatIsCutShort_IsRefusedWith63()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        TransferManifest manifest = await world.LockedManifest();
        string importId = await world.BeginOk(manifest);
        (_, byte[] bytes) = await world.Part("fx-1", "tree");

        CliRun run = await world.Load(importId, "tree", bytes[..(bytes.Length / 2)]);

        Assert.Equal(63, run.Exit);
    }

    [Fact]
    public async Task Part_OfAnUnknownImport_IsExit64_AndOfAPartTheManifestDoesNotList_Exit25()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        TransferManifest manifest = await world.LockedManifest();
        string importId = await world.BeginOk(manifest);

        Assert.Equal(64, (await world.Load("imp-000000000000", "tree", [])).Exit);
        Assert.Equal(64, (await world.Load("../escape", "tree", [])).Exit);
        Assert.Equal(25, (await world.Load(importId, "image-1", [])).Exit);
    }

    [Fact]
    public async Task Part_SentAgain_BeginsFromNothing()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        (string importId, _) = await world.Stage();
        string stray = Path.Combine(StageOf(world, importId), "tree", "instance", "stray.txt");
        File.WriteAllText(stray, "left over");

        (_, byte[] bytes) = await world.Part("fx-1", "tree");
        Assert.Equal(0, (await world.Load(importId, "tree", bytes)).Exit);

        Assert.False(File.Exists(stray));
    }

    [Fact]
    public async Task Part_OfAnImage_LoadsItAndComparesTheId()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, ImageInfo image) = world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        string importId = await world.BeginOk(manifest);

        (CliRun made, byte[] bytes) = await world.Part("vr-1", "image-1");
        CliRun loaded = await world.Load(importId, "image-1", bytes);

        Assert.Equal(0, made.Exit);
        Assert.Equal(0, loaded.Exit);
        Assert.Equal(image.Chain, world.Target.Session.Images.Held[reference].Chain);
        Assert.NotEqual(image.Id, world.Target.Session.Images.Held[reference].Id);
        Assert.True(File.Exists(Path.Combine(StageOf(world, importId), "parts", "image-1.done")));
    }

    [Fact]
    public async Task Part_OfAnImageThatLoadsAsSomethingElse_IsRefusedWith63_AndTheStrayImageIsRemovedAtOnce()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, _) = world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        string importId = await world.BeginOk(manifest);

        CliRun run = await world.Load(importId, "image-1", TransferWorld.Sealed($"{reference}|chain:other|10"));

        Assert.Equal(63, run.Exit);
        Assert.Contains("chain:other", run.Err, StringComparison.Ordinal);
        Assert.Empty(world.Target.Session.Images.Held);
        Assert.False(File.Exists(Path.Combine(StageOf(world, importId), "parts", "image-1.done")));
    }

    [Fact]
    public async Task Part_OfAnImageThatReplacedAnotherUnderTheSameReference_PutsTheReferenceBack()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, _) = world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        ImageInfo mine = world.Target.Session.Images.Add("elsewhere", "chain:mine", 7);
        world.Target.Session.Images.Held[reference] = mine;
        string importId = await world.BeginOk(manifest);

        CliRun run = await world.Load(importId, "image-1", TransferWorld.Sealed($"{reference}|chain:other|10"));

        Assert.Equal(63, run.Exit);
        Assert.Equal(mine.Id, world.Target.Session.Images.Held[reference].Id);
    }

    [Fact]
    public async Task Part_OfAnImageWhoseBytesWereDamaged_IsRefusedWith63_AndTheImageItLoadedIsRemovedAtOnce()
    {
        var world = TransferWorld.Create();
        world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        string importId = await world.BeginOk(manifest);
        (_, byte[] bytes) = await world.Part("vr-1", "image-1");
        bytes[^(ImageStreamTests.TrailerLength + 1)] ^= 0x01; // the last byte of the saved image, the size's last digit

        CliRun run = await world.Load(importId, "image-1", bytes);

        Assert.Equal(63, run.Exit);
        Assert.Contains("damaged", TransferWorld.Error(run).Message, StringComparison.Ordinal);
        Assert.Empty(world.Target.Session.Images.Held);
        Assert.False(File.Exists(Path.Combine(StageOf(world, importId), "parts", "image-1.done")));
    }

    [Fact]
    public async Task Part_OfAnImageStreamWithoutItsTrailer_OrCutShort_IsRefusedWith63()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, ImageInfo image) = world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        string importId = await world.BeginOk(manifest);
        byte[] bare = TransferWorld.Utf8($"{reference}|{image.Chain}|{image.Size}");
        (_, byte[] whole) = await world.Part("vr-1", "image-1");

        Assert.Equal(63, (await world.Load(importId, "image-1", bare)).Exit);
        Assert.Equal(63, (await world.Load(importId, "image-1", whole[..^1])).Exit);
        Assert.Equal(63, (await world.Load(importId, "image-1", [])).Exit);
        Assert.Empty(world.Target.Session.Images.Held);

        Assert.Equal(0, (await world.Load(importId, "image-1", whole)).Exit);
    }

    [Fact]
    public async Task Part_OfAnImageStreamTheRuntimeRefuses_IsRefusedWith63()
    {
        var world = TransferWorld.Create();
        world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        string importId = await world.BeginOk(manifest);

        CliRun run = await world.Load(importId, "image-1", TransferWorld.Utf8("garbage"));

        Assert.Equal(63, run.Exit);
        Assert.Contains("could not be loaded", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Abort_RemovesTheStaging_AndOnlyTheImagesItLoadedAndVerified()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, ImageInfo image) = world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        string importId = await world.BeginOk(manifest);
        await world.LoadAll(importId, manifest, "vr-1");

        CliRun run = await world.Target.Run("transfer", "import", "abort", importId, "--json");

        Assert.Equal(0, run.Exit);
        ImportAbortReport report = JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.ImportAbortReport)!;
        Assert.True(report.Found);
        Assert.Equal([reference], report.ImagesRemoved);
        Assert.False(world.Target.Session.Images.Held.ContainsKey(reference));
        Assert.Empty(world.Staged());
        Assert.False(Directory.Exists(Path.Combine(world.Target.Main.Path, ".kgsm-import")));
    }

    [Fact]
    public async Task Abort_PutsTheReferenceBackOnTheImageItNamedBeforeTheImportLoadedAnother()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, _) = world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        ImageInfo previous = world.Target.Session.Images.Add(reference, "chain:older");
        world.Target.Session.Images.Add("older-tag", "chain:older");
        world.Target.Session.Images.Held["older-tag"] = previous;
        string importId = await world.BeginOk(manifest);
        await world.LoadAll(importId, manifest, "vr-1");
        Assert.NotEqual(previous.Id, world.Target.Session.Images.Held[reference].Id);

        Assert.Equal(0, (await world.Target.Run("transfer", "import", "abort", importId)).Exit);

        Assert.Equal(previous.Id, world.Target.Session.Images.Held[reference].Id);
        Assert.Empty(world.Staged());
    }

    [Fact]
    public async Task Abort_LeavesAnImageTheHostHeldBeforeTheImportBegan()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, ImageInfo image) = world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        world.Target.Session.Images.Add(reference, image.Chain);
        string importId = await world.BeginOk(manifest);
        await world.LoadAll(importId, manifest, "vr-1");

        Assert.Equal(0, (await world.Target.Run("transfer", "import", "abort", importId)).Exit);

        Assert.True(world.Target.Session.Images.Held.ContainsKey(reference));
        Assert.Empty(world.Target.Session.Images.Removed);
    }

    [Fact]
    public async Task Abort_LeavesAnImageForAPartThatNeverArrived()
    {
        var world = TransferWorld.Create();
        (_, _, string reference, ImageInfo image) = world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        string importId = await world.BeginOk(manifest);
        world.Target.Session.Images.Add(reference, image.Chain);

        Assert.Equal(0, (await world.Target.Run("transfer", "import", "abort", importId)).Exit);

        Assert.True(world.Target.Session.Images.Held.ContainsKey(reference));
        Assert.Empty(world.Staged());
    }

    [Fact]
    public async Task Abort_OfAnImportNobodyStaged_Succeeds()
    {
        var world = TransferWorld.Create();

        CliRun run = await world.Target.Run("transfer", "import", "abort", "imp-000000000000", "--json");

        Assert.Equal(0, run.Exit);
        Assert.False(JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.ImportAbortReport)!.Found);
    }

    [Fact]
    public async Task Abort_WhenTheRuntimeWillNotRemoveTheImage_KeepsTheStaging_SoItCanBeRunAgain()
    {
        var world = TransferWorld.Create();
        world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        string importId = await world.BeginOk(manifest);
        await world.LoadAll(importId, manifest, "vr-1");
        world.Target.Session.Images.RemoveFails = true;

        CliRun failed = await world.Target.Run("transfer", "import", "abort", importId);

        Assert.Equal(1, failed.Exit);
        Assert.Single(world.Staged());

        world.Target.Session.Images.RemoveFails = false;
        Assert.Equal(0, (await world.Target.Run("transfer", "import", "abort", importId)).Exit);
        Assert.Empty(world.Staged());
    }

    [Fact]
    public async Task List_ShowsEveryStagedImport_AcrossLibraries()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        world.Target.Sandbox.AddLibrary("second");
        TransferManifest manifest = await world.LockedManifest();
        string first = await world.BeginOk(manifest, "--library", "main");
        world.Target.Session.Clock.Advance(TimeSpan.FromMinutes(1));
        string second = await world.BeginOk(manifest, "--library", "second");

        CliRun run = await world.Target.Run("transfer", "import", "list", "--json");

        Assert.Equal(0, run.Exit);
        StagedImport[] rows = [.. JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.IReadOnlyListStagedImport)!];
        Assert.Equal([first, second], rows.Select(r => r.ImportId));
        Assert.Equal(["main", "second"], rows.Select(r => r.Library));
        Assert.All(rows, r => Assert.Equal("fx-1", r.Instance));
        Assert.All(rows, r => Assert.Equal("factorio", r.Blueprint));
    }

    [Fact]
    public async Task List_WithNothingStaged_IsEmpty()
    {
        var world = TransferWorld.Create();

        CliRun run = await world.Target.Run("transfer", "import", "list", "--json");

        Assert.Equal(0, run.Exit);
        Assert.Equal("[]", run.Out.Trim());
    }

    internal static string StageOf(TransferWorld world, string importId) => Path.Combine(world.Target.Main.Path, ".kgsm-import", importId);

    private static ImportStageMeta ReadMeta(TransferWorld world, string importId) =>
        JsonSerializer.Deserialize(File.ReadAllText(Path.Combine(StageOf(world, importId), "meta.json")), EngineJsonContext.Default.ImportStageMeta)!;
}
