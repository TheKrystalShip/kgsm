using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Journal;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Runs an instance's management script, which holds the one implementation of every action that changes
/// an instance: start and stop without the watchdog, console input, download, deploy, update, backup
/// creation and restore. The script reports in its exit status (0, 1, 7 and 8 for a malformed call, 25 for
/// something that does not exist), its messages on stderr and its result on stdout.
/// </summary>
public sealed class ScriptClient(
    IProcessRunner runner, string watchdogSocket, Provenance provenance, IReadOnlyDictionary<string, string> inherited, ILogger? logger = null)
{
    /// <summary>Runs the script with these arguments and returns what it did, whatever its exit status.</summary>
    public async Task<ProcessResult> RunAsync(InstanceDescription instance, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        string script = instance.Layout.ManagementScript;
        if (!File.Exists(script))
            throw OperationException.Refused($"'{instance.Id}' has no management script; run 'kgsm instance repair {instance.Id}'");

        var environment = new Dictionary<string, string>(inherited, StringComparer.Ordinal)
        {
            ["KGSM_WATCHDOG_SOCKET"] = watchdogSocket,
        };
        if (provenance.Actor is { } actor) environment["KGSM_EVENT_ACTOR"] = actor;
        if (provenance.Origin is { } origin) environment["KGSM_EVENT_ORIGIN"] = origin;

        ProcessResult result = await runner.RunAsync(
            new ProcessCall(script, arguments, instance.WorkingDirectory, environment), cancellationToken).ConfigureAwait(false);

        logger?.LogInformation(
            "{Instance}: {Script} {Arguments} exited {ExitCode}{Messages}",
            instance.Id, Path.GetFileName(script), string.Join(' ', arguments.Select(Redact)), result.ExitCode,
            result.Error.Length == 0 ? string.Empty : "; " + result.ErrorTail(8));
        return result;
    }

    /// <summary>Runs the script and fails with its own words when it exits non-zero.</summary>
    /// <exception cref="OperationException">The script exited non-zero; <paramref name="what"/> says what it was doing.</exception>
    public async Task<ProcessResult> RequireAsync(
        InstanceDescription instance, IReadOnlyList<string> arguments, string what, CancellationToken cancellationToken)
    {
        ProcessResult result = await RunAsync(instance, arguments, cancellationToken).ConfigureAwait(false);
        if (result.Succeeded) return result;

        string detail = result.ErrorTail() is { Length: > 0 } tail ? tail : $"exit {result.ExitCode}";
        throw result.ExitCode switch
        {
            Contracts.ExitCodes.NotFound => OperationException.NotFound($"{what}: {detail}"),
            7 or 8 => OperationException.Invalid($"{what}: {detail}"),
            _ => new OperationException(ErrorCodes.Failed, $"{what}: {detail}"),
        };
    }

    // A line sent to the console can hold a password; the log keeps the verb and not the line.
    private static string Redact(string argument) => argument.Length > 64 ? argument[..64] + "..." : argument;
}
