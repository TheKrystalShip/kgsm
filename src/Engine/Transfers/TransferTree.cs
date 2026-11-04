using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Transfers;

/// <summary>Which files make up the tree part of an instance, on the source and in a staged import.</summary>
internal static class TransferTree
{
    public const string Instance = "instance";

    public const string Backups = "backups";

    public const string Blueprint = "blueprint";

    public const string Overrides = "overrides";

    /// <summary>
    /// The members of an instance's tree: its working directory without the files that only mean something
    /// while it runs, the backups when they live outside it, and for a custom blueprint its file and the
    /// person's hooks for the game.
    /// </summary>
    /// <param name="paths">The engine's paths.</param>
    /// <param name="instance">The instance.</param>
    /// <param name="config">Its config.</param>
    /// <param name="blueprintFile">The custom blueprint's file; null when the blueprint is the system's.</param>
    public static IReadOnlyList<TreeMember> Of(EnginePaths paths, InstanceDescription instance, InstanceConfig config, string? blueprintFile)
    {
        InstanceLayout layout = instance.Layout;
        var members = new List<TreeMember>
        {
            new(Instance, instance.WorkingDirectory, new HashSet<string>(StringComparer.Ordinal)
            {
                Path.GetFileName(layout.PidFile),
                Path.GetFileName(layout.InputFifo),
                Path.GetFileName(layout.TransferLockFile),
            }),
        };

        string backups = config.BackupsDirectory;
        if (backups.Length > 0 && Directory.Exists(backups) && !Libraries.LibraryRules.IsWithin(backups, instance.WorkingDirectory))
            members.Add(new TreeMember(Backups, backups));

        if (blueprintFile is not null && File.Exists(blueprintFile))
        {
            members.Add(new TreeMember($"{Blueprint}/{Path.GetFileName(blueprintFile)}", blueprintFile));

            string hooks = Path.Combine(paths.UserOverridesDirectory, config.Blueprint, Scripts.HookFiles.FileName);
            if (File.Exists(hooks)) members.Add(new TreeMember($"{Overrides}/{config.Blueprint}/{Scripts.HookFiles.FileName}", hooks));
        }

        return members;
    }

    /// <summary>The members of a staged tree, which holds the four top-level directories as they were extracted.</summary>
    public static IReadOnlyList<TreeMember> Staged(string treeDirectory) =>
    [
        new(Instance, Path.Combine(treeDirectory, Instance)),
        new(Backups, Path.Combine(treeDirectory, Backups)),
        new(Blueprint, Path.Combine(treeDirectory, Blueprint)),
        new(Overrides, Path.Combine(treeDirectory, Overrides)),
    ];
}
