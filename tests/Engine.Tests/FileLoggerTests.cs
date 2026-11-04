using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using TheKrystalShip.KGSM.Engine.Logging;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Engine.Tests;

public class FileLoggerTests
{
    private static readonly DateTimeOffset Start = new(2026, 11, 4, 10, 15, 30, 123, TimeSpan.Zero);

    private static (ILogger Logger, string Path) Open(Sandbox sandbox, long maxBytes = 1_000_000, int maxFiles = 5, TimeProvider? clock = null)
    {
        string path = sandbox.PathFor("logs", "kgsm.log");
        var provider = new FileLoggerProvider(
            new FileLoggerOptions { Path = path, MaxSizeBytes = maxBytes, MaxFiles = maxFiles },
            clock ?? new FakeTimeProvider(Start));
        return (provider.CreateLogger("Cat"), path);
    }

    [Fact]
    public void ALine_IsTheSimpleConsoleFormat_WithAUtcTimestamp()
    {
        var (logger, path) = Open(Sandbox.Create());

        logger.LogInformation(new EventId(7), "installed {Id}", "factorio-1");

        Assert.Equal("2026-11-04T10:15:30.123Z info: Cat[7]\n      installed factorio-1\n", File.ReadAllText(path));
    }

    [Theory]
    [InlineData(LogLevel.Trace, "trce")]
    [InlineData(LogLevel.Debug, "dbug")]
    [InlineData(LogLevel.Information, "info")]
    [InlineData(LogLevel.Warning, "warn")]
    [InlineData(LogLevel.Error, "fail")]
    [InlineData(LogLevel.Critical, "crit")]
    public void EachLevel_HasItsSimpleConsoleTag(LogLevel level, string tag)
    {
        var (logger, path) = Open(Sandbox.Create());

        logger.Log(level, "m");

        Assert.Contains($" {tag}: Cat[0]\n", File.ReadAllText(path), StringComparison.Ordinal);
    }

    [Fact]
    public void AMultiLineMessageAndAnException_AreIndentedUnderTheLine()
    {
        var (logger, path) = Open(Sandbox.Create());

        logger.LogError(new InvalidOperationException("boom"), "first\nsecond");

        string text = File.ReadAllText(path);
        Assert.StartsWith("2026-11-04T10:15:30.123Z fail: Cat[0]\n      first\n      second\n      System.InvalidOperationException: boom", text, StringComparison.Ordinal);
    }

    [Fact]
    public void WhenTheFileReachesItsSize_ItRotates_AndKeepsABoundedNumberOfFiles()
    {
        var (logger, path) = Open(Sandbox.Create(), maxBytes: 100, maxFiles: 2);

        for (int i = 0; i < 12; i++) logger.LogInformation("entry number {N} padded out to be long enough", i);

        Assert.True(File.Exists(path));
        Assert.True(File.Exists(path + ".1"));
        Assert.True(File.Exists(path + ".2"));
        Assert.False(File.Exists(path + ".3"));
        Assert.Contains("entry number 11", File.ReadAllText(path), StringComparison.Ordinal);
        Assert.DoesNotContain("entry number 0 ", File.ReadAllText(path + ".1") + File.ReadAllText(path + ".2"), StringComparison.Ordinal);
    }

    [Fact]
    public void RotatedFilesPastTheBound_AreRemoved_WhateverBoundAnEarlierRunKept()
    {
        var sandbox = Sandbox.Create();
        var (logger, path) = Open(sandbox, maxBytes: 50, maxFiles: 1);
        File.WriteAllText(path + ".1", "old1");
        File.WriteAllText(path + ".2", "old2");
        File.WriteAllText(path + ".4", "old4");
        File.WriteAllText(path, new string('x', 80));

        logger.LogInformation("trigger");

        Assert.True(File.Exists(path + ".1"));
        Assert.False(File.Exists(path + ".2"));
        Assert.False(File.Exists(path + ".4"));
    }

    [Fact]
    public void WithNoRotatedFilesKept_TheFullFileIsDiscarded()
    {
        var (logger, path) = Open(Sandbox.Create(), maxBytes: 50, maxFiles: 0);
        File.WriteAllText(path, new string('x', 80));

        logger.LogInformation("fresh");

        Assert.False(File.Exists(path + ".1"));
        Assert.DoesNotContain("xxx", File.ReadAllText(path), StringComparison.Ordinal);
    }

    [Fact]
    public void AnUnwritableLog_NeverFailsTheCaller()
    {
        var sandbox = Sandbox.Create();
        string blocker = sandbox.WriteFile(sandbox.PathFor("blocker"), "a file where a directory is needed");
        var provider = new FileLoggerProvider(
            new FileLoggerOptions { Path = Path.Combine(blocker, "kgsm.log"), MaxSizeBytes = 100, MaxFiles = 1 });

        Exception? failure = Record.Exception(() => provider.CreateLogger("c").LogError("lost"));

        Assert.Null(failure);
    }

    [Fact]
    public void ManyThreadsAppending_NeverInterleaveWithinAnEntry()
    {
        var (logger, path) = Open(Sandbox.Create());

        Parallel.For(0, 200, i => logger.LogInformation("entry-{N}-end", i));

        string[] lines = File.ReadAllLines(path);
        Assert.Equal(200 * 2, lines.Length);
        Assert.Equal(200, lines.Count(l => l.StartsWith("      entry-", StringComparison.Ordinal) && l.EndsWith("-end", StringComparison.Ordinal)));
    }

    [Fact]
    public void TheLevel_IsTheConfiguredDefault_AndTheEnvironmentOverridesTheFile()
    {
        var sandbox = Sandbox.Create();
        sandbox.WriteFile(sandbox.Paths.SystemSettingsFile, """{"Logging":{"LogLevel":{"Default":"Warning"}}}""");

        EngineConfiguration quiet = EngineSettingsLoader.Load(sandbox.Paths, new Dictionary<string, string?>());
        using (ILoggerFactory factory = EngineLogging.CreateFactory(quiet, sandbox.Paths))
        {
            factory.CreateLogger("c").LogInformation("hidden");
            factory.CreateLogger("c").LogWarning("shown");
        }

        EngineConfiguration loud = EngineSettingsLoader.Load(sandbox.Paths, new Dictionary<string, string?> { ["Logging__LogLevel__Default"] = "Debug" });
        using (ILoggerFactory factory = EngineLogging.CreateFactory(loud, sandbox.Paths))
        {
            factory.CreateLogger("c").LogDebug("debug-shown");
        }

        string text = File.ReadAllText(sandbox.Paths.LogFile);
        Assert.DoesNotContain("hidden", text, StringComparison.Ordinal);
        Assert.Contains("shown", text, StringComparison.Ordinal);
        Assert.Contains("debug-shown", text, StringComparison.Ordinal);
    }

    [Fact]
    public void WithNoLevelConfigured_InformationIsTheDefault()
    {
        var sandbox = Sandbox.Create();
        EngineConfiguration configuration = EngineSettingsLoader.Load(sandbox.Paths, new Dictionary<string, string?>());

        using (ILoggerFactory factory = EngineLogging.CreateFactory(configuration, sandbox.Paths))
        {
            factory.CreateLogger("c").LogDebug("debug-hidden");
            factory.CreateLogger("c").LogInformation("info-shown");
        }

        string text = File.ReadAllText(sandbox.Paths.LogFile);
        Assert.DoesNotContain("debug-hidden", text, StringComparison.Ordinal);
        Assert.Contains("info-shown", text, StringComparison.Ordinal);
    }
}
