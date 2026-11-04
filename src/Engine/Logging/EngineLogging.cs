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

        return LoggerFactory.Create(builder =>
        {
            builder.AddConfiguration(configuration.Configuration.GetSection("Logging"));
            builder.SetMinimumLevel(LogLevel.Information);
            builder.AddProvider(new FileLoggerProvider(options, clock));
        });
    }
}
