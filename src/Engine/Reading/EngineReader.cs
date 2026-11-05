using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using TheKrystalShip.KGSM.Engine.Backups;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Paths;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Paths;
using TheKrystalShip.KGSM.Engine.Settings;
using TheKrystalShip.KGSM.Engine.Status;

namespace TheKrystalShip.KGSM.Engine.Reading;

/// <summary>Where a reader finds the engine's files.</summary>
public sealed class EngineReaderOptions
{
    /// <summary>
    /// The directory the system blueprints, overrides and <c>kgsm.settings.json</c> sit in: the install root
    /// beside the binary. When unset it is the directory of the real file behind <see cref="BinaryPath"/>.
    /// </summary>
    public string? InstallRoot { get; set; }

    /// <summary>The <c>kgsm</c> binary: a path, or a name found on <c>PATH</c>. Locates the install root when none is set.</summary>
    public string BinaryPath { get; set; } = "kgsm";

    /// <summary>
    /// The environment the engine would run in (<c>HOME</c>, the XDG homes and <c>Section__Key</c> settings).
    /// The process's own environment when null.
    /// </summary>
    public IReadOnlyDictionary<string, string?>? Environment { get; set; }

    /// <summary>The home directory when <c>HOME</c> is unset.</summary>
    public string? HomeFallback { get; set; }
}

/// <summary>
/// The engine's reads, in-process: instances, status, backups, blueprints, libraries, ports, settings and
/// paths, answered from the engine's files with the same rules and the same shapes as the binary's read
/// commands. A reader changes nothing; every change runs the binary (<c>EngineCli</c> in the contracts
/// package), so engine state has one writer.
/// </summary>
/// <remarks>
/// A reader holds no cache. The registry, the config files and the markers are read when asked, so an
/// answer is as fresh as the files; a caller that wants a snapshot keeps the value it received.
/// </remarks>
public sealed class EngineReader : IDisposable
{
    private readonly EngineConfiguration _configuration;
    private readonly ILoggerFactory _loggers;
    private readonly IWatchdogControl _watchdog;
    private readonly IContainerRuntime _containers;

    public EngineReader(EngineReaderOptions? options = null, ILoggerFactory? loggers = null)
    {
        options ??= new EngineReaderOptions();
        IReadOnlyDictionary<string, string?> environment = options.Environment ?? ProcessEnvironment();

        Paths = EnginePaths.Resolve(
            name => environment.TryGetValue(name, out string? value) ? value : null,
            options.InstallRoot ?? InstallRootOf(options.BinaryPath),
            options.HomeFallback ?? System.Environment.GetFolderPath(System.Environment.SpecialFolder.UserProfile));

        _configuration = EngineSettingsLoader.Load(Paths, environment);
        _loggers = loggers ?? NullLoggerFactory.Instance;
        _watchdog = new WatchdogControl(_configuration.Settings.Watchdog.Socket);
        _containers = new DockerCompose();
    }

    public EnginePaths Paths { get; }

    public EngineSettings Settings => _configuration.Settings;

    /// <summary>Every directory and file the engine resolves.</summary>
    public PathsReport ResolvedPaths() => Paths.ToReport();

    /// <summary>Every setting with its value and the source that set it.</summary>
    public IReadOnlyList<EngineSetting> SettingValues() => SettingsView.List(_configuration, Paths);

    public EngineSetting? SettingValue(string key) => SettingsView.Find(_configuration, Paths, key);

    // ── Instances ─────────────────────────────────────────────────────────────────────────────

    private LibraryCatalog Libraries => new(Paths);

    private InstanceStore Store => new(Paths, Libraries, _loggers.CreateLogger<InstanceStore>());

    /// <summary>Every registered instance, whatever state its config is in.</summary>
    public IReadOnlyList<InstanceDescription> Instances() => Store.List();

    /// <summary>The instance a reference names (an id, else an exact display name), or null.</summary>
    /// <exception cref="AmbiguousInstanceException">Several instances carry that display name.</exception>
    public InstanceDescription? FindInstance(string reference) => Store.Resolve(reference);

    public IReadOnlyList<InstanceSummary> InstanceSummaries() =>
        [.. Store.List().Select(InstanceReportBuilder.Summary)];

    public InstanceInfo? InstanceInfo(string reference) =>
        Store.Resolve(reference) is { } instance ? InstanceReportBuilder.Info(instance, Settings.Cgroup) : null;

    /// <summary>An instance's run state, version, ports, backups and recent output; null when the reference names none.</summary>
    public async Task<InstanceStatus?> StatusAsync(string reference, bool measureDisk = false, CancellationToken cancellationToken = default) =>
        Store.Resolve(reference) is { } instance ? await StatusOfAsync(instance, measureDisk, cancellationToken).ConfigureAwait(false) : null;

    public Task<InstanceStatus> StatusOfAsync(InstanceDescription instance, bool measureDisk = false, CancellationToken cancellationToken = default) =>
        new InstanceStatusReader(_watchdog, _containers, Settings.Watchdog.Enabled).ReadAsync(instance, measureDisk, cancellationToken);

