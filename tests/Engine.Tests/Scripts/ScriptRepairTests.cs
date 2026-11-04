using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Libraries;
using TheKrystalShip.KGSM.Engine.Locks;
using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>Regenerating a stale management script: what makes one stale, what a repair touches and what it refuses.</summary>
public class ScriptRepairTests
{
    private const string Socket = "/run/test-watchdog/control.sock";

    private sealed class Fixture
    {
        public Fixture()
        {
            Sandbox = Sandbox.Create();
            Library = Sandbox.AddLibrary("main");
            Locks = new EngineLocks(Sandbox.Paths);
            Repairer = new ScriptRepairer(Sandbox.Paths, Socket, Locks);
        }

        public Sandbox Sandbox { get; }

        public LibraryRecord Library { get; }

        public EngineLocks Locks { get; }

        public ScriptRepairer Repairer { get; }

        public InstanceDescription Add(string id, string blueprint = "g", Func<InstanceConfig, InstanceConfig>? shape = null)
        {
            Sandbox.AddInstance(Library, blueprint, id, shape);
            return Find(id);
        }

        public InstanceDescription Find(string id) =>
            new InstanceStore(Sandbox.Paths, new LibraryCatalog(Sandbox.Paths)).Find(id)!;

        public string Hooks(string blueprint, string text, bool user = false) =>
            Sandbox.WriteFile(
                Path.Combine(user ? Sandbox.Paths.UserOverridesDirectory : Sandbox.Paths.SystemOverridesDirectory, blueprint, "hooks.sh"), text);
    }

    [Fact]
    public void AnInstanceWithNoScript_IsStale_AndARepairWritesOne()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1");

        Assert.Equal("the script is missing", f.Repairer.StaleReason(instance));
        ScriptRepairEntry entry = f.Repairer.Repair(instance, onlyIfStale: true);

