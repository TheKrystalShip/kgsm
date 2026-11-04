using System.Text;
using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Tests.Cli;
using TheKrystalShip.KGSM.Engine.Tests.Operations;

namespace TheKrystalShip.KGSM.Engine.Tests.Transfers;

/// <summary>
/// Two nodes, each a sandbox of its own with its own library, registry, journal and container runtime, and
/// the command lines that move an instance from one to the other the way a driver does: a manifest, a
/// check, a begin, each part streamed from the source's standard output into the target's standard input,
/// a finish and a commit.
/// </summary>
internal sealed class TransferWorld
{
    public const string Token = "transfer-1";

    private TransferWorld()
    {
        Source = OpsFixture.Create();
        Target = OpsFixture.Create();
    }

    public OpsFixture Source { get; }

    public OpsFixture Target { get; }

    public static TransferWorld Create() => new();

    /// <summary>A native Factorio on the source, with a world to save, a log, a version and one backup.</summary>
    public (InstanceDescription Instance, string WorkingDirectory) AddNative(string id = "fx-1", Func<InstanceConfig, InstanceConfig>? shape = null, bool ran = true)
    {
        (InstanceDescription instance, string wd) = Source.AddInstance(id, "factorio", shape: c => shape is null ? c with { Ports = "34197/tcp" } : shape(c with { Ports = "34197/tcp" }));
        Populate(wd, id, ran);
        Directory.CreateDirectory(Source.Backups(id));
        Source.Script.WriteBackup(wd, id, "manual");
        return (Source.Find(id), wd);
    }

    /// <summary>The system Factorio blueprint copied to the person's own as <c>mygame</c>, with hooks of the person's, and an instance of it.</summary>
    public (InstanceDescription Instance, string WorkingDirectory) AddCustom(string id = "my-1", string hooks = "kgsm_hook_latest_version() { echo 1; }\n")
    {
        WriteCustomBlueprint(Source, "mygame", hooks);
        (InstanceDescription instance, string wd) = Source.AddInstance(id, "mygame", shape: c => c with { Ports = "34197/tcp" });
        Populate(wd, id, ran: true);
        Directory.CreateDirectory(Source.Backups(id));
        return (Source.Find(id), wd);
    }

    public static string WriteCustomBlueprint(OpsFixture node, string name, string? hooks = null, string comment = "")
    {
        string text = File.ReadAllText(Path.Combine(node.Sandbox.Paths.SystemBlueprintsDirectory, "factorio.bp.yaml")).Replace("name: factorio", "name: " + name, StringComparison.Ordinal) + comment;
        string file = node.Sandbox.WriteFile(Path.Combine(node.Sandbox.Paths.UserBlueprintsDirectory, name + ".bp.yaml"), text);
        if (hooks is not null) node.Sandbox.WriteFile(Path.Combine(node.Sandbox.Paths.UserOverridesDirectory, name, "hooks.sh"), hooks);
        return file;
    }

    /// <summary>A container instance on the source, whose image the source's runtime holds.</summary>
    public (InstanceDescription Instance, string WorkingDirectory, string Reference, ImageInfo Image) AddContainer(string id = "vr-1", bool ran = true)
    {
        (InstanceDescription instance, string wd) = Source.AddInstance(id, "vrising", shape: c => c with { Runtime = BlueprintRuntime.Container, Ports = "9876:9877/udp" });
        Populate(wd, id, ran);
        Directory.CreateDirectory(Path.Combine(wd, "events"));
        if (ran) File.WriteAllText(Path.Combine(wd, "events", "lifecycle.ndjson"), "{}\n");
        File.WriteAllText(new InstanceLayout(wd, id).ComposeFile, "services: {}\n");
        Directory.CreateDirectory(Source.Backups(id));
        const string Reference = "ghcr.io/thekrystalship/vrising:latest";
        ImageInfo image = Source.Session.Images.Add(Reference, "chain:aaaa1111", 4096);
        Source.Session.Images.Compose[new InstanceLayout(wd, id).ComposeFile] = [Reference];
        return (Source.Find(id), wd, Reference, image);
    }

    private static void Populate(string wd, string id, bool ran)
    {
        File.WriteAllText(Path.Combine(wd, "install", "game.bin"), "the game");
        Directory.CreateDirectory(Path.Combine(wd, "install", "data"));
        File.WriteAllText(Path.Combine(wd, "install", "data", "map.dat"), new string('m', 5000));
        File.WriteAllText(Path.Combine(wd, "saves", "world.zip"), "the world");
        if (ran)
        {
            File.WriteAllText(Path.Combine(wd, "logs", "old.log"), "an earlier run");
            File.WriteAllText(new InstanceLayout(wd, id).LogFile, "started\n");
        }

        File.WriteAllText(new InstanceLayout(wd, id).LatestVersionFile, "1.0.0\n");
    }

