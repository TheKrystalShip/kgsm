namespace TheKrystalShip.KGSM.Engine;

/// <summary>
/// A refusal or failure the engine reports by name. <see cref="Code"/> is stable text a caller can
/// branch on; the message is for a person.
/// </summary>
public class EngineException(string code, string message, Exception? inner = null) : Exception(message, inner)
{
    public string Code { get; } = code;
}

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
