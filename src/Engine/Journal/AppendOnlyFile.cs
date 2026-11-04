using System.Runtime.InteropServices;

namespace TheKrystalShip.KGSM.Engine.Journal;

/// <summary>
/// Appends one whole record to a file through a descriptor opened with <c>O_APPEND</c>. With that flag the
/// kernel moves to the end of the file and writes in one step, so any number of processes appending
/// records below <c>PIPE_BUF</c> land them whole, one after another, with no lock. A managed
/// <c>FileStream</c> opened in append mode seeks to the end once and then writes at that remembered offset,
/// which lets two writers overwrite each other.
/// </summary>
internal static partial class AppendOnlyFile
{
    private const int WriteOnly = 0x1;
    private const int Create = 0x40;
    private const int Append = 0x400;
    private const int CloseOnExec = 0x80000;
    private const int ModeRw_R_R = 0x1A4; // 0644
    private const int Interrupted = 4; // EINTR

    [LibraryImport("libc", EntryPoint = "open", SetLastError = true, StringMarshalling = StringMarshalling.Utf8)]
    private static partial int Open(string path, int flags, int mode);

    [LibraryImport("libc", EntryPoint = "write", SetLastError = true)]
    private static partial nint Write(int descriptor, ReadOnlySpan<byte> buffer, nuint count);

    [LibraryImport("libc", EntryPoint = "close", SetLastError = true)]
    private static partial int Close(int descriptor);

    /// <summary>Appends <paramref name="record"/> to <paramref name="path"/>, creating the file when it is not there.</summary>
    /// <exception cref="IOException">The file cannot be opened or written.</exception>
    public static void Write(string path, ReadOnlySpan<byte> record)
    {
        int descriptor;
        do
        {
            descriptor = Open(path, WriteOnly | Create | Append | CloseOnExec, ModeRw_R_R);
        }
        while (descriptor < 0 && Marshal.GetLastPInvokeError() == Interrupted);

        if (descriptor < 0) throw Failure("open", path);

        try
        {
            while (!record.IsEmpty)
            {
                nint written = Write(descriptor, record, (nuint)record.Length);
                if (written < 0)
                {
                    if (Marshal.GetLastPInvokeError() == Interrupted) continue;
                    throw Failure("write", path);
                }

                record = record[(int)written..];
            }
        }
        finally
        {
            Close(descriptor);
        }
    }

    private static Exception Failure(string call, string path)
    {
        int errno = Marshal.GetLastPInvokeError();
        return errno switch
        {
            13 or 1 => new UnauthorizedAccessException($"{call} '{path}': permission denied"),
            _ => new IOException($"{call} '{path}' failed (errno {errno})"),
        };
    }
}
