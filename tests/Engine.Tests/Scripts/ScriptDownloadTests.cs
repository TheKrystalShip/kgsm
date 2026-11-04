namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>Download, deploy and update of a native Steam instance.</summary>
public class ScriptDownloadTests
{
    private static ScriptWorld SteamWorld(Func<Contracts.Instances.InstanceConfig, Contracts.Instances.InstanceConfig>? shape = null)
    {
        ScriptWorld world = ScriptWorld.Native(c => (shape ?? (x => x))(c with { SteamAppId = 1234 }));
        world.Script("steam/buildid", "500\n");
        return world;
    }

    private static string Staging(ScriptWorld world) => Path.Combine(world.Temp, "download");

    // --- download ---

    [Fact]
    public async Task Download_RunsSteamcmdIntoTheStagingDirectory_ThenChecksForGameFiles()
    {
        using ScriptWorld world = SteamWorld(c => c with { SteamcmdArguments = "-beta experimental -betapassword x" });

        ScriptRun run = await world.RunAsync("download");

        Assert.Equal(0, run.Exit);
        Assert.Equal(
            ["+@sSteamCmdForcePlatformType", "linux", "+force_install_dir", Staging(world), "+login", "anonymous", "+app_update", "1234",
                "-beta", "experimental", "-betapassword", "x", "validate", "+quit"],
            world.Calls("steam/log").Single());
        Assert.True(File.Exists(Path.Combine(Staging(world), "game.bin")));
    }

