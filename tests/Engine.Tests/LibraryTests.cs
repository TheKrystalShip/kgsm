using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;

namespace TheKrystalShip.KGSM.Engine.Tests;

public class LibraryRulesTests
{
    private static LibraryRecord Lib(string name, string path) => new() { Name = name, Id = "id-" + name, Path = path };

    [Theory]
    [InlineData("ssd", true)]
    [InlineData("0-archive", true)]
    [InlineData("a-b-c", true)]
    [InlineData("-lead", false)]
    [InlineData("Upper", false)]
    [InlineData("has space", false)]
    [InlineData("under_score", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void ANameIsLowercaseLettersDigitsAndHyphens(string? name, bool valid)
    {
        Assert.Equal(valid, LibraryRules.IsValidName(name));
    }

    [Theory]
    [InlineData("/mnt/ssd", "/mnt/ssd", true)]
    [InlineData("/mnt/ssd/instances/x", "/mnt/ssd", true)]
    [InlineData("/mnt/ssd2", "/mnt/ssd", false)]
    [InlineData("/mnt", "/mnt/ssd", false)]
    [InlineData("/mnt/ssd/", "/mnt/ssd", true)]
    [InlineData("/anything", "/", true)]
    public void WithinIsPathAware_NotAStringPrefix(string path, string root, bool within)
    {
        Assert.Equal(within, LibraryRules.IsWithin(path, root));
    }

    [Fact]
    public void AnInstance_BelongsToTheLibraryWithTheLongestPrefix()
    {
        LibraryRecord[] libraries = [Lib("outer", "/data"), Lib("inner", "/data/fast"), Lib("other", "/data/fastest")];

        Assert.Equal("inner", LibraryRules.Membership(libraries, "/data/fast/instances/g/g-1")?.Name);
        Assert.Equal("outer", LibraryRules.Membership(libraries, "/data/slow/instances/g/g-1")?.Name);
        Assert.Equal("other", LibraryRules.Membership(libraries, "/data/fastest/instances/g/g-1")?.Name);
    }

    [Fact]
    public void AnInstanceUnderNoRoot_BelongsToNoLibrary_NotTheNearest()
    {
        Assert.Null(LibraryRules.Membership([Lib("a", "/mnt/a")], "/elsewhere/instances/g/g-1"));
    }

    [Theory]
    [InlineData("/home/u/.local/share/kgsm", true)]
    [InlineData("/home/u/.local/share/kgsm/backups", true)]
    [InlineData("/home/u/.local/share", true)]
    [InlineData("/home/u/.local/share/kgsm-library", false)]
    [InlineData("/mnt/ssd", false)]
    public void ARootThatIsContainsOrLiesInsideTheRegistryDirectory_Overlaps(string root, bool overlaps)
    {
        Assert.Equal(overlaps, LibraryRules.OverlapsRegistry(root, "/home/u/.local/share/kgsm"));
    }

    // --- placement: flag, then default, then the only one ---

    private static PlacementChoice Choose(LibraryRecord[] libraries, string? requested, string? configured, params string[] offline) =>
        LibraryRules.ChoosePlacement(
            libraries, l => offline.Contains(l.Name) ? LibraryState.Offline : LibraryState.Online, requested, configured);

    [Fact]
    public void Placement_PrefersTheFlag_ThenTheDefault_ThenTheOnlyLibrary()
    {
        LibraryRecord[] two = [Lib("a", "/a"), Lib("b", "/b")];

        Assert.Equal("b", Choose(two, "b", "a").Library?.Name);
        Assert.Equal("a", Choose(two, null, "a").Library?.Name);
        Assert.Equal("a", Choose(two, "", "a").Library?.Name);
        Assert.Equal("only", Choose([Lib("only", "/o")], null, null).Library?.Name);
    }

    [Fact]
    public void Placement_IsRefused_WhenNothingCanBeChosen()
    {
        LibraryRecord[] two = [Lib("a", "/a"), Lib("b", "/b")];

        Assert.Contains("none is chosen", Choose(two, null, null).Refusal, StringComparison.Ordinal);
        Assert.Contains("no library is registered", Choose([], null, null).Refusal, StringComparison.Ordinal);
        Assert.Contains("'missing' is not registered", Choose(two, "missing", null).Refusal, StringComparison.Ordinal);
    }

    [Fact]
    public void Placement_IsRefused_InAnOfflineLibrary()
    {
        PlacementChoice choice = Choose([Lib("a", "/a")], "a", null, offline: "a");

        Assert.False(choice.Ok);
        Assert.Contains("offline", choice.Refusal, StringComparison.Ordinal);
    }

    // --- what stops add, rename and remove ---

    [Fact]
    public void Add_ListsEveryRefusal()
    {
        LibraryRecord[] existing = [Lib("ssd", "/mnt/ssd")];

        var refusals = LibraryRules.AddRefusals(existing, "Bad Name", "/mnt/ssd", markerId: null, registryDirectory: "/mnt/ssd/kgsm");

        Assert.Equal(3, refusals.Count);
        Assert.Contains(refusals, r => r.Contains("is not a library name", StringComparison.Ordinal));
        Assert.Contains(refusals, r => r.Contains("already the library 'ssd'", StringComparison.Ordinal));
        Assert.Contains(refusals, r => r.Contains("overlaps", StringComparison.Ordinal));
    }

    [Fact]
    public void Add_RefusesATakenName_AndAMarkerRegisteredElsewhere()
    {
        LibraryRecord[] existing = [Lib("ssd", "/mnt/ssd")];

        var refusals = LibraryRules.AddRefusals(existing, "ssd", "/mnt/new", markerId: "id-ssd", registryDirectory: "/var/kgsm");

        Assert.Equal(2, refusals.Count);
        Assert.Contains(refusals, r => r.Contains("taken by another library", StringComparison.Ordinal));
        Assert.Contains(refusals, r => r.Contains("registered at /mnt/ssd", StringComparison.Ordinal));
    }

    [Fact]
    public void Add_OfAFreshRootWithAGoodName_HasNoRefusals()
    {
        Assert.Empty(LibraryRules.AddRefusals([Lib("ssd", "/mnt/ssd")], "archive", "/mnt/archive", null, "/var/kgsm"));
    }

    [Fact]
    public void Rename_Refuses_AnUnknownSource_ABadName_AndATakenName()
    {
        LibraryRecord[] existing = [Lib("a", "/a"), Lib("b", "/b")];

        Assert.Empty(LibraryRules.RenameRefusals(existing, "a", "c"));
        Assert.Empty(LibraryRules.RenameRefusals(existing, "a", "a"));
        Assert.Contains("not registered", Assert.Single(LibraryRules.RenameRefusals(existing, "zz", "c")), StringComparison.Ordinal);
        Assert.Contains("taken", Assert.Single(LibraryRules.RenameRefusals(existing, "a", "b")), StringComparison.Ordinal);
        Assert.Contains("not a library name", Assert.Single(LibraryRules.RenameRefusals(existing, "a", "NO")), StringComparison.Ordinal);
    }

    [Fact]
    public void Removal_IsBlockedByEveryInstancePlacedInTheLibrary()
    {
        var instances = new Dictionary<string, InstanceRegistryEntry>
        {
            ["g-2"] = new() { Blueprint = "g", Library = "x", WorkingDirectory = "/mnt/a/instances/g/g-2" },
            ["g-1"] = new() { Blueprint = "g", Library = "x", WorkingDirectory = "/mnt/a/instances/g/g-1" },
            ["h-1"] = new() { Blueprint = "h", Library = "y", WorkingDirectory = "/mnt/b/instances/h/h-1" },
        };

        Assert.Equal(["g-1", "g-2"], LibraryRules.RemovalBlockers(Lib("a", "/mnt/a"), instances));
        Assert.Empty(LibraryRules.RemovalBlockers(Lib("c", "/mnt/c"), instances));
    }
}

public class LibraryCatalogTests
{
    [Fact]
    public void WithNoRegistry_ThereAreNoLibraries_AndNothingIsWritten()
    {
        var sandbox = Sandbox.Create();

        Assert.Empty(new LibraryCatalog(sandbox.Paths).Registered());
        Assert.False(File.Exists(sandbox.Paths.LibraryRegistryFile));
    }

    [Fact]
    public void ALibraryWhoseRootCarriesItsMarker_IsOnline()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord record = sandbox.AddLibrary("ssd");

        Assert.Equal(LibraryState.Online, LibraryCatalog.StateOf(record));
    }

    [Fact]
    public void AMissingRoot_ARootWithNoMarker_AndAMarkerHoldingAnotherId_AreAllOffline()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord gone = sandbox.AddLibrary("gone");
        Directory.Delete(gone.Path, recursive: true);
        LibraryRecord bare = sandbox.AddLibrary("bare", withMarker: false);
        LibraryRecord swapped = sandbox.AddLibrary("swapped");
        Sandbox.WriteMarker(swapped.Path, "another-disks-id", "other");

        Assert.Equal(LibraryState.Offline, LibraryCatalog.StateOf(gone));
        Assert.Equal(LibraryState.Offline, LibraryCatalog.StateOf(bare));
        Assert.Equal(LibraryState.Offline, LibraryCatalog.StateOf(swapped));
    }

