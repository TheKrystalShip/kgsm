using System.Text;
using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>A compose document names an instance value that does not exist.</summary>
public sealed class ComposeException(string message) : EngineException("compose", message);

/// <summary>
/// Renders a container blueprint's compose document into <c>&lt;id&gt;.docker-compose.yml</c> without a
/// shell. Only <c>${instance_&lt;key&gt;}</c> and <c>$instance_&lt;key&gt;</c> are substituted, against the
/// instance's own values; every other <c>$</c> is left for compose, and <c>$$</c> stays the escape
/// compose reads as one literal dollar. A key the instance has no value for fails the render.
/// </summary>
public static partial class ComposeRenderer
{
    /// <summary>The values a compose document may name, by the snake_case spelling a blueprint writes.</summary>
    public static IReadOnlyDictionary<string, string> Values(InstanceConfig config, InstanceLayout layout)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(layout);

        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach ((string key, string value) in InstancePlaceholders.Values(config, layout))
            values[InstancePlaceholders.CamelToSnake(key)] = value;

        values["auto_update"] = config.AutoUpdateBeforeStart ? "true" : "false";
        values["player_joined_regex_b64"] = Base64(config.PlayerJoinedRegex);
        values["player_left_regex_b64"] = Base64(config.PlayerLeftRegex);
        return values;
    }

    /// <summary>The compose text with the instance's values in place of its references.</summary>
    /// <exception cref="ComposeException">The document references a key that has no value.</exception>
    public static string Render(string compose, InstanceConfig config, InstanceLayout layout)
    {
        ArgumentNullException.ThrowIfNull(compose);
        IReadOnlyDictionary<string, string> values = Values(config, layout);

        return ReferencePattern().Replace(compose, match =>
        {
            if (match.Groups["escape"].Success) return match.Value;

            string key = match.Groups["braced"].Success ? match.Groups["braced"].Value : match.Groups["bare"].Value;
            return values.TryGetValue(key, out string? value)
                ? value
                : throw new ComposeException($"the compose file names '$instance_{key}', which is not an instance value");
        });
    }

    private static string Base64(string text) => Convert.ToBase64String(Encoding.UTF8.GetBytes(text));

    [GeneratedRegex(@"(?<escape>\$\$)|\$\{instance_(?<braced>[a-z0-9_]+)\}|\$instance_(?<bare>[a-z0-9_]+)")]
    private static partial Regex ReferencePattern();
}
