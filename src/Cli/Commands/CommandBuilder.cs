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
