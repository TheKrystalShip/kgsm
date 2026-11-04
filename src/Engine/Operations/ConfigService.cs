using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Scheduling;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Journal;
using TheKrystalShip.KGSM.Engine.Placeholders;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Sets one instance config key. A protected key is refused, a value is checked against what its key
/// means before the file is touched, and the file is replaced whole, so the script that reads it never
/// sees a partial. Every change is journaled with the key and never the value, which can be a credential.
/// </summary>
public sealed class ConfigService(OperationHost host)
{
    public ConfigSetReport Set(InstanceDescription instance, string key, string value, string? author, string? authorName)
    {
        InstanceConfig config = Guards.Config(instance);
        Guards.Online(instance, "config set");
        TransferLock.Require(instance, "config set");

        InstanceConfigKey known = InstanceConfigKeys.Find(key)
            ?? throw OperationException.NotFound($"An instance config has no key '{key}'.");
        if (!known.Settable || known.Write is null)
            throw OperationException.Refused($"'{key}' is protected: it is the instance's identity, a path, or something the engine writes itself");

        bool windows = known.Name == "maintenanceWindows";
        if (!windows && (author is not null || authorName is not null))
            throw OperationException.Invalid("--author and --author-name record who wrote maintenanceWindows and apply to no other key");

        string checkedValue = Validate(known, value);
        string? normalizedAuthor = null;
        if (windows && author is not null)
        {
            normalizedAuthor = Provenance.NormalizeActor(author)
                ?? throw OperationException.Invalid($"'{author}' is not an author: write it as provider:name");
        }

        using IDisposable held = host.Locks.AcquireInstance(instance.Id);

        string? before = known.Read(config);
        InstanceConfig updated = known.Write(config, checkedValue);
        if (windows)
        {
            updated = updated with
            {
                MaintenanceWindowsAuthor = normalizedAuthor,
                MaintenanceWindowsAuthorName = normalizedAuthor is null ? null : DisplayNames.Normalize(authorName) is { Length: > 0 } name ? name : null,
            };
        }

        bool changed = before != known.Read(updated)
            || updated.MaintenanceWindowsAuthor != config.MaintenanceWindowsAuthor
            || updated.MaintenanceWindowsAuthorName != config.MaintenanceWindowsAuthorName;

        if (changed)
        {
            ContractFile.Write(instance.Layout.ConfigFile, updated, EngineJsonContext.Default.InstanceConfig);
            host.Events.Append(new ConfigChanged { InstanceName = instance.Id, Key = known.Name });

            if (known.Name == "displayName")
            {
                host.Events.Append(new Renamed
                {
                    InstanceName = instance.Id,
                    OldDisplayName = config.Label,
                    NewDisplayName = updated.Label,
                });
            }
        }

        return new ConfigSetReport { Instance = instance.Id, Key = known.Name, Value = known.Read(updated), Changed = changed };
    }

    /// <summary>The value as the config stores it, or a refusal that says what the key accepts.</summary>
    internal static string Validate(InstanceConfigKey key, string value)
    {
        switch (key.Name)
        {
            case "displayName":
                return DisplayNames.Normalize(value);
            case "cpuPriority":
                return value is "low" or "normal" or "high" ? value : throw Invalid(key, "low, normal or high");
            case "timezone":
                return value.Length == 0 || IsTimezone(value) ? value : throw Invalid(key, "an IANA time zone such as Europe/Madrid, or empty");
            case "maintenanceWindows":
                return Windows(value);
            case "announceLeadMinutes":
                return LeadMinutes(value);
            case "executableArguments":
                return Arguments(value);
            case "rconPort":
                return value.Length == 0 || (int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out int port) && port is >= 1 and <= 65535)
                    ? value
                    : throw Invalid(key, "a port from 1 to 65535, or empty");
        }

        return key.Type switch
        {
            "bool" => value.ToLowerInvariant() is "true" or "false" ? value.ToLowerInvariant() : throw Invalid(key, "true or false"),
            "int" => Integer(key, value),
            _ => SingleLine(key, value),
        };
    }

    private static string Integer(InstanceConfigKey key, string value)
    {
        int minimum = key.Name is "backupRetention" or "rconPollIntervalSeconds" or "downloadTimeoutSeconds" ? 1 : 0;
        if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out int number) || number < minimum)
            throw Invalid(key, minimum == 1 ? "a whole number of at least 1" : "a whole number, zero or more");

        return number.ToString(CultureInfo.InvariantCulture);
    }

    private static string SingleLine(InstanceConfigKey key, string value) =>
        value.Any(char.IsControl) ? throw Invalid(key, "one line of text, with no control characters") : value;

    private static string Windows(string value)
    {
        IReadOnlyList<MaintenanceWindow> parsed = MaintenanceWindowParser.Parse(value);
        string[] problems = [.. parsed.Where(w => !w.IsValid).Select(w => w.Error ?? w.Expression)];
        if (problems.Length > 0) throw OperationException.Invalid("maintenanceWindows holds a window that cannot be read", problems);

        return MaintenanceWindowParser.Format(parsed);
    }

    private static string LeadMinutes(string value)
    {
        if (value.Length == 0) return value;

        string[] parts = value.Split(',', StringSplitOptions.TrimEntries);
        if (parts.Any(p => !int.TryParse(p, NumberStyles.None, CultureInfo.InvariantCulture, out int n) || n < 1))
            throw OperationException.Invalid("announceLeadMinutes is a comma-separated list of whole minutes, such as 15,5,1");

        return string.Join(',', parts);
    }

    private static string Arguments(string value)
    {
        IReadOnlyList<string> names;
        try
        {
            names = LaunchArguments.Keys(value);
        }
        catch (PlaceholderException ex)
        {
            throw OperationException.Invalid($"executableArguments: {ex.Message}");
        }

        string[] unknown = [.. names.Where(n => !InstancePlaceholders.Keys.Contains(n))];
        if (unknown.Length > 0)
            throw OperationException.Invalid($"executableArguments names {string.Join(", ", unknown.Select(n => "{" + n + "}"))}, which an instance has no value for", ["kgsm engine placeholders lists the keys"]);

        return SingleLine(InstanceConfigKeys.Find("executableArguments")!, value);
    }

    private static bool IsTimezone(string id)
    {
        try
        {
            TimeZoneInfo.FindSystemTimeZoneById(id);
            return true;
        }
        catch (Exception ex) when (ex is TimeZoneNotFoundException or InvalidTimeZoneException)
        {
            return false;
        }
    }

    private static OperationException Invalid(InstanceConfigKey key, string expected) =>
        OperationException.Invalid($"'{key.Name}' takes {expected}");
}
