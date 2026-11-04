using System.Diagnostics;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;

namespace TheKrystalShip.KGSM.Engine.Blueprints;

/// <summary>Measures whether this host has a requirement.</summary>
public interface IRequirementProbe
{
    bool IsPresent(string requirementId);
}

/// <summary>
/// The requirements a blueprint declares by what it says: a container blueprint needs the container
/// runtime, a blueprint with a Steam app id needs steamcmd, and one that requires a Steam account needs
/// credentials. Blueprints carry no host-dependency field of their own.
/// </summary>
public static class BlueprintRequirementRules
{
    public static IReadOnlyList<string> IdsFor(Blueprint blueprint)
    {
        ArgumentNullException.ThrowIfNull(blueprint);

        if (blueprint.Runtime == BlueprintRuntime.Container) return [RequirementIds.ContainerRuntime];
        if (blueprint.Native is not { } native) return [];

        var ids = new List<string>();
        if (native.SteamAppId > 0) ids.Add(RequirementIds.Steamcmd);
        if (native.IsSteamAccountRequired) ids.Add(RequirementIds.SteamCredentials);
        return ids;
    }

    public static BlueprintRequirements Evaluate(Blueprint blueprint, IRequirementProbe probe)
    {
        ArgumentNullException.ThrowIfNull(probe);

        return new BlueprintRequirements
        {
            Blueprint = blueprint.Name,
            Requirements = IdsFor(blueprint).Select(id => new RequirementState(id, probe.IsPresent(id))).ToList(),
        };
    }
}

/// <summary>
/// The probe for the running host: executables are looked up on <c>PATH</c>, the container runtime is asked
/// for its compose version, and Steam credentials are the environment's or the credentials file's.
/// </summary>
public sealed class HostRequirementProbe(
    Func<string, string?> environment, string credentialsFile, Func<string, string[], bool>? run = null) : IRequirementProbe
{
    private readonly Func<string, string[], bool> _run = run ?? RunToCompletion;

    public bool IsPresent(string requirementId) => requirementId switch
    {
        RequirementIds.ContainerRuntime => OnPath("docker") && _run("docker", ["compose", "version"]),
        RequirementIds.Steamcmd => OnPath("steamcmd"),
        RequirementIds.SteamCredentials => SteamCredentials.Read(environment, credentialsFile).HasUsername,
        _ => false,
    };

    private bool OnPath(string executable)
    {
        string? path = environment("PATH");
        if (string.IsNullOrEmpty(path)) return false;

        return path.Split(':', StringSplitOptions.RemoveEmptyEntries)
            .Any(directory => File.Exists(Path.Combine(directory, executable)));
    }

    private static bool RunToCompletion(string executable, string[] arguments)
    {
        var start = new ProcessStartInfo(executable)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (string argument in arguments) start.ArgumentList.Add(argument);

        try
        {
            using Process? process = Process.Start(start);
            if (process is null) return false;

            process.StandardOutput.ReadToEnd();
            process.StandardError.ReadToEnd();
            process.WaitForExit();
            return process.ExitCode == 0;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }
}

/// <summary>
/// Steam credentials: <c>STEAM_USERNAME</c> and <c>STEAM_PASSWORD</c> from the environment, which wins, or
/// from the <c>KEY=VALUE</c> lines of <c>/etc/kgsm/kgsm.env</c>. A password may be empty (a stored login
/// token is used instead); the username is what marks credentials present.
/// </summary>
public sealed record SteamCredentials(string Username, string Password)
{
    public bool HasUsername => Username.Length > 0;

    public static SteamCredentials Read(Func<string, string?> environment, string file)
    {
        ArgumentNullException.ThrowIfNull(environment);

        Dictionary<string, string> fromFile = ReadFile(file);
        return new SteamCredentials(
            Pick(environment("STEAM_USERNAME"), fromFile, "STEAM_USERNAME"),
            Pick(environment("STEAM_PASSWORD"), fromFile, "STEAM_PASSWORD"));
    }

    private static string Pick(string? fromEnvironment, Dictionary<string, string> fromFile, string key) =>
        !string.IsNullOrEmpty(fromEnvironment) ? fromEnvironment
        : fromFile.TryGetValue(key, out string? value) ? value
        : string.Empty;

    private static Dictionary<string, string> ReadFile(string file)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);

        string[] lines;
        try
        {
            lines = File.ReadAllLines(file);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return values;
        }

        foreach (string raw in lines)
        {
            string line = raw.Trim();
            if (line.Length == 0 || line[0] == '#') continue;

            int equals = line.IndexOf('=', StringComparison.Ordinal);
            if (equals <= 0) continue;

            string value = line[(equals + 1)..].Trim();
            if (value.Length >= 2 && value[0] == value[^1] && value[0] is '"' or '\'')
                value = value[1..^1];

            values[line[..equals].Trim()] = value;
        }

        return values;
    }
}
