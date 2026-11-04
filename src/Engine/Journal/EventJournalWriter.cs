using System.Buffers;
using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts.Events;

namespace TheKrystalShip.KGSM.Engine.Journal;

/// <summary>Where the engine's journal is and how it labels its lines.</summary>
public sealed record EventJournalOptions
{
    /// <summary>The directory the daily segments are appended to.</summary>
    public required string Directory { get; init; }

    /// <summary>Stamped on every line; null leaves the field out.</summary>
    public string? ProducerVersion { get; init; } = EngineVersion.Current;

    /// <summary>Stamped on every line; null leaves the field out.</summary>
    public string? Hostname { get; init; } = Environment.MachineName;
}

/// <summary>
/// Appends the engine's events to its journal in the V2 envelope of <c>reference/event-envelope.md</c>, one
/// whole line per event in one append. The envelope is composed by hand so field order is the documented
/// one and an absent field is omitted rather than written as null; the payload goes through its registered
/// type. A payload declares its own name, so a raw string cannot reach the writer.
/// </summary>
/// <remarks>
/// The timestamp and the segment come from one reading of the clock, so an event at midnight lands in the
/// day it says. The whole line leaves in a single <c>O_APPEND</c> write (<see cref="AppendOnlyFile"/>), which is
/// what lets any number of writers and readers share a segment with no lock.
/// </remarks>
public sealed class EventJournalWriter(
    EventJournalOptions options, TimeProvider? clock = null, ILogger<EventJournalWriter>? logger = null)
{
    /// <summary>The largest line that is appended atomically: <c>PIPE_BUF</c> on Linux.</summary>
    public const int AtomicWriteLimitBytes = 4096;

    /// <summary>The envelope schema version this writer produces.</summary>
    public const int EnvelopeVersion = 2;

    /// <summary>How a <c>Timestamp</c> is spelled: millisecond-precision UTC.</summary>
    public const string TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fff'Z'";

    private readonly TimeProvider _clock = clock ?? TimeProvider.System;

    /// <summary>
    /// Records one event. Returns false, after logging, when the line could not be written: the action
    /// already happened, and failing it because recording it did not work would trade a missing audit line
    /// for a broken operation. The caller decides what to do with the answer.
    /// </summary>
    /// <param name="data">The payload; its type says which event this is.</param>
    /// <param name="provenance">Who drove it and through which surface; an invalid half is dropped.</param>
    /// <param name="summary">One line of prose for a fact; ignored for a phase bracket, which no feed renders.</param>
    public bool Append<TData>(TData data, Provenance provenance = default, string? summary = null)
        where TData : EngineEventData, IEngineEvent<TData>
    {
        ArgumentNullException.ThrowIfNull(data);

        if (provenance.DropsAnything)
        {
            logger?.LogWarning(
                "Event {Type} carries provenance the journal does not accept (actor '{Actor}', origin '{Origin}'); the invalid half is recorded as unknown",
                TData.Name, provenance.Actor, provenance.Origin);
        }

        DateTimeOffset now = _clock.GetUtcNow();
        byte[] line = Compose(data, provenance.Normalized(), summary, now);

        if (line.Length > AtomicWriteLimitBytes)
        {
            logger?.LogWarning(
                "Event {Type} encodes to {Bytes} bytes, past the {Limit}-byte atomic-append limit; a concurrent write to this segment could interleave with it",
                TData.Name, line.Length, AtomicWriteLimitBytes);
        }

        return AppendLine(line, now, TData.Name.Value);
    }

    /// <summary>The path of the segment an event at <paramref name="instant"/> is appended to.</summary>
    public string SegmentPath(DateTimeOffset instant) =>
        Path.Combine(options.Directory, SegmentName(instant));

    /// <summary>The segment file name for a UTC day: <c>YYYY-MM-DD.ndjson</c>.</summary>
    public static string SegmentName(DateTimeOffset instant) =>
        instant.UtcDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + ".ndjson";

    private bool AppendLine(byte[] line, DateTimeOffset now, string eventType)
    {
        string path = SegmentPath(now);

        try
        {
            Directory.CreateDirectory(options.Directory);

            // One O_APPEND write of the whole line: concurrent appenders land whole lines one after another.
            AppendOnlyFile.Write(path, line);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            logger?.LogError(ex, "Event {Type} was NOT recorded: the journal at {Path} could not be written", eventType, path);
            return false;
        }
    }

    private byte[] Compose<TData>(TData data, Provenance provenance, string? summary, DateTimeOffset now)
        where TData : EngineEventData, IEngineEvent<TData>
    {
        var buffer = new ArrayBufferWriter<byte>(512);
        EventTraits traits = TData.Traits;
        bool fact = traits.Weight == EventWeight.Fact;

        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions { Indented = false }))
        {
            writer.WriteStartObject();

            writer.WriteNumber("V", EnvelopeVersion);
            writer.WriteString("Id", Guid.CreateVersion7(now).ToString("d"));
            writer.WriteString("EventType", TData.Name.Value);

            if (fact)
            {
                writer.WriteString("Severity", traits.Severity.ToWire());
                writer.WriteString("Outcome", traits.Outcome.ToWire());
                if (!string.IsNullOrEmpty(summary)) writer.WriteString("Summary", summary);
            }

            writer.WritePropertyName("Data");
            JsonSerializer.Serialize(writer, data, TData.TypeInfo);

            writer.WriteString("Timestamp", now.UtcDateTime.ToString(TimestampFormat, CultureInfo.InvariantCulture));

            if (provenance.Actor is not null) writer.WriteString("Actor", provenance.Actor);
            if (provenance.Origin is not null) writer.WriteString("Origin", provenance.Origin);
            if (!string.IsNullOrEmpty(options.Hostname)) writer.WriteString("Hostname", options.Hostname);
            if (!string.IsNullOrEmpty(options.ProducerVersion)) writer.WriteString("ProducerVersion", options.ProducerVersion);

            writer.WriteEndObject();
        }

        ReadOnlySpan<byte> json = buffer.WrittenSpan;
        byte[] line = new byte[json.Length + 1];
        json.CopyTo(line);
        line[^1] = (byte)'\n';
        return line;
    }
}
