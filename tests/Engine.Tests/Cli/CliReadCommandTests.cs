using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Accounts;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Paths;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Libraries;

namespace TheKrystalShip.KGSM.Engine.Tests.Cli;

public class CliReadCommandTests
{
    private static T Parse<T>(string json, System.Text.Json.Serialization.Metadata.JsonTypeInfo<T> info) =>
        JsonSerializer.Deserialize(json, info) ?? throw new InvalidOperationException("null");

    private static (CliSession Session, LibraryRecord Library) NewSession(bool withBlueprints = false)
    {
        var sandbox = Sandbox.Create();
        return (new CliSession(sandbox, withBlueprints), sandbox.AddLibrary("main"));
    }

    // --- the process-wide surface ---

    [Fact]
    public async Task Version_IsTheReleaseNumber_AsACommandAndAsAFlag()
    {
        var (session, _) = NewSession();

        CliRun command = await session.RunAsync("engine", "version");
        CliRun flag = await session.RunAsync("--version");
        CliRun json = await session.RunAsync("engine", "version", "--json");

        Assert.Equal(0, command.Exit);
        Assert.Equal(Journal.EngineVersion.Current + "\n", command.Out);
        Assert.Equal(command.Out, flag.Out);
        Assert.Equal(Journal.EngineVersion.Current, Parse(json.Out, EngineJsonContext.Default.EngineVersionReport).Version);
    }

    [Fact]
    public async Task Paths_AreReportedAsJson_FromTheSandboxHomes()
    {
        var (session, _) = NewSession();

        CliRun run = await session.RunAsync("engine", "paths", "--format=json");

        PathsReport report = Parse(run.Out, EngineJsonContext.Default.PathsReport);
        Assert.Equal(0, run.Exit);
        Assert.Equal(session.Sandbox.Paths.InstanceRegistryFile, report.InstanceRegistryFile);
        Assert.Equal(session.Sandbox.Paths.LogFile, report.LogFile);
        Assert.Equal("", run.Err);
    }

    [Fact]
    public async Task AMalformedCommandLine_IsUsage_WithStdoutEmpty_AndTheReportOnStderr()
    {
        var (session, _) = NewSession();

        CliRun text = await session.RunAsync("bogus");
        CliRun json = await session.RunAsync("instance", "show", "--json");

        Assert.Equal(2, text.Exit);
        Assert.Equal("", text.Out);
        Assert.StartsWith("error:", text.Err);
        Assert.Equal(2, json.Exit);
        Assert.Equal("", json.Out);
        ErrorReport report = Parse(json.Err, EngineJsonContext.Default.ErrorReport);
        Assert.Equal("usage", report.Code);
        Assert.Equal(2, report.ExitCode);
    }

    [Fact]
    public async Task ANamelessCommandLine_IsUsage()
    {
        var (session, _) = NewSession();

        CliRun run = await session.RunAsync();

        Assert.Equal(2, run.Exit);
        Assert.Equal("", run.Out);
    }

    [Fact]
    public async Task AFormatThatIsNotAFormat_IsUsage()
    {
        var (session, _) = NewSession();

        CliRun run = await session.RunAsync("instance", "list", "--format", "yaml");

        Assert.Equal(2, run.Exit);
        Assert.Contains("yaml", run.Err);
    }

    [Fact]
    public async Task EveryCommandButHelpVersionAndPaths_IsRefusedWhenTheJournalBelongsToAnotherAccount()
    {
        var (session, _) = NewSession();
        session.AccountGate = (journal, arguments) =>
            RegistryAccountGate.Check(journal, arguments, _ => 1500, 1000, uid => uid == 1500 ? "keeper" : null);

        CliRun refused = await session.RunAsync("instance", "list", "--json");
        CliRun paths = await session.RunAsync("engine", "paths");
        CliRun version = await session.RunAsync("engine", "version");

        Assert.Equal(1, refused.Exit);
        Assert.Equal("", refused.Out);
        ErrorReport report = Parse(refused.Err, EngineJsonContext.Default.ErrorReport);
        Assert.Equal("wrong-account", report.Code);
        Assert.Contains("sudo -u keeper kgsm instance list --json", report.Message);
        Assert.Equal(0, paths.Exit);
        Assert.Equal(0, version.Exit);
    }

    [Fact]
    public async Task EveryCommand_AppendsALineToTheEnginesLog()
    {
        var (session, _) = NewSession();

        await session.RunAsync("instance", "list");

        string log = File.ReadAllText(session.Sandbox.Paths.LogFile);
        Assert.Contains("kgsm instance list exited 0", log);
    }

