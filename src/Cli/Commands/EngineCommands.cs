using TheKrystalShip.KGSM.ComponentConfig;
using System.CommandLine;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Instances;
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

        engine.Subcommands.Add(new Command("placeholders", "The values a launch argument may name.")
            .Act(host, "engine placeholders", _ => Task.FromResult<Outcome>(new Result<LaunchPlaceholderReport>(
                new LaunchPlaceholderReport { Keys = [.. InstancePlaceholders.Keys.Order(StringComparer.Ordinal)] },
                EngineJsonContext.Default.LaunchPlaceholderReport, report => string.Join('\n', report.Keys))), gated: false));

        var config = new Command("config", "The settings the engine runs with.");
        config.Subcommands.Add(ConfigList(host));
        config.Subcommands.Add(ConfigGet(host));
        config.Subcommands.Add(ConfigSet(host));

        engine.Subcommands.Add(config);
        return engine;
    }

    [Action("kgsm:engine.config.read", "Read the engine's settings", DeclaredEffect.Read, DeclaredScope.Node)]
    private static Command ConfigList(CommandHost host) =>
        new Command("list", "Every setting, its value and the source that set it.")
            .Act(host, "engine config list", context => Task.FromResult<Outcome>(new Result<IReadOnlyList<EngineSetting>>(
                SettingsView.List(context.Services.Configuration, context.Services.Paths),
                EngineJsonContext.Default.IReadOnlyListEngineSetting, Settings)));

    [Action("kgsm:engine.config.read", "Read the engine's settings", DeclaredEffect.Read, DeclaredScope.Node)]
    private static Command ConfigGet(CommandHost host)
    {
        var key = new Argument<string>("key") { Description = "The setting as Section:Key or Section__Key." };
        return new Command("get", "One setting.") { key }
            .Act(host, "engine config get", context =>
            {
                string name = context.Parse.GetValue(key)!;
                EngineSetting? setting = SettingsView.Find(context.Services.Configuration, context.Services.Paths, name);
                return Task.FromResult<Outcome>(setting is null
                    ? Failure.NotFound($"The engine has no setting '{name}'.")
                    : new Result<EngineSetting>(setting, EngineJsonContext.Default.EngineSetting, s => s.Value));
            });
    }

    private static Command ConfigSet(CommandHost host)
    {
        var key = new Argument<string>("key") { Description = "The setting as Section:Key." };
        var value = new Argument<string>("value") { Description = "The new value; an empty string clears a text setting." };
        return new Command("set", "Set one setting in the person's settings file.") { key, value }
            .Act(host, "engine config set", context =>
            {
                SettingChange change = SettingsWriter.Set(
                    context.Services.Paths, context.Services.Environment.Variables,
                    context.Parse.GetValue(key)!, context.Parse.GetValue(value)!);
                return Task.FromResult<Outcome>(new Result<SettingSetReport>(
                    new SettingSetReport { Key = change.Key, Stored = change.Stored, Changed = change.Changed, Effective = change.Effective },
                    EngineJsonContext.Default.SettingSetReport,
                    report => $"{report.Key} = {report.Stored}" + (report.Effective.Source == SettingSource.Environment ? $"\nan environment variable still sets it to {report.Effective.Value}" : string.Empty)));
            });
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
