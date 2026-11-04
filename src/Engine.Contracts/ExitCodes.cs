namespace TheKrystalShip.KGSM.Engine.Contracts;

/// <summary>
/// The exit codes the binary returns. A command that succeeds returns <see cref="Success"/>, a failure
/// <see cref="Failure"/>, a malformed command line <see cref="Usage"/>; the rest are contracts other
/// components read, and the specific error is the <c>code</c> of the error report on stderr.
/// </summary>
public static class ExitCodes
{
    public const int Success = 0;

    public const int Failure = 1;

    public const int Usage = 2;

    /// <summary>The instance, blueprint, backup or library asked for does not exist. kgsm-api's transfer reads it as "already done".</summary>
    public const int NotFound = 25;

    /// <summary>The node has no room to start the instance; a deferral, not a fault.</summary>
    public const int InsufficientMemory = 51;

    public const int InsufficientDisk = 56;

    public const int InstanceRunning = 57;

    public const int TransferLocked = 59;

    public const int TransferVersionMismatch = 60;

    public const int TransferRequirementMissing = 61;

    public const int TransferPortConflict = 62;

    public const int TransferIntegrity = 63;

    public const int TransferImportNotFound = 64;
}
