namespace TheKrystalShip.KGSM.Engine.Contracts.Reports;

/// <summary>
/// A failure as the binary reports it on stderr: <c>code</c> is stable text a caller branches on, the
/// message is for a person, and <c>exitCode</c> repeats the process's exit status.
/// </summary>
public sealed record ErrorReport
{
    public required string Code { get; init; }

    public required string Message { get; init; }

    public required int ExitCode { get; init; }

    /// <summary>Further lines that belong to the failure, such as every problem a validation found.</summary>
    public IReadOnlyList<string> Details { get; init; } = [];
}

/// <summary>The stable error codes the binary uses.</summary>
public static class ErrorCodes
{
    public const string Usage = "usage";

    public const string NotFound = "not-found";

    public const string Ambiguous = "ambiguous";

    public const string WrongAccount = "wrong-account";

    public const string Invalid = "invalid";

    public const string Failed = "failed";
}
