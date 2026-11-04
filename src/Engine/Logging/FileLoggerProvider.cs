using System.Globalization;
using System.Text;
using Microsoft.Extensions.Logging;

namespace TheKrystalShip.KGSM.Engine.Logging;

/// <summary>Where the engine's log goes and when it rotates.</summary>
public sealed record FileLoggerOptions
{
    /// <summary>The current log file; rotated files are named <c>&lt;file&gt;.1</c> (newest) upward.</summary>
    public required string Path { get; init; }

    /// <summary>Size at which the current file rotates.</summary>
    public required long MaxSizeBytes { get; init; }

    /// <summary>Rotated files kept beside the current one. Zero keeps none.</summary>
    public required int MaxFiles { get; init; }
}

/// <summary>
/// The engine's file logger: the simple console formatter's line format, written to a file that rotates by
/// size and keeps a bounded number of rotated files. Logging never writes to the terminal and has no off
/// switch, and a failure to write is swallowed because a log must not break the command it records.
/// </summary>
/// <remarks>
/// Each entry is one append, so several kgsm processes can share the file; a rotation that loses a race to
/// another process is skipped. The line is the simple console format with a leading UTC timestamp:
/// <c>2026-11-04T10:15:30.123Z info: Category[0]</c>, then the message on following lines indented six
/// spaces, then any exception.
/// </remarks>
public sealed class FileLoggerProvider : ILoggerProvider
{
    private const string MessagePadding = "      ";
    private const string TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fff'Z'";

    private readonly FileLoggerOptions _options;
    private readonly TimeProvider _clock;
    private readonly Lock _gate = new();

    public FileLoggerProvider(FileLoggerOptions options, TimeProvider? clock = null)
    {
        ArgumentNullException.ThrowIfNull(options);
        _options = options;
        _clock = clock ?? TimeProvider.System;
    }

    public ILogger CreateLogger(string categoryName) => new FileLogger(categoryName, this);

    public void Dispose()
    {
    }

    internal void Write(LogLevel level, string category, EventId eventId, string message, Exception? exception)
    {
        string text = Format(_clock.GetUtcNow(), level, category, eventId, message, exception);

        lock (_gate)
        {
            try
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(_options.Path)!);
                RotateIfFull();
                using var stream = new FileStream(
                    _options.Path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete,
                    bufferSize: 0, useAsync: false);
                byte[] bytes = Encoding.UTF8.GetBytes(text);
                stream.Write(bytes, 0, bytes.Length);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException)
            {
                // A log that cannot be written is not worth failing the command it describes.
            }
        }
    }

    internal static string Format(
        DateTimeOffset now, LogLevel level, string category, EventId eventId, string message, Exception? exception)
    {
        var line = new StringBuilder();
        line.Append(now.UtcDateTime.ToString(TimestampFormat, CultureInfo.InvariantCulture)).Append(' ')
            .Append(LevelTag(level)).Append(": ").Append(category)
            .Append('[').Append(eventId.Id.ToString(CultureInfo.InvariantCulture)).Append(']')
            .Append('\n');

        AppendIndented(line, message);
        if (exception is not null) AppendIndented(line, exception.ToString());

        return line.ToString();
    }

    private static void AppendIndented(StringBuilder line, string text)
    {
        if (text.Length == 0) return;

        line.Append(MessagePadding)
            .Append(text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace("\n", "\n" + MessagePadding, StringComparison.Ordinal))
            .Append('\n');
    }

    private static string LevelTag(LogLevel level) => level switch
    {
        LogLevel.Trace => "trce",
        LogLevel.Debug => "dbug",
        LogLevel.Information => "info",
        LogLevel.Warning => "warn",
        LogLevel.Error => "fail",
        LogLevel.Critical => "crit",
        _ => "none",
    };

    private void RotateIfFull()
    {
        var current = new FileInfo(_options.Path);
        if (!current.Exists || current.Length < _options.MaxSizeBytes) return;

        string path = _options.Path;

        // Rotated files past the bound go first, whatever bound an earlier run kept.
        foreach (string stale in Directory.EnumerateFiles(System.IO.Path.GetDirectoryName(path)!, System.IO.Path.GetFileName(path) + ".*"))
        {
            if (RotationIndex(stale, path) is { } index && index >= Math.Max(_options.MaxFiles, 1))
                TryDelete(stale);
        }

        if (_options.MaxFiles == 0)
        {
            TryDelete(path);
            return;
        }

        for (int i = _options.MaxFiles - 1; i >= 1; i--)
            TryMove($"{path}.{i.ToString(CultureInfo.InvariantCulture)}", $"{path}.{(i + 1).ToString(CultureInfo.InvariantCulture)}");

        TryMove(path, path + ".1");
    }

    private static int? RotationIndex(string candidate, string basePath)
    {
        if (candidate.Length <= basePath.Length + 1 || !candidate.StartsWith(basePath + ".", StringComparison.Ordinal))
            return null;

        string suffix = candidate[(basePath.Length + 1)..];
        return int.TryParse(suffix, NumberStyles.None, CultureInfo.InvariantCulture, out int index) ? index : null;
    }

    private static void TryMove(string from, string to)
    {
        try
        {
            if (File.Exists(from)) File.Move(from, to, overwrite: true);
        }
        catch (IOException)
        {
            // Another process rotated first.
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
            // Another process removed it first.
        }
    }

    private sealed class FileLogger(string category, FileLoggerProvider provider) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => logLevel != LogLevel.None;

        public void Log<TState>(
            LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel)) return;
            provider.Write(logLevel, category, eventId, formatter(state, exception), exception);
        }
    }
}
