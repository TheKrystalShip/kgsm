// The payloads the engine writes. A payload carries its subject's identifying field and the fields
// below; the envelope carries who, from where and when. No payload holds a file body, a diff or a
// config value: a config change names its key only, because a value can be a credential.
using System.Text.Json.Serialization.Metadata;

namespace TheKrystalShip.KGSM.Engine.Contracts.Events;

public sealed record InstallStarted : InstanceEventData, IEngineEvent<InstallStarted>
{
    public required string Blueprint { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.install.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<InstallStarted> TypeInfo => EngineEventJsonContext.Default.InstallStarted;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Blueprint")];
}

public sealed record InstallDirectoriesCreated : InstanceEventData, IEngineEvent<InstallDirectoriesCreated>
{
    public static EventName Name { get; } = EventName.Parse("server.install.directories_created");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<InstallDirectoriesCreated> TypeInfo => EngineEventJsonContext.Default.InstallDirectoriesCreated;
}

public sealed record InstallFilesCreated : InstanceEventData, IEngineEvent<InstallFilesCreated>
{
    public static EventName Name { get; } = EventName.Parse("server.install.files_created");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<InstallFilesCreated> TypeInfo => EngineEventJsonContext.Default.InstallFilesCreated;
}

public sealed record DownloadStarted : InstanceEventData, IEngineEvent<DownloadStarted>
{
    public static EventName Name { get; } = EventName.Parse("server.download.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<DownloadStarted> TypeInfo => EngineEventJsonContext.Default.DownloadStarted;
}

public sealed record DownloadFinished : InstanceEventData, IEngineEvent<DownloadFinished>
{
    public static EventName Name { get; } = EventName.Parse("server.download.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<DownloadFinished> TypeInfo => EngineEventJsonContext.Default.DownloadFinished;
}

public sealed record DownloadFailed : InstanceEventData, IEngineEvent<DownloadFailed>
{
    public static EventName Name { get; } = EventName.Parse("server.download.failed");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Failure, EventSeverity.Danger);
    public static JsonTypeInfo<DownloadFailed> TypeInfo => EngineEventJsonContext.Default.DownloadFailed;
}

public sealed record DeployStarted : InstanceEventData, IEngineEvent<DeployStarted>
{
    public static EventName Name { get; } = EventName.Parse("server.deploy.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<DeployStarted> TypeInfo => EngineEventJsonContext.Default.DeployStarted;
}

public sealed record DeployFinished : InstanceEventData, IEngineEvent<DeployFinished>
{
    public static EventName Name { get; } = EventName.Parse("server.deploy.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<DeployFinished> TypeInfo => EngineEventJsonContext.Default.DeployFinished;
}

public sealed record DeployFailed : InstanceEventData, IEngineEvent<DeployFailed>
{
    public static EventName Name { get; } = EventName.Parse("server.deploy.failed");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Failure, EventSeverity.Danger);
    public static JsonTypeInfo<DeployFailed> TypeInfo => EngineEventJsonContext.Default.DeployFailed;
}

public sealed record Installed : InstanceEventData, IEngineEvent<Installed>
{
    public required string Blueprint { get; init; }

