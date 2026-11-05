using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;

namespace TheKrystalShip.KGSM.Engine.Contracts.Invocation;

/// <summary>Who acts and through which surface; both travel to the engine as <c>--actor</c> and <c>--origin</c>.</summary>
public readonly record struct EngineCaller(string? Actor = null, string? Origin = null);

/// <summary>Where the engine binary is and how it is run.</summary>
public sealed class EngineCliOptions
{
    /// <summary>The <c>kgsm</c> binary: a path, or a name found on <c>PATH</c>.</summary>
    public string BinaryPath { get; set; } = "kgsm";

    /// <summary>Environment variables set on every invocation (for example a data home).</summary>
    public IDictionary<string, string> Environment { get; set; } = new Dictionary<string, string>(StringComparer.Ordinal);

    /// <summary>Used when a call names no caller.</summary>
    public EngineCaller DefaultCaller { get; set; }
}

/// <summary>
/// The typed invocation of the <c>kgsm</c> binary for everything that changes engine state. Each method
/// runs one command with <c>--json</c> and reads the report the command prints through the engine's
/// registered types; a refusal is the command's exit code and error report in the result, never text to
/// parse. Reads do not come through here: they are in-process.
/// </summary>
public sealed class EngineCli(EngineCliOptions options, IEngineProcess? process = null)
{
    private readonly IEngineProcess _process = process ?? new SystemEngineProcess();

    public string BinaryPath => options.BinaryPath;

    // ── Instances ─────────────────────────────────────────────────────────────────────────────

