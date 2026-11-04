using TheKrystalShip.KGSM.Engine.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;

namespace TheKrystalShip.KGSM.Engine.Tests;

public class BackupReaderTests
{
    private static string Manifest(string id, string createdAt, string extra = "") =>
        $$"""
        {"schemaVersion":1,"id":"{{id}}","instance":"g-1","blueprint":"g","version":"1.2","createdAt":"{{createdAt}}",
         "compressed":true,"sources":["install","saves"],"sizeBytes":2048,"fileCount":12,"sha256":"abc"{{extra}}}
        """;

    private static string Add(Sandbox sandbox, string root, string id, string manifestJson)
    {
        sandbox.WriteFile(Path.Combine(root, id, "manifest.json"), manifestJson);
        return id;
    }

    [Fact]
    public void ABackupsDirectoryThatDoesNotExist_ListsNothing()
    {
        BackupListing listing = BackupReader.List(Path.Combine(Sandbox.Create().Root, "none"));

        Assert.Empty(listing.Backups);
        Assert.Empty(listing.Skipped);
    }

    [Fact]
    public void Backups_AreListedNewestFirst_ByTheirRecordedTime_NotTheirName()
    {
        var sandbox = Sandbox.Create();
        string root = sandbox.PathFor("backups", "x");
        Add(sandbox, root, "g-1-20260101T000000Z-aaaaaa", Manifest("g-1-20260101T000000Z-aaaaaa", "2026-01-03T00:00:00+00:00"));
        Add(sandbox, root, "g-1-20260102T000000Z-bbbbbb", Manifest("g-1-20260102T000000Z-bbbbbb", "2026-01-01T00:00:00+00:00"));
        Add(sandbox, root, "g-1-20260103T000000Z-cccccc", Manifest("g-1-20260103T000000Z-cccccc", "2026-01-02T00:00:00+00:00"));

        BackupListing listing = BackupReader.List(root);

        Assert.Equal(
            ["g-1-20260101T000000Z-aaaaaa", "g-1-20260103T000000Z-cccccc", "g-1-20260102T000000Z-bbbbbb"],
            listing.Backups.Select(b => b.Id));
    }

    [Fact]
    public void ABackup_ReadsEveryManifestField()
    {
        var sandbox = Sandbox.Create();
        string root = sandbox.PathFor("backups", "x");
        Add(sandbox, root, "b1", Manifest("b1", "2026-05-06T07:08:09+00:00", ""","reason":"pre-update","retention":"pinned","consistency":"flushed" """));

        Backup backup = Assert.Single(BackupReader.List(root).Backups);

        Assert.Equal("b1", backup.Id);
        Assert.Equal("g-1", backup.Instance);
        Assert.Equal("g", backup.Blueprint);
        Assert.Equal("1.2", backup.Version);
        Assert.Equal(new DateTimeOffset(2026, 5, 6, 7, 8, 9, TimeSpan.Zero), backup.CreatedAt);
        Assert.Equal(BackupReason.PreUpdate, backup.Reason);
        Assert.Equal(BackupRetention.Pinned, backup.Retention);
        Assert.True(backup.IsPinned);
        Assert.Equal(BackupConsistency.Flushed, backup.Consistency);
        Assert.True(backup.Compressed);
        Assert.Equal(["install", "saves"], backup.Sources);
        Assert.Equal(2048, backup.SizeBytes);
        Assert.Equal(12, backup.FileCount);
        Assert.Equal("abc", backup.Sha256);
    }

    [Fact]
    public void AnAbsentRetention_IsPrunable_AndAnAbsentReasonStaysNull()
    {
        var sandbox = Sandbox.Create();
        string root = sandbox.PathFor("backups", "x");
        Add(sandbox, root, "b1", Manifest("b1", "2026-05-06T07:08:09+00:00"));

        Backup backup = Assert.Single(BackupReader.List(root).Backups);

        Assert.Equal(BackupRetention.Prunable, backup.Retention);
        Assert.False(backup.IsPinned);
        Assert.Null(backup.Reason);
        Assert.Null(backup.Consistency);
    }

