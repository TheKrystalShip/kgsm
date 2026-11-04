using TheKrystalShip.KGSM.Cli;
using TheKrystalShip.KGSM.Engine.Accounts;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Settings;
using TheKrystalShip.KGSM.Engine.Status;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Tests.Cli;

/// <summary>What a command line printed and returned.</summary>
internal sealed record CliRun(int Exit, string Out, string Err);

/// <summary>A watchdog that answers what a test tells it to and holds no socket.</summary>
internal sealed class FakeWatchdog : IWatchdogControl
{
    /// <summary>What the watchdog was asked to do, in order, as <c>verb instance</c>.</summary>
    public List<string> Actions { get; } = [];

    /// <summary>The origin each start and stop carried.</summary>
    public List<string?> Origins { get; } = [];

    public ActionResult StartResult { get; set; } = new("", true, "started");

    public ActionResult StopResult { get; set; } = new("", true, "stopped");

    public ActionResult ForgetResult { get; set; } = new("", true, "forgotten");

    /// <summary>Runs when the watchdog is asked to start an instance, so a test can make the world match what a real start does.</summary>
    public Action<string>? OnStart { get; set; }

    public Action<string>? OnStop { get; set; }

    public Task<ActionResult> StartAsync(string instance, bool force, string? origin, CancellationToken cancellationToken)
    {
        Actions.Add(force ? $"start {instance} --force" : $"start {instance}");
        Origins.Add(origin);
        if (StartResult.Ok) OnStart?.Invoke(instance);
        return Task.FromResult(StartResult with { Instance = instance });
    }

    public Task<ActionResult> StopAsync(string instance, string? origin, CancellationToken cancellationToken)
    {
        Actions.Add($"stop {instance}");
        Origins.Add(origin);
        if (StopResult.Ok) OnStop?.Invoke(instance);
        return Task.FromResult(StopResult with { Instance = instance });
    }

    /// <summary>The boot-autostart set.</summary>
    public HashSet<string> Autostart { get; } = [];

    /// <summary>Whether enabling is refused.</summary>
    public bool RefuseEnable { get; set; }

    public Task<ActionResult> EnableAsync(string instance, CancellationToken cancellationToken)
    {
        Actions.Add($"enable {instance}");
        if (RefuseEnable) return Task.FromResult(new ActionResult(instance, false, "refused"));
        Autostart.Add(instance);
        return Task.FromResult(new ActionResult(instance, true, "enabled"));
    }

    public Task<ActionResult> DisableAsync(string instance, CancellationToken cancellationToken)
    {
        Actions.Add($"disable {instance}");
        Autostart.Remove(instance);
        return Task.FromResult(new ActionResult(instance, true, "disabled"));
    }

    public Task<IReadOnlyList<string>> EnabledAsync(CancellationToken cancellationToken)
    {
        if (ThrowOnStatus) throw new WatchdogUnavailableException("the watchdog went away");
        return Task.FromResult<IReadOnlyList<string>>([.. Autostart.Order(StringComparer.Ordinal)]);
    }

    public Task<ActionResult> ForgetAsync(string instance, CancellationToken cancellationToken)
    {
        Actions.Add($"forget {instance}");
        return Task.FromResult(ForgetResult with { Instance = instance });
    }

    public bool SocketPresent { get; set; } = true;

    public WatchdogHealth Health { get; set; } = new(true, true, "in the slice");

    public Dictionary<string, InstanceState> Tracked { get; } = [];

    public bool ThrowOnStatus { get; set; }

    public int Calls { get; private set; }

    public Task<WatchdogHealth> HealthAsync(CancellationToken cancellationToken)
    {
        Calls++;
        return Task.FromResult(Health);
    }

    public Task<InstanceState?> StatusAsync(string instance, CancellationToken cancellationToken)
    {
        Calls++;
        if (ThrowOnStatus) throw new WatchdogUnavailableException("the watchdog went away");
        return Task.FromResult(Tracked.GetValueOrDefault(instance));
    }

    public static InstanceState State(string name, bool populated, int? pid = null, string phase = "running", DateTime? spawnedAt = null) =>
        new(name, populated ? "running" : "stopped", true, populated, pid, "/sys/fs/cgroup/x/" + name, phase, 0, "test", spawnedAt);
}

/// <summary>A container runtime that answers what a test tells it to.</summary>
internal sealed class FakeContainers : IContainerRuntime
{
    public ComposeAnswer Answer { get; set; } = ComposeAnswer.Of([]);

    public (IReadOnlyList<string>?, string?) Logs { get; set; } = ([], null);

    public Task<ComposeAnswer> ListRunningAsync(string composeFile, CancellationToken cancellationToken) => Task.FromResult(Answer);

    public Task<(IReadOnlyList<string>? Lines, string? Problem)> TailAsync(string composeFile, int lines, CancellationToken cancellationToken) =>
        Task.FromResult(Logs);

