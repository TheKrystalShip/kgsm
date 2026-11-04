using TheKrystalShip.KGSM.Cli;
using TheKrystalShip.KGSM.Engine.Accounts;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Settings;
using TheKrystalShip.KGSM.Engine.Status;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Tests.Cli;

/// <summary>What a command line printed and returned.</summary>
internal sealed record CliRun(int Exit, string Out, string Err);

/// <summary>A watchdog that answers what a test tells it to and holds no socket.</summary>
internal sealed class FakeWatchdog : IWatchdogProbe
{
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