    public required string Library { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.installed");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Success);
    public static JsonTypeInfo<Installed> TypeInfo => EngineEventJsonContext.Default.Installed;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Blueprint"), new("Library")];
}

public sealed record InstallFailed : InstanceEventData, IEngineEvent<InstallFailed>
{
    public required string Blueprint { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.install.failed");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Failure, EventSeverity.Danger);
    public static JsonTypeInfo<InstallFailed> TypeInfo => EngineEventJsonContext.Default.InstallFailed;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Blueprint")];
}

public sealed record InstallFinished : InstanceEventData, IEngineEvent<InstallFinished>
{
    public required string Blueprint { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.install.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<InstallFinished> TypeInfo => EngineEventJsonContext.Default.InstallFinished;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Blueprint")];
}

public sealed record UninstallStarted : InstanceEventData, IEngineEvent<UninstallStarted>
{
    public static EventName Name { get; } = EventName.Parse("server.uninstall.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<UninstallStarted> TypeInfo => EngineEventJsonContext.Default.UninstallStarted;
}

public sealed record UninstallFinished : InstanceEventData, IEngineEvent<UninstallFinished>
{
    public static EventName Name { get; } = EventName.Parse("server.uninstall.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<UninstallFinished> TypeInfo => EngineEventJsonContext.Default.UninstallFinished;
}

public sealed record UninstallFailed : InstanceEventData, IEngineEvent<UninstallFailed>
{
    public static EventName Name { get; } = EventName.Parse("server.uninstall.failed");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Failure, EventSeverity.Danger);
    public static JsonTypeInfo<UninstallFailed> TypeInfo => EngineEventJsonContext.Default.UninstallFailed;
}

public sealed record Uninstalled : InstanceEventData, IEngineEvent<Uninstalled>
{
    public string? InstallNonce { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.uninstalled");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Success);
    public static JsonTypeInfo<Uninstalled> TypeInfo => EngineEventJsonContext.Default.Uninstalled;
    public static IReadOnlyList<EventField> Fields { get; } = [new("InstallNonce")];
}

public sealed record StartStarted : InstanceEventData, IEngineEvent<StartStarted>
{
    public static EventName Name { get; } = EventName.Parse("server.start.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<StartStarted> TypeInfo => EngineEventJsonContext.Default.StartStarted;
}

public sealed record StartFinished : InstanceEventData, IEngineEvent<StartFinished>
{
    public static EventName Name { get; } = EventName.Parse("server.start.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<StartFinished> TypeInfo => EngineEventJsonContext.Default.StartFinished;
}

public sealed record Started : InstanceEventData, IEngineEvent<Started>
{
    public static EventName Name { get; } = EventName.Parse("server.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<Started> TypeInfo => EngineEventJsonContext.Default.Started;
}

public sealed record StopStarted : InstanceEventData, IEngineEvent<StopStarted>
{
    public static EventName Name { get; } = EventName.Parse("server.stop.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<StopStarted> TypeInfo => EngineEventJsonContext.Default.StopStarted;
}

public sealed record StopFinished : InstanceEventData, IEngineEvent<StopFinished>
{
    public static EventName Name { get; } = EventName.Parse("server.stop.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<StopFinished> TypeInfo => EngineEventJsonContext.Default.StopFinished;
}

public sealed record Stopped : InstanceEventData, IEngineEvent<Stopped>
{
    public static EventName Name { get; } = EventName.Parse("server.stopped");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Neutral, EventSeverity.Warn);
    public static JsonTypeInfo<Stopped> TypeInfo => EngineEventJsonContext.Default.Stopped;
}

public sealed record RestartStarted : InstanceEventData, IEngineEvent<RestartStarted>
{
    public static EventName Name { get; } = EventName.Parse("server.restart.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<RestartStarted> TypeInfo => EngineEventJsonContext.Default.RestartStarted;
}

public sealed record RestartStopped : InstanceEventData, IEngineEvent<RestartStopped>
{
    public static EventName Name { get; } = EventName.Parse("server.restart.stopped");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<RestartStopped> TypeInfo => EngineEventJsonContext.Default.RestartStopped;
}

public sealed record RestartFinished : InstanceEventData, IEngineEvent<RestartFinished>
{
    public static EventName Name { get; } = EventName.Parse("server.restart.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<RestartFinished> TypeInfo => EngineEventJsonContext.Default.RestartFinished;
}

public sealed record Restarted : InstanceEventData, IEngineEvent<Restarted>
{
    public static EventName Name { get; } = EventName.Parse("server.restarted");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<Restarted> TypeInfo => EngineEventJsonContext.Default.Restarted;
}

public sealed record UpdateStarted : InstanceEventData, IEngineEvent<UpdateStarted>
{
    public static EventName Name { get; } = EventName.Parse("server.update.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<UpdateStarted> TypeInfo => EngineEventJsonContext.Default.UpdateStarted;
}

public sealed record UpdateFinished : InstanceEventData, IEngineEvent<UpdateFinished>
{
    public static EventName Name { get; } = EventName.Parse("server.update.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<UpdateFinished> TypeInfo => EngineEventJsonContext.Default.UpdateFinished;
}

public sealed record UpdateFailed : InstanceEventData, IEngineEvent<UpdateFailed>
{
    public static EventName Name { get; } = EventName.Parse("server.update.failed");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Failure, EventSeverity.Danger);
    public static JsonTypeInfo<UpdateFailed> TypeInfo => EngineEventJsonContext.Default.UpdateFailed;
}

public sealed record Updated : InstanceEventData, IEngineEvent<Updated>
{
    public required string OldVersion { get; init; }

