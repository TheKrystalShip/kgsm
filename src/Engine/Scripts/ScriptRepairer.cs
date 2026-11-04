using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Locks;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Scripts;

/// <summary>
/// Writes an instance's management script and finds the scripts that have gone stale. A script is stale
/// when it is missing, records no header, or was built from another template version, another hooks
/// file or another runtime than the ones the instance would get today. Generation is a write, so it
/// holds the instance's lock; no read ever regenerates a script.
/// </summary>
public sealed class ScriptRepairer(EnginePaths paths, string watchdogSocket, EngineLocks locks, ILogger<ScriptRepairer>? logger = null)
{
    /// <summary>
    /// Why an instance's script is stale, or null when it is current. The hooks file that would be used
    /// is checked as well, so a hooks file that cannot be inlined is reported as the reason.
    /// </summary>
    /// <exception cref="HookFileException">The instance's hooks file is not acceptable.</exception>
    public string? StaleReason(InstanceDescription instance)
    {
        InstanceConfig config = instance.Config ?? throw new InvalidOperationException("The instance has no readable config.");
        HookFile? hooks = HooksFor(config);
        return StaleReason(instance.Layout.ManagementScript, ScriptGenerator.HeaderFor(config, hooks));
    }

    /// <summary>Why the script at <paramref name="scriptPath"/> differs from <paramref name="expected"/>, or null when it matches.</summary>
    public static string? StaleReason(string scriptPath, ScriptHeader expected)
    {
        if (!File.Exists(scriptPath)) return "the script is missing";

        ScriptHeader? recorded = ScriptHeader.Parse(File.ReadAllText(scriptPath));
        if (recorded is null) return "the script records no header";
        if (recorded.TemplateVersion != expected.TemplateVersion)
            return $"the script is built from template {recorded.TemplateVersion}, the engine carries {expected.TemplateVersion}";
        if (recorded.Runtime != expected.Runtime) return "the script is for the other runtime";
        if (recorded.HooksDigest != expected.HooksDigest) return "the hooks file changed";
        return null;
    }

    /// <summary>
    /// Regenerates one instance's script. With <paramref name="onlyIfStale"/> a current script is left
    /// alone; without it the script is rewritten whatever it holds, which is what repairing one instance by
    /// hand means.
    /// </summary>
    public ScriptRepairEntry Repair(InstanceDescription instance, bool onlyIfStale)
    {
        if (instance.Config is null)
        {
            return new ScriptRepairEntry
            {
                Id = instance.Id,
                Outcome = ScriptRepairOutcome.Skipped,
                Detail = instance.ConfigProblem ?? "the instance's config cannot be read",
            };
        }

        try
        {
            using IDisposable held = locks.AcquireInstance(instance.Id);

            HookFile? hooks = HooksFor(instance.Config);
            string? reason = StaleReason(instance.Layout.ManagementScript, ScriptGenerator.HeaderFor(instance.Config, hooks));
            if (onlyIfStale && reason is null)
                return new ScriptRepairEntry { Id = instance.Id, Outcome = ScriptRepairOutcome.Current };

            string text = ScriptGenerator.Render(instance.Config, hooks, watchdogSocket);
            ScriptFile.Write(instance.Layout.ManagementScript, text);
            logger?.LogInformation("Regenerated the management script of {Id}: {Reason}", instance.Id, reason ?? "repair was asked for");
            return new ScriptRepairEntry { Id = instance.Id, Outcome = ScriptRepairOutcome.Regenerated, Detail = reason };
        }
        catch (EngineException ex)
        {
            logger?.LogWarning("The management script of {Id} was not regenerated: {Problem}", instance.Id, ex.Message);
            return new ScriptRepairEntry { Id = instance.Id, Outcome = ScriptRepairOutcome.Failed, Detail = ex.Message };
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger?.LogWarning("The management script of {Id} was not regenerated: {Problem}", instance.Id, ex.Message);
            return new ScriptRepairEntry { Id = instance.Id, Outcome = ScriptRepairOutcome.Failed, Detail = ex.Message };
        }
    }

    private HookFile? HooksFor(InstanceConfig config) =>
        config.Runtime == BlueprintRuntime.Native ? HookFiles.Find(paths, config.Blueprint) : null;
}

/// <summary>Writes a script where an instance's runs it from.</summary>
public static class ScriptFile
{
    /// <summary>
    /// Writes the script through a staged file and a rename, executable by its owner and readable by
    /// others. A script already running keeps its old file, because bash reads a script incrementally
    /// and a rename leaves the old inode untouched.
    /// </summary>
    public static void Write(string path, string text)
    {
        string staged = path + ".staged";
        File.WriteAllText(staged, text, new System.Text.UTF8Encoding(false));
        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(
                staged,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute
                | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
        }

        File.Move(staged, path, overwrite: true);
    }
}
