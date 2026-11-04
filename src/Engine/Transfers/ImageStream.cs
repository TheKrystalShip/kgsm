using System.Security.Cryptography;
using System.Text;

namespace TheKrystalShip.KGSM.Engine.Transfers;

/// <summary>
/// An image part is what the container runtime saves, followed by a trailer holding the SHA-256 of every byte
/// before it. A runtime verifies less than it seems to when it loads: a damaged byte inside a layer can load
/// without complaint, so the target checks the stream itself, as it checks the tree.
/// </summary>
internal static class ImageStream
{
    private const string Prefix = "\n#kgsm-sha256:";

    /// <summary>The trailer's length: the prefix, 64 hex digits and a newline.</summary>
    public const int TrailerLength = 14 + 64 + 1;

    public static byte[] Trailer(byte[] digest) => Encoding.ASCII.GetBytes(Prefix + Convert.ToHexStringLower(digest) + "\n");

    /// <summary>Passes everything written through to <paramref name="inner"/> and hashes it.</summary>
    public sealed class Writer(Stream inner) : Stream
    {
        private readonly IncrementalHash _hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);

        public override bool CanRead => false;

        public override bool CanSeek => false;

        public override bool CanWrite => true;

        public override long Length => throw new NotSupportedException();

        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        /// <summary>Writes the trailer, which closes the stream.</summary>
        public async Task CompleteAsync(CancellationToken cancellationToken)
        {
            await inner.WriteAsync(Trailer(_hash.GetHashAndReset()), cancellationToken).ConfigureAwait(false);
            await inner.FlushAsync(cancellationToken).ConfigureAwait(false);
        }

        public override async ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken cancellationToken = default)
        {
            _hash.AppendData(buffer.Span);
            await inner.WriteAsync(buffer, cancellationToken).ConfigureAwait(false);
        }

        public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) =>
            WriteAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();

        public override void Write(byte[] buffer, int offset, int count)
        {
            _hash.AppendData(buffer, offset, count);
            inner.Write(buffer, offset, count);
        }

        public override void Flush() => inner.Flush();

        public override Task FlushAsync(CancellationToken cancellationToken) => inner.FlushAsync(cancellationToken);

        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing) _hash.Dispose();
            base.Dispose(disposing);
        }
    }

    /// <summary>
    /// Reads a stream that ends in a trailer: it hands on every byte but the last <see cref="TrailerLength"/>,
    /// hashes what it hands on, and after the end says whether the trailer matched.
    /// </summary>
    public sealed class Reader(Stream inner) : Stream
    {
        private const int Chunk = 81920;

        private readonly IncrementalHash _hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        private readonly byte[] _buffer = new byte[Chunk + TrailerLength];
        private int _start;
        private int _end;
        private bool _ended;

        public override bool CanRead => true;

        public override bool CanSeek => false;

        public override bool CanWrite => false;

        public override long Length => throw new NotSupportedException();

        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        /// <summary>Why the stream is not whole, or null when it ended in a trailer that matches what was read. Call after reading to the end.</summary>
        public string? Problem()
        {
            if (!_ended) return "the stream was not read to its end";
            if (_end - _start != TrailerLength) return "the stream ended before its trailer";

            string expected = Encoding.ASCII.GetString(Trailer(_hash.GetHashAndReset()));
            string actual = Encoding.ASCII.GetString(_buffer, _start, TrailerLength);
            return string.Equals(expected, actual, StringComparison.Ordinal) ? null : "the stream's digest differs from what arrived";
        }

        public override async ValueTask<int> ReadAsync(Memory<byte> destination, CancellationToken cancellationToken = default)
        {
            while (true)
            {
                int releasable = _end - _start - TrailerLength;
                if (releasable > 0)
                {
                    int count = Math.Min(releasable, destination.Length);
                    _buffer.AsSpan(_start, count).CopyTo(destination.Span);
                    _hash.AppendData(_buffer.AsSpan(_start, count));
                    _start += count;
                    return count;
                }

                if (_ended) return 0;

                if (_start > 0)
                {
                    Buffer.BlockCopy(_buffer, _start, _buffer, 0, _end - _start);
                    _end -= _start;
                    _start = 0;
                }

                int read = await inner.ReadAsync(_buffer.AsMemory(_end), cancellationToken).ConfigureAwait(false);
                if (read == 0) _ended = true;
                else _end += read;
            }
        }

        public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) =>
            ReadAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();

        public override int Read(byte[] buffer, int offset, int count) =>
            ReadAsync(buffer.AsMemory(offset, count), CancellationToken.None).AsTask().GetAwaiter().GetResult();

        public override void Flush()
        {
        }

        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing) _hash.Dispose();
            base.Dispose(disposing);
        }
    }
}
