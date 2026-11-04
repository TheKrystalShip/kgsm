using System.Text;
using System.Text.RegularExpressions;

namespace TheKrystalShip.KGSM.Engine.Transfers;

/// <summary>
/// The <c>name:</c> of a blueprint file is what its per-game hooks bind to, so a travelling copy that
/// is installed under another name must carry that name. These rewrite the top-level <c>name:</c> line
/// of a blueprint's text, whatever its quoting, and leave every other byte as it is.
/// </summary>
internal static partial class BlueprintNames
{
    /// <summary>A suffix label: lowercase letters, digits, dots, underscores and hyphens, starting with a letter or digit.</summary>
    public static bool IsValidSuffix(string suffix) => SuffixPattern().IsMatch(suffix);

    /// <summary>Appends <c>-suffix</c> to the name.</summary>
    public static string AddSuffix(string text, string suffix) => Rewrite(text, name => name + "-" + suffix);

    /// <summary>Removes <c>-suffix</c> from the name when it ends with it.</summary>
    public static string StripSuffix(string text, string suffix) =>
        Rewrite(text, name => name.EndsWith("-" + suffix, StringComparison.Ordinal) ? name[..^(suffix.Length + 1)] : name);

    /// <summary>The top-level <c>name:</c> value, or null when the text has none.</summary>
    public static string? NameOf(string text)
    {
        Match match = NameLine().Match(text);
        return match.Success ? match.Groups["value"].Value : null;
    }

    private static string Rewrite(string text, Func<string, string> change)
    {
        Match match = NameLine().Match(text);
        if (!match.Success) return text;

        string quote = match.Groups["quote"].Value;
        string renamed = change(match.Groups["value"].Value);
        var line = new StringBuilder("name: ").Append(quote).Append(renamed).Append(quote).Append(match.Groups["rest"].Value);
        return text[..match.Index] + line + text[(match.Index + match.Length)..];
    }

    [GeneratedRegex("^name:[ \t]*(?:(?<quote>[\"'])(?<value>[^\"'\r\n]*)\\k<quote>|(?<value>[^ \t#\r\n]+))(?<rest>[^\r\n]*)", RegexOptions.Multiline)]
    private static partial Regex NameLine();

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]*$")]
    private static partial Regex SuffixPattern();
}
