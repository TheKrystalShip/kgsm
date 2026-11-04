using TheKrystalShip.KGSM.Engine.Contracts.Events;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Writes one engine event named by its type, for <c>kgsm event emit</c>. The type must be one the
/// engine writes (<see cref="EngineEventCatalog"/>), and every field its payload requires must be given.
/// </summary>
public static class EventEmission
{
    /// <summary>Writes the event.</summary>
    /// <param name="recorder">Where it is written, with the acting provenance.</param>
    /// <param name="type">The event type, such as <c>server.download.started</c>.</param>
    /// <param name="subject">The instance, blueprint or library the event is about.</param>
    /// <param name="fields">The payload's other fields by name.</param>
    /// <exception cref="OperationException">The type is not the engine's, or a required field is missing or malformed.</exception>
    public static void Emit(EventRecorder recorder, string type, string subject, IReadOnlyDictionary<string, string> fields)
    {
        ArgumentNullException.ThrowIfNull(recorder);

        EventDescriptor descriptor = EngineEventCatalog.Find(type)
            ?? throw OperationException.Invalid($"'{type}' is not an event the engine writes");
        if (string.IsNullOrWhiteSpace(subject))
            throw OperationException.Invalid($"{type} needs the name of the {descriptor.Subject.ToString().ToLowerInvariant()} it is about");

        foreach (EventField field in descriptor.Fields)
        {
            if (!IsOptional(type, field.Name) && !fields.ContainsKey(field.Name))
                throw OperationException.Invalid($"{type} needs the field {field.Name}", [$"pass --field {field.Name}=<value>"]);
        }

        foreach (string given in fields.Keys)
        {
            if (descriptor.Fields.All(f => f.Name != given))
                throw OperationException.Invalid($"{type} has no field {given}");
        }

        string Text(string name) => fields.TryGetValue(name, out string? value) ? value : string.Empty;
        string? Maybe(string name) => fields.GetValueOrDefault(name);
        int Number(string name) =>
            int.TryParse(Text(name), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out int n)
                ? n
                : throw OperationException.Invalid($"the field {name} of {type} is a whole number");
        bool? Flag(string name) =>
            Maybe(name) is null ? null
            : bool.TryParse(Maybe(name), out bool b) ? b
            : throw OperationException.Invalid($"the field {name} of {type} is true or false");
        BlueprintTier Tier() =>
            Enum.TryParse(Text("Tier"), ignoreCase: true, out BlueprintTier tier)
                ? tier
                : throw OperationException.Invalid($"the field Tier of {type} is system or user");

        bool written = type switch
        {
            "server.install.started" => recorder.Append(new InstallStarted { InstanceName = subject, Blueprint = Text("Blueprint") }),
            "server.install.directories_created" => recorder.Append(new InstallDirectoriesCreated { InstanceName = subject }),
            "server.install.files_created" => recorder.Append(new InstallFilesCreated { InstanceName = subject }),
            "server.download.started" => recorder.Append(new DownloadStarted { InstanceName = subject }),
            "server.download.finished" => recorder.Append(new DownloadFinished { InstanceName = subject }),
            "server.download.failed" => recorder.Append(new DownloadFailed { InstanceName = subject }),
            "server.deploy.started" => recorder.Append(new DeployStarted { InstanceName = subject }),
            "server.deploy.finished" => recorder.Append(new DeployFinished { InstanceName = subject }),
            "server.deploy.failed" => recorder.Append(new DeployFailed { InstanceName = subject }),
            "server.installed" => recorder.Append(new Installed { InstanceName = subject, Blueprint = Text("Blueprint"), Library = Text("Library") }),
            "server.install.failed" => recorder.Append(new InstallFailed { InstanceName = subject, Blueprint = Text("Blueprint") }),
            "server.install.finished" => recorder.Append(new InstallFinished { InstanceName = subject, Blueprint = Text("Blueprint") }),
            "server.uninstall.started" => recorder.Append(new UninstallStarted { InstanceName = subject }),
            "server.uninstall.finished" => recorder.Append(new UninstallFinished { InstanceName = subject }),
            "server.uninstall.failed" => recorder.Append(new UninstallFailed { InstanceName = subject }),
            "server.uninstalled" => recorder.Append(new Uninstalled { InstanceName = subject, InstallNonce = Maybe("InstallNonce") }),
            "server.start.started" => recorder.Append(new StartStarted { InstanceName = subject }),
            "server.start.finished" => recorder.Append(new StartFinished { InstanceName = subject }),
            "server.started" => recorder.Append(new Started { InstanceName = subject }),
            "server.stop.started" => recorder.Append(new StopStarted { InstanceName = subject }),
            "server.stop.finished" => recorder.Append(new StopFinished { InstanceName = subject }),
            "server.stopped" => recorder.Append(new Stopped { InstanceName = subject }),
            "server.restart.started" => recorder.Append(new RestartStarted { InstanceName = subject }),
            "server.restart.stopped" => recorder.Append(new RestartStopped { InstanceName = subject }),
            "server.restart.finished" => recorder.Append(new RestartFinished { InstanceName = subject }),
            "server.restarted" => recorder.Append(new Restarted { InstanceName = subject }),
            "server.update.started" => recorder.Append(new UpdateStarted { InstanceName = subject }),
            "server.update.finished" => recorder.Append(new UpdateFinished { InstanceName = subject }),
            "server.update.failed" => recorder.Append(new UpdateFailed { InstanceName = subject }),
            "server.updated" => recorder.Append(new Updated { InstanceName = subject, OldVersion = Text("OldVersion"), NewVersion = Text("NewVersion") }),
            "server.update.available" => recorder.Append(new UpdateAvailable { InstanceName = subject, CurrentVersion = Text("CurrentVersion"), LatestVersion = Text("LatestVersion") }),
            "server.moved" => recorder.Append(new Moved { InstanceName = subject, FromLibrary = Text("FromLibrary"), ToLibrary = Text("ToLibrary") }),
            "server.renamed" => recorder.Append(new Renamed { InstanceName = subject, OldDisplayName = Text("OldDisplayName"), NewDisplayName = Text("NewDisplayName") }),
            "server.exported" => recorder.Append(new Exported { InstanceName = subject }),
            "server.imported" => recorder.Append(new Imported { InstanceName = subject, Blueprint = Text("Blueprint"), Library = Text("Library") }),
            "backup.started" => recorder.Append(new BackupStarted { InstanceName = subject }),
            "backup.finished" => recorder.Append(new BackupFinished { InstanceName = subject }),
            "backup.restore.started" => recorder.Append(new RestoreStarted { InstanceName = subject }),
            "backup.restore.finished" => recorder.Append(new RestoreFinished { InstanceName = subject }),
            "backup.created" => recorder.Append(new BackupCreated { InstanceName = subject, Source = Text("Source"), Version = Text("Version") }),
            "backup.restored" => recorder.Append(new BackupRestored { InstanceName = subject, Source = Text("Source"), Version = Text("Version") }),
            "backup.deleted" => recorder.Append(new BackupDeleted { InstanceName = subject, Source = Text("Source") }),
            "backup.pinned" => recorder.Append(new BackupPinned { InstanceName = subject, Source = Text("Source") }),
            "backup.unpinned" => recorder.Append(new BackupUnpinned { InstanceName = subject, Source = Text("Source") }),
            "backup.pruned" => recorder.Append(new BackupsPruned { InstanceName = subject, Deleted = Number("Deleted"), Kept = Number("Kept"), Pinned = Number("Pinned") }),
            "config.changed" => recorder.Append(new ConfigChanged { InstanceName = subject, Key = Text("Key") }),
            "console.input.sent" => recorder.Append(new InputSent { InstanceName = subject, Command = Text("Command") }),
            "announcement.sent" => recorder.Append(new AnnouncementSent { InstanceName = subject, Message = Text("Message"), Command = Text("Command") }),
            "player.kicked" => recorder.Append(new PlayerKicked { InstanceName = subject, Target = Text("Target"), Command = Text("Command") }),
            "player.banned" => recorder.Append(new PlayerBanned { InstanceName = subject, Target = Text("Target"), Command = Text("Command") }),
            "player.unbanned" => recorder.Append(new PlayerUnbanned { InstanceName = subject, Target = Text("Target"), Command = Text("Command") }),
            "blueprint.created" => recorder.Append(new BlueprintCreated { BlueprintName = subject, Tier = Tier(), OverridesSystem = Flag("OverridesSystem"), Runtime = Maybe("Runtime") }),
            "blueprint.updated" => recorder.Append(new BlueprintUpdated { BlueprintName = subject, Tier = Tier(), OverridesSystem = Flag("OverridesSystem"), Runtime = Maybe("Runtime") }),
            "blueprint.removed" => recorder.Append(new BlueprintRemoved { BlueprintName = subject, Tier = Tier(), RevertedToSystem = Flag("RevertedToSystem") }),
            "library.added" => recorder.Append(new LibraryAdded { LibraryName = subject, Path = Text("Path") }),
            "library.removed" => recorder.Append(new LibraryRemoved { LibraryName = subject, Path = Text("Path") }),
            "library.renamed" => recorder.Append(new LibraryRenamed { LibraryName = subject, OldName = Text("OldName"), Path = Text("Path") }),
            _ => throw OperationException.Invalid($"'{type}' cannot be emitted by name"),
        };

        if (!written)
            throw new OperationException("journal", $"the journal at {recorder.Directory} could not be written");
    }

    /// <summary>Whether a payload field may be left out: the nullable ones.</summary>
    private static bool IsOptional(string type, string field) => (type, field) switch
    {
        ("server.uninstalled", "InstallNonce") => true,
        ("blueprint.created" or "blueprint.updated", "OverridesSystem" or "Runtime") => true,
        ("blueprint.removed", "RevertedToSystem") => true,
        _ => false,
    };
}
