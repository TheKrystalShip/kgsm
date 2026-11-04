namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>
/// Every path inside an instance's working directory. They are derived, never stored: the binary derives
/// them from the registry, the management script from its own location. The names are fixed, so moving or
/// importing an instance rewrites no path and renames no file.
/// </summary>
public sealed record InstanceLayout(string WorkingDirectory, string Id, string ExecutableSubdirectory = "")
{
    public string InstallDirectory => Path.Combine(WorkingDirectory, "install");

    public string SavesDirectory => Path.Combine(WorkingDirectory, "saves");

    public string LogsDirectory => Path.Combine(WorkingDirectory, "logs");

    public string TempDirectory => Path.Combine(WorkingDirectory, "temp");

    /// <summary>A container instance's directory, bind-mounted at <c>/run/kgsm</c>.</summary>
    public string EventsDirectory => Path.Combine(WorkingDirectory, "events");

    /// <summary>Where a native instance's binary is launched from.</summary>
    public string LaunchDirectory => string.IsNullOrEmpty(ExecutableSubdirectory)
        ? InstallDirectory
        : Path.Combine(InstallDirectory, ExecutableSubdirectory);

    public string ConfigFile => Path.Combine(WorkingDirectory, $"{Id}.config.json");

    public string ManagementScript => Path.Combine(WorkingDirectory, $"{Id}.manage.sh");

    public string ComposeFile => Path.Combine(WorkingDirectory, $"{Id}.docker-compose.yml");

    public string VersionFile => Path.Combine(WorkingDirectory, $".{Id}.version");

    /// <summary>The last upstream version an update check found.</summary>
    public string LatestVersionFile => Path.Combine(WorkingDirectory, $".{Id}.latest");

    public string PidFile => Path.Combine(WorkingDirectory, $".{Id}.pid");

    /// <summary>Present while a transfer holds the instance; it holds the holder's token.</summary>
    public string TransferLockFile => Path.Combine(WorkingDirectory, $".{Id}.transfer-lock");

    /// <summary>The named pipe console input is written to.</summary>
    public string InputFifo => Path.Combine(WorkingDirectory, $".{Id}.sock");

    public string LogFile => Path.Combine(WorkingDirectory, $"{Id}.log");

    /// <summary>The working directory a library places an instance at: <c>&lt;library&gt;/instances/&lt;blueprint&gt;/&lt;id&gt;</c>.</summary>
    public static string WorkingDirectoryFor(string libraryRoot, string blueprint, string id) =>
        Path.Combine(libraryRoot, "instances", blueprint, id);

    /// <summary>
    /// The instance's cgroup path below the cgroup mount point, which the monitor reads:
    /// <c>&lt;mount&gt;/&lt;watchdog cgroup&gt;/&lt;id&gt;</c>.
    /// </summary>
    public string CgroupPath(string mountPoint, string baseName) =>
        Path.Combine(mountPoint, baseName.Trim('/'), Id);
}
