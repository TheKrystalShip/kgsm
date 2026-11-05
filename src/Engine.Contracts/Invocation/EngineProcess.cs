using System.Diagnostics;
using System.Text;

namespace TheKrystalShip.KGSM.Engine.Contracts.Invocation;

/// <summary>What a finished engine process left: its exit code and what it wrote.</summary>
public sealed record EngineProcessResult(int ExitCode, string Stdout, string Stderr);

/// <summary>
/// What a streamed engine process left: its exit code, what it wrote to standard output when nothing was
/// asked to receive it (capped), and what it wrote to standard error (capped).
/// </summary>
public sealed record EngineStreamResult(int ExitCode, string Stdout, string Stderr);

/// <summary>
/// The door to the operating system for the typed invocation. Arguments are passed as a list, never as
/// shell text, so a value is one argument whatever characters it holds.
/// </summary>
public interface IEngineProcess
{
    /// <summary>Runs the binary, optionally feeding standard input, and buffers its output.</summary>
    Task<EngineProcessResult> RunAsync(
        string binary,
        IReadOnlyList<string> arguments,
        IReadOnlyDictionary<string, string> environment,
        string? standardInput,
        CancellationToken cancellationToken);

    /// <summary>
    /// Runs the binary with standard input read from <paramref name="source"/> and standard output copied
    /// to <paramref name="destination"/>, whichever are given; nothing is held whole. Without a destination
    /// the (small) output is returned. Cancelling kills the process tree.
    /// </summary>
    Task<EngineStreamResult> RunStreamingAsync(
        string binary,
        IReadOnlyList<string> arguments,
        IReadOnlyDictionary<string, string> environment,
        Stream? source,
        Stream? destination,
        CancellationToken cancellationToken);
}

/// <summary>Runs the engine binary as a child process.</summary>
public sealed class SystemEngineProcess : IEngineProcess
{
    private const int StderrCapBytes = 64 * 1024;
    private const int CopyBufferBytes = 1024 * 1024;

    public async Task<EngineProcessResult> RunAsync(
        string binary,
        IReadOnlyList<string> arguments,
        IReadOnlyDictionary<string, string> environment,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        using Process process = Start(binary, arguments, environment, redirectInput: standardInput is not null, redirectOutput: true);

        try
        {
            Task<string> stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
            Task<string> stderr = process.StandardError.ReadToEndAsync(cancellationToken);

            if (standardInput is not null)
            {
                await process.StandardInput.WriteAsync(standardInput.AsMemory(), cancellationToken).ConfigureAwait(false);
                process.StandardInput.Close();
            }

            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            return new EngineProcessResult(process.ExitCode, await stdout.ConfigureAwait(false), await stderr.ConfigureAwait(false));
        }
        catch (OperationCanceledException)
        {
            Kill(process);
            throw;
        }
    }

    public async Task<EngineStreamResult> RunStreamingAsync(
        string binary,
        IReadOnlyList<string> arguments,
        IReadOnlyDictionary<string, string> environment,
        Stream? source,
        Stream? destination,
        CancellationToken cancellationToken)
    {
        using Process process = Start(binary, arguments, environment, redirectInput: source is not null, redirectOutput: true);

        try
        {
            Task<string> stderr = ReadCappedAsync(process.StandardError.BaseStream, cancellationToken);
            Task<string> stdout = destination is null
                ? ReadCappedAsync(process.StandardOutput.BaseStream, cancellationToken)
                : Task.FromResult(string.Empty);

            Task feed = source is null
                ? Task.CompletedTask
                : FeedAsync(source, process.StandardInput.BaseStream, cancellationToken);
            Task drain = destination is null
                ? Task.CompletedTask
                : process.StandardOutput.BaseStream.CopyToAsync(destination, CopyBufferBytes, cancellationToken);

            await Task.WhenAll(feed, drain).ConfigureAwait(false);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            return new EngineStreamResult(process.ExitCode, await stdout.ConfigureAwait(false), await stderr.ConfigureAwait(false));
        }
        catch
        {
            Kill(process);
            throw;
        }
    }

    private static async Task FeedAsync(Stream source, Stream input, CancellationToken cancellationToken)
    {
        try
        {
            await source.CopyToAsync(input, CopyBufferBytes, cancellationToken).ConfigureAwait(false);
            await input.FlushAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (IOException)
        {
            // The engine closed its input early: it refused the stream, and its exit code says why.
        }
        finally
        {
            input.Close();
        }
    }

    private static async Task<string> ReadCappedAsync(Stream stream, CancellationToken cancellationToken)
    {
        var kept = new MemoryStream();
        var buffer = new byte[8192];
        int read;
        while ((read = await stream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
        {
            int room = StderrCapBytes - (int)kept.Length;
            if (room > 0) kept.Write(buffer, 0, Math.Min(room, read));
        }

        return Encoding.UTF8.GetString(kept.GetBuffer(), 0, (int)kept.Length);
    }

    private static Process Start(
        string binary, IReadOnlyList<string> arguments, IReadOnlyDictionary<string, string> environment,
        bool redirectInput, bool redirectOutput)
    {
        var info = new ProcessStartInfo(binary)
        {
            RedirectStandardInput = redirectInput,
            RedirectStandardOutput = redirectOutput,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = redirectOutput ? new UTF8Encoding(false) : null,
            StandardErrorEncoding = new UTF8Encoding(false),
        };

        foreach (string argument in arguments) info.ArgumentList.Add(argument);
        foreach ((string key, string value) in environment) info.Environment[key] = value;

        return Process.Start(info) ?? throw new InvalidOperationException($"{binary} did not start.");
    }

    private static void Kill(Process process)
    {
        try
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
        }
        catch (InvalidOperationException)
        {
            // It exited between the check and the kill.
        }
    }
}