    public Task<EngineResult<InstallReport>> InstallAsync(
        string blueprint, string? id = null, string? name = null, string? library = null, string? gameVersion = null,
        bool start = false, bool skipSpaceCheck = false, EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "instance", "install", blueprint };
        AddOption(args, "--id", id);
        AddOption(args, "--name", name);
        AddOption(args, "--library", library);
        AddOption(args, "--game-version", gameVersion);
        AddFlag(args, "--start", start);
        AddFlag(args, "--skip-space-check", skipSpaceCheck);
        return RunAsync(args, EngineJsonContext.Default.InstallReport, caller, null, cancellationToken);
    }

    public Task<EngineResult<UninstallReport>> UninstallAsync(
        string instance, bool force = false, bool purgeBackups = false, string? transferToken = null,
        EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "instance", "uninstall", instance, "--yes" };
        AddFlag(args, "--force", force);
        AddFlag(args, "--purge-backups", purgeBackups);
        AddOption(args, "--transfer-token", transferToken);
        return RunAsync(args, EngineJsonContext.Default.UninstallReport, caller, null, cancellationToken);
    }

    public Task<EngineResult<LifecycleReport>> StartAsync(
        string instance, bool force = false, EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "instance", "start", instance };
        AddFlag(args, "--force", force);
        return RunAsync(args, EngineJsonContext.Default.LifecycleReport, caller, null, cancellationToken);
    }

    public Task<EngineResult<LifecycleReport>> StopAsync(
        string instance, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "stop", instance], EngineJsonContext.Default.LifecycleReport, caller, null, cancellationToken);

    public Task<EngineResult<LifecycleReport>> RestartAsync(
        string instance, bool force = false, EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "instance", "restart", instance };
        AddFlag(args, "--force", force);
        return RunAsync(args, EngineJsonContext.Default.LifecycleReport, caller, null, cancellationToken);
    }

    public Task<EngineResult<MoveReport>> MoveAsync(
        string instance, string library, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "move", instance, library], EngineJsonContext.Default.MoveReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> EnableAsync(
        string instance, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "enable", instance], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> DisableAsync(
        string instance, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "disable", instance], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    public Task<EngineResult<UpdateReport>> UpdateAsync(
        string instance, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "update", instance], EngineJsonContext.Default.UpdateReport, caller, null, cancellationToken);

    /// <summary>Asks whether a newer version exists; exit 1 with a report means the answer is unknown.</summary>
    public Task<EngineResult<UpdateCheckReport>> CheckUpdateAsync(
        string instance, bool emit = false, EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "instance", "check-update", instance };
        AddFlag(args, "--emit", emit);
        return RunAsync(args, EngineJsonContext.Default.UpdateCheckReport, caller, null, cancellationToken);
    }

    /// <summary>Releases the transfer lock; without a token the lock is released whoever holds it.</summary>
    public Task<EngineResult<ActionReport>> UnlockAsync(
        string instance, string? lockToken = null, EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "instance", "unlock", instance };
        AddOption(args, "--lock", lockToken);
        return RunAsync(args, EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);
    }

    public Task<EngineResult<ScriptRepairReport>> RepairAsync(
        string? instance = null, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(instance is null ? ["instance", "repair", "--all"] : ["instance", "repair", instance],
            EngineJsonContext.Default.ScriptRepairReport, caller, null, cancellationToken);

    public Task<EngineResult<ConfigSetReport>> SetConfigAsync(
        string instance, string key, string value, string? author = null, string? authorName = null,
        EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "instance", "config", "set", instance, key, value };
        AddOption(args, "--author", author);
        AddOption(args, "--author-name", authorName);
        return RunAsync(args, EngineJsonContext.Default.ConfigSetReport, caller, null, cancellationToken);
    }

    // ── Console ───────────────────────────────────────────────────────────────────────────────

    public Task<EngineResult<ActionReport>> SendInputAsync(
        string instance, string line, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "console", "send", instance, line], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> SaveAsync(
        string instance, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "console", "save", instance], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> AnnounceAsync(
        string instance, string message, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "console", "announce", instance, message], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> KickAsync(
        string instance, string target, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "console", "kick", instance, target], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> BanAsync(
        string instance, string target, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "console", "ban", instance, target], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> UnbanAsync(
        string instance, string target, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["instance", "console", "unban", instance, target], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    // ── Backups ───────────────────────────────────────────────────────────────────────────────

    public Task<EngineResult<BackupCreateReport>> CreateBackupAsync(
        string instance, BackupReason reason = BackupReason.Manual, BackupRetention retention = BackupRetention.Prunable,
        EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["backup", "create", instance, "--reason", reason.ToWire(), "--retention", retention.ToWire()],
            EngineJsonContext.Default.BackupCreateReport, caller, null, cancellationToken);

    public Task<EngineResult<BackupRestoreReport>> RestoreBackupAsync(
        string instance, string backup, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["backup", "restore", instance, backup, "--yes"], EngineJsonContext.Default.BackupRestoreReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> DeleteBackupAsync(
        string instance, string backup, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["backup", "delete", instance, backup, "--yes"], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    /// <summary>Deletes the backups beyond the newest <paramref name="keep"/>; the instance's retention when null.</summary>
    public Task<EngineResult<BackupPruneReport>> PruneBackupsAsync(
        string instance, int? keep = null, EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "backup", "prune", instance, "--yes" };
        if (keep is { } count) AddOption(args, "--keep", count.ToString(System.Globalization.CultureInfo.InvariantCulture));
        return RunAsync(args, EngineJsonContext.Default.BackupPruneReport, caller, null, cancellationToken);
    }

    public Task<EngineResult<ActionReport>> PinBackupAsync(
        string instance, string backup, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["backup", "pin", instance, backup], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    public Task<EngineResult<ActionReport>> UnpinBackupAsync(
        string instance, string backup, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["backup", "unpin", instance, backup], EngineJsonContext.Default.ActionReport, caller, null, cancellationToken);

    // ── Blueprints and libraries ──────────────────────────────────────────────────────────────

    /// <summary>Adds a user blueprint from its YAML text.</summary>
    public Task<EngineResult<BlueprintWriteReport>> CreateBlueprintAsync(
        string name, string yaml, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["blueprint", "create", name], EngineJsonContext.Default.BlueprintWriteReport, caller, yaml, cancellationToken);

    /// <summary>Replaces a user blueprint with the YAML text.</summary>
    public Task<EngineResult<BlueprintWriteReport>> UpdateBlueprintAsync(
        string name, string yaml, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["blueprint", "update", name], EngineJsonContext.Default.BlueprintWriteReport, caller, yaml, cancellationToken);

    public Task<EngineResult<BlueprintWriteReport>> DeleteBlueprintAsync(
        string name, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["blueprint", "delete", name, "--yes"], EngineJsonContext.Default.BlueprintWriteReport, caller, null, cancellationToken);

    public Task<EngineResult<LibraryChangeReport>> AddLibraryAsync(
        string name, string path, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["library", "add", name, path], EngineJsonContext.Default.LibraryChangeReport, caller, null, cancellationToken);

    public Task<EngineResult<LibraryChangeReport>> RemoveLibraryAsync(
        string name, bool force = false, string? drainTo = null, EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "library", "remove", name, "--yes" };
        AddFlag(args, "--force", force);
        AddOption(args, "--drain", drainTo);
        return RunAsync(args, EngineJsonContext.Default.LibraryChangeReport, caller, null, cancellationToken);
    }

    public Task<EngineResult<LibraryChangeReport>> RenameLibraryAsync(
        string name, string newName, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["library", "rename", name, newName], EngineJsonContext.Default.LibraryChangeReport, caller, null, cancellationToken);

    // ── The journal ───────────────────────────────────────────────────────────────────────────

    /// <summary>Writes one of the engine's own event types to its journal.</summary>
    public Task<EngineResult<EmitReport>> EmitEventAsync(
        string type, string subject, IReadOnlyDictionary<string, string>? fields = null,
        EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "event", "emit", type, subject };
        if (fields is not null)
        {
            foreach ((string name, string value) in fields)
            {
                args.Add("--field");
                args.Add($"{name}={value}");
            }
        }

        return RunAsync(args, EngineJsonContext.Default.EmitReport, caller, null, cancellationToken);
    }

    public Task<EngineResult<JournalStatusReport>> JournalStatusAsync(
        EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["event", "journal", "status"], EngineJsonContext.Default.JournalStatusReport, caller, null, cancellationToken);

    public Task<EngineResult<JournalPruneReport>> PruneJournalAsync(
        EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["event", "journal", "prune", "--yes"], EngineJsonContext.Default.JournalPruneReport, caller, null, cancellationToken);

    public Task<EngineResult<JournalVerifyReport>> VerifyJournalAsync(
        EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["event", "journal", "verify"], EngineJsonContext.Default.JournalVerifyReport, caller, null, cancellationToken);

    // ── Transfer: the source ──────────────────────────────────────────────────────────────────

    /// <summary>
    /// The instance's manifest. With a <paramref name="lockToken"/> the instance is locked first under
    /// that token; every part and the commit name the same token.
    /// </summary>
    public Task<EngineResult<TransferManifest>> ExportManifestAsync(
        string instance, string? lockToken = null, EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "transfer", "export", instance, "--manifest" };
        AddOption(args, "--lock", lockToken);
        return RunAsync(args, EngineJsonContext.Default.TransferManifest, caller, null, cancellationToken);
    }

    /// <summary>
    /// Streams one part of a locked instance into <paramref name="destination"/>. The bytes are data only
    /// when the result's exit code is 0.
    /// </summary>
    public Task<EngineResult<ActionReport>> ExportPartAsync(
        string instance, string partId, string lockToken, Stream destination,
        EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        StreamAsync(["transfer", "export", instance, "--part", partId, "--lock", lockToken], null, destination, caller, cancellationToken);

    public Task<EngineResult<ExportCommitReport>> CommitExportAsync(
        string instance, string lockToken, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["transfer", "export", instance, "--commit", "--lock", lockToken], EngineJsonContext.Default.ExportCommitReport, caller, null, cancellationToken);

    // ── Transfer: the target ──────────────────────────────────────────────────────────────────

    /// <summary>
    /// Every reason this node would refuse the manifest. The verdict is the value whether or not the
    /// exit code is zero.
    /// </summary>
    public Task<EngineResult<ImportVerdict>> ImportCheckAsync(
        TransferManifest manifest, string? library = null, string? blueprintSuffix = null,
        EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "transfer", "import", "check" };
        AddOption(args, "--library", library);
        AddOption(args, "--blueprint-suffix", blueprintSuffix);
        return RunAsync(args, EngineJsonContext.Default.ImportVerdict, caller, JsonSerializer.Serialize(manifest, EngineJsonContext.Default.TransferManifest), cancellationToken);
    }

    /// <summary>Stages an import. A refusal carries the verdict in <see cref="ImportBeginResult.Verdict"/>.</summary>
    public async Task<EngineResult<ImportBeginResult>> ImportBeginAsync(
        TransferManifest manifest, string? library = null, string? blueprintSuffix = null,
        EngineCaller? caller = null, CancellationToken cancellationToken = default)
    {
        var args = new List<string> { "transfer", "import", "begin" };
        AddOption(args, "--library", library);
        AddOption(args, "--blueprint-suffix", blueprintSuffix);
        EngineProcessResult run = await RunRawAsync(args, caller, JsonSerializer.Serialize(manifest, EngineJsonContext.Default.TransferManifest), cancellationToken).ConfigureAwait(false);

        if (run.ExitCode == 0)
        {
            ImportBegun? begun = Parse(run.Stdout, EngineJsonContext.Default.ImportBegun);
            return new EngineResult<ImportBeginResult>
            {
                ExitCode = 0,
                Value = begun is null ? null : new ImportBeginResult { ImportId = begun.ImportId },
                Diagnostics = run.Stderr.Trim(),
            };
        }

        ImportVerdict? verdict = Parse(run.Stdout, EngineJsonContext.Default.ImportVerdict);
        return new EngineResult<ImportBeginResult>
        {
            ExitCode = run.ExitCode,
            Value = verdict is null ? null : new ImportBeginResult { Verdict = verdict },
            Error = Parse(run.Stderr, EngineJsonContext.Default.ErrorReport),
            Diagnostics = run.Stderr.Trim(),
        };
    }

    /// <summary>Reads one part from <paramref name="source"/> into a staged import.</summary>
    public Task<EngineResult<ActionReport>> ImportPartAsync(
        string importId, string partId, Stream source, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        StreamAsync(["transfer", "import", "part", importId, partId], source, null, caller, cancellationToken);

    public Task<EngineResult<ImportedInstance>> ImportFinishAsync(
        string importId, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["transfer", "import", "finish", importId], EngineJsonContext.Default.ImportedInstance, caller, null, cancellationToken);

    public Task<EngineResult<ImportAbortReport>> ImportAbortAsync(
        string importId, EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["transfer", "import", "abort", importId], EngineJsonContext.Default.ImportAbortReport, caller, null, cancellationToken);

    public Task<EngineResult<IReadOnlyList<StagedImport>>> ListImportsAsync(
        EngineCaller? caller = null, CancellationToken cancellationToken = default) =>
        RunAsync(["transfer", "import", "list"], EngineJsonContext.Default.IReadOnlyListStagedImport, caller, null, cancellationToken);

    // ── Mechanism ─────────────────────────────────────────────────────────────────────────────

    private async Task<EngineResult<T>> RunAsync<T>(
        IReadOnlyList<string> command, JsonTypeInfo<T> typeInfo, EngineCaller? caller, string? input, CancellationToken cancellationToken)
    {
        EngineProcessResult run = await RunRawAsync(command, caller, input, cancellationToken).ConfigureAwait(false);
        return new EngineResult<T>
        {
            ExitCode = run.ExitCode,
            Value = Parse(run.Stdout, typeInfo),
            Error = run.ExitCode == 0 ? null : Parse(run.Stderr, EngineJsonContext.Default.ErrorReport),
            Diagnostics = run.Stderr.Trim(),
        };
    }

    private async Task<EngineResult<ActionReport>> StreamAsync(
        IReadOnlyList<string> command, Stream? source, Stream? destination, EngineCaller? caller, CancellationToken cancellationToken)
    {
        EngineStreamResult run = await _process
            .RunStreamingAsync(options.BinaryPath, Arguments(command, caller), Environment(caller), source, destination, cancellationToken)
            .ConfigureAwait(false);

        return new EngineResult<ActionReport>
        {
            ExitCode = run.ExitCode,
            Value = Parse(run.Stdout, EngineJsonContext.Default.ActionReport),
            Error = run.ExitCode == 0 ? null : Parse(run.Stderr, EngineJsonContext.Default.ErrorReport),
            Diagnostics = run.Stderr.Trim(),
        };
    }

    private Task<EngineProcessResult> RunRawAsync(
        IReadOnlyList<string> command, EngineCaller? caller, string? input, CancellationToken cancellationToken) =>
        _process.RunAsync(options.BinaryPath, Arguments(command, caller), Environment(caller), input, cancellationToken);

    private List<string> Arguments(IReadOnlyList<string> command, EngineCaller? caller)
    {
        var args = new List<string>(command) { "--json" };
        EngineCaller who = caller ?? options.DefaultCaller;
        AddOption(args, "--actor", who.Actor);
        AddOption(args, "--origin", who.Origin);
        return args;
    }

    private IReadOnlyDictionary<string, string> Environment(EngineCaller? caller) =>
        options.Environment.Count == 0
            ? new Dictionary<string, string>()
            : new Dictionary<string, string>(options.Environment, StringComparer.Ordinal);

    private static T? Parse<T>(string text, JsonTypeInfo<T> typeInfo)
    {
        if (string.IsNullOrWhiteSpace(text)) return default;
        try
        {
            return JsonSerializer.Deserialize(text, typeInfo);
        }
        catch (JsonException)
        {
            return default;
        }
    }

    private static void AddOption(List<string> args, string name, string? value)
    {
        if (string.IsNullOrEmpty(value)) return;
        args.Add(name);
        args.Add(value);
    }

    private static void AddFlag(List<string> args, string name, bool on)
    {
        if (on) args.Add(name);
    }
}

/// <summary>
/// The answer to staging an import: the id of the staged import, or the verdict that refused it.
/// </summary>
public sealed record ImportBeginResult
{
    public string? ImportId { get; init; }

    public ImportVerdict? Verdict { get; init; }
}

internal static class BackupWire
{
    public static string ToWire(this BackupReason reason) => reason switch
    {
        BackupReason.Scheduled => "scheduled",
        BackupReason.PreUpdate => "pre-update",
        BackupReason.PreRestore => "pre-restore",
        BackupReason.Incident => "incident",
        _ => "manual",
    };

    public static string ToWire(this BackupRetention retention) =>
        retention == BackupRetention.Pinned ? "pinned" : "prunable";
}
