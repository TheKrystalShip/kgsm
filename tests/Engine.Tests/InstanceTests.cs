using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;

namespace TheKrystalShip.KGSM.Engine.Tests;

public class InstanceIdTests
{
    [Theory]
    [InlineData("factorio-1", true)]
    [InlineData("A", true)]
    [InlineData("a.b_c-d", true)]
    [InlineData("0lead", true)]
    [InlineData("", false)]
    [InlineData(".hidden", false)]
    [InlineData("-lead", false)]
    [InlineData("has space", false)]
    [InlineData("a/b", false)]
    [InlineData("../x", false)]
    public void AnIdStartsAlphanumeric_ThenLettersDigitsDotsUnderscoresHyphens(string id, bool valid)
    {
        Assert.Equal(valid, InstanceIds.IsValid(id));
    }

    [Fact]
    public void AnIdIsAtMostSixtyFourCharacters()
    {
        Assert.True(InstanceIds.IsValid(new string('a', 64)));
        Assert.False(InstanceIds.IsValid(new string('a', 65)));
    }

    [Fact]
    public void AGeneratedId_HasTheBlueprintAndASuffixOfTheAskedLength_AndIsValid()
    {
        string? id = InstanceIds.Generate("factorio", 3, _ => false);

        Assert.Matches("^factorio-[0-9a-z]{3}$", id);
        Assert.True(InstanceIds.IsValid(id));
    }

    [Fact]
    public void AGeneratedId_AvoidsEveryTakenId_AcrossBlueprints()
    {
        var taken = new HashSet<string> { "g-0", "g-1", "g-2" };

        for (int i = 0; i < 50; i++)
            Assert.DoesNotContain(InstanceIds.Generate("g", 1, taken.Contains)!, taken);
    }

    [Fact]
    public void WhenTheSuffixSpaceIsFull_GenerationEnds_InsteadOfLoopingForever()
    {
        Assert.Null(InstanceIds.Generate("g", 1, _ => true));
    }

    [Fact]
    public void WhenOneSuffixIsLeft_ItIsFound()
    {
        Assert.Equal("g-z", InstanceIds.Generate("g", 1, id => id != "g-z"));
    }
}

public class InstanceLayoutTests
{
    private static readonly InstanceLayout Layout = new("/lib/instances/g/g-1", "g-1", "bin/x64");

    [Fact]
    public void EveryPath_IsDerivedFromTheWorkingDirectoryAndTheId()
    {
        Assert.Equal("/lib/instances/g/g-1/install", Layout.InstallDirectory);
        Assert.Equal("/lib/instances/g/g-1/saves", Layout.SavesDirectory);
        Assert.Equal("/lib/instances/g/g-1/logs", Layout.LogsDirectory);
        Assert.Equal("/lib/instances/g/g-1/temp", Layout.TempDirectory);
        Assert.Equal("/lib/instances/g/g-1/events", Layout.EventsDirectory);
        Assert.Equal("/lib/instances/g/g-1/install/bin/x64", Layout.LaunchDirectory);
        Assert.Equal("/lib/instances/g/g-1/g-1.config.json", Layout.ConfigFile);
        Assert.Equal("/lib/instances/g/g-1/g-1.manage.sh", Layout.ManagementScript);
        Assert.Equal("/lib/instances/g/g-1/g-1.docker-compose.yml", Layout.ComposeFile);
        Assert.Equal("/lib/instances/g/g-1/.g-1.version", Layout.VersionFile);
        Assert.Equal("/lib/instances/g/g-1/.g-1.latest", Layout.LatestVersionFile);
        Assert.Equal("/lib/instances/g/g-1/.g-1.pid", Layout.PidFile);
        Assert.Equal("/lib/instances/g/g-1/.g-1.sock", Layout.InputFifo);
        Assert.Equal("/lib/instances/g/g-1/g-1.log", Layout.LogFile);
    }

    [Fact]
    public void WithNoExecutableSubdirectory_TheLaunchDirectoryIsTheInstallDirectory()
    {
        Assert.Equal("/w/install", new InstanceLayout("/w", "i").LaunchDirectory);
    }

    [Fact]
    public void AMove_ChangesOnlyTheWorkingDirectory_AndEveryDerivedPathFollows()
    {
        var moved = Layout with { WorkingDirectory = "/other/instances/g/g-1" };

        Assert.Equal("/other/instances/g/g-1/saves", moved.SavesDirectory);
        Assert.Equal(Layout.ConfigFile.Replace("/lib/", "/other/", StringComparison.Ordinal), moved.ConfigFile);
    }

    [Fact]
    public void TheWorkingDirectory_IsLibraryInstancesBlueprintId()
    {
        Assert.Equal("/mnt/ssd/instances/terraria/terraria-ab", InstanceLayout.WorkingDirectoryFor("/mnt/ssd", "terraria", "terraria-ab"));
    }