    public required string NewVersion { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.updated");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Success);
    public static JsonTypeInfo<Updated> TypeInfo => EngineEventJsonContext.Default.Updated;
    public static IReadOnlyList<EventField> Fields { get; } = [new("OldVersion"), new("NewVersion")];
}

public sealed record UpdateAvailable : InstanceEventData, IEngineEvent<UpdateAvailable>
{
    public required string CurrentVersion { get; init; }

    public required string LatestVersion { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.update.available");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<UpdateAvailable> TypeInfo => EngineEventJsonContext.Default.UpdateAvailable;
    public static IReadOnlyList<EventField> Fields { get; } = [new("CurrentVersion"), new("LatestVersion")];
}

public sealed record Moved : InstanceEventData, IEngineEvent<Moved>
{
    public required string FromLibrary { get; init; }

    public required string ToLibrary { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.moved");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<Moved> TypeInfo => EngineEventJsonContext.Default.Moved;
    public static IReadOnlyList<EventField> Fields { get; } = [new("FromLibrary"), new("ToLibrary")];
}

public sealed record Renamed : InstanceEventData, IEngineEvent<Renamed>
{
    public required string OldDisplayName { get; init; }

    public required string NewDisplayName { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.renamed");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<Renamed> TypeInfo => EngineEventJsonContext.Default.Renamed;
    public static IReadOnlyList<EventField> Fields { get; } = [new("OldDisplayName"), new("NewDisplayName")];
}

public sealed record Exported : InstanceEventData, IEngineEvent<Exported>
{
    public static EventName Name { get; } = EventName.Parse("server.exported");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<Exported> TypeInfo => EngineEventJsonContext.Default.Exported;
}

public sealed record Imported : InstanceEventData, IEngineEvent<Imported>
{
    public required string Blueprint { get; init; }

    public required string Library { get; init; }

    public static EventName Name { get; } = EventName.Parse("server.imported");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Success);
    public static JsonTypeInfo<Imported> TypeInfo => EngineEventJsonContext.Default.Imported;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Blueprint"), new("Library")];
}

public sealed record BackupStarted : InstanceEventData, IEngineEvent<BackupStarted>
{
    public static EventName Name { get; } = EventName.Parse("backup.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<BackupStarted> TypeInfo => EngineEventJsonContext.Default.BackupStarted;
}

public sealed record BackupFinished : InstanceEventData, IEngineEvent<BackupFinished>
{
    public static EventName Name { get; } = EventName.Parse("backup.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<BackupFinished> TypeInfo => EngineEventJsonContext.Default.BackupFinished;
}

public sealed record RestoreStarted : InstanceEventData, IEngineEvent<RestoreStarted>
{
    public static EventName Name { get; } = EventName.Parse("backup.restore.started");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<RestoreStarted> TypeInfo => EngineEventJsonContext.Default.RestoreStarted;
}

public sealed record RestoreFinished : InstanceEventData, IEngineEvent<RestoreFinished>
{
    public static EventName Name { get; } = EventName.Parse("backup.restore.finished");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Phase;
    public static JsonTypeInfo<RestoreFinished> TypeInfo => EngineEventJsonContext.Default.RestoreFinished;
}

public sealed record BackupCreated : InstanceEventData, IEngineEvent<BackupCreated>
{
    public required string Source { get; init; }

