using System.Globalization;
using System.Runtime.InteropServices;

namespace TheKrystalShip.KGSM.Engine.Accounts;

/// <summary>The gate's decision: the command may run, or the journal belongs to another account.</summary>
public sealed record AccountVerdict(bool Allowed, string? Owner, string? Message)
{
    public static AccountVerdict Ok { get; } = new(true, null, null);
}

/// <summary>
/// The registry is per account and the journal is per host. When the journal directory belongs to another
/// account, a command run as this one would split the host's state between two registries, so it is
/// refused with the <c>sudo -u</c> line that runs it as the owner.
/// </summary>
public static partial class RegistryAccountGate
{
    private const int CurrentDirectory = -100; // AT_FDCWD
    private const uint UidMask = 0x8; // STATX_UID
    private const int UidOffset = 20; // stx_uid in struct statx, the same on every architecture
    private const int StatxSize = 256;

    [LibraryImport("libc", EntryPoint = "statx", SetLastError = true, StringMarshalling = StringMarshalling.Utf8)]
    private static partial int Statx(int directory, string path, int flags, uint mask, [Out] byte[] buffer);

    [LibraryImport("libc", EntryPoint = "geteuid")]
    private static partial uint GetEffectiveUserId();

    /// <summary>Checks the journal directory against the running account.</summary>
    /// <param name="journalDirectory">The directory the event journal is written to.</param>
    /// <param name="arguments">The command line, quoted into the suggested line.</param>
    public static AccountVerdict Check(string journalDirectory, IReadOnlyList<string> arguments) =>
        Check(journalDirectory, arguments, OwnerOf, GetEffectiveUserId(), NameOf);

    /// <summary>The decision with every system fact supplied, so a test owns all of them.</summary>
    public static AccountVerdict Check(
        string journalDirectory, IReadOnlyList<string> arguments,
        Func<string, uint?> ownerOf, uint effectiveUser, Func<uint, string?> nameOf)
    {
        uint? owner = ownerOf(journalDirectory);
        if (owner is null || owner == effectiveUser) return AccountVerdict.Ok;

        string name = nameOf(owner.Value) ?? owner.Value.ToString(CultureInfo.InvariantCulture);
        string line = "sudo -u " + name + " kgsm" + string.Concat(arguments.Select(a => " " + Quote(a)));
        return new AccountVerdict(
            false, name,
            $"The journal directory '{journalDirectory}' belongs to '{name}', and the registry is per account. Run: {line}");
    }

    /// <summary>The numeric owner of a path; null when it does not exist.</summary>
    public static uint? OwnerOf(string path)
    {
        if (!Directory.Exists(path)) return null;

        byte[] buffer = new byte[StatxSize];
        if (Statx(CurrentDirectory, path, 0, UidMask, buffer) != 0) return null;
        return BitConverter.ToUInt32(buffer, UidOffset);
    }

    /// <summary>The account name for a uid from <c>/etc/passwd</c>; null when it has none.</summary>
    public static string? NameOf(uint uid)
    {
        try
        {
            foreach (string line in File.ReadLines("/etc/passwd"))
            {
                string[] fields = line.Split(':');
                if (fields.Length > 2 && fields[2] == uid.ToString(CultureInfo.InvariantCulture)) return fields[0];
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }

        return null;
    }

    private static string Quote(string argument) =>
        argument.Length > 0 && argument.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.' or '/' or ':' or '=' or ',' or '@')
            ? argument
            : "'" + argument.Replace("'", "'\\''", StringComparison.Ordinal) + "'";
}
