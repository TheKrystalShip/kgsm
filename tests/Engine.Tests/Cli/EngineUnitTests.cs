using TheKrystalShip.KGSM.Engine.Accounts;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Network;

namespace TheKrystalShip.KGSM.Engine.Tests.Cli;

public class PortSpecTests
{
    [Fact]
    public void AToken_WithoutAProtocol_IsOpenOnBoth()
    {
        IReadOnlyList<PortRange> ranges = PortSpecs.Parse("22420");

        Assert.Equal([(22420, 22420, PortProtocol.Tcp), (22420, 22420, PortProtocol.Udp)], ranges.Select(r => (r.Start, r.End, r.Protocol)));
    }

    [Fact]
    public void RangesProtocolsAndPipes_AreAllRead()
    {
        IReadOnlyList<PortRange> ranges = PortSpecs.Parse("2456:2458/udp|27015/tcp");

        Assert.Equal([(2456, 2458, PortProtocol.Udp), (27015, 27015, PortProtocol.Tcp)], ranges.Select(r => (r.Start, r.End, r.Protocol)));
    }

    [Theory]
    [InlineData("")]
    [InlineData("abc")]
    [InlineData("0")]
    [InlineData("70000")]
    [InlineData("5:3")]
    [InlineData("80/sctp")]
    public void ATokenThatIsNotAPortRange_IsLeftOut(string spec)
    {
        Assert.Empty(PortSpecs.Parse(spec));
    }

    [Fact]
    public void Overlap_NeedsTheSameProtocol()
    {
        var tcp = new PortRange { Start = 10, End = 20, Protocol = PortProtocol.Tcp };

        Assert.True(tcp.Overlaps(new PortRange { Start = 20, End = 30, Protocol = PortProtocol.Tcp }));
        Assert.False(tcp.Overlaps(new PortRange { Start = 21, End = 30, Protocol = PortProtocol.Tcp }));
        Assert.False(tcp.Overlaps(new PortRange { Start = 10, End = 20, Protocol = PortProtocol.Udp }));
    }

    private static PortUse Use(string instance, int start, int end, PortProtocol protocol = PortProtocol.Udp) =>
        new() { Instance = instance, Start = start, End = end, Protocol = protocol };

    [Fact]
    public void ThreeInstancesContendingForOnePort_AreOneConflict()
    {
        IReadOnlyList<PortConflict> conflicts = PortSpecs.Conflicts([Use("a", 100, 100), Use("b", 100, 100), Use("c", 100, 100)]);

        PortConflict conflict = Assert.Single(conflicts);
        Assert.Equal(["a", "b", "c"], conflict.Instances);
    }

    [Fact]
    public void OverlappingRangesChain_IntoOneSpan_AndDisjointOnesStaySeparate()
    {
        IReadOnlyList<PortConflict> conflicts = PortSpecs.Conflicts(
            [Use("a", 10, 20), Use("b", 15, 30), Use("c", 30, 40), Use("d", 100, 110), Use("e", 200, 210), Use("f", 205, 206)]);

        Assert.Equal([(10, 40, 3), (200, 210, 2)], conflicts.Select(c => (c.Start, c.End, c.Instances.Count)));
    }

    [Fact]
    public void OneInstanceDeclaringOverlappingRanges_ConflictsWithNobody()
    {
        Assert.Empty(PortSpecs.Conflicts([Use("a", 10, 20), Use("a", 15, 25)]));
    }

    [Fact]
    public void TheSamePortOnDifferentProtocols_DoesNotConflict()
    {
        Assert.Empty(PortSpecs.Conflicts([Use("a", 10, 10, PortProtocol.Tcp), Use("b", 10, 10, PortProtocol.Udp)]));
    }
}

public class InstanceLogsTests
{
    private static string Write(string content)
    {
        string file = Sandbox.Create().PathFor("log", "x.log");
        File.WriteAllText(file, content);
        return file;
    }

    [Fact]
    public void TheLastLines_AreReturned_OldestFirst()
    {
        string file = Write("a\nb\nc\nd\n");

        Assert.Equal(["c", "d"], InstanceLogs.Tail(file, 2));
        Assert.Equal(["a", "b", "c", "d"], InstanceLogs.Tail(file, 10));
        Assert.Empty(InstanceLogs.Tail(file, 0));
    }

