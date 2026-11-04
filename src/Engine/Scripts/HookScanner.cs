using System.Text;
using System.Text.RegularExpressions;

namespace TheKrystalShip.KGSM.Engine.Scripts;

/// <summary>
/// A structural scan of a hooks file that never sources or runs it. Outside a function definition a hooks
/// file may hold comments and blank lines only (a shebang is a comment); anything else would run each time
/// the script loads. The scan follows quoting, comments, <c>${...}</c> and here-documents closely enough to
/// find where each function body ends.
/// </summary>
public static partial class HookScanner
{
    /// <summary>The problems found, each naming its line; empty when the file holds only comments, blanks and function definitions.</summary>
    public static IReadOnlyList<string> Scan(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        var problems = new List<string>();
        int position = 0;

        while (true)
        {
            position = SkipBlankAndComments(text, position);
            if (position >= text.Length) break;

            Match header = HeaderPattern().Match(text, position);
            if (!header.Success || header.Index != position)
            {
                problems.Add($"line {LineOf(text, position)}: outside a function there may be only comments and blank lines");
                break;
            }

            int end = FindBodyEnd(text, header.Index + header.Length);
            if (end < 0)
            {
                problems.Add($"line {LineOf(text, position)}: the function never closes");
                break;
            }

            position = end;
            int lineEnd = text.IndexOf('\n', position);
            string rest = text[position..(lineEnd < 0 ? text.Length : lineEnd)].Trim();
            if (rest.Length > 0 && rest[0] != '#')
            {
                problems.Add($"line {LineOf(text, position)}: text follows a function's closing brace");
                break;
            }
        }

        return problems;
    }

    private static int SkipBlankAndComments(string text, int position)
    {
        while (position < text.Length)
        {
            char c = text[position];
            if (char.IsWhiteSpace(c))
            {
                position++;
            }
            else if (c == '#')
            {
                int lineEnd = text.IndexOf('\n', position);
                position = lineEnd < 0 ? text.Length : lineEnd + 1;
            }
            else
            {
                break;
            }
        }

        return position;
    }

    /// <summary>The index just after the brace that closes a body opened before <paramref name="start"/>, or -1.</summary>
    private static int FindBodyEnd(string text, int start)
    {
        int depth = 1;
        int i = start;
        var pending = new List<(string Tag, bool StripTabs)>();

        while (i < text.Length)
        {
            char c = text[i];

            if (c == '\n')
            {
                i++;
                foreach ((string tag, bool stripTabs) in pending) i = SkipHereDocument(text, i, tag, stripTabs);
                pending.Clear();
                continue;
            }

            if (c == '\\')
            {
                i += 2;
                continue;
            }

            if (c == '\'')
            {
                int close = text.IndexOf('\'', i + 1);
                if (close < 0) return -1;
                i = close + 1;
                continue;
            }

            if (c == '"')
            {
                i++;
                while (i < text.Length && text[i] != '"') i += text[i] == '\\' ? 2 : 1;
                i++;
                continue;
            }

            if (c == '#' && IsWordStart(text, i))
            {
                int lineEnd = text.IndexOf('\n', i);
                i = lineEnd < 0 ? text.Length : lineEnd;
                continue;
            }

            if (c == '$' && i + 1 < text.Length && text[i + 1] == '{')
            {
                i = SkipParameterExpansion(text, i + 2);
                continue;
            }

            if (c == '<' && i + 1 < text.Length && text[i + 1] == '<' && !(i + 2 < text.Length && text[i + 2] == '<'))
            {
                Match here = HereDocumentPattern().Match(text, i);
                if (here.Success && here.Index == i)
                {
                    pending.Add((here.Groups["tag"].Value, here.Groups["dash"].Success));
                    i += here.Length;
                    continue;
                }
            }

            if (c == '{' && IsWordStart(text, i) && IsWordEnd(text, i + 1))
            {
                depth++;
            }
            else if (c == '}' && IsWordStart(text, i) && IsWordEnd(text, i + 1))
            {
                depth--;
                if (depth == 0) return i + 1;
            }

            i++;
        }

        return -1;
    }

    private static int SkipHereDocument(string text, int position, string tag, bool stripTabs)
    {
        while (position < text.Length)
        {
            int lineEnd = text.IndexOf('\n', position);
            string line = text[position..(lineEnd < 0 ? text.Length : lineEnd)];
            position = lineEnd < 0 ? text.Length : lineEnd + 1;
            if ((stripTabs ? line.TrimStart('\t') : line) == tag) break;
        }

        return position;
    }

    private static int SkipParameterExpansion(string text, int position)
    {
        int depth = 1;
        while (position < text.Length && depth > 0)
        {
            char c = text[position];
            if (c == '\\') position++;
            else if (c == '{') depth++;
            else if (c == '}') depth--;
            position++;
        }

        return position;
    }

    private static bool IsWordStart(string text, int i) => i == 0 || char.IsWhiteSpace(text[i - 1]) || text[i - 1] is ';' or '(' or '&' or '|';

    private static bool IsWordEnd(string text, int i) => i >= text.Length || char.IsWhiteSpace(text[i]) || text[i] is ';' or ')' or '&' or '|';

    private static int LineOf(string text, int position)
    {
        var line = 1;
        for (int i = 0; i < position && i < text.Length; i++)
        {
            if (text[i] == '\n') line++;
        }

        return line;
    }

    [GeneratedRegex(@"(?:function\s+[^\s(){};&|<>=#]+(?:\s*\(\s*\))?|[^\s(){};&|<>=#]+\s*\(\s*\))\s*\{")]
    private static partial Regex HeaderPattern();

    [GeneratedRegex(@"<<(?<dash>-)?\s*(?:'(?<tag>[^']+)'|""(?<tag>[^""]+)""|(?<tag>[A-Za-z_][A-Za-z0-9_]*))")]
    private static partial Regex HereDocumentPattern();
}