    [Fact]
    public async Task AMarkerOfAnUnknownVersion_FailsEveryCommandTouchingTheLibrary_NamingTheMarker()
    {
        var (session, library) = NewSession();
        session.Sandbox.AddInstance(library, "factorio", "factorio-a");
        string marker = Path.Combine(library.Path, LibraryRules.MarkerFileName);
        File.WriteAllText(marker, $$"""{"schemaVersion":7,"id":"{{library.Id}}","name":"main"}""");

        CliRun libraries = await session.RunAsync("library", "list");
        CliRun instances = await session.RunAsync("instance", "list", "--json");

        Assert.Equal(1, libraries.Exit);
        Assert.Contains(marker, libraries.Err);
        Assert.Equal(1, instances.Exit);
        Assert.Equal("unsupported-schema-version", Parse(instances.Err, EngineJsonContext.Default.ErrorReport).Code);
        Assert.Equal("", instances.Out);
    }

    // --- engine config ---

    [Fact]
    public async Task ConfigList_NamesTheSourceOfEachValue()
    {
        var (session, _) = NewSession();
        session.Sandbox.WriteFile(session.Sandbox.Paths.UserSettingsFile, """{"Libraries":{"InstallFreeSpaceMarginMb":2048}}""");
        session.Extra["Downloads__TimeoutSeconds"] = "90";

        CliRun run = await session.RunAsync("engine", "config", "list", "--json");

        EngineSetting[] settings = Parse(run.Out, EngineJsonContext.Default.IReadOnlyListEngineSetting).ToArray();
        Assert.Equal(SettingSource.User, settings.Single(s => s.Key == "Libraries:InstallFreeSpaceMarginMb").Source);
        Assert.Equal("2048", settings.Single(s => s.Key == "Libraries:InstallFreeSpaceMarginMb").Value);
        Assert.Equal(SettingSource.Environment, settings.Single(s => s.Key == "Downloads:TimeoutSeconds").Source);
        Assert.Equal("90", settings.Single(s => s.Key == "Downloads:TimeoutSeconds").Value);
        Assert.Equal(SettingSource.Default, settings.Single(s => s.Key == "Instances:IdSuffixLength").Source);
        Assert.Equal("true", settings.Single(s => s.Key == "Watchdog:Enabled").Value);
        Assert.Equal(settings.Select(s => s.Key).Order(StringComparer.Ordinal), settings.Select(s => s.Key));
    }

    [Fact]
    public async Task ConfigGet_AcceptsEitherSpellingOfAKey_AndAnUnknownKeyIsNotFound()
    {
        var (session, _) = NewSession();

        CliRun colon = await session.RunAsync("engine", "config", "get", "Downloads:TimeoutSeconds");
        CliRun underscores = await session.RunAsync("engine", "config", "get", "Downloads__TimeoutSeconds");
        CliRun unknown = await session.RunAsync("engine", "config", "get", "Nothing:Here");

        Assert.Equal("60\n", colon.Out);
        Assert.Equal(colon.Out, underscores.Out);
        Assert.Equal(25, unknown.Exit);
        Assert.Equal("", unknown.Out);
    }

    // --- instances ---

    [Fact]
    public async Task InstanceList_IsEmptyOnAFreshHost_AndOnlyAnEmptyArrayInJson()
    {
        var (session, _) = NewSession();

        CliRun text = await session.RunAsync("instance", "list");
        CliRun json = await session.RunAsync("instance", "list", "--json");

        Assert.Equal("No instances are registered.\n", text.Out);
        Assert.Equal("[]\n", json.Out);
    }

    [Fact]
    public async Task InstanceList_ReportsEachInstanceInIdOrder_WithItsLibraryState()
    {
        var (session, library) = NewSession();
        session.Sandbox.AddInstance(library, "factorio", "factorio-b", c => c with { DisplayName = "Base" });
        session.Sandbox.AddInstance(library, "terraria", "terraria-a");
        LibraryRecord away = session.Sandbox.AddLibrary("away", withMarker: false);
        session.Sandbox.AddInstance(away, "valheim", "valheim-a");

        CliRun run = await session.RunAsync("instance", "list", "--json");

        InstanceSummary[] list = Parse(run.Out, EngineJsonContext.Default.IReadOnlyListInstanceSummary).ToArray();
        Assert.Equal(["factorio-b", "terraria-a", "valheim-a"], list.Select(i => i.Id));
        Assert.Equal("Base", list[0].Label);
        Assert.Equal("terraria-a", list[1].Label);
        Assert.Equal(InstanceLibraryState.Online, list[0].LibraryState);
        Assert.Equal(InstanceLibraryState.Offline, list[2].LibraryState);
        Assert.Null(list[2].Runtime);
        Assert.Contains("offline", list[2].ConfigProblem);
    }

