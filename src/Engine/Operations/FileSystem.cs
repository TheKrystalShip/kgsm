using System.Runtime.InteropServices;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>File system facts and operations the engine needs beyond the base library.</summary>
public static partial class FileSystem
{
    private const int CurrentDirectory = -100; // AT_FDCWD
    private const uint TypeAndModeMask = 0x1 | 0x2; // STATX_TYPE | STATX_MODE
    private const int ModeOffset = 28;
    private const int DeviceMajorOffset = 136;
    private const int DeviceMinorOffset = 140;
    private const int StatxSize = 256;

    [LibraryImport("libc", EntryPoint = "statx", SetLastError = true, StringMarshalling = StringMarshalling.Utf8)]
    private static partial int Statx(int directory, string path, int flags, uint mask, [Out] byte[] buffer);

    /// <summary>
    /// Removes <c>&lt;library&gt;/instances/&lt;blueprint&gt;</c> and <c>&lt;library&gt;/instances</c> once the last instance in
    /// them is gone, so an emptied library holds nothing but its marker. A directory that holds anything stays.
    /// </summary>
    public static void RemoveEmptyInstanceParents(string workingDirectory)
    {
        string? blueprintDirectory = Path.GetDirectoryName(workingDirectory);
        string? instancesDirectory = blueprintDirectory is null ? null : Path.GetDirectoryName(blueprintDirectory);
        if (instancesDirectory is null || Path.GetFileName(instancesDirectory) != "instances") return;

        foreach (string directory in new[] { blueprintDirectory!, instancesDirectory })
        {
            try
            {
                if (Directory.Exists(directory) && !Directory.EnumerateFileSystemEntries(directory).Any()) Directory.Delete(directory);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                return;
            }
        }
    }

    /// <summary>The device a path lives on as <c>major:minor</c>, or null when it cannot be read.</summary>
    public static string? DeviceOf(string path)
    {
        byte[] buffer = new byte[StatxSize];
        if (Statx(CurrentDirectory, path, 0, TypeAndModeMask, buffer) != 0) return null;

        uint major = BitConverter.ToUInt32(buffer, DeviceMajorOffset);
        uint minor = BitConverter.ToUInt32(buffer, DeviceMinorOffset);
        return $"{major}:{minor}";
    }

    /// <summary>Whether two existing paths live on one device, so a rename between them is a rename and not a copy.</summary>
    public static bool SameDevice(string a, string b) => DeviceOf(a) is { } da && da == DeviceOf(b);

    /// <summary>
    /// Copies a directory tree, keeping symbolic links and permissions and skipping pipes and sockets (they
    /// are runtime artifacts). A file is copied to a hidden name and renamed when whole, and a file already
    /// there with the same length and modification time is left as it is, so a copy that was cut short
    /// resumes where it stopped.
    /// </summary>
    public static void CopyTree(string source, string destination, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(destination);
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(destination, File.GetUnixFileMode(source));

        foreach (string path in Directory.EnumerateFileSystemEntries(source))
        {
            cancellationToken.ThrowIfCancellationRequested();

            string name = Path.GetFileName(path);
            string target = Path.Combine(destination, name);
            FileSystemInfo entry = Directory.Exists(path) ? new DirectoryInfo(path) : new FileInfo(path);

            if (entry.LinkTarget is { } link)
            {
                if (File.Exists(target) || Directory.Exists(target) || new FileInfo(target).LinkTarget is not null) File.Delete(target);
                File.CreateSymbolicLink(target, link);
            }
            else if (entry is DirectoryInfo)
            {
                CopyTree(path, target, cancellationToken);
            }
            else if (IsRegular(path))
            {
                var file = (FileInfo)entry;
                if (File.Exists(target) && new FileInfo(target).Length == file.Length && File.GetLastWriteTimeUtc(target) == file.LastWriteTimeUtc)
                    continue;

                string partial = Path.Combine(destination, $".{name}.kgsm-partial");
                File.Copy(path, partial, overwrite: true);
                if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(partial, file.UnixFileMode);
                File.SetLastWriteTimeUtc(partial, file.LastWriteTimeUtc);
                File.Move(partial, target, overwrite: true);
            }
        }

        Directory.SetLastWriteTimeUtc(destination, Directory.GetLastWriteTimeUtc(source));
    }

    /// <summary>Whether a path is a regular file, as the kernel types it: a pipe, socket or device is not.</summary>
    private static bool IsRegular(string path)
    {
        byte[] buffer = new byte[StatxSize];
        if (Statx(CurrentDirectory, path, 0, TypeAndModeMask, buffer) != 0) return false;

        ushort mode = BitConverter.ToUInt16(buffer, ModeOffset);
        return (mode & 0xF000) == 0x8000; // S_IFREG
    }
}
