using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Reading;

namespace TheKrystalShip.KGSM.Engine.Tests.Reading;

public class EngineReaderTests
{
    private static EngineReader ReaderOn(Sandbox sandbox) => new(new EngineReaderOptions
    {
        InstallRoot = sandbox.InstallRoot,
        HomeFallback = Path.Combine(sandbox.Root, "home"),
        Environment = new Dictionary<string, string?>
        {
            ["HOME"] = Path.Combine(sandbox.Root, "home"),
            ["XDG_CONFIG_HOME"] = Path.Combine(sandbox.Root, "config"),
            ["XDG_DATA_HOME"] = Path.Combine(sandbox.Root, "data"),
            ["XDG_STATE_HOME"] = Path.Combine(sandbox.Root, "state"),
            ["Watchdog__Enabled"] = "false",
        },
    });

    [Fact]
    public void ReadsTheRegistrySummariesAndInfoTheBinaryWouldPrint()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("main");
        sandbox.AddInstance(library, "factorio", "factorio-1");
        using EngineReader reader = ReaderOn(sandbox);

        InstanceSummary summary = Assert.Single(reader.InstanceSummaries());
        Assert.Equal("factorio-1", summary.Id);
        Assert.Equal("main", summary.Library);

        InstanceInfo info = reader.InstanceInfo("factorio-1")!;
        Assert.Equal(summary.Blueprint, info.Blueprint);
        Assert.EndsWith("factorio-1.config.json", info.Paths.ConfigFile, StringComparison.Ordinal);
        Assert.NotNull(reader.ConfigEntries("factorio-1"));
        Assert.Null(reader.InstanceInfo("nothing"));
    }

    [Fact]
    public async Task StatusOfAnInstanceWithNoWatchdogIsReadFromItsFiles()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("main");
        sandbox.AddInstance(library, "factorio", "factorio-1");
        using EngineReader reader = ReaderOn(sandbox);

        InstanceStatus status = (await reader.StatusAsync("factorio-1"))!;

        Assert.Equal("factorio-1", status.Id);
        Assert.Equal(RunState.Stopped, status.Process.State);
        Assert.Contains("factorio-1", (await reader.StatusAllAsync()).Keys);
    }

    [Fact]
    public void ListsTheLibrariesAndAnEmptyBackupListing()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("main");
        sandbox.AddInstance(library, "factorio", "factorio-1");
        using EngineReader reader = ReaderOn(sandbox);

        Assert.Equal("main", Assert.Single(reader.LibraryList()).Name);
        Assert.Empty(reader.Backups("factorio-1")!.Backups);
        Assert.Empty(reader.PortConflicts());
    }

    [Fact]
    public void TheInstallRootNamesWhereTheSystemBlueprintsAre()
    {
        var sandbox = Sandbox.Create();
        using EngineReader reader = ReaderOn(sandbox);

        Assert.Equal(sandbox.InstallRoot, reader.ResolvedPaths().InstallRoot);
        Assert.Empty(reader.Blueprints());
    }
}
