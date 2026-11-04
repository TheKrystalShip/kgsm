using TheKrystalShip.KGSM.Engine.Status;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>What the engine asks of the watchdog beyond reading: carrying out a lifecycle action and keeping the autostart set.</summary>
public interface IWatchdogControl : IWatchdogProbe
{
    /// <param name="instance">The instance.</param>
    /// <param name="force">A person's override of the memory admission check.</param>
    /// <param name="origin">The surface that asked; it reaches the daemon's own log.</param>
    /// <param name="cancellationToken">Cancellation of the command.</param>
    /// <exception cref="WatchdogUnavailableException">The daemon stopped answering.</exception>
    Task<ActionResult> StartAsync(string instance, bool force, string? origin, CancellationToken cancellationToken);

    Task<ActionResult> StopAsync(string instance, string? origin, CancellationToken cancellationToken);

    Task<ActionResult> EnableAsync(string instance, CancellationToken cancellationToken);

    Task<ActionResult> DisableAsync(string instance, CancellationToken cancellationToken);

    /// <summary>Drops an instance from supervision, stopping it first; not Ok while it is still live.</summary>
    Task<ActionResult> ForgetAsync(string instance, CancellationToken cancellationToken);
}

/// <summary>
/// The watchdog over its real control socket. A stop drains for the instance's whole stop timeout, so
/// actions use a client with a patient timeout while reads keep the short one.
/// </summary>
public sealed class WatchdogControl(string socketPath) : IWatchdogControl, IDisposable
{
    private static readonly TimeSpan ActionTimeout = TimeSpan.FromMinutes(10);

    private readonly Lazy<WatchdogClient> _reads = new(() => new WatchdogClient(socketPath));
    private readonly Lazy<WatchdogClient> _actions = new(() => new WatchdogClient(socketPath, ActionTimeout));

    public bool SocketPresent => File.Exists(socketPath);

    public Task<WatchdogHealth> HealthAsync(CancellationToken cancellationToken) => _reads.Value.HealthAsync(cancellationToken);

    public Task<InstanceState?> StatusAsync(string instance, CancellationToken cancellationToken) =>
        _reads.Value.StatusAsync(instance, cancellationToken);

    public Task<ActionResult> StartAsync(string instance, bool force, string? origin, CancellationToken cancellationToken) =>
        _actions.Value.StartAsync(instance, force, origin, cancellationToken);

    public Task<ActionResult> StopAsync(string instance, string? origin, CancellationToken cancellationToken) =>
        _actions.Value.StopAsync(instance, origin, cancellationToken);

    public Task<ActionResult> EnableAsync(string instance, CancellationToken cancellationToken) =>
        _actions.Value.EnableAsync(instance, cancellationToken);

    public Task<ActionResult> DisableAsync(string instance, CancellationToken cancellationToken) =>
        _actions.Value.DisableAsync(instance, cancellationToken);

    public Task<ActionResult> ForgetAsync(string instance, CancellationToken cancellationToken) =>
        _actions.Value.ForgetAsync(instance, cancellationToken);

    public void Dispose()
    {
        if (_reads.IsValueCreated) _reads.Value.Dispose();
        if (_actions.IsValueCreated) _actions.Value.Dispose();
    }
}