    public Task<int> FollowAsync(string composeFile, int lines, CancellationToken cancellationToken) => Task.FromResult(0);
}

/// <summary>
/// A container runtime's images that answer what a test tells them to. A saved image is the text
/// <c>reference|chain|size</c>, and loading reads that text back under an id of the loading runtime's own,
/// as a second runtime would, so a stream a test damages loads as something else or not at all.
/// </summary>
internal sealed class FakeImages : IImageStore
{
    public Dictionary<string, ImageInfo> Held { get; } = new(StringComparer.Ordinal);

    /// <summary>The references each compose file resolves to.</summary>
    public Dictionary<string, string[]> Compose { get; } = new(StringComparer.Ordinal);

    public long? Free { get; set; }

    public bool RemoveFails { get; set; }

    public List<string> Calls { get; } = [];

    public List<string> Removed { get; } = [];

    public ImageInfo Add(string reference, string chain, long size = 100)
    {
        var image = new ImageInfo("local-" + chain, size, chain);
        Held[reference] = image;
        return image;
    }

    public Task<IReadOnlyList<string>> ReferencedByAsync(string composeFile, string workingDirectory, CancellationToken cancellationToken)
    {
        Calls.Add($"references {Path.GetFileName(composeFile)}");
        return Compose.TryGetValue(composeFile, out string[]? references)
            ? Task.FromResult<IReadOnlyList<string>>(references)
            : throw new OperationException(ErrorCodes.Failed, $"the container runtime cannot resolve the images of {composeFile}");
    }

    public Task<ImageInfo?> InspectAsync(string reference, CancellationToken cancellationToken)
    {
        Calls.Add($"inspect {reference}");
        ImageInfo? found = Held.TryGetValue(reference, out ImageInfo? byReference) ? byReference : Held.Values.FirstOrDefault(i => i.Id == reference);
        return Task.FromResult(found);
    }

    public async Task SaveAsync(string reference, Stream destination, CancellationToken cancellationToken)
    {
        Calls.Add($"save {reference}");
        ImageInfo image = Held[reference];
        await destination.WriteAsync(System.Text.Encoding.UTF8.GetBytes($"{reference}|{image.Chain}|{image.Size}"), cancellationToken);
    }

    public async Task LoadAsync(Stream source, CancellationToken cancellationToken)
    {
        Calls.Add("load");
        using var reader = new StreamReader(source, System.Text.Encoding.UTF8, leaveOpen: true);
        string[] fields = (await reader.ReadToEndAsync(cancellationToken)).Split('|');
        if (fields.Length != 3 || !long.TryParse(fields[2], out long size)) throw new OperationException(ErrorCodes.Failed, "docker load failed: not an image");
        Held[fields[0]] = new ImageInfo("loaded-" + fields[1], size, fields[1]);
    }

    public Task TagAsync(string imageId, string reference, CancellationToken cancellationToken)
    {
        Calls.Add($"tag {imageId} {reference}");
        Held[reference] = Held.Values.First(i => i.Id == imageId);
        return Task.CompletedTask;
    }

    public Task<bool> RemoveAsync(string idOrReference, CancellationToken cancellationToken)
    {
        Calls.Add($"remove {idOrReference}");
        if (RemoveFails) return Task.FromResult(false);

        foreach (string key in Held.Where(h => h.Key == idOrReference || h.Value.Id == idOrReference).Select(h => h.Key).ToList()) Held.Remove(key);
        Removed.Add(idOrReference);
        return Task.FromResult(true);
    }

    public Task<long?> FreeBytesAsync(CancellationToken cancellationToken) => Task.FromResult(Free);
}

/// <summary>Runs no program: it records each call and answers what a test scripts.</summary>
internal sealed class FakeProcesses : IProcessRunner
{
    public List<ProcessCall> Calls { get; } = [];

    /// <summary>Answers a call; the default is a silent success.</summary>
    public Func<ProcessCall, ProcessResult> Handler { get; set; } = _ => new ProcessResult(0, string.Empty, string.Empty);

    /// <summary>The arguments of every call to an instance's management script, as one string each.</summary>
    public IReadOnlyList<string> ScriptCalls => [.. Calls.Where(c => c.FileName.EndsWith(".manage.sh", StringComparison.Ordinal)).Select(c => string.Join(' ', c.Arguments))];

    public Task<ProcessResult> RunAsync(ProcessCall call, CancellationToken cancellationToken)
    {
        lock (Calls) Calls.Add(call);
        return Task.FromResult(Handler(call));
    }
}

/// <summary>A firewall authority that answers what a test tells it to.</summary>
internal sealed class FakeFirewall : IFirewallClient
{
    public List<string> Calls { get; } = [];

    public FirewallVerdict Verdict { get; set; } = FirewallVerdict.Success;

