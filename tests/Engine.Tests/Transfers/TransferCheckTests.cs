using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Transfers;

/// <summary><c>transfer import check</c>: every reason a host refuses a manifest, listed together, with nothing written.</summary>
public class TransferCheckTests
{
    private static async Task<(TransferWorld World, TransferManifest Manifest)> Ready()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        return (world, await world.LockedManifest());
    }

    private static string[] Codes(ImportVerdict verdict) => [.. verdict.Refusals.Select(r => r.Code)];

    [Fact]
    public async Task AManifestTheHostAccepts_IsOk_AndNamesTheLibraryAndBlueprintItWillUse()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();

        CliRun run = await world.Check(manifest);

        Assert.Equal(0, run.Exit);
        ImportVerdict verdict = TransferWorld.Verdict(run);
        Assert.True(verdict.Ok);
        Assert.Empty(verdict.Refusals);
        Assert.Equal("main", verdict.Library);
        Assert.Equal("factorio", verdict.Blueprint);
    }

    [Fact]
    public async Task ACheck_WritesNothing_NoStagingNoInstanceNoLibrary()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();
        string before = File.ReadAllText(world.Target.Sandbox.Paths.LibraryRegistryFile);

        await world.Check(manifest);

        Assert.Empty(world.Staged());
        Assert.Empty(world.Target.Events());
        Assert.False(File.Exists(world.Target.Sandbox.Paths.InstanceRegistryFile));
        Assert.Equal(before, File.ReadAllText(world.Target.Sandbox.Paths.LibraryRegistryFile));
    }

    [Fact]
    public async Task AnEngineOnAnotherVersion_IsRefusedWith60_ExactlyAndInBothDirections()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();

        foreach (string version in new[] { "9.9.9", Journal.EngineVersion.Current + ".1", "4.0.0-dev.0" })
        {
            world.Target.Session.EngineVersion = version;
            CliRun run = await world.Check(manifest);
            Assert.Equal(60, run.Exit);
            Assert.Equal(["engine_version_mismatch"], Codes(TransferWorld.Verdict(run)));
        }

        world.Target.Session.EngineVersion = Journal.EngineVersion.Current;
        Assert.Equal(0, (await world.Check(manifest)).Exit);
    }

    [Fact]
    public async Task EveryRefusalIsListed_AndTheFirstOneDecidesTheExitCode()
    {
        var world = TransferWorld.Create();
        world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        world.Target.Session.EngineVersion = "9.9.9";
        world.Target.Session.Requirements = new FakeRequirements();
        world.Target.Session.Images.Free = 1;
        world.Target.AddInstance("other-1", "vrising", shape: c => c with { Runtime = BlueprintRuntime.Container, Ports = "9870:9880/udp" });
        File.Delete(Path.Combine(world.Target.Sandbox.Paths.SystemBlueprintsDirectory, "vrising.bp.yaml"));

        CliRun run = await world.Check(manifest);

        ImportVerdict verdict = TransferWorld.Verdict(run);
        Assert.False(verdict.Ok);
        Assert.Equal(
            ["engine_version_mismatch", "requirement_missing", "blueprint_missing", "insufficient_disk", "port_conflict"],
            Codes(verdict));
        Assert.Equal(60, run.Exit);
        Assert.Equal([60, 61, 1, 56, 62], verdict.Refusals.Select(r => r.ExitCode));
        Assert.Equal(string.Empty, run.Err);
    }

    [Fact]
    public async Task ARequirementTheHostLacks_IsRefusedWith61()
    {
        var world = TransferWorld.Create();
        world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");
        world.Target.Session.Requirements = new FakeRequirements();

        CliRun run = await world.Check(manifest);

        Assert.Equal(61, run.Exit);
        Assert.Contains("container-runtime", TransferWorld.Verdict(run).Refusals[0].Detail, StringComparison.Ordinal);
    }

    [Fact]
    public async Task APortThatOverlapsAnotherInstanceOnTheSameProtocol_IsRefusedWith62_AndOnlyThen()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();
        world.Target.AddInstance("other-1", "factorio", shape: c => c with { Ports = "34197/udp" });
        Assert.Equal(0, (await world.Check(manifest)).Exit);

        world.Target.AddInstance("other-2", "factorio", shape: c => c with { Ports = "34190:34200/tcp" });
        CliRun run = await world.Check(manifest);

        Assert.Equal(62, run.Exit);
        ImportRefusal refusal = Assert.Single(TransferWorld.Verdict(run).Refusals);
        Assert.Contains("other-2", refusal.Detail, StringComparison.Ordinal);
    }

    [Fact]
    public async Task TooLittleRoomInTheLibrary_IsRefusedWith56()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();
        TransferManifest huge = manifest with { Parts = [manifest.Parts[0] with { Bytes = long.MaxValue / 4 }] };

        CliRun run = await world.Check(huge);

        Assert.Equal(56, run.Exit);
        Assert.Contains("Library 'main'", TransferWorld.Verdict(run).Refusals[0].Detail, StringComparison.Ordinal);
    }

    [Fact]
    public async Task TooLittleRoomForTheImages_IsRefusedWith56_AndAnUnmeasurableRuntimeIsNotARefusal()
    {
        var world = TransferWorld.Create();
        world.AddContainer();
        TransferManifest manifest = await world.LockedManifest("vr-1");

        world.Target.Session.Images.Free = null;
        Assert.Equal(0, (await world.Check(manifest)).Exit);

        world.Target.Session.Images.Free = 100;
        CliRun run = await world.Check(manifest);
        Assert.Equal(56, run.Exit);
        Assert.Contains("container runtime", TransferWorld.Verdict(run).Refusals[0].Detail, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ALibraryThatIsNotRegistered_Offline_OrOverlappingTheRegistry_IsRefused()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();

        Assert.Equal(["library_not_found"], Codes(TransferWorld.Verdict(await world.Check(manifest, "--library", "nope"))));

        world.Target.Sandbox.AddLibrary("second");
        CliRun several = await world.Check(manifest);
        Assert.Equal(["library_not_found"], Codes(TransferWorld.Verdict(several)));
        Assert.Contains("none was chosen", TransferWorld.Verdict(several).Refusals[0].Detail, StringComparison.Ordinal);
        Assert.Equal(0, (await world.Check(manifest, "--library", "second")).Exit);

        File.Delete(Path.Combine(world.Target.Sandbox.Root, "libraries", "second", ".kgsm-library"));
        Assert.Equal(["library_offline"], Codes(TransferWorld.Verdict(await world.Check(manifest, "--library", "second"))));

        world.Target.Sandbox.AddLibrary("inside", Path.Combine(world.Target.Sandbox.Paths.DataDirectory, "libs"));
        Assert.Equal(["library_overlaps_registry"], Codes(TransferWorld.Verdict(await world.Check(manifest, "--library", "inside"))));
    }

    [Fact]
    public async Task AHostWithNoLibrary_RefusesRatherThanSeedingOne()
    {
        var world = TransferWorld.Create();
        world.AddNative();
        TransferManifest manifest = await world.LockedManifest();
        File.Delete(world.Target.Sandbox.Paths.LibraryRegistryFile);

        CliRun run = await world.Check(manifest);

        Assert.Equal(["library_not_found"], Codes(TransferWorld.Verdict(run)));
        Assert.False(File.Exists(world.Target.Sandbox.Paths.LibraryRegistryFile));
    }

    [Fact]
    public async Task ADefaultBlueprintTheHostLacks_IsRefused()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();
        File.Delete(Path.Combine(world.Target.Sandbox.Paths.SystemBlueprintsDirectory, "factorio.bp.yaml"));

        CliRun run = await world.Check(manifest);

        Assert.Equal(["blueprint_missing"], Codes(TransferWorld.Verdict(run)));
        Assert.Equal(1, run.Exit);
    }

    [Fact]
    public async Task ACustomBlueprint_IsInstalled_WhenAbsent_UsedWhenIdentical_AndCollidesWhenDifferent()
    {
        var world = TransferWorld.Create();
        world.AddCustom();
        TransferManifest manifest = await world.LockedManifest("my-1");

        ImportVerdict absent = TransferWorld.Verdict(await world.Check(manifest));
        Assert.True(absent.Ok);
        Assert.Equal("mygame", absent.Blueprint);

        TransferWorld.WriteCustomBlueprint(world.Target, "mygame");
        Assert.True(TransferWorld.Verdict(await world.Check(manifest)).Ok);

        TransferWorld.WriteCustomBlueprint(world.Target, "mygame", comment: "\n# a different file\n");
        CliRun collision = await world.Check(manifest);
        Assert.Equal(["blueprint_collision"], Codes(TransferWorld.Verdict(collision)));
        Assert.Contains("--blueprint-suffix", TransferWorld.Verdict(collision).Refusals[0].Detail, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ACollidingBlueprint_WithASuffix_IsAcceptedAsNameDashSuffix_AndAnEarlierCopyIsRecognised()
    {
        var world = TransferWorld.Create();
        world.AddCustom();
        TransferManifest manifest = await world.LockedManifest("my-1");
        TransferWorld.WriteCustomBlueprint(world.Target, "mygame", comment: "\n# a different file\n");

        ImportVerdict suffixed = TransferWorld.Verdict(await world.Check(manifest, "--blueprint-suffix", "v2"));
        Assert.True(suffixed.Ok);
        Assert.Equal("mygame-v2", suffixed.Blueprint);

        // A copy an earlier transfer made: the travelling file with the suffix on its name.
        string travelling = File.ReadAllText(Path.Combine(world.Source.Sandbox.Paths.UserBlueprintsDirectory, "mygame.bp.yaml"));
        world.Target.Sandbox.WriteFile(Path.Combine(world.Target.Sandbox.Paths.UserBlueprintsDirectory, "mygame-v2.bp.yaml"), travelling.Replace("name: mygame", "name: mygame-v2", StringComparison.Ordinal));
        Assert.True(TransferWorld.Verdict(await world.Check(manifest, "--blueprint-suffix", "v2")).Ok);

        world.Target.Sandbox.WriteFile(Path.Combine(world.Target.Sandbox.Paths.UserBlueprintsDirectory, "mygame-v2.bp.yaml"), travelling.Replace("name: mygame", "name: mygame-v2", StringComparison.Ordinal) + "\n# edited\n");
        Assert.Equal(["blueprint_collision"], Codes(TransferWorld.Verdict(await world.Check(manifest, "--blueprint-suffix", "v2"))));
    }

    [Fact]
    public async Task ASuffixThatIsNotALowercaseName_IsRefused()
    {
        var world = TransferWorld.Create();
        world.AddCustom();
        TransferManifest manifest = await world.LockedManifest("my-1");
        TransferWorld.WriteCustomBlueprint(world.Target, "mygame", comment: "\n# different\n");

        CliRun run = await world.Check(manifest, "--blueprint-suffix", "Bad Suffix");

        Assert.Equal(["invalid_suffix"], Codes(TransferWorld.Verdict(run)));
    }

    [Fact]
    public async Task AManifestThatIsNotOne_IsRefusedAsInvalid_WhateverIsWrongWithIt()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();

        TransferManifest[] broken =
        [
            manifest with { SchemaVersion = 2 },
            manifest with { Instance = manifest.Instance with { Id = "../x" } },
            manifest with { Blueprint = manifest.Blueprint with { Name = "../x" } },
            manifest with { Parts = [] },
            manifest with { Parts = [manifest.Parts[0], manifest.Parts[0]] },
            manifest with { Parts = [manifest.Parts[0], new TransferPart { Id = "image-1", Kind = TransferPartKind.Image, Bytes = 1 }] },
            manifest with { Parts = [manifest.Parts[0] with { Files = null }] },
        ];

        foreach (TransferManifest candidate in broken)
        {
            CliRun run = await world.Check(candidate);
            Assert.Equal(["invalid_manifest"], Codes(TransferWorld.Verdict(run)));
            Assert.Equal(1, run.Exit);
        }
    }

    [Fact]
    public async Task StandardInputThatIsNotJson_IsRefusedAsAnInvalidManifest_WithAVerdictOnStdout()
    {
        var world = TransferWorld.Create();
        world.Target.Session.Stdin = new StringReader("not json");

        CliRun run = await world.Target.Run("transfer", "import", "check", "--json");

        Assert.Equal(1, run.Exit);
        Assert.Equal(["invalid_manifest"], Codes(TransferWorld.Verdict(run)));
    }

    [Fact]
    public async Task InTextMode_ARefusalIsStillPrintedOnStdout()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();
        world.Target.Session.EngineVersion = "9.9.9";
        world.Target.Session.Stdin = new StringReader(TransferWorld.Write(manifest));

        CliRun run = await world.Target.Run("transfer", "import", "check");

        Assert.Equal(60, run.Exit);
        Assert.Contains("engine_version_mismatch", run.Out, StringComparison.Ordinal);
    }

    [Fact]
    public async Task APortSpecWithTcpAndUdpEntries_ComparesPerProtocol()
    {
        (TransferWorld world, TransferManifest manifest) = await Ready();
        TransferManifest both = manifest with
        {
            Instance = manifest.Instance with
            {
                Ports =
                [
                    new PortRange { Start = 5000, End = 5001, Protocol = PortProtocol.Udp },
                    new PortRange { Start = 5000, End = 5001, Protocol = PortProtocol.Tcp },
                ],
            },
        };
        world.Target.AddInstance("other-1", "factorio", shape: c => c with { Ports = "5001/tcp" });

        ImportVerdict verdict = TransferWorld.Verdict(await world.Check(both));

        ImportRefusal refusal = Assert.Single(verdict.Refusals);
        Assert.Contains("5000-5001/tcp", refusal.Detail, StringComparison.Ordinal);
    }
}