    // --- the source's commands ---

    public Task<CliRun> Manifest(string id, string? token = Token) =>
        token is null
            ? Source.Run("transfer", "export", id, "--manifest", "--json")
            : Source.Run("transfer", "export", id, "--manifest", "--lock", token, "--json");

    public async Task<TransferManifest> LockedManifest(string id = "fx-1", string token = Token)
    {
        CliRun run = await Manifest(id, token);
        Assert.Equal(0, run.Exit);
        return ReadManifest(run.Out);
    }

    public static TransferManifest ReadManifest(string json) =>
        JsonSerializer.Deserialize(json, EngineJsonContext.Default.TransferManifest) ?? throw new InvalidOperationException("null manifest");

    public static string Write(TransferManifest manifest) => JsonSerializer.Serialize(manifest, EngineJsonContext.Default.TransferManifest);

    /// <summary>A part as the source streams it, and the run that produced it.</summary>
    public async Task<(CliRun Run, byte[] Bytes)> Part(string id, string part, string token = Token)
    {
        Source.Session.RawStdout = new MemoryStream();
        CliRun run = await Source.Run("transfer", "export", id, "--part", part, "--lock", token);
        return (run, Source.Session.RawStdout.ToArray());
    }

    public Task<CliRun> Commit(string id, string token = Token) => Source.Run("transfer", "export", id, "--commit", "--lock", token, "--json");

    // --- the target's commands ---

    public Task<CliRun> Check(TransferManifest manifest, params string[] options) => WithManifest(manifest, ["transfer", "import", "check", "--json", .. options]);

    public async Task<CliRun> Begin(TransferManifest manifest, params string[] options) =>
        await WithManifest(manifest, ["transfer", "import", "begin", "--json", .. options]);

    private async Task<CliRun> WithManifest(TransferManifest manifest, string[] args)
    {
        Target.Session.Stdin = new StringReader(Write(manifest));
        return await Target.Run(args);
    }

    public async Task<string> BeginOk(TransferManifest manifest, params string[] options)
    {
        CliRun run = await Begin(manifest, options);
        Assert.True(run.Exit == 0, run.Out + run.Err);
        return JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.ImportBegun)!.ImportId;
    }

    public async Task<CliRun> Load(string importId, string part, byte[] bytes)
    {
        Target.Session.RawStdin = new MemoryStream(bytes);
        return await Target.Run("transfer", "import", "part", importId, part, "--json");
    }

    /// <summary>Streams every part of the manifest from the source into the staged import.</summary>
    public async Task LoadAll(string importId, TransferManifest manifest, string sourceId = "fx-1")
    {
        foreach (TransferPart part in manifest.Parts)
        {
            (CliRun made, byte[] bytes) = await Part(sourceId, part.Id);
            Assert.True(made.Exit == 0, made.Err);
            CliRun loaded = await Load(importId, part.Id, bytes);
            Assert.True(loaded.Exit == 0, loaded.Err);
        }
    }

    public Task<CliRun> Finish(string importId) => Target.Run("transfer", "import", "finish", importId, "--json");

    /// <summary>A full transfer up to the finish: lock, check, begin, every part.</summary>
    public async Task<(string ImportId, TransferManifest Manifest)> Stage(string sourceId = "fx-1", params string[] beginOptions)
    {
        TransferManifest manifest = await LockedManifest(sourceId);
        string importId = await BeginOk(manifest, beginOptions);
        await LoadAll(importId, manifest, sourceId);
        return (importId, manifest);
    }

    public ImportedInstance Imported(CliRun finish)
    {
        Assert.True(finish.Exit == 0, finish.Out + finish.Err);
        return JsonSerializer.Deserialize(finish.Out, EngineJsonContext.Default.ImportedInstance)!;
    }

    public static ErrorReport Error(CliRun run) =>
        JsonSerializer.Deserialize(run.Err, EngineJsonContext.Default.ErrorReport) ?? throw new InvalidOperationException("null");

    public static ImportVerdict Verdict(CliRun run) =>
        JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.ImportVerdict) ?? throw new InvalidOperationException("null");

    /// <summary>The staging directories below the target's main library.</summary>
    public string[] Staged() =>
        Directory.Exists(Path.Combine(Target.Main.Path, ".kgsm-import"))
            ? [.. Directory.EnumerateDirectories(Path.Combine(Target.Main.Path, ".kgsm-import"))]
            : [];

    public static byte[] Utf8(string text) => Encoding.UTF8.GetBytes(text);

    /// <summary>An image stream as the source writes it: the saved bytes and the trailer that seals them.</summary>
    public static byte[] Sealed(string text) => [.. Utf8(text), .. ImageStreamTests.TrailerFor(Utf8(text))];
}
