using System.CommandLine;
using System.Diagnostics;
using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine;
using TheKrystalShip.KGSM.Engine.Accounts;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Journal;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Cli;

/// <summary>What a command's action sees: the parse, the wired modules, who is acting and the way to be cancelled.</summary>
internal sealed class CommandContext(
    ParseResult parse, EngineServices services, Provenance provenance, TextWriter output, CancellationToken cancellation,
    CliEnvironment environment, bool yes)
{
    /// <summary>What the command reads from standard input.</summary>
    public TextReader Input => environment.Stdin ?? Console.In;

    /// <summary>The bytes a command streams out; only a transfer part writes here.</summary>
    public Stream RawOutput => environment.RawStdout ?? Console.OpenStandardOutput();

    /// <summary>The bytes a command streams in; only a transfer part reads from here.</summary>
    public Stream RawInput => environment.RawStdin ?? Console.OpenStandardInput();

    /// <summary>
    /// Asks before something destructive. With <c>--yes</c> it is settled; at a terminal the person is asked;
    /// with neither the command is refused with exit 2 and told to pass <c>--yes</c>.
    /// </summary>
    /// <returns>Null when confirmed, otherwise the failure that ends the command.</returns>
    public Outcome? Confirm(string question)
    {
        if (yes) return null;
        if (!environment.Interactive)
            return Failure.Usage($"{question} Nothing is asked without a terminal; pass --yes to confirm.");

        bool answer = environment.Ask is { } ask ? ask(question) : ConsolePrompt(question);
        return answer ? null : Failure.Of(ErrorCodes.Refused, "cancelled: nothing was changed");
    }

    private static bool ConsolePrompt(string question)
    {
        Console.Error.Write($"{question} [y/N] ");
        string? reply = Console.In.ReadLine();
        return reply is not null && reply.Trim().Equals("y", StringComparison.OrdinalIgnoreCase)
            || reply is not null && reply.Trim().Equals("yes", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Stdout, for the one kind of command whose result is a stream: following a log.</summary>
    public TextWriter Output => output;

    public ParseResult Parse => parse;

    public EngineServices Services => services;

    public Provenance Provenance => provenance;

    public CancellationToken Cancellation => cancellation;
}

/// <summary>
/// Runs a command's action and renders what it returns. It owns what every command shares: the
/// registry-account gate, the mapping from the engine's refusals to error reports and exit codes, the
/// engine's log line, and the output stage.
/// </summary>
internal sealed class CommandHost(CliEnvironment environment, TextWriter stdout, TextWriter stderr)
{
    public Option<bool> JsonOption { get; } = new("--json") { Description = "Write the result as JSON.", Recursive = true };

    public Option<string> FormatOption { get; } = new("--format")
    {
        Description = "Output format: text or json.",
        Recursive = true,
    };

    public Option<bool> YesOption { get; } = new("--yes") { Description = "Confirm a destructive command without asking.", Recursive = true };

    public Option<string> ActorOption { get; } = new("--actor") { Description = "Who acts, as provider:name.", Recursive = true };

    public Option<string> OriginOption { get; } = new("--origin")
    {
        Description = "The surface the action came through: " + string.Join(", ", Provenance.Origins) + ".",
        Recursive = true,
    };

    public CliEnvironment Environment => environment;

    /// <summary>
    /// Who is acting. <c>--actor</c> and <c>--origin</c> win; then the <c>KGSM_EVENT_ACTOR</c> and
    /// <c>KGSM_EVENT_ORIGIN</c> a calling script or service sets; and at a terminal the actor is the local
    /// account. Nothing else is invented.
    /// </summary>
    private Provenance Acting(ParseResult parse)
    {
        string? actor = parse.GetValue(ActorOption) ?? environment.Variable("KGSM_EVENT_ACTOR");
        string? origin = parse.GetValue(OriginOption) ?? environment.Variable("KGSM_EVENT_ORIGIN");
        if (actor is null && environment.Interactive) actor = $"local:{environment.UserName}";

        return new Provenance(actor, origin).Normalized();
    }

    public OutputFormat FormatOf(ParseResult parse) =>
        parse.GetValue(JsonOption) || string.Equals(parse.GetValue(FormatOption), "json", StringComparison.OrdinalIgnoreCase)
            ? OutputFormat.Json
            : OutputFormat.Text;

    /// <summary>Whether the format option names something other than the two formats.</summary>
    public string? FormatProblem(ParseResult parse) =>
        parse.GetValue(FormatOption) is { } format && !format.Equals("json", StringComparison.OrdinalIgnoreCase) && !format.Equals("text", StringComparison.OrdinalIgnoreCase)
            ? $"'{format}' is not an output format; use text or json"
            : null;

    /// <summary>Runs <paramref name="action"/> for a command and returns the exit code.</summary>
    /// <param name="parse">The parse of the command line.</param>
    /// <param name="name">The command's name, for the log.</param>
    /// <param name="gated">Whether the registry-account gate applies; only help, version and paths are exempt.</param>
    /// <param name="action">The command.</param>
    /// <param name="cancellation">Cancellation of the process.</param>
    public async Task<int> RunAsync(
        ParseResult parse, string name, bool gated, Func<CommandContext, Task<Outcome>> action, CancellationToken cancellation)
    {
        OutputFormat format = FormatOf(parse);
        var clock = Stopwatch.StartNew();

        using var services = new EngineServices(environment);
        Provenance provenance = Acting(parse);
        services.Provenance = provenance;
        Outcome outcome;
        ILogger? logger = null;

        try
        {
            if (FormatProblem(parse) is { } problem)
            {
                outcome = Failure.Usage(problem);
            }
            else
            {
                if (gated)
                {
                    logger = services.Loggers.CreateLogger("kgsm");
                    AccountVerdict verdict = (environment.AccountGate ?? RegistryAccountGate.Check)(
                        services.Settings.Journal.Directory, parse.Tokens.Select(t => t.Value).ToList());
                    if (!verdict.Allowed)
                    {
                        outcome = Failure.Of(ErrorCodes.WrongAccount, verdict.Message!);
                        return Finish(outcome, format, name, clock, logger);
                    }
                }

                outcome = await action(new CommandContext(parse, services, provenance, stdout, cancellation, environment, parse.GetValue(YesOption))).ConfigureAwait(false);
            }
        }
        catch (EngineException ex)
        {
            outcome = Describe(ex);
        }
        catch (OperationCanceledException)
        {
            outcome = Failure.Of(ErrorCodes.Failed, "cancelled", 130);
        }
        catch (Exception ex)
        {
            logger ??= TryLogger(services);
            logger?.LogError(ex, "kgsm {Command} failed unexpectedly", name);
            outcome = Failure.Of("internal", $"unexpected {ex.GetType().Name}: {ex.Message}");
        }

        logger ??= TryLogger(services);
        return Finish(outcome, format, name, clock, logger);
    }

    private int Finish(Outcome outcome, OutputFormat format, string name, Stopwatch clock, ILogger? logger)
    {
        outcome.Write(format, stdout, stderr);

        if (logger is not null)
        {
            string code = outcome is Failure failure ? failure.Report.Code : "ok";
            logger.LogInformation("kgsm {Command} exited {ExitCode} ({Code}) in {Elapsed} ms", name, outcome.ExitCode, code, clock.ElapsedMilliseconds);
        }

        return outcome.ExitCode;
    }

    /// <summary>The engine's log, or null when it cannot be opened: a command's answer does not depend on its log.</summary>
    private static ILogger? TryLogger(EngineServices services)
    {
        try
        {
            return services.Loggers.CreateLogger("kgsm");
        }
        catch (Exception ex) when (ex is EngineException or IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static Failure Describe(EngineException ex) => ex switch
    {
        AmbiguousInstanceException ambiguous => Failure.Of(ex.Code, ex.Message, ExitCodes.Failure, ambiguous.Candidates),
        InvalidSettingsException settings => Failure.Of(ex.Code, ex.Message, ExitCodes.Failure, settings.Problems),
        OperationException operation => Failure.Of(ex.Code, ex.Message, ex.ExitCode, operation.Details),
        _ => Failure.Of(ex.Code, ex.Message, ex.ExitCode),
    };
}
