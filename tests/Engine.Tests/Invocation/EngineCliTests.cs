using TheKrystalShip.KGSM.Engine.Contracts.Invocation;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;

namespace TheKrystalShip.KGSM.Engine.Tests.Invocation;

public class EngineCliTests
{
    private sealed class RecordedProcess(int exit, string stdout, string stderr = "") : IEngineProcess
    {
        public List<string> Arguments { get; } = [];

        public string? Input { get; private set; }

        public Task<EngineProcessResult> RunAsync(
            string binary, IReadOnlyList<string> arguments, IReadOnlyDictionary<string, string> environment,
            string? standardInput, CancellationToken cancellationToken)
        {
            Arguments.AddRange(arguments);
            Input = standardInput;
            return Task.FromResult(new EngineProcessResult(exit, stdout, stderr));
        }

        public async Task<EngineStreamResult> RunStreamingAsync(
            string binary, IReadOnlyList<string> arguments, IReadOnlyDictionary<string, string> environment,
            Stream? source, Stream? destination, CancellationToken cancellationToken)
        {
            Arguments.AddRange(arguments);
            if (source is not null) await source.CopyToAsync(Stream.Null, cancellationToken);
            return new EngineStreamResult(exit, stdout, stderr);
        }
    }

    private static EngineCli Cli(RecordedProcess process) => new(new EngineCliOptions { BinaryPath = "kgsm" }, process);

    [Fact]
    public async Task AValueIsOneArgument_WhateverItHolds()
    {
        var process = new RecordedProcess(0, "{\"action\":\"save\",\"subject\":\"a\",\"message\":\"sent\"}");

        await Cli(process).AnnounceAsync("a", "back in 5; rm -rf \"x\" $HOME", new EngineCaller("local:me", "ui"));

        Assert.Equal(
            ["instance", "console", "announce", "a", "back in 5; rm -rf \"x\" $HOME", "--json", "--actor", "local:me", "--origin", "ui"],
            process.Arguments);
    }

    [Fact]
    public async Task ASuccessCarriesTheReportTheCommandPrinted()
    {
        var process = new RecordedProcess(0, "{\"action\":\"save\",\"subject\":\"a\",\"message\":\"sent\"}");

        var result = await Cli(process).SaveAsync("a");

        Assert.True(result.IsSuccess);
        Assert.Equal("sent", result.Require().Message);
    }

    [Fact]
    public async Task ARefusalCarriesTheErrorReportAndTheExitCode()
    {
        var process = new RecordedProcess(
            57, string.Empty, "{\"code\":\"running\",\"message\":\"it runs\",\"exitCode\":57,\"details\":[]}");

        var result = await Cli(process).UpdateAsync("a");

        Assert.False(result.IsSuccess);
        Assert.Equal(57, result.ExitCode);
        Assert.Equal("running", result.Error!.Code);
        Assert.Equal("it runs", result.Message);
        Assert.Throws<EngineCommandException>(() => result.Require());
    }

    [Fact]
    public async Task AnImportVerdictIsTheValue_EvenWhenTheCheckRefuses()
    {
        var process = new RecordedProcess(
            60, "{\"ok\":false,\"refusals\":[{\"exitCode\":60,\"code\":\"version-mismatch\",\"detail\":\"other engine\"}]}");
        var manifest = new TransferManifest
        {
            SchemaVersion = 1,
            EngineVersion = "4.0.0",
            Instance = new TransferInstance
            {
                Id = "a", Blueprint = "factorio", Runtime = TheKrystalShip.KGSM.Engine.Contracts.Blueprints.BlueprintRuntime.Native,
                DisplayName = "", Autostart = false, HasRun = false, Library = "main", Ports = [],
            },
            Blueprint = new TransferBlueprint { Name = "factorio", Custom = false, Sha256 = "x" },
            Requirements = [],
            Parts = [],
        };

        var result = await Cli(process).ImportCheckAsync(manifest);

        Assert.Equal(60, result.ExitCode);
        Assert.False(result.Value!.Ok);
        Assert.Equal("version-mismatch", result.Value.Refusals[0].Code);
        Assert.Contains("\"engineVersion\"", process.Input, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ABlueprintTravelsOnStandardInput()
    {
        var process = new RecordedProcess(0, "{\"name\":\"x\",\"path\":\"/p\",\"systemBlueprintInvolved\":false}");

        await Cli(process).CreateBlueprintAsync("x", "name: x\n");

        Assert.Equal("name: x\n", process.Input);
        Assert.Equal(["blueprint", "create", "x", "--json"], process.Arguments);
    }
}