    public required string Version { get; init; }

    public static EventName Name { get; } = EventName.Parse("backup.created");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Success);
    public static JsonTypeInfo<BackupCreated> TypeInfo => EngineEventJsonContext.Default.BackupCreated;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Source"), new("Version")];
}

public sealed record BackupRestored : InstanceEventData, IEngineEvent<BackupRestored>
{
    public required string Source { get; init; }

    public required string Version { get; init; }

    public static EventName Name { get; } = EventName.Parse("backup.restored");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Success, EventSeverity.Warn);
    public static JsonTypeInfo<BackupRestored> TypeInfo => EngineEventJsonContext.Default.BackupRestored;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Source"), new("Version")];
}

public sealed record BackupDeleted : InstanceEventData, IEngineEvent<BackupDeleted>
{
    public required string Source { get; init; }

    public static EventName Name { get; } = EventName.Parse("backup.deleted");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Neutral, EventSeverity.Warn);
    public static JsonTypeInfo<BackupDeleted> TypeInfo => EngineEventJsonContext.Default.BackupDeleted;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Source")];
}

public sealed record BackupPinned : InstanceEventData, IEngineEvent<BackupPinned>
{
    public required string Source { get; init; }

    public static EventName Name { get; } = EventName.Parse("backup.pinned");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<BackupPinned> TypeInfo => EngineEventJsonContext.Default.BackupPinned;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Source")];
}

public sealed record BackupUnpinned : InstanceEventData, IEngineEvent<BackupUnpinned>
{
    public required string Source { get; init; }

    public static EventName Name { get; } = EventName.Parse("backup.unpinned");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Neutral, EventSeverity.Warn);
    public static JsonTypeInfo<BackupUnpinned> TypeInfo => EngineEventJsonContext.Default.BackupUnpinned;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Source")];
}

public sealed record BackupsPruned : InstanceEventData, IEngineEvent<BackupsPruned>
{
    public required int Deleted { get; init; }

    public required int Kept { get; init; }

    public required int Pinned { get; init; }

    public static EventName Name { get; } = EventName.Parse("backup.pruned");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<BackupsPruned> TypeInfo => EngineEventJsonContext.Default.BackupsPruned;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Deleted", Shape: FieldShape.Number), new("Kept", Shape: FieldShape.Number), new("Pinned", Shape: FieldShape.Number)];
}

public sealed record ConfigChanged : InstanceEventData, IEngineEvent<ConfigChanged>
{
    public required string Key { get; init; }

    public static EventName Name { get; } = EventName.Parse("config.changed");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<ConfigChanged> TypeInfo => EngineEventJsonContext.Default.ConfigChanged;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Key")];
}

public sealed record InputSent : InstanceEventData, IEngineEvent<InputSent>
{
    public required string Command { get; init; }

    public static EventName Name { get; } = EventName.Parse("console.input.sent");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<InputSent> TypeInfo => EngineEventJsonContext.Default.InputSent;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Command", FieldSensitivity.Privileged)];
}

public sealed record AnnouncementSent : InstanceEventData, IEngineEvent<AnnouncementSent>
{
    public required string Message { get; init; }

    public required string Command { get; init; }

    public static EventName Name { get; } = EventName.Parse("announcement.sent");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<AnnouncementSent> TypeInfo => EngineEventJsonContext.Default.AnnouncementSent;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Message"), new("Command", FieldSensitivity.Privileged)];
}

public sealed record PlayerKicked : InstanceEventData, IEngineEvent<PlayerKicked>
{
    public required string Target { get; init; }

    public required string Command { get; init; }

    public static EventName Name { get; } = EventName.Parse("player.kicked");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Neutral, EventSeverity.Warn);
    public static JsonTypeInfo<PlayerKicked> TypeInfo => EngineEventJsonContext.Default.PlayerKicked;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Target", FieldSensitivity.Conditional), new("Command", FieldSensitivity.Privileged)];
}

public sealed record PlayerBanned : InstanceEventData, IEngineEvent<PlayerBanned>
{
    public required string Target { get; init; }

