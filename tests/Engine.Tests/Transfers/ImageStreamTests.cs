using System.Security.Cryptography;
using TheKrystalShip.KGSM.Engine.Transfers;

namespace TheKrystalShip.KGSM.Engine.Tests.Transfers;

/// <summary>The trailer that seals an image stream: written after the saved bytes, checked after the load.</summary>
public class ImageStreamTests
{
    internal const int TrailerLength = ImageStream.TrailerLength;

    internal static byte[] TrailerFor(byte[] saved) => ImageStream.Trailer(SHA256.HashData(saved));

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(78)]
    [InlineData(79)]
    [InlineData(80)]
    [InlineData(81_920)]
    [InlineData(81_920 + 79)]
    [InlineData(300_000)]
    public async Task AWrittenStream_ReadsBackWhole_AtAnySizeAndAnyReadSize(int size)
    {
        byte[] payload = new byte[size];
        new Random(size).NextBytes(payload);
        var sealedBytes = new MemoryStream();
        await using (var writer = new ImageStream.Writer(sealedBytes))
        {
            await writer.WriteAsync(payload);
            await writer.CompleteAsync(CancellationToken.None);
        }

        Assert.Equal(size + ImageStream.TrailerLength, sealedBytes.Length);

        foreach (int readSize in new[] { 1, 7, 4096, 1_000_000 })
        {
            using var reader = new ImageStream.Reader(new MemoryStream(sealedBytes.ToArray()));
            var received = new MemoryStream();
            byte[] buffer = new byte[readSize];
            int read;
            while ((read = await reader.ReadAsync(buffer)) > 0) received.Write(buffer, 0, read);

            Assert.Equal(payload, received.ToArray());
            Assert.Null(reader.Problem());
        }
    }

    [Fact]
    public async Task ADamagedByte_ATruncation_AndAMissingTrailer_AreEachReported()
    {
        byte[] payload = new byte[1000];
        new Random(1).NextBytes(payload);
        byte[] whole = [.. payload, .. TrailerFor(payload)];

        byte[] flipped = (byte[])whole.Clone();
        flipped[500] ^= 1;
        Assert.Contains("differs", await ProblemOf(flipped), StringComparison.Ordinal);
        Assert.Contains("differs", await ProblemOf(whole[..^1]), StringComparison.Ordinal);
        Assert.Contains("differs", await ProblemOf(payload), StringComparison.Ordinal);
        Assert.Contains("before its trailer", await ProblemOf(payload[..40]), StringComparison.Ordinal);
        Assert.Contains("before its trailer", await ProblemOf([]), StringComparison.Ordinal);
        Assert.Null(await ProblemOf(whole));
    }

    [Fact]
    public async Task AStreamNotReadToItsEnd_IsNotWhole()
    {
        using var reader = new ImageStream.Reader(new MemoryStream(new byte[500]));
        await reader.ReadAsync(new byte[10]);

        Assert.Contains("not read to its end", reader.Problem(), StringComparison.Ordinal);
    }

    private static async Task<string?> ProblemOf(byte[] bytes)
    {
        using var reader = new ImageStream.Reader(new MemoryStream(bytes));
        await reader.CopyToAsync(Stream.Null);
        return reader.Problem();
    }
}
