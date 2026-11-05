using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Locks;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Settings;

/// <summary>What setting one value did.</summary>
/// <param name="Key">The setting as <c>Section:Key</c>.</param>
/// <param name="Stored">What the person's file now holds for it.</param>
/// <param name="Changed">Whether the file changed.</param>
/// <param name="Effective">The setting as the engine now resolves it, with the source that wins: an environment variable still overrides the file.</param>
public sealed record SettingChange(string Key, string Stored, bool Changed, EngineSetting Effective);

/// <summary>
/// Writes one setting into the person's settings file (<c>kgsm/kgsm.settings.json</c> in the config home). The
/// value is checked against what its key holds and against the engine's floors before anything is written,
/// the file holds only what the person set, and it is replaced whole.
/// </summary>
public static class SettingsWriter
{
    /// <exception cref="OperationException">The key is unknown, or the value does not suit it.</exception>
    public static SettingChange Set(
        EnginePaths paths, IReadOnlyDictionary<string, string?> environment, string key, string value)
    {
        EngineConfiguration current = EngineSettingsLoader.Load(paths, environment);
        EngineSetting declared = SettingsView.Find(current, paths, key)
            ?? throw OperationException.NotFound($"The engine has no setting '{key}'.");

        using IDisposable held = new EngineLocks(paths).AcquireGlobal();

        SettingsOverrides overrides = Read(paths.UserSettingsFile);
        string stored = Apply(overrides, declared.Key, value);

        byte[] candidate = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(overrides, SettingsFileJsonContext.Default.SettingsOverrides);
        IReadOnlyList<string> problems = EngineSettingsLoader.Check(paths, environment, candidate);
        if (problems.Count > 0)
            throw OperationException.Invalid($"'{value}' does not suit {declared.Key}", problems);

        byte[]? existing = File.Exists(paths.UserSettingsFile) ? File.ReadAllBytes(paths.UserSettingsFile) : null;
        bool changed = existing is null || !existing.AsSpan().SequenceEqual(candidate);
        if (changed) ContractFile.WriteBytes(paths.UserSettingsFile, candidate);

        EngineSetting effective = SettingsView.Find(EngineSettingsLoader.Load(paths, environment), paths, declared.Key)!;
        return new SettingChange(declared.Key, stored, changed, effective);
    }

    private static SettingsOverrides Read(string file)
    {
        if (!File.Exists(file)) return new SettingsOverrides();

        try
        {
            return System.Text.Json.JsonSerializer.Deserialize(File.ReadAllBytes(file), SettingsFileJsonContext.Default.SettingsOverrides)
                ?? new SettingsOverrides();
        }
        catch (Exception ex) when (ex is System.Text.Json.JsonException or IOException or UnauthorizedAccessException)
        {
            throw new EngineFormatException(file, "the settings file cannot be read, so it is not rewritten", ex);
        }
    }

    private static string Apply(SettingsOverrides o, string key, string value)
    {
        switch (key.ToLowerInvariant())
        {
            case "libraries:defaultlibrary": (o.Libraries ??= new()).DefaultLibrary = Text(key, value); break;
            case "libraries:installfreespacemarginmb": (o.Libraries ??= new()).InstallFreeSpaceMarginMb = Int(key, value); break;
            case "instances:idsuffixlength": (o.Instances ??= new()).IdSuffixLength = Int(key, value); break;
            case "instances:savecommandtimeoutseconds": (o.Instances ??= new()).SaveCommandTimeoutSeconds = Int(key, value); break;
            case "instances:stopcommandtimeoutseconds": (o.Instances ??= new()).StopCommandTimeoutSeconds = Int(key, value); break;
            case "instances:autoupdatebeforestart": (o.Instances ??= new()).AutoUpdateBeforeStart = Bool(key, value); break;
            case "instances:maintenancewindows": (o.Instances ??= new()).MaintenanceWindows = Text(key, value); break;
            case "instances:announceleadminutes": (o.Instances ??= new()).AnnounceLeadMinutes = Text(key, value); break;
            case "instances:announcemaintenancemessage": (o.Instances ??= new()).AnnounceMaintenanceMessage = Text(key, value); break;
            case "instances:announcemaintenancecancelledmessage": (o.Instances ??= new()).AnnounceMaintenanceCancelledMessage = Text(key, value); break;
            case "instances:enablefirewallmanagement": (o.Instances ??= new()).EnableFirewallManagement = Bool(key, value); break;
            case "instances:enableportforwarding": (o.Instances ??= new()).EnablePortForwarding = Bool(key, value); break;
            case "backups:directory": (o.Backups ??= new()).Directory = Text(key, value); break;
            case "backups:compress": (o.Backups ??= new()).Compress = Bool(key, value); break;
            case "journal:directory": (o.Journal ??= new()).Directory = Text(key, value); break;
            case "journal:retentiondays": (o.Journal ??= new()).RetentionDays = Int(key, value); break;
            case "cgroup:mountpoint": (o.Cgroup ??= new()).MountPoint = Text(key, value); break;
            case "cgroup:basename": (o.Cgroup ??= new()).BaseName = Text(key, value); break;
            case "watchdog:socket": (o.Watchdog ??= new()).Socket = Text(key, value); break;
            case "watchdog:enabled": (o.Watchdog ??= new()).Enabled = Bool(key, value); break;
            case "firewall:client": (o.Firewall ??= new()).Client = Text(key, value); break;
            case "firewall:socket": (o.Firewall ??= new()).Socket = Text(key, value); break;
            case "downloads:timeoutseconds": (o.Downloads ??= new()).TimeoutSeconds = Int(key, value); break;
            case "logging:loglevel:default": ((o.Logging ??= new()).LogLevel ??= new()).Default = Text(key, value); break;
            case "logging:file:maxsizekb": ((o.Logging ??= new()).File ??= new()).MaxSizeKb = Int(key, value); break;
            case "logging:file:maxfiles": ((o.Logging ??= new()).File ??= new()).MaxFiles = Int(key, value); break;
            default:
                throw OperationException.Refused($"'{key}' cannot be set here");
        }

        return value;
    }

    private static string Text(string key, string value) =>
        value.Any(char.IsControl) ? throw OperationException.Invalid($"{key} takes one line of text, with no control characters") : value;

    private static int Int(string key, string value) =>
        int.TryParse(value, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out int number)
            ? number
            : throw OperationException.Invalid($"{key} takes a whole number");

    private static bool Bool(string key, string value) => value.ToLowerInvariant() switch
    {
        "true" => true,
        "false" => false,
        _ => throw OperationException.Invalid($"{key} takes true or false"),
    };
}
