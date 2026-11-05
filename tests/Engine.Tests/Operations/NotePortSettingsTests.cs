using System.Text.Json;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

/// <summary>The instance note, the install port override, the host's listening sockets and <c>engine config set</c>.</summary>
public class NotePortSettingsTests
{
    [Fact]
    public async Task ANote_RecordsTheEnginesActorAndTime_AndJournalsTheKey()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "note", "set", "g-1", "Mods:", "  install", "the pack \r\n first ", "--actor", "discord:123", "--json");

        Assert.Equal(0, run.Exit);
        NoteReport report = JsonSerializer.Deserialize(run.Out, EngineJsonContext.Default.NoteReport)!;
        Assert.Equal("Mods:   install the pack \n first", report.Note);
        Assert.Equal("discord:123", report.UpdatedBy);
        Assert.NotNull(report.UpdatedAt);
        InstanceConfig stored = fx.Find("g-1").Config!;
        Assert.Equal(report.Note, stored.Note);
        Assert.Equal("discord:123", stored.NoteUpdatedBy);
        Assert.Equal(["config.changed"], fx.Events());
    }

    [Fact]
    public async Task ANoteLongerThanTheLimitIsRefused_AndClearRemovesEverything()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun tooLong = await fx.Run("instance", "note", "set", "g-1", new string('x', InstanceNote.MaxLength + 1));
        Assert.NotEqual(0, tooLong.Exit);
        Assert.Null(fx.Find("g-1").Config!.Note);

        await fx.Run("instance", "note", "set", "g-1", "hello");
        CliRun cleared = await fx.Run("instance", "note", "clear", "g-1", "--json");

        Assert.Equal(0, cleared.Exit);
        InstanceConfig stored = fx.Find("g-1").Config!;
        Assert.Null(stored.Note);
        Assert.Null(stored.NoteUpdatedBy);
        Assert.Null(stored.NoteUpdatedAt);
    }

    [Fact]
    public async Task TheNoteKeysAreNotSettableThroughConfigSet()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();

        CliRun run = await fx.Run("instance", "config", "set", "g-1", "note", "x");

        Assert.Equal(1, run.Exit);
        Assert.Contains("protected", run.Err, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("34197", 34200, "34200")]
    [InlineData("7777/tcp|7777/udp", 7800, "7800/tcp|7800/udp")]
    [InlineData("27015:27016/udp", 27015, "27015:27016/udp")]
    [InlineData("27015:27016/udp|27017/tcp", 30000, "30000:27016/udp|27017/tcp")]
    [InlineData("25565|25575/tcp", 25600, "25600|25575/tcp")]
    [InlineData("", 8000, "8000")]
    public void TheInstallPortReplacesThePrimaryPortAndKeepsTheRest(string spec, int port, string expected) =>
        Assert.Equal(expected, PortSpecs.OverridePrimary(spec, port));

    [Fact]
    public async Task InstallWithAPortWritesItIntoTheConfig_AndRefusesOneOutOfRange()
    {
        var fx = OpsFixture.Create();

        CliRun bad = await fx.Run("instance", "install", "factorio", "--id", "fx-1", "--port", "70000");
        Assert.Equal(1, bad.Exit);
        Assert.False(fx.IsRegistered("fx-1"));

        CliRun ok = await fx.Run("instance", "install", "factorio", "--id", "fx-2", "--port", "34200", "--json");
        Assert.Equal(0, ok.Exit);
        Assert.Contains("34200", fx.Find("fx-2").Config!.Ports, StringComparison.Ordinal);
    }

    [Fact]
    public void ListeningSocketsAreReadFromProcNet_AndAProcessIsNamedOnlyWhenItCanBeSeen()
    {
        string proc = Sandbox.Create().PathFor("proc", "net", "tcp");
        string root = Path.GetDirectoryName(Path.GetDirectoryName(proc))!;
        File.WriteAllText(proc,
            "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n" +
            "   0: 00000000:1E61 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 11111 1 0 0\n" +
            "   1: 0100007F:0050 0100007F:9999 01 00000000:00000000 00:00000000 00000000  1000        0 22222 1 0 0\n");
        File.WriteAllText(Path.Combine(root, "net", "udp"),
            "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode ref pointer drops\n" +
            "   0: 00000000:85A5 00000000:0000 07 00000000:00000000 00:00000000 00000000  1000        0 33333 2 0 0\n");

        IReadOnlyList<ListeningPort> ports = HostSockets.Listening(root);

        Assert.Equal([(7777, "tcp"), (34213, "udp")], ports.Select(p => (p.Port, p.Protocol)));
        Assert.All(ports, p => Assert.Null(p.Process));
    }

    [Fact]
    public void EngineConfigSet_WritesOnlyWhatWasSet_ChecksFloors_AndReportsTheEffectiveSource()
    {
        var sandbox = Sandbox.Create();
        IReadOnlyDictionary<string, string?> env = new Dictionary<string, string?> { ["Downloads__TimeoutSeconds"] = "99" };
        sandbox.WriteFile(sandbox.Paths.SystemSettingsFile, "{ \"Downloads\": { \"TimeoutSeconds\": 60 }, \"Journal\": { \"RetentionDays\": 90 } }");

        var first = Engine.Settings.SettingsWriter.Set(sandbox.Paths, new Dictionary<string, string?>(), "Journal:RetentionDays", "30");
        Assert.True(first.Changed);
        Assert.Equal("30", first.Effective.Value);
        Assert.Equal(SettingSource.User, first.Effective.Source);
        string file = File.ReadAllText(sandbox.Paths.UserSettingsFile);
        Assert.Contains("RetentionDays", file, StringComparison.Ordinal);
        Assert.DoesNotContain("Downloads", file, StringComparison.Ordinal);

        Assert.False(Engine.Settings.SettingsWriter.Set(sandbox.Paths, new Dictionary<string, string?>(), "journal:retentiondays", "30").Changed);

        var overridden = Engine.Settings.SettingsWriter.Set(sandbox.Paths, env, "Downloads:TimeoutSeconds", "120");
        Assert.Equal(SettingSource.Environment, overridden.Effective.Source);
        Assert.Equal("99", overridden.Effective.Value);

        Assert.Throws<OperationException>(() => Engine.Settings.SettingsWriter.Set(sandbox.Paths, new Dictionary<string, string?>(), "Downloads:TimeoutSeconds", "0"));
        Assert.Throws<OperationException>(() => Engine.Settings.SettingsWriter.Set(sandbox.Paths, new Dictionary<string, string?>(), "Nothing:Here", "1"));
        Assert.Contains("\"TimeoutSeconds\": 120", File.ReadAllText(sandbox.Paths.UserSettingsFile), StringComparison.Ordinal);
    }
}