    [Fact]
    public async Task InstanceShow_ReportsDerivedPaths_ParsedPorts_AndTheCgroup()
    {
        var (session, library) = NewSession();
        var (directory, _) = session.Sandbox.AddInstance(library, "factorio", "factorio-a", c => c with { Ports = "34197/udp|27015:27016/tcp" });

        CliRun run = await session.RunAsync("instance", "show", "factorio-a", "--json");

        InstanceInfo info = Parse(run.Out, EngineJsonContext.Default.InstanceInfo);
        Assert.Equal(directory, info.Paths.WorkingDirectory);
        Assert.Equal(Path.Combine(directory, "factorio-a.config.json"), info.Paths.ConfigFile);
        Assert.Equal(Path.Combine(directory, ".factorio-a.version"), info.Paths.VersionFile);
        Assert.Equal(Path.Combine(directory, "install"), info.Paths.LaunchDirectory);
        Assert.Equal(["27015-27016/tcp", "34197/udp"], info.Ports.OrderBy(p => p.Start).Select(p => $"{(p.Start == p.End ? p.Start.ToString() : p.Start + "-" + p.End)}/{p.Protocol.ToString().ToLowerInvariant()}"));
        Assert.Equal("/sys/fs/cgroup/kgsm.slice/kgsm-watchdog.service/factorio-a", info.CgroupPath);
        Assert.Equal("main", info.Library!.Name);
        Assert.Equal(BlueprintRuntime.Native, info.Runtime);
        Assert.NotNull(info.Config);
    }

    [Fact]
    public async Task AnInstanceInAnOfflineLibrary_IsShownHonestly_WithoutItsConfig()
    {
        var (session, _) = NewSession();
        LibraryRecord away = session.Sandbox.AddLibrary("away", withMarker: false);
        session.Sandbox.AddInstance(away, "valheim", "valheim-a");

        CliRun run = await session.RunAsync("instance", "show", "valheim-a", "--json");

        InstanceInfo info = Parse(run.Out, EngineJsonContext.Default.InstanceInfo);
        Assert.Equal(0, run.Exit);
        Assert.Null(info.Config);
        Assert.Null(info.Runtime);
        Assert.Equal(InstanceLibraryState.Offline, info.LibraryState);
        Assert.Contains("offline", info.ConfigProblem);
    }

    [Fact]
    public async Task AnUnknownInstance_IsNotFound_WithStdoutEmpty()
    {
        var (session, _) = NewSession();

        CliRun run = await session.RunAsync("instance", "show", "nope");

        Assert.Equal(25, run.Exit);
        Assert.Equal("", run.Out);
        Assert.Contains("nope", run.Err);
    }

    [Fact]
    public async Task ADisplayName_ResolvesToItsInstance_AnAmbiguousOneListsTheCandidates()
    {
        var (session, library) = NewSession();
        session.Sandbox.AddInstance(library, "factorio", "factorio-a", c => c with { DisplayName = "Base" });
        session.Sandbox.AddInstance(library, "factorio", "factorio-b", c => c with { DisplayName = "Twin" });
        session.Sandbox.AddInstance(library, "terraria", "terraria-a", c => c with { DisplayName = "Twin" });

        CliRun resolved = await session.RunAsync("instance", "show", "Base", "--json");
        CliRun ambiguous = await session.RunAsync("instance", "show", "Twin", "--json");

        Assert.Equal("factorio-a", Parse(resolved.Out, EngineJsonContext.Default.InstanceInfo).Id);
        Assert.Equal(1, ambiguous.Exit);
        ErrorReport report = Parse(ambiguous.Err, EngineJsonContext.Default.ErrorReport);
        Assert.Equal("ambiguous", report.Code);
        Assert.Equal(["factorio-b", "terraria-a"], report.Details);
    }

