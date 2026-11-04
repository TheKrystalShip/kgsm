using Microsoft.Extensions.Configuration;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Settings;

/// <summary>
/// Lists the settings the engine runs with. The file beside the binary declares the whole surface, so its
/// keys are the engine's keys; each value is what the merged configuration resolves to, and the source is
/// the highest-precedence one that sets it.
/// </summary>
public static class SettingsView
{
    /// <summary>Every declared setting in the order its file declares it.</summary>
    public static IReadOnlyList<EngineSetting> List(EngineConfiguration configuration, EnginePaths paths)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(paths);

        var declared = new ConfigurationBuilder()
            .AddJsonFile(source =>
            {
                source.Path = paths.SystemSettingsFile;
                source.Optional = true;
                source.ReloadOnChange = false;
                source.ResolveFileProvider();
            })
            .Build();

        // The merged configuration's providers are, lowest precedence first: the file beside the binary, the
        // person's file, then the environment.
        IConfigurationProvider[] providers = [.. ((IConfigurationRoot)configuration.Configuration).Providers];

        return
        [
            .. declared.AsEnumerable(makePathsRelative: false)
                .Where(pair => pair.Value is not null)
                .Select(pair => pair.Key)
                .Select(key => Describe(key, providers))
                .OrderBy(setting => setting.Key, StringComparer.Ordinal),
        ];
    }

    /// <summary>One setting by its <c>Section:Key</c> (or <c>Section__Key</c>) name, or null when the engine declares none by that name.</summary>
    public static EngineSetting? Find(EngineConfiguration configuration, EnginePaths paths, string key)
    {
        string normalised = key.Replace("__", ":", StringComparison.Ordinal);
        return List(configuration, paths).FirstOrDefault(s => string.Equals(s.Key, normalised, StringComparison.OrdinalIgnoreCase));
    }

    private static EngineSetting Describe(string key, IConfigurationProvider[] providers)
    {
        string value = string.Empty;
        SettingSource source = SettingSource.Default;

        for (int index = 0; index < providers.Length; index++)
        {
            if (providers[index].TryGet(key, out string? found) && found is not null)
            {
                value = found;
                source = index switch { 0 => SettingSource.Default, 1 => SettingSource.User, _ => SettingSource.Environment };
            }
        }

        // The configuration system renders a JSON boolean as True or False; the settings file spells it as JSON does.
        value = value switch { "True" => "true", "False" => "false", _ => value };
        return new EngineSetting { Key = key, Value = value, Source = source };
    }
}
