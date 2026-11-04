using System.Diagnostics;
using System.Globalization;
using System.Text;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Scripts;
using TheKrystalShip.Testing;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>What a script printed and returned.</summary>
internal sealed record ScriptRun(int Exit, string Out, string Err)
{
    /// <summary>The last non-empty line of stdout, where a script puts a result's id.</summary>
    public string LastOutLine => Out.Split('\n', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? string.Empty;
}

/// <summary>
/// One generated management script in a world of its own: a real script written into a temporary working
/// directory by the engine's generator and run with bash, with every external tool replaced by a fake on a
/// <c>PATH</c> that holds nothing else. Nothing in it reaches outside the test's directory.
/// </summary>
internal sealed class ScriptWorld : IDisposable
{
    public const string Id = "g-1";

    private readonly List<Process> _helpers = [];

    private ScriptWorld(Sandbox sandbox, InstanceConfig config, string workingDirectory, HookFile? hooks, bool realCurl)
    {
        Sandbox = sandbox;
        Config = config;
        WorkingDirectory = workingDirectory;
        Hooks = hooks;

        Bin = Path.Combine(sandbox.Root, "bin");
        Control = Path.Combine(sandbox.Root, "fake");
        Directory.CreateDirectory(Bin);
        Directory.CreateDirectory(Control);

        FakeScripts.Install(Bin, "steamcmd", FakeScripts.Steamcmd);
        FakeScripts.Install(Bin, "docker", FakeScripts.Docker);
        if (realCurl) File.CreateSymbolicLink(Path.Combine(Bin, "curl"), HostTools.Find("curl") ?? throw new InvalidOperationException("the host has no curl"));
        else FakeScripts.Install(Bin, "curl", FakeScripts.Curl);

        SocketPath = Path.Combine(sandbox.Root, "w.sock");
        EnvFile = Path.Combine(sandbox.Root, "steam.env");
        Environment = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["PATH"] = Bin + ":" + HostTools.Path,
            ["HOME"] = Path.Combine(sandbox.Root, "home"),
            ["FAKE_DIR"] = Control,
            ["FAKE_LIFECYCLE"] = Path.Combine(workingDirectory, "events", "lifecycle.ndjson"),
            ["KGSM_ENV_FILE"] = EnvFile,
            ["KGSM_TERM_GRACE_SECONDS"] = "1",
            ["LC_ALL"] = "C.UTF-8",
        };
        Directory.CreateDirectory(Environment["HOME"]);
        Generate();
    }

    public Sandbox Sandbox { get; }

    public InstanceConfig Config { get; private set; }

    public string WorkingDirectory { get; }

    public HookFile? Hooks { get; private set; }

    /// <summary>The fakes' directory, first on the script's <c>PATH</c>.</summary>
    public string Bin { get; }

    /// <summary>Where the fakes keep what a test scripted and what they recorded; <c>$FAKE_DIR</c>.</summary>
    public string Control { get; }

    public string SocketPath { get; }

    public string EnvFile { get; }

    /// <summary>The environment the script runs in; a test may add or change a variable before a run.</summary>
    public Dictionary<string, string> Environment { get; }

    public FakeWatchdogServer? Watchdog { get; private set; }

    public string ScriptPath => Path.Combine(WorkingDirectory, $"{Id}.manage.sh");

    public string Install => Path.Combine(WorkingDirectory, "install");

    public string Saves => Path.Combine(WorkingDirectory, "saves");

    public string Logs => Path.Combine(WorkingDirectory, "logs");

    public string Temp => Path.Combine(WorkingDirectory, "temp");

    public string Events => Path.Combine(WorkingDirectory, "events");

    public string PidFile => Path.Combine(WorkingDirectory, $".{Id}.pid");

    public string InputFifo => Path.Combine(WorkingDirectory, $".{Id}.sock");

    public string LogFile => Path.Combine(WorkingDirectory, $"{Id}.log");

    public string VersionFile => Path.Combine(WorkingDirectory, $".{Id}.version");

    public string LatestFile => Path.Combine(WorkingDirectory, $".{Id}.latest");

    public string BackupsDirectory => Config.BackupsDirectory;

