using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>The template's own rules: its version tracks its text, the two runtimes share one body, and no rendering needs a shell's expansion.</summary>
public partial class ScriptTemplateTests
{
    private static readonly Dictionary<string, string> Tokens = new() { ["A"] = "1" };

    /// <summary>
    /// The SHA-256 of the template for each version. A change to the template's text changes the hash, and
    /// this test fails until the version is bumped and the new hash recorded: a script records the version,
    /// and a changed template under an unchanged version would never be regenerated.
    /// </summary>
    private static readonly Dictionary<int, string> Hashes = new()
    {
        [1] = "5ac5ef5f82f1909b361c8efbf862a6b616825c092a814b616d2ed65b86290e08",
        [2] = "5924a5a7261d124e5a9ebce5600c5a712e449ea9e76140a6785a4dbe5f543da9",
        [3] = "cefb2cbd2d39211a8ad8d937d04d2e98ade2f5ed2f10eeae8df365d3e71c5791",
    };

    [Fact]
    public void TheTemplateVersion_IsBumpedWheneverTheTemplatesTextChanges()
    {
        string hash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(ScriptTemplate.Text)));

        Assert.True(Hashes.TryGetValue(ScriptTemplate.Version, out string? recorded), $"record template version {ScriptTemplate.Version} with hash {hash}");
        Assert.True(recorded == hash, $"the template changed under version {ScriptTemplate.Version}: bump ScriptTemplate.Version and record {hash}");
    }

    // --- rendering ---

    [Fact]
    public void ABlockForTheOtherRuntime_IsDropped_AndTheMarkersLeaveNoTrace()
    {
        const string Template = "a\n#@if native\nnative @@A@@\n#@end\n#@if container\ncontainer\n#@end\nz\n";

        Assert.Equal("a\nnative 1\nz\n", ScriptTemplate.Render(Template, native: true, Tokens, hooks: null));
        Assert.Equal("a\ncontainer\nz\n", ScriptTemplate.Render(Template, native: false, Tokens, hooks: null));
    }

    [Fact]
    public void TheHooksLine_IsReplacedByTheHooksText_OrByNothing()
    {
        const string Template = "a\n#@hooks\nz\n";

        Assert.Equal("a\n# The game's hooks, inlined at generation.\nh1() { :; }\nz\n", ScriptTemplate.Render(Template, native: true, Tokens, "h1() { :; }\n\n"));
        Assert.Equal("a\nz\n", ScriptTemplate.Render(Template, native: true, Tokens, null));
    }

    [Fact]
    public void AToken_IsNeverReplacedInsideTheHooksText()
    {
        Assert.Contains("@@A@@", ScriptTemplate.Render("#@hooks\n", native: true, Tokens, "echo @@A@@\n"), StringComparison.Ordinal);
    }

    [Fact]
    public void ATokenWithNoValue_FailsTheRender()
    {
        var failure = Assert.Throws<InvalidOperationException>(() => ScriptTemplate.Render("@@MISSING@@\n", native: true, Tokens, null));

        Assert.Contains("@@MISSING@@", failure.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("#@if native\n#@if container\n#@end\n#@end\n")]
    [InlineData("#@end\n")]
    [InlineData("#@if native\nopen\n")]
    public void AMalformedBlock_FailsTheRender(string template)
    {
        Assert.Throws<InvalidOperationException>(() => ScriptTemplate.Render(template, native: true, Tokens, null));
    }

    [Fact]
    public void TheTemplate_LeavesNoMarkerOrTokenInEitherRuntimesScript()
    {
        foreach (bool native in new[] { true, false })
        {
            using ScriptWorld world = native ? ScriptWorld.Native() : ScriptWorld.Container();
            string script = File.ReadAllText(world.ScriptPath);

            Assert.DoesNotContain("#@", script, StringComparison.Ordinal);
            Assert.DoesNotMatch(@"@@[A-Z_]+@@", script);
        }
    }

    // --- one body for both runtimes ---

    [Theory]
    [InlineData("_load_config")]
    [InlineData("_usage")]
    [InlineData("_usage_command")]
    [InlineData("_create_backup")]
    [InlineData("_restore_backup")]
    [InlineData("_set_backup_retention")]
    [InlineData("_backup_manifests_json")]
    [InlineData("_list_backups")]
    [InlineData("_rotate_log_file")]
    [InlineData("_status")]
    [InlineData("_version_check")]
    [InlineData("_installed_version")]
    [InlineData("_save_latest_version")]
    [InlineData("_send_input")]
    [InlineData("_send_broadcast")]
    [InlineData("_send_moderation_command")]
    [InlineData("_send_save_command")]
    public void Help_Config_Backups_Logs_Status_AndTheConsole_AreDefinedOnce_ForBothRuntimes(string function)
    {
        // One body serves both runtimes: a copy per runtime would drift.
        string[] lines = ScriptTemplate.Text.Split('\n');
        int definitions = lines.Count(l => l.StartsWith($"function {function}()", StringComparison.Ordinal));
        string? block = null;
        int inside = 0;
        foreach (string line in lines)
        {
            if (line.StartsWith("#@if ", StringComparison.Ordinal)) block = line;
            else if (line == "#@end") block = null;
            else if (block is not null && line.StartsWith($"function {function}()", StringComparison.Ordinal)) inside++;
        }

        Assert.Equal(1, definitions);
        Assert.Equal(0, inside);
    }

    [Theory]
    [InlineData("_start_background")]
    [InlineData("_stop_server")]
    [InlineData("_is_active")]
    [InlineData("_kill_all_processes")]
    [InlineData("_attach")]
    [InlineData("_download")]
    [InlineData("_deploy")]
    [InlineData("_update")]
    [InlineData("_latest_version")]
    [InlineData("_print_logs")]
    [InlineData("_process_facts")]
    [InlineData("_console_fifo")]
    public void Lifecycle_Input_Version_Download_Deploy_AndStatus_DifferByRuntime(string function)
    {
        string text = ScriptTemplate.Text;

        Assert.Equal(2, Regex.Matches(text, $"(?m)^function {function}\\(\\)").Count);
    }

    [Fact]
    public void TheContainerScript_HasNeitherTheWatchdogNorSteamNorLaunchArguments()
    {
        using ScriptWorld container = ScriptWorld.Container();
        string script = File.ReadAllText(container.ScriptPath);

        Assert.DoesNotContain("_wd_call", script, StringComparison.Ordinal);
        Assert.DoesNotContain("steamcmd", script, StringComparison.Ordinal);
        Assert.DoesNotContain("_resolve_arguments", script, StringComparison.Ordinal);
        Assert.DoesNotContain("kgsm_hook_", script, StringComparison.Ordinal);
    }

    [Fact]
    public void TheNativeScript_HasNoDockerAndNoContainerLifecycle()
    {
        using ScriptWorld native = ScriptWorld.Native();
        string script = File.ReadAllText(native.ScriptPath);

        Assert.DoesNotContain("docker", script, StringComparison.Ordinal);
        Assert.DoesNotContain("_compose", script, StringComparison.Ordinal);
    }

    // --- no expansion by a shell ---

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void NoScript_UsesEnvsubstOrEval_AndNoneReadsItsConfigBySourcingIt(bool native)
    {
        using ScriptWorld world = native ? ScriptWorld.Native() : ScriptWorld.Container();
        string script = File.ReadAllText(world.ScriptPath);

        Assert.DoesNotMatch(@"(?m)^[^#\n]*\benvsubst\b", script);
        Assert.DoesNotMatch(@"(?m)^[^#\n]*\beval\b", script);
        Assert.DoesNotMatch(@"(?m)^\s*(source|\.)\s+""?\$", script);
    }

    [Fact]
    public void EveryExitStatusTheScriptReturns_IsOneItDefines()
    {
        // A constant the script never defines expands to nothing, and the return then carries the previous status.
        string script = ScriptTemplate.Text;
        string[] defined = [.. Regex.Matches(script, @"readonly (EC_[A-Z_]+)=").Select(m => m.Groups[1].Value)];
        string[] used = [.. Regex.Matches(script, @"\$(EC_[A-Z_]+)").Select(m => m.Groups[1].Value).Distinct()];

        Assert.Empty(used.Except(defined));
    }
}
