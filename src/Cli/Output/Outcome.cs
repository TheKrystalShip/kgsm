using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;

namespace TheKrystalShip.KGSM.Cli.Output;

/// <summary>How a command's result is rendered.</summary>
internal enum OutputFormat
{
    Text,
    Json,
}

/// <summary>
/// What a command returns. A command never writes: it returns an outcome and the output stage renders it,
/// as text for a person or as JSON through the source-generated context, with the exit code the outcome
/// carries.
/// </summary>
internal abstract class Outcome
{
    public abstract int ExitCode { get; }

    /// <summary>Writes the outcome: a result to stdout, a failure to stderr, and nothing else.</summary>
    public abstract void Write(OutputFormat format, TextWriter stdout, TextWriter stderr);
}

/// <summary>A result: a registered DTO and the text that shows it. The exit code is zero unless the result itself is a verdict, as validation's is.</summary>
internal sealed class Result<T>(T value, JsonTypeInfo<T> typeInfo, Func<T, string> text, int exitCode = ExitCodes.Success) : Outcome
{
    public override int ExitCode => exitCode;

    public override void Write(OutputFormat format, TextWriter stdout, TextWriter stderr)
    {
        string rendered = format == OutputFormat.Json ? JsonSerializer.Serialize(value, typeInfo) : text(value);
        stdout.WriteLine(rendered.TrimEnd('\n'));
    }
}

/// <summary>A failure: an error report on stderr, as JSON under <c>--json</c>, with stdout left empty.</summary>
internal sealed class Failure(ErrorReport report) : Outcome
{
    public ErrorReport Report => report;

    public override int ExitCode => report.ExitCode;

    public override void Write(OutputFormat format, TextWriter stdout, TextWriter stderr)
    {
        if (format == OutputFormat.Json)
        {
            stderr.WriteLine(JsonSerializer.Serialize(report, Engine.Contracts.EngineJsonContext.Default.ErrorReport));
            return;
        }

        stderr.WriteLine($"error: {report.Message}");
        foreach (string detail in report.Details) stderr.WriteLine($"  {detail}");
    }

    public static Failure Of(string code, string message, int exitCode = ExitCodes.Failure, IReadOnlyList<string>? details = null) =>
        new(new ErrorReport { Code = code, Message = message, ExitCode = exitCode, Details = details ?? [] });

    public static Failure NotFound(string message) => Of(ErrorCodes.NotFound, message, ExitCodes.NotFound);

    public static Failure Usage(string message) => Of(ErrorCodes.Usage, message, ExitCodes.Usage);
}

/// <summary>Plain-text tables for the text rendering.</summary>
internal static class Table
{
    public static string Render(string[] headers, IEnumerable<string[]> rows)
    {
        List<string[]> all = [headers, .. rows];
        int[] widths = new int[headers.Length];
        foreach (string[] row in all)
        {
            for (int column = 0; column < headers.Length; column++)
                widths[column] = Math.Max(widths[column], row[column].Length);
        }

        return string.Join('\n', all.Select(row =>
            string.Join("  ", row.Select((cell, column) => column == row.Length - 1 ? cell : cell.PadRight(widths[column]))).TrimEnd()));
    }

    /// <summary>Aligned <c>label: value</c> lines.</summary>
    public static string Fields(IEnumerable<(string Label, string Value)> fields)
    {
        (string Label, string Value)[] list = [.. fields];
        int width = list.Max(f => f.Label.Length);
        return string.Join('\n', list.Select(f => $"{f.Label.PadRight(width)}  {f.Value}"));
    }
}
