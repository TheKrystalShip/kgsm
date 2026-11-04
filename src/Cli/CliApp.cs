using System.CommandLine;
using TheKrystalShip.KGSM.Cli.Commands;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;

namespace TheKrystalShip.KGSM.Cli;

/// <summary>
/// The command line: <c>kgsm &lt;noun&gt; &lt;verb&gt;</c> over the engine core. It parses with System.CommandLine,
/// renders what each command returns through the one output stage, and returns the exit code: 0, 1, 2 and
/// the codes that are contracts. A malformed command line is 2; System.CommandLine's own parse-error status
/// is 1, so the parse's errors are checked here.
/// </summary>
internal static class CliApp
{
    public static async Task<int> RunAsync(string[] args, CliEnvironment environment, TextWriter stdout, TextWriter stderr, CancellationToken cancellation)
    {
        var host = new CommandHost(environment, stdout, stderr);
        var root = new RootCommand("KGSM engine: install, run and manage game server instances.");

        // The built-in --version prints the assembly's informational version with its build metadata; the
        // engine's version is its release number, which `engine version` and --version both report.
        foreach (Option builtIn in root.Options.Where(o => o.Name == "--version").ToList()) root.Options.Remove(builtIn);
        var version = new Option<bool>("--version") { Description = "Show the engine's release number." };
        root.Options.Add(version);
        root.Options.Add(host.JsonOption);
        root.Options.Add(host.FormatOption);
        root.Options.Add(host.YesOption);
        root.Options.Add(host.ActorOption);
        root.Options.Add(host.OriginOption);

        root.Subcommands.Add(EngineCommands.Build(host));
        root.Subcommands.Add(InstanceCommands.Build(host));
        root.Subcommands.Add(BlueprintCommands.Build(host));
        root.Subcommands.Add(FleetCommands.Library(host));
        root.Subcommands.Add(FleetCommands.Backup(host));
        root.Subcommands.Add(FleetCommands.Port(host));
        root.Subcommands.Add(TransferCommands.Build(host));
        root.Subcommands.Add(EventCommands.Build(host));

        root.SetAction((parse, token) => host.RunAsync(
            parse, "kgsm", gated: false,
            action: _ => Task.FromResult<Outcome>(parse.GetValue(version)
                ? EngineCommands.Version()
                : Failure.Usage("A command is required; run kgsm --help.")),
            token));

        ParseResult parsed = root.Parse(args);
        if (parsed.Errors.Count > 0) return Usage(parsed, host, stdout, stderr);

        var invocation = new InvocationConfiguration { Output = stdout, Error = stderr };
        return await parsed.InvokeAsync(invocation, cancellation).ConfigureAwait(false);
    }

    private static int Usage(ParseResult parsed, CommandHost host, TextWriter stdout, TextWriter stderr)
    {
        var outcome = Failure.Of(
            ErrorCodes.Usage, parsed.Errors[0].Message, ExitCodes.Usage, [.. parsed.Errors.Skip(1).Select(e => e.Message)]);
        outcome.Write(host.FormatOf(parsed), stdout, stderr);
        return outcome.ExitCode;
    }
}
