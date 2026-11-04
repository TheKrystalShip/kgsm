using System.CommandLine;
using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Paths;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Cli;

/// <summary>
/// A stub: three read commands over the core, enough to publish the core as a Native-AOT binary. The
/// command tree, output stage and exit codes of the real CLI replace it.
/// </summary>
internal static class Program
{
    private static int Main(string[] args)
    {
        var root = new RootCommand("KGSM engine");

        var engine = new Command("engine", "The engine itself");

        var paths = new Command("paths", "Every directory and file the engine resolves");
        paths.SetAction(_ =>
        {
            Console.Out.WriteLine(JsonSerializer.Serialize(EnginePaths.FromProcess().ToReport(), EngineJsonContext.Default.PathsReport));
            return 0;
        });
        engine.Subcommands.Add(paths);

        var config = new Command("config", "The settings the engine runs with");
        config.SetAction(_ =>
        {
            var settings = EngineSettingsLoader.FromProcess().Settings;
            Console.Out.WriteLine($"Libraries:InstallFreeSpaceMarginMb={settings.Libraries.InstallFreeSpaceMarginMb}");
            Console.Out.WriteLine($"Journal:Directory={settings.Journal.Directory}");
            Console.Out.WriteLine($"Logging:File:MaxSizeKb={settings.Logging.File.MaxSizeKb}");
            return 0;
        });
        engine.Subcommands.Add(config);

        var blueprint = new Command("blueprint", "Blueprints");
        var list = new Command("list", "Every blueprint file by name");
        list.SetAction(_ =>
        {
            var catalog = new BlueprintCatalog(EnginePaths.FromProcess(), new BlueprintParser());
            foreach (var entry in catalog.List())
                Console.Out.WriteLine($"{entry.Key}\t{(entry.Blueprint is null ? "invalid" : "valid")}");
            return 0;
        });
        blueprint.Subcommands.Add(list);

        root.Subcommands.Add(engine);
        root.Subcommands.Add(blueprint);

        ParseResult parsed = root.Parse(args);
        return parsed.Errors.Count > 0 ? Usage(parsed) : parsed.Invoke();
    }

    private static int Usage(ParseResult parsed)
    {
        foreach (var error in parsed.Errors) Console.Error.WriteLine(error.Message);
        return 2;
    }
}