    public Task<FirewallVerdict> EnsureOpenAsync(string instance, IReadOnlyList<TheKrystalShip.KGSM.Engine.Contracts.Network.PortRange> ports, TheKrystalShip.KGSM.Engine.Journal.Provenance provenance, CancellationToken cancellationToken)
    {
        Calls.Add($"ensure-open {instance} {string.Join(' ', ports.Select(FirewallCli.Token))}");
        return Task.FromResult(Verdict);
    }

    public Task<FirewallVerdict> RemoveAsync(string instance, TheKrystalShip.KGSM.Engine.Journal.Provenance provenance, CancellationToken cancellationToken)
    {
        Calls.Add($"remove {instance}");
        return Task.FromResult(Verdict);
    }
}

internal sealed class FakeRequirements(params string[] present) : IRequirementProbe
{
    public bool IsPresent(string requirementId) => present.Contains(requirementId);
}

/// <summary>Runs command lines in-process against a sandbox: its homes, install root, journal directory and sockets, and nothing else.</summary>
internal sealed class CliSession
{
    public CliSession(Sandbox sandbox, bool withBlueprints = false)
    {
        Sandbox = sandbox;
        Directory.CreateDirectory(sandbox.InstallRoot);
        File.Copy(Path.Combine(AppContext.BaseDirectory, "kgsm.settings.json"), Path.Combine(sandbox.InstallRoot, "kgsm.settings.json"), overwrite: true);

        if (withBlueprints)
        {
            Directory.CreateDirectory(sandbox.Paths.SystemBlueprintsDirectory);
            foreach (string file in Directory.EnumerateFiles(Path.Combine(AppContext.BaseDirectory, "blueprints")))
                File.Copy(file, Path.Combine(sandbox.Paths.SystemBlueprintsDirectory, Path.GetFileName(file)), overwrite: true);
        }
    }

    public Sandbox Sandbox { get; }

    public FakeWatchdog Watchdog { get; } = new();

    public FakeContainers Containers { get; } = new();

    public FakeRequirements Requirements { get; set; } = new("steamcmd", "steam-credentials", "container-runtime");

    public Func<int, bool> ProcessAlive { get; set; } = _ => false;

    public Func<string, IReadOnlyList<string>, AccountVerdict> AccountGate { get; set; } = (_, _) => AccountVerdict.Ok;

    public FakeProcesses Processes { get; } = new();

    public FakeFirewall Firewall { get; } = new();

    public FakeImages Images { get; } = new();

    /// <summary>What a command streams out as raw bytes.</summary>
    public MemoryStream RawStdout { get; set; } = new();

    /// <summary>What a command streams in as raw bytes.</summary>
    public Stream RawStdin { get; set; } = new MemoryStream();

    public string? EngineVersion { get; set; }

    public bool Interactive { get; set; }

    public Func<string, bool>? Ask { get; set; }

    public TextReader? Stdin { get; set; }

    public Microsoft.Extensions.Time.Testing.FakeTimeProvider Clock { get; } = new(new DateTimeOffset(2026, 11, 4, 12, 0, 0, TimeSpan.Zero));

    public Dictionary<string, string?> Extra { get; } = [];

    public CliEnvironment Environment()
    {
        var variables = new Dictionary<string, string?>
        {
            ["HOME"] = Path.Combine(Sandbox.Root, "home"),
            ["XDG_CONFIG_HOME"] = Path.Combine(Sandbox.Root, "config"),
            ["XDG_DATA_HOME"] = Path.Combine(Sandbox.Root, "data"),
            ["XDG_STATE_HOME"] = Path.Combine(Sandbox.Root, "state"),
            ["Journal__Directory"] = Sandbox.JournalDirectory,
            ["Watchdog__Socket"] = Path.Combine(Sandbox.Root, "run", "control.sock"),
            ["PATH"] = string.Empty,
        };
        foreach ((string key, string? value) in Extra) variables[key] = value;

        return new CliEnvironment
        {
            Variables = variables,
            InstallRoot = Sandbox.InstallRoot,
            HomeFallback = Path.Combine(Sandbox.Root, "home"),
            WatchdogProbe = _ => Watchdog,
            Containers = Containers,
            ProcessAlive = ProcessAlive,
            AccountGate = AccountGate,
            Requirements = Requirements,
            Processes = Processes,
            Firewall = Firewall,
            Images = Images,
            RawStdout = RawStdout,
            RawStdin = RawStdin,
            EngineVersion = EngineVersion,
            BinaryPath = "/test/bin/kgsm",
            Interactive = Interactive,
            Ask = Ask,
            Stdin = Stdin,
            UserName = "tester",
            SettleTimeout = TimeSpan.Zero,
            Clock = Clock,
        };
    }

    public async Task<CliRun> RunAsync(params string[] args)
    {
        var stdout = new StringWriter();
        var stderr = new StringWriter();
        int exit = await CliApp.RunAsync(args, Environment(), stdout, stderr, CancellationToken.None);
        return new CliRun(exit, stdout.ToString(), stderr.ToString());
    }
}
