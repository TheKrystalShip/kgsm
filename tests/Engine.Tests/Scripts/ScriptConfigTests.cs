
namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>How the script reads its config, finds its paths and answers a command it does not know.</summary>
public class ScriptConfigTests
{
    [Fact]
    public async Task AConfigWithAnUnknownSchemaVersion_IsRefusedRatherThanMisread()
    {
        using ScriptWorld world = ScriptWorld.Native();
        string config = Path.Combine(world.WorkingDirectory, $"{ScriptWorld.Id}.config.json");
        File.WriteAllText(config, File.ReadAllText(config).Replace("\"schemaVersion\":1", "\"schemaVersion\":2", StringComparison.Ordinal));

        ScriptRun run = await world.RunAsync("version");

        Assert.Equal(1, run.Exit);
        Assert.Contains("schemaVersion 2", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AConfigWithNoSchemaVersion_IsRefused()
    {
        using ScriptWorld world = ScriptWorld.Native();
        string config = Path.Combine(world.WorkingDirectory, $"{ScriptWorld.Id}.config.json");
        File.WriteAllText(config, "{\"name\":\"g-1\"}");

        ScriptRun run = await world.RunAsync("version");

        Assert.Equal(1, run.Exit);
        Assert.Contains("schemaVersion none", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AConfigThatIsNotJson_IsRefused()
    {
        using ScriptWorld world = ScriptWorld.Native();
        File.WriteAllText(Path.Combine(world.WorkingDirectory, $"{ScriptWorld.Id}.config.json"), "not json");

        ScriptRun run = await world.RunAsync("version");

        Assert.Equal(1, run.Exit);
        Assert.Contains("not valid JSON", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AMissingConfig_IsReported()
    {
        using ScriptWorld world = ScriptWorld.Native();
        File.Delete(Path.Combine(world.WorkingDirectory, $"{ScriptWorld.Id}.config.json"));

        ScriptRun run = await world.RunAsync("version");

        Assert.Equal(1, run.Exit);
        Assert.Contains("not found", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AConfigThatNamesAnotherInstance_IsRefused()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.Reconfigure(c => c with { Name = "someone-else" });

        ScriptRun run = await world.RunAsync("version");

        Assert.Equal(1, run.Exit);
        Assert.Contains("someone-else", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AScriptForTheOtherRuntime_AsksForARepair()
    {
        using ScriptWorld world = ScriptWorld.Native();
        string config = Path.Combine(world.WorkingDirectory, $"{ScriptWorld.Id}.config.json");
        File.WriteAllText(config, File.ReadAllText(config).Replace("\"runtime\":\"native\"", "\"runtime\":\"container\"", StringComparison.Ordinal));

        ScriptRun run = await world.RunAsync("version");

        Assert.Equal(1, run.Exit);
        Assert.Contains("instance repair", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AConfigValueThatIsNotAWholeNumberOfSeconds_IsRefused()
    {
        using ScriptWorld world = ScriptWorld.Native();
        string config = Path.Combine(world.WorkingDirectory, $"{ScriptWorld.Id}.config.json");
        File.WriteAllText(config, File.ReadAllText(config).Replace("\"stopCommandTimeoutSeconds\":5", "\"stopCommandTimeoutSeconds\":-3", StringComparison.Ordinal));

        ScriptRun run = await world.RunAsync("version");

        Assert.Equal(1, run.Exit);
        Assert.Contains("stop_command_timeout_seconds", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task EveryPathIsDerivedFromTheScriptsOwnLocation_SoAMovedInstanceNeedsNoRewrite()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { ExecutableSubdirectory = "bin" });
        string moved = Path.Combine(world.Sandbox.Root, "elsewhere", ScriptWorld.Id);
        Directory.CreateDirectory(Path.GetDirectoryName(moved)!);
        Directory.Move(world.WorkingDirectory, moved);

        string script = Path.Combine(moved, $"{ScriptWorld.Id}.manage.sh");
        var run = await RunAt(world, script, "status", "--json", "--fast");

        Assert.Equal(0, run.Exit);
        Assert.Equal(moved, ScriptJson.Status(run.Out).Configuration.Directory);

        var args = await RunAt(world, script, "launch-args", "--null");
        Assert.Equal($"--save\0{moved}/saves/world one\0--name\0{ScriptWorld.Id}\0", args.Out);
    }

    [Fact]
    public async Task ValuesAreLiteral_NothingInAConfigIsUnescapedOrExpanded()
    {
        // A JSON config holds the value itself, so there is no escaping to undo: quotes, backslashes,
        // backticks and dollars read back exactly as they were written.
        const string Tricky = "a \"quoted\" \\ back\\\\slash `tick` $(id) $HOME 'single' {x} é";
        using ScriptWorld world = ScriptWorld.Native(c => c with { LevelName = Tricky, ExecutableArguments = "{levelName}" });

        ScriptRun run = await world.RunAsync("launch-args", "--null");

        Assert.Equal(0, run.Exit);
        Assert.Equal(Tricky + "\0", run.Out);
    }

    [Fact]
    public async Task TheLatestVersionFile_IsDerivedFromTheInstance_NotRead()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(0, (await world.RunAsync("version", "--save-latest", "42")).Exit);

        Assert.Equal("42", File.ReadAllLines(world.LatestFile)[0]);
    }

    // --- help and unknown commands ---

    [Fact]
    public async Task Help_ListsTheCommands_AndWorksWithADamagedConfig()
    {
        using ScriptWorld world = ScriptWorld.Native();
        File.WriteAllText(Path.Combine(world.WorkingDirectory, $"{ScriptWorld.Id}.config.json"), "not json");

        ScriptRun run = await world.RunAsync("help");

        Assert.Equal(0, run.Exit);
        Assert.Contains("restore-backup", run.Out, StringComparison.Ordinal);
        Assert.Contains("check-update", run.Out, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("start")]
    [InlineData("stop")]
    [InlineData("restart")]
    [InlineData("attach")]
    [InlineData("status")]
    [InlineData("logs")]
    [InlineData("version")]
    [InlineData("check-update")]
    [InlineData("download")]
    [InlineData("update")]
    [InlineData("announce")]
    [InlineData("kick")]
    [InlineData("backup")]
    [InlineData("create-backup")]
    [InlineData("launch-args")]
    public async Task HelpForACommand_PrintsItsUsage(string command)
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("help", command);

        Assert.Equal(0, run.Exit);
        Assert.Contains("Usage:", run.Out, StringComparison.Ordinal);
    }

    [Fact]
    public async Task HelpForAnUnknownCommand_IsAnInvalidArgument()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(8, (await world.RunAsync("help", "frobnicate")).Exit);
    }

    [Fact]
    public async Task NoCommand_PrintsTheUsageAndFails()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync();

        Assert.Equal(1, run.Exit);
        Assert.Contains("Usage:", run.Out, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnUnknownCommand_IsAnInvalidArgument()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("frobnicate");

        Assert.Equal(8, run.Exit);
        Assert.Contains("Unknown command", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task EveryMessageGoesToStderr_AndStdoutCarriesOnlyTheResult()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("version", "--save", "5");

        Assert.Equal(string.Empty, run.Out);
        Assert.Contains("Version saved", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ScriptInfo_ReportsTheTemplateVersionHooksDigestAndRuntime()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("script-info");

        Assert.Equal($"template={TemplateVersion} hooks=none runtime=native\n", run.Out);
    }

    private const int TemplateVersion = TheKrystalShip.KGSM.Engine.Scripts.ScriptTemplate.Version;

    private static async Task<ScriptRun> RunAt(ScriptWorld world, string script, params string[] args)
    {
        var start = new System.Diagnostics.ProcessStartInfo(HostTools.Find("bash")!)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
        };
        start.ArgumentList.Add(script);
        foreach (string arg in args) start.ArgumentList.Add(arg);
        start.Environment.Clear();
        foreach ((string key, string value) in world.Environment) start.Environment[key] = value;

        using var process = System.Diagnostics.Process.Start(start)!;
        process.StandardInput.Close();
        Task<string> output = process.StandardOutput.ReadToEndAsync();
        Task<string> error = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return new ScriptRun(process.ExitCode, await output, await error);
    }
}
