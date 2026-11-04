using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>
/// The values a launch-argument placeholder can name: the instance config's own camelCase keys plus the
/// paths derived from the instance's location. Config stores no path, so the paths come from the layout.
/// </summary>
public static class InstancePlaceholders
{
    public static IReadOnlyDictionary<string, string> Values(InstanceConfig config, InstanceLayout layout)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentNullException.ThrowIfNull(layout);

        return new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["name"] = config.Name,
            ["displayName"] = config.Label,
            ["blueprint"] = config.Blueprint,
            ["runtime"] = config.Runtime == BlueprintRuntime.Native ? "native" : "container",
            ["platform"] = config.Platform,
            ["levelName"] = config.LevelName,
            ["executableFile"] = config.ExecutableFile,
            ["executableSubdirectory"] = config.ExecutableSubdirectory,
            ["workingDir"] = layout.WorkingDirectory,
            ["installDir"] = layout.InstallDirectory,
            ["savesDir"] = layout.SavesDirectory,
            ["logsDir"] = layout.LogsDirectory,
            ["tempDir"] = layout.TempDirectory,
            ["eventsDir"] = layout.EventsDirectory,
            ["launchDir"] = layout.LaunchDirectory,
            ["backupsDir"] = config.BackupsDirectory,
        };
    }

    /// <summary><c>levelName</c> to <c>level_name</c>: the spelling a blueprint's <c>$instance_&lt;key&gt;</c> uses.</summary>
    public static string CamelToSnake(string camel)
    {
        var snake = new System.Text.StringBuilder(camel.Length + 4);
        foreach (char c in camel)
        {
            if (char.IsAsciiLetterUpper(c)) snake.Append('_').Append(char.ToLowerInvariant(c));
            else snake.Append(c);
        }

        return snake.ToString();
    }

    /// <summary>The keys a blueprint's launch arguments may reference.</summary>
    public static IReadOnlySet<string> Keys { get; } = new HashSet<string>(
    [
        "name", "displayName", "blueprint", "runtime", "platform", "levelName", "executableFile",
        "executableSubdirectory", "workingDir", "installDir", "savesDir", "logsDir", "tempDir", "eventsDir",
        "launchDir", "backupsDir",
    ], StringComparer.Ordinal);

    /// <summary>The finished argument list for an instance: its config's template resolved against its values.</summary>
    /// <exception cref="Placeholders.PlaceholderException">The template names a key with no value.</exception>
    public static IReadOnlyList<string> ResolveLaunchArguments(InstanceConfig config, InstanceLayout layout) =>
        Placeholders.LaunchArguments.Resolve(config.ExecutableArguments, Values(config, layout));
}
