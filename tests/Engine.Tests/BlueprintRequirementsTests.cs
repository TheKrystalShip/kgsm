using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;

namespace TheKrystalShip.KGSM.Engine.Tests;

public class BlueprintRequirementsTests
{
    private sealed class FakeProbe(params string[] present) : IRequirementProbe
    {
        public bool IsPresent(string requirementId) => present.Contains(requirementId);
    }

    private static Blueprint Native(long steamAppId = 0, bool account = false) => new()
    {
        Name = "g",
        Runtime = BlueprintRuntime.Native,
        Metadata = new BlueprintMetadata(),
        Native = new NativeBlueprint { ExecutableFile = "s", SteamAppId = steamAppId, IsSteamAccountRequired = account },
    };

    [Fact]
    public void ANonSteamNativeGame_NeedsNothing()
    {
        Assert.Empty(BlueprintRequirementRules.IdsFor(Native()));
    }

    [Fact]
    public void ASteamGame_NeedsSteamcmd_AndAnAccountGameNeedsCredentialsToo()
    {
        Assert.Equal(["steamcmd"], BlueprintRequirementRules.IdsFor(Native(steamAppId: 294420)));
        Assert.Equal(["steamcmd", "steam-credentials"], BlueprintRequirementRules.IdsFor(Native(steamAppId: 294420, account: true)));
        Assert.Equal(["steam-credentials"], BlueprintRequirementRules.IdsFor(Native(account: true)));
    }

    [Fact]
    public void AContainerGame_NeedsTheContainerRuntime()
    {
        var container = new Blueprint
        {
            Name = "c",
            Runtime = BlueprintRuntime.Container,
            Metadata = new BlueprintMetadata(),
            Container = new ContainerBlueprint { Compose = "services: {}" },
        };

        Assert.Equal(["container-runtime"], BlueprintRequirementRules.IdsFor(container));
    }

    [Fact]
    public void EvaluatingAgainstAProbe_ReportsEachRequirement_AndWhetherAllArePresent()
    {
        BlueprintRequirements missing = BlueprintRequirementRules.Evaluate(Native(1, true), new FakeProbe("steamcmd"));
        BlueprintRequirements met = BlueprintRequirementRules.Evaluate(Native(1, true), new FakeProbe("steamcmd", "steam-credentials"));

        Assert.Equal("g", missing.Blueprint);
        Assert.Equal([new RequirementState("steamcmd", true), new RequirementState("steam-credentials", false)], missing.Requirements);
        Assert.False(missing.Satisfied);
        Assert.True(met.Satisfied);
        Assert.True(BlueprintRequirementRules.Evaluate(Native(), new FakeProbe()).Satisfied);
    }

    // --- the host's own measurement ---

    [Fact]
    public void SteamcmdIsPresent_WhenItIsOnPath()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.PathFor("bin", "steamcmd"), "#!/bin/sh");
        var probe = new HostRequirementProbe(
            name => name == "PATH" ? "/nonexistent:" + sandbox.PathFor("bin") : null, sandbox.PathFor("none.env"));

        Assert.True(probe.IsPresent("steamcmd"));
        Assert.False(new HostRequirementProbe(_ => "/nonexistent", sandbox.PathFor("none.env")).IsPresent("steamcmd"));
        Assert.False(new HostRequirementProbe(_ => null, sandbox.PathFor("none.env")).IsPresent("steamcmd"));
    }

    [Fact]
    public void TheContainerRuntime_NeedsDockerOnPath_AndComposeAnswering()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.PathFor("bin", "docker"), "#!/bin/sh");
        Func<string, string?> environment = name => name == "PATH" ? sandbox.PathFor("bin") : null;
        var asked = new List<string>();

        var answering = new HostRequirementProbe(environment, sandbox.PathFor("x"), (exe, args) => { asked.Add($"{exe} {string.Join(' ', args)}"); return true; });
        var failing = new HostRequirementProbe(environment, sandbox.PathFor("x"), (_, _) => false);
        var absent = new HostRequirementProbe(_ => "/nonexistent", sandbox.PathFor("x"), (_, _) => true);

        Assert.True(answering.IsPresent("container-runtime"));
        Assert.Equal(["docker compose version"], asked);
        Assert.False(failing.IsPresent("container-runtime"));
        Assert.False(absent.IsPresent("container-runtime"));
    }

    [Fact]
    public void AnUnknownRequirement_IsNeverPresent()
    {
        Assert.False(new HostRequirementProbe(_ => null, "/none").IsPresent("anything-else"));
    }

    [Fact]
    public void Credentials_ComeFromTheEnvironment_ThenTheFile_AndTheEnvironmentWins()
    {
        var sandbox = Sandbox.Create();
        string file = sandbox.WriteFile(sandbox.PathFor("kgsm.env"), "# comment\nSTEAM_USERNAME=fromfile\nSTEAM_PASSWORD=\"quoted pass\"\nOTHER=x\n");

        SteamCredentials fromFile = SteamCredentials.Read(_ => null, file);
        SteamCredentials overridden = SteamCredentials.Read(name => name == "STEAM_USERNAME" ? "fromenv" : null, file);
        SteamCredentials none = SteamCredentials.Read(_ => null, sandbox.PathFor("missing.env"));

        Assert.Equal(new SteamCredentials("fromfile", "quoted pass"), fromFile);
        Assert.Equal(new SteamCredentials("fromenv", "quoted pass"), overridden);
        Assert.False(none.HasUsername);
        Assert.True(new HostRequirementProbe(_ => null, file).IsPresent("steam-credentials"));
        Assert.False(new HostRequirementProbe(_ => null, sandbox.PathFor("missing.env")).IsPresent("steam-credentials"));
    }

    [Fact]
    public void ALoginByStoredToken_NeedsNoPassword()
    {
        var sandbox = Sandbox.Create();
        string file = sandbox.WriteFile(sandbox.PathFor("kgsm.env"), "STEAM_USERNAME=someone\nSTEAM_PASSWORD=\n");

        SteamCredentials credentials = SteamCredentials.Read(_ => null, file);

        Assert.True(credentials.HasUsername);
        Assert.Equal(string.Empty, credentials.Password);
    }
}
