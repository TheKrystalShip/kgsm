using System.Collections;
using TheKrystalShip.KGSM.Engine.Accounts;
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

    /// <summary>The watchdog probe for the configured socket; the real one when unset.</summary>
    public Func<WatchdogSettings, IWatchdogProbe>? WatchdogProbe { get; init; }

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