        Assert.Equal(ScriptRepairOutcome.Regenerated, entry.Outcome);
        Assert.Null(f.Repairer.StaleReason(instance));
        string script = instance.Layout.ManagementScript;
        Assert.Null(BashSyntax.Check(File.ReadAllText(script)));
        Assert.True(File.GetUnixFileMode(script).HasFlag(UnixFileMode.UserExecute));
        Assert.Contains(Socket, File.ReadAllText(script), StringComparison.Ordinal);
        Assert.False(File.Exists(script + ".staged"));
    }

    [Fact]
    public void ACurrentScript_IsLeftAlone_ByAnAllRepair()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1");
        f.Repairer.Repair(instance, onlyIfStale: true);
        string script = instance.Layout.ManagementScript;
        File.SetLastWriteTimeUtc(script, new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));

        ScriptRepairEntry entry = f.Repairer.Repair(instance, onlyIfStale: true);

        Assert.Equal(ScriptRepairOutcome.Current, entry.Outcome);
        Assert.Equal(new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc), File.GetLastWriteTimeUtc(script));
    }

    [Fact]
    public void RepairingOneInstanceByHand_RewritesItsScriptWhateverItHolds()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1");
        f.Repairer.Repair(instance, onlyIfStale: true);
        string script = instance.Layout.ManagementScript;
        string original = File.ReadAllText(script);
        File.WriteAllText(script, original.Replace("start) _cmd_start", "start) echo broken", StringComparison.Ordinal) + "\n# hand edit\n");

        ScriptRepairEntry entry = f.Repairer.Repair(instance, onlyIfStale: false);

        Assert.Equal(ScriptRepairOutcome.Regenerated, entry.Outcome);
        Assert.Equal(original, File.ReadAllText(script));
    }

    [Fact]
    public void ATemplateVersionThatDiffers_MakesTheScriptStale()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1");
        f.Repairer.Repair(instance, onlyIfStale: true);
        string script = instance.Layout.ManagementScript;
        File.WriteAllText(script, File.ReadAllText(script).Replace($"# kgsm-script: template={ScriptTemplate.Version} ", "# kgsm-script: template=0 ", StringComparison.Ordinal));

        Assert.Equal($"the script is built from template 0, the engine carries {ScriptTemplate.Version}", f.Repairer.StaleReason(instance));
        Assert.Equal(ScriptRepairOutcome.Regenerated, f.Repairer.Repair(instance, onlyIfStale: true).Outcome);
        Assert.Null(f.Repairer.StaleReason(instance));
    }

    [Fact]
    public void AScriptWithNoHeader_IsStale()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1");
        File.WriteAllText(instance.Layout.ManagementScript, "#!/usr/bin/env bash\necho hand written\n");

        Assert.Equal("the script records no header", f.Repairer.StaleReason(instance));
    }

    [Fact]
    public void AHooksFileThatAppears_ChangesOrVanishes_MakesTheScriptStale()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1", "factorio");
        f.Repairer.Repair(instance, onlyIfStale: true);
        Assert.Null(f.Repairer.StaleReason(instance));

        string hooks = f.Hooks("factorio", "kgsm_hook_latest_version() { echo 1; }\n");
        Assert.Equal("the hooks file changed", f.Repairer.StaleReason(instance));
        Assert.Equal(ScriptRepairOutcome.Regenerated, f.Repairer.Repair(instance, onlyIfStale: true).Outcome);
        Assert.Null(f.Repairer.StaleReason(instance));
        Assert.Contains("kgsm_hook_latest_version() { echo 1; }", File.ReadAllText(instance.Layout.ManagementScript), StringComparison.Ordinal);

        File.WriteAllText(hooks, "kgsm_hook_latest_version() { echo 2; }\n");
        Assert.Equal("the hooks file changed", f.Repairer.StaleReason(instance));
        f.Repairer.Repair(instance, onlyIfStale: true);

        File.Delete(hooks);
        Assert.Equal("the hooks file changed", f.Repairer.StaleReason(instance));
        f.Repairer.Repair(instance, onlyIfStale: true);
        Assert.DoesNotContain("# The game's hooks", File.ReadAllText(instance.Layout.ManagementScript), StringComparison.Ordinal);
    }

    [Fact]
    public void AUserHooksFile_ThatReplacesTheSystemOne_MakesTheScriptStale()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1", "factorio");
        f.Hooks("factorio", "kgsm_hook_latest_version() { echo system; }\n");
        f.Repairer.Repair(instance, onlyIfStale: true);

        f.Hooks("factorio", "kgsm_hook_latest_version() { echo user; }\n", user: true);

        Assert.Equal("the hooks file changed", f.Repairer.StaleReason(instance));
        f.Repairer.Repair(instance, onlyIfStale: true);
        string script = File.ReadAllText(instance.Layout.ManagementScript);
        Assert.Contains("echo user", script, StringComparison.Ordinal);
        Assert.DoesNotContain("echo system", script, StringComparison.Ordinal);
    }

    [Fact]
    public void AScriptForTheOtherRuntime_IsStale()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1", shape: c => c with { Runtime = BlueprintRuntime.Container });
        string native = ScriptGenerator.Render(instance.Config! with { Runtime = BlueprintRuntime.Native }, null, Socket);
        ScriptFile.Write(instance.Layout.ManagementScript, native);

        Assert.Equal("the script is for the other runtime", f.Repairer.StaleReason(instance));
    }

    [Fact]
    public void AContainerInstance_IgnoresAHooksFileForItsBlueprint()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1", "factorio", c => c with { Runtime = BlueprintRuntime.Container });
        f.Hooks("factorio", "kgsm_hook_latest_version() { echo 1; }\n");

        f.Repairer.Repair(instance, onlyIfStale: true);

        Assert.Equal(HookFiles.NoHooksDigest, ScriptHeader.Parse(File.ReadAllText(instance.Layout.ManagementScript))!.HooksDigest);
        Assert.Null(f.Repairer.StaleReason(instance));
    }

    [Fact]
    public void AHooksFileThatCannotBeInlined_FailsTheRepair_AndLeavesTheExistingScriptAlone()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1", "factorio");
        f.Repairer.Repair(instance, onlyIfStale: true);
        string before = File.ReadAllText(instance.Layout.ManagementScript);
        f.Hooks("factorio", "rogue() { :; }\n");

        ScriptRepairEntry entry = f.Repairer.Repair(instance, onlyIfStale: true);

        Assert.Equal(ScriptRepairOutcome.Failed, entry.Outcome);
        Assert.Contains("'rogue'", entry.Detail, StringComparison.Ordinal);
        Assert.Equal(before, File.ReadAllText(instance.Layout.ManagementScript));
    }

    [Fact]
    public void AnInstanceWithNoReadableConfig_IsSkipped()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1");
        File.Delete(instance.Layout.ConfigFile);

        ScriptRepairEntry entry = f.Repairer.Repair(f.Find("g-1"), onlyIfStale: false);

        Assert.Equal(ScriptRepairOutcome.Skipped, entry.Outcome);
        Assert.False(File.Exists(instance.Layout.ManagementScript));
    }

    [Fact]
    public void GenerationTakesTheInstancesLock_SoABusyInstanceFails_AndAnotherOneDoesNot()
    {
        var f = new Fixture();
        InstanceDescription busy = f.Add("g-1");
        InstanceDescription free = f.Add("g-2");

        using (f.Locks.AcquireInstance("g-1"))
        {
            Assert.Equal(ScriptRepairOutcome.Failed, f.Repairer.Repair(busy, onlyIfStale: false).Outcome);
            Assert.Contains("busy", f.Repairer.Repair(busy, onlyIfStale: false).Detail, StringComparison.Ordinal);
            Assert.Equal(ScriptRepairOutcome.Regenerated, f.Repairer.Repair(free, onlyIfStale: false).Outcome);
        }

        Assert.Equal(ScriptRepairOutcome.Regenerated, f.Repairer.Repair(busy, onlyIfStale: false).Outcome);
        Assert.False(File.Exists(busy.Layout.ManagementScript + ".staged"));
    }

    [Fact]
    public async Task ARepair_ReplacesTheFile_SoARunningScriptKeepsItsOwnText()
    {
        var f = new Fixture();
        InstanceDescription instance = f.Add("g-1");
        f.Repairer.Repair(instance, onlyIfStale: true);
        string script = instance.Layout.ManagementScript;
        await using var reading = new FileStream(script, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        string before = await new StreamReader(reading).ReadToEndAsync();
        reading.Position = 0;
        File.WriteAllText(script, before.Replace($"template={ScriptTemplate.Version}", "template=0", StringComparison.Ordinal));
        reading.Position = 0;
        string stale = await new StreamReader(reading).ReadToEndAsync();
        Assert.Contains("template=0", stale, StringComparison.Ordinal);

        f.Repairer.Repair(instance, onlyIfStale: true);
        reading.Position = 0;

        Assert.Equal(stale, await new StreamReader(reading).ReadToEndAsync());
        Assert.Contains($"template={ScriptTemplate.Version}", File.ReadAllText(script), StringComparison.Ordinal);
    }
}