    /// <summary>A native instance whose executable is the fake game.</summary>
    public static ScriptWorld Native(
        Func<InstanceConfig, InstanceConfig>? shape = null, string? hooks = null, string blueprint = "g", bool realCurl = false)
    {
        var sandbox = Sandbox.Create();
        var library = sandbox.AddLibrary("main");
        string backups = Path.Combine(sandbox.Root, "backups", Id);

        (string workingDirectory, InstanceConfig config) = sandbox.AddInstance(library, blueprint, Id, baseConfig =>
        {
            InstanceConfig shaped = baseConfig with
            {
                ExecutableFile = "./server",
                StopCommand = "stop",
                SaveCommand = "save",
                SaveCommandTimeoutSeconds = 0,
                StopCommandTimeoutSeconds = 5,
                BroadcastCommand = "say {message}",
                KickCommand = "kick {name}",
                BanCommand = "ban {ip}",
                UnbanCommand = "pardon {id}",
                BackupsDirectory = backups,
            };
            return shape is null ? shaped : shape(shaped);
        });

        HookFile? hookFile = null;
        if (hooks is not null)
        {
            string path = sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemOverridesDirectory, blueprint, HookFiles.FileName), hooks);
            hookFile = HookFiles.Find(sandbox.Paths, blueprint);
            _ = path;
        }

        var world = new ScriptWorld(sandbox, config, workingDirectory, hookFile, realCurl);
        world.PrepareDirectories();
        FakeScripts.Install(world.Install, "server", FakeScripts.Game);
        return world;
    }

    /// <summary>A container instance with a compose file that exists and docker faked.</summary>
    public static ScriptWorld Container(Func<InstanceConfig, InstanceConfig>? shape = null)
    {
        var sandbox = Sandbox.Create();
        var library = sandbox.AddLibrary("main");
        string backups = Path.Combine(sandbox.Root, "backups", Id);

        (string workingDirectory, InstanceConfig config) = sandbox.AddInstance(library, "gc", Id, baseConfig =>
        {
            InstanceConfig shaped = baseConfig with
            {
                Runtime = BlueprintRuntime.Container,
                StopCommand = "stop",
                SaveCommand = "save",
                SaveCommandTimeoutSeconds = 0,
                StopCommandTimeoutSeconds = 5,
                BroadcastCommand = "say {message}",
                KickCommand = "kick {name}",
                BackupsDirectory = backups,
                ExecutableFile = string.Empty,
                ExecutableArguments = string.Empty,
            };
            return shape is null ? shaped : shape(shaped);
        });

        var world = new ScriptWorld(sandbox, config, workingDirectory, hooks: null, realCurl: false);
        world.PrepareDirectories();
        File.WriteAllText(Path.Combine(workingDirectory, $"{Id}.docker-compose.yml"), "services: {}\n");
        return world;
    }

    private void PrepareDirectories()
    {
        foreach (string directory in new[] { Install, Saves, Logs, Temp, Events })
            Directory.CreateDirectory(directory);
    }

    /// <summary>Writes the script again from the world's config and hooks.</summary>
    public void Generate()
    {
        File.Delete(ScriptPath);
        ScriptFile.Write(ScriptPath, ScriptGenerator.Render(Config, Hooks, SocketPath));
    }

    /// <summary>Replaces the config on disk and regenerates the script.</summary>
    public void Reconfigure(Func<InstanceConfig, InstanceConfig> shape)
    {
        Config = shape(Config);
        ContractFile.Write(new InstanceLayout(WorkingDirectory, Id).ConfigFile, Config, EngineJsonContext.Default.InstanceConfig);
        Generate();
    }

    /// <summary>Starts the fake watchdog on the world's socket.</summary>
    public FakeWatchdogServer StartWatchdog() => Watchdog ??= new FakeWatchdogServer(SocketPath);

    /// <summary>Makes the pipe the image's entrypoint would serve and reads it into <c>container-input</c>.</summary>
    public void ServeCommandFifo()
    {
        string fifo = Path.Combine(Events, "command.fifo");
        RunTool("mkfifo", fifo);

        string log = Path.Combine(Control, "container-input");
        var start = new ProcessStartInfo(HostTools.Find("bash")!) { UseShellExecute = false, RedirectStandardInput = true };
        start.ArgumentList.Add("-c");
        start.ArgumentList.Add("exec 3<>\"$1\"; while IFS= read -r line <&3; do printf '%s\\n' \"$line\" >>\"$2\"; done");
        start.ArgumentList.Add("reader");
        start.ArgumentList.Add(fifo);
        start.ArgumentList.Add(log);
        _helpers.Add(Process.Start(start)!);
    }

    /// <summary>The path of a file under the fakes' control directory.</summary>
    public string Fake(string relative) => Path.Combine(Control, relative);

    /// <summary>Scripts a fake: writes a file under the control directory.</summary>
    public void Script(string relative, string content)
    {
        string path = Fake(relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
    }

    /// <summary>The lines a fake or the fake game recorded, or none.</summary>
    public string[] Recorded(string relative) =>
        File.Exists(Fake(relative)) ? File.ReadAllLines(Fake(relative)) : [];

    /// <summary>The calls a fake logged under the control directory, each as its argument list.</summary>
    public string[][] Calls(string relative) =>
        [.. Recorded(relative).Select(line => line.Split('\u001f', StringSplitOptions.None)[..^1])];

    /// <summary>The arguments the fake game received.</summary>
    public string[] GameArguments() =>
        File.ReadAllText(Fake("game/args")).Split('\0', StringSplitOptions.None) is { Length: > 0 } parts ? parts[..^1] : [];

    /// <summary>Serves a url to the fake curl.</summary>
    public void Serve(string url, string content) => Script("curl/" + FixtureKey(url), content);

    /// <summary>Serves a url to the fake curl from bytes.</summary>
    public void Serve(string url, byte[] content)
    {
        string path = Fake("curl/" + FixtureKey(url));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, content);
    }

    private static string FixtureKey(string url) =>
        Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(url)))[..16];

    /// <summary>Runs the script with arguments, its stdin closed.</summary>
    public Task<ScriptRun> RunAsync(params string[] args) => RunWithInputAsync(string.Empty, args);

    /// <summary>Runs the script with arguments, its stdin holding <paramref name="stdin"/>.</summary>
    public async Task<ScriptRun> RunWithInputAsync(string stdin, params string[] args)
    {
        var start = new ProcessStartInfo(HostTools.Find("bash")!)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            WorkingDirectory = Sandbox.Root,
        };
        start.ArgumentList.Add(ScriptPath);
        foreach (string arg in args) start.ArgumentList.Add(arg);
        start.Environment.Clear();
        foreach ((string key, string value) in Environment) start.Environment[key] = value;

        using Process process = Process.Start(start) ?? throw new InvalidOperationException("bash did not start");
        await process.StandardInput.WriteAsync(stdin);
        process.StandardInput.Close();
        Task<string> output = process.StandardOutput.ReadToEndAsync();
        Task<string> error = process.StandardError.ReadToEndAsync();

        using var ceiling = new CancellationTokenSource(TimeSpan.FromSeconds(90));
        try
        {
            await process.WaitForExitAsync(ceiling.Token);
        }
        catch (OperationCanceledException)
        {
            process.Kill(entireProcessTree: true);
            throw new TimeoutException($"{string.Join(' ', args)} did not finish; it had printed:\n{await output}\n{await error}");
        }

        return new ScriptRun(process.ExitCode, await output, await error);
    }

    /// <summary>Starts the game with <c>start -d</c> and waits until it has read its arguments.</summary>
    public async Task<ScriptRun> StartGameAsync()
    {
        ScriptRun run = await RunAsync("start", "-d");
        Assert.True(run.Exit == 0, run.Err);
        await Eventually.Holds(() => File.Exists(Fake("game/started")), "the fake game started");
        return run;
    }

    public int GamePid() => int.Parse(File.ReadAllText(Fake("game/pid")).Trim(), CultureInfo.InvariantCulture);

    public int ChildPid() => int.Parse(File.ReadAllText(Fake("game/child.pid")).Trim(), CultureInfo.InvariantCulture);

    /// <summary>Makes a named pipe nothing reads or writes.</summary>
    public void MakeFifo(string path) => RunTool("mkfifo", path);

    private void RunTool(string tool, params string[] args)
    {
        var start = new ProcessStartInfo(HostTools.Find(tool)!) { UseShellExecute = false };
        foreach (string arg in args) start.ArgumentList.Add(arg);
        using Process process = Process.Start(start)!;
        process.WaitForExit();
    }

    public void Dispose()
    {
        foreach (string file in new[] { Fake("game/pid"), Fake("game/child.pid"), PidFile })
        {
            if (File.Exists(file) && int.TryParse(File.ReadAllText(file).Trim(), CultureInfo.InvariantCulture, out int pid))
                ProcessTable.Kill(pid);
        }

        foreach (Process helper in _helpers)
        {
            try
            {
                helper.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
            }

            helper.Dispose();
        }

        Watchdog?.Dispose();
        try
        {
            Directory.Delete(Sandbox.Root, recursive: true);
        }
        catch (IOException)
        {
        }
    }
}
