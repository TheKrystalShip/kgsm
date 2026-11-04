using System.Formats.Tar;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using TheKrystalShip.KGSM.Engine.Operations;

namespace TheKrystalShip.KGSM.Engine.Transfers;

/// <summary>What the tree part carries on disk: a top-level name in the archive and where it comes from.</summary>
/// <param name="Name">The path inside the archive: <c>instance</c>, <c>backups</c>, <c>blueprint/&lt;file&gt;</c> or <c>overrides/&lt;name&gt;/hooks.sh</c>.</param>
/// <param name="Path">The directory or file on disk.</param>
/// <param name="Excluded">File names directly inside a directory member that are left out.</param>
internal sealed record TreeMember(string Name, string Path, IReadOnlySet<string>? Excluded = null);

internal enum TreeEntryKind
{
    Directory,
    File,
    Symlink,
}

/// <summary>One entry of the tree part.</summary>
internal sealed record TreeEntry(string Name, string FullPath, TreeEntryKind Kind, long Length, string? LinkTarget, UnixFileMode Mode);

/// <summary>The outcome of reading a tree stream: it was whole, or the reason it was not.</summary>
internal sealed class TreeIntegrityException(string message, Exception? inner = null) : Exception(message, inner);

/// <summary>
/// The tree part as a stream: a pax tar of the members, closed by a digest entry that covers every name,
/// length and byte before it. The tar's own header checksums catch a damaged header; the digest catches a
/// damaged byte of content, which a tar alone does not. Nothing is staged or buffered: the bytes leave as
/// they are read and are written as they arrive.
/// </summary>
internal static class TreeArchive
{
    /// <summary>The last entry of the stream, holding the digest as lowercase hex.</summary>
    public const string DigestEntryName = ".kgsm-tree-digest";

    /// <summary>The entries of the members in a fixed order: the same enumeration measures, writes and verifies.</summary>
    public static IEnumerable<TreeEntry> Enumerate(IEnumerable<TreeMember> members)
    {
        foreach (TreeMember member in members)
        {
            if (File.Exists(member.Path) && !Directory.Exists(member.Path))
            {
                if (FileSystem.IsRegular(member.Path)) yield return FileEntry(member.Name, new FileInfo(member.Path));
                continue;
            }

            if (!Directory.Exists(member.Path)) continue;

            yield return new TreeEntry(member.Name, member.Path, TreeEntryKind.Directory, 0, null, ModeOf(member.Path));
            foreach (TreeEntry entry in Walk(member.Name, new DirectoryInfo(member.Path), member.Excluded)) yield return entry;
        }
    }

    /// <summary>The bytes of regular files and the count of entries that are not directories. A directory's own size is the file system's and left out.</summary>
    public static (long Bytes, long Files) Measure(IEnumerable<TreeMember> members)
    {
        long bytes = 0;
        long files = 0;
        foreach (TreeEntry entry in Enumerate(members))
        {
            if (entry.Kind == TreeEntryKind.Directory) continue;
            files++;
            if (entry.Kind == TreeEntryKind.File) bytes += entry.Length;
        }

        return (bytes, files);
    }

    private static IEnumerable<TreeEntry> Walk(string name, DirectoryInfo directory, IReadOnlySet<string>? excluded)
    {
        foreach (FileSystemInfo info in directory.EnumerateFileSystemInfos().OrderBy(i => i.Name, StringComparer.Ordinal))
        {
            if (excluded is not null && excluded.Contains(info.Name)) continue;

            string entryName = name + "/" + info.Name;
            if (info.LinkTarget is { } link)
            {
                yield return new TreeEntry(entryName, info.FullName, TreeEntryKind.Symlink, 0, link, UnixFileMode.None);
            }
            else if (info is DirectoryInfo child)
            {
                yield return new TreeEntry(entryName, child.FullName, TreeEntryKind.Directory, 0, null, ModeOf(child.FullName));
                foreach (TreeEntry entry in Walk(entryName, child, null)) yield return entry;
            }
            else if (FileSystem.IsRegular(info.FullName))
            {
                yield return FileEntry(entryName, (FileInfo)info);
            }
        }
    }

    private static UnixFileMode ModeOf(string path) => OperatingSystem.IsWindows() ? UnixFileMode.None : File.GetUnixFileMode(path);

    private static TreeEntry FileEntry(string name, FileInfo file) =>
        new(name, file.FullName, TreeEntryKind.File, file.Length, null, ModeOf(file.FullName));

