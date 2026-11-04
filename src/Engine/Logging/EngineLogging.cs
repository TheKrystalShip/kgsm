using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Paths;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Engine.Logging;

/// <summary>Builds the engine's logger factory: the file provider only, never the terminal.</summary>
public static class EngineLogging
{
    /// <summary>
    /// The factory for a command. The level is <c>Logging:LogLevel:Default</c> of the merged configuration,
    /// <c>Information</c> when it names none.
    /// </summary>
    public static ILoggerFactory CreateFactory(EngineConfiguration configuration, EnginePaths paths, TimeProvider? clock = null)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(paths);

        FileLogSettings file = configuration.Settings.Logging.File;
        var options = new FileLoggerOptions
        {
            Path = paths.LogFile,
            MaxSizeBytes = file.MaxSizeKb * 1024L,
            MaxFiles = file.MaxFiles,
        };

        // The factory is built directly rather than through a service collection: a command line pays for
        // everything it constructs, and the log needs only the one provider and its level rules.
        var filters = new LoggerFilterOptions { MinLevel = LogLevel.Information };
        foreach (IConfigurationSection rule in configuration.Configuration.GetSection("Logging:LogLevel").GetChildren())
        {
            if (!Enum.TryParse(rule.Value, ignoreCase: true, out LogLevel level)) continue;

            if (string.Equals(rule.Key, "Default", StringComparison.OrdinalIgnoreCase))
                filters.MinLevel = level;
            else
                filters.Rules.Add(new LoggerFilterRule(providerName: null, categoryName: rule.Key, logLevel: level, filter: null));
        }

        return new LoggerFactory([new FileLoggerProvider(options, clock)], filters);
    }
}
