using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

/// <summary><c>kgsm instance install</c>: the order of its steps, its events, its refusals, and its complete rollback.</summary>
public class InstallTests
{
    private static readonly string[] SuccessfulInstall =
    [
        "server.install.started", "server.install.directories_created", "server.install.files_created",
        "server.download.started", "server.download.finished", "server.deploy.started", "server.deploy.finished",
        "server.installed", "server.install.finished",
    ];

    private static InstallReport Report(CliRun run) =>
        JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.InstallReport) ?? throw new InvalidOperationException("null");

    [Fact]
    public async Task Install_RunsItsStepsInOrder_AndLeavesAnInstanceThatIsRegisteredAndReadable()
    {
        var fx = OpsFixture.Create();

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1", "--json");

        Assert.Equal(0, run.Exit);
        InstallReport report = Report(run);
        Assert.Equal("fx-1", report.Id);
        Assert.Equal("1.0.0", report.Version);
        Assert.Equal(["fx-1 version --latest", "fx-1 download 1.0.0", "fx-1 deploy", "fx-1 version --save 1.0.0", "fx-1 version --save-latest 1.0.0"], fx.Script.Calls);
        Assert.Equal(SuccessfulInstall, fx.Events());

        InstanceDescription instance = fx.Find("fx-1");
        Assert.NotNull(instance.Config);
        Assert.Equal("factorio", instance.Config!.Blueprint);
        Assert.Equal(fx.Backups("fx-1"), instance.Config.BackupsDirectory);
        Assert.True(File.Exists(instance.Layout.ManagementScript));
        Assert.True(Directory.Exists(instance.Layout.SavesDirectory));
        Assert.True(Directory.Exists(instance.Config.BackupsDirectory));
        Assert.Equal("1.0.0\n", File.ReadAllText(instance.Layout.VersionFile));
    }

    [Fact]
    public async Task Install_WritesTheBlueprintsValuesAndTheHostsDefaultsIntoTheConfig()
    {
        var fx = OpsFixture.Create();
        fx.Session.Extra["Instances__StopCommandTimeoutSeconds"] = "77";
        fx.Session.Extra["Backups__Compress"] = "false";

        await fx.Run("instance", "install", "factorio", "--id", "fx-1", "--name", "  My\tFactory  ");

        InstanceConfig config = fx.Find("fx-1").Config!;
        Assert.Equal("My\tFactory".Replace("\t", string.Empty, StringComparison.Ordinal), config.DisplayName);
        Assert.Equal("--start-server {savesDir}/{levelName}", config.ExecutableArguments);
        Assert.Equal("34197", config.Ports);
        Assert.Equal(77, config.StopCommandTimeoutSeconds);
        Assert.False(config.CompressBackups);
        Assert.False(config.EnableFirewallManagement);
        Assert.Equal(32, config.InstallNonce.Length);
        Assert.NotNull(config.InstallDatetime);
    }

    [Fact]
    public async Task Install_WithoutAnId_GeneratesOneFromTheBlueprintsName_ThatNoInstanceHas()
    {
        var fx = OpsFixture.Create();

        CliRun first = await fx.Run("instance", "install", "factorio", "--json");
        CliRun second = await fx.Run("instance", "install", "factorio", "--json");

        string a = Report(first).Id;
        string b = Report(second).Id;
        Assert.StartsWith("factorio-", a, StringComparison.Ordinal);
        Assert.StartsWith("factorio-", b, StringComparison.Ordinal);
        Assert.NotEqual(a, b);
    }

    [Fact]
    public async Task Install_ASecondTimeWithTheSameId_IsRefused_BeforeAnythingIsCreated()
    {
        var fx = OpsFixture.Create();
        await fx.Run("instance", "install", "factorio", "--id", "fx-1");
        int events = fx.Events().Count;
        int calls = fx.Script.Calls.Count;

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("already registered", run.Err, StringComparison.Ordinal);
        Assert.Equal(events, fx.Events().Count);
        Assert.Equal(calls, fx.Script.Calls.Count);
    }

    [Theory]
    [InlineData("../escape")]
    [InlineData("-leading")]
    [InlineData("has space")]
    public async Task Install_RefusesAnIdThatIsNotAnId(string id)
    {
        var fx = OpsFixture.Create();

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", id);

        Assert.Equal(1, run.Exit);
        Assert.Contains("is not an instance id", run.Err, StringComparison.Ordinal);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Install_OfABlueprintThatDoesNotExist_IsNotFound_ExitTwentyFive()
    {
        var fx = OpsFixture.Create();

        CliRun run = await fx.Run("instance", "install", "nothing-here");

        Assert.Equal(25, run.Exit);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Install_RefusesWhatTheHostLacks_NamingIt()
    {
        var fx = OpsFixture.Create();
        fx.Session.Requirements = new FakeRequirements();

        CliRun run = await fx.Run("instance", "install", "vrising", "--id", "v-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("container-runtime", run.Err, StringComparison.Ordinal);
        Assert.False(fx.IsRegistered("v-1"));
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Install_SeedsTheFirstLibraryBesideTheDataDirectory_WhenNoneIsRegistered()
    {
        var sandbox = Sandbox.Create();
        var session = new CliSession(sandbox, withBlueprints: true);
        session.Watchdog.SocketPresent = false;
        var script = new ScriptEmulator(session);

        CliRun run = await session.RunAsync("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(0, run.Exit);
        LibraryRecord library = Assert.Single(new LibraryCatalog(sandbox.Paths).Registered());
        Assert.Equal("default", library.Name);
        Assert.Equal(Path.Combine(sandbox.Paths.DataHome, "kgsm-library"), library.Path);
        Assert.True(File.Exists(Path.Combine(library.Path, ".kgsm-library")));
        Assert.Contains("fx-1", string.Join(' ', script.Calls), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Install_WithSeveralLibrariesAndNoChoice_AsksForOne()
    {
        var fx = OpsFixture.Create();
        fx.Sandbox.AddLibrary("second");

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("none is chosen", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Install_IntoAnOfflineLibrary_IsRefused()
    {
        var fx = OpsFixture.Create();
        LibraryRecord away = fx.Sandbox.AddLibrary("away", withMarker: false);

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1", "--library", away.Name);

        Assert.Equal(1, run.Exit);
        Assert.Contains("offline", run.Err, StringComparison.Ordinal);
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Install_WithoutRoom_ExitsFiftySix_AndTheSkipFlagInstallsAnyway()
    {
        var fx = OpsFixture.Create();
        fx.Session.Extra["Libraries__InstallFreeSpaceMarginMb"] = "2000000000";

        CliRun refused = await fx.Run("instance", "install", "factorio", "--id", "fx-1", "--json");
        CliRun skipped = await fx.Run("instance", "install", "factorio", "--id", "fx-1", "--skip-space-check");

        Assert.Equal(56, refused.Exit);
        Assert.Equal(ErrorCodes.InsufficientDisk, JsonSerializer.Deserialize(refused.Err, EngineJsonContext.Default.ErrorReport)!.Code);
        Assert.Equal(0, skipped.Exit);
    }

    [Fact]
    public async Task Install_WhoseJournalCannotBeWritten_IsRefusedBeforeAnythingIsCreated()
    {
        var fx = OpsFixture.Create();
        File.WriteAllText(fx.Sandbox.JournalDirectory, "a file where the journal directory should be");

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("journal", run.Err, StringComparison.Ordinal);
        Assert.False(fx.IsRegistered("fx-1"));
        Assert.Empty(fx.Script.Calls);
    }

    [Fact]
    public async Task Install_OfAContainer_RendersItsComposeFile_AndDeclaresThePortsComposeNames()
    {
        var fx = OpsFixture.Create();

        CliRun run = await fx.Run("instance", "install", "vrising", "--id", "v-1");

        Assert.Equal(0, run.Exit);
        InstanceDescription instance = fx.Find("v-1");
        string compose = File.ReadAllText(instance.Layout.ComposeFile);
        Assert.Contains("container_name: v-1", compose, StringComparison.Ordinal);
        Assert.Contains(instance.Layout.SavesDirectory, compose, StringComparison.Ordinal);
        Assert.DoesNotContain("${instance_", compose, StringComparison.Ordinal);
        Assert.Equal("9876/udp|9877/udp|27015/udp|27016/udp", instance.Config!.Ports);
        Assert.True(Directory.Exists(instance.Layout.EventsDirectory));
    }

    // --- rollback ---

    [Fact]
    public async Task AFailedDownload_RollsBackEverything_AndClosesTheBracket()
    {
        var fx = OpsFixture.Create();
        fx.Script.Failures["download"] = "the server returned 404";

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("404", run.Err, StringComparison.Ordinal);
        AssertNothingRemains(fx, "fx-1");
        Assert.Equal(
            ["server.install.started", "server.install.directories_created", "server.install.files_created", "server.download.started",
             "server.download.failed", "server.install.failed", "server.install.finished"],
            fx.Events());
        Assert.Equal("danger", fx.Journal().Single(l => l.EventType == "server.install.failed").Severity);
    }

    [Fact]
    public async Task ACancelledInstall_RollsBackEverything_AndClosesTheDownloadPhaseItOpened()
    {
        var fx = OpsFixture.Create();
        Func<ProcessCall, ProcessResult> inner = fx.Session.Processes.Handler;
        fx.Session.Processes.Handler = call => call.Arguments[0] == "download" ? throw new OperationCanceledException() : inner(call);

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(130, run.Exit);
        AssertNothingRemains(fx, "fx-1");
        Assert.Equal(
            ["server.install.started", "server.install.directories_created", "server.install.files_created", "server.download.started",
             "server.download.failed", "server.install.failed", "server.install.finished"],
            fx.Events());
    }

    [Fact]
    public async Task AFailedDeploy_RollsBackEverything_TooAndSaysWhichPhaseFailed()
    {
        var fx = OpsFixture.Create();
        fx.Script.Failures["deploy"] = "post-deploy hook failed";

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(1, run.Exit);
        AssertNothingRemains(fx, "fx-1");
        Assert.Contains("server.deploy.failed", fx.Events());
        Assert.Equal("server.install.finished", fx.Events()[^1]);
        Assert.DoesNotContain("server.installed", fx.Events());
    }

    [Fact]
    public async Task AVersionThatCannotBeResolved_RollsBack_BeforeAnyDownload()
    {
        var fx = OpsFixture.Create();
        fx.Script.Failures["version --latest"] = "upstream is down";

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(1, run.Exit);
        AssertNothingRemains(fx, "fx-1");
        Assert.DoesNotContain(fx.Script.Calls, c => c.Contains("download", StringComparison.Ordinal));
    }

    [Fact]
    public async Task ARollback_KeepsWhatOtherInstancesOwn()
    {
        var fx = OpsFixture.Create();
        await fx.Run("instance", "install", "factorio", "--id", "fx-1");
        fx.Script.Failures["download"] = "boom";

        await fx.Run("instance", "install", "factorio", "--id", "fx-2");

        Assert.True(fx.IsRegistered("fx-1"));
        Assert.True(Directory.Exists(fx.Find("fx-1").WorkingDirectory));
        Assert.True(Directory.Exists(fx.Backups("fx-1")));
        Assert.False(Directory.Exists(Path.GetDirectoryName(fx.Backups("fx-1"))! + "/fx-2"));
    }

    [Fact]
    public async Task ARollback_RemovesTheDirectoriesTheInstallMadeAboveTheWorkingDirectory()
    {
        var fx = OpsFixture.Create();
        fx.Script.Failures["download"] = "boom";

        await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Empty(Directory.EnumerateFileSystemEntries(fx.Main.Path).Where(p => !p.EndsWith(".kgsm-library", StringComparison.Ordinal)));
    }

    [Fact]
    public async Task ABackupsDirectoryThatAlreadyExists_IsNeverAdopted_NorRemoved()
    {
        var fx = OpsFixture.Create();
        Directory.CreateDirectory(fx.Backups("fx-1"));
        File.WriteAllText(Path.Combine(fx.Backups("fx-1"), "precious"), "earlier backup");

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("never adopts", run.Err, StringComparison.Ordinal);
        Assert.True(File.Exists(Path.Combine(fx.Backups("fx-1"), "precious")));
    }

    // --- start after install ---

    [Fact]
    public async Task InstallWithStart_StartsTheInstance_WithItsOwnBracket()
    {
        var fx = OpsFixture.Create();

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1", "--start", "--json");

        Assert.Equal(0, run.Exit);
        Assert.NotNull(Report(run).Start);
        Assert.Equal(
            [.. SuccessfulInstall, "server.start.started", "server.started", "server.start.finished"],
            fx.Events());
    }

    [Fact]
    public async Task InstallWithStart_ThatCannotStart_LeavesTheInstanceInstalled_AndSaysSo()
    {
        var fx = OpsFixture.Create();
        fx.Script.Failures["start"] = "no display";

        CliRun run = await fx.Run("instance", "install", "factorio", "--id", "fx-1", "--start");

        Assert.Equal(1, run.Exit);
        Assert.Contains("is installed, and could not be started", run.Err, StringComparison.Ordinal);
        Assert.True(fx.IsRegistered("fx-1"));
        Assert.Contains("server.installed", fx.Events());
        Assert.DoesNotContain("server.install.failed", fx.Events());
    }

    // --- provenance ---

    [Fact]
    public async Task EveryFactCarriesTheActorAndOrigin_TheCommandGave()
    {
        var fx = OpsFixture.Create();

        await fx.Run("--actor", "discord:haru", "--origin", "api", "instance", "install", "factorio", "--id", "fx-1");

        JournalLine installed = fx.Journal().Single(l => l.EventType == "server.installed");
        Assert.Equal("discord:haru", installed.Actor);
        Assert.Equal("api", installed.Origin);
    }

    [Fact]
    public async Task WithoutAnActor_NoneIsInvented_UnlessAPersonIsAtATerminal()
    {
        var fx = OpsFixture.Create();
        await fx.Run("instance", "install", "factorio", "--id", "fx-1");
        Assert.All(fx.Journal(), l => Assert.Null(l.Actor));

        fx.Session.Interactive = true;
        await fx.Run("instance", "install", "factorio", "--id", "fx-2");
        Assert.Equal("local:tester", fx.Journal().Last(l => l.EventType == "server.installed").Actor);
    }

    private static void AssertNothingRemains(OpsFixture fx, string id)
    {
        Assert.False(fx.IsRegistered(id));
        Assert.False(Directory.Exists(fx.Backups(id)));
        Assert.False(Directory.Exists(Path.Combine(fx.Main.Path, "instances", "factorio", id)));
        Assert.False(Directory.Exists(Path.Combine(fx.Main.Path, "instances")));
    }
}
