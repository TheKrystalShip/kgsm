namespace TheKrystalShip.KGSM.Engine.Contracts.Events;

/// <summary>What the engine knows about one of its own event types.</summary>
public sealed record EventDescriptor(
    EventName Name,
    EventSubject Subject,
    EventTraits Traits,
    string PayloadType,
    IReadOnlyList<EventField> Fields);

/// <summary>
/// The engine's event types: the one registry of what the engine writes. It states facts about each event
/// and never policy; a surface decides what to do with a classification. Static data, no reflection.
/// </summary>
public static class EngineEventCatalog
{
    /// <summary>Every event type the engine writes, in declaration order.</summary>
    public static IReadOnlyList<EventDescriptor> All { get; } =
    [
        Describe<InstallStarted>(),
        Describe<InstallDirectoriesCreated>(),
        Describe<InstallFilesCreated>(),
        Describe<DownloadStarted>(),
        Describe<DownloadFinished>(),
        Describe<DownloadFailed>(),
        Describe<DeployStarted>(),
        Describe<DeployFinished>(),
        Describe<DeployFailed>(),
        Describe<Installed>(),
        Describe<InstallFailed>(),
        Describe<InstallFinished>(),
        Describe<UninstallStarted>(),
        Describe<UninstallFinished>(),
        Describe<UninstallFailed>(),
        Describe<Uninstalled>(),
        Describe<StartStarted>(),
        Describe<StartFinished>(),
        Describe<Started>(),
        Describe<StopStarted>(),
        Describe<StopFinished>(),
        Describe<Stopped>(),
        Describe<RestartStarted>(),
        Describe<RestartStopped>(),
        Describe<RestartFinished>(),
        Describe<Restarted>(),
        Describe<UpdateStarted>(),
        Describe<UpdateFinished>(),
        Describe<UpdateFailed>(),
        Describe<Updated>(),
        Describe<UpdateAvailable>(),
        Describe<Moved>(),
        Describe<Renamed>(),
        Describe<Exported>(),
        Describe<Imported>(),
        Describe<BackupStarted>(),
        Describe<BackupFinished>(),
        Describe<RestoreStarted>(),
        Describe<RestoreFinished>(),
        Describe<BackupCreated>(),
        Describe<BackupRestored>(),
        Describe<BackupDeleted>(),
        Describe<BackupPinned>(),
        Describe<BackupUnpinned>(),
        Describe<BackupsPruned>(),
        Describe<ConfigChanged>(),
        Describe<InputSent>(),
        Describe<AnnouncementSent>(),
        Describe<PlayerKicked>(),
        Describe<PlayerBanned>(),
        Describe<PlayerUnbanned>(),
        Describe<BlueprintCreated>(),
        Describe<BlueprintUpdated>(),
        Describe<BlueprintRemoved>(),
        Describe<LibraryAdded>(),
        Describe<LibraryRemoved>(),
        Describe<LibraryRenamed>(),
    ];

    private static readonly Dictionary<string, EventDescriptor> ByName =
        All.ToDictionary(d => d.Name.Value, StringComparer.Ordinal);

    /// <summary>The descriptor of a name the engine writes, or null for any other name.</summary>
    public static EventDescriptor? Find(string? name) =>
        name is not null && ByName.TryGetValue(name, out EventDescriptor? descriptor) ? descriptor : null;

    /// <summary>Whether the engine writes an event of this name.</summary>
    public static bool IsEngineEvent(string? name) => Find(name) is not null;

    private static EventDescriptor Describe<T>() where T : EngineEventData, IEngineEvent<T> =>
        new(T.Name, T.Subject, T.Traits, typeof(T).Name, T.Fields);
}