    [Fact]
    public void TheCgroupPath_IsBelowTheWatchdogsCgroup()
    {
        Assert.Equal(
            "/sys/fs/cgroup/kgsm.slice/kgsm-watchdog.service/g-1",
            Layout.CgroupPath("/sys/fs/cgroup", "kgsm.slice/kgsm-watchdog.service"));
        Assert.Equal(
            "/sys/fs/cgroup/kgsm.slice/kgsm-watchdog.service/g-1",
            Layout.CgroupPath("/sys/fs/cgroup", "/kgsm.slice/kgsm-watchdog.service/"));
    }
}

public class InstanceStoreTests
{
    private static InstanceStore NewStore(Sandbox sandbox) => new(sandbox.Paths, new LibraryCatalog(sandbox.Paths));

    [Fact]
    public void WithNoRegistry_ThereAreNoInstances_AndNothingIsWritten()
    {
        var sandbox = Sandbox.Create();

        Assert.Empty(NewStore(sandbox).List());
        Assert.Null(NewStore(sandbox).Find("g-1"));
        Assert.False(File.Exists(sandbox.Paths.InstanceRegistryFile));
    }

    [Fact]
    public void AnInstance_IsDescribedWithItsLibraryAndItsConfig()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        var (workingDirectory, config) = sandbox.AddInstance(library, "terraria", "terraria-1", c => c with { DisplayName = "Survival" });

        InstanceDescription instance = NewStore(sandbox).Find("terraria-1")!;

