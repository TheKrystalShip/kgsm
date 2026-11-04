using System.Globalization;
using Microsoft.Extensions.Logging;
using YamlDotNet.Core;
using YamlDotNet.Serialization;

namespace TheKrystalShip.KGSM.Engine.Blueprints;

/// <summary>
/// The firewall set of a container instance, read from the ports its compose services declare. Under host
/// networking the block publishes nothing; it is the blueprint's statement of which ports the game
/// listens on, written in compose's short syntax (<c>host:container/proto</c>, <c>ip:host:container</c>, a
/// bare port, a <c>from-to</c> range). A port with no protocol is TCP, as compose reads it.
/// </summary>
public static class ComposePorts
{
    private static readonly IDeserializer Deserializer = new StaticDeserializerBuilder(new BlueprintYamlContext())
        .WithNamingConvention(YamlDotNet.Serialization.NamingConventions.UnderscoredNamingConvention.Instance)
        .IgnoreUnmatchedProperties()
        .Build();

    /// <summary>The ports in the instance config's format, pipe-separated; empty when the compose declares none or cannot be read for them.</summary>
    public static string Derive(string compose, ILogger? logger = null)
    {
        ComposePortsFile? document;
        try
        {
            document = Deserializer.Deserialize<ComposePortsFile?>(compose);
        }
        catch (YamlException ex)
        {
            logger?.LogWarning("The compose ports could not be read, so the instance declares none: {Detail}", ex.Message);
            return string.Empty;
        }

        var tokens = new List<string>();
        foreach (string entry in document?.Services?.Values.SelectMany(s => s?.Ports ?? []) ?? [])
        {
            if (Token(entry) is { } token && !tokens.Contains(token, StringComparer.Ordinal)) tokens.Add(token);
        }

        return string.Join('|', tokens);
    }

    private static string? Token(string entry)
    {
        string text = entry.Trim();
        string protocol = "tcp";

        int slash = text.LastIndexOf('/');
        if (slash >= 0)
        {
            protocol = text[(slash + 1)..].ToLowerInvariant();
            text = text[..slash];
        }

        if (protocol is not ("tcp" or "udp")) return null;

        string[] parts = text.Split(':');
        string host = parts.Length switch
        {
            1 or 2 => parts[0],
            _ => parts[^2],
        };

        string[] range = host.Split('-');
        if (range.Length > 2 || !range.All(IsPort)) return null;

        return $"{string.Join(':', range)}/{protocol}";
    }

    private static bool IsPort(string text) =>
        int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out int port) && port is >= 1 and <= 65535;
}
