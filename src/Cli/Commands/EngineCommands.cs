using System.CommandLine;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Journal;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>The <c>engine</c> noun: where the engine keeps things, which release it is, and how it is set.</summary>
internal static class EngineCommands
{
    public static Command Build(CommandHost host)
    {
        var engine = new Command("engine", "The engine itself.");

        engine.Subcommands.Add(new Command("paths", "Every directory and file the engine resolves.")
            .Act(host, "engine paths", context => Task.FromResult<Outcome>(new Result<Engine.Contracts.Paths.PathsReport>(
                context.Services.Paths.ToReport(), EngineJsonContext.Default.PathsReport, Paths)), gated: false));

        engine.Subcommands.Add(new Command("version", "The engine's release number.")
            .Act(host, "engine version", _ => Task.FromResult(Version()), gated: false));

        var config = new Command("config", "The settings the engine runs with.");
        config.Subcommands.Add(new Command("list", "Every setting, its value and the source that set it.")
            .Act(host, "engine config list", context => Task.FromResult<Outcome>(new Result<IReadOnlyList<EngineSetting>>(
                SettingsView.List(context.Services.Configuration, context.Services.Paths),
                EngineJsonContext.Default.IReadOnlyListEngineSetting, Settings))));

        var key = new Argument<string>("key") { Description = "The setting as Section:Key or Section__Key." };
        config.Subcommands.Add(new Command("get", "One setting.") { key }
            .Act(host, "engine config get", context =>
            {
                string name = context.Parse.GetValue(key)!;
                EngineSetting? setting = SettingsView.Find(context.Services.Configuration, context.Services.Paths, name);
                return Task.FromResult<Outcome>(setting is null
                    ? Failure.NotFound($"The engine has no setting '{name}'.")
                    : new Result<EngineSetting>(setting, EngineJsonContext.Default.EngineSetting, s => s.Value));
            }));

        engine.Subcommands.Add(config);
        return engine;
    }

    public static Outcome Version() => new Result<EngineVersionReport>(
        new EngineVersionReport { Version = EngineVersion.Current },
        EngineJsonContext.Default.EngineVersionReport, v => v.Version);

    private static string Paths(Engine.Contracts.Paths.PathsReport report) => Table.Fields(
    [
        ("config home", report.ConfigHome),
        ("data home", report.DataHome),
        ("state home", report.StateHome),
        ("install root", report.InstallRoot),
        ("user settings", report.UserSettingsFile),
        ("system settings", report.SystemSettingsFile),
        ("instance registry", report.InstanceRegistryFile),
        ("library registry", report.LibraryRegistryFile),
        ("user blueprints", report.UserBlueprintsDirectory),
        ("system blueprints", report.SystemBlueprintsDirectory),
        ("user overrides", report.UserOverridesDirectory),
        ("system overrides", report.SystemOverridesDirectory),
        ("default backups", report.DefaultBackupsDirectory),
        ("log directory", report.LogDirectory),
        ("log file", report.LogFile),
        ("locks", report.LocksDirectory),
        ("steam credentials", report.SteamCredentialsFile),
    ]);

    private static string Settings(IReadOnlyList<EngineSetting> settings) => Table.Render(
        ["KEY", "VALUE", "SOURCE"],
        settings.Select(s => new[] { s.Key, CommandBuilder.Text(s.Value), s.Source.ToString().ToLowerInvariant() }));
}