    [Fact]
    public void AMarkerOfAnUnknownVersion_IsARefusalThatNamesTheMarker_ForEveryCommandTouchingTheLibrary()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord record = sandbox.AddLibrary("ssd");
        sandbox.AddInstance(record, "factorio", "factorio-a");
        string marker = Path.Combine(record.Path, LibraryRules.MarkerFileName);
        File.WriteAllText(marker, $$"""{"schemaVersion":99,"id":"{{record.Id}}","name":"ssd"}""");
        var libraries = new LibraryCatalog(sandbox.Paths);

        var fromState = Assert.Throws<UnsupportedSchemaVersionException>(() => LibraryCatalog.StateOf(record));
        Assert.Equal(marker, fromState.Path);
        Assert.Equal(99, fromState.Found);
        Assert.Throws<UnsupportedSchemaVersionException>(() => LibraryCatalog.ReadMarker(record.Path));
        Assert.Throws<UnsupportedSchemaVersionException>(() => libraries.List(new Dictionary<string, InstanceRegistryEntry>()));
        Assert.Throws<UnsupportedSchemaVersionException>(() => new InstanceStore(sandbox.Paths, libraries).List());
    }

    [Fact]
    public void AMarkerThatIsNotJson_IsNotAMarker_SoTheLibraryIsOffline()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord record = sandbox.AddLibrary("ssd");
        File.WriteAllText(Path.Combine(record.Path, LibraryRules.MarkerFileName), "not json");

        Assert.Equal(LibraryState.Offline, LibraryCatalog.StateOf(record));
        Assert.Null(LibraryCatalog.ReadMarker(record.Path));
    }

    [Fact]
    public void TheState_IsMeasuredOnEveryCall_NeverCached()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord record = sandbox.AddLibrary("ssd");
        var catalog = new LibraryCatalog(sandbox.Paths);
        Assert.Equal(LibraryState.Online, catalog.List(new Dictionary<string, InstanceRegistryEntry>())[0].State);

        File.Delete(Path.Combine(record.Path, LibraryRules.MarkerFileName));

        Assert.Equal(LibraryState.Offline, catalog.List(new Dictionary<string, InstanceRegistryEntry>())[0].State);
    }

    [Fact]
    public void TheListing_MeasuresAnOnlineLibrary_AndReportsNothingForAnOfflineOne()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord online = sandbox.AddLibrary("online");
        LibraryRecord offline = sandbox.AddLibrary("offline", withMarker: false);
        sandbox.AddInstance(online, "g", "g-1");
        sandbox.AddInstance(online, "g", "g-2");
        sandbox.AddInstance(offline, "g", "g-3");
        var store = new InstanceStore(sandbox.Paths, new LibraryCatalog(sandbox.Paths));

        var listing = new LibraryCatalog(sandbox.Paths).List(store.Registered());

        Library onlineRow = listing.Single(l => l.Name == "online");
        Assert.True(onlineRow.FreeBytes > 0);
        Assert.True(onlineRow.TotalBytes >= onlineRow.FreeBytes);
        Assert.Equal(2, onlineRow.InstanceCount);

        Library offlineRow = listing.Single(l => l.Name == "offline");
        Assert.Null(offlineRow.FreeBytes);
        Assert.Null(offlineRow.TotalBytes);
        Assert.Equal(1, offlineRow.InstanceCount);
    }

    [Fact]
    public void ARegistryOfAnUnknownVersion_IsRefused_NotMisread()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.Paths.LibraryRegistryFile, """{"schemaVersion":2,"libraries":[]}""");

        var refusal = Assert.Throws<UnsupportedSchemaVersionException>(() => new LibraryCatalog(sandbox.Paths).Registered());

        Assert.Equal(2, refusal.Found);
        Assert.Equal(1, refusal.Expected);
        Assert.Equal(sandbox.Paths.LibraryRegistryFile, refusal.Path);
    }

    [Fact]
    public void LibraryIds_AreSixteenHexCharacters_AndDiffer()
    {
        string a = LibraryCatalog.NewId();
        string b = LibraryCatalog.NewId();

        Assert.Matches("^[0-9a-f]{16}$", a);
        Assert.NotEqual(a, b);
    }
}
