using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Instances;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// The lock a transfer places on an instance while it is exported or imported. It is a file in the
/// instance's working directory holding the holder's token and the autostart flag the lock switched off.
/// A locked instance refuses start, restart, move, update, every backup change and every config change,
/// and the only way past it is the token itself or <c>instance unlock</c>.
/// </summary>
public static partial class TransferLock
{
    /// <summary>The token the lock is held under, or null when the instance is not locked.</summary>
    public static string? Holder(InstanceLayout layout)
    {
        if (!File.Exists(layout.TransferLockFile)) return null;
        try
        {
            return Read(layout)?.Token ?? "(unreadable)";
        }
        catch (Exception ex) when (ex is EngineException or IOException or UnauthorizedAccessException)
        {
            return "(unreadable)";
        }
    }

    /// <summary>The lock record, or null when there is no lock.</summary>
    /// <exception cref="EngineException">The file is not a lock record this engine reads.</exception>
    public static TransferLockRecord? Read(InstanceLayout layout) =>
        ContractFile.ReadIfExists(
            layout.TransferLockFile, EngineJsonContext.Default.TransferLockRecord, SchemaVersions.TransferLock, r => r.SchemaVersion);

    /// <summary>Writes the lock whole.</summary>
    public static void Place(InstanceLayout layout, string token, bool autostart) =>
        ContractFile.Write(
            layout.TransferLockFile,
            new TransferLockRecord { SchemaVersion = SchemaVersions.TransferLock, Token = token, Autostart = autostart },
            EngineJsonContext.Default.TransferLockRecord);

    /// <summary>Refuses an action on a locked instance.</summary>
    /// <param name="instance">The instance.</param>
    /// <param name="action">What was asked, for the refusal.</param>
    /// <param name="token">The token the caller holds, which passes its own lock.</param>
    /// <exception cref="TransferLockedException">The instance is locked under another token, or the caller holds none.</exception>
    public static void Require(InstanceDescription instance, string action, string? token = null)
    {
        string? holder = Holder(instance.Layout);
        if (holder is null) return;
        if (token is not null && string.Equals(holder, token, StringComparison.Ordinal)) return;

        throw new TransferLockedException(instance.Id, action);
    }

    /// <summary>Deletes the lock file; false when there was none.</summary>
    public static bool Delete(InstanceLayout layout)
    {
        if (!File.Exists(layout.TransferLockFile)) return false;
        File.Delete(layout.TransferLockFile);
        return true;
    }

    /// <summary>A token is written to disk and compared byte for byte, so it is held to a small alphabet.</summary>
    public static bool IsValidToken(string? token) => token is not null && TokenPattern().IsMatch(token);

    [GeneratedRegex("^[A-Za-z0-9_.:@-]{1,128}$")]
    private static partial Regex TokenPattern();
}
