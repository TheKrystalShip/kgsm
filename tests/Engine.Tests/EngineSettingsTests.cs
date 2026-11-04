using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Configuration;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Engine.Tests;

[JsonSourceGenerationOptions(WriteIndented = false)]
[JsonSerializable(typeof(EngineSettings))]
internal sealed partial class SettingsJsonContext : JsonSerializerContext;

public class EngineSettingsTests
{
    private static readonly IReadOnlyDictionary<string, string?> NoEnvironment = new Dictionary<string, string?>();

    private static EngineSettings Load(Sandbox sandbox, IReadOnlyDictionary<string, string?>? environment = null) =>
        EngineSettingsLoader.Load(sandbox.Paths, environment ?? NoEnvironment).Settings;

    [Fact]
    public void WithoutAnyFile_TheClassDefaultsApply()
    {
        EngineSettings settings = Load(Sandbox.Create());

        Assert.Equal(string.Empty, settings.Libraries.DefaultLibrary);
        Assert.Equal(1024, settings.Libraries.InstallFreeSpaceMarginMb);
        Assert.Equal(2, settings.Instances.IdSuffixLength);
        Assert.Equal("/var/lib/kgsm/events", settings.Journal.Directory);
        Assert.Equal(90, settings.Journal.RetentionDays);
        Assert.Equal(10240, settings.Logging.File.MaxSizeKb);
        Assert.Equal(5, settings.Logging.File.MaxFiles);
        Assert.True(settings.Backups.Compress);
        Assert.True(settings.Watchdog.Enabled);
    }

    [Fact]
    public void ThePersonsFile_OverridesTheFileBesideTheBinary_KeyByKey()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.Paths.SystemSettingsFile, """{"Libraries":{"DefaultLibrary":"system","InstallFreeSpaceMarginMb":2048},"Downloads":{"TimeoutSeconds":90}}""");
        sandbox.WriteFile(sandbox.Paths.UserSettingsFile, """{"Libraries":{"DefaultLibrary":"mine"}}""");

        EngineSettings settings = Load(sandbox);

        Assert.Equal("mine", settings.Libraries.DefaultLibrary);
        Assert.Equal(2048, settings.Libraries.InstallFreeSpaceMarginMb);
        Assert.Equal(90, settings.Downloads.TimeoutSeconds);
    }

    [Fact]
    public void TheEnvironment_OverridesOneKeyOfEitherFile()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.Paths.SystemSettingsFile, """{"Libraries":{"DefaultLibrary":"system"}}""");
        sandbox.WriteFile(sandbox.Paths.UserSettingsFile, """{"Libraries":{"DefaultLibrary":"mine"},"Journal":{"RetentionDays":30}}""");

        EngineSettings settings = Load(sandbox, new Dictionary<string, string?>
        {
            ["Libraries__DefaultLibrary"] = "env",
            ["Logging__File__MaxFiles"] = "2",
            ["UNRELATED"] = "x",
        });

        Assert.Equal("env", settings.Libraries.DefaultLibrary);
        Assert.Equal(2, settings.Logging.File.MaxFiles);
        Assert.Equal(30, settings.Journal.RetentionDays);
    }

    [Fact]
    public void AVariableNamingAKeyTheClassDoesNotDeclare_BindsToNothing()
    {
        EngineSettings settings = Load(Sandbox.Create(), new Dictionary<string, string?> { ["Libraries__Invented"] = "x" });

        Assert.Equal(string.Empty, settings.Libraries.DefaultLibrary);
    }

    [Fact]
    public void AFileThatIsNotJson_IsRefusedNamingTheFile()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.Paths.UserSettingsFile, "{ not json");

        var refusal = Assert.Throws<EngineFormatException>(() => Load(sandbox));

        Assert.Equal(sandbox.Paths.UserSettingsFile, refusal.Path);
    }

    [Fact]
    public void EveryFloorBroken_IsListed_NotTheFirst()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.Paths.UserSettingsFile, """
            {"Instances":{"IdSuffixLength":0,"StopCommandTimeoutSeconds":-1,"MaintenanceWindows":"nonsense"},
             "Downloads":{"TimeoutSeconds":0},"Logging":{"File":{"MaxSizeKb":0}}}
            """);

        var refusal = Assert.Throws<InvalidSettingsException>(() => Load(sandbox));

        Assert.Equal(5, refusal.Problems.Count);
        Assert.Contains(refusal.Problems, p => p.StartsWith("Instances:IdSuffixLength", StringComparison.Ordinal));
        Assert.Contains(refusal.Problems, p => p.StartsWith("Instances:StopCommandTimeoutSeconds", StringComparison.Ordinal));
        Assert.Contains(refusal.Problems, p => p.StartsWith("Instances:MaintenanceWindows", StringComparison.Ordinal));
        Assert.Contains(refusal.Problems, p => p.StartsWith("Downloads:TimeoutSeconds", StringComparison.Ordinal));
        Assert.Contains(refusal.Problems, p => p.StartsWith("Logging:File:MaxSizeKb", StringComparison.Ordinal));
    }

    [Fact]
    public void ABlankNumberInTheEnvironment_KeepsTheDefault()
    {
        EngineSettings settings = Load(Sandbox.Create(), new Dictionary<string, string?> { ["Downloads__TimeoutSeconds"] = "" });

        Assert.Equal(60, settings.Downloads.TimeoutSeconds);
    }

    // The file shipped beside the binary is the lowest-precedence source and declares the whole surface
    // with its defaults. It and the class must agree key for key, or the panel would show a default the
    // engine does not start with.

    [Fact]
    public void TheShippedSettingsFile_DeclaresEveryKeyOfTheClass_WithItsDefault()
    {
        string shipped = Path.Combine(AppContext.BaseDirectory, "kgsm.settings.json");
        var sandbox = Sandbox.Create();
        File.Copy(shipped, Directory.CreateDirectory(sandbox.InstallRoot).FullName + "/kgsm.settings.json");

        EngineSettings fromFile = Load(sandbox);
        EngineSettings defaults = new();

        Assert.Equal(
            JsonSerializer.Serialize(defaults, SettingsJsonContext.Default.EngineSettings),
            JsonSerializer.Serialize(fromFile, SettingsJsonContext.Default.EngineSettings));

        Assert.Equal(KeysOf(JsonSerializer.Serialize(defaults, SettingsJsonContext.Default.EngineSettings)), KeysOfFile(shipped, except: "Logging:LogLevel:Default"));
    }

    [Fact]
    public void TheShippedSettingsFile_NamesTheDefaultLogLevel()
    {
        var config = new ConfigurationBuilder().AddJsonFile(Path.Combine(AppContext.BaseDirectory, "kgsm.settings.json")).Build();

        Assert.Equal("Information", config["Logging:LogLevel:Default"]);
    }

    private static string[] KeysOf(string json)
    {
        using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(json));
        return Flatten(new ConfigurationBuilder().AddJsonStream(stream).Build(), except: null);
    }

    private static string[] KeysOfFile(string path, string except) =>
        Flatten(new ConfigurationBuilder().AddJsonFile(path).Build(), except);

    private static string[] Flatten(IConfigurationRoot config, string? except) =>
        config.AsEnumerable().Where(p => p.Value is not null && p.Key != except).Select(p => p.Key).Order(StringComparer.Ordinal).ToArray();
}