    [Fact]
    public async Task AnIdWins_OverADisplayNameThatSpellsTheSame()
    {
        var (session, library) = NewSession();
        session.Sandbox.AddInstance(library, "factorio", "factorio-a");
        session.Sandbox.AddInstance(library, "terraria", "terraria-a", c => c with { DisplayName = "factorio-a" });

        CliRun run = await session.RunAsync("instance", "show", "factorio-a", "--json");

        Assert.Equal("factorio-a", Parse(run.Out, EngineJsonContext.Default.InstanceInfo).Id);
    }

    [Fact]
    public async Task ConfigList_RendersEveryKeyTyped_WithWhetherItIsSettable()
    {
        var (session, library) = NewSession();
        session.Sandbox.AddInstance(library, "factorio", "factorio-a", c => c with { RconPort = 27015, CompressBackups = false });

        CliRun run = await session.RunAsync("instance", "config", "list", "factorio-a", "--json");

        ConfigEntry[] entries = Parse(run.Out, EngineJsonContext.Default.IReadOnlyListConfigEntry).ToArray();
        Assert.Equal(("bool", "false", true), (entries.Single(e => e.Key == "compressBackups").Type, entries.Single(e => e.Key == "compressBackups").Value, entries.Single(e => e.Key == "compressBackups").Settable));
        Assert.Equal(("int", "27015"), (entries.Single(e => e.Key == "rconPort").Type, entries.Single(e => e.Key == "rconPort").Value));
        Assert.False(entries.Single(e => e.Key == "name").Settable);
        Assert.False(entries.Single(e => e.Key == "ports").Settable);
        Assert.False(entries.Single(e => e.Key == "backupsDirectory").Settable);
        Assert.True(entries.Single(e => e.Key == "levelName").Settable);
        Assert.Equal(InstanceConfigKeysCount(), entries.Length);
    }

    private static int InstanceConfigKeysCount() => TheKrystalShip.KGSM.Engine.Instances.InstanceConfigKeys.All.Count;

    [Fact]
    public async Task ConfigGet_PrintsTheBareValue_AndAnUnknownKeyIsNotFound()
    {
        var (session, library) = NewSession();
        session.Sandbox.AddInstance(library, "factorio", "factorio-a");

        CliRun value = await session.RunAsync("instance", "config", "get", "factorio-a", "levelName");
        CliRun unset = await session.RunAsync("instance", "config", "get", "factorio-a", "rconPort", "--json");
        CliRun unknown = await session.RunAsync("instance", "config", "get", "factorio-a", "level_name");

        Assert.Equal("world one\n", value.Out);
        Assert.Null(Parse(unset.Out, EngineJsonContext.Default.ConfigEntry).Value);
        Assert.Equal(25, unknown.Exit);
    }

    [Fact]
    public async Task Logs_PrintTheLastLines_AndAnInstanceThatNeverWroteOneIsNotFound()
    {
        var (session, library) = NewSession();
        var (directory, _) = session.Sandbox.AddInstance(library, "factorio", "factorio-a");
        session.Sandbox.AddInstance(library, "terraria", "terraria-a");
        File.WriteAllLines(Path.Combine(directory, "factorio-a.log"), Enumerable.Range(1, 120).Select(i => $"line {i}"));

        CliRun last = await session.RunAsync("instance", "logs", "factorio-a", "-n", "3");
        CliRun json = await session.RunAsync("instance", "logs", "factorio-a", "--lines", "2", "--json");
        CliRun none = await session.RunAsync("instance", "logs", "terraria-a");
        CliRun follow = await session.RunAsync("instance", "logs", "factorio-a", "-f", "--json");

        Assert.Equal("line 118\nline 119\nline 120\n", last.Out);
        Assert.Equal(["line 119", "line 120"], Parse(json.Out, EngineJsonContext.Default.LogTail).Lines);
        Assert.Equal(25, none.Exit);
        Assert.Equal(2, follow.Exit);
    }

    [Fact]
    public async Task ContainerLogs_ComeFromTheRuntime_AndItsFailureIsAFailure()
    {
        var (session, library) = NewSession();
        var (directory, _) = session.Sandbox.AddInstance(library, "cs", "cs-a", c => c with { Runtime = BlueprintRuntime.Container });
        File.WriteAllText(Path.Combine(directory, "cs-a.docker-compose.yml"), "services: {}");
        session.Containers.Logs = (["a", "b"], null);

        CliRun ok = await session.RunAsync("instance", "logs", "cs-a", "--json");
        session.Containers.Logs = (null, "docker is not installed");
        CliRun failed = await session.RunAsync("instance", "logs", "cs-a");

        Assert.Equal(["a", "b"], Parse(ok.Out, EngineJsonContext.Default.LogTail).Lines);
        Assert.Null(Parse(ok.Out, EngineJsonContext.Default.LogTail).File);
        Assert.Equal(1, failed.Exit);
        Assert.Contains("docker is not installed", failed.Err);
    }

