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

    public const string Busy = "busy";

    public const string Locked = "transfer-locked";

    public const string Running = "running";

    public const string InsufficientDisk = "insufficient-disk";

    public const string InsufficientMemory = "insufficient-memory";

    public const string FirewallUnreachable = "firewall-unreachable";

    public const string FirewallFailed = "firewall-failed";

    public const string Refused = "refused";

    public const string Integrity = "transfer-integrity";

    public const string ImportNotFound = "import-not-found";
}
