using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Journal;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>What the firewall authority answered.</summary>
/// <param name="Ok">Whether the authority applied or removed the rule, or found it already so.</param>
/// <param name="Unreachable">Whether the authority could not be asked at all, as opposed to rejecting the request.</param>
/// <param name="Detail">The authority's words, or why it could not be asked.</param>
public sealed record FirewallVerdict(bool Ok, bool Unreachable, string? Detail)
{
    public static FirewallVerdict Success { get; } = new(true, false, null);

    /// <summary>Turns a refusal into the exception that ends the command, with the exit status the verdict names.</summary>
    public void ThrowIfRefused(string what)
    {
        if (Ok) return;

        throw Unreachable
            ? new OperationException(ErrorCodes.FirewallUnreachable, $"{what}: the firewall authority cannot be reached ({Detail})", ExitCodes.FirewallUnreachable)
            : new OperationException(ErrorCodes.FirewallFailed, $"{what}: the firewall authority refused ({Detail})", ExitCodes.FirewallFailed);
    }
}

/// <summary>What the engine asks of the firewall authority. Rules it writes are tagged <c>kgsm-&lt;instance&gt;</c> by the authority.</summary>
public interface IFirewallClient
{
    /// <summary>Asserts that exactly these ports are open for the instance.</summary>
    Task<FirewallVerdict> EnsureOpenAsync(string instance, IReadOnlyList<PortRange> ports, Provenance provenance, CancellationToken cancellationToken);

    /// <summary>Removes every rule the authority owns for the instance; a rule that is not there is a success.</summary>
    Task<FirewallVerdict> RemoveAsync(string instance, Provenance provenance, CancellationToken cancellationToken);
}

/// <summary>
/// The authority through its own command-line client. Its exit status carries the distinction that
/// matters: 3 is an authority that did not answer, anything else non-zero one that answered no.
/// </summary>
public sealed class FirewallCli(IProcessRunner runner, FirewallSettings settings) : IFirewallClient
{
    private const int UnreachableExit = 3;

    public Task<FirewallVerdict> EnsureOpenAsync(string instance, IReadOnlyList<PortRange> ports, Provenance provenance, CancellationToken cancellationToken)
    {
        List<string> arguments = ["ensure-open", instance, .. ports.Select(Token)];
        return RunAsync(arguments, provenance, cancellationToken);
    }

    public Task<FirewallVerdict> RemoveAsync(string instance, Provenance provenance, CancellationToken cancellationToken) =>
        RunAsync(["remove", instance], provenance, cancellationToken);

    /// <summary>A range as the client spells it: <c>34197/udp</c> or <c>27015:27020/tcp</c>.</summary>
    public static string Token(PortRange range)
    {
        string numbers = range.Start == range.End
            ? range.Start.ToString(CultureInfo.InvariantCulture)
            : $"{range.Start.ToString(CultureInfo.InvariantCulture)}:{range.End.ToString(CultureInfo.InvariantCulture)}";
        return $"{numbers}/{range.Protocol.ToString().ToLowerInvariant()}";
    }

    private async Task<FirewallVerdict> RunAsync(IReadOnlyList<string> arguments, Provenance provenance, CancellationToken cancellationToken)
    {
        var environment = new Dictionary<string, string> { ["KGSM_FIREWALL_SOCKET"] = settings.Socket };
        if (provenance.Actor is { } actor) environment["KGSM_EVENT_ACTOR"] = actor;
        if (provenance.Origin is { } origin) environment["KGSM_EVENT_ORIGIN"] = origin;

        ProcessResult result = await runner.RunAsync(new ProcessCall(settings.Client, arguments, Environment: environment), cancellationToken)
            .ConfigureAwait(false);

        if (result.Succeeded) return FirewallVerdict.Success;

        string detail = result.ErrorTail() is { Length: > 0 } tail ? tail : $"exit {result.ExitCode.ToString(CultureInfo.InvariantCulture)}";
        return new FirewallVerdict(false, result.ExitCode is ProcessResult.NotStarted or UnreachableExit, detail);
    }
}
