using System.CommandLine;
using System.Globalization;
using TheKrystalShip.KGSM.Cli.Output;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Cli.Commands;

/// <summary>The <c>instance</c> noun, read side: list, show, status, logs and config.</summary>
internal static class InstanceCommands
{
    private const int DefaultLogLines = 50;

    public static Command Build(CommandHost host)
    {
        var instance = new Command("instance", "Installed game server instances.");
        instance.Subcommands.Add(List(host));
        instance.Subcommands.Add(Show(host));
        instance.Subcommands.Add(Status(host));
        instance.Subcommands.Add(Logs(host));
        instance.Subcommands.Add(Config(host));
        instance.Subcommands.Add(Repair(host));
        InstanceWriteCommands.AddTo(instance, host);
        return instance;
    }

    private static Command List(CommandHost host) =>
        new Command("list", "Every registered instance.")
            .Act(host, "instance list", context =>
            {
                IReadOnlyList<InstanceSummary> summaries =
                [
                    .. context.Services.Instances.List().Select(i => new InstanceSummary
                    {
                        Id = i.Id,
                        Label = i.Config?.Label ?? i.Id,
                        Blueprint = i.Blueprint,
                        Runtime = i.Config?.Runtime,
                        Library = i.Library?.Name,
                        LibraryState = i.LibraryState,
                        ConfigProblem = i.ConfigProblem,
                    }),
                ];

                return Task.FromResult<Outcome>(new Result<IReadOnlyList<InstanceSummary>>(
                    summaries, EngineJsonContext.Default.IReadOnlyListInstanceSummary, RenderList));
            });

    private static Command Repair(CommandHost host)
    {
        var reference = new Argument<string>("instance")
        {
            Description = "The instance's id or display name; its script is rewritten whatever it holds.",
            Arity = ArgumentArity.ZeroOrOne,
        };
        var all = new Option<bool>("--all") { Description = "Regenerate the scripts that are stale, and only those." };

        return new Command("repair", "Regenerate an instance's management script.") { reference, all }
            .Act(host, "instance repair", context =>
            {
                string? named = context.Parse.GetValue(reference);
                bool everything = context.Parse.GetValue(all);
                if (everything == (named is not null))
                    return Task.FromResult<Outcome>(Failure.Usage("Name one instance, or pass --all."));

                IReadOnlyList<InstanceDescription> targets;
                if (named is not null)
                {
                    InstanceDescription? instance = CommandBuilder.Resolve(context, named, out Outcome? failure);
                    if (instance is null) return Task.FromResult(failure!);
                    targets = [instance];
                }
                else
                {
                    targets = context.Services.Instances.List();
                }

                ScriptRepairer repairer = context.Services.ScriptRepairer;
                IReadOnlyList<ScriptRepairEntry> entries = [.. targets.Select(i => repairer.Repair(i, onlyIfStale: everything))];
                bool failed = entries.Any(e => e.Outcome == ScriptRepairOutcome.Failed);

                return Task.FromResult<Outcome>(new Result<ScriptRepairReport>(
                    new ScriptRepairReport { Instances = entries },
                    EngineJsonContext.Default.ScriptRepairReport,
                    RenderRepair,
                    failed ? ExitCodes.Failure : ExitCodes.Success));
            });
    }

    private static string RenderRepair(ScriptRepairReport report) =>
        report.Instances.Count == 0
            ? "No instances."
            : Table.Render(
                ["INSTANCE", "SCRIPT", "DETAIL"],
                report.Instances.Select(e => new[] { e.Id, e.Outcome.ToString().ToLowerInvariant(), CommandBuilder.Text(e.Detail) }));

