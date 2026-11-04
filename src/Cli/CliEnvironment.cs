using System.Collections;
using TheKrystalShip.KGSM.Engine.Accounts;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Paths;
using TheKrystalShip.KGSM.Engine.Settings;
using TheKrystalShip.KGSM.Engine.Status;

namespace TheKrystalShip.KGSM.Cli;

/// <summary>
/// Everything the command line takes from the machine it runs on. The process supplies the real thing;
/// a test supplies its own, so a command run in a test touches nothing outside the test.
/// </summary>
internal sealed class CliEnvironment
{
    public required IReadOnlyDictionary<string, string?> Variables { get; init; }

    /// <summary>The directory the binary sits in.</summary>
    public required string InstallRoot { get; init; }

    public required string HomeFallback { get; init; }

    /// <summary>The watchdog for the configured socket; the real one when unset.</summary>
    public Func<WatchdogSettings, IWatchdogControl>? WatchdogProbe { get; init; }

    /// <summary>How external programs are run; child processes when unset.</summary>
    public IProcessRunner? Processes { get; init; }

    /// <summary>The firewall authority's client; the bundled command-line client when unset.</summary>
    public IFirewallClient? Firewall { get; init; }

    /// <summary>The running binary, which an instance's script calls back to report update phases; the process's own path when unset.</summary>
    public string? BinaryPath { get; init; } = Environment.ProcessPath;

    /// <summary>How long a start or stop waits for the run state to show it.</summary>
    public TimeSpan SettleTimeout { get; init; } = TimeSpan.FromSeconds(15);

    /// <summary>What a command reads from standard input; the process's when unset.</summary>
    public TextReader? Stdin { get; init; }

    /// <summary>The bytes a command streams to standard output (a transfer part); the process's own output when unset.</summary>
    public Stream? RawStdout { get; init; }

    /// <summary>The bytes a command streams from standard input (a transfer part); the process's own input when unset.</summary>
    public Stream? RawStdin { get; init; }

    /// <summary>The container runtime's images; the <c>docker</c> command line when unset.</summary>
    public IImageStore? Images { get; init; }

    /// <summary>The engine version a transfer compares; the running build's when unset.</summary>
    public string? EngineVersion { get; init; }

    /// <summary>Whether a person is at a terminal and can be asked; true when both input and output are terminals.</summary>
    public bool Interactive { get; init; } = !Console.IsInputRedirected && !Console.IsOutputRedirected;

    /// <summary>The account running the command, which names the actor when none is given at a terminal.</summary>
    public string UserName { get; init; } = Environment.UserName;

    /// <summary>Asks a person a yes-or-no question on the terminal; the real prompt when unset.</summary>
    public Func<string, bool>? Ask { get; init; }

    /// <summary>The container runtime; <c>docker compose</c> when unset.</summary>
    public IContainerRuntime? Containers { get; init; }

    /// <summary>Whether a pid is a live process; <c>/proc</c> when unset.</summary>
    public Func<int, bool>? ProcessAlive { get; init; }

    /// <summary>The registry-account gate; the real one when unset.</summary>
    public Func<string, IReadOnlyList<string>, AccountVerdict>? AccountGate { get; init; }

    /// <summary>Whether a requirement is present on the host; the real probe when unset.</summary>
    public Engine.Blueprints.IRequirementProbe? Requirements { get; init; }

    public TimeProvider Clock { get; init; } = TimeProvider.System;

    public Func<string, string?> Variable => name => Variables.TryGetValue(name, out string? value) ? value : null;

    public EnginePaths ResolvePaths() => EnginePaths.Resolve(Variable, InstallRoot, HomeFallback);

    public static CliEnvironment FromProcess()
    {
        var variables = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            if (entry.Key is string key) variables[key] = entry.Value as string;
        }

        return new CliEnvironment
        {
            Variables = variables,
            InstallRoot = AppContext.BaseDirectory,
            HomeFallback = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        };
    }
}
