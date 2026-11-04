using System.Security.Cryptography;
using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Backups;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.Testing;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>Backups: creation, the manifest, listing, restore and retention, for both runtimes' shared script code.</summary>
public partial class ScriptBackupTests
{
    private static ScriptWorld World(Func<Contracts.Instances.InstanceConfig, Contracts.Instances.InstanceConfig>? shape = null)
    {
        ScriptWorld world = ScriptWorld.Native(shape);
        File.WriteAllText(Path.Combine(world.Install, "game.bin"), "game");
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "world");
        return world;
    }

    private static async Task<string> CreateAsync(ScriptWorld world, params string[] extra)
    {
        ScriptRun run = await world.RunAsync(["create-backup", .. extra]);
        Assert.True(run.Exit == 0, run.Err);
        return run.LastOutLine;
    }

    // --- creation ---

    [Fact]
    public async Task Create_MakesADirectoryNamedByTheInstanceTheTimeAndSixHex_AndPrintsItsIdLast()
    {
        using ScriptWorld world = World();

        ScriptRun run = await world.RunAsync("create-backup");

        Assert.Equal(0, run.Exit);
        string id = run.LastOutLine;
        Assert.Matches(IdPattern(), id);
        Assert.True(File.Exists(Path.Combine(world.BackupsDirectory, id, "manifest.json")));
        Assert.True(File.Exists(Path.Combine(world.BackupsDirectory, id, "data.tar.gz")));
    }

    [Fact]
    public async Task Create_WritesAManifestTheEngineReads_AsItReadsAnyBackup()
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.VersionFile, "1.2.3\n");

        string id = await CreateAsync(world);

        BackupManifest manifest = ScriptJson.Manifest(world, id);
        Assert.Equal(SchemaVersions.BackupManifest, manifest.SchemaVersion);
        Assert.Equal(id, manifest.Id);
        Assert.Equal(ScriptWorld.Id, manifest.Instance);
        Assert.Equal("g", manifest.Blueprint);
        Assert.Equal("1.2.3", manifest.Version);
        Assert.Equal(BackupReason.Manual, manifest.Reason);
        Assert.Equal(BackupRetention.Prunable, manifest.Retention);
        Assert.True(manifest.Compressed);
        Assert.Equal(BackupConsistency.Cold, manifest.Consistency);
        Assert.Equal(["install", "saves"], manifest.Sources);
        Assert.Equal(3, manifest.FileCount);
        string archive = Path.Combine(world.BackupsDirectory, id, "data.tar.gz");
        Assert.Equal(new FileInfo(archive).Length, manifest.SizeBytes);
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(archive))), manifest.Sha256);
        Assert.True(DateTimeOffset.UtcNow - manifest.CreatedAt < TimeSpan.FromMinutes(5));

        BackupListing listing = BackupReader.List(world.BackupsDirectory);
        Assert.Equal(id, Assert.Single(listing.Backups).Id);
        Assert.Empty(listing.Skipped);
    }

    [Fact]
    public async Task TheManifest_IsCamelCase_AndCarriesSchemaVersion()
    {
        // The manifest's keys are camelCase and it records its schemaVersion.
        using ScriptWorld world = World();
        string id = await CreateAsync(world);

        string text = File.ReadAllText(Path.Combine(world.BackupsDirectory, id, "manifest.json"));
        string[] keys = [.. KeyPattern().Matches(text).Select(m => m.Groups[1].Value).Order(StringComparer.Ordinal)];

        Assert.Equal(
            ["blueprint", "compressed", "consistency", "createdAt", "fileCount", "id", "instance", "reason", "retention", "schemaVersion", "sha256", "sizeBytes", "sources", "version"],
            keys);
    }

    [Fact]
    public async Task Create_RecordsNoVersion_WhenTheInstalledVersionIsUnknown()
    {
        using ScriptWorld world = World();

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world));

        Assert.Null(manifest.Version);
    }

    [Fact]
    public async Task Create_WithCompressionOff_CopiesATree_AndRecordsNoDigest()
    {
        using ScriptWorld world = World(c => c with { CompressBackups = false });

        string id = await CreateAsync(world);

        BackupManifest manifest = ScriptJson.Manifest(world, id);
        Assert.False(manifest.Compressed);
        Assert.Null(manifest.Sha256);
        Assert.Equal("world", File.ReadAllText(Path.Combine(world.BackupsDirectory, id, "data", "saves", "world.sav")));
        Assert.True(manifest.SizeBytes > 0);
    }

    [Fact]
    public async Task Create_CapturesOnlyTheSubtreesThatHoldSomething()
    {
        using ScriptWorld world = World();
        File.Delete(Path.Combine(world.Saves, "world.sav"));

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world));

        Assert.Equal(["install"], manifest.Sources);
    }

    [Fact]
    public async Task Create_WithNothingToCapture_FailsAndLeavesNothingBehind()
    {
        using ScriptWorld world = ScriptWorld.Native();
        File.Delete(Path.Combine(world.Install, "server"));

        ScriptRun run = await world.RunAsync("create-backup");

        Assert.Equal(1, run.Exit);
        Assert.Contains("Nothing to back up", run.Err, StringComparison.Ordinal);
        Assert.False(Directory.Exists(world.BackupsDirectory) && Directory.EnumerateFileSystemEntries(world.BackupsDirectory).Any());
    }

    [Theory]
    [InlineData("manual", BackupReason.Manual)]
    [InlineData("scheduled", BackupReason.Scheduled)]
    [InlineData("pre-update", BackupReason.PreUpdate)]
    [InlineData("pre-restore", BackupReason.PreRestore)]
    [InlineData("incident", BackupReason.Incident)]
    public async Task Create_RecordsTheReason(string reason, BackupReason expected)
    {
        using ScriptWorld world = World();

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world, "--reason", reason));

        Assert.Equal(expected, manifest.Reason);
    }

    [Fact]
    public async Task Create_RecordsAPinnedRetention()
    {
        using ScriptWorld world = World();

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world, "--retention", "pinned"));

        Assert.Equal(BackupRetention.Pinned, manifest.Retention);
    }

    [Theory]
    [InlineData("--reason", "whim")]
    [InlineData("--retention", "forever")]
    [InlineData("--run-state", "maybe")]
    [InlineData("--frobnicate", "x")]
    public async Task Create_RefusesAValueOutsideTheClosedSets_BeforeArchivingAnything(string option, string value)
    {
        using ScriptWorld world = World();

        ScriptRun run = await world.RunAsync("create-backup", option, value);

        Assert.Equal(8, run.Exit);
        Assert.False(Directory.Exists(world.BackupsDirectory));
    }

    // --- consistency, measured per backup ---

    [Fact]
    public async Task Consistency_IsFlushed_WhenARunningInstanceAcceptedItsSaveCommand()
    {
        using ScriptWorld world = World();
        await world.StartGameAsync();

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world));

        Assert.Equal(BackupConsistency.Flushed, manifest.Consistency);
        await Eventually.Holds(() => world.Recorded("game/input").Contains("save"), "the game read the save command");
    }

    [Fact]
    public async Task Consistency_IsHot_WhenTheSaveCommandIsTheStopCommand()
    {
        // Some games declare one token for both, and sending it would shut the server down to back it up.
        using ScriptWorld world = World(c => c with { SaveCommand = "exit", StopCommand = "exit" });
        await world.StartGameAsync();

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world));

        Assert.Equal(BackupConsistency.Hot, manifest.Consistency);
        Assert.Empty(world.Recorded("game/input"));
    }

    [Fact]
    public async Task Consistency_IsHot_WhenARunningInstanceDeclaresNoSaveCommand()
    {
        using ScriptWorld world = World(c => c with { SaveCommand = string.Empty });

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world, "--run-state", "active"));

        Assert.Equal(BackupConsistency.Hot, manifest.Consistency);
    }

    [Fact]
    public async Task Consistency_IsHot_WhenTheSaveCommandCannotBeDelivered()
    {
        using ScriptWorld world = World();

        ScriptRun run = await world.RunAsync("create-backup", "--run-state", "active");

        Assert.Equal(0, run.Exit);
        Assert.Contains("archiving without a flush", run.Err, StringComparison.Ordinal);
        Assert.Equal(BackupConsistency.Hot, ScriptJson.Manifest(world, run.LastOutLine).Consistency);
    }

    [Fact]
    public async Task Consistency_IsUnknown_WhenTheCallerCannotSayWhetherItRuns()
    {
        using ScriptWorld world = World();

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world, "--run-state", "unknown"));

        Assert.Null(manifest.Consistency);
    }

    [Fact]
    public async Task ARunningInstance_IsBackedUpBySavesAlone_WhenSavesHoldSomething()
    {
        using ScriptWorld world = World();

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world, "--run-state", "active"));

        Assert.Equal(["saves"], manifest.Sources);
    }

    [Fact]
    public async Task ARunningInstance_IsBackedUpWhole_WhenItsSavesAreEmpty()
    {
        // Several games keep their world inside install/, and there saves alone would back up nothing.
        using ScriptWorld world = World();
        File.Delete(Path.Combine(world.Saves, "world.sav"));

        BackupManifest manifest = ScriptJson.Manifest(world, await CreateAsync(world, "--run-state", "active"));

        Assert.Equal(["install"], manifest.Sources);
    }

    // --- atomic and staged ---

    [Fact]
    public async Task Create_LeavesNoStagingDirectoryBehind()
    {
        using ScriptWorld world = World();

        await CreateAsync(world);

        Assert.All(Directory.GetFileSystemEntries(world.BackupsDirectory), entry => Assert.DoesNotContain(".partial", entry, StringComparison.Ordinal));
        Assert.Single(Directory.GetFileSystemEntries(world.BackupsDirectory));
    }

    [Fact]
    public async Task AFailedArchive_LeavesNoBackupAndNoPartialOne()
    {
        using ScriptWorld world = World();
        string unreadable = Path.Combine(world.Saves, "locked.sav");
        File.WriteAllText(unreadable, "x");
        File.SetUnixFileMode(unreadable, UnixFileMode.None);

        ScriptRun run = await world.RunAsync("create-backup");

        File.SetUnixFileMode(unreadable, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        Assert.Equal(1, run.Exit);
        Assert.Empty(Directory.GetFileSystemEntries(world.BackupsDirectory));
    }

    [Fact]
    public async Task ABackupBeingBuilt_IsInvisibleToEveryListing()
    {
        using ScriptWorld world = World();
        string partial = Path.Combine(world.BackupsDirectory, ".g-1-20260101T000000Z-abcdef.partial");
        Directory.CreateDirectory(partial);
        File.WriteAllText(Path.Combine(partial, "manifest.json"), "{}");

        Assert.Equal(string.Empty, (await world.RunAsync("backups")).Out);
        Assert.Empty(BackupReader.List(world.BackupsDirectory).Backups);
        Assert.Empty(BackupReader.List(world.BackupsDirectory).Skipped);
    }

    // --- listing ---

    [Fact]
    public async Task Backups_ListsIdsNewestFirst_AndTheJsonCarriesEveryManifest()
    {
        using ScriptWorld world = World();
        string older = WriteManifest(world, "g-1-20260101T000000Z-aaaaaa", createdAt: "2026-01-01T00:00:00Z");
        string newer = WriteManifest(world, "g-1-20260301T000000Z-bbbbbb", createdAt: "2026-03-01T00:00:00Z");

        Assert.Equal($"{newer}\n{older}\n", (await world.RunAsync("backups")).Out);

        BackupManifest[] manifests = ScriptJson.Manifests((await world.RunAsync("backups", "--json")).Out);
        Assert.Equal([newer, older], manifests.Select(m => m.Id));
    }

    [Fact]
    public async Task Backups_Json_IsAnEmptyArray_WhenThereAreNoBackups()
    {
        using ScriptWorld world = World();

        Assert.Equal("[]\n", (await world.RunAsync("backups", "--json")).Out);
        Assert.Equal(string.Empty, (await world.RunAsync("backups")).Out);
    }

    [Fact]
    public async Task Backups_FillsAnAbsentRetentionAsPrunable_AndAnAbsentReasonAsNull()
    {
        using ScriptWorld world = World();
        string id = "g-1-20260101T000000Z-aaaaaa";
        Directory.CreateDirectory(Path.Combine(world.BackupsDirectory, id));
        File.WriteAllText(
            Path.Combine(world.BackupsDirectory, id, "manifest.json"),
            $$"""{"schemaVersion":1,"id":"{{id}}","createdAt":"2026-01-01T00:00:00Z","compressed":true,"sources":["saves"],"sizeBytes":1,"fileCount":1}""");

        string json = (await world.RunAsync("backups", "--json")).Out;

        Assert.Contains("\"retention\":\"prunable\"", json, StringComparison.Ordinal);
        Assert.Contains("\"reason\":null", json, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Backups_SkipsWhatIsNotABackup()
    {
        using ScriptWorld world = World();
        string good = WriteManifest(world, "g-1-20260101T000000Z-aaaaaa", createdAt: "2026-01-01T00:00:00Z");
        Directory.CreateDirectory(Path.Combine(world.BackupsDirectory, "no-manifest"));
        WriteManifest(world, "wrong-name", createdAt: "2026-02-01T00:00:00Z", idInManifest: "another-id");
        WriteManifest(world, "future", createdAt: "2026-02-01T00:00:00Z", schemaVersion: 9);
        Directory.CreateDirectory(Path.Combine(world.BackupsDirectory, "garbled"));
        File.WriteAllText(Path.Combine(world.BackupsDirectory, "garbled", "manifest.json"), "{not json");

        string ids = (await world.RunAsync("backups")).Out;

        Assert.Equal($"{good}\n", ids);
        Assert.Equal([good], BackupReader.List(world.BackupsDirectory).Backups.Select(b => b.Id));
    }

    [Fact]
    public async Task TheOlderSpelling_BackupCreateAndList_StillWorks()
    {
        using ScriptWorld world = World();

        ScriptRun created = await world.RunAsync("backup", "create");
        ScriptRun listed = await world.RunAsync("backup", "list");

        Assert.Equal(0, created.Exit);
        Assert.Equal(created.LastOutLine + "\n", listed.Out);
        Assert.Equal(7, (await world.RunAsync("backup")).Exit);
        Assert.Equal(8, (await world.RunAsync("backup", "frobnicate")).Exit);
        Assert.Equal(7, (await world.RunAsync("backup", "restore")).Exit);
    }

    // --- restore ---

    [Fact]
    public async Task Restore_PutsBackWhatTheBackupCaptured_AndRemovesWhatItDidNot()
    {
        using ScriptWorld world = World();
        File.WriteAllText(world.VersionFile, "1.0\n");
        string id = await CreateAsync(world);
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "changed");
        File.WriteAllText(Path.Combine(world.Saves, "extra.sav"), "extra");
        File.WriteAllText(Path.Combine(world.Saves, ".hidden"), "dotfile");
        File.WriteAllText(world.VersionFile, "2.0\n");

        ScriptRun run = await world.RunAsync("restore-backup", id);

        Assert.Equal(0, run.Exit);
        Assert.Equal("world", File.ReadAllText(Path.Combine(world.Saves, "world.sav")));
        Assert.False(File.Exists(Path.Combine(world.Saves, "extra.sav")));
        Assert.False(File.Exists(Path.Combine(world.Saves, ".hidden")), "a restore clears a subtree whole, dotfiles included");
        Assert.Equal("1.0", File.ReadAllText(world.VersionFile).Trim());
    }

    [Fact]
    public async Task Restore_FromAnUncompressedBackup_Works()
    {
        using ScriptWorld world = World(c => c with { CompressBackups = false });
        string id = await CreateAsync(world);
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "changed");

        Assert.Equal(0, (await world.RunAsync("restore-backup", id)).Exit);

        Assert.Equal("world", File.ReadAllText(Path.Combine(world.Saves, "world.sav")));
    }

    [Fact]
    public async Task Restore_TakesAPreRestoreSafetyBackup_OfWhatIsThere()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "work done since");

        Assert.Equal(0, (await world.RunAsync("restore-backup", id)).Exit);

        BackupManifest safety = Assert.Single(BackupReader.List(world.BackupsDirectory).Backups.Where(b => b.Reason == BackupReason.PreRestore))
            is { } found ? ScriptJson.Manifest(world, found.Id) : null!;
        Assert.Equal(BackupConsistency.Cold, safety.Consistency);
    }

    [Fact]
    public async Task Restore_PassesTheCallersRunStateToTheSafetyBackup()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);

        Assert.Equal(0, (await world.RunAsync("restore-backup", id, "--run-state", "unknown")).Exit);

        Backup safety = Assert.Single(BackupReader.List(world.BackupsDirectory).Backups, b => b.Reason == BackupReason.PreRestore);
        Assert.Null(safety.Consistency);
    }

    [Fact]
    public async Task Restore_RefusesACorruptArchive_WhileTheCurrentStateIsStillIntact()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);
        File.AppendAllText(Path.Combine(world.BackupsDirectory, id, "data.tar.gz"), "corruption");
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "current");

        ScriptRun run = await world.RunAsync("restore-backup", id);

        Assert.Equal(1, run.Exit);
        Assert.Contains("Checksum mismatch", run.Err, StringComparison.Ordinal);
        Assert.Equal("current", File.ReadAllText(Path.Combine(world.Saves, "world.sav")));
        Assert.Empty(BackupReader.List(world.BackupsDirectory).Backups.Where(b => b.Reason == BackupReason.PreRestore));
    }

    [Fact]
    public async Task Restore_AbortsWhenTheSafetyBackupCannotBeTaken_AndChangesNothing()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);
        File.WriteAllText(Path.Combine(world.Saves, "world.sav"), "current");
        File.SetUnixFileMode(world.BackupsDirectory, UnixFileMode.UserRead | UnixFileMode.UserExecute);

        ScriptRun run = await world.RunAsync("restore-backup", id);

        File.SetUnixFileMode(world.BackupsDirectory, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        Assert.Equal(1, run.Exit);
        Assert.Contains("aborting to prevent data loss", run.Err, StringComparison.Ordinal);
        Assert.Equal("current", File.ReadAllText(Path.Combine(world.Saves, "world.sav")));
    }

    [Fact]
    public async Task Restore_OntoEmptyData_TakesNoSafetyBackup()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);
        File.Delete(Path.Combine(world.Saves, "world.sav"));
        File.Delete(Path.Combine(world.Install, "game.bin"));
        File.Delete(Path.Combine(world.Install, "server"));

        Assert.Equal(0, (await world.RunAsync("restore-backup", id)).Exit);

        Assert.Single(BackupReader.List(world.BackupsDirectory).Backups);
        Assert.Equal("world", File.ReadAllText(Path.Combine(world.Saves, "world.sav")));
    }

    [Fact]
    public async Task Restore_ClearsTheVersion_WhenTheBackupRecordedNone()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);
        File.WriteAllText(world.VersionFile, "9.9\n");

        Assert.Equal(0, (await world.RunAsync("restore-backup", id)).Exit);

        Assert.False(File.Exists(world.VersionFile), "a backup that recorded no version leaves no version file, rather than the word unknown");
    }

    [Fact]
    public async Task Restore_OfABackupThatDoesNotExist_ExitsWithTheNotFoundStatus()
    {
        using ScriptWorld world = World();

        ScriptRun run = await world.RunAsync("restore-backup", "g-1-20260101T000000Z-aaaaaa");

        Assert.Equal(25, run.Exit);
    }

    [Theory]
    [InlineData("../escape")]
    [InlineData("a/b")]
    [InlineData(".hidden")]
    public async Task Restore_RefusesAnIdThatIsAPath(string id)
    {
        using ScriptWorld world = World();

        Assert.Equal(8, (await world.RunAsync("restore-backup", id)).Exit);
    }

    [Fact]
    public async Task Restore_RefusesAManifestThatNamesASourceOutsideInstallAndSaves()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);
        string manifest = Path.Combine(world.BackupsDirectory, id, "manifest.json");
        File.WriteAllText(manifest, File.ReadAllText(manifest).Replace("\"sources\":[\"install\",\"saves\"]", "\"sources\":[\"../../etc\"]", StringComparison.Ordinal));

        ScriptRun run = await world.RunAsync("restore-backup", id);

        Assert.Equal(1, run.Exit);
        Assert.Contains("refusing to restore", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Restore_RefusesAManifestOfAnUnknownSchemaVersion()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);
        string manifest = Path.Combine(world.BackupsDirectory, id, "manifest.json");
        File.WriteAllText(manifest, File.ReadAllText(manifest).Replace("\"schemaVersion\":1", "\"schemaVersion\":2", StringComparison.Ordinal));

        ScriptRun run = await world.RunAsync("restore-backup", id);

        Assert.Equal(1, run.Exit);
        Assert.Contains("schemaVersion", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Restore_WithNoId_IsAMissingArgument()
    {
        using ScriptWorld world = World();

        Assert.Equal(7, (await world.RunAsync("restore-backup")).Exit);
    }

    // --- retention ---

    [Fact]
    public async Task PinAndUnpin_SetTheRetention_AndLeaveTheReasonAlone()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world, "--reason", "incident");

        Assert.Equal(0, (await world.RunAsync("pin-backup", id)).Exit);
        BackupManifest pinned = ScriptJson.Manifest(world, id);
        Assert.Equal(BackupRetention.Pinned, pinned.Retention);
        Assert.Equal(BackupReason.Incident, pinned.Reason);

        Assert.Equal(0, (await world.RunAsync("unpin-backup", id)).Exit);
        Assert.Equal(BackupRetention.Prunable, ScriptJson.Manifest(world, id).Retention);
    }

    [Fact]
    public async Task Pin_LeavesTheArchiveRestorable_TheDigestCoversThePayloadNotTheManifest()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);
        await world.RunAsync("pin-backup", id);

        Assert.Equal(0, (await world.RunAsync("restore-backup", id)).Exit);
    }

    [Fact]
    public async Task Pin_LeavesNoStagedManifestBehind()
    {
        using ScriptWorld world = World();
        string id = await CreateAsync(world);

        await world.RunAsync("pin-backup", id);

        Assert.Equal(["data.tar.gz", "manifest.json"], Directory.GetFiles(Path.Combine(world.BackupsDirectory, id)).Select(Path.GetFileName).Order(StringComparer.Ordinal));
    }

    [Fact]
    public async Task Pin_GivesAnOldManifestAnExplicitNullReason()
    {
        using ScriptWorld world = World();
        string id = "g-1-20260101T000000Z-aaaaaa";
        Directory.CreateDirectory(Path.Combine(world.BackupsDirectory, id));
        string manifest = Path.Combine(world.BackupsDirectory, id, "manifest.json");
        File.WriteAllText(manifest, $$"""{"schemaVersion":1,"id":"{{id}}","createdAt":"2026-01-01T00:00:00Z","compressed":true,"sources":["saves"],"sizeBytes":1,"fileCount":1}""");

        Assert.Equal(0, (await world.RunAsync("pin-backup", id)).Exit);

        string text = File.ReadAllText(manifest);
        Assert.Contains("\"reason\":null", text, StringComparison.Ordinal);
        Assert.Contains("\"retention\":\"pinned\"", text, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("pin-backup")]
    [InlineData("unpin-backup")]
    public async Task PinOfABackupThatDoesNotExist_ExitsWithTheNotFoundStatus_NotWhateverRanLast(string verb)
    {
        // A missing backup exits with the defined not-found status, never with whatever ran last.
        using ScriptWorld world = World();

        ScriptRun run = await world.RunAsync(verb, "g-1-20260101T000000Z-aaaaaa");

        Assert.Equal(25, run.Exit);
        Assert.Contains("Not a backup", run.Err, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("pin-backup")]
    [InlineData("unpin-backup")]
    public async Task Pin_WithNoId_IsAMissingArgument(string verb)
    {
        using ScriptWorld world = World();

        Assert.Equal(7, (await world.RunAsync(verb)).Exit);
    }

    [Fact]
    public async Task Pin_RefusesAnIdThatIsAPath()
    {
        using ScriptWorld world = World();

        Assert.Equal(8, (await world.RunAsync("pin-backup", "../x")).Exit);
    }

    private static string WriteManifest(ScriptWorld world, string directory, string createdAt, string? idInManifest = null, int schemaVersion = 1)
    {
        string path = Path.Combine(world.BackupsDirectory, directory);
        Directory.CreateDirectory(path);
        File.WriteAllText(
            Path.Combine(path, "manifest.json"),
            $$"""{"schemaVersion":{{schemaVersion}},"id":"{{idInManifest ?? directory}}","instance":"g-1","blueprint":"g","version":null,"createdAt":"{{createdAt}}","reason":"manual","retention":"prunable","compressed":true,"consistency":"cold","sources":["saves"],"sizeBytes":1,"fileCount":1,"sha256":null}""");
        return directory;
    }

    [GeneratedRegex(@"^g-1-\d{8}T\d{6}Z-[0-9a-f]{6}$")]
    private static partial Regex IdPattern();

    [GeneratedRegex("\"([A-Za-z0-9_]+)\":")]
    private static partial Regex KeyPattern();
}
