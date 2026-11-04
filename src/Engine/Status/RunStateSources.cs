using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Watchdog.Client;
using TheKrystalShip.KGSM.Watchdog.Model;

namespace TheKrystalShip.KGSM.Engine.Status;

/// <summary>What the engine asks of the watchdog to learn a native instance's run state.</summary>
public interface IWatchdogProbe
{
    /// <summary>Whether the control socket exists; an absent socket means no daemon is installed here.</summary>
    bool SocketPresent { get; }

    Task<WatchdogHealth> HealthAsync(CancellationToken cancellationToken);

    /// <summary>The instance's state, or null when the daemon does not track it.</summary>
    /// <exception cref="WatchdogUnavailableException">The daemon stopped answering.</exception>
    Task<InstanceState?> StatusAsync(string instance, CancellationToken cancellationToken);
}


/// <summary>The state of one service in a compose project, as <c>docker compose ps</c> reports it.</summary>
public sealed record ComposeService(string Name, string State);

/// <summary>The outcome of asking the container runtime: the services it lists, or why it could not be asked.</summary>
public sealed record ComposeAnswer(IReadOnlyList<ComposeService>? Services, string? Problem)
{
    public static ComposeAnswer Of(IReadOnlyList<ComposeService> services) => new(services, null);

    public static ComposeAnswer Unavailable(string problem) => new(null, problem);
}

/// <summary>What the engine asks of the container runtime.</summary>
public interface IContainerRuntime
{
    /// <summary>The running services of a compose project.</summary>
    Task<ComposeAnswer> ListRunningAsync(string composeFile, CancellationToken cancellationToken);

    /// <summary>The last lines of a compose project's output; null with a reason when the runtime cannot be asked.</summary>
    Task<(IReadOnlyList<string>? Lines, string? Problem)> TailAsync(string composeFile, int lines, CancellationToken cancellationToken);

    /// <summary>Streams a compose project's output to this process's own stdout until cancelled; returns the runtime's exit code.</summary>
    Task<int> FollowAsync(string composeFile, int lines, CancellationToken cancellationToken);
}

/// <summary>The runtime through <c>docker compose ps</c>.</summary>
public sealed class DockerCompose : IContainerRuntime
{
    public async Task<ComposeAnswer> ListRunningAsync(string composeFile, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo("docker")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (string argument in new[] { "compose", "-f", composeFile, "ps", "--format", "json" })
            start.ArgumentList.Add(argument);

        try
        {
            using Process? process = Process.Start(start);
            if (process is null) return ComposeAnswer.Unavailable("docker could not be started");

            Task<string> output = process.StandardOutput.ReadToEndAsync(cancellationToken);
            Task<string> error = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

            if (process.ExitCode != 0)
            {
                string first = (await error.ConfigureAwait(false)).Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).FirstOrDefault() ?? "no message";
                return ComposeAnswer.Unavailable($"docker compose ps failed: {first}");
            }

            return Parse(await output.ConfigureAwait(false));
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return ComposeAnswer.Unavailable("docker is not installed");
        }
    }

    public async Task<(IReadOnlyList<string>? Lines, string? Problem)> TailAsync(string composeFile, int lines, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo("docker")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (string argument in new[] { "compose", "-f", composeFile, "logs", "--no-color", "--tail", lines.ToString(System.Globalization.CultureInfo.InvariantCulture) })
            start.ArgumentList.Add(argument);

        try
        {
            using Process? process = Process.Start(start);
            if (process is null) return (null, "docker could not be started");

            Task<string> output = process.StandardOutput.ReadToEndAsync(cancellationToken);
            Task<string> error = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

            if (process.ExitCode != 0)
            {
                string first = (await error.ConfigureAwait(false)).Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).FirstOrDefault() ?? "no message";
                return (null, $"docker compose logs failed: {first}");
            }

            return ([.. (await output.ConfigureAwait(false)).Split('\n', StringSplitOptions.RemoveEmptyEntries)], null);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return (null, "docker is not installed");
        }
    }

    public async Task<int> FollowAsync(string composeFile, int lines, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo("docker") { UseShellExecute = false };
        foreach (string argument in new[] { "compose", "-f", composeFile, "logs", "--follow", "--tail", lines.ToString(System.Globalization.CultureInfo.InvariantCulture) })
            start.ArgumentList.Add(argument);

        try
        {
            using Process? process = Process.Start(start);
            if (process is null) return 1;

            using CancellationTokenRegistration stop = cancellationToken.Register(() =>
            {
                try { process.Kill(); } catch (InvalidOperationException) { }
            });
            await process.WaitForExitAsync(CancellationToken.None).ConfigureAwait(false);
            return cancellationToken.IsCancellationRequested ? 0 : process.ExitCode;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return 1;
        }
    }

    /// <summary>
    /// Reads the output of <c>docker compose ps --format json</c>: one object per line, or one array,
    /// depending on the compose version.
    /// </summary>
    public static ComposeAnswer Parse(string output)
    {
        try
        {
            string trimmed = output.Trim();
            if (trimmed.Length == 0) return ComposeAnswer.Of([]);

            ComposePsEntry[] entries = trimmed[0] == '['
                ? JsonSerializer.Deserialize(trimmed, InternalJsonContext.Default.ComposePsEntryArray) ?? []
                : [.. trimmed.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Select(line => JsonSerializer.Deserialize(line, InternalJsonContext.Default.ComposePsEntry))
                    .OfType<ComposePsEntry>()];

            return ComposeAnswer.Of([.. entries.Select(e => new ComposeService(e.Service ?? e.Name ?? string.Empty, e.State ?? string.Empty))]);
        }
        catch (JsonException ex)
        {
            return ComposeAnswer.Unavailable($"docker compose ps answered with something that is not JSON: {ex.Message}");
        }
    }
}

/// <summary>The fields of a <c>docker compose ps</c> entry the engine reads.</summary>
internal sealed record ComposePsEntry(
    [property: JsonPropertyName("Service")] string? Service,
    [property: JsonPropertyName("Name")] string? Name,
    [property: JsonPropertyName("State")] string? State);
