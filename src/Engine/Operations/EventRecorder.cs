using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Journal;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// The engine's journal as one command sees it: the writer, the directory it appends to and who is
/// acting. Every operation records through it, so the actor and origin on a line are the command's own.
/// </summary>
public sealed class EventRecorder(EventJournalWriter writer, string directory, Provenance provenance, ILogger? logger = null)
{
    public string Directory => directory;

    public Provenance Provenance => provenance;

    /// <summary>Records one event; false, after logging, when the line could not be written.</summary>
    public bool Append<TData>(TData data, string? summary = null)
        where TData : EngineEventData, IEngineEvent<TData> =>
        writer.Append(data, provenance, summary);

    /// <summary>Whether a line can be appended: the directory exists or can be made, and a file can be created in it.</summary>
    public bool IsWritable()
    {
        string probe = Path.Combine(directory, $".kgsm-write-test-{Guid.NewGuid():N}");
        try
        {
            System.IO.Directory.CreateDirectory(directory);
            File.WriteAllBytes(probe, []);
            File.Delete(probe);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger?.LogWarning("The journal directory {Directory} is not writable: {Problem}", directory, ex.Message);
            return false;
        }
    }
}
