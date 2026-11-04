using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

/// <summary><c>kgsm blueprint create|update|delete</c>.</summary>
public class BlueprintWriteTests
{
    private const string Native = """
        schema_version: 1
        name: mygame
        runtime: native
        native:
          executable_file: run.sh
        """;

    private static string UserFile(OpsFixture fx, string key) => Path.Combine(fx.Sandbox.Paths.UserBlueprintsDirectory, key + ".bp.yaml");

    [Fact]
    public async Task Create_FromAFile_WritesTheUserBlueprint_AndJournalsIt()
    {
        var fx = OpsFixture.Create();
        string source = fx.Sandbox.WriteFile(fx.Sandbox.PathFor("in", "mygame.yaml"), Native);

        CliRun run = await fx.Run("blueprint", "create", "mygame", "--file", source);

        Assert.Equal(0, run.Exit);
        Assert.Equal(Native, File.ReadAllText(UserFile(fx, "mygame")));
        Assert.Equal(["blueprint.created"], fx.Events());
        string fact = fx.JournalText().Single();
        Assert.Contains("\"BlueprintName\":\"mygame\"", fact, StringComparison.Ordinal);
        Assert.Contains("\"Tier\":\"user\"", fact, StringComparison.Ordinal);
        Assert.Contains("\"Runtime\":\"native\"", fact, StringComparison.Ordinal);
        Assert.Contains("\"OverridesSystem\":false", fact, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Create_FromStandardInput_Works_AndTheNewBlueprintIsReadable()
    {
        var fx = OpsFixture.Create();
        fx.Session.Stdin = new StringReader(Native);

        CliRun run = await fx.Run("blueprint", "create", "mygame");

        Assert.Equal(0, run.Exit);
        CliRun shown = await fx.Run("blueprint", "show", "mygame", "--json");
        Assert.Equal(0, shown.Exit);
    }

    [Fact]
    public async Task Create_OfAnInvalidBlueprint_ListsEveryProblem_AndWritesNothing()
    {
        var fx = OpsFixture.Create();
        fx.Session.Stdin = new StringReader("name: Bad Name\nruntime: sideways\n");

        CliRun run = await fx.Run("blueprint", "create", "bad");

        Assert.Equal(1, run.Exit);
        Assert.Contains("runtime", run.Err, StringComparison.Ordinal);
        Assert.False(File.Exists(UserFile(fx, "bad")));
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Create_ThatShadowsASystemBlueprint_SaysSo_AndAnExistingUserFileIsRefused()
    {
        var fx = OpsFixture.Create();
        fx.Session.Stdin = new StringReader(Native);
        CliRun shadow = await fx.Run("blueprint", "create", "factorio");
        fx.Session.Stdin = new StringReader(Native);
        CliRun again = await fx.Run("blueprint", "create", "factorio");

        Assert.Equal(0, shadow.Exit);
        Assert.Contains("\"OverridesSystem\":true", fx.JournalText().Single(), StringComparison.Ordinal);
        Assert.Equal(1, again.Exit);
    }

    [Fact]
    public async Task Update_ReplacesTheFileWhole_AndNeedsAnExistingUserBlueprint()
    {
        var fx = OpsFixture.Create();
        fx.Session.Stdin = new StringReader(Native);
        CliRun missing = await fx.Run("blueprint", "update", "mygame");
        fx.Session.Stdin = new StringReader(Native);
        await fx.Run("blueprint", "create", "mygame");
        string changed = Native.Replace("run.sh", "start.sh", StringComparison.Ordinal);
        fx.Session.Stdin = new StringReader(changed);

        CliRun run = await fx.Run("blueprint", "update", "mygame");

        Assert.Equal(25, missing.Exit);
        Assert.Equal(0, run.Exit);
        Assert.Equal(changed, File.ReadAllText(UserFile(fx, "mygame")));
        Assert.Equal(["blueprint.created", "blueprint.updated"], fx.Events());
        Assert.Empty(Directory.EnumerateFiles(fx.Sandbox.Paths.UserBlueprintsDirectory, ".*"));
    }

    [Fact]
    public async Task Delete_RemovesAUserBlueprint_AndSaysWhetherASystemOneShowsAgain()
    {
        var fx = OpsFixture.Create();
        fx.Session.Stdin = new StringReader(Native);
        await fx.Run("blueprint", "create", "factorio");

        CliRun unconfirmed = await fx.Run("blueprint", "delete", "factorio");
        CliRun run = await fx.Run("blueprint", "delete", "factorio", "--yes");

        Assert.Equal(2, unconfirmed.Exit);
        Assert.Equal(0, run.Exit);
        Assert.False(File.Exists(UserFile(fx, "factorio")));
        Assert.Contains("\"RevertedToSystem\":true", fx.JournalText()[^1], StringComparison.Ordinal);
    }

    [Fact]
    public async Task Delete_NeverRemovesASystemBlueprint()
    {
        var fx = OpsFixture.Create();

        CliRun run = await fx.Run("blueprint", "delete", "factorio", "--yes");

        Assert.Equal(1, run.Exit);
        Assert.Contains("system blueprint", run.Err, StringComparison.Ordinal);
        Assert.True(File.Exists(Path.Combine(fx.Sandbox.Paths.SystemBlueprintsDirectory, "factorio.bp.yaml")));
    }

    [Fact]
    public async Task Delete_IsRefusedWhileInstancesAreInstalledFromIt_AndNoSystemFileCoversIt()
    {
        var fx = OpsFixture.Create();
        fx.Session.Stdin = new StringReader(Native);
        await fx.Run("blueprint", "create", "mygame");
        fx.AddInstance("m-1", "mygame");

        CliRun run = await fx.Run("blueprint", "delete", "mygame", "--yes");

        Assert.Equal(1, run.Exit);
        Assert.Contains("m-1", run.Err, StringComparison.Ordinal);
        Assert.True(File.Exists(UserFile(fx, "mygame")));
    }
}

/// <summary><c>kgsm library add|remove|rename</c>.</summary>
public class LibraryWriteTests
{
    [Fact]
    public async Task Add_RegistersTheRoot_WritesItsMarker_AndJournalsIt()
    {
        var fx = OpsFixture.Create();
        string root = Path.Combine(fx.Sandbox.Root, "disks", "big");

        CliRun run = await fx.Run("library", "add", "big", root);

        Assert.Equal(0, run.Exit);
        LibraryRecord record = new LibraryCatalog(fx.Sandbox.Paths).Registered().Single(l => l.Name == "big");
        Assert.Equal(root, record.Path);
        Assert.Equal(record.Id, LibraryCatalog.ReadMarker(root)!.Id);
        Assert.Equal(["library.added"], fx.Events());
    }

    [Fact]
    public async Task Add_RefusesBeforeItCreatesAnything()
    {
        var fx = OpsFixture.Create();
        string root = Path.Combine(fx.Sandbox.Root, "disks", "nope");

        CliRun badName = await fx.Run("library", "add", "Bad Name", root);
        CliRun taken = await fx.Run("library", "add", "main", root);
        CliRun overlap = await fx.Run("library", "add", "inside", Path.Combine(fx.Sandbox.Paths.DataDirectory, "libs"));

        Assert.Equal(1, badName.Exit);
        Assert.Equal(1, taken.Exit);
        Assert.Equal(1, overlap.Exit);
        Assert.False(Directory.Exists(root));
        Assert.False(Directory.Exists(Path.Combine(fx.Sandbox.Paths.DataDirectory, "libs")));
    }

    [Fact]
    public async Task Add_OfARootThatCarriesAMarker_AdoptsItsIdentity()
    {
        var fx = OpsFixture.Create();
        string root = Path.Combine(fx.Sandbox.Root, "disks", "usb");
        Directory.CreateDirectory(root);
        Sandbox.WriteMarker(root, "abcdef0123456789", "oldname");

        await fx.Run("library", "add", "usb", root);

        LibraryRecord record = new LibraryCatalog(fx.Sandbox.Paths).Registered().Single(l => l.Name == "usb");
        Assert.Equal("abcdef0123456789", record.Id);
        Assert.Equal("usb", LibraryCatalog.ReadMarker(root)!.Name);
    }

    [Fact]
    public async Task Rename_ChangesTheNameOnly_AndWritesTheEventItDidNotHaveBefore()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        string before = File.ReadAllText(fx.Sandbox.Paths.InstanceRegistryFile);

        CliRun run = await fx.Run("library", "rename", "main", "primary");

        Assert.Equal(0, run.Exit);
        Assert.Equal("primary", Assert.Single(new LibraryCatalog(fx.Sandbox.Paths).Registered()).Name);
        Assert.Equal(before, File.ReadAllText(fx.Sandbox.Paths.InstanceRegistryFile));
        Assert.Equal("primary", LibraryCatalog.ReadMarker(fx.Main.Path)!.Name);
        Assert.Equal(["library.renamed"], fx.Events());
        string fact = fx.JournalText().Single();
        Assert.Contains("\"LibraryName\":\"primary\"", fact, StringComparison.Ordinal);
        Assert.Contains("\"OldName\":\"main\"", fact, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Rename_RefusesAnUnknownLibrary_ABadName_AndATakenName()
    {
        var fx = OpsFixture.Create();
        fx.Sandbox.AddLibrary("other");

        CliRun unknown = await fx.Run("library", "rename", "nope", "x");
        CliRun bad = await fx.Run("library", "rename", "main", "Bad Name");
        CliRun taken = await fx.Run("library", "rename", "main", "other");

        Assert.All(new[] { unknown, bad, taken }, r => Assert.Equal(1, r.Exit));
        Assert.Empty(fx.Events());
    }

    [Fact]
    public async Task Remove_NeedsYes_AndIsRefusedWhileInstancesLiveThere()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun unconfirmed = await fx.Run("library", "remove", "main");
        CliRun refused = await fx.Run("library", "remove", "main", "--yes");

        Assert.Equal(2, unconfirmed.Exit);
        Assert.Equal(1, refused.Exit);
        Assert.Contains("g-1", refused.Err, StringComparison.Ordinal);
        Assert.Single(new LibraryCatalog(fx.Sandbox.Paths).Registered());
    }

    [Fact]
    public async Task Remove_WithForce_LeavesTheInstancesUnregisteredInTheirLibrary_AndDeletesNoFile()
    {
        var fx = OpsFixture.Create();
        var (_, wd) = fx.AddInstance();

        CliRun run = await fx.Run("library", "remove", "main", "--force", "--yes");

        Assert.Equal(0, run.Exit);
        Assert.Empty(new LibraryCatalog(fx.Sandbox.Paths).Registered());
        Assert.True(Directory.Exists(wd));
        Assert.True(fx.IsRegistered("g-1"));
        Assert.Equal(InstanceLibraryState.Unregistered, fx.Find("g-1").LibraryState);
        Assert.Equal(["library.removed"], fx.Events());
    }

    [Fact]
    public async Task Remove_OfAnEmptyLibrary_Works_AndForceWithDrainExcludeEachOther()
    {
        var fx = OpsFixture.Create();
        fx.Sandbox.AddLibrary("spare");

        CliRun both = await fx.Run("library", "remove", "spare", "--force", "--drain", "main", "--yes");
        CliRun run = await fx.Run("library", "remove", "spare", "--yes");

        Assert.Equal(1, both.Exit);
        Assert.Equal(0, run.Exit);
        Assert.Equal(["main"], new LibraryCatalog(fx.Sandbox.Paths).Registered().Select(l => l.Name));
    }
}

/// <summary><c>kgsm event emit</c> and <c>kgsm event journal</c>.</summary>
public class EventCommandTests
{
    [Fact]
    public async Task Emit_WritesAnEnginePhase_WithTheActorAndOrigin()
    {
        var fx = OpsFixture.Create();

        CliRun run = await fx.Run("--actor", "system:scheduler", "--origin", "system", "event", "emit", "server.download.started", "g-1");

        Assert.Equal(0, run.Exit);
        JournalLine line = Assert.Single(fx.Journal());
        Assert.Equal("server.download.started", line.EventType);
        Assert.Equal("system:scheduler", line.Actor);
        Assert.Equal("system", line.Origin);
    }

    [Fact]
    public async Task Emit_TakesTheActorFromTheEnvironmentAScriptHandsDown()
    {
        var fx = OpsFixture.Create();
        fx.Session.Extra["KGSM_EVENT_ACTOR"] = "discord:haru";
        fx.Session.Extra["KGSM_EVENT_ORIGIN"] = "discord";

        await fx.Run("event", "emit", "server.deploy.finished", "g-1");

        JournalLine line = Assert.Single(fx.Journal());
        Assert.Equal("discord:haru", line.Actor);
        Assert.Equal("discord", line.Origin);
    }

    [Fact]
    public async Task Emit_RefusesAnEventTheEngineDoesNotWrite()
    {
        var fx = OpsFixture.Create();

        CliRun foreign = await fx.Run("event", "emit", "watchdog.instance.crashed", "g-1");
        CliRun nonsense = await fx.Run("event", "emit", "not an event", "g-1");

        Assert.Equal(1, foreign.Exit);
        Assert.Contains("not an event the engine writes", foreign.Err, StringComparison.Ordinal);
        Assert.Equal(1, nonsense.Exit);
        Assert.Empty(fx.Journal());
    }

    [Fact]
    public async Task Emit_NeedsTheFieldsThePayloadRequires_AndRefusesOnesItDoesNotHave()
    {
        var fx = OpsFixture.Create();

        CliRun missing = await fx.Run("event", "emit", "server.updated", "g-1", "--field", "OldVersion=1");
        CliRun extra = await fx.Run("event", "emit", "server.download.started", "g-1", "--field", "Surprise=1");
        CliRun malformed = await fx.Run("event", "emit", "backup.pruned", "g-1", "--field", "Deleted=x", "--field", "Kept=1", "--field", "Pinned=0");
        CliRun good = await fx.Run("event", "emit", "server.updated", "g-1", "--field", "OldVersion=1", "--field", "NewVersion=2");

        Assert.Contains("needs the field NewVersion", missing.Err, StringComparison.Ordinal);
        Assert.Contains("no field Surprise", extra.Err, StringComparison.Ordinal);
        Assert.Equal(1, malformed.Exit);
        Assert.Equal(0, good.Exit);
        Assert.Equal(["server.updated"], fx.Events());
    }

    [Fact]
    public void EveryEventTheEngineWrites_CanBeEmittedByName_WithItsFields()
    {
        var fx = OpsFixture.Create();
        Directory.CreateDirectory(fx.Sandbox.JournalDirectory);
        var recorder = new EventRecorder(
            new Journal.EventJournalWriter(new Journal.EventJournalOptions { Directory = fx.Sandbox.JournalDirectory }),
            fx.Sandbox.JournalDirectory, default);

        foreach (EventDescriptor descriptor in EngineEventCatalog.All)
        {
            var fields = descriptor.Fields.ToDictionary(
                f => f.Name,
                f => f.Name switch
                {
                    "Tier" => "user",
                    "OverridesSystem" or "RevertedToSystem" => "true",
                    _ when f.Shape == FieldShape.Number => "1",
                    _ => "value",
                },
                StringComparer.Ordinal);

            EventEmission.Emit(recorder, descriptor.Name.Value, "subject", fields);
        }

        Assert.Equal(EngineEventCatalog.All.Select(d => d.Name.Value), fx.Events());
    }

    // --- the journal ---

    [Fact]
    public async Task JournalStatus_CountsSegmentsEventsAndSize_AndSaysWhenThereIsNoDirectory()
    {
        var fx = OpsFixture.Create();
        CliRun empty = await fx.Run("event", "journal", "status", "--json");
        Assert.Contains("\"exists\":false", empty.Out, StringComparison.Ordinal);

        await fx.Run("event", "emit", "server.started", "g-1");
        await fx.Run("event", "emit", "server.stopped", "g-1");
        CliRun run = await fx.Run("event", "journal", "status", "--json");

        JournalStatusReport report = JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.JournalStatusReport)!;
        Assert.True(report.Exists);
        Assert.True(report.Writable);
        Assert.Equal(1, report.Segments);
        Assert.Equal(2, report.Events);
        Assert.Equal("2026-11-04.ndjson", report.Newest);
    }

    [Fact]
    public async Task JournalPrune_DeletesWholeSegmentsPastTheWindow_ByTheirNames_AndLeavesWhatIsNotADate()
    {
        var fx = OpsFixture.Create();
        Directory.CreateDirectory(fx.Sandbox.JournalDirectory);
        foreach (string name in new[] { "2026-07-01.ndjson", "2026-08-05.ndjson", "2026-08-06.ndjson", "2026-11-03.ndjson", "notes.ndjson" })
            File.WriteAllText(Path.Combine(fx.Sandbox.JournalDirectory, name), "{}\n");
        File.SetLastWriteTimeUtc(Path.Combine(fx.Sandbox.JournalDirectory, "2026-11-03.ndjson"), new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        fx.Session.Extra["Journal__RetentionDays"] = "90";

        CliRun unconfirmed = await fx.Run("event", "journal", "prune");
        CliRun run = await fx.Run("event", "journal", "prune", "--yes", "--json");

        Assert.Equal(2, unconfirmed.Exit);
        JournalPruneReport report = JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.JournalPruneReport)!;
        Assert.Equal("2026-08-06", report.Cutoff);
        Assert.Equal(["2026-07-01.ndjson", "2026-08-05.ndjson"], report.Pruned);
        Assert.True(File.Exists(Path.Combine(fx.Sandbox.JournalDirectory, "2026-08-06.ndjson")));
        Assert.True(File.Exists(Path.Combine(fx.Sandbox.JournalDirectory, "2026-11-03.ndjson")));
        Assert.True(File.Exists(Path.Combine(fx.Sandbox.JournalDirectory, "notes.ndjson")));
    }

    [Fact]
    public async Task JournalPrune_WithRetentionOff_KeepsEverything()
    {
        var fx = OpsFixture.Create();
        Directory.CreateDirectory(fx.Sandbox.JournalDirectory);
        File.WriteAllText(Path.Combine(fx.Sandbox.JournalDirectory, "2001-01-01.ndjson"), "{}\n");
        fx.Session.Extra["Journal__RetentionDays"] = "0";

        CliRun run = await fx.Run("event", "journal", "prune", "--yes");

        Assert.Equal(0, run.Exit);
        Assert.True(File.Exists(Path.Combine(fx.Sandbox.JournalDirectory, "2001-01-01.ndjson")));
    }

    [Fact]
    public async Task JournalVerify_AcceptsWellFormedSegments()
    {
        var fx = OpsFixture.Create();
        await fx.Run("event", "emit", "server.started", "g-1");

        CliRun run = await fx.Run("event", "journal", "verify");

        Assert.Equal(0, run.Exit);
        Assert.Contains("all well-formed", run.Out, StringComparison.Ordinal);
    }

    [Fact]
    public async Task JournalVerify_FindsATornLastLine_AnEmptyLine_ALineThatIsNotAnObject_AndNulBytes()
    {
        var fx = OpsFixture.Create();
        Directory.CreateDirectory(fx.Sandbox.JournalDirectory);
        string segment = Path.Combine(fx.Sandbox.JournalDirectory, "2026-11-04.ndjson");
        File.WriteAllBytes(segment, System.Text.Encoding.UTF8.GetBytes("{\"a\":1}\n\n[1,2]\n"
            + "\0\0\0{\"b\":2}\n{\"c\":3} trailing\n{\"torn\":"));

        CliRun run = await fx.Run("event", "journal", "verify", "--json");

        Assert.Equal(1, run.Exit);
        JournalVerifyReport report = JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.JournalVerifyReport)!;
        Assert.Equal(
            new[] { (2, "empty line"), (3, "is not one JSON object"), (4, "holds NUL bytes"), (5, "is not one JSON object"), (6, "is not one JSON object"), (6, "the last line has no terminator") },
            report.Problems.Select(p => (p.Line, p.Problem.Split(',')[0].Split(';')[0])));
    }

    [Fact]
    public async Task JournalVerify_TreatsAnUnterminatedButValidLastLineAsATornWrite()
    {
        var fx = OpsFixture.Create();
        Directory.CreateDirectory(fx.Sandbox.JournalDirectory);
        File.WriteAllText(Path.Combine(fx.Sandbox.JournalDirectory, "2026-11-04.ndjson"), "{\"a\":1}\n{\"b\":2}");

        CliRun run = await fx.Run("event", "journal", "verify", "--json");

        Assert.Equal(1, run.Exit);
        JournalProblem problem = Assert.Single(JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.JournalVerifyReport)!.Problems);
        Assert.Equal(2, problem.Line);
        Assert.Contains("no terminator", problem.Problem, StringComparison.Ordinal);
    }
}
