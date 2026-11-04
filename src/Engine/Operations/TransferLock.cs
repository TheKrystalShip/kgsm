using TheKrystalShip.KGSM.Engine.Instances;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// The lock a transfer places on an instance while it is exported or imported. It is a file in the
/// instance's working directory holding the holder's token. A locked instance refuses start, restart,
/// move, update, every backup change and every config change, and the only way past it is the token
/// itself or <c>instance unlock</c>.
/// </summary>
public static class TransferLock
{
    /// <summary>The token the lock is held under, or null when the instance is not locked.</summary>
    public static string? Holder(InstanceLayout layout)
    {
        try
        {
            if (!File.Exists(layout.TransferLockFile)) return null;
            string token = File.ReadAllText(layout.TransferLockFile).Trim();
            return token.Length == 0 ? "(unnamed)" : token;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return "(unreadable)";
        }
    }

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

    /// <summary>Releases the lock; false when there was none.</summary>
    public static bool Release(InstanceLayout layout)
    {
        if (!File.Exists(layout.TransferLockFile)) return false;
        File.Delete(layout.TransferLockFile);
        return true;
    }
}
