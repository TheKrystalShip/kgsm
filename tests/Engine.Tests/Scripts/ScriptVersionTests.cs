using System.Text.RegularExpressions;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>Installed and latest versions, the latest-version record, the three-outcome check and Steam credentials.</summary>
public partial class ScriptVersionTests
{
    private static ScriptWorld SteamWorld(Func<Contracts.Instances.InstanceConfig, Contracts.Instances.InstanceConfig>? shape = null)
    {
        ScriptWorld world = ScriptWorld.Native(c => (shape ?? (x => x))(c with { SteamAppId = 1234 }));
        world.Script("steam/buildid", "500\n");
        return world;
    }

    // --- the installed version ---

    [Fact]
    public async Task TheInstalledVersion_IsUnknown_WhenNoneIsRecorded_SpelledOneWay()
    {
        // Unknown has one spelling in both runtimes and in status.
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("version");

        Assert.Equal(0, run.Exit);
        Assert.Equal("unknown\n", run.Out);
    }

    [Fact]
    public async Task SaveThenVersion_RoundTripsTheInstalledVersion()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(0, (await world.RunAsync("version", "--save", "1.2.3")).Exit);

        Assert.Equal("1.2.3\n", (await world.RunAsync("version")).Out);
        Assert.Equal("1.2.3\n", File.ReadAllText(world.VersionFile));
    }

    [Fact]
    public async Task Save_WithNoVersion_IsAMissingArgument()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(7, (await world.RunAsync("version", "--save")).Exit);
    }

    [Fact]
    public async Task AnUnknownVersionOption_IsAnInvalidArgument()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(8, (await world.RunAsync("version", "--bogus")).Exit);
    }

    // --- the latest-version record ---

    [Fact]
    public async Task TheLatestVersionRecord_IsTwoLines_TheVersionAndTheMomentItWasFetched()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(0, (await world.RunAsync("version", "--save-latest", "777")).Exit);

        string[] lines = File.ReadAllLines(world.LatestFile);
        Assert.Equal(2, lines.Length);
        Assert.Equal("777", lines[0]);
        Assert.Matches(IsoUtc(), lines[1]);
        Assert.Equal("777\n", (await world.RunAsync("version", "--stored-latest")).Out);
        Assert.Equal(lines[1] + "\n", (await world.RunAsync("version", "--stored-checked-at")).Out);
    }

    [Fact]
    public async Task WithNoRecord_TheStoredLatestAndItsTimeAreEmpty()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(string.Empty, (await world.RunAsync("version", "--stored-latest")).Out);
        Assert.Equal(string.Empty, (await world.RunAsync("version", "--stored-checked-at")).Out);
    }

    [Fact]
    public async Task ARecordedVersionWithNoTime_HasNoCheckedAt_NeverANowInItsPlace()
    {
        using ScriptWorld world = ScriptWorld.Native();
        File.WriteAllText(world.LatestFile, "777\n");

        Assert.Equal("777\n", (await world.RunAsync("version", "--stored-latest")).Out);
        Assert.Equal(string.Empty, (await world.RunAsync("version", "--stored-checked-at")).Out);
    }

    [Fact]
    public async Task SaveLatest_RefusesAnEmptyVersion()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("version", "--save-latest", "");

        Assert.Equal(7, run.Exit);
        Assert.False(File.Exists(world.LatestFile));
    }

    [Fact]
    public async Task CheckingForUpdates_WritesNoRecord_OnlyTheEngineRecordsAFetch()
    {
        using ScriptWorld world = SteamWorld();

        await world.RunAsync("check-update");

        Assert.False(File.Exists(world.LatestFile));
    }

    // --- the three outcomes ---

    [Fact]
    public async Task CheckUpdate_ReportsAnAvailableUpdate_WithTheLatestVersion()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "400\n");

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(0, run.Exit);
        Assert.Equal("available 500\n", run.Out);
    }

    [Fact]
    public async Task CheckUpdate_ReportsUpToDate_WhenTheVersionsMatch()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "500\n");

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(0, run.Exit);
        Assert.Equal("current 500\n", run.Out);
    }

    [Fact]
    public async Task CheckUpdate_ReportsUnknown_WithItsOwnExitStatus_WhenUpstreamDoesNotAnswer()
    {
        // "Already current" and "could not ask" must never share an exit status.
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "500\n");

        ScriptRun answered = await world.RunAsync("check-update");
        world.Script("steam/exit", "1\n");
        ScriptRun silent = await world.RunAsync("check-update");

        Assert.Equal(0, answered.Exit);
        Assert.Equal("current 500\n", answered.Out);
        Assert.Equal(1, silent.Exit);
        Assert.Equal("unknown\n", silent.Out);
        Assert.NotEqual(answered.Exit, silent.Exit);
    }

    [Fact]
    public async Task CheckUpdate_ReportsUnknown_WhenSteamcmdReturnsNoBuildId()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "500\n");
        world.Script("steam/no-buildid", "1");

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
        Assert.Contains("no build id", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task CheckUpdate_TreatsAnUnknownInstalledVersionAsAnAvailableUpdate_NeverAsCurrent()
    {
        using ScriptWorld world = SteamWorld();

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal("available 500\n", run.Out);
    }

    [Fact]
    public async Task VersionCompare_AnswersTheSameThreeOutcomes()
    {
        using ScriptWorld world = SteamWorld();
        File.WriteAllText(world.VersionFile, "400\n");

        Assert.Equal("available 500\n", (await world.RunAsync("version", "--compare")).Out);
        File.WriteAllText(world.VersionFile, "500\n");
        Assert.Equal("current 500\n", (await world.RunAsync("version", "--compare")).Out);
        world.Script("steam/exit", "1\n");
        ScriptRun unknown = await world.RunAsync("version", "--compare");
        Assert.Equal(1, unknown.Exit);
        Assert.Equal("unknown\n", unknown.Out);
    }

    [Fact]
    public async Task VersionLatest_PrintsTheBuildIdOfThePublicBranch()
    {
        using ScriptWorld world = SteamWorld();

        ScriptRun run = await world.RunAsync("version", "--latest");

        Assert.Equal(0, run.Exit);
        Assert.Equal("500\n", run.Out);
        Assert.Equal(["+login", "anonymous", "+app_info_update", "1", "+app_info_print", "1234", "+quit"], world.Calls("steam/log").Single());
    }

    [Fact]
    public async Task WithNoSteamAppIdAndNoHook_TheLatestVersionIsUnknown_AndSteamcmdIsNeverAsked()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
        Assert.Empty(world.Recorded("steam/log"));
    }

    // --- Steam credentials ---

    [Fact]
    public async Task AnAccountGatedApp_LogsInWithTheEnvironmentsCredentials()
    {
        using ScriptWorld world = SteamWorld(c => c with { IsSteamAccountRequired = true });
        world.Environment["STEAM_USERNAME"] = "alice";
        world.Environment["STEAM_PASSWORD"] = "hunter2";

        await world.RunAsync("version", "--latest");

        Assert.Equal(["+login", "alice", "hunter2"], world.Calls("steam/log").Single()[..3]);
    }

    [Fact]
    public async Task APasswordWithSpaces_StaysOneArgument()
    {
        // The login arguments are never word-split, so a password with a space is one argument.
        using ScriptWorld world = SteamWorld(c => c with { IsSteamAccountRequired = true });
        world.Environment["STEAM_USERNAME"] = "alice";
        world.Environment["STEAM_PASSWORD"] = "correct horse  battery";

        await world.RunAsync("version", "--latest");

        Assert.Equal(["+login", "alice", "correct horse  battery", "+app_info_update"], world.Calls("steam/log").Single()[..4]);
    }

    [Fact]
    public async Task AUsernameAlone_SpendsTheStoredRefreshToken()
    {
        using ScriptWorld world = SteamWorld(c => c with { IsSteamAccountRequired = true });
        world.Environment["STEAM_USERNAME"] = "alice";

        await world.RunAsync("version", "--latest");

        Assert.Equal(["+login", "alice", "+app_info_update"], world.Calls("steam/log").Single()[..3]);
    }

    [Fact]
    public async Task WithNoCredentialsInTheEnvironment_TheyAreReadFromTheCredentialsFile()
    {
        using ScriptWorld world = SteamWorld(c => c with { IsSteamAccountRequired = true });
        File.WriteAllText(world.EnvFile, "# the engine's credentials\nSTEAM_USERNAME=\"bob\"\nexport STEAM_PASSWORD='p w'\nOTHER=x\n");

        await world.RunAsync("version", "--latest");

        Assert.Equal(["+login", "bob", "p w", "+app_info_update"], world.Calls("steam/log").Single()[..4]);
    }

    [Fact]
    public async Task TheEnvironmentWinsOverTheCredentialsFile()
    {
        using ScriptWorld world = SteamWorld(c => c with { IsSteamAccountRequired = true });
        File.WriteAllText(world.EnvFile, "STEAM_USERNAME=bob\nSTEAM_PASSWORD=file\n");
        world.Environment["STEAM_USERNAME"] = "alice";

        await world.RunAsync("version", "--latest");

        Assert.Equal(["+login", "alice", "file"], world.Calls("steam/log").Single()[..3]);
    }

    [Fact]
    public async Task AnAccountGatedApp_WithNoUsername_FailsWithoutCallingSteamcmd()
    {
        using ScriptWorld world = SteamWorld(c => c with { IsSteamAccountRequired = true });

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
        Assert.Contains("STEAM_USERNAME", run.Err, StringComparison.Ordinal);
        Assert.Empty(world.Recorded("steam/log"));
    }

    [Fact]
    public async Task AnAppThatNeedsNoAccount_LogsInAnonymously_WhateverTheEnvironmentHolds()
    {
        using ScriptWorld world = SteamWorld();
        world.Environment["STEAM_USERNAME"] = "alice";

        await world.RunAsync("version", "--latest");

        Assert.Equal("anonymous", world.Calls("steam/log").Single()[1]);
    }

    [Fact]
    public async Task ACredentialsFileIsReadNeverSourced()
    {
        using ScriptWorld world = SteamWorld(c => c with { IsSteamAccountRequired = true });
        string marker = Path.Combine(world.Sandbox.Root, "sourced");
        File.WriteAllText(world.EnvFile, $"STEAM_USERNAME=bob\n$(touch {marker})\ntouch {marker}\n");

        await world.RunAsync("version", "--latest");

        Assert.False(File.Exists(marker));
        Assert.Equal("bob", world.Calls("steam/log").Single()[1]);
    }

    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")]
    private static partial Regex IsoUtc();
}
