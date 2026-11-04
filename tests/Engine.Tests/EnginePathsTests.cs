using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Tests;

public class EnginePathsTests
{
    private static EnginePaths Resolve(Dictionary<string, string> environment, string home = "/home/fallback") =>
        EnginePaths.Resolve(name => environment.GetValueOrDefault(name), "/opt/kgsm-install", home);

    [Fact]
    public void XdgVariables_PlaceEveryDirectory()
    {
        EnginePaths paths = Resolve(new()
        {
            ["XDG_CONFIG_HOME"] = "/x/config",
            ["XDG_DATA_HOME"] = "/x/data",
            ["XDG_STATE_HOME"] = "/x/state",
        });

        Assert.Equal("/x/config/kgsm/kgsm.settings.json", paths.UserSettingsFile);
        Assert.Equal("/x/data/kgsm/instances.json", paths.InstanceRegistryFile);
        Assert.Equal("/x/data/kgsm/libraries.json", paths.LibraryRegistryFile);
        Assert.Equal("/x/data/kgsm/blueprints", paths.UserBlueprintsDirectory);
        Assert.Equal("/x/data/kgsm/overrides", paths.UserOverridesDirectory);
        Assert.Equal("/x/data/kgsm/backups", paths.DefaultBackupsDirectory);
        Assert.Equal("/x/state/kgsm/logs/kgsm.log", paths.LogFile);
    }

    [Fact]
    public void WithoutXdgVariables_FallbackUnderHome()
    {
        EnginePaths paths = Resolve(new() { ["HOME"] = "/home/someone" });

        Assert.Equal("/home/someone/.config/kgsm/kgsm.settings.json", paths.UserSettingsFile);
        Assert.Equal("/home/someone/.local/share/kgsm/instances.json", paths.InstanceRegistryFile);
        Assert.Equal("/home/someone/.local/state/kgsm/logs", paths.LogDirectory);
    }

    [Fact]
    public void HomeFallbackIsUsedWhenHomeIsUnset()
    {
        EnginePaths paths = Resolve([], home: "/home/fallback");

        Assert.Equal("/home/fallback/.local/share/kgsm", paths.DataDirectory);
    }

    [Theory]
    [InlineData("")]
    [InlineData("relative/dir")]
    public void AnEmptyOrRelativeXdgVariable_IsIgnored(string value)
    {
        EnginePaths paths = Resolve(new() { ["HOME"] = "/home/h", ["XDG_DATA_HOME"] = value, ["XDG_CONFIG_HOME"] = value, ["XDG_STATE_HOME"] = value });

        Assert.Equal("/home/h/.local/share", paths.DataHome);
        Assert.Equal("/home/h/.config", paths.ConfigHome);
        Assert.Equal("/home/h/.local/state", paths.StateHome);
    }

    [Fact]
    public void SystemFiles_SitBesideTheBinary()
    {
        EnginePaths paths = EnginePaths.Resolve(_ => null, "/opt/kgsm-install/", "/h");

        Assert.Equal("/opt/kgsm-install", paths.InstallRoot);
        Assert.Equal("/opt/kgsm-install/kgsm.settings.json", paths.SystemSettingsFile);
        Assert.Equal("/opt/kgsm-install/blueprints", paths.SystemBlueprintsDirectory);
        Assert.Equal("/opt/kgsm-install/overrides", paths.SystemOverridesDirectory);
    }

    [Fact]
    public void Report_NamesEveryResolvedPath()
    {
        EnginePaths paths = Resolve(new() { ["HOME"] = "/h" });

        var report = paths.ToReport();

        Assert.Equal(paths.UserSettingsFile, report.UserSettingsFile);
        Assert.Equal(paths.SystemBlueprintsDirectory, report.SystemBlueprintsDirectory);
        Assert.Equal(paths.LocksDirectory, report.LocksDirectory);
        Assert.Equal("/etc/kgsm/kgsm.env", report.SteamCredentialsFile);
        Assert.All(
            [report.ConfigHome, report.DataHome, report.StateHome, report.InstallRoot, report.UserSettingsFile,
                report.SystemSettingsFile, report.InstanceRegistryFile, report.LibraryRegistryFile,
                report.UserBlueprintsDirectory, report.SystemBlueprintsDirectory, report.UserOverridesDirectory,
                report.SystemOverridesDirectory, report.DefaultBackupsDirectory, report.LogDirectory, report.LogFile,
                report.LocksDirectory],
            path => Assert.True(Path.IsPathRooted(path)));
    }
}
