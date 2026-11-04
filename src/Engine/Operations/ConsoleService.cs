using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Instances;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>The console verbs an instance understands, besides sending a raw line.</summary>
public enum ModerationVerb
{
    Kick,
    Ban,
    Unban,
}

/// <summary>
/// Writes to a running instance's console through its management script, the one implementation of the
/// console. Announcements and moderation need a running instance, and so do input and save. The journal
/// records what was sent: the line, or the command a template turned a message or a target into.
/// </summary>
public sealed class ConsoleService(OperationHost host)
{
    /// <summary>The longest announcement or moderation target, in characters.</summary>
    public const int MaxLength = 1000;

    public async Task<ActionReport> SendAsync(InstanceDescription instance, string line, CancellationToken cancellationToken)
    {
        await RequireRunningAsync(instance, "console send", cancellationToken).ConfigureAwait(false);
        await host.Script.RequireAsync(instance, ["input", line], "console send", cancellationToken).ConfigureAwait(false);

        host.Events.Append(new InputSent { InstanceName = instance.Id, Command = line });
        return new ActionReport { Action = "send", Subject = instance.Id, Message = "sent to the console" };
    }

    public async Task<ActionReport> SaveAsync(InstanceDescription instance, CancellationToken cancellationToken)
    {
        await RequireRunningAsync(instance, "console save", cancellationToken).ConfigureAwait(false);
        await host.Script.RequireAsync(instance, ["save"], "console save", cancellationToken).ConfigureAwait(false);
        return new ActionReport { Action = "save", Subject = instance.Id, Message = "the save command was sent" };
    }

    public async Task<ActionReport> AnnounceAsync(InstanceDescription instance, string message, CancellationToken cancellationToken)
    {
        InstanceConfig config = await RequireRunningAsync(instance, "console announce", cancellationToken).ConfigureAwait(false);
        string command = ResolveBroadcast(config, message);

        await host.Script.RequireAsync(instance, ["announce", message], "console announce", cancellationToken).ConfigureAwait(false);

        host.Events.Append(new AnnouncementSent { InstanceName = instance.Id, Message = message, Command = command });
        return new ActionReport { Action = "announce", Subject = instance.Id, Message = "announced" };
    }

    public async Task<ActionReport> ModerateAsync(InstanceDescription instance, ModerationVerb verb, string target, CancellationToken cancellationToken)
    {
        InstanceConfig config = await RequireRunningAsync(instance, $"console {verb.ToString().ToLowerInvariant()}", cancellationToken).ConfigureAwait(false);
        string template = verb switch
        {
            ModerationVerb.Kick => config.KickCommand,
            ModerationVerb.Ban => config.BanCommand,
            _ => config.UnbanCommand,
        };
        string name = verb.ToString().ToLowerInvariant();
        string command = ResolveModeration(template, target, name);

        await host.Script.RequireAsync(instance, [name, target], $"console {name}", cancellationToken).ConfigureAwait(false);

        switch (verb)
        {
            case ModerationVerb.Kick:
                host.Events.Append(new PlayerKicked { InstanceName = instance.Id, Target = target, Command = command });
                break;
            case ModerationVerb.Ban:
                host.Events.Append(new PlayerBanned { InstanceName = instance.Id, Target = target, Command = command });
                break;
            default:
                host.Events.Append(new PlayerUnbanned { InstanceName = instance.Id, Target = target, Command = command });
                break;
        }

        return new ActionReport { Action = name, Subject = instance.Id, Message = $"{name} sent for {target}" };
    }

    /// <summary>The broadcast template with the message in place of <c>{message}</c>.</summary>
    internal static string ResolveBroadcast(InstanceConfig config, string message)
    {
        if (config.BroadcastCommand.Length == 0)
            throw OperationException.Refused($"the blueprint of '{config.Name}' has no broadcast command");
        if (!config.BroadcastCommand.Contains("{message}", StringComparison.Ordinal))
            throw OperationException.Refused("the broadcast command has no {message} placeholder");

        CheckLine(message, "an announcement");
        return config.BroadcastCommand.Replace("{message}", message, StringComparison.Ordinal);
    }

    /// <summary>The moderation template with the target in place of its one <c>{ip}</c>, <c>{name}</c> or <c>{id}</c>.</summary>
    internal static string ResolveModeration(string template, string target, string verb)
    {
        if (template.Length == 0) throw OperationException.Refused($"the blueprint has no {verb} command");
        CheckLine(target, "a target");

        string resolved = template
            .Replace("{ip}", target, StringComparison.Ordinal)
            .Replace("{name}", target, StringComparison.Ordinal)
            .Replace("{id}", target, StringComparison.Ordinal);
        return resolved == template
            ? throw OperationException.Refused($"the {verb} command has no {{ip}}, {{name}} or {{id}} placeholder")
            : resolved;
    }

    private static void CheckLine(string text, string what)
    {
        if (text.Length == 0) throw OperationException.Invalid($"{what} cannot be empty");
        if (text.Length > MaxLength) throw OperationException.Invalid($"{what} is longer than {MaxLength} characters");
        if (text.Contains('\n') || text.Contains('\r')) throw OperationException.Invalid($"{what} cannot hold a line break");
    }

    private async Task<InstanceConfig> RequireRunningAsync(InstanceDescription instance, string action, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.Config(instance);
        Guards.Online(instance, action);

        InstanceProcess process = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);
        if (process.State != RunState.Running)
        {
            throw OperationException.Refused(
                process.State == RunState.Stopped
                    ? $"{action} needs a running instance and '{instance.Id}' is stopped"
                    : $"{action} needs a running instance and whether '{instance.Id}' runs cannot be measured ({process.Detail ?? "no answer"})");
        }

        return config;
    }
}
