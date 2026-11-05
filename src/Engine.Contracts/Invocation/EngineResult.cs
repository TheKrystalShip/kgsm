using TheKrystalShip.KGSM.Engine.Contracts.Reports;

namespace TheKrystalShip.KGSM.Engine.Contracts.Invocation;

/// <summary>
/// What running one engine command produced: the exit code, the report the command printed and, for a
/// refusal, the error report it wrote to standard error.
/// </summary>
/// <remarks>
/// A command that refuses still prints its verdict when the verdict is the answer (a manifest check, a
/// blueprint validation), so <see cref="Value"/> can be present while <see cref="IsSuccess"/> is false.
/// A failure is read from <see cref="Error"/>, never from the text of standard error.
/// </remarks>
public sealed record EngineResult<T> : IEngineResultInfo
{
    public required int ExitCode { get; init; }

    /// <summary>The report the command printed, or null when it printed none.</summary>
    public T? Value { get; init; }

    /// <summary>The error report the command wrote, or null when it succeeded or wrote none that parses.</summary>
    public ErrorReport? Error { get; init; }

    /// <summary>What the process wrote to standard error, for an exit with no parseable error report.</summary>
    public string Diagnostics { get; init; } = string.Empty;

    public bool IsSuccess => ExitCode == 0;

    public bool IsFailure => ExitCode != 0;

    /// <summary>The failure in one line: the error report's message, else the diagnostics, else the exit code.</summary>
    public string Message =>
        Error?.Message ?? (Diagnostics.Length > 0 ? Diagnostics : Described(ExitCode));

    internal static string Described(int exitCode) =>
        exitCode == 0 ? "the engine printed no report this client reads" : $"the engine exited {exitCode}";

    /// <summary>The value of a successful command.</summary>
    /// <exception cref="EngineCommandException">The command failed or printed nothing.</exception>
    public T Require() => IsSuccess && Value is not null ? Value : throw new EngineCommandException(this);

    public EngineResult<TOther> Without<TOther>() => new() { ExitCode = ExitCode, Error = Error, Diagnostics = Diagnostics };
}

/// <summary>A command failed where the caller required it to succeed.</summary>
public sealed class EngineCommandException : Exception
{
    public EngineCommandException(int exitCode, ErrorReport? error, string diagnostics)
        : base(error?.Message ?? (diagnostics.Length > 0 ? diagnostics : EngineResult<object>.Described(exitCode)))
    {
        ExitCode = exitCode;
        Error = error;
    }

    internal EngineCommandException(IEngineResultInfo result)
        : this(result.ExitCode, result.Error, result.Diagnostics)
    {
    }

    public int ExitCode { get; }

    public ErrorReport? Error { get; }
}

/// <summary>The parts of a result that do not depend on its report type.</summary>
internal interface IEngineResultInfo
{
    int ExitCode { get; }

    ErrorReport? Error { get; }

    string Diagnostics { get; }
}