    [Fact]
    public async Task Download_FailsWhenSteamcmdReportsSuccessButLeavesNoGameFiles()
    {
        using ScriptWorld world = SteamWorld();
        world.Script("steam/empty", "1");

        ScriptRun run = await world.RunAsync("download");

        Assert.Equal(1, run.Exit);
        Assert.Contains("downloaded no game files", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Download_FailsWhenSteamcmdFails()
    {
        using ScriptWorld world = SteamWorld();
        world.Script("steam/exit", "3\n");

        ScriptRun run = await world.RunAsync("download");

        Assert.Equal(1, run.Exit);
        Assert.Contains("exited non-zero", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Download_ClearsWhatAnEarlierDownloadLeftBehind()
    {
        using ScriptWorld world = SteamWorld();
        Directory.CreateDirectory(Staging(world));
        File.WriteAllText(Path.Combine(Staging(world), "stale.txt"), "old");

        Assert.Equal(0, (await world.RunAsync("download")).Exit);

        Assert.False(File.Exists(Path.Combine(Staging(world), "stale.txt")));
    }

    [Fact]
    public async Task Download_OfASpecificVersion_WarnsThatSteamServesOnlyTheLatest()
    {
        using ScriptWorld world = SteamWorld();

        ScriptRun run = await world.RunAsync("download", "123");

        Assert.Equal(0, run.Exit);
        Assert.Contains("ignored", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Download_WithNoSteamAppIdAndNoHook_FailsClearly()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("download");

        Assert.Equal(1, run.Exit);
        Assert.Contains("no Steam app id", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Download_RefusesAnOption_ItDoesNotKnow()
    {
        using ScriptWorld world = SteamWorld();

        Assert.Equal(8, (await world.RunAsync("download", "--now")).Exit);
    }

    // --- deploy ---

    [Fact]
    public async Task Deploy_CopiesTheStagedFilesIntoInstall_DotfilesIncluded_ThenClearsStaging()
    {
        // A deploy copies hidden files too, which a shell glob would leave out.
        using ScriptWorld world = SteamWorld();
        Directory.CreateDirectory(Path.Combine(Staging(world), "sub"));
        File.WriteAllText(Path.Combine(Staging(world), "a.txt"), "a");
        File.WriteAllText(Path.Combine(Staging(world), ".hidden"), "h");
        File.WriteAllText(Path.Combine(Staging(world), "sub", "b.txt"), "b");

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(0, run.Exit);
        Assert.Equal("a", File.ReadAllText(Path.Combine(world.Install, "a.txt")));
        Assert.Equal("h", File.ReadAllText(Path.Combine(world.Install, ".hidden")));
        Assert.Equal("b", File.ReadAllText(Path.Combine(world.Install, "sub", "b.txt")));
        Assert.Empty(Directory.GetFileSystemEntries(Staging(world)));
    }

    [Fact]
    public async Task Deploy_FailsWhenNothingIsStaged()
    {
        using ScriptWorld world = SteamWorld();

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(1, run.Exit);
        Assert.Contains("nothing to deploy", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Deploy_NeverTakesABackupInProgressForDownloadedGameFiles()
    {
        // A backup stages beside its final place and a download in the temp directory's own staging
        // directory, so neither is mistaken for the other.
        using ScriptWorld world = SteamWorld();
        string partial = Path.Combine(world.Temp, "g-1-20260101T000000Z-abcdef.partial");
        Directory.CreateDirectory(partial);
        File.WriteAllText(Path.Combine(partial, "data.tar.gz"), "half a backup");

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(1, run.Exit);
        Assert.False(File.Exists(Path.Combine(world.Install, "data.tar.gz")));
        Assert.True(File.Exists(Path.Combine(partial, "data.tar.gz")));
    }

    [Fact]
    public async Task Deploy_CreatesTheInstallDirectory_WhenItIsMissing()
    {
        using ScriptWorld world = SteamWorld();
        Directory.Delete(world.Install, recursive: true);
        Directory.CreateDirectory(Staging(world));
        File.WriteAllText(Path.Combine(Staging(world), "a.txt"), "a");

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        Assert.True(File.Exists(Path.Combine(world.Install, "a.txt")));
    }

    // --- update ---

    [Fact]
    public async Task Update_OfAnInstanceThatIsAlreadyCurrent_ChangesNothingAndSaysSo()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "500\n");

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(0, run.Exit);
        Assert.Equal("current 500\n", run.Out);
        Assert.False(Directory.Exists(world.BackupsDirectory));
        Assert.Single(world.Calls("steam/log"));
    }

    [Fact]
    public async Task Update_TakesAPreUpdateBackup_Downloads_Deploys_AndRecordsTheVersion()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "400\n");
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "precious");

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(0, run.Exit);
        Assert.Equal("updated 500\n", run.Out);
        Assert.Equal("500", File.ReadAllText(world.VersionFile).Trim());
        Assert.True(File.Exists(Path.Combine(world.Install, "game.bin")));

        string backup = Assert.Single(Directory.GetDirectories(world.BackupsDirectory));
        Contracts.Backups.BackupManifest manifest = ScriptJson.Manifest(world, Path.GetFileName(backup));
        Assert.Equal(Contracts.Backups.BackupReason.PreUpdate, manifest.Reason);
        Assert.Equal("400", manifest.Version);
        Assert.Equal(Contracts.Backups.BackupConsistency.Cold, manifest.Consistency);
    }

    [Fact]
    public async Task Update_RefusesWhileTheGameRuns_BeforeAskingUpstreamAnything()
    {
        using ScriptWorld world = SteamWorld();
        await world.StartGameAsync();

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(1, run.Exit);
        Assert.Contains("stop it before updating", run.Err, StringComparison.Ordinal);
        Assert.Empty(world.Recorded("steam/log"));
    }

    [Fact]
    public async Task Update_RefusesWhenTheCallerSaysTheInstanceRuns_WhateverTheScriptCanSee()
    {
        using ScriptWorld world = SteamWorld();

        ScriptRun run = await world.RunAsync("update", "--run-state", "active");

        Assert.Equal(1, run.Exit);
        Assert.Empty(world.Recorded("steam/log"));
    }

    [Fact]
    public async Task Update_RefusesARunStateItDoesNotKnow()
    {
        using ScriptWorld world = SteamWorld();

        Assert.Equal(8, (await world.RunAsync("update", "--run-state", "maybe")).Exit);
    }

    [Fact]
    public async Task Update_WhenUpstreamDoesNotAnswer_FailsAndTouchesNothing()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "400\n");
        world.Script("steam/no-buildid", "1");

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("400", File.ReadAllText(world.VersionFile).Trim());
        Assert.False(Directory.Exists(world.BackupsDirectory));
    }

    [Fact]
    public async Task Update_AbandonsTheUpdate_WhenTheBackupBeforeItFails()
    {
        using ScriptWorld world = SteamWorld();
        string blocker = Path.Combine(world.Sandbox.Root, "a-file");
        File.WriteAllText(blocker, "not a directory");
        world.Reconfigure(c => c with { BackupsDirectory = Path.Combine(blocker, "backups") });
        File.WriteAllText(world.VersionFile, "400\n");
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "precious");

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(1, run.Exit);
        Assert.Contains("backup before the update failed", run.Err, StringComparison.Ordinal);
        Assert.Equal("400", File.ReadAllText(world.VersionFile).Trim());
        Assert.Single(world.Calls("steam/log"));
    }

    [Fact]
    public async Task Update_ReportsItsPhasesThroughTheEmitCommand_InOrder()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "400\n");
        string emit = WriteEmitter(world);

