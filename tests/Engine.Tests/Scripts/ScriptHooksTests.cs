using System.Security.Cryptography;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>The four hooks a game may define, inlined into a native instance's script.</summary>
public class ScriptHooksTests
{
    private static string Staging(ScriptWorld world) => Path.Combine(world.Temp, "download");

    // --- latest version ---

    [Fact]
    public async Task TheLatestVersionHook_ReplacesSteamcmd_AndItsFirstLineIsTheVersion()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { SteamAppId = 1234 }, hooks: """
            kgsm_hook_latest_version() {
              echo "  1.2.3  "
              echo "ignored second line"
            }
            """);

        ScriptRun run = await world.RunAsync("version", "--latest");

        Assert.Equal(0, run.Exit);
        Assert.Equal("1.2.3\n", run.Out);
        Assert.Empty(world.Recorded("steam/log"));
    }

    [Fact]
    public async Task AFailingLatestVersionHook_MeansUnknown()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_latest_version() {
              echo "partial" 
              return 1
            }
            """);

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
    }

    [Fact]
    public async Task ALatestVersionHookThatPrintsNothing_MeansUnknown()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: "kgsm_hook_latest_version() { :; }\n");

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
    }

    [Fact]
    public async Task VersionsAreOpaque_ComparedForEqualityOnly()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: "kgsm_hook_latest_version() { echo 'weekly'; }\n");
        File.WriteAllText(world.VersionFile, "weekly\n");

        Assert.Equal("current weekly\n", (await world.RunAsync("check-update")).Out);
        File.WriteAllText(world.VersionFile, "999.0\n");
        Assert.Equal("available weekly\n", (await world.RunAsync("check-update")).Out);
    }

    [Fact]
    public async Task AHookReadsTheInstancesValues_AsInstanceVariables()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { LevelName = "my world", DownloadTimeoutSeconds = 17, SteamAppId = 99 }, hooks: """
            kgsm_hook_latest_version() {
              echo "${instance_level_name}|${instance_download_timeout_seconds}|${instance_steam_app_id}|${instance_install_dir##*/}|${instance_name}|${instance_temp_dir##*/}"
            }
            """);

        ScriptRun run = await world.RunAsync("version", "--latest");

        Assert.Equal("my world|17|99|install|g-1|temp\n", run.Out);
    }

    [Fact]
    public async Task AHooksDiagnostics_ReachStderr()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_latest_version() {
              echo "upstream said no" >&2
              return 1
            }
            """);

        ScriptRun run = await world.RunAsync("version", "--latest");

        Assert.Equal(1, run.Exit);
        Assert.Contains("upstream said no", run.Err, StringComparison.Ordinal);
    }

    // --- download ---

    [Fact]
    public async Task TheDownloadHook_IsHandedTheExactVersionAndTheStagingDirectory()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_download() {
              echo "$1" >"$2/version"
              echo "$2" >"$2/dest"
            }
            """);

        ScriptRun run = await world.RunAsync("download", "4.5.6");

        Assert.Equal(0, run.Exit);
        Assert.Equal("4.5.6\n", File.ReadAllText(Path.Combine(Staging(world), "version")));
        Assert.Equal(Staging(world) + "\n", File.ReadAllText(Path.Combine(Staging(world), "dest")));
        Assert.Empty(world.Recorded("steam/log"));
    }

    [Theory]
    [InlineData]
    [InlineData("latest")]
    [InlineData("0")]
    public async Task LatestIsResolvedByTheScript_BeforeTheDownloadHookIsCalled(params string[] arguments)
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_latest_version() { echo 77; }
            kgsm_hook_download() { echo "$1" >"$2/version"; }
            """);

        Assert.Equal(0, (await world.RunAsync(["download", .. arguments])).Exit);

        Assert.Equal("77\n", File.ReadAllText(Path.Combine(Staging(world), "version")));
    }

    [Fact]
    public async Task ADownloadThatLeavesTheDestinationEmpty_Fails_HookedOrNot()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: "kgsm_hook_download() { :; }\n");

        ScriptRun run = await world.RunAsync("download", "1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("left", run.Err, StringComparison.Ordinal);
        Assert.Contains("empty", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AFailingDownloadHook_FailsTheDownload()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_download() {
              echo partial >"$2/f"
              return 3
            }
            """);

        ScriptRun run = await world.RunAsync("download", "1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("download hook failed", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AHook_RunsUnderSetE_SoAFailingStepFailsTheHook()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_download() {
              false
              echo reached >"$2/f"
            }
            """);

        ScriptRun run = await world.RunAsync("download", "1");

        Assert.Equal(1, run.Exit);
        Assert.False(File.Exists(Path.Combine(Staging(world), "f")));
    }

    [Fact]
    public async Task AHook_RunsInASubshell_SoNothingItDoesLeaksIntoTheScript()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_deploy() {
              cd /
              LEAK=from-deploy
              cp -a "$1/." "$2/"
            }
            kgsm_hook_post_deploy() {
              echo "${LEAK:-unset}" >"$1/leak"
            }
            """);
        Directory.CreateDirectory(Staging(world));
        File.WriteAllText(Path.Combine(Staging(world), "a.txt"), "a");

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(0, run.Exit);
        Assert.Equal("unset\n", File.ReadAllText(Path.Combine(world.Install, "leak")));
        Assert.Empty(Directory.GetFileSystemEntries(Staging(world)));
    }

    // --- deploy ---

    [Fact]
    public async Task TheDeployHook_ReplacesTheDefaultCopy_AndIsHandedStagingAndInstall()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_deploy() {
              mv "$1/a.txt" "$2/renamed.txt"
              echo "$1|$2" >"$2/args"
            }
            """);
        Directory.CreateDirectory(Staging(world));
        File.WriteAllText(Path.Combine(Staging(world), "a.txt"), "a");
        File.WriteAllText(Path.Combine(Staging(world), "b.txt"), "b");

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        Assert.Equal("a", File.ReadAllText(Path.Combine(world.Install, "renamed.txt")));
        Assert.False(File.Exists(Path.Combine(world.Install, "b.txt")), "the hook, not the default copy, did the deploy");
        Assert.Equal($"{Staging(world)}|{world.Install}\n", File.ReadAllText(Path.Combine(world.Install, "args")));
        Assert.Empty(Directory.GetFileSystemEntries(Staging(world)));
    }

    [Fact]
    public async Task ThePostDeployHook_RunsAfterTheDefaultDeploy_Too_AndIsHandedTheInstallDirectory()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_post_deploy() {
              ls "$1" >"$1/listing-at-post-deploy"
            }
            """);
        Directory.CreateDirectory(Staging(world));
        File.WriteAllText(Path.Combine(world.Staging(), "a.txt"), "a");

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        string listing = File.ReadAllText(Path.Combine(world.Install, "listing-at-post-deploy"));
        Assert.Contains("a.txt", listing, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AFailingDeployHook_FailsTheDeploy_AndKeepsTheStagedFiles()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: "kgsm_hook_deploy() { return 1; }\n");
        Directory.CreateDirectory(Staging(world));
        File.WriteAllText(Path.Combine(Staging(world), "a.txt"), "a");

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(1, run.Exit);
        Assert.Contains("deploy hook failed", run.Err, StringComparison.Ordinal);
        Assert.True(File.Exists(Path.Combine(Staging(world), "a.txt")));
    }

    [Fact]
    public async Task AFailingPostDeployHook_FailsTheDeploy_AndKeepsTheStagedFiles()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: "kgsm_hook_post_deploy() { return 1; }\n");
        Directory.CreateDirectory(Staging(world));
        File.WriteAllText(Path.Combine(Staging(world), "a.txt"), "a");

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(1, run.Exit);
        Assert.Contains("post-deploy hook failed", run.Err, StringComparison.Ordinal);
        Assert.True(File.Exists(Path.Combine(Staging(world), "a.txt")));
    }

    [Fact]
    public async Task AHelperPrefixedHook_IsCallableFromAHook()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_post_deploy() { _hook_mark "$1"; }
            _hook_mark() { echo marked >"$1/mark"; }
            """);
        Directory.CreateDirectory(Staging(world));
        File.WriteAllText(Path.Combine(Staging(world), "a.txt"), "a");

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        Assert.Equal("marked\n", File.ReadAllText(Path.Combine(world.Install, "mark")));
    }

    // --- the whole update through hooks ---

    [Fact]
    public async Task AnUpdate_RunsEveryHookInOrder_AndRecordsTheHooksVersion()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: """
            kgsm_hook_latest_version() { echo 9; }
            kgsm_hook_download() { echo payload >"$2/game.bin"; }
            kgsm_hook_post_deploy() { echo done >"$1/post"; }
            """);
        File.WriteAllText(world.VersionFile, "8\n");
        File.WriteAllText(Path.Combine(world.Saves, "w.sav"), "w");

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(0, run.Exit);
        Assert.Equal("updated 9\n", run.Out);
        Assert.Equal("payload\n", File.ReadAllText(Path.Combine(world.Install, "game.bin")));
        Assert.Equal("done\n", File.ReadAllText(Path.Combine(world.Install, "post")));
        Assert.Equal("9", File.ReadAllText(world.VersionFile).Trim());
    }

    // --- the digest ---

    [Fact]
    public async Task TheScriptRecordsTheDigestOfTheHooksFileItWasBuiltFrom()
    {
        const string Hooks = "kgsm_hook_latest_version() { echo 1; }\n";
        using ScriptWorld world = ScriptWorld.Native(hooks: Hooks);
        string expected = Convert.ToHexStringLower(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(Hooks)));

        ScriptRun run = await world.RunAsync("script-info");

        Assert.Equal($"template={ScriptTemplate.Version} hooks={expected} runtime=native\n", run.Out);
        Assert.Equal(expected, ScriptHeader.Parse(File.ReadAllText(world.ScriptPath))!.HooksDigest);
        Assert.Equal(expected, world.Hooks!.Digest);
    }

    [Fact]
    public void AContainerInstance_TakesNoHooks()
    {
        using ScriptWorld native = ScriptWorld.Native(hooks: "kgsm_hook_latest_version() { echo 1; }\n");

        string script = ScriptGenerator.Render(native.Config with { Runtime = BlueprintRuntime.Container }, native.Hooks, "/run/x.sock");

        Assert.DoesNotContain("kgsm_hook_latest_version() {", script, StringComparison.Ordinal);
        Assert.Equal(HookFiles.NoHooksDigest, ScriptHeader.Parse(script)!.HooksDigest);
    }

    [Fact]
    public async Task HooksAreInlinedAtGeneration_SoTheScriptNeedsNoFileBesideIt()
    {
        using ScriptWorld world = ScriptWorld.Native(hooks: "kgsm_hook_latest_version() { echo inlined; }\n");
        File.Delete(world.Hooks!.Path);

        ScriptRun run = await world.RunAsync("version", "--latest");

        Assert.Equal("inlined\n", run.Out);
    }
}

internal static class ScriptWorldStaging
{
    /// <summary>The directory a download lands in and a deploy reads from.</summary>
    public static string Staging(this ScriptWorld world) => Path.Combine(world.Temp, "download");
}