    [Fact]
    public void AFileWithoutATrailingNewline_KeepsItsLastLine_AndCarriageReturnsAreDropped()
    {
        Assert.Equal(["b", "c"], InstanceLogs.Tail(Write("a\r\nb\r\nc"), 2));
    }

    [Fact]
    public void ALogLargerThanOneChunk_IsReadFromItsEnd()
    {
        string content = string.Concat(Enumerable.Range(1, 5000).Select(i => $"line number {i}\n"));

        Assert.Equal(["line number 4999", "line number 5000"], InstanceLogs.Tail(Write(content), 2));
        Assert.Equal(5000, InstanceLogs.Tail(Write(content), 6000).Count);
    }

    [Fact]
    public void AnAbsentFile_HasNoLines()
    {
        Assert.Empty(InstanceLogs.Tail(Path.Combine(Sandbox.Create().Root, "none.log"), 5));
    }
}

public class ConfigKeyTests
{
    [Fact]
    public void EveryKeyOfTheConfigType_HasAnEntry()
    {
        InstanceConfig config = Sandbox.NewConfig("g", "g-1", "/b");
        string[] declared = [.. typeof(InstanceConfig).GetProperties().Select(p => char.ToLowerInvariant(p.Name[0]) + p.Name[1..])
            .Where(n => n is not ("schemaVersion" or "label"))];

        Assert.Equal(declared.Order(StringComparer.Ordinal), InstanceConfigKeys.All.Select(k => k.Name).Order(StringComparer.Ordinal));
        Assert.All(InstanceConfigKeys.All, k => _ = k.Read(config));
    }

    [Fact]
    public void ProtectedKeys_AreTheIdentityPathsAndSideEffectingOnes()
    {
        string[] protectedKeys = [.. InstanceConfigKeys.All.Where(k => !k.Settable).Select(k => k.Name)];

        Assert.Equal(
            new[]
            {
                "name", "blueprint", "runtime", "installDatetime", "installNonce", "backupsDirectory", "platform",
                "maintenanceWindowsAuthor", "maintenanceWindowsAuthorName", "executableFile", "executableSubdirectory",
                "steamAppId", "clientSteamAppId", "isSteamAccountRequired", "ports", "enableFirewallManagement",
            }.Order(StringComparer.Ordinal),
            protectedKeys.Order(StringComparer.Ordinal));
    }
}

public class AccountGateTests
{
    [Fact]
    public void ADirectoryOwnedByTheRunningAccount_OrAbsent_Passes()
    {
        Assert.True(RegistryAccountGate.Check("/j", [], _ => 1000, 1000, _ => "me").Allowed);
        Assert.True(RegistryAccountGate.Check("/j", [], _ => null, 1000, _ => "me").Allowed);
    }

    [Fact]
    public void ADirectoryOwnedByAnotherAccount_IsRefused_WithTheLineToRunInstead()
    {
        AccountVerdict verdict = RegistryAccountGate.Check(
            "/j", ["instance", "show", "Base Camp", "--json"], _ => 0, 1000, uid => uid == 0 ? "root" : null);

        Assert.False(verdict.Allowed);
        Assert.Equal("root", verdict.Owner);
        Assert.Contains("sudo -u root kgsm instance show 'Base Camp' --json", verdict.Message);
    }

    [Fact]
    public void AnOwnerWithNoName_IsNamedByItsNumber()
    {
        AccountVerdict verdict = RegistryAccountGate.Check("/j", ["instance", "list"], _ => 4242, 1000, _ => null);

        Assert.Contains("sudo -u 4242 kgsm instance list", verdict.Message);
    }

    [Fact]
    public void TheRealOwnerLookup_ReadsAKernelAnswer()
    {
        string directory = Sandbox.Create().PathFor("owned", "x");
        Directory.CreateDirectory(directory);

        uint? owner = RegistryAccountGate.OwnerOf(directory);

        Assert.NotNull(owner);
        Assert.Null(RegistryAccountGate.OwnerOf(Path.Combine(directory, "missing")));
        Assert.True(RegistryAccountGate.Check(directory, [], RegistryAccountGate.OwnerOf, owner!.Value, _ => null).Allowed);
        Assert.False(RegistryAccountGate.Check(directory, [], RegistryAccountGate.OwnerOf, owner.Value + 1, _ => null).Allowed);
    }
}