    public required string Command { get; init; }

    public static EventName Name { get; } = EventName.Parse("player.banned");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact(EventOutcome.Neutral, EventSeverity.Danger);
    public static JsonTypeInfo<PlayerBanned> TypeInfo => EngineEventJsonContext.Default.PlayerBanned;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Target", FieldSensitivity.Conditional), new("Command", FieldSensitivity.Privileged)];
}

public sealed record PlayerUnbanned : InstanceEventData, IEngineEvent<PlayerUnbanned>
{
    public required string Target { get; init; }

    public required string Command { get; init; }

    public static EventName Name { get; } = EventName.Parse("player.unbanned");
    public static EventSubject Subject => EventSubject.Instance;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<PlayerUnbanned> TypeInfo => EngineEventJsonContext.Default.PlayerUnbanned;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Target", FieldSensitivity.Conditional), new("Command", FieldSensitivity.Privileged)];
}

public sealed record BlueprintCreated : BlueprintEventData, IEngineEvent<BlueprintCreated>
{
    public required BlueprintTier Tier { get; init; }

    public bool? OverridesSystem { get; init; }

    public string? Runtime { get; init; }

    public static EventName Name { get; } = EventName.Parse("blueprint.created");
    public static EventSubject Subject => EventSubject.Blueprint;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<BlueprintCreated> TypeInfo => EngineEventJsonContext.Default.BlueprintCreated;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Tier"), new("OverridesSystem"), new("Runtime")];
}

public sealed record BlueprintUpdated : BlueprintEventData, IEngineEvent<BlueprintUpdated>
{
    public required BlueprintTier Tier { get; init; }

    public bool? OverridesSystem { get; init; }

    public string? Runtime { get; init; }

    public static EventName Name { get; } = EventName.Parse("blueprint.updated");
    public static EventSubject Subject => EventSubject.Blueprint;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<BlueprintUpdated> TypeInfo => EngineEventJsonContext.Default.BlueprintUpdated;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Tier"), new("OverridesSystem"), new("Runtime")];
}

public sealed record BlueprintRemoved : BlueprintEventData, IEngineEvent<BlueprintRemoved>
{
    public required BlueprintTier Tier { get; init; }

    public bool? RevertedToSystem { get; init; }

    public static EventName Name { get; } = EventName.Parse("blueprint.removed");
    public static EventSubject Subject => EventSubject.Blueprint;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<BlueprintRemoved> TypeInfo => EngineEventJsonContext.Default.BlueprintRemoved;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Tier"), new("RevertedToSystem")];
}

public sealed record LibraryAdded : LibraryEventData, IEngineEvent<LibraryAdded>
{
    public required string Path { get; init; }

    public static EventName Name { get; } = EventName.Parse("library.added");
    public static EventSubject Subject => EventSubject.Library;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<LibraryAdded> TypeInfo => EngineEventJsonContext.Default.LibraryAdded;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Path")];
}

public sealed record LibraryRemoved : LibraryEventData, IEngineEvent<LibraryRemoved>
{
    public required string Path { get; init; }

    public static EventName Name { get; } = EventName.Parse("library.removed");
    public static EventSubject Subject => EventSubject.Library;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<LibraryRemoved> TypeInfo => EngineEventJsonContext.Default.LibraryRemoved;
    public static IReadOnlyList<EventField> Fields { get; } = [new("Path")];
}

public sealed record LibraryRenamed : LibraryEventData, IEngineEvent<LibraryRenamed>
{
    public required string OldName { get; init; }

    public required string Path { get; init; }

    public static EventName Name { get; } = EventName.Parse("library.renamed");
    public static EventSubject Subject => EventSubject.Library;
    public static EventTraits Traits => EventTraits.Fact();
    public static JsonTypeInfo<LibraryRenamed> TypeInfo => EngineEventJsonContext.Default.LibraryRenamed;
    public static IReadOnlyList<EventField> Fields { get; } = [new("OldName"), new("Path")];
}
