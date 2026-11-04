using TheKrystalShip.KGSM.ComponentConfig;
using System.CommandLine;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Operations;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>The <c>instance</c> noun, write side: install, uninstall, lifecycle, move, update, autostart, unlock, config set and the console.</summary>
internal static class InstanceWriteCommands
{
    public static void AddTo(Command instance, CommandHost host)
    {
        instance.Subcommands.Add(Install(host));
        instance.Subcommands.Add(Uninstall(host));
        instance.Subcommands.Add(Start(host));
        instance.Subcommands.Add(Stop(host));
        instance.Subcommands.Add(Restart(host));
        instance.Subcommands.Add(Move(host));
        instance.Subcommands.Add(Autostart(host, "enable", "Start an instance at boot, through the watchdog.", enable: true));
        instance.Subcommands.Add(Autostart(host, "disable", "Stop starting an instance at boot.", enable: false));
        instance.Subcommands.Add(Update(host));
        instance.Subcommands.Add(CheckUpdate(host));
        instance.Subcommands.Add(Unlock(host));
        instance.Subcommands.Add(Console(host));
    }

    [Action("kgsm:server.config.write", "Change server settings", DeclaredEffect.Write, DeclaredScope.Instance)]
    [Action("kgsm:server.windows.write", "Change maintenance windows", DeclaredEffect.Write, DeclaredScope.Instance)]
    public static Command ConfigSet(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var key = new Argument<string>("key") { Description = "The config key, camelCase as the config file spells it." };
        var value = new Argument<string>("value") { Description = "The new value; an empty string clears a text key." };
        var author = new Option<string>("--author") { Description = "For maintenanceWindows: who wrote them, as provider:name." };
        var authorName = new Option<string>("--author-name") { Description = "For maintenanceWindows: the author's display name." };

        return new Command("set", "Set one config key.") { reference, key, value, author, authorName }
            .ActOnInstance(host, "instance config set", reference, (context, instance) =>
            {
                ConfigSetReport report = new ConfigService(context.Services.Operations).Set(
                    instance, context.Parse.GetValue(key)!, context.Parse.GetValue(value)!,
                    context.Parse.GetValue(author), context.Parse.GetValue(authorName));

                return Task.FromResult<Outcome>(new Result<ConfigSetReport>(
                    report, EngineJsonContext.Default.ConfigSetReport,
                    r => r.Changed ? $"{r.Key} set" : $"{r.Key} already holds that value"));
            });
    }

    [Action("kgsm:server.install", "Install servers", DeclaredEffect.Write, DeclaredScope.Node)]
    private static Command Install(CommandHost host)
    {
        var blueprint = new Argument<string>("blueprint") { Description = "The blueprint's file name without .bp.yaml." };
        var id = new Option<string>("--id") { Description = "The instance id; generated from the blueprint when omitted." };
        var name = new Option<string>("--name") { Description = "A label for the instance." };
        var library = new Option<string>("--library") { Description = "The library to place it in; the default library, or the only one." };
        var version = new Option<string>("--game-version") { Description = "The game version to install; the latest when omitted." };
        var start = new Option<bool>("--start") { Description = "Start the instance once it is installed." };
        var skip = new Option<bool>("--skip-space-check") { Description = "Install even when the library has less room than the blueprint asks for." };

        return new Command("install", "Install an instance from a blueprint.") { blueprint, id, name, library, version, start, skip }
            .Act(host, "instance install", async context =>
            {
                var request = new InstallRequest(
                    context.Parse.GetValue(blueprint)!, context.Parse.GetValue(id), context.Parse.GetValue(name),
                    context.Parse.GetValue(library), context.Parse.GetValue(version), context.Parse.GetValue(start), context.Parse.GetValue(skip));

                InstallReport report = await new InstallService(context.Services.Operations).InstallAsync(request, context.Cancellation).ConfigureAwait(false);
                return new Result<InstallReport>(report, EngineJsonContext.Default.InstallReport, RenderInstall);
            });
    }

    [Action("kgsm:server.uninstall", "Uninstall servers", DeclaredEffect.Write, DeclaredScope.Instance)]
    private static Command Uninstall(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var force = new Option<bool>("--force") { Description = "Remove an instance whose run state or config cannot be read, or deregister one in an offline library." };
        var purge = new Option<bool>("--purge-backups") { Description = "Also delete the instance's backups." };
        var token = new Option<string>("--transfer-token") { Description = "The token of the transfer that holds the instance.", Hidden = true };

        return new Command("uninstall", "Stop an instance if it runs, then delete it.") { reference, force, purge, token }
            .ActOnInstance(host, "instance uninstall", reference, async (context, instance) =>
            {
                bool purgeBackups = context.Parse.GetValue(purge);
                string what = purgeBackups ? "its files and its backups" : "its files (its backups are kept)";
                if (context.Confirm($"Uninstall '{instance.Id}' and delete {what}?") is { } declined) return declined;

                UninstallReport report = await new UninstallService(context.Services.Operations).UninstallAsync(
                    instance, context.Parse.GetValue(force), purgeBackups, context.Parse.GetValue(token), context.Cancellation).ConfigureAwait(false);

                return new Result<UninstallReport>(report, EngineJsonContext.Default.UninstallReport, RenderUninstall);
            });
    }

