using System.Diagnostics;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Journal;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Settings;
using TheKrystalShip.KGSM.Engine.Tests.Cli;

namespace TheKrystalShip.KGSM.Engine.Tests.Operations;

/// <summary>The firewall client: its command line, its environment and how it reads an exit status.</summary>
public class FirewallCliTests
{
    private static PortRange Range(int start, int end, PortProtocol protocol) => new() { Start = start, End = end, Protocol = protocol };

    private static (FirewallCli Client, FakeProcesses Processes) Client()
    {
        var processes = new FakeProcesses();
        return (new FirewallCli(processes, new FirewallSettings { Client = "/opt/fw/kgsm-firewall", Socket = "/run/fw.sock" }), processes);
    }

    [Fact]
    public async Task EnsureOpen_SpellsEachRangeTheWayTheClientReadsIt_AndHandsDownTheSocketAndTheProvenance()
    {
        var (client, processes) = Client();

        FirewallVerdict verdict = await client.EnsureOpenAsync(
            "g-1", [Range(34197, 34197, PortProtocol.Udp), Range(27015, 27020, PortProtocol.Tcp)],
            new Provenance("discord:haru", "ui"), CancellationToken.None);

        Assert.True(verdict.Ok);
        ProcessCall call = Assert.Single(processes.Calls);
        Assert.Equal("/opt/fw/kgsm-firewall", call.FileName);
        Assert.Equal(["ensure-open", "g-1", "34197/udp", "27015:27020/tcp"], call.Arguments);
        Assert.Equal("/run/fw.sock", call.Environment!["KGSM_FIREWALL_SOCKET"]);
        Assert.Equal("discord:haru", call.Environment["KGSM_EVENT_ACTOR"]);
        Assert.Equal("ui", call.Environment["KGSM_EVENT_ORIGIN"]);
    }

    [Fact]
    public async Task Remove_AsksForTheInstanceAlone_AndLeavesOutProvenanceThatWasNotGiven()
    {
        var (client, processes) = Client();

        await client.RemoveAsync("g-1", default, CancellationToken.None);

        ProcessCall call = Assert.Single(processes.Calls);
        Assert.Equal(["remove", "g-1"], call.Arguments);
        Assert.False(call.Environment!.ContainsKey("KGSM_EVENT_ACTOR"));
        Assert.False(call.Environment.ContainsKey("KGSM_EVENT_ORIGIN"));
    }

    [Theory]
    [InlineData(0, true, false)]
    [InlineData(3, false, true)]
    [InlineData(-1, false, true)]
    [InlineData(4, false, false)]
    [InlineData(5, false, false)]
    [InlineData(6, false, false)]
    public async Task AnExitStatus_IsReadAsSuccess_AnAuthorityThatDidNotAnswer_OrOneThatSaidNo(int exit, bool ok, bool unreachable)
    {
        var (client, processes) = Client();
        processes.Handler = _ => new ProcessResult(exit, string.Empty, "the reason\n");

        FirewallVerdict verdict = await client.RemoveAsync("g-1", default, CancellationToken.None);

        Assert.Equal((ok, unreachable), (verdict.Ok, verdict.Unreachable));
        if (!ok) Assert.Equal("the reason", verdict.Detail);
    }
}

/// <summary>Ports a compose file names.</summary>
public class ComposePortsTests
{
    [Fact]
    public void ShortSyntax_BecomesTheConfigsFormat_TcpWhenNoProtocolIsGiven()
    {
        string compose = """
            services:
              game:
                ports:
                  - 9876:9876/udp
                  - "27015:27016/tcp"
                  - 8080:80
                  - 127.0.0.1:2222:22/tcp
                  - 7000
                  - 7100-7110:7100-7110/udp
              helper:
                ports:
                  - 9876:9876/udp
            """;

        Assert.Equal("9876/udp|27015/tcp|8080/tcp|2222/tcp|7000/tcp|7100:7110/udp", ComposePorts.Derive(compose));
    }