    [Fact]
    public void AnUncompressedBackup_HasNoDigest()
    {
        var sandbox = Sandbox.Create();
        string root = sandbox.PathFor("backups", "x");
        Add(sandbox, root, "b1", """{"schemaVersion":1,"id":"b1","createdAt":"2026-05-06T07:08:09+00:00","compressed":false,"sources":[],"sizeBytes":0,"fileCount":0,"sha256":null}""");

        Backup backup = Assert.Single(BackupReader.List(root).Backups);

        Assert.False(backup.Compressed);
        Assert.Null(backup.Sha256);
        Assert.Empty(backup.Sources);
    }

    [Fact]
    public void ADirectoryWithoutAReadableManifest_IsSkippedAndSaid_NeverDroppedSilently()
    {
        var sandbox = Sandbox.Create();
        string root = sandbox.PathFor("backups", "x");
        Add(sandbox, root, "good", Manifest("good", "2026-05-06T07:08:09+00:00"));
        Directory.CreateDirectory(Path.Combine(root, "no-manifest"));
        Add(sandbox, root, "broken", "{ not json");
        Add(sandbox, root, "future", """{"schemaVersion":2,"id":"future","createdAt":"2026-05-06T07:08:09+00:00"}""");
        Add(sandbox, root, "liar", Manifest("another-id", "2026-05-06T07:08:09+00:00"));
        Add(sandbox, root, "incomplete", """{"schemaVersion":1,"id":"incomplete","createdAt":"2026-05-06T07:08:09+00:00","compressed":true}""");
        Add(sandbox, root, "odd-reason", Manifest("odd-reason", "2026-05-06T07:08:09+00:00", ""","reason":"whim" """));
        sandbox.WriteFile(Path.Combine(root, "stray-file.txt"), "ignored");

        BackupListing listing = BackupReader.List(root);

        Assert.Equal(["good"], listing.Backups.Select(b => b.Id));
        Assert.Equal(["broken", "future", "incomplete", "liar", "no-manifest", "odd-reason"], listing.Skipped.Select(s => s.Directory));
        Assert.Equal("no manifest", listing.Skipped.Single(s => s.Directory == "no-manifest").Reason);
        Assert.Contains("schemaVersion 2", listing.Skipped.Single(s => s.Directory == "future").Reason, StringComparison.Ordinal);
        Assert.Contains("another-id", listing.Skipped.Single(s => s.Directory == "liar").Reason, StringComparison.Ordinal);
    }

    [Fact]
    public void FindingOneBackup_ByItsId()
    {
        var sandbox = Sandbox.Create();
        string root = sandbox.PathFor("backups", "x");
        Add(sandbox, root, "b1", Manifest("b1", "2026-05-06T07:08:09+00:00"));

        Assert.Equal("b1", BackupReader.Find(root, "b1")?.Id);
        Assert.Null(BackupReader.Find(root, "b2"));
    }

    [Fact]
    public void ReadingBackups_WritesNothing()
    {
        var sandbox = Sandbox.Create();
        string root = sandbox.PathFor("backups", "x");
        string manifest = Path.Combine(root, "b1", "manifest.json");
        Add(sandbox, root, "b1", """{"schemaVersion":1,"id":"b1","createdAt":"2026-05-06T07:08:09+00:00"}""");
        string before = File.ReadAllText(manifest);

        BackupReader.List(root);

        Assert.Equal(before, File.ReadAllText(manifest));
        Assert.Equal(["b1"], Directory.EnumerateFileSystemEntries(root).Select(Path.GetFileName));
        Assert.Equal(["manifest.json"], Directory.EnumerateFileSystemEntries(Path.Combine(root, "b1")).Select(Path.GetFileName));
    }
}