    // --- blueprints ---

    [Fact]
    public async Task BlueprintList_ShowsEveryShippedBlueprint_AUserFileShadowingASystemOne()
    {
        var (session, _) = NewSession(withBlueprints: true);
        string shadow = Path.Combine(session.Sandbox.Paths.UserBlueprintsDirectory, "factorio.bp.yaml");
        session.Sandbox.WriteFile(shadow, File.ReadAllText(Path.Combine(session.Sandbox.Paths.SystemBlueprintsDirectory, "factorio.bp.yaml")));

        CliRun all = await session.RunAsync("blueprint", "list", "--json");
        CliRun custom = await session.RunAsync("blueprint", "list", "--custom", "--json");
        CliRun system = await session.RunAsync("blueprint", "list", "--default", "--json");
        CliRun both = await session.RunAsync("blueprint", "list", "--custom", "--default");

        BlueprintListing[] listing = Parse(all.Out, EngineJsonContext.Default.IReadOnlyListBlueprintListing).ToArray();
        Assert.Equal(Directory.GetFiles(session.Sandbox.Paths.SystemBlueprintsDirectory).Length, listing.Length);
        Assert.Equal(shadow, listing.Single(b => b.Key == "factorio").Path);
        Assert.Equal(["factorio"], Parse(custom.Out, EngineJsonContext.Default.IReadOnlyListBlueprintListing).Select(b => b.Key));
        Assert.DoesNotContain(Parse(system.Out, EngineJsonContext.Default.IReadOnlyListBlueprintListing), b => b.Key == "factorio");
        Assert.Equal(2, both.Exit);
    }

    [Fact]
    public async Task BlueprintShow_FindAndAMissingName()
    {
        var (session, _) = NewSession(withBlueprints: true);

        CliRun show = await session.RunAsync("blueprint", "show", "factorio", "--json");
        CliRun find = await session.RunAsync("blueprint", "find", "factorio", "--json");
        CliRun missing = await session.RunAsync("blueprint", "show", "nothing");
        CliRun badName = await session.RunAsync("blueprint", "show", "../etc");

        Blueprint blueprint = Parse(show.Out, EngineJsonContext.Default.Blueprint);
        Assert.Equal("factorio", blueprint.Name);
        Assert.Equal(BlueprintRuntime.Native, blueprint.Runtime);
        BlueprintResolution resolution = Parse(find.Out, EngineJsonContext.Default.BlueprintResolution);
        Assert.Equal(Path.Combine(session.Sandbox.Paths.SystemBlueprintsDirectory, "factorio.bp.yaml"), resolution.Resolved);
        Assert.Equal(2, resolution.Candidates.Count);
        Assert.False(resolution.Candidates[0].Exists);
        Assert.Equal(25, missing.Exit);
        Assert.Equal(2, badName.Exit);
    }

    [Fact]
    public async Task BlueprintValidate_PrintsItsVerdictEvenWhenItFails()
    {
        var (session, _) = NewSession(withBlueprints: true);
        session.Sandbox.WriteFile(Path.Combine(session.Sandbox.Paths.UserBlueprintsDirectory, "broken.bp.yaml"), "name: \"\"\nruntime: native\n");

        CliRun good = await session.RunAsync("blueprint", "validate", "factorio", "--json");
        CliRun bad = await session.RunAsync("blueprint", "validate", "broken", "--json");
        CliRun byPath = await session.RunAsync("blueprint", "validate", Path.Combine(session.Sandbox.Paths.UserBlueprintsDirectory, "broken.bp.yaml"), "--json");

        Assert.Equal(0, good.Exit);
        Assert.True(Parse(good.Out, EngineJsonContext.Default.BlueprintValidation).Valid);
        Assert.Equal(1, bad.Exit);
        BlueprintValidation verdict = Parse(bad.Out, EngineJsonContext.Default.BlueprintValidation);
        Assert.False(verdict.Valid);
        Assert.NotEmpty(verdict.Errors);
        Assert.Equal("", bad.Err);
        Assert.Equal(1, byPath.Exit);
    }