    [Fact]
    public void AComposeWithoutPorts_OrWithAnUnreadableSyntax_DeclaresNone()
    {
        Assert.Equal(string.Empty, ComposePorts.Derive("services:\n  game:\n    image: x\n"));
        Assert.Equal(string.Empty, ComposePorts.Derive("services: [unclosed"));
        Assert.Equal(string.Empty, ComposePorts.Derive("services:\n  game:\n    ports:\n      - 99999:99999/tcp\n      - 80:80/sctp\n"));
    }
}

/// <summary>The copy a cross-device move relies on, and the facts about devices.</summary>
public class FileSystemTests
{
    private static string NewRoot() => Path.Combine(Path.GetTempPath(), "kgsm-fs-" + Guid.NewGuid().ToString("N"));

    [Fact]
    public void CopyTree_KeepsContentModesAndLinks_AndSkipsPipes()
    {
        string root = NewRoot();
        string from = Path.Combine(root, "from");
        string to = Path.Combine(root, "to");
        Directory.CreateDirectory(Path.Combine(from, "bin"));
        File.WriteAllText(Path.Combine(from, "bin", "run"), "#!/bin/sh\n");
        File.SetUnixFileMode(Path.Combine(from, "bin", "run"), UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        File.WriteAllText(Path.Combine(from, ".hidden"), "h");
        File.CreateSymbolicLink(Path.Combine(from, "latest"), "bin/run");
        File.CreateSymbolicLink(Path.Combine(from, "dir-link"), "bin");
        using (Process mkfifo = Process.Start("mkfifo", Path.Combine(from, ".g.sock"))!) mkfifo.WaitForExit();
        Directory.CreateDirectory(Path.Combine(from, "empty"));

        FileSystem.CopyTree(from, to, CancellationToken.None);

        Assert.Equal("#!/bin/sh\n", File.ReadAllText(Path.Combine(to, "bin", "run")));
        Assert.True(File.GetUnixFileMode(Path.Combine(to, "bin", "run")).HasFlag(UnixFileMode.UserExecute));
        Assert.Equal("h", File.ReadAllText(Path.Combine(to, ".hidden")));
        Assert.Equal("bin/run", new FileInfo(Path.Combine(to, "latest")).LinkTarget);
        Assert.Equal("bin", new FileInfo(Path.Combine(to, "dir-link")).LinkTarget);
        Assert.False(File.Exists(Path.Combine(to, ".g.sock")));
        Assert.True(Directory.Exists(Path.Combine(to, "empty")));
        Assert.Equal(File.GetLastWriteTimeUtc(Path.Combine(from, "bin", "run")), File.GetLastWriteTimeUtc(Path.Combine(to, "bin", "run")));
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public void CopyTree_ResumesACutShortCopy_ByRepeatingOnlyWhatIsMissingOrDiffers()
    {
        string root = NewRoot();
        string from = Path.Combine(root, "from");
        string to = Path.Combine(root, "to");
        Directory.CreateDirectory(from);
        File.WriteAllText(Path.Combine(from, "a"), "aaaa");
        File.WriteAllText(Path.Combine(from, "b"), "bbbb");
        File.WriteAllText(Path.Combine(from, "c"), "cccc");
        FileSystem.CopyTree(from, to, CancellationToken.None);

        // b is missing, c was cut short, a is whole (it carries different bytes of the same length and time,
        // which only a copy that skipped it can leave standing).
        File.Delete(Path.Combine(to, "b"));
        File.WriteAllText(Path.Combine(to, "c"), "cc");
        File.WriteAllText(Path.Combine(to, ".c.kgsm-partial"), "leftover");
        File.WriteAllText(Path.Combine(to, "a"), "XXXX");
        File.SetLastWriteTimeUtc(Path.Combine(to, "a"), File.GetLastWriteTimeUtc(Path.Combine(from, "a")));

        FileSystem.CopyTree(from, to, CancellationToken.None);

        Assert.Equal("bbbb", File.ReadAllText(Path.Combine(to, "b")));
        Assert.Equal("cccc", File.ReadAllText(Path.Combine(to, "c")));
        Assert.Equal("XXXX", File.ReadAllText(Path.Combine(to, "a")));
        Assert.False(File.Exists(Path.Combine(to, ".c.kgsm-partial")));
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public void CopyTree_StopsWhenCancelled()
    {
        string root = NewRoot();
        Directory.CreateDirectory(Path.Combine(root, "from"));
        File.WriteAllText(Path.Combine(root, "from", "a"), "a");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();

        Assert.Throws<OperationCanceledException>(() => FileSystem.CopyTree(Path.Combine(root, "from"), Path.Combine(root, "to"), cancelled.Token));
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public void SameDevice_IsTrueWithinOneDirectoryTree_AndFalseForAPathThatIsNotThere()
    {
        string root = NewRoot();
        Directory.CreateDirectory(Path.Combine(root, "a"));
        Directory.CreateDirectory(Path.Combine(root, "b"));

        Assert.True(FileSystem.SameDevice(Path.Combine(root, "a"), Path.Combine(root, "b")));
        Assert.False(FileSystem.SameDevice(Path.Combine(root, "a"), Path.Combine(root, "missing")));
        Directory.Delete(root, recursive: true);
    }

    [Fact]
    public void SameDevice_TellsTheRootFileSystemFromAnotherMount()
    {
        // /dev is a mount of its own on every Linux host the suite runs on.
        Assert.False(FileSystem.SameDevice("/", "/dev"));
    }
}

/// <summary>The lock a transfer leaves on an instance.</summary>
public class TransferLockTests
{
    [Fact]
    public void ALockIsHeldByItsToken_AndOnlyThatTokenPassesIt()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();
        Assert.Null(TransferLock.Holder(instance.Layout));
        TransferLock.Require(instance, "anything");

        File.WriteAllText(instance.Layout.TransferLockFile, "token-1\n");

        Assert.Equal("token-1", TransferLock.Holder(instance.Layout));
        Assert.Throws<TransferLockedException>(() => TransferLock.Require(instance, "start"));
        Assert.Throws<TransferLockedException>(() => TransferLock.Require(instance, "start", "token-2"));
        TransferLock.Require(instance, "uninstall", "token-1");
    }

    [Fact]
    public async Task Unlock_ReleasesTheLock_AndSaysWhenThereWasNone()
    {
        var fx = OpsFixture.Create();
        var (instance, _) = fx.AddInstance();
        File.WriteAllText(instance.Layout.TransferLockFile, "t");

        CliRun first = await fx.Run("instance", "unlock", "g-1");
        CliRun second = await fx.Run("instance", "unlock", "g-1");

        Assert.Contains("released", first.Out, StringComparison.Ordinal);
        Assert.Contains("was not locked", second.Out, StringComparison.Ordinal);
        Assert.Null(TransferLock.Holder(instance.Layout));
    }
}

/// <summary>Autostart goes through the watchdog and nowhere else.</summary>
public class AutostartTests
{
    [Fact]
    public async Task Enable_AndDisable_AskTheReadyWatchdog()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.Session.Watchdog.SocketPresent = true;

        CliRun enable = await fx.Run("instance", "enable", "g-1");
        CliRun disable = await fx.Run("instance", "disable", "g-1");

        Assert.Equal(0, enable.Exit);
        Assert.Equal(0, disable.Exit);
        Assert.Equal(["enable g-1", "disable g-1"], fx.Session.Watchdog.Actions);
    }

    [Fact]
    public async Task Enable_WithoutAWatchdog_OrForAContainer_IsRefused()
    {
        var fx = OpsFixture.Create();
        fx.AddInstance();
        fx.AddInstance("c-1", "vrising", shape: c => c with { Runtime = Contracts.Blueprints.BlueprintRuntime.Container });

        CliRun absent = await fx.Run("instance", "enable", "g-1");
        fx.Session.Watchdog.SocketPresent = true;
        CliRun container = await fx.Run("instance", "enable", "c-1");

        Assert.Equal(1, absent.Exit);
        Assert.Contains("not available", absent.Err, StringComparison.Ordinal);
        Assert.Equal(1, container.Exit);
        Assert.Empty(fx.Session.Watchdog.Actions);
    }
}