    /// <summary>Writes the entries as a tar stream and closes it with the digest.</summary>
    public static async Task WriteAsync(IEnumerable<TreeEntry> entries, Stream destination, CancellationToken cancellationToken)
    {
        using IncrementalHash digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);

        await using (var writer = new TarWriter(destination, TarEntryFormat.Pax, leaveOpen: true))
        {
            foreach (TreeEntry entry in entries)
            {
                cancellationToken.ThrowIfCancellationRequested();
                AppendHeader(digest, entry.Kind, entry.Name, entry.Kind == TreeEntryKind.File ? entry.Length : 0, entry.LinkTarget);

                switch (entry.Kind)
                {
                    case TreeEntryKind.Directory:
                        await writer.WriteEntryAsync(new PaxTarEntry(TarEntryType.Directory, entry.Name) { Mode = entry.Mode }, cancellationToken).ConfigureAwait(false);
                        break;
                    case TreeEntryKind.Symlink:
                        await writer.WriteEntryAsync(new PaxTarEntry(TarEntryType.SymbolicLink, entry.Name) { LinkName = entry.LinkTarget! }, cancellationToken).ConfigureAwait(false);
                        break;
                    default:
                        await using (var source = new DigestReadStream(new FileStream(entry.FullPath, FileMode.Open, FileAccess.Read, FileShare.Read, 1), digest, entry.Length))
                        {
                            var tarEntry = new PaxTarEntry(TarEntryType.RegularFile, entry.Name)
                            {
                                Mode = entry.Mode,
                                ModificationTime = File.GetLastWriteTimeUtc(entry.FullPath),
                                DataStream = source,
                            };
                            await writer.WriteEntryAsync(tarEntry, cancellationToken).ConfigureAwait(false);
                        }

                        break;
                }
            }

            string hex = Convert.ToHexStringLower(digest.GetHashAndReset());
            await using var text = new MemoryStream(Encoding.ASCII.GetBytes(hex));
            await writer.WriteEntryAsync(new PaxTarEntry(TarEntryType.RegularFile, DigestEntryName) { Mode = UnixFileMode.UserRead, DataStream = text }, cancellationToken).ConfigureAwait(false);
        }

        await destination.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Extracts a tree stream into <paramref name="destination"/> and checks it against its digest. Every
    /// name must stay inside the destination and under one of the four top-level members; nothing is
    /// written through a symbolic link.
    /// </summary>
    /// <exception cref="TreeIntegrityException">The stream is damaged, cut short, or names something it may not.</exception>
    public static async Task ExtractAsync(Stream source, string destination, CancellationToken cancellationToken)
    {
        string root = Path.GetFullPath(destination);
        Directory.CreateDirectory(root);
        using IncrementalHash digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var directoryModes = new List<(string Path, UnixFileMode Mode)>();
        bool sealedStream = false;

        try
        {
            using var reader = new TarReader(source, leaveOpen: true);
            while (await reader.GetNextEntryAsync(copyData: false, cancellationToken).ConfigureAwait(false) is { } entry)
            {
                if (sealedStream) throw new TreeIntegrityException("the stream carries entries after its digest");

                string name = entry.Name.TrimEnd('/');
                if (name == DigestEntryName)
                {
                    string expected = await ReadTextAsync(entry, cancellationToken).ConfigureAwait(false);
                    string actual = Convert.ToHexStringLower(digest.GetHashAndReset());
                    if (!string.Equals(expected, actual, StringComparison.Ordinal))
                        throw new TreeIntegrityException("the stream's digest differs from what arrived");
                    sealedStream = true;
                    continue;
                }

                string target = Resolve(root, name);
                switch (entry.EntryType)
                {
                    case TarEntryType.Directory:
                        AppendHeader(digest, TreeEntryKind.Directory, name, 0, null);
                        Directory.CreateDirectory(target);
                        directoryModes.Add((target, entry.Mode));
                        break;
                    case TarEntryType.SymbolicLink:
                        AppendHeader(digest, TreeEntryKind.Symlink, name, 0, entry.LinkName);
                        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                        File.CreateSymbolicLink(target, entry.LinkName);
                        break;
                    case TarEntryType.RegularFile or TarEntryType.V7RegularFile:
                        AppendHeader(digest, TreeEntryKind.File, name, entry.Length, null);
                        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                        await WriteFileAsync(entry, target, digest, cancellationToken).ConfigureAwait(false);
                        break;
                    default:
                        throw new TreeIntegrityException($"'{name}' is a {entry.EntryType} entry, which a tree does not carry");
                }
            }
        }
        catch (Exception ex) when (ex is InvalidDataException or EndOfStreamException or FormatException or IOException or UnauthorizedAccessException)
        {
            throw new TreeIntegrityException($"the tree stream could not be read: {ex.Message}", ex);
        }

        if (!sealedStream) throw new TreeIntegrityException("the tree stream ended before its digest");

        // Whatever follows the archive is drained so the writer on the other end of a pipe is never left blocked.
        await source.CopyToAsync(Stream.Null, cancellationToken).ConfigureAwait(false);

        // A directory is given its mode last: one that is not writable could not have held its own contents.
        if (!OperatingSystem.IsWindows())
        {
            foreach ((string path, UnixFileMode mode) in Enumerable.Reverse(directoryModes))
                File.SetUnixFileMode(path, mode);
        }
    }

