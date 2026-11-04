using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace TheKrystalShip.KGSM.Engine.Scripts;

/// <summary>
/// The management-script template the binary carries: one text for both runtimes. Lines between
/// <c>#@if native</c> or <c>#@if container</c> and <c>#@end</c> belong to one runtime, the <c>#@hooks</c>
/// line is where a game's hooks are inlined, and <c>@@NAME@@</c> tokens are replaced at generation.
/// </summary>
public static partial class ScriptTemplate
{
    /// <summary>
    /// The version a generated script records. It changes whenever the template's text does; a script
    /// whose recorded version differs is stale and <c>instance repair</c> regenerates it.
    /// </summary>
    public const int Version = 1;

    private const string ResourceName = "management-script.tpl";

    /// <summary>The template's text as embedded.</summary>
    public static string Text { get; } = Load();

    /// <summary>
    /// Renders the template for a runtime: the other runtime's blocks are dropped, the tokens replaced
    /// and the hooks text placed at the <c>#@hooks</c> line.
    /// </summary>
    /// <param name="native">Whether to render the native runtime; otherwise the container runtime.</param>
    /// <param name="tokens">The <c>@@NAME@@</c> values, keyed by NAME.</param>
    /// <param name="hooks">The hooks text, or null for none.</param>
    public static string Render(bool native, IReadOnlyDictionary<string, string> tokens, string? hooks) =>
        Render(Text, native, tokens, hooks);

    /// <summary>As <see cref="Render(bool, IReadOnlyDictionary{string, string}, string?)"/>, for a template text of the caller's.</summary>
    public static string Render(string template, bool native, IReadOnlyDictionary<string, string> tokens, string? hooks)
    {
        var output = new StringBuilder(template.Length);
        string? block = null;
        string wanted = native ? "native" : "container";

        string[] lines = template.Split('\n');
        int count = lines.Length > 0 && lines[^1].Length == 0 ? lines.Length - 1 : lines.Length;

        foreach (string line in lines.Take(count))
        {
            string trimmed = line.TrimEnd('\r');

            if (trimmed.StartsWith("#@if ", StringComparison.Ordinal))
            {
                if (block is not null) throw new InvalidOperationException("The script template nests a runtime block.");
                block = trimmed["#@if ".Length..].Trim();
                continue;
            }

            if (trimmed == "#@end")
            {
                if (block is null) throw new InvalidOperationException("The script template closes a block it never opened.");
                block = null;
                continue;
            }

            if (block is not null && block != wanted) continue;

            if (trimmed == "#@hooks")
            {
                if (!string.IsNullOrEmpty(hooks))
                {
                    output.Append("# The game's hooks, inlined at generation.\n");
                    output.Append(hooks.TrimEnd('\n')).Append('\n');
                }

                continue;
            }

            output.Append(Replace(trimmed, tokens)).Append('\n');
        }

        if (block is not null) throw new InvalidOperationException("The script template leaves a runtime block open.");

        return output.ToString();
    }

    private static string Replace(string line, IReadOnlyDictionary<string, string> tokens)
    {
        if (!line.Contains("@@", StringComparison.Ordinal)) return line;

        return TokenPattern().Replace(line, match =>
            tokens.TryGetValue(match.Groups["name"].Value, out string? value)
                ? value
                : throw new InvalidOperationException($"The script template names the token @@{match.Groups["name"].Value}@@, which has no value."));
    }

    private static string Load()
    {
        using Stream stream = typeof(ScriptTemplate).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException($"The engine carries no embedded resource '{ResourceName}'.");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }

    [GeneratedRegex("@@(?<name>[A-Z_]+)@@")]
    private static partial Regex TokenPattern();
}
