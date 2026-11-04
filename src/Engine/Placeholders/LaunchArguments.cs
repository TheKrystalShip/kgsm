using System.Text;
using System.Text.RegularExpressions;

namespace TheKrystalShip.KGSM.Engine.Placeholders;

/// <summary>A template names a key that has no value, or is not well formed.</summary>
public sealed class PlaceholderException(string message) : EngineException("placeholder", message);

/// <summary>
/// Launch-argument placeholders. A template is split on whitespace (space, tab, line feed, carriage
/// return, vertical tab and form feed) first, then each <c>{key}</c> is
/// replaced inside its own argument, so a value with spaces stays one argument and nothing in a value is
/// shell syntax. <c>{{</c> and <c>}}</c> are literal braces and every other character is literal. A key with
/// no value fails, and so does a brace that opens or closes nothing. There is no quoting syntax, no
/// <c>envsubst</c> and no command-substitution guard to bypass.
/// </summary>
/// <remarks>
/// The engine core and the generated management script are the two resolvers of this grammar; the suite
/// checks both against the same cases.
/// </remarks>
public static partial class LaunchArguments
{
    /// <summary>A key is a camelCase name: a lowercase letter, then letters and digits.</summary>
    public static bool IsValidKey(string key) => KeyPattern().IsMatch(key);

    /// <summary>
    /// Resolves a template to the argument list it stands for.
    /// </summary>
    /// <exception cref="PlaceholderException">A key has no value, or a brace is unmatched.</exception>
    public static IReadOnlyList<string> Resolve(string template, IReadOnlyDictionary<string, string> values)
    {
        ArgumentNullException.ThrowIfNull(template);
        ArgumentNullException.ThrowIfNull(values);

        return Tokens(template).Select(token => Substitute(token, values)).ToList();
    }

    /// <summary>As <see cref="Resolve"/>, returning the failure as text.</summary>
    public static bool TryResolve(
        string template, IReadOnlyDictionary<string, string> values, out IReadOnlyList<string> arguments, out string? error)
    {
        try
        {
            arguments = Resolve(template, values);
            error = null;
            return true;
        }
        catch (PlaceholderException ex)
        {
            arguments = [];
            error = ex.Message;
            return false;
        }
    }

    /// <summary>The keys a template names, in order of first use, without resolving any.</summary>
    /// <exception cref="PlaceholderException">A brace is unmatched.</exception>
    public static IReadOnlyList<string> Keys(string template)
    {
        var keys = new List<string>();
        foreach (string token in Tokens(template))
            Walk(token, key => { if (!keys.Contains(key)) keys.Add(key); return string.Empty; });
        return keys;
    }

    /// <summary>
    /// Rewrites a blueprint's <c>executable_arguments</c> into the template the instance config stores:
    /// <c>$instance_level_name</c> and <c>${instance_level_name}</c> become <c>{levelName}</c>, and a literal
    /// brace becomes <c>{{</c> or <c>}}</c>. Every other character, a <c>$</c> included, stays literal.
    /// </summary>
    /// <exception cref="PlaceholderException">A reference names a key outside <paramref name="knownKeys"/>.</exception>
    public static string FromBlueprint(string blueprintArguments, IReadOnlySet<string> knownKeys)
    {
        ArgumentNullException.ThrowIfNull(blueprintArguments);
        ArgumentNullException.ThrowIfNull(knownKeys);

        var result = new StringBuilder(blueprintArguments.Length);
        int position = 0;

        foreach (Match reference in InstanceReferencePattern().Matches(blueprintArguments))
        {
            result.Append(EscapeBraces(blueprintArguments[position..reference.Index]));

            string snake = reference.Groups["braced"].Success ? reference.Groups["braced"].Value : reference.Groups["bare"].Value;
            string key = SnakeToCamel(snake);
            if (!knownKeys.Contains(key))
                throw new PlaceholderException($"the launch arguments name '$instance_{snake}', which is not an instance value");

            result.Append('{').Append(key).Append('}');
            position = reference.Index + reference.Length;
        }

        result.Append(EscapeBraces(blueprintArguments[position..]));
        return result.ToString();
    }

    /// <summary><c>level_name</c> to <c>levelName</c>.</summary>
    public static string SnakeToCamel(string snake)
    {
        string[] parts = snake.Split('_', StringSplitOptions.RemoveEmptyEntries);
        var camel = new StringBuilder(snake.Length);
        for (int i = 0; i < parts.Length; i++)
            camel.Append(i == 0 ? parts[i] : char.ToUpperInvariant(parts[i][0]) + parts[i][1..]);
        return camel.ToString();
    }

    private static string EscapeBraces(string text) =>
        text.Replace("{", "{{", StringComparison.Ordinal).Replace("}", "}}", StringComparison.Ordinal);

    /// <summary>The characters that separate arguments: space, tab, line feed, carriage return, vertical tab and form feed.</summary>
    private static readonly char[] Whitespace = [' ', '\t', '\n', '\r', '\v', '\f'];

    private static IEnumerable<string> Tokens(string template) =>
        template.Split(Whitespace, StringSplitOptions.RemoveEmptyEntries);

    private static string Substitute(string token, IReadOnlyDictionary<string, string> values) =>
        Walk(token, key => values.TryGetValue(key, out string? value)
            ? value
            : throw new PlaceholderException($"the launch arguments name '{{{key}}}', which has no value"));

    private static string Walk(string token, Func<string, string> valueOf)
    {
        var output = new StringBuilder(token.Length);

        for (int i = 0; i < token.Length; i++)
        {
            char c = token[i];

            if (c == '{')
            {
                if (i + 1 < token.Length && token[i + 1] == '{')
                {
                    output.Append('{');
                    i++;
                    continue;
                }

                int close = token.IndexOf('}', i + 1);
                if (close < 0)
                    throw new PlaceholderException($"'{{' in '{token}' opens a placeholder that never closes; write '{{{{' for a literal brace");

                string key = token[(i + 1)..close];
                if (!IsValidKey(key))
                    throw new PlaceholderException($"'{{{key}}}' in '{token}' is not a placeholder; write '{{{{' for a literal brace");

                output.Append(valueOf(key));
                i = close;
            }
            else if (c == '}')
            {
                if (i + 1 < token.Length && token[i + 1] == '}')
                {
                    output.Append('}');
                    i++;
                    continue;
                }

                throw new PlaceholderException($"'}}' in '{token}' closes nothing; write '}}}}' for a literal brace");
            }
            else
            {
                output.Append(c);
            }
        }

        return output.ToString();
    }

    [GeneratedRegex("^[a-z][A-Za-z0-9]*$")]
    private static partial Regex KeyPattern();

    [GeneratedRegex(@"\$\{instance_(?<braced>[a-z0-9_]+)\}|\$instance_(?<bare>[a-z0-9_]+)")]
    private static partial Regex InstanceReferencePattern();
}
