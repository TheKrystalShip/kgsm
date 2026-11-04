using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Time.Testing;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Journal;

namespace TheKrystalShip.KGSM.Engine.Tests;

/// <summary>The envelope read back through a registered type, with the payload typed as the event under test.</summary>
internal sealed record Envelope<TData>(
    int V, string Id, string EventType, string? Severity, string? Outcome, string? Summary, TData Data,
    string Timestamp, string? Actor, string? Origin, string? Hostname, string? ProducerVersion);

[JsonSerializable(typeof(Envelope<BackupCreated>))]
[JsonSerializable(typeof(Envelope<BlueprintCreated>))]
[JsonSerializable(typeof(Envelope<BackupStarted>))]
internal sealed partial class EnvelopeJsonContext : JsonSerializerContext;

public partial class EventJournalTests
{
    private static readonly DateTimeOffset Noon = new(2026, 11, 4, 12, 30, 15, 250, TimeSpan.Zero);

    private static (EventJournalWriter Writer, Sandbox Sandbox, FakeTimeProvider Clock) NewWriter(DateTimeOffset? at = null)
    {
        var sandbox = Sandbox.Create();
        var clock = new FakeTimeProvider(at ?? Noon);
        var writer = new EventJournalWriter(
            new EventJournalOptions { Directory = sandbox.JournalDirectory, Hostname = "node-a", ProducerVersion = "4.0.0-dev.1" }, clock);
        return (writer, sandbox, clock);
    }

    private static string[] Lines(string path) => File.ReadAllText(path).Split('\n', StringSplitOptions.RemoveEmptyEntries);

    private static string WithoutId(string line) => IdPattern().Replace(line, "\"Id\":\"<id>\"");

    [GeneratedRegex("\"Id\":\"[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\"")]
    private static partial Regex IdPattern();