    [Fact]
    public async Task BlueprintRequirements_PrintsEachOne_AndExitsNonZeroWhenOneIsMissing()
    {
        var (session, _) = NewSession(withBlueprints: true);

        CliRun satisfied = await session.RunAsync("blueprint", "requirements", "valheim", "--json");
        session.Requirements = new FakeRequirements();
        CliRun missing = await session.RunAsync("blueprint", "requirements", "valheim", "--json");

        Assert.Equal(0, satisfied.Exit);
        Assert.All(Parse(satisfied.Out, EngineJsonContext.Default.BlueprintRequirements).Requirements, r => Assert.True(r.Present));
        Assert.Equal(1, missing.Exit);
        BlueprintRequirements requirements = Parse(missing.Out, EngineJsonContext.Default.BlueprintRequirements);
        Assert.NotEmpty(requirements.Requirements);
        Assert.All(requirements.Requirements, r => Assert.False(r.Present));
    }

    // --- libraries, backups, ports ---

    [Fact]
    public async Task LibraryList_ReportsStateFiguresAndInstanceCount()
    {
        var (session, library) = NewSession();
        session.Sandbox.AddInstance(library, "factorio", "factorio-a");
        session.Sandbox.AddLibrary("away", withMarker: false);

        CliRun run = await session.RunAsync("library", "list", "--json");

        Library[] libraries = Parse(run.Out, EngineJsonContext.Default.IReadOnlyListLibrary).ToArray();
        Assert.Equal(LibraryState.Online, libraries[0].State);
        Assert.Equal(1, libraries[0].InstanceCount);
        Assert.True(libraries[0].TotalBytes > 0);
        Assert.Equal(LibraryState.Offline, libraries[1].State);
        Assert.Null(libraries[1].FreeBytes);
    }

    [Fact]
    public async Task BackupList_ReadsTheInstancesBackupsDirectory_NewestFirst()
    {
        var (session, library) = NewSession();
        var (_, config) = session.Sandbox.AddInstance(library, "factorio", "factorio-a");
        foreach ((string id, string at) in new[] { ("factorio-a-20260101T000000Z-aaaaaa", "2026-01-01T00:00:00Z"), ("factorio-a-20260102T000000Z-bbbbbb", "2026-01-02T00:00:00Z") })
        {
            session.Sandbox.WriteFile(
                Path.Combine(config.BackupsDirectory, id, "manifest.json"),
                $$"""{"schemaVersion":1,"id":"{{id}}","createdAt":"{{at}}","compressed":false,"sources":["saves"],"sizeBytes":5,"fileCount":1,"reason":"manual"}""");
        }

        CliRun run = await session.RunAsync("backup", "list", "factorio-a", "--json");

        BackupListing listing = Parse(run.Out, EngineJsonContext.Default.BackupListing);
        Assert.Equal(["factorio-a-20260102T000000Z-bbbbbb", "factorio-a-20260101T000000Z-aaaaaa"], listing.Backups.Select(b => b.Id));
        Assert.Equal(BackupRetention.Prunable, listing.Backups[0].Retention);
    }

    [Fact]
    public async Task PortList_AndConflicts_ReadEveryInstancesPorts()
    {
        var (session, library) = NewSession();
        session.Sandbox.AddInstance(library, "factorio", "factorio-a", c => c with { Ports = "34197/udp" });
        session.Sandbox.AddInstance(library, "factorio", "factorio-b", c => c with { Ports = "34190:34200/udp|27015/tcp" });
        session.Sandbox.AddInstance(library, "terraria", "terraria-a", c => c with { Ports = "27015/udp" });

        CliRun list = await session.RunAsync("port", "list", "--json");
        CliRun conflicts = await session.RunAsync("port", "conflicts", "--json");
        CliRun text = await session.RunAsync("port", "conflicts");

        Assert.Equal(4, Parse(list.Out, EngineJsonContext.Default.IReadOnlyListPortUse).Count);
        PortConflict conflict = Assert.Single(Parse(conflicts.Out, EngineJsonContext.Default.IReadOnlyListPortConflict));
        Assert.Equal((PortProtocol.Udp, 34190, 34200), (conflict.Protocol, conflict.Start, conflict.End));
        Assert.Equal(["factorio-a", "factorio-b"], conflict.Instances);
        Assert.Contains("factorio-a, factorio-b", text.Out);
        Assert.Equal(0, conflicts.Exit);
    }
}