        ScriptRun run = await world.RunAsync("update", "--emit-cmd", emit);

        Assert.Equal(0, run.Exit);
        Assert.Equal(
            ["server.download.started g-1", "server.download.finished g-1", "server.deploy.started g-1", "server.deploy.finished g-1"],
            world.Recorded("emitted"));
    }

    [Fact]
    public async Task Update_ReportsAFailedDownload_AndFails()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "400\n");
        world.Script("steam/empty", "1");
        string emit = WriteEmitter(world);

        ScriptRun run = await world.RunAsync("update", "--emit-cmd", emit);

        Assert.Equal(1, run.Exit);
        Assert.Equal(["server.download.started g-1", "server.download.failed g-1"], world.Recorded("emitted"));
        Assert.Equal("400", File.ReadAllText(world.VersionFile).Trim());
    }

    [Fact]
    public async Task Update_ReportsAFailedDeploy_AndFails()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "400\n");
        // A directory where the downloaded game.bin should land makes the copy fail after a good download.
        Directory.CreateDirectory(Path.Combine(world.Install, "game.bin"));
        File.WriteAllText(Path.Combine(world.Install, "game.bin", "kept"), "x");
        string emit = WriteEmitter(world);

        ScriptRun run = await world.RunAsync("update", "--emit-cmd", emit);

        Assert.Equal(1, run.Exit);
        Assert.Contains("server.deploy.failed g-1", world.Recorded("emitted"));
        Assert.Equal("400", File.ReadAllText(world.VersionFile).Trim());
    }

    [Fact]
    public async Task Update_IsNotFailedByAnEmitCommandThatFails_ButSaysSo()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "400\n");
        string emit = Path.Combine(world.Sandbox.Root, "broken-emitter");
        FakeScripts.Install(world.Sandbox.Root, "broken-emitter", "#!/usr/bin/env bash\necho nope >&2\nexit 3\n");

        ScriptRun run = await world.RunAsync("update", "--emit-cmd", emit);

        Assert.Equal(0, run.Exit);
        Assert.Contains("Could not report phase", run.Err, StringComparison.Ordinal);
        Assert.Equal("500", File.ReadAllText(world.VersionFile).Trim());
    }

    [Fact]
    public async Task Update_RefusesAnArgumentItDoesNotKnow()
    {
        using ScriptWorld world = SteamWorld();

        Assert.Equal(8, (await world.RunAsync("update", "--force")).Exit);
    }

    private static string WriteEmitter(ScriptWorld world)
    {
        FakeScripts.Install(world.Sandbox.Root, "emitter", $"#!/usr/bin/env bash\necho \"$1 $2\" >>\"{world.Fake("emitted")}\"\n");
        return Path.Combine(world.Sandbox.Root, "emitter");
    }
}