    [Fact]
    public void AFact_IsTheV2EnvelopeExactly_InTheDocumentedOrder()
    {
        var (writer, sandbox, _) = NewWriter();

        bool recorded = writer.Append(
            new BackupCreated { InstanceName = "g-1", Source = "saves", Version = "1.2" },
            new Provenance("local:claude", "api"),
            "backup of g-1 created");

        Assert.True(recorded);
        string line = Assert.Single(Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson")));
        Assert.Equal(
            """{"V":2,"Id":"<id>","EventType":"backup.created","Severity":"info","Outcome":"success","Summary":"backup of g-1 created","Data":{"InstanceName":"g-1","Source":"saves","Version":"1.2"},"Timestamp":"2026-11-04T12:30:15.250Z","Actor":"local:claude","Origin":"api","Hostname":"node-a","ProducerVersion":"4.0.0-dev.1"}""",
            WithoutId(line));
    }

    [Fact]
    public void TheLine_ReadsBackThroughItsTypes()
    {
        var (writer, sandbox, _) = NewWriter();
        writer.Append(new BackupCreated { InstanceName = "g-1", Source = "install", Version = "7" }, new Provenance("discord:haru", "discord"), "s");

        var envelope = JsonSerializer.Deserialize(
            Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"))[0], EnvelopeJsonContext.Default.EnvelopeBackupCreated)!;

        Assert.Equal(2, envelope.V);
        Assert.Equal("backup.created", envelope.EventType);
        Assert.Equal("g-1", envelope.Data.InstanceName);
        Assert.Equal("install", envelope.Data.Source);
        Assert.Equal("discord:haru", envelope.Actor);
        Assert.Equal("discord", envelope.Origin);
    }

    [Fact]
    public void ThePayload_IsPascalCase_LikeTheEnvelope()
    {
        var (writer, sandbox, _) = NewWriter();
        writer.Append(new BackupsPruned { InstanceName = "g-1", Deleted = 2, Kept = 3, Pinned = 1 });

        string line = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"))[0];

        Assert.Contains("\"Data\":{\"InstanceName\":\"g-1\",\"Deleted\":2,\"Kept\":3,\"Pinned\":1}", line, StringComparison.Ordinal);
    }

    [Fact]
    public void ABlueprintEvent_IsSpelledWithDots_AndCarriesItsOwnSubject()
    {
        var (writer, sandbox, _) = NewWriter();

        writer.Append(new BlueprintCreated { BlueprintName = "mygame", Tier = BlueprintTier.User, OverridesSystem = false, Runtime = "native" }, summary: "blueprint mygame created");
        writer.Append(new BlueprintRemoved { BlueprintName = "mygame", Tier = BlueprintTier.User, RevertedToSystem = null });
        writer.Append(new BlueprintUpdated { BlueprintName = "mygame", Tier = BlueprintTier.User });

        string[] lines = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"));
        Assert.Contains("\"EventType\":\"blueprint.created\"", lines[0], StringComparison.Ordinal);
        Assert.Contains("\"Data\":{\"BlueprintName\":\"mygame\",\"Tier\":\"user\",\"OverridesSystem\":false,\"Runtime\":\"native\"}", lines[0], StringComparison.Ordinal);
        Assert.Contains("\"EventType\":\"blueprint.removed\"", lines[1], StringComparison.Ordinal);
        Assert.DoesNotContain("RevertedToSystem", lines[1], StringComparison.Ordinal);
        Assert.Contains("\"EventType\":\"blueprint.updated\"", lines[2], StringComparison.Ordinal);
        Assert.DoesNotContain("-", Regex.Match(lines[0], "\"EventType\":\"([^\"]*)\"").Groups[1].Value, StringComparison.Ordinal);

        var envelope = JsonSerializer.Deserialize(lines[0], EnvelopeJsonContext.Default.EnvelopeBlueprintCreated)!;
        Assert.Equal(BlueprintTier.User, envelope.Data.Tier);
    }

    [Fact]
    public void APhaseBracket_CarriesNoSeverityOutcomeOrSummary()
    {
        var (writer, sandbox, _) = NewWriter();

        writer.Append(new BackupStarted { InstanceName = "g-1" }, new Provenance("local:u", null), summary: "ignored for a bracket");

        string line = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"))[0];
        Assert.Equal(
            """{"V":2,"Id":"<id>","EventType":"backup.started","Data":{"InstanceName":"g-1"},"Timestamp":"2026-11-04T12:30:15.250Z","Actor":"local:u","Hostname":"node-a","ProducerVersion":"4.0.0-dev.1"}""",
            WithoutId(line));
    }

    [Fact]
    public void ASeverityAndOutcome_ComeFromTheEventsOwnTraits()
    {
        var (writer, sandbox, _) = NewWriter();

        writer.Append(new PlayerBanned { InstanceName = "g-1", Target = "someone", Command = "ban someone" });
        writer.Append(new Stopped { InstanceName = "g-1" });
        writer.Append(new UpdateFailed { InstanceName = "g-1" });

        string[] lines = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"));
        Assert.Contains("\"Severity\":\"danger\",\"Outcome\":\"neutral\"", lines[0], StringComparison.Ordinal);
        Assert.Contains("\"Severity\":\"warn\",\"Outcome\":\"neutral\"", lines[1], StringComparison.Ordinal);
        Assert.Contains("\"Severity\":\"danger\",\"Outcome\":\"failure\"", lines[2], StringComparison.Ordinal);
    }

    [Fact]
    public void AnAbsentActorOrOrigin_IsLeftOut_NotWrittenAsNull()
    {
        var (writer, sandbox, _) = NewWriter();

        writer.Append(new Started { InstanceName = "g-1" });

        string line = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"))[0];
        Assert.DoesNotContain("Actor", line, StringComparison.Ordinal);
        Assert.DoesNotContain("Origin", line, StringComparison.Ordinal);
        Assert.DoesNotContain("null", line, StringComparison.Ordinal);
        Assert.DoesNotContain("Summary", line, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("bare")]
    [InlineData(":nobody")]
    [InlineData("nobody:")]
    [InlineData("a:b:c")]
    [InlineData("")]
    public void AnActorThatIsNotProviderColonName_IsRecordedAsUnknown_NeverReplaced(string actor)
    {
        var (writer, sandbox, _) = NewWriter();

        writer.Append(new Started { InstanceName = "g-1" }, new Provenance(actor, "ui"));

        string line = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"))[0];
        Assert.DoesNotContain("Actor", line, StringComparison.Ordinal);
        Assert.Contains("\"Origin\":\"ui\"", line, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("ui")]
    [InlineData("assistant")]
    [InlineData("discord")]
    [InlineData("api")]
    [InlineData("notification")]
    [InlineData("system")]
    [InlineData("reactor")]
    public void EveryOriginOfTheClosedSet_IsAccepted(string origin)
    {
        var (writer, sandbox, _) = NewWriter();

        writer.Append(new Started { InstanceName = "g-1" }, new Provenance(null, origin));

        Assert.Contains($"\"Origin\":\"{origin}\"", Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"))[0], StringComparison.Ordinal);
    }

    [Fact]
    public void AnOriginOutsideTheClosedSet_IsRecordedAsUnknown()
    {
        var (writer, sandbox, _) = NewWriter();

        writer.Append(new Started { InstanceName = "g-1" }, new Provenance("local:u", "terminal"));

        string line = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"))[0];
        Assert.DoesNotContain("Origin", line, StringComparison.Ordinal);
        Assert.Contains("\"Actor\":\"local:u\"", line, StringComparison.Ordinal);
    }

    [Fact]
    public void TheTimestamp_HasMillisecondPrecision_AndTheIdIsAUuidV7()
    {
        var (writer, sandbox, _) = NewWriter(new DateTimeOffset(2026, 1, 2, 3, 4, 5, 6, TimeSpan.Zero));

        writer.Append(new Started { InstanceName = "g-1" });

        string line = Lines(Path.Combine(sandbox.JournalDirectory, "2026-01-02.ndjson"))[0];
        Assert.Contains("\"Timestamp\":\"2026-01-02T03:04:05.006Z\"", line, StringComparison.Ordinal);
        Assert.Matches(IdPattern(), line);
    }

    [Fact]
    public void TheSegmentAndTheTimestamp_ComeFromOneReadingOfTheClock()
    {
        var (writer, sandbox, clock) = NewWriter(new DateTimeOffset(2026, 11, 4, 23, 59, 59, 999, TimeSpan.Zero));

        writer.Append(new Started { InstanceName = "last" });
        clock.Advance(TimeSpan.FromMilliseconds(1));
        writer.Append(new Started { InstanceName = "first" });

        string before = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson")).Single();
        string after = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-05.ndjson")).Single();
        Assert.Contains("\"Timestamp\":\"2026-11-04T23:59:59.999Z\"", before, StringComparison.Ordinal);
        Assert.Contains("\"Timestamp\":\"2026-11-05T00:00:00.000Z\"", after, StringComparison.Ordinal);
    }

    [Fact]
    public void ASegmentIsAppendedTo_NeverRewritten()
    {
        var (writer, sandbox, _) = NewWriter();
        string segment = Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson");

        writer.Append(new Started { InstanceName = "one" });
        string first = File.ReadAllText(segment);
        writer.Append(new Stopped { InstanceName = "two" });

        string both = File.ReadAllText(segment);
        Assert.StartsWith(first, both, StringComparison.Ordinal);
        Assert.Equal(2, Lines(segment).Length);
        Assert.EndsWith("\n", both, StringComparison.Ordinal);
    }

    [Fact]
    public void ManyWritersOnOneSegment_NeverInterleaveWithinALine()
    {
        var (writer, sandbox, _) = NewWriter();

        Parallel.For(0, 300, i => writer.Append(new ConfigChanged { InstanceName = $"g-{i}", Key = "level" + i }));

        string[] lines = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"));
        Assert.Equal(300, lines.Length);
        Assert.All(lines, line =>
        {
            Assert.StartsWith("{\"V\":2,", line, StringComparison.Ordinal);
            Assert.EndsWith("\"ProducerVersion\":\"4.0.0-dev.1\"}", line, StringComparison.Ordinal);
        });
        Assert.Equal(300, lines.Select(l => IdPattern().Match(l).Value).Distinct().Count());
    }

    [Fact]
    public void AJournalThatCannotBeWritten_ReportsFalse_InsteadOfFailingTheOperation()
    {
        var sandbox = Sandbox.Create();
        string blocker = sandbox.WriteFile(sandbox.PathFor("not-a-directory"), "a file");
        var writer = new EventJournalWriter(new EventJournalOptions { Directory = Path.Combine(blocker, "events") }, new FakeTimeProvider(Noon));

        Assert.False(writer.Append(new Started { InstanceName = "g-1" }));
    }

    [Fact]
    public void TheJournalDirectory_IsCreatedOnFirstAppend()
    {
        var (writer, sandbox, _) = NewWriter();
        Assert.False(Directory.Exists(sandbox.JournalDirectory));

        writer.Append(new Started { InstanceName = "g-1" });

        Assert.True(Directory.Exists(sandbox.JournalDirectory));
    }

    [Fact]
    public void ASecretIsNeverInAConfigChangeEvent_OnlyTheKey()
    {
        var (writer, sandbox, _) = NewWriter();

        writer.Append(new ConfigChanged { InstanceName = "g-1", Key = "rconPassword" });

        string line = Lines(Path.Combine(sandbox.JournalDirectory, "2026-11-04.ndjson"))[0];
        Assert.Contains("\"Data\":{\"InstanceName\":\"g-1\",\"Key\":\"rconPassword\"}", line, StringComparison.Ordinal);
    }

    [Fact]
    public void TheProducerVersion_IsAReleaseNumber_NotAFourPartAssemblyVersion()
    {
        Assert.Matches(@"^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$", EngineVersion.Current);
    }
}
