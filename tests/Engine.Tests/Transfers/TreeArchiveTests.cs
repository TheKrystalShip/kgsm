using System.Formats.Tar;
using TheKrystalShip.KGSM.Engine.Transfers;

namespace TheKrystalShip.KGSM.Engine.Tests.Transfers;

/// <summary>The tree part as a stream: written, read back, and refused when it was damaged or names what it may not.</summary>
public class TreeArchiveTests : IDisposable
{
    internal const string DigestEntry = ".kgsm-tree-digest";

    private readonly string _root = Path.Combine(Path.GetTempPath(), "kgsm-test-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, recursive: true);
    }

    private string Make(string name)
    {
        string source = Path.Combine(_root, name);
        Directory.CreateDirectory(Path.Combine(source, "sub", "deep"));
        File.WriteAllText(Path.Combine(source, "a.txt"), "alpha");
        File.WriteAllText(Path.Combine(source, "sub", "b.bin"), new string('b', 70_000));
        File.WriteAllText(Path.Combine(source, "sub", "deep", "empty.txt"), string.Empty);
        File.CreateSymbolicLink(Path.Combine(source, "link"), "a.txt");
        File.SetUnixFileMode(Path.Combine(source, "a.txt"), UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        return source;
    }

    private static async Task<byte[]> Write(string source)
    {
        var buffer = new MemoryStream();
        await TreeArchive.WriteAsync(TreeArchive.Enumerate([new TreeMember("instance", source)]), buffer, CancellationToken.None);
        return buffer.ToArray();
    }

    [Fact]
    public async Task ARoundTrip_RestoresFilesSymlinksModesAndEmptyFiles()
    {
        string source = Make("src");
        byte[] bytes = await Write(source);
        string target = Path.Combine(_root, "out");

        await TreeArchive.ExtractAsync(new MemoryStream(bytes), target, CancellationToken.None);

        string restored = Path.Combine(target, "instance");
        Assert.Equal("alpha", File.ReadAllText(Path.Combine(restored, "a.txt")));
        Assert.Equal(70_000, new FileInfo(Path.Combine(restored, "sub", "b.bin")).Length);
        Assert.Equal(0, new FileInfo(Path.Combine(restored, "sub", "deep", "empty.txt")).Length);
        Assert.Equal("a.txt", new FileInfo(Path.Combine(restored, "link")).LinkTarget);
        Assert.True(File.GetUnixFileMode(Path.Combine(restored, "a.txt")).HasFlag(UnixFileMode.UserExecute));
        Assert.Equal(TreeArchive.Measure([new TreeMember("instance", source)]), TreeArchive.Measure([new TreeMember("instance", restored)]));
    }

    [Fact]
    public async Task Measure_CountsFilesAndSymlinksNotDirectories_AndSumsRegularFileBytes()
    {
        string source = Make("src");

        (long bytes, long files) = TreeArchive.Measure([new TreeMember("instance", source)]);

        Assert.Equal(5 + 70_000 + 0, bytes);
        Assert.Equal(4, files);
        await Task.CompletedTask;
    }

    [Fact]
    public void Enumerate_LeavesOutPipesAndTheExcludedNames()
    {
        string source = Make("src");
        File.WriteAllText(Path.Combine(source, ".skip.pid"), "1");
        Assert.Equal(0, MakeFifo(Path.Combine(source, ".input.sock")));

        string[] names = [.. TreeArchive.Enumerate([new TreeMember("instance", source, new HashSet<string> { ".skip.pid" })]).Select(e => e.Name)];

        Assert.DoesNotContain("instance/.skip.pid", names);
        Assert.DoesNotContain("instance/.input.sock", names);
        Assert.Contains("instance/a.txt", names);
    }

    [Fact]
    public async Task AFlippedByteOfContent_IsCaughtByTheDigest_WhichATarAloneWouldNotNotice()
    {
        byte[] bytes = await Write(Make("src"));
        int at = IndexOf(bytes, "alpha"u8.ToArray());
        bytes[at] ^= 0x01;

        TreeIntegrityException ex = await Assert.ThrowsAsync<TreeIntegrityException>(
            () => TreeArchive.ExtractAsync(new MemoryStream(bytes), Path.Combine(_root, "out"), CancellationToken.None));

        Assert.Contains("digest", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AFlippedByteOfAName_IsCaughtByTheDigest_BecauseTheDotNetTarReaderChecksNoHeaderChecksum()
    {
        byte[] bytes = await Write(Make("src"));
        int at = IndexOf(bytes, "instance/a.txt"u8.ToArray()) + "instance/a.tx".Length;
        bytes[at] ^= 0x01;

        TreeIntegrityException ex = await Assert.ThrowsAsync<TreeIntegrityException>(
            () => TreeArchive.ExtractAsync(new MemoryStream(bytes), Path.Combine(_root, "out"), CancellationToken.None));

        Assert.Contains("digest", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AStreamCutShort_IsRefused_WhereverItWasCut()
    {
        byte[] bytes = await Write(Make("src"));

        foreach (int length in new[] { 0, 100, 700, bytes.Length / 2, bytes.Length - 1200, bytes.Length - 1024 - 10 })
        {
            await Assert.ThrowsAsync<TreeIntegrityException>(
                () => TreeArchive.ExtractAsync(new MemoryStream(bytes[..length]), Path.Combine(_root, "out" + length), CancellationToken.None));
        }
    }

    [Fact]
    public async Task AnEntryThatLeavesTheTree_OrIsNotUnderAMember_OrPassesThroughALink_IsRefused()
    {
        foreach (string name in new[] { "instance/../escape", "/etc/passwd", "other/file", "instance//x", "instance/./x" })
        {
            byte[] bytes = await Crafted(writer => writer.WriteEntry(Entry(name, "x")));
            await Assert.ThrowsAsync<TreeIntegrityException>(
                () => TreeArchive.ExtractAsync(new MemoryStream(bytes), Path.Combine(_root, "evil"), CancellationToken.None));
        }

        Assert.False(File.Exists(Path.Combine(_root, "escape")));

        byte[] linked = await Crafted(writer =>
        {
            writer.WriteEntry(new PaxTarEntry(TarEntryType.SymbolicLink, "instance/out") { LinkName = _root });
            writer.WriteEntry(Entry("instance/out/planted", "x"));
        });
        await Assert.ThrowsAsync<TreeIntegrityException>(
            () => TreeArchive.ExtractAsync(new MemoryStream(linked), Path.Combine(_root, "evil2"), CancellationToken.None));
        Assert.False(File.Exists(Path.Combine(_root, "planted")));
    }

    [Fact]
    public async Task AStreamWithoutItsDigest_IsRefused()
    {
        byte[] bytes = await Crafted(writer => writer.WriteEntry(Entry("instance/a", "x")), digest: false);

        TreeIntegrityException ex = await Assert.ThrowsAsync<TreeIntegrityException>(
            () => TreeArchive.ExtractAsync(new MemoryStream(bytes), Path.Combine(_root, "out"), CancellationToken.None));

        Assert.Contains("digest", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnEntryTypeATreeDoesNotCarry_IsRefused()
    {
        byte[] bytes = await Crafted(writer => writer.WriteEntry(new PaxTarEntry(TarEntryType.HardLink, "instance/h") { LinkName = "instance/a" }));

        await Assert.ThrowsAsync<TreeIntegrityException>(
            () => TreeArchive.ExtractAsync(new MemoryStream(bytes), Path.Combine(_root, "out"), CancellationToken.None));
    }

    private static PaxTarEntry Entry(string name, string content) =>
        new(TarEntryType.RegularFile, name) { DataStream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(content)) };

    /// <summary>A tar written by hand, closed by a digest entry that does not match, as a damaged writer would.</summary>
    private static async Task<byte[]> Crafted(Action<TarWriter> entries, bool digest = true)
    {
        var buffer = new MemoryStream();
        await using (var writer = new TarWriter(buffer, TarEntryFormat.Pax, leaveOpen: true))
        {
            entries(writer);
            if (digest) writer.WriteEntry(Entry(DigestEntry, "0000"));
        }

        return buffer.ToArray();
    }

    private static int IndexOf(byte[] haystack, byte[] needle)
    {
        for (int i = 0; i <= haystack.Length - needle.Length; i++)
        {
            if (haystack.AsSpan(i, needle.Length).SequenceEqual(needle)) return i;
        }

        throw new InvalidOperationException("not found");
    }

    [System.Runtime.InteropServices.DllImport("libc", EntryPoint = "mkfifo", SetLastError = true)]
    private static extern int Mkfifo([System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPStr)] string path, uint mode);

    private static int MakeFifo(string path) => Mkfifo(path, 0x1A4);
}
