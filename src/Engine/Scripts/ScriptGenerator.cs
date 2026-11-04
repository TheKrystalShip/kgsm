using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Instances;

namespace TheKrystalShip.KGSM.Engine.Scripts;

/// <summary>What a generated script records about how it was built.</summary>
/// <param name="TemplateVersion">The template's version.</param>
/// <param name="HooksDigest">The digest of the hooks file it was built from, or <see cref="HookFiles.NoHooksDigest"/>.</param>
/// <param name="Runtime">The runtime it serves.</param>
public sealed partial record ScriptHeader(int TemplateVersion, string HooksDigest, BlueprintRuntime Runtime)
{
    /// <summary>Reads the header line of a script's text; null when there is none.</summary>
    public static ScriptHeader? Parse(string script)
    {
        Match match = HeaderPattern().Match(script);
        if (!match.Success) return null;

        return new ScriptHeader(
            int.Parse(match.Groups["template"].Value, System.Globalization.CultureInfo.InvariantCulture),
            match.Groups["hooks"].Value,
            match.Groups["runtime"].Value == "native" ? BlueprintRuntime.Native : BlueprintRuntime.Container);
    }

    [GeneratedRegex(@"^# kgsm-script: template=(?<template>\d+) hooks=(?<hooks>[0-9a-f]{64}|none) runtime=(?<runtime>native|container)\r?$", RegexOptions.Multiline)]
    private static partial Regex HeaderPattern();
}

/// <summary>
/// Renders an instance's management script from the template: one script for either runtime, with the
/// template version and the hooks digest recorded, the launch-argument keys and the watchdog socket
/// filled in, and a native game's hooks inlined. Container instances take no hooks.
/// </summary>
public static partial class ScriptGenerator
{
    /// <summary>The header a script built from these inputs carries.</summary>
    public static ScriptHeader HeaderFor(InstanceConfig config, HookFile? hooks) =>
        new(ScriptTemplate.Version, config.Runtime == BlueprintRuntime.Native && hooks is not null ? hooks.Digest : HookFiles.NoHooksDigest, config.Runtime);

    /// <summary>The script's text.</summary>
    /// <param name="config">The instance's config; its runtime picks the variant.</param>
    /// <param name="hooks">The game's hooks, which only a native instance takes.</param>
    /// <param name="watchdogSocket">The control socket the script asks first; an absolute path.</param>
    public static string Render(InstanceConfig config, HookFile? hooks, string watchdogSocket)
    {
        ArgumentNullException.ThrowIfNull(config);
        if (!SocketPattern().IsMatch(watchdogSocket))
            throw new EngineException("script", $"the watchdog socket '{watchdogSocket}' is not a path a script can carry");

        bool native = config.Runtime == BlueprintRuntime.Native;
        ScriptHeader header = HeaderFor(config, hooks);

        var tokens = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["TEMPLATE_VERSION"] = header.TemplateVersion.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["HOOKS_DIGEST"] = header.HooksDigest,
            ["RUNTIME"] = native ? "native" : "container",
            ["PLACEHOLDER_KEYS"] = string.Join(' ', InstancePlaceholders.Keys.Order(StringComparer.Ordinal)),
            ["WATCHDOG_SOCKET"] = watchdogSocket,
        };

        return ScriptTemplate.Render(native, tokens, native ? hooks?.Text : null);
    }

    [GeneratedRegex(@"^/[A-Za-z0-9_./ -]*$")]
    private static partial Regex SocketPattern();
}