    private static async Task WriteFileAsync(TarEntry entry, string target, IncrementalHash digest, CancellationToken cancellationToken)
    {
        if (entry.DataStream is null && entry.Length != 0) throw new TreeIntegrityException($"'{entry.Name}' has no data");

        long written = 0;
        await using (var output = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true))
        {
            byte[] buffer = new byte[81920];
            int read;
            while (entry.DataStream is not null && (read = await entry.DataStream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
            {
                digest.AppendData(buffer, 0, read);
                await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
                written += read;
            }
        }

        if (written != entry.Length) throw new TreeIntegrityException($"'{entry.Name}' is {written} bytes and its header says {entry.Length}");

        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(target, entry.Mode);
        File.SetLastWriteTimeUtc(target, entry.ModificationTime.UtcDateTime);
    }

    private static async Task<string> ReadTextAsync(TarEntry entry, CancellationToken cancellationToken)
    {
        if (entry.DataStream is null) throw new TreeIntegrityException("the digest entry has no data");
        using var reader = new StreamReader(entry.DataStream, Encoding.ASCII, false, 128, leaveOpen: true);
        return (await reader.ReadToEndAsync(cancellationToken).ConfigureAwait(false)).Trim();
    }

    /// <summary>The path an entry lands at, which must lie under the destination, below an allowed member, and behind no symbolic link.</summary>
    private static string Resolve(string root, string name)
    {
        string[] parts = name.Split('/');
        if (name.Length == 0 || name.StartsWith('/') || parts.Any(p => p.Length == 0 || p is "." or ".."))
            throw new TreeIntegrityException($"'{name}' is not a path inside the tree");
        if (parts[0] is not ("instance" or "backups" or "blueprint" or "overrides"))
            throw new TreeIntegrityException($"'{name}' is not under a member a tree carries");

        string path = Path.GetFullPath(Path.Combine(root, name));
        if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            throw new TreeIntegrityException($"'{name}' leaves the tree");

        string current = root;
        foreach (string part in parts[..^1])
        {
            current = Path.Combine(current, part);
            if (new FileInfo(current).LinkTarget is not null) throw new TreeIntegrityException($"'{name}' passes through a symbolic link");
        }

        return path;
    }

    private static void AppendHeader(IncrementalHash digest, TreeEntryKind kind, string name, long length, string? link)
    {
        string header = string.Create(CultureInfo.InvariantCulture, $"{(int)kind}\0{name}\0{length}\0{link}\0");
        digest.AppendData(Encoding.UTF8.GetBytes(header));
    }

    /// <summary>Reads a file and adds what it reads to the digest, so the digest covers exactly the bytes the tar carries.</summary>
    private sealed class DigestReadStream(Stream inner, IncrementalHash digest, long expectedLength) : Stream
    {
        private long _read;

        public override bool CanRead => true;

        public override bool CanSeek => inner.CanSeek;

        public override bool CanWrite => false;

        public override long Length => expectedLength;

        public override long Position
        {
            get => inner.Position;
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count) => Read(buffer.AsSpan(offset, count));

        public override int Read(Span<byte> buffer)
        {
            int count = inner.Read(buffer);
            Account(buffer[..count]);
            return count;
        }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            int count = await inner.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            Account(buffer.Span[..count]);
            return count;
        }

        public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) =>
            ReadAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();

        private void Account(ReadOnlySpan<byte> bytes)
        {
            digest.AppendData(bytes);
            _read += bytes.Length;
        }

        public override void Flush()
        {
        }

        public override long Seek(long offset, SeekOrigin origin) => inner.Seek(offset, origin);

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing) inner.Dispose();
            base.Dispose(disposing);
        }

        public override ValueTask DisposeAsync() => inner.DisposeAsync();
    }
}
