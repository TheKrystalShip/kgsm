using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Engine.Reading;

/// <summary>
/// Builds the instance reports the binary's <c>instance list</c> and <c>instance show</c> print and the
/// in-process reader returns, so both answer with one set of rules.
/// </summary>
public static class InstanceReportBuilder
{
    public static InstanceSummary Summary(Instances.InstanceDescription instance) => new()
    {
        Id = instance.Id,
        Label = instance.Config?.Label ?? instance.Id,
        Blueprint = instance.Blueprint,
        Runtime = instance.Config?.Runtime,
        Library = instance.Library?.Name,
        LibraryState = instance.LibraryState,
        ConfigProblem = instance.ConfigProblem,
    };

    public static InstanceInfo Info(Instances.InstanceDescription instance, CgroupSettings cgroup)
    {
        Instances.InstanceLayout layout = instance.Layout;
        return new InstanceInfo
        {
            Id = instance.Id,
            Label = instance.Config?.Label ?? instance.Id,
            Blueprint = instance.Blueprint,
            Runtime = instance.Config?.Runtime,
            Library = instance.Library is { } library ? new InstanceLibraryRef(library.Name, library.Id, library.Path) : null,
            LibraryState = instance.LibraryState,
            Paths = PathsOf(instance, layout),
            CgroupPath = layout.CgroupPath(cgroup.MountPoint, cgroup.BaseName),
            Ports = PortSpecs.Parse(instance.Config?.Ports),
            Config = instance.Config,
            ConfigProblem = instance.ConfigProblem,
        };
    }

    public static InstancePaths PathsOf(Instances.InstanceDescription instance, Instances.InstanceLayout layout) => new()
    {
        WorkingDirectory = layout.WorkingDirectory,
        ConfigFile = layout.ConfigFile,
        ManagementScript = layout.ManagementScript,
        InstallDirectory = layout.InstallDirectory,
        SavesDirectory = layout.SavesDirectory,
        LogsDirectory = layout.LogsDirectory,
        TempDirectory = layout.TempDirectory,
        EventsDirectory = layout.EventsDirectory,
        LaunchDirectory = layout.LaunchDirectory,
        VersionFile = layout.VersionFile,
        LatestVersionFile = layout.LatestVersionFile,
        PidFile = layout.PidFile,
        InputFifo = layout.InputFifo,
        LogFile = layout.LogFile,
        ComposeFile = layout.ComposeFile,
        BackupsDirectory = instance.Config?.BackupsDirectory,
    };
}