    private static Command Show(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        return new Command("show", "An instance's registry entry, library, paths, ports and config.") { reference }
            .Act(host, "instance show", context =>
            {
                InstanceDescription? instance = CommandBuilder.Resolve(context, context.Parse.GetValue(reference)!, out Outcome? failure);
                if (instance is null) return Task.FromResult(failure!);

                InstanceLayout layout = instance.Layout;
                var cgroup = context.Services.Settings.Cgroup;
                var info = new InstanceInfo
                {
                    Id = instance.Id,
                    Label = instance.Config?.Label ?? instance.Id,
                    Blueprint = instance.Blueprint,
                    Runtime = instance.Config?.Runtime,
                    Library = instance.Library is { } library ? new InstanceLibraryRef(library.Name, library.Id, library.Path) : null,
                    LibraryState = instance.LibraryState,
                    Paths = PathsOf(instance, layout),
                    CgroupPath = layout.CgroupPath(cgroup.MountPoint, cgroup.BaseName),
                    Ports = PortSpecs.Parse(instance.Config?.Ports),
                    Config = instance.Config,
                    ConfigProblem = instance.ConfigProblem,
                };

                return Task.FromResult<Outcome>(new Result<InstanceInfo>(info, EngineJsonContext.Default.InstanceInfo, RenderInfo));
            });
    }

    private static Command Status(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var disk = new Option<bool>("--disk") { Description = "Measure the bytes the working directory holds." };
        return new Command("status", "An instance's run state, version, ports, backups and recent output.") { reference, disk }
            .Act(host, "instance status", async context =>
            {
                InstanceDescription? instance = CommandBuilder.Resolve(context, context.Parse.GetValue(reference)!, out Outcome? failure);
                if (instance is null) return failure!;

                InstanceStatus status = await context.Services.Status
                    .ReadAsync(instance, context.Parse.GetValue(disk), context.Cancellation).ConfigureAwait(false);
                return new Result<InstanceStatus>(status, EngineJsonContext.Default.InstanceStatus, RenderStatus);
            });
    }

    private static Command Logs(CommandHost host)
    {
        Argument<string> reference = CommandBuilder.InstanceArgument();
        var lines = new Option<int>("--lines", "-n") { Description = "How many lines from the end.", DefaultValueFactory = _ => DefaultLogLines };
        var follow = new Option<bool>("--follow", "-f") { Description = "Keep printing as the instance writes." };
        return new Command("logs", "An instance's output.") { reference, lines, follow }
            .Act(host, "instance logs", async context =>
            {
                InstanceDescription? instance = CommandBuilder.Resolve(context, context.Parse.GetValue(reference)!, out Outcome? failure);
                if (instance is null) return failure!;
                if (instance.Config is null) return Failure.Of(ErrorCodes.Failed, instance.ConfigProblem ?? "the instance's config cannot be read");

                int count = context.Parse.GetValue(lines);
                if (count < 0) return Failure.Usage("--lines must not be negative");
                bool streaming = context.Parse.GetValue(follow);
                if (streaming && host.FormatOf(context.Parse) == OutputFormat.Json)
                    return Failure.Usage("--follow streams text and cannot be combined with --json");

                InstanceLayout layout = instance.Layout;
                if (instance.Config.Runtime == BlueprintRuntime.Container)
                    return await ContainerLogsAsync(context, instance, layout, count, streaming).ConfigureAwait(false);

                string? source = InstanceLogs.SourceFile(layout);
                if (source is null) return Failure.NotFound($"Instance '{instance.Id}' has written no log.");

                if (streaming) return await FollowAsync(source, count, context.Output, context.Cancellation).ConfigureAwait(false);

                return new Result<LogTail>(
                    new LogTail { Instance = instance.Id, File = source, Lines = InstanceLogs.Tail(source, count) },
                    EngineJsonContext.Default.LogTail, tail => string.Join('\n', tail.Lines));
            });
    }

    private static async Task<Outcome> ContainerLogsAsync(
        CommandContext context, InstanceDescription instance, InstanceLayout layout, int count, bool streaming)
    {
        if (!File.Exists(layout.ComposeFile)) return Failure.Of(ErrorCodes.Failed, "the compose file is missing");
        var containers = context.Services.Environment.Containers ?? new Engine.Status.DockerCompose();

        if (streaming)
        {
            int exit = await containers.FollowAsync(layout.ComposeFile, count, context.Cancellation).ConfigureAwait(false);
            return new Streamed(exit);
        }

        (IReadOnlyList<string>? lines, string? problem) = await containers.TailAsync(layout.ComposeFile, count, context.Cancellation).ConfigureAwait(false);
        return lines is null
            ? Failure.Of(ErrorCodes.Failed, problem!)
            : new Result<LogTail>(
                new LogTail { Instance = instance.Id, Lines = lines }, EngineJsonContext.Default.LogTail, tail => string.Join('\n', tail.Lines));
    }

