namespace TheKrystalShip.KGSM.Engine;

/// <summary>
/// A refusal or failure the engine reports by name. <see cref="Code"/> is stable text a caller can
/// branch on; the message is for a person.
/// </summary>
public class EngineException(string code, string message, Exception? inner = null) : Exception(message, inner)
{
    public string Code { get; } = code;

    /// <summary>The process exit status this refusal ends a command with.</summary>
    public virtual int ExitCode => Contracts.ExitCodes.Failure;
}

/// <summary>A refusal or failure of an operation that carries an exit status of its own.</summary>
public class OperationException(string code, string message, int exitCode = Contracts.ExitCodes.Failure, IReadOnlyList<string>? details = null, Exception? inner = null)
    : EngineException(code, message, inner)
{
    public override int ExitCode => exitCode;

    /// <summary>Further lines that belong to the failure.</summary>
    public IReadOnlyList<string> Details { get; } = details ?? [];

    public static OperationException NotFound(string message) =>
        new(Contracts.Reports.ErrorCodes.NotFound, message, Contracts.ExitCodes.NotFound);

    public static OperationException Refused(string message, IReadOnlyList<string>? details = null) =>
        new(Contracts.Reports.ErrorCodes.Refused, message, Contracts.ExitCodes.Failure, details);

    public static OperationException Invalid(string message, IReadOnlyList<string>? details = null) =>
        new(Contracts.Reports.ErrorCodes.Invalid, message, Contracts.ExitCodes.Failure, details);
}

/// <summary>An instance is held by a transfer, so nothing that would change it may run.</summary>
public sealed class TransferLockedException(string instance, string action)
    : OperationException(
        Contracts.Reports.ErrorCodes.Locked,
        $"'{instance}' is held by a transfer; {action} is refused until it is unlocked",
        Contracts.ExitCodes.TransferLocked);

/// <summary>Another process holds the lock the operation needs. Nothing waits.</summary>
public sealed class EngineBusyException(string lockName)
    : EngineException("busy", $"'{lockName}' is busy: another kgsm command holds it")
{
    public string LockName { get; } = lockName;
}

/// <summary>A file carries a <c>schemaVersion</c> this engine does not know, so it is refused rather than misread.</summary>
public sealed class UnsupportedSchemaVersionException(string path, int? found, int expected)
    : EngineException(
        "unsupported-schema-version",
        $"'{path}' has schemaVersion {(found is { } v ? v.ToString(System.Globalization.CultureInfo.InvariantCulture) : "(none)")}; this engine reads {expected}")
{
    public string Path { get; } = path;

    public int? Found { get; } = found;

    public int Expected { get; } = expected;
}

/// <summary>A file the engine owns cannot be read as the type it should be.</summary>
public sealed class EngineFormatException(string path, string detail, Exception? inner = null)
    : EngineException("invalid-format", $"'{path}' cannot be read: {detail}", inner)
{
    public string Path { get; } = path;
}

/// <summary>A display name matches several instances, so it names none of them.</summary>
public sealed class AmbiguousInstanceException(string reference, IReadOnlyList<string> candidates)
    : EngineException("ambiguous", $"'{reference}' matches several instances: {string.Join(", ", candidates)}")
{
    public IReadOnlyList<string> Candidates { get; } = candidates;
}