        Assert.Equal("terraria", instance.Blueprint);
        Assert.Equal(workingDirectory, instance.WorkingDirectory);
        Assert.Equal("ssd", instance.Library?.Name);
        Assert.Equal(InstanceLibraryState.Online, instance.LibraryState);
        Assert.Equal(config, instance.Config);
        Assert.Equal("Survival", instance.Config!.Label);
        Assert.Null(instance.ConfigProblem);
        Assert.Equal(Path.Combine(workingDirectory, "terraria-1.config.json"), instance.Layout.ConfigFile);
    }

    [Fact]
    public void TheListing_IsInIdOrder()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        sandbox.AddInstance(library, "g", "g-2");
        sandbox.AddInstance(library, "g", "g-1");
        sandbox.AddInstance(library, "a", "a-1");

        Assert.Equal(["a-1", "g-1", "g-2"], NewStore(sandbox).List().Select(i => i.Id));
    }

    [Fact]
    public void AnInstanceInAnOfflineLibrary_StaysListed_WithNoConfigAndAReason()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("usb");
        sandbox.AddInstance(library, "g", "g-1");
        File.Delete(Path.Combine(library.Path, LibraryRules.MarkerFileName));

        InstanceDescription instance = NewStore(sandbox).Find("g-1")!;

        Assert.Equal(InstanceLibraryState.Offline, instance.LibraryState);
        Assert.Null(instance.Config);
        Assert.Equal("library 'usb' is offline", instance.ConfigProblem);
        Assert.Equal("g", instance.Blueprint);
        Assert.NotEmpty(instance.WorkingDirectory);
    }

    [Fact]
    public void AnInstanceUnderNoRegisteredLibrary_IsUnregistered()
    {
        var sandbox = Sandbox.Create();
        sandbox.Register("g-1", "g", "none", Path.Combine(sandbox.Root, "nowhere", "instances", "g", "g-1"));

        InstanceDescription instance = NewStore(sandbox).Find("g-1")!;

        Assert.Equal(InstanceLibraryState.Unregistered, instance.LibraryState);
        Assert.Null(instance.Library);
        Assert.NotNull(instance.ConfigProblem);
    }

    [Fact]
    public void AMissingConfig_IsAProblemOfThatInstance_NotOfTheListing()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        var (workingDirectory, _) = sandbox.AddInstance(library, "g", "g-1");
        sandbox.AddInstance(library, "g", "g-2");
        File.Delete(Path.Combine(workingDirectory, "g-1.config.json"));

        var listing = NewStore(sandbox).List();

        Assert.NotNull(listing.Single(i => i.Id == "g-1").ConfigProblem);
        Assert.Null(listing.Single(i => i.Id == "g-2").ConfigProblem);
    }

    [Fact]
    public void AConfigOfAnUnknownVersion_IsRefused_AsThatInstancesProblem()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        var (workingDirectory, config) = sandbox.AddInstance(library, "g", "g-1");
        File.WriteAllText(Path.Combine(workingDirectory, "g-1.config.json"), $$"""{"schemaVersion":7,"name":"{{config.Name}}"}""");

        InstanceDescription instance = NewStore(sandbox).Find("g-1")!;

        Assert.Null(instance.Config);
        Assert.Contains("schemaVersion 7", instance.ConfigProblem, StringComparison.Ordinal);
    }

    [Fact]
    public void AConfigMissingAKey_IsRefused_NeverFilledWithADefault()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        var (workingDirectory, _) = sandbox.AddInstance(library, "g", "g-1");
        File.WriteAllText(
            Path.Combine(workingDirectory, "g-1.config.json"),
            File.ReadAllText(Path.Combine(workingDirectory, "g-1.config.json")).Replace("\"crashRestart\":true,", "", StringComparison.Ordinal));

        InstanceDescription instance = NewStore(sandbox).Find("g-1")!;

        Assert.Null(instance.Config);
        Assert.Contains("crashRestart", instance.ConfigProblem, StringComparison.Ordinal);
    }

    [Fact]
    public void AConfigWithNoVersion_IsRefused()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        var (workingDirectory, _) = sandbox.AddInstance(library, "g", "g-1");
        File.WriteAllText(Path.Combine(workingDirectory, "g-1.config.json"), """{"name":"g-1"}""");

        Assert.Contains("(none)", NewStore(sandbox).Find("g-1")!.ConfigProblem, StringComparison.Ordinal);
    }

    [Fact]
    public void ARegistryOfAnUnknownVersion_IsRefused_AsAWhole()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.Paths.InstanceRegistryFile, """{"schemaVersion":2,"instances":{}}""");

        Assert.Throws<UnsupportedSchemaVersionException>(() => NewStore(sandbox).List());
    }

    [Fact]
    public void ARegistryThatIsNotJson_IsAFormatError_NamingTheFile()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.Paths.InstanceRegistryFile, "{ nope");

        var refusal = Assert.Throws<EngineFormatException>(() => NewStore(sandbox).List());

        Assert.Equal(sandbox.Paths.InstanceRegistryFile, refusal.Path);
    }

    [Fact]
    public void TheConfig_IsCamelCaseJson_WithNoPathKeyExceptTheBackupsDirectory()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        var (workingDirectory, _) = sandbox.AddInstance(library, "g", "g-1");

        string json = File.ReadAllText(Path.Combine(workingDirectory, "g-1.config.json"));

        Assert.StartsWith("""{"schemaVersion":1,"name":"g-1",""", json, StringComparison.Ordinal);
        Assert.Contains("\"backupsDirectory\":", json, StringComparison.Ordinal);
        foreach (string pathKey in new[] { "workingDir", "installDir", "savesDir", "tempDir", "logsDir", "pidFile", "logFile", "versionFile", "managementFile", "libraryDir", "socketFile" })
            Assert.DoesNotContain($"\"{pathKey}\"", json, StringComparison.Ordinal);
        Assert.Contains("\"runtime\":\"native\"", json, StringComparison.Ordinal);
    }

    [Fact]
    public void TheConfigRoundTrips_ValuesLiteral_WithNothingEscaped()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        const string hostile = "a\\b & c \"quoted\" $(rm -rf /) `x` \n{newline}\tend";
        var (_, written) = sandbox.AddInstance(library, "g", "g-1", c => c with { StopCommand = hostile, RconPassword = hostile });

        InstanceConfig read = NewStore(sandbox).Find("g-1")!.Config!;

        Assert.Equal(hostile, read.StopCommand);
        Assert.Equal(hostile, read.RconPassword);
        Assert.Equal(written, read);
    }

    [Fact]
    public void ALabel_FallsBackToTheId()
    {
        InstanceConfig config = Sandbox.NewConfig("g", "g-1", "/b");

        Assert.Equal("g-1", config.Label);
        Assert.Equal("Named", (config with { DisplayName = "Named" }).Label);
    }

    [Fact]
    public void ARegistryEntry_NamesTheLibraryById_SoARenameRewritesNoInstance()
    {
        var sandbox = Sandbox.Create();
        LibraryRecord library = sandbox.AddLibrary("ssd");
        sandbox.AddInstance(library, "g", "g-1");

        string json = File.ReadAllText(sandbox.Paths.InstanceRegistryFile);

        Assert.Contains($"\"library\":\"{library.Id}\"", json, StringComparison.Ordinal);
        Assert.DoesNotContain("\"ssd\"", json, StringComparison.Ordinal);
    }

    [Fact]
    public void ContractFileWrites_AreAtomic_LeavingNoStagedFileBehind()
    {
        var sandbox = Sandbox.Create();
        sandbox.AddLibrary("ssd");

        Assert.Empty(Directory.EnumerateFiles(Path.GetDirectoryName(sandbox.Paths.LibraryRegistryFile)!, "*.tmp"));
    }
}
