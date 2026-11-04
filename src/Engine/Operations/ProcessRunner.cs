using System.Diagnostics;
using System.Text;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>An external program to run and the world to run it in.</summary>
/// <param name="FileName">The program: a path, or a name looked up on <c>PATH</c>.</param>
/// <param name="Arguments">Its arguments, passed as they are; nothing goes through a shell.</param>
/// <param name="WorkingDirectory">Where it runs; the caller's directory when null.</param>
/// <param name="Environment">Variables added to the caller's environment.</param>
public sealed record ProcessCall(
    string FileName,
    IReadOnlyList<string> Arguments,
    string? WorkingDirectory = null,
    IReadOnlyDictionary<string, string>? Environment = null);

/// <summary>What a finished program left behind.</summary>
/// <param name="ExitCode">Its exit status; <see cref="NotStarted"/> when it could not be run at all.</param>
/// <param name="Output">What it wrote to stdout.</param>
/// <param name="Error">What it wrote to stderr.</param>
public sealed record ProcessResult(int ExitCode, string Output, string Error)
{
    /// <summary>The exit status reported for a program that could not be started.</summary>
    public const int NotStarted = -1;

    public bool Succeeded => ExitCode == 0;

    /// <summary>The last non-empty line of the output, where a script puts a result's id or version.</summary>
    public string LastOutputLine =>
        Output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).LastOrDefault() ?? string.Empty;

    /// <summary>The last lines the program wrote to its error stream, for a failure message.</summary>
    public string ErrorTail(int lines = 3) =>
        string.Join(" | ", Error.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).TakeLast(lines));
}

/// <summary>What the engine asks of the machine to run a program. A test supplies its own.</summary>
public interface IProcessRunner
{
    Task<ProcessResult> RunAsync(ProcessCall call, CancellationToken cancellationToken);
}

/// <summary>Runs programs as child processes.</summary>
public sealed class SystemProcessRunner : IProcessRunner
{
    public async Task<ProcessResult> RunAsync(ProcessCall call, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo(call.FileName)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            UseShellExecute = false,
            WorkingDirectory = call.WorkingDirectory ?? string.Empty,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (string argument in call.Arguments) start.ArgumentList.Add(argument);
        if (call.Environment is not null)
        {
            foreach ((string key, string value) in call.Environment) start.Environment[key] = value;
        }

        try
        {
            using Process? process = Process.Start(start);
            if (process is null) return new ProcessResult(ProcessResult.NotStarted, string.Empty, $"{call.FileName} could not be started");

            // The program reads nothing from this process.
            process.StandardInput.Close();

            Task<string> output = process.StandardOutput.ReadToEndAsync(cancellationToken);
            Task<string> error = process.StandardError.ReadToEndAsync(cancellationToken);

            try
            {
                await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // The script's own children (a download, a game) go with it; none is left running unattended.
                try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
                throw;
            }

            return new ProcessResult(process.ExitCode, await output.ConfigureAwait(false), await error.ConfigureAwait(false));
        }
        catch (System.ComponentModel.Win32Exception ex)
        {
            return new ProcessResult(ProcessResult.NotStarted, string.Empty, $"{call.FileName} could not be started: {ex.Message}");
        }
    }
}
