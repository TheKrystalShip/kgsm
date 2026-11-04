using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>Finding a game's hooks file, and refusing one that is not acceptable.</summary>
public class HookFilesTests
{
    private const string SystemHooks = "kgsm_hook_latest_version() { echo system; }\nkgsm_hook_post_deploy() { :; }\n";
    private const string UserHooks = "kgsm_hook_latest_version() { echo user; }\n";

    // --- lookup ---

    [Fact]
    public void AGameWithNoHooksFile_HasNoHooks()
    {
        var sandbox = Sandbox.Create();

        Assert.Null(HookFiles.Find(sandbox.Paths, "factorio"));
    }

    [Fact]
    public void TheSystemHooksFile_IsFoundByTheBlueprintsName()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemOverridesDirectory, "factorio", "hooks.sh"), SystemHooks);

        HookFile? found = HookFiles.Find(sandbox.Paths, "factorio");

        Assert.NotNull(found);
        Assert.False(found.IsUser);
        Assert.Equal(SystemHooks, found.Text);
        Assert.Null(HookFiles.Find(sandbox.Paths, "terraria"));
    }

    [Fact]
    public void AUserHooksFile_ReplacesTheSystemFileWhole_NeverMergingWithIt()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemOverridesDirectory, "factorio", "hooks.sh"), SystemHooks);
        sandbox.WriteFile(Path.Combine(sandbox.Paths.UserOverridesDirectory, "factorio", "hooks.sh"), UserHooks);

        HookFile? found = HookFiles.Find(sandbox.Paths, "factorio");

        Assert.NotNull(found);
        Assert.True(found.IsUser);
        Assert.Equal(UserHooks, found.Text);
        Assert.DoesNotContain("kgsm_hook_post_deploy", found.Text, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("")]
    [InlineData("../factorio")]
    [InlineData("a/b")]
    [InlineData("..")]
    public void ABlueprintNameThatIsAPath_FindsNothing(string name)
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemOverridesDirectory, "factorio", "hooks.sh"), SystemHooks);

        Assert.Null(HookFiles.Find(sandbox.Paths, name));
    }

    [Fact]
    public void TheDigest_IsTheSha256OfTheFilesBytes_AndChangesWithThem()
    {
        var sandbox = Sandbox.Create();
        string path = Path.Combine(sandbox.Paths.SystemOverridesDirectory, "g", "hooks.sh");
        sandbox.WriteFile(path, UserHooks);
        string first = HookFiles.Find(sandbox.Paths, "g")!.Digest;
        sandbox.WriteFile(path, UserHooks + "\n");

        string second = HookFiles.Find(sandbox.Paths, "g")!.Digest;

        Assert.Equal(64, first.Length);
        Assert.NotEqual(first, second);
    }

    // --- the allow-list ---

    [Fact]
    public void TheFourHooksAndHooksPrefixedHelpers_Pass()
    {
        HookFiles.Validate("hooks.sh", """
            kgsm_hook_latest_version() { echo 1; }
            kgsm_hook_download() { :; }
            kgsm_hook_deploy() { :; }
            function kgsm_hook_post_deploy { _hook_one; }
            _hook_one() { _hook_Two_2; }
            _hook_Two_2() { :; }
            """);
    }

    [Theory]
    [InlineData("helper() { :; }", "helper")]
    [InlineData("function other { :; }", "other")]
    [InlineData("function other() { :; }", "other")]
    [InlineData("kgsm_hook_unknown() { :; }", "kgsm_hook_unknown")]
    [InlineData("hook_helper() { :; }", "hook_helper")]
    [InlineData("_hookx() { :; }", "_hookx")]
    [InlineData("_hook_() { :; }", "_hook_")]
    [InlineData("_start_background() { :; }", "_start_background")]
    [InlineData("_stop_server () { :; }", "_stop_server")]
    public void AnyOtherFunction_FailsGeneration(string text, string name)
    {
        var failure = Assert.Throws<HookFileException>(() => HookFiles.Validate("hooks.sh", text + "\n"));

        Assert.Contains(failure.Problems, p => p.Contains($"'{name}'", StringComparison.Ordinal));
    }

    [Fact]
    public void ANestedDefinition_IsFoundToo()
    {
        const string Text = """
            kgsm_hook_deploy() {
              sneaky() { :; }
              sneaky
            }
            """;

        var failure = Assert.Throws<HookFileException>(() => HookFiles.Validate("hooks.sh", Text + "\n"));

        Assert.Contains(failure.Problems, p => p.Contains("'sneaky'", StringComparison.Ordinal));
    }

    [Fact]
    public void AFileThatIsNotValidBash_FailsGeneration()
    {
        var failure = Assert.Throws<HookFileException>(() => HookFiles.Validate("hooks.sh", "kgsm_hook_deploy() {\n  if true; then\n}\n"));

        Assert.Contains(failure.Problems, p => p.Contains("bash -n rejects it", StringComparison.Ordinal));
    }

    [Fact]
    public void EveryProblemIsReported_NotOnlyTheFirst()
    {
        var failure = Assert.Throws<HookFileException>(() => HookFiles.Validate("hooks.sh", "one() { :; }\ntwo() { :; }\nkgsm_hook_deploy() { if; }\n"));

        Assert.Equal(3, failure.Problems.Count);
        Assert.Equal("hooks", failure.Code);
    }

    [Fact]
    public void LoadingAnUnacceptableFile_FailsWithItsPath()
    {
        var sandbox = Sandbox.Create();
        string path = sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemOverridesDirectory, "g", "hooks.sh"), "rogue() { :; }\n");

        var failure = Assert.Throws<HookFileException>(() => HookFiles.Find(sandbox.Paths, "g"));

        Assert.Equal(path, failure.Path);
    }

    [Fact]
    public void BashSyntaxCheck_ReportsTheFirstComplaint_OrNull()
    {
        Assert.Null(BashSyntax.Check("echo ok\n"));
        Assert.NotNull(BashSyntax.Check("if true; then\n"));
    }

    [Fact]
    public void TheDefinitionScan_ReadsBothBashSpellings()
    {
        string[] names = [.. HookFiles.DefinedFunctions("a() { :; }\nfunction b { :; }\nfunction c() { :; }\n  d ()  { :; }\necho \"x()\"\n")];

        Assert.Equal(["a", "b", "c", "d"], names);
    }
}
