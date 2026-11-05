using System.Collections;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Configuration.Json;
using TheKrystalShip.KGSM.Engine.Contracts.Scheduling;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Settings;

/// <summary>The settings the engine runs with, and the configuration they were bound from.</summary>
public sealed class EngineConfiguration
{
    public required EngineSettings Settings { get; init; }

    /// <summary>The merged configuration; the <c>Logging</c> section drives the log level.</summary>
    public required IConfiguration Configuration { get; init; }
}

/// <summary>The settings do not satisfy the engine's floors.</summary>
public sealed class InvalidSettingsException(IReadOnlyList<string> problems)
    : EngineException("invalid-settings", "The settings are not valid: " + string.Join("; ", problems))
{
    public IReadOnlyList<string> Problems { get; } = problems;
}

/// <summary>
/// Builds the engine's settings from three sources, lowest precedence first: <c>kgsm.settings.json</c>
/// beside the binary, the person's <c>kgsm/kgsm.settings.json</c> in the config home, and the environment
/// (<c>Section__Key</c>). A source added later wins.
/// </summary>
public static class EngineSettingsLoader
{
    /// <param name="paths">Where the two files are.</param>
    /// <param name="environment">The environment to read; a name with <c>__</c> maps to a configuration key.</param>
    /// <exception cref="EngineFormatException">A settings file is not valid JSON.</exception>
    /// <exception cref="InvalidSettingsException">A value is below its floor or unreadable.</exception>
    public static EngineConfiguration Load(EnginePaths paths, IReadOnlyDictionary<string, string?> environment) =>
        Load(paths, environment, userSettings: null);

    /// <summary>
    /// The problems the settings would have if the person's file held <paramref name="userSettings"/>; empty
    /// when they would be valid. Nothing is written.
    /// </summary>
    public static IReadOnlyList<string> Check(EnginePaths paths, IReadOnlyDictionary<string, string?> environment, byte[] userSettings)
    {
        try
        {
            Load(paths, environment, userSettings);
            return [];
        }
        catch (InvalidSettingsException ex)
        {
            return ex.Problems;
        }
    }

    private static EngineConfiguration Load(EnginePaths paths, IReadOnlyDictionary<string, string?> environment, byte[]? userSettings)
    {
        ArgumentNullException.ThrowIfNull(paths);
        ArgumentNullException.ThrowIfNull(environment);

        var builder = new ConfigurationBuilder();
        AddFile(builder, paths.SystemSettingsFile);
        if (userSettings is null) AddFile(builder, paths.UserSettingsFile);
        else builder.Add(new JsonBytesSource(paths.UserSettingsFile, userSettings));
        builder.AddInMemoryCollection(EnvironmentKeys(environment));

        IConfigurationRoot configuration = builder.Build();

        EngineSettings settings;
        try
        {
            settings = configuration.Get<EngineSettings>() ?? new EngineSettings();
        }
        catch (InvalidOperationException ex)
        {
            throw new InvalidSettingsException([ex.InnerException?.Message ?? ex.Message]);
        }

        IReadOnlyList<string> problems = Validate(settings);
        if (problems.Count > 0) throw new InvalidSettingsException(problems);

        return new EngineConfiguration { Settings = settings, Configuration = configuration };
    }

    /// <summary>Loads from the running process's paths and environment.</summary>
    public static EngineConfiguration FromProcess() => Load(EnginePaths.FromProcess(), ProcessEnvironment());

    /// <summary>The floors every setting keeps. Every problem is listed, not the first.</summary>
    public static IReadOnlyList<string> Validate(EngineSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        var problems = new List<string>();

        AtLeast(problems, "Libraries:InstallFreeSpaceMarginMb", settings.Libraries.InstallFreeSpaceMarginMb, LibrariesSettings.Floors.Zero);
        AtLeast(problems, "Instances:IdSuffixLength", settings.Instances.IdSuffixLength, InstancesSettings.Floors.IdSuffixLength);
        if (settings.Instances.IdSuffixLength > InstancesSettings.Floors.MaxIdSuffixLength)
            problems.Add($"Instances:IdSuffixLength is above {InstancesSettings.Floors.MaxIdSuffixLength}");
        AtLeast(problems, "Instances:SaveCommandTimeoutSeconds", settings.Instances.SaveCommandTimeoutSeconds, InstancesSettings.Floors.Zero);
        AtLeast(problems, "Instances:StopCommandTimeoutSeconds", settings.Instances.StopCommandTimeoutSeconds, InstancesSettings.Floors.Zero);
        AtLeast(problems, "Downloads:TimeoutSeconds", settings.Downloads.TimeoutSeconds, DownloadsSettings.Floors.TimeoutSeconds);
        AtLeast(problems, "Logging:File:MaxSizeKb", settings.Logging.File.MaxSizeKb, FileLogSettings.Floors.MaxSizeKb);
        AtLeast(problems, "Logging:File:MaxFiles", settings.Logging.File.MaxFiles, FileLogSettings.Floors.MaxFiles);

        foreach (MaintenanceWindow window in MaintenanceWindowParser.Parse(settings.Instances.MaintenanceWindows))
        {
            if (!window.IsValid) problems.Add($"Instances:MaintenanceWindows: {window.Error}");
        }

        if (string.IsNullOrWhiteSpace(settings.Journal.Directory))
            problems.Add("Journal:Directory is empty");

        return problems;
    }

    private static void AtLeast(List<string> problems, string key, int value, int floor)
    {
        if (value < floor) problems.Add($"{key} is {value}, below its floor of {floor}");
    }

    /// <summary>
    /// Adds a settings file when it exists. The file is read straight into the configuration: a command line
    /// pays for every provider it constructs, and a settings file is read once and never watched.
    /// </summary>
    private static void AddFile(ConfigurationBuilder builder, string path)
    {
        byte[] content;
        try
        {
            if (!File.Exists(path)) return;
            content = File.ReadAllBytes(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new EngineFormatException(path, "the settings file cannot be read", ex);
        }

        builder.Add(new JsonBytesSource(path, content));
    }

    /// <summary>A settings file's bytes as a configuration source; invalid JSON is the engine's format error.</summary>
    private sealed class JsonBytesSource(string path, byte[] content) : IConfigurationSource
    {
        public IConfigurationProvider Build(IConfigurationBuilder builder) => new Provider(path, content);

        private sealed class Provider(string path, byte[] content) : JsonStreamConfigurationProvider(new JsonStreamConfigurationSource())
        {
            public override void Load()
            {
                try
                {
                    Load(new MemoryStream(content));
                }
                catch (Exception ex) when (ex is FormatException or InvalidDataException or System.Text.Json.JsonException)
                {
                    throw new EngineFormatException(path, "the settings file is not valid JSON", ex);
                }
            }
        }
    }

    private static IEnumerable<KeyValuePair<string, string?>> EnvironmentKeys(IReadOnlyDictionary<string, string?> environment)
    {
        foreach ((string name, string? value) in environment)
        {
            if (!name.Contains("__", StringComparison.Ordinal)) continue;
            yield return new(name.Replace("__", ":", StringComparison.Ordinal), value);
        }
    }

    private static Dictionary<string, string?> ProcessEnvironment()
    {
        var copy = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            if (entry.Key is string key) copy[key] = entry.Value as string;
        }

        return copy;
    }
}
