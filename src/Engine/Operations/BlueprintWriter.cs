using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>
/// Writes and removes user blueprints. A blueprint is checked against every rule before a file is made,
/// the file is replaced whole, and only the user directory is ever written: a system blueprint is shadowed
/// by a user file of the same name and never edited.
/// </summary>
public sealed class BlueprintWriter(OperationHost host)
{
    private readonly BlueprintParser _parser = new(Microsoft.Extensions.Logging.LoggerFactoryExtensions.CreateLogger<BlueprintParser>(host.Loggers));

    public BlueprintWriteReport Create(string key, string yaml) => Write(key, yaml, mustExist: false);

    public BlueprintWriteReport Update(string key, string yaml) => Write(key, yaml, mustExist: true);

    public BlueprintWriteReport Delete(string key)
    {
        RequireKey(key);
        using IDisposable held = host.Locks.AcquireGlobal();

        string path = UserPath(key);
        if (!File.Exists(path))
        {
            throw File.Exists(SystemPath(key))
                ? OperationException.Refused($"'{key}' is a system blueprint and is never removed; a user file of the same name shadows it")
                : OperationException.NotFound($"No user blueprint '{key}' exists.");
        }

        bool systemRemains = File.Exists(SystemPath(key));
        string? name = _parser.ParseFile(path).Blueprint?.Name;
        if (name is not null && !systemRemains)
        {
            string[] users = [.. host.Instances.List().Where(i => i.Blueprint == name).Select(i => i.Id)];
            if (users.Length > 0)
                throw OperationException.Refused($"instances are installed from '{key}': {string.Join(", ", users)}");
        }

        File.Delete(path);
        host.Events.Append(new BlueprintRemoved { BlueprintName = key, Tier = BlueprintTier.User, RevertedToSystem = systemRemains });
        return new BlueprintWriteReport { Name = key, Path = path, Tier = BlueprintTier.User, SystemBlueprintInvolved = systemRemains };
    }

    private BlueprintWriteReport Write(string key, string yaml, bool mustExist)
    {
        RequireKey(key);

        string path = UserPath(key);
        BlueprintParseResult parsed = _parser.Parse(yaml, path);
        if (parsed.Blueprint is not { } blueprint)
            throw OperationException.Invalid($"the blueprint for '{key}' is not valid", parsed.Validation.Errors);

        using IDisposable held = host.Locks.AcquireGlobal();

        bool exists = File.Exists(path);
        if (mustExist && !exists) throw OperationException.NotFound($"No user blueprint '{key}' exists; create it first.");
        if (!mustExist && exists) throw OperationException.Refused($"the user blueprint '{key}' exists; update it instead");

        bool overridesSystem = File.Exists(SystemPath(key));
        Directory.CreateDirectory(host.Paths.UserBlueprintsDirectory);

        string staged = Path.Combine(host.Paths.UserBlueprintsDirectory, $".{key}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(staged, yaml, new System.Text.UTF8Encoding(false));
            File.Move(staged, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(staged)) File.Delete(staged);
        }

        string runtime = blueprint.Runtime == BlueprintRuntime.Native ? "native" : "container";
        if (mustExist) host.Events.Append(new BlueprintUpdated { BlueprintName = key, Tier = BlueprintTier.User, OverridesSystem = overridesSystem, Runtime = runtime });
        else host.Events.Append(new BlueprintCreated { BlueprintName = key, Tier = BlueprintTier.User, OverridesSystem = overridesSystem, Runtime = runtime });

        return new BlueprintWriteReport { Name = key, Path = path, Tier = BlueprintTier.User, SystemBlueprintInvolved = overridesSystem };
    }

    private string UserPath(string key) => Path.Combine(host.Paths.UserBlueprintsDirectory, key + EnginePaths.BlueprintFileSuffix);

    private string SystemPath(string key) => Path.Combine(host.Paths.SystemBlueprintsDirectory, key + EnginePaths.BlueprintFileSuffix);

    private static void RequireKey(string key)
    {
        if (!BlueprintParser.IsValidName(key))
            throw OperationException.Invalid($"'{key}' is not a blueprint file name: lowercase letters, digits, '.', '_' and '-'");
    }
}
