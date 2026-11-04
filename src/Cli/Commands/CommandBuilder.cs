using System.CommandLine;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Instances;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>Shared pieces of the command tree.</summary>
internal static class CommandBuilder
{
    /// <summary>Gives <paramref name="command"/> its action: the host runs <paramref name="action"/> and renders the outcome.</summary>
    public static Command Act(
        this Command command, CommandHost host, string name, Func<CommandContext, Task<Outcome>> action, bool gated = true)
    {
        command.SetAction((parse, cancellation) => host.RunAsync(parse, name, gated, action, cancellation));
        return command;
    }

    /// <summary>
    /// Gives <paramref name="command"/> an action that runs on the instance <paramref name="reference"/> names:
    /// the instance is resolved first, and an unknown one ends the command with not-found.
    /// </summary>
    public static Command ActOnInstance(
        this Command command, CommandHost host, string name, Argument<string> reference,
        Func<CommandContext, InstanceDescription, Task<Outcome>> body)
    {
        return command.Act(host, name, async context =>
        {
            InstanceDescription? instance = Resolve(context, context.Parse.GetValue(reference)!, out Outcome? failure);
            return instance is null ? failure! : await body(context, instance).ConfigureAwait(false);
        });
    }

    public static Argument<string> InstanceArgument() =>
        new("instance") { Description = "The instance's id or display name." };

    /// <summary>The instance an argument names, or a not-found failure.</summary>
    public static InstanceDescription? Resolve(CommandContext context, string reference, out Outcome? failure)
    {
        InstanceDescription? instance = context.Services.Instances.Resolve(reference);
        failure = instance is null ? Failure.NotFound($"No instance '{reference}' is registered.") : null;
        return instance;
    }

    public static string Text(string? value) => string.IsNullOrEmpty(value) ? "-" : value;
}
