using System.Text.Json;
using System.Text.Json.Serialization;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Backups;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

/// <summary>The fields of a journal line the tests read.</summary>
internal sealed record JournalLine(string EventType, string? Severity, string? Outcome, string? Actor, string? Origin);

[JsonSerializable(typeof(JournalLine))]
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false)]
internal sealed partial class JournalLineJson : JsonSerializerContext;

/// <summary>
/// A stand-in for an instance's management script. It answers the verbs the engine calls with what the real
/// script leaves behind (a pid file, a version file, a backup directory with its manifest), so an operation
/// is tested for what the engine decides and writes and never for bash. The script itself is tested against
/// bash in <c>Scripts/</c>.
/// </summary>
internal sealed class ScriptEmulator
{
    private readonly CliSession _session;
    private readonly HashSet<int> _alive = [];
    private int _nextPid = 4200;

    public ScriptEmulator(CliSession session)
    {
        _session = session;
        session.Processes.Handler = Handle;
        session.ProcessAlive = pid => _alive.Contains(pid);
    }

    /// <summary>What <c>version --latest</c> and a download resolve to.</summary>
    public string Latest { get; set; } = "1.0.0";

    /// <summary>What <c>check-update</c> prints.</summary>
    public string CheckOutput { get; set; } = "current 1.0.0";

    /// <summary>What <c>update</c> prints; the version file is set to the version it names.</summary>
    public string UpdateOutput { get; set; } = "updated 2.0.0";

    /// <summary>Verbs (the first argument, or the first two joined for <c>version</c>) that exit 1 with a message.</summary>
    public Dictionary<string, string> Failures { get; } = [];

    /// <summary>Whether <c>start -d</c> leaves a live process behind.</summary>
    public bool StartsTheProcess { get; set; } = true;

    /// <summary>Every call to an instance's script as <c>id verb args</c>.</summary>
    public List<string> Calls { get; } = [];

    public bool IsAlive(int pid) => _alive.Contains(pid);

    /// <summary>Marks an instance as running, the way a start does.</summary>
    public int Run(string id, string workingDirectory)
    {
        int pid = _nextPid++;
        _alive.Add(pid);
        File.WriteAllText(new InstanceLayout(workingDirectory, id).PidFile, pid.ToString(System.Globalization.CultureInfo.InvariantCulture) + "\n");
        return pid;
    }

    private ProcessResult Handle(ProcessCall call)
    {
        if (!call.FileName.EndsWith(".manage.sh", StringComparison.Ordinal)) return new ProcessResult(0, string.Empty, string.Empty);

        string wd = call.WorkingDirectory!;
        string id = Path.GetFileName(call.FileName)[..^".manage.sh".Length];
        var layout = new InstanceLayout(wd, id);
        string[] a = [.. call.Arguments];
        Calls.Add($"{id} {string.Join(' ', a)}");

        string key = a[0] == "version" && a.Length > 1 ? $"version {a[1]}" : a[0];
        if (Failures.TryGetValue(key, out string? message)) return new ProcessResult(1, string.Empty, message + "\n");

        switch (a[0])
        {
            case "version" when a[1] == "--latest":
                return Ok(Latest);
            case "version" when a[1] == "--save":
                File.WriteAllText(layout.VersionFile, a[2] + "\n");
                return Ok();
            case "version" when a[1] == "--save-latest":
                File.WriteAllText(layout.LatestVersionFile, a[2] + "\n2026-11-04T12:00:00Z\n");
                return Ok();
            case "download":
                Directory.CreateDirectory(Path.Combine(layout.TempDirectory, "download"));
                File.WriteAllText(Path.Combine(layout.TempDirectory, "download", "game.bin"), a[1]);
                return Ok();
            case "deploy":
                File.Move(Path.Combine(layout.TempDirectory, "download", "game.bin"), Path.Combine(layout.InstallDirectory, "game.bin"), overwrite: true);
                return Ok();
            case "start":
                if (StartsTheProcess) Run(id, wd);
                return Ok();
            case "stop":
                if (File.Exists(layout.PidFile))
                {
                    _alive.Remove(int.Parse(File.ReadAllText(layout.PidFile).Trim(), System.Globalization.CultureInfo.InvariantCulture));
                    File.Delete(layout.PidFile);
                }

                return Ok();
            case "check-update":
                return new ProcessResult(CheckOutput == "unknown" ? 1 : 0, CheckOutput + "\n", string.Empty);
            case "update":
                if (UpdateOutput.StartsWith("updated ", StringComparison.Ordinal))
                {
                    WriteBackup(wd, id, reason: "pre-update");
                    File.WriteAllText(layout.VersionFile, UpdateOutput["updated ".Length..] + "\n");
                }

                return Ok(UpdateOutput);
            case "create-backup":
                return Ok(WriteBackup(wd, id, Option(a, "--reason") ?? "manual", Option(a, "--retention") ?? "prunable"));
            case "restore-backup":
                WriteBackup(wd, id, "pre-restore");
                return Ok();
            case "pin-backup" or "unpin-backup":
                Retention(wd, id, a[1], a[0] == "pin-backup" ? BackupRetention.Pinned : BackupRetention.Prunable);
                return Ok();
            default:
                return Ok();
        }
    }

    private static string? Option(string[] a, string name) => Array.IndexOf(a, name) is var i and >= 0 ? a[i + 1] : null;

    private static ProcessResult Ok(string output = "") => new(0, output.Length == 0 ? string.Empty : output + "\n", string.Empty);