    [Action("kgsm:server.start", "Start servers", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Start(CommandHost host) => Lifecycle(host, "start", "Start an instance.");

    [Action("kgsm:server.stop", "Stop servers", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Stop(CommandHost host) => Lifecycle(host, "stop", "Stop an instance, whoever runs it.");

    [Action("kgsm:server.restart", "Restart servers", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Restart(CommandHost host) => Lifecycle(host, "restart", "Stop an instance, then start it.");

    private static Command Lifecycle(CommandHost host, string verb, string description)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var force = new Option<bool>("--force") { Description = "Override the watchdog's memory admission check." };
        var command = verb == "stop" ? new Command(verb, description) { reference } : new Command(verb, description) { reference, force };

        return command.ActOnInstance(host, $"instance {verb}", reference, async (context, instance) =>
        {
            LifecycleService lifecycle = context.Services.Operations.Lifecycle;
            bool forced = verb != "stop" && context.Parse.GetValue(force);
            LifecycleReport report = verb switch
            {
                "start" => await lifecycle.StartAsync(instance, forced, context.Cancellation).ConfigureAwait(false),
                "stop" => await lifecycle.StopAsync(instance, context.Cancellation).ConfigureAwait(false),
                _ => await lifecycle.RestartAsync(instance, forced, context.Cancellation).ConfigureAwait(false),
            };

            return new Result<LifecycleReport>(report, EngineJsonContext.Default.LifecycleReport, RenderLifecycle);
        });
    }

    [Action("kgsm:server.move", "Move servers between libraries", DeclaredEffect.Write, DeclaredScope.Instance)]
    private static Command Move(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var library = new Argument<string>("library") { Description = "The library to move the instance to." };

        return new Command("move", "Move a stopped instance to another library.") { reference, library }
            .ActOnInstance(host, "instance move", reference, async (context, instance) =>
            {
                MoveReport report = await new MoveService(context.Services.Operations).MoveAsync(
                    instance, context.Parse.GetValue(library)!, context.Cancellation).ConfigureAwait(false);

                return new Result<MoveReport>(
                    report, EngineJsonContext.Default.MoveReport,
                    r => $"{r.Id} moved from {r.FromLibrary} to {r.ToLibrary} by {r.Method}\n{r.WorkingDirectory}");
            });
    }

    [Action("kgsm:server.config.write", "Change server settings", DeclaredEffect.Write, DeclaredScope.Instance)]
    private static Command Autostart(CommandHost host, string verb, string description, bool enable)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        return new Command(verb, description) { reference }
            .ActOnInstance(host, $"instance {verb}", reference, async (context, instance) =>
            {
                ActionReport report = await new InstanceAdminService(context.Services.Operations)
                    .SetAutostartAsync(instance, enable, context.Cancellation).ConfigureAwait(false);
                return new Result<ActionReport>(report, EngineJsonContext.Default.ActionReport, r => $"{r.Subject} {r.Message}");
            });
    }

    [Action("kgsm:server.update", "Update servers", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Update(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        return new Command("update", "Update an instance to the latest version, after a backup.") { reference }
            .ActOnInstance(host, "instance update", reference, async (context, instance) =>
            {
                UpdateReport report = await new UpdateService(context.Services.Operations).UpdateAsync(instance, context.Cancellation).ConfigureAwait(false);
                return new Result<UpdateReport>(report, EngineJsonContext.Default.UpdateReport, RenderUpdate);
            });
    }

    [Action("kgsm:server.read", "See servers", DeclaredEffect.Read, DeclaredScope.Instance)]
    private static Command CheckUpdate(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var emit = new Option<bool>("--emit") { Description = "Record the latest version and announce it once." };

        return new Command("check-update", "Ask whether a newer version exists.") { reference, emit }
            .ActOnInstance(host, "instance check-update", reference, async (context, instance) =>
            {
                UpdateCheckReport report = await new UpdateService(context.Services.Operations)
                    .CheckAsync(instance, context.Parse.GetValue(emit), context.Cancellation).ConfigureAwait(false);

                return new Result<UpdateCheckReport>(
                    report, EngineJsonContext.Default.UpdateCheckReport, RenderCheck,
                    report.Outcome == "unknown" ? ExitCodes.Failure : ExitCodes.Success);
            });
    }

    [Action("kgsm:server.export", "Transfer servers out", DeclaredEffect.Write, DeclaredScope.Instance)]
    private static Command Unlock(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var token = new Option<string>("--lock") { Description = "Release only if this token holds the lock; without it the lock is released whoever holds it." };
        return new Command("unlock", "Release the lock a transfer left on an instance and restore its autostart.") { reference, token }
            .ActOnInstance(host, "instance unlock", reference, async (context, instance) =>
            {
                ActionReport report = await new InstanceAdminService(context.Services.Operations)
                    .UnlockAsync(instance, context.Parse.GetValue(token), context.Cancellation).ConfigureAwait(false);
                return new Result<ActionReport>(report, EngineJsonContext.Default.ActionReport, r => $"{r.Subject}: {r.Message}");
            });
    }

    private static Command Console(CommandHost host)
    {
        var console = new Command("console", "An instance's console.");
        console.Subcommands.Add(Send(host));
        console.Subcommands.Add(Save(host));
        console.Subcommands.Add(Announce(host));
        console.Subcommands.Add(Kick(host));
        console.Subcommands.Add(Ban(host));
        console.Subcommands.Add(Unban(host));
        return console;
    }

    [Action("kgsm:server.console.write", "Send console commands", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Send(CommandHost host) =>
        Console(host, "send", "Send a line to the console.", "line", (service, instance, text, token) => service.SendAsync(instance, text, token));

    [Action("kgsm:server.announce", "Announce to players", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Announce(CommandHost host) =>
        Console(host, "announce", "Broadcast a message to the players.", "message", (service, instance, text, token) => service.AnnounceAsync(instance, text, token));

    [Action("kgsm:server.players.kick", "Kick players", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Kick(CommandHost host) =>
        Console(host, "kick", "Kick a player.", "target", (service, instance, text, token) => service.ModerateAsync(instance, ModerationVerb.Kick, text, token));

    [Action("kgsm:server.players.ban", "Ban and unban players", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Ban(CommandHost host) =>
        Console(host, "ban", "Ban a player.", "target", (service, instance, text, token) => service.ModerateAsync(instance, ModerationVerb.Ban, text, token));

    [Action("kgsm:server.players.ban", "Ban and unban players", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Unban(CommandHost host) =>
        Console(host, "unban", "Lift a player's ban.", "target", (service, instance, text, token) => service.ModerateAsync(instance, ModerationVerb.Unban, text, token));

    [Action("kgsm:server.console.write", "Send console commands", DeclaredEffect.Execute, DeclaredScope.Instance)]
    private static Command Save(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        return new Command("save", "Send the save command.") { reference }
            .ActOnInstance(host, "instance console save", reference, async (context, instance) =>
            {
                ActionReport report = await new ConsoleService(context.Services.Operations).SaveAsync(instance, context.Cancellation).ConfigureAwait(false);
                return new Result<ActionReport>(report, EngineJsonContext.Default.ActionReport, r => $"{r.Subject}: {r.Message}");
            });
    }

    private static Command Console(
        CommandHost host, string verb, string description, string argumentName,
        Func<ConsoleService, InstanceDescription, string, CancellationToken, Task<ActionReport>> send)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var text = new Argument<string[]>(argumentName) { Description = "The text; several words are joined with spaces.", Arity = ArgumentArity.OneOrMore };

        return new Command(verb, description) { reference, text }
            .ActOnInstance(host, $"instance console {verb}", reference, async (context, instance) =>
            {
                string line = string.Join(' ', context.Parse.GetValue(text)!);
                ActionReport report = await send(new ConsoleService(context.Services.Operations), instance, line, context.Cancellation).ConfigureAwait(false);
                return new Result<ActionReport>(report, EngineJsonContext.Default.ActionReport, r => $"{r.Subject}: {r.Message}");
            });
    }

    private static string RenderInstall(InstallReport report)
    {
        string text = $"{report.Id} installed from {report.Blueprint} in {report.Library}"
            + (report.Version is { } version ? $" at version {version}" : string.Empty)
            + $"\n{report.WorkingDirectory}";
        return report.Start is { } start ? text + "\n" + RenderLifecycle(start) : text;
    }

    private static string RenderUninstall(UninstallReport report) =>
        $"{report.Id} " + (report.FilesRemoved ? "uninstalled" : "deregistered, its files left where they are")
        + (report.Stopped ? "; it was running and was stopped first" : string.Empty)
        + (report.BackupsRemoved ? "; its backups were deleted" : string.Empty);

    private static string RenderLifecycle(LifecycleReport report)
    {
        string verb = report.Action switch { "start" => "started", "stop" => "stopped", _ => "restarted" };
        string how = report.Changed ? verb : report.Message ?? "unchanged";
        string via = report.Action == "stop" ? string.Empty : report.Supervised ? " (supervised by the watchdog)" : report.Via == "script" && report.Changed ? " (unsupervised)" : string.Empty;
        return $"{report.Id} {how}{via}";
    }

    private static string RenderUpdate(UpdateReport report) => report.Outcome == "updated"
        ? $"{report.Id} updated from {report.PreviousVersion ?? "unknown"} to {report.Version}" + (report.Backup is { } backup ? $"\nbackup before the update: {backup}" : string.Empty)
        : $"{report.Id} is up to date at {report.Version}";

    private static string RenderCheck(UpdateCheckReport report) => report.Outcome switch
    {
        "available" => $"{report.Id}: update available, {report.Current ?? "unknown"} -> {report.Latest}" + (report.Announced ? " (announced)" : string.Empty),
        "current" => $"{report.Id}: up to date at {report.Current ?? report.Latest}",
        _ => $"{report.Id}: unknown, upstream gave no answer",
    };
}
