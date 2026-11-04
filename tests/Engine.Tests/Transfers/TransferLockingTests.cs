using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;
using TheKrystalShip.KGSM.Engine.Tests.Operations;
using TheKrystalShip.KGSM.Engine.Transfers;

namespace TheKrystalShip.KGSM.Engine.Tests.Transfers;

/// <summary>Unlocking restores autostart; enabling and disabling it write their facts; a blueprint's name is rewritten as text.</summary>
public class TransferLockingTests
{
    [Fact]
    public async Task Unlock_ReleasesTheLock_AndRestoresTheAutostartTheLockSwitchedOff()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        (var instance, _) = world.AddNative();
        await world.LockedManifest();
        Assert.DoesNotContain("fx-1", world.Source.Session.Watchdog.Autostart);

        CliRun run = await world.Source.Run("instance", "unlock", "fx-1", "--lock", TransferWorld.Token);

        Assert.Equal(0, run.Exit);
        Assert.Null(TransferLock.Holder(instance.Layout));
        Assert.Contains("fx-1", world.Source.Session.Watchdog.Autostart);
    }

    [Fact]
    public async Task Unlock_WithoutAToken_ReleasesWhoeverHoldsTheLock()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        (var instance, _) = world.AddNative();
        await world.LockedManifest();

        CliRun run = await world.Source.Run("instance", "unlock", "fx-1");

        Assert.Equal(0, run.Exit);
        Assert.Null(TransferLock.Holder(instance.Layout));
        Assert.Contains("fx-1", world.Source.Session.Watchdog.Autostart);
    }

    [Fact]
    public async Task Unlock_WithAnotherTokensLock_IsRefusedWith59_AndChangesNothing()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        (var instance, _) = world.AddNative();
        await world.LockedManifest();

        CliRun run = await world.Source.Run("instance", "unlock", "fx-1", "--lock", "someone-else");

        Assert.Equal(59, run.Exit);
        Assert.Equal(TransferWorld.Token, TransferLock.Holder(instance.Layout));
        Assert.DoesNotContain("fx-1", world.Source.Session.Watchdog.Autostart);
    }

    [Fact]
    public async Task Unlock_WhenAutostartCannotBeRestored_KeepsTheLock_SoItCanBeReleasedAgain()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.Source.Session.Watchdog.Autostart.Add("fx-1");
        (var instance, _) = world.AddNative();
        await world.LockedManifest();
        world.Source.Session.Watchdog.RefuseEnable = true;

        CliRun failed = await world.Source.Run("instance", "unlock", "fx-1");

        Assert.Equal(1, failed.Exit);
        Assert.Equal(TransferWorld.Token, TransferLock.Holder(instance.Layout));

        world.Source.Session.Watchdog.RefuseEnable = false;
        Assert.Equal(0, (await world.Source.Run("instance", "unlock", "fx-1")).Exit);
        Assert.Contains("fx-1", world.Source.Session.Watchdog.Autostart);
    }

    [Fact]
    public async Task Unlock_OfALockThatRecordedNoAutostart_RestoresNothing()
    {
        var world = TransferWorld.Create();
        world.Source.Session.Watchdog.SocketPresent = true;
        world.AddNative();
        await world.LockedManifest();

        Assert.Equal(0, (await world.Source.Run("instance", "unlock", "fx-1")).Exit);

        Assert.DoesNotContain("enable fx-1", world.Source.Session.Watchdog.Actions);
    }

    [Fact]
    public async Task Unlock_OfALockFileThatCannotBeRead_StillReleases()
    {
        var world = TransferWorld.Create();
        (var instance, _) = world.AddNative();
        File.WriteAllText(instance.Layout.TransferLockFile, "token-1\n");

        Assert.Equal("(unreadable)", TransferLock.Holder(instance.Layout));
        CliRun run = await world.Source.Run("instance", "unlock", "fx-1");

        Assert.Equal(0, run.Exit);
        Assert.Null(TransferLock.Holder(instance.Layout));
    }

    [Fact]
    public async Task Unlock_OfAnInstanceThatWasNotLocked_SaysSo()
    {
        var world = TransferWorld.Create();
        world.AddNative();

        CliRun run = await world.Source.Run("instance", "unlock", "fx-1");

        Assert.Equal(0, run.Exit);
        Assert.Contains("was not locked", run.Out, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ALockRefusesStartMoveUpdateAndConfigChanges_WithExit59()
    {
        var world = TransferWorld.Create();
        world.Source.Sandbox.AddLibrary("second");
        world.AddNative();
        await world.LockedManifest();

        Assert.Equal(59, (await world.Source.Run("instance", "start", "fx-1")).Exit);
        Assert.Equal(59, (await world.Source.Run("instance", "move", "fx-1", "second")).Exit);
        Assert.Equal(59, (await world.Source.Run("instance", "update", "fx-1")).Exit);
        Assert.Equal(59, (await world.Source.Run("instance", "config", "set", "fx-1", "backupRetention", "5")).Exit);
        Assert.Equal(59, (await world.Source.Run("backup", "create", "fx-1")).Exit);
    }

    [Fact]
    public async Task Enable_AndDisable_WriteTheirFacts_AfterTheWatchdogAgreed()
    {
        var fx = OpsFixture.Create();
        fx.Session.Watchdog.SocketPresent = true;
        fx.AddInstance();

        Assert.Equal(0, (await fx.Run("instance", "enable", "g-1")).Exit);
        Assert.Equal(0, (await fx.Run("instance", "disable", "g-1")).Exit);

        Assert.Equal(["server.autostart.enabled", "server.autostart.disabled"], fx.Events());
    }

    [Fact]
    public async Task Enable_WhenTheWatchdogRefuses_WritesNoFact()
    {
        var fx = OpsFixture.Create();
        fx.Session.Watchdog.SocketPresent = true;
        fx.Session.Watchdog.RefuseEnable = true;
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "enable", "g-1");

        Assert.Equal(1, run.Exit);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public void ABlueprintsNameIsRewrittenAsText_WhateverItsQuoting_AndNothingElseChanges()
    {
        const string Text = "schema_version: 1\nname: mygame   # the key\nruntime: native\nmetadata:\n  name: inner\n";

        string added = BlueprintNames.AddSuffix(Text, "v2");

        Assert.Equal("schema_version: 1\nname: mygame-v2   # the key\nruntime: native\nmetadata:\n  name: inner\n", added);
        Assert.Equal(Text, BlueprintNames.StripSuffix(added, "v2"));
        Assert.Equal("name: \"a-v2\"\n", BlueprintNames.AddSuffix("name: \"a\"\n", "v2"));
        Assert.Equal("name: 'a-v2'\r\nx: 1\r\n", BlueprintNames.AddSuffix("name: 'a'\r\nx: 1\r\n", "v2"));
        Assert.Equal("name: a\n", BlueprintNames.StripSuffix("name: a\n", "v2"));
        Assert.Equal("no name here\n", BlueprintNames.AddSuffix("no name here\n", "v2"));
        Assert.Equal("mygame", BlueprintNames.NameOf(Text));
        Assert.Null(BlueprintNames.NameOf("x: 1"));
    }

    [Theory]
    [InlineData("v2", true)]
    [InlineData("a.b_c-1", true)]
    [InlineData("0x", true)]
    [InlineData("V2", false)]
    [InlineData("-v", false)]
    [InlineData("a b", false)]
    [InlineData("", false)]
    public void ASuffixIsALowercaseName(string suffix, bool valid) => Assert.Equal(valid, BlueprintNames.IsValidSuffix(suffix));
}