    private string BackupsOf(string wd, string id)
    {
        InstanceConfig config = ContractFile.Read(
            new InstanceLayout(wd, id).ConfigFile, EngineJsonContext.Default.InstanceConfig, SchemaVersions.InstanceConfig, c => c.SchemaVersion);
        return config.BackupsDirectory;
    }

    /// <summary>Writes a backup directory with its manifest, as the script does, and returns its id.</summary>
    public string WriteBackup(string wd, string id, string reason, string retention = "prunable", DateTimeOffset? at = null)
    {
        string root = BackupsOf(wd, id);
        DateTimeOffset created = at ?? _session.Clock.GetUtcNow().AddSeconds(Calls.Count);
        string backupId = $"{id}-{created:yyyyMMddTHHmmss}Z-{Calls.Count:x6}";
        Directory.CreateDirectory(Path.Combine(root, backupId));

        var manifest = new BackupManifest
        {
            SchemaVersion = SchemaVersions.BackupManifest,
            Id = backupId,
            Instance = id,
            Blueprint = "g",
            Version = "1.0.0",
            CreatedAt = created,
            Reason = reason switch
            {
                "scheduled" => BackupReason.Scheduled,
                "pre-update" => BackupReason.PreUpdate,
                "pre-restore" => BackupReason.PreRestore,
                "incident" => BackupReason.Incident,
                _ => BackupReason.Manual,
            },
            Retention = retention == "pinned" ? BackupRetention.Pinned : BackupRetention.Prunable,
            Compressed = false,
            Sources = ["saves"],
            SizeBytes = 1,
            FileCount = 1,
        };
        ContractFile.Write(Path.Combine(root, backupId, "manifest.json"), manifest, EngineJsonContext.Default.BackupManifest);
        return backupId;
    }

    private void Retention(string wd, string id, string backupId, BackupRetention retention)
    {
        string path = Path.Combine(BackupsOf(wd, id), backupId, "manifest.json");
        BackupManifest manifest = ContractFile.Read(path, EngineJsonContext.Default.BackupManifest, SchemaVersions.BackupManifest, m => m.SchemaVersion);
        ContractFile.Write(path, manifest with { Retention = retention }, EngineJsonContext.Default.BackupManifest);
    }
}

/// <summary>One test's world for the write operations: a sandbox, a library, a script emulator and the fakes behind the doors.</summary>
internal sealed class OpsFixture
{
    private OpsFixture(CliSession session, LibraryRecord library)
    {
        Session = session;
        Main = library;
        Script = new ScriptEmulator(session);

        // Tests run without a watchdog unless one asks for it.
        session.Watchdog.SocketPresent = false;

        // Installs keep their backups where AddInstance puts them.
        session.Extra["Backups__Directory"] = Path.Combine(session.Sandbox.Root, "backups");
    }

    public CliSession Session { get; }

    public Sandbox Sandbox => Session.Sandbox;

    public LibraryRecord Main { get; }

    public ScriptEmulator Script { get; }

    public static OpsFixture Create(bool withBlueprints = true)
    {
        var sandbox = Sandbox.Create();
        var session = new CliSession(sandbox, withBlueprints);
        return new OpsFixture(session, sandbox.AddLibrary("main"));
    }

    public Task<CliRun> Run(params string[] args) => Session.RunAsync(args);

    /// <summary>Registers an instance and writes the files a real install leaves: config, script, version.</summary>
    public (InstanceDescription Instance, string WorkingDirectory) AddInstance(
        string id = "g-1", string blueprint = "g", LibraryRecord? library = null, Func<InstanceConfig, InstanceConfig>? shape = null)
    {
        LibraryRecord into = library ?? Main;
        (string wd, _) = Sandbox.AddInstance(into, blueprint, id, c => shape is null ? c : shape(c));
        Directory.CreateDirectory(Path.Combine(wd, "install"));
        Directory.CreateDirectory(Path.Combine(wd, "saves"));
        Directory.CreateDirectory(Path.Combine(wd, "logs"));
        Directory.CreateDirectory(Path.Combine(wd, "temp"));
        File.WriteAllText(new InstanceLayout(wd, id).VersionFile, "1.0.0\n");
        File.WriteAllText(new InstanceLayout(wd, id).ManagementScript, "#!/usr/bin/env bash\n");
        return (Find(id), wd);
    }

    public InstanceDescription Find(string id) =>
        new InstanceStore(Sandbox.Paths, new LibraryCatalog(Sandbox.Paths)).Find(id) ?? throw new InvalidOperationException($"no instance {id}");

    public bool IsRegistered(string id) =>
        new InstanceStore(Sandbox.Paths, new LibraryCatalog(Sandbox.Paths)).Registered().ContainsKey(id);

    /// <summary>The journal's lines in the order they were written.</summary>
    public IReadOnlyList<string> JournalText() =>
        !Directory.Exists(Sandbox.JournalDirectory)
            ? []
            : [.. Directory.EnumerateFiles(Sandbox.JournalDirectory, "*.ndjson").Order(StringComparer.Ordinal).SelectMany(File.ReadAllLines)];

    public IReadOnlyList<JournalLine> Journal() =>
        [.. JournalText().Select(l => JsonSerializer.Deserialize(l, JournalLineJson.Default.JournalLine)!)];

    /// <summary>The event types written so far, in order.</summary>
    public IReadOnlyList<string> Events() => [.. Journal().Select(l => l.EventType)];

    public string Backups(string id) => Sandbox.PathFor("backups", id);

    public void Simulate(string id, string workingDirectory) => Script.Run(id, workingDirectory);
}