    /// <summary>Prints the last lines, then whatever the file gains until the process is cancelled.</summary>
    private static async Task<Outcome> FollowAsync(string file, int count, TextWriter output, CancellationToken cancellation)
    {
        foreach (string line in InstanceLogs.Tail(file, count)) output.WriteLine(line);

        long position = new FileInfo(file).Length;
        try
        {
            while (!cancellation.IsCancellationRequested)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(250), cancellation).ConfigureAwait(false);
                if (!File.Exists(file)) continue;

                long length = new FileInfo(file).Length;
                if (length < position) position = 0; // rotated or truncated: start over
                if (length == position) continue;

                using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                stream.Seek(position, SeekOrigin.Begin);
                using var reader = new StreamReader(stream);
                string? text = await reader.ReadToEndAsync(cancellation).ConfigureAwait(false);
                output.Write(text);
                position = stream.Position;
            }
        }
        catch (OperationCanceledException)
        {
        }

        return new Streamed(0);
    }

    private static Command Config(CommandHost host)
    {
        var config = new Command("config", "An instance's configuration.");

        Argument<string> listed = CommandBuilder.InstanceArgument();
        config.Subcommands.Add(new Command("list", "Every config key with its value and whether it can be set.") { listed }
            .Act(host, "instance config list", context =>
            {
                InstanceConfig? values = ConfigOf(context, context.Parse.GetValue(listed)!, out Outcome? failure);
                if (values is null) return Task.FromResult(failure!);

                return Task.FromResult<Outcome>(new Result<IReadOnlyList<ConfigEntry>>(
                    InstanceConfigKeys.Entries(values), EngineJsonContext.Default.IReadOnlyListConfigEntry,
                    entries => Table.Render(["KEY", "VALUE", "SET"],
                        entries.Select(e => new[] { e.Key, CommandBuilder.Text(e.Value), e.Settable ? "yes" : "no" }))));
            }));

        Argument<string> got = CommandBuilder.InstanceArgument();
        var key = new Argument<string>("key") { Description = "The config key, camelCase as the config file spells it." };
        config.Subcommands.Add(new Command("get", "One config key.") { got, key }
            .Act(host, "instance config get", context =>
            {
                InstanceConfig? values = ConfigOf(context, context.Parse.GetValue(got)!, out Outcome? failure);
                if (values is null) return Task.FromResult(failure!);

                string name = context.Parse.GetValue(key)!;
                InstanceConfigKey? known = InstanceConfigKeys.Find(name);
                return Task.FromResult<Outcome>(known is null
                    ? Failure.NotFound($"An instance config has no key '{name}'.")
                    : new Result<ConfigEntry>(InstanceConfigKeys.Entry(known, values), EngineJsonContext.Default.ConfigEntry, e => e.Value ?? string.Empty));
            }));

        config.Subcommands.Add(InstanceWriteCommands.ConfigSet(host));
        return config;
    }

    private static InstanceConfig? ConfigOf(CommandContext context, string reference, out Outcome? failure)
    {
        InstanceDescription? instance = CommandBuilder.Resolve(context, reference, out failure);
        if (instance is null) return null;

        if (instance.Config is null)
        {
            failure = Failure.Of(ErrorCodes.Failed, instance.ConfigProblem ?? "the instance's config cannot be read");
            return null;
        }

        failure = null;
        return instance.Config;
    }

    private static InstancePaths PathsOf(InstanceDescription instance, InstanceLayout layout) => new()
    {
        WorkingDirectory = layout.WorkingDirectory,
        ConfigFile = layout.ConfigFile,
        ManagementScript = layout.ManagementScript,
        InstallDirectory = layout.InstallDirectory,
        SavesDirectory = layout.SavesDirectory,
        LogsDirectory = layout.LogsDirectory,
        TempDirectory = layout.TempDirectory,
        EventsDirectory = layout.EventsDirectory,
        LaunchDirectory = layout.LaunchDirectory,
        VersionFile = layout.VersionFile,
        LatestVersionFile = layout.LatestVersionFile,
        PidFile = layout.PidFile,
        InputFifo = layout.InputFifo,
        LogFile = layout.LogFile,
        ComposeFile = layout.ComposeFile,
        BackupsDirectory = instance.Config?.BackupsDirectory,
    };

    private static string RenderList(IReadOnlyList<InstanceSummary> summaries) => summaries.Count == 0
        ? "No instances are registered."
        : Table.Render(
            ["ID", "NAME", "BLUEPRINT", "RUNTIME", "LIBRARY", "STATE"],
            summaries.Select(s => new[]
            {
                s.Id,
                s.Label,
                s.Blueprint,
                s.Runtime is { } runtime ? runtime.ToString().ToLowerInvariant() : "-",
                CommandBuilder.Text(s.Library),
                s.LibraryState.ToString().ToLowerInvariant(),
            }));

    private static string RenderInfo(InstanceInfo info) => Table.Fields(
    [
        ("id", info.Id),
        ("name", info.Label),
        ("blueprint", info.Blueprint),
        ("runtime", info.Runtime is { } runtime ? runtime.ToString().ToLowerInvariant() : "unknown"),
        ("library", info.Library is { } library ? $"{library.Name} ({info.LibraryState.ToString().ToLowerInvariant()})" : "unregistered"),
        ("directory", info.Paths.WorkingDirectory),
        ("cgroup", info.CgroupPath),
        ("ports", RenderPorts(info.Ports)),
        ("backups", CommandBuilder.Text(info.Paths.BackupsDirectory)),
        ("config", info.Config is null ? $"unreadable: {info.ConfigProblem}" : info.Paths.ConfigFile),
    ]);

    private static string RenderStatus(InstanceStatus status)
    {
        InstanceProcess process = status.Process;
        string state = process.State.ToString().ToLowerInvariant()
            + (process.Pid is { } pid ? $" (pid {pid.ToString(CultureInfo.InvariantCulture)})" : string.Empty);

        string updates = status.Version.UpdatesAvailable switch
        {
            true => $"update available: {status.Version.Latest}",
            false => "up to date",
            null => "not checked",
        };

        var fields = new List<(string, string)>
        {
            ("instance", status.Id),
            ("state", state),
            ("source", process.Source == RunStateSource.PidFile ? "pid-file" : process.Source.ToString().ToLowerInvariant()),
        };
        if (process.Phase is not null) fields.Add(("phase", process.Phase));
        if (process.StartTime is { } started) fields.Add(("started", started.ToString("u", CultureInfo.InvariantCulture)));
        if (process.Detail is not null) fields.Add(("note", process.Detail));
        fields.Add(("version", CommandBuilder.Text(status.Version.Current)));
        fields.Add(("updates", updates));
        fields.Add(("blueprint", status.Configuration.Blueprint));
        fields.Add(("directory", status.Configuration.Directory));
        fields.Add(("ports", RenderPorts(status.Configuration.Ports)));
        if (status.DiskUsageBytes is { } bytes) fields.Add(("disk", bytes.ToString(CultureInfo.InvariantCulture) + " bytes"));
        fields.Add(("backups", status.Backups.Count.ToString(CultureInfo.InvariantCulture)));

        string text = Table.Fields(fields);
        return status.RecentLogs.Count == 0 ? text : text + "\n\nrecent output:\n" + string.Join('\n', status.RecentLogs.Select(l => "  " + l));
    }

    internal static string RenderPorts(IReadOnlyList<PortRange> ports) => ports.Count == 0
        ? "-"
        : string.Join(' ', ports.Select(p => (p.Start == p.End ? p.Start.ToString(CultureInfo.InvariantCulture) : $"{p.Start}-{p.End}") + "/" + p.Protocol.ToString().ToLowerInvariant()));
}

/// <summary>A command that wrote its own output as a stream and has only an exit code left to give.</summary>
internal sealed class Streamed(int exitCode) : Outcome
{
    public override int ExitCode => exitCode;

    public override void Write(OutputFormat format, TextWriter stdout, TextWriter stderr)
    {
    }
}
