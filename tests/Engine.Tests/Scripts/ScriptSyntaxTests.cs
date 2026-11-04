using System.Diagnostics;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>Every variant of the generated script is valid bash and clean under shellcheck.</summary>
public class ScriptSyntaxTests
{
    private const string AllHooks = """
        kgsm_hook_latest_version() { echo 1; }
        kgsm_hook_download() { echo x >"$2/f"; }
        kgsm_hook_deploy() { cp -a "$1/." "$2/"; }
        kgsm_hook_post_deploy() { _hook_touch "$1"; }
        _hook_touch() { touch "$1/done"; }
        """;

    public static TheoryData<string> Variants() => new() { "native", "native-hooks", "container" };

    private static string Render(string variant)
    {
        using ScriptWorld world = variant == "container"
            ? ScriptWorld.Container()
            : ScriptWorld.Native(hooks: variant == "native-hooks" ? AllHooks : null);
        return File.ReadAllText(world.ScriptPath);
    }

    [Theory]
    [MemberData(nameof(Variants))]
    public void EveryVariant_PassesBashSyntaxCheck(string variant)
    {
        Assert.Null(BashSyntax.Check(Render(variant)));
    }

    [Theory]
    [MemberData(nameof(Variants))]
    public async Task EveryVariant_PassesShellcheck(string variant)
    {
        string? shellcheck = HostTools.Find("shellcheck");
        if (shellcheck is null) return;

        string script = Render(variant);
        var start = new ProcessStartInfo(shellcheck)
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        start.ArgumentList.Add("--shell=bash");
        start.ArgumentList.Add("-");

        using Process process = Process.Start(start)!;
        process.StandardInput.Write(script);
        process.StandardInput.Close();
        string output = await process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();

        Assert.True(process.ExitCode == 0, output);
    }

    [Theory]
    [MemberData(nameof(Variants))]
    public void EveryVariant_RecordsItsTemplateVersionHooksDigestAndRuntime(string variant)
    {
        ScriptHeader? header = ScriptHeader.Parse(Render(variant));

        Assert.NotNull(header);
        Assert.Equal(ScriptTemplate.Version, header.TemplateVersion);
        Assert.Equal(variant == "container" ? BlueprintRuntime.Container : BlueprintRuntime.Native, header.Runtime);
        Assert.Equal(variant == "native-hooks" ? 64 : 4, header.HooksDigest.Length);
    }
}