    /// <summary>Every instance's status, read concurrently, keyed by instance id.</summary>
    public async Task<IReadOnlyDictionary<string, InstanceStatus>> StatusAllAsync(bool measureDisk = false, CancellationToken cancellationToken = default)
    {
        IReadOnlyList<InstanceDescription> instances = Store.List();
        InstanceStatus[] statuses = await Task.WhenAll(instances.Select(i => StatusOfAsync(i, measureDisk, cancellationToken))).ConfigureAwait(false);
        return instances.Zip(statuses).ToDictionary(pair => pair.First.Id, pair => pair.Second, StringComparer.Ordinal);
    }

    /// <summary>An instance's config as key, value and whether <c>config set</c> may change it; null when the config cannot be read.</summary>
    public IReadOnlyList<ConfigEntry>? ConfigEntries(string reference) =>
        Store.Resolve(reference)?.Config is { } config ? InstanceConfigKeys.Entries(config) : null;

    /// <summary>The last lines a native instance wrote; a container's come from <c>docker compose logs</c>.</summary>
    public async Task<LogTail?> LogsAsync(string reference, int lines = 100, CancellationToken cancellationToken = default)
    {
        if (Store.Resolve(reference) is not { Config: { } config } instance) return null;
        InstanceLayout layout = instance.Layout;

        if (config.Runtime == BlueprintRuntime.Container)
        {
            if (!File.Exists(layout.ComposeFile)) return null;
            (IReadOnlyList<string>? tail, _) = await _containers.TailAsync(layout.ComposeFile, lines, cancellationToken).ConfigureAwait(false);
            return tail is null ? null : new LogTail { Instance = instance.Id, Lines = tail };
        }

        string? source = InstanceLogs.SourceFile(layout);
        return source is null ? null : new LogTail { Instance = instance.Id, File = source, Lines = InstanceLogs.Tail(source, lines) };
    }

    /// <summary>
    /// The argument list an instance is launched with, the placeholders resolved against its config: what the
    /// watchdog hands the process. Null when the reference names no instance or its config cannot be read.
    /// </summary>
    public IReadOnlyList<string>? LaunchArguments(string reference) =>
        Store.Resolve(reference) is { Config: { } config } instance
            ? InstancePlaceholders.ResolveLaunchArguments(config, instance.Layout)
            : null;

    // ── Backups ───────────────────────────────────────────────────────────────────────────────

    /// <summary>An instance's backups, newest first; null when the reference names none or its config cannot be read.</summary>
    public BackupListing? Backups(string reference) =>
        Store.Resolve(reference)?.Config is { } config ? BackupReader.List(config.BackupsDirectory) : null;

    // ── Blueprints ────────────────────────────────────────────────────────────────────────────

    private BlueprintCatalog Catalog => new(Paths, new BlueprintParser(_loggers.CreateLogger<BlueprintParser>()));

    public IReadOnlyList<BlueprintListing> Blueprints() => Catalog.List();

    public BlueprintResolution FindBlueprint(string name) => Catalog.Find(name);

    /// <summary>The blueprint's parse result, or null when no file of that name exists.</summary>
    public BlueprintParseResult? ReadBlueprint(string name) => Catalog.Read(name);

    /// <summary>What a blueprint needs from this host and whether each is present; null when it does not exist or does not validate.</summary>
    public BlueprintRequirements? BlueprintRequirements(string name) =>
        Catalog.Read(name)?.Blueprint is { } blueprint
            ? BlueprintRequirementRules.Evaluate(blueprint, new HostRequirementProbe(
                key => System.Environment.GetEnvironmentVariable(key), EnginePaths.SteamCredentialsFilePath))
            : null;

    public BlueprintValidation ValidateBlueprintFile(string path) => new BlueprintParser().ParseFile(path).Validation;

    // ── Libraries and ports ───────────────────────────────────────────────────────────────────

    public IReadOnlyList<Library> LibraryList() => Libraries.List(Store.Registered());

    public IReadOnlyList<PortUse> PortsInUse() => PortSpecs.Used(Store.List());

    public IReadOnlyList<PortConflict> PortConflicts() => PortSpecs.Conflicts(PortSpecs.Used(Store.List()));

    /// <summary>
    /// The ports the host is listening on, TCP and UDP, each once, with the process that holds it where
    /// the caller may see it and unknown otherwise.
    /// </summary>
    public IReadOnlyList<Contracts.Operations.ListeningPort> ListeningPorts() => HostSockets.Listening();

    public void Dispose() => _loggers.Dispose();

    private static IReadOnlyDictionary<string, string?> ProcessEnvironment() =>
        System.Environment.GetEnvironmentVariables().Cast<System.Collections.DictionaryEntry>()
            .ToDictionary(e => (string)e.Key, e => (string?)e.Value, StringComparer.Ordinal);

    /// <summary>The directory of the real file behind the binary: a name is searched for on <c>PATH</c>, a link is followed.</summary>
    private static string InstallRootOf(string binary)
    {
        string? path = binary.Contains('/', StringComparison.Ordinal) ? binary : OnPath(binary);
        if (path is null || !File.Exists(path)) return AppContext.BaseDirectory;

        FileSystemInfo? target = new FileInfo(path).ResolveLinkTarget(returnFinalTarget: true);
        return Path.GetDirectoryName(Path.GetFullPath(target?.FullName ?? path)) ?? AppContext.BaseDirectory;
    }

    private static string? OnPath(string name) =>
        (System.Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(':', StringSplitOptions.RemoveEmptyEntries)
            .Select(directory => Path.Combine(directory, name))
            .FirstOrDefault(File.Exists);
}
