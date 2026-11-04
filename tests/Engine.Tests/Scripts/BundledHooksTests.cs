using System.Diagnostics;
using System.IO.Compression;
using TheKrystalShip.KGSM.Engine.Scripts;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>
/// The hooks files the six bundled games ship, run by the real script against a fake curl that serves what
/// each game's download site would: each one is acceptable to the generator, clean under shellcheck and does
/// the work its game needs.
/// </summary>
public class BundledHooksTests
{
    public static TheoryData<string> Games() => new() { "factorio", "minecraft", "terraria", "veloren", "barotrauma", "projectzomboid" };

    private static readonly Dictionary<string, string[]> Defined = new()
    {
        ["factorio"] = ["kgsm_hook_latest_version", "kgsm_hook_download", "kgsm_hook_post_deploy"],
        ["minecraft"] = ["kgsm_hook_latest_version", "kgsm_hook_download", "kgsm_hook_deploy", "kgsm_hook_post_deploy"],
        ["terraria"] = ["kgsm_hook_latest_version", "kgsm_hook_download", "kgsm_hook_deploy", "kgsm_hook_post_deploy"],
        ["veloren"] = ["kgsm_hook_latest_version", "kgsm_hook_download"],
        ["barotrauma"] = ["kgsm_hook_post_deploy"],
        ["projectzomboid"] = ["kgsm_hook_post_deploy", "_hook_write_launcher"],
    };

    private static string HooksPath(string game) => Path.Combine(AppContext.BaseDirectory, "overrides", game, "hooks.sh");

    private static string Hooks(string game) => File.ReadAllText(HooksPath(game));

    private static ScriptWorld World(string game, Func<Contracts.Instances.InstanceConfig, Contracts.Instances.InstanceConfig>? shape = null) =>
        ScriptWorld.Native(shape, Hooks(game), game);

    private static string Staging(ScriptWorld world) => Path.Combine(world.Temp, "download");

    // --- every file ---

    [Theory]
    [MemberData(nameof(Games))]
    public void EveryBundledHooksFile_IsAcceptableToTheGenerator(string game)
    {
        HookFiles.Validate(HooksPath(game), Hooks(game));
    }

    [Theory]
    [MemberData(nameof(Games))]
    public void EveryBundledHooksFile_DefinesExactlyTheHooksItsGameNeeds(string game)
    {
        Assert.Equal(Defined[game].Order(StringComparer.Ordinal), HookFiles.DefinedFunctions(Hooks(game)).Order(StringComparer.Ordinal));
    }

    [Theory]
    [MemberData(nameof(Games))]
    public async Task EveryBundledHooksFile_IsCleanUnderShellcheck(string game)
    {
        string? shellcheck = HostTools.Find("shellcheck");
        if (shellcheck is null) return;

        var start = new ProcessStartInfo(shellcheck) { UseShellExecute = false, RedirectStandardOutput = true };
        start.ArgumentList.Add("--shell=bash");
        start.ArgumentList.Add(HooksPath(game));
        using Process process = Process.Start(start)!;
        string output = await process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();

        Assert.True(process.ExitCode == 0, output);
    }

    [Theory]
    [MemberData(nameof(Games))]
    public void EveryBundledHooksFile_InlinesIntoAScriptThatPassesTheSyntaxCheck(string game)
    {
        using ScriptWorld world = World(game);

        Assert.Null(BashSyntax.Check(File.ReadAllText(world.ScriptPath)));
        Assert.Equal(world.Hooks!.Digest, ScriptHeader.Parse(File.ReadAllText(world.ScriptPath))!.HooksDigest);
    }

    // --- factorio ---

    private const string FactorioApi = "https://factorio.com/api/latest-releases";

    [Fact]
    public async Task Factorio_TheLatestVersionIsTheStableHeadlessRelease()
    {
        using ScriptWorld world = World("factorio", c => c with { DownloadTimeoutSeconds = 23 });
        world.Serve(FactorioApi, """{"stable":{"alpha":"2.0.9","headless":"2.0.8"},"experimental":{"headless":"2.1.0"}}""");

        ScriptRun run = await world.RunAsync("version", "--latest");

        Assert.Equal("2.0.8\n", run.Out);
        Assert.Equal("23\n", File.ReadAllText(world.Fake("curl/max-time")));
    }

    [Fact]
    public async Task Factorio_ASiteThatNamesNoStableRelease_IsUnknown()
    {
        using ScriptWorld world = World("factorio");
        world.Serve(FactorioApi, """{"stable":{}}""");

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
    }

    [Fact]
    public async Task Factorio_ASiteThatCannotBeReached_IsUnknown()
    {
        using ScriptWorld world = World("factorio");

        Assert.Equal("unknown\n", (await world.RunAsync("check-update")).Out);
    }

    [Fact]
    public async Task Factorio_TheArchiveIsUnpackedWithoutItsTopFolder()
    {
        using ScriptWorld world = World("factorio");
        world.Serve(FactorioApi, """{"stable":{"headless":"2.0.8"}}""");
        world.Serve("https://factorio.com/get-download/2.0.8/headless/linux64", TarXz(("factorio/bin/x64/factorio", "exe"), ("factorio/data/base/info.json", "{}")));

        Assert.Equal(0, (await world.RunAsync("download")).Exit);

        Assert.Equal("exe", File.ReadAllText(Path.Combine(Staging(world), "bin", "x64", "factorio")));
        Assert.True(File.Exists(Path.Combine(Staging(world), "data", "base", "info.json")));
        Assert.False(File.Exists(Path.Combine(Staging(world), "factorio_headless.tar.xz")));
    }

    [Fact]
    public async Task Factorio_ADeployCreatesTheSaveTheServerCannotStartWithout_WhenTheLevelHasNone()
    {
        using ScriptWorld world = FactorioWorld();
        PutStaged(world, ("bin/x64/factorio", "#!/usr/bin/env bash\n[[ \"$1\" == --create ]] && echo created >\"$2.zip\"\n"));

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(0, run.Exit);
        Assert.Equal("created\n", File.ReadAllText(Path.Combine(world.Saves, "default.zip")));
    }

    [Fact]
    public async Task Factorio_ADeployLeavesAnExistingSaveAlone()
    {
        using ScriptWorld world = FactorioWorld();
        PutStaged(world, ("bin/x64/factorio", "#!/usr/bin/env bash\necho invoked >\"" + Path.Combine(world.Sandbox.Root, "invoked") + "\"\n"));
        File.WriteAllText(Path.Combine(world.Saves, "default.zip"), "mine");

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        Assert.Equal("mine", File.ReadAllText(Path.Combine(world.Saves, "default.zip")));
        Assert.False(File.Exists(Path.Combine(world.Sandbox.Root, "invoked")));
    }

    [Fact]
    public async Task Factorio_ADeployFails_WhenTheSaveCannotBeCreated()
    {
        using ScriptWorld world = FactorioWorld();
        PutStaged(world, ("bin/x64/factorio", "#!/usr/bin/env bash\nexit 1\n"));

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(1, run.Exit);
        Assert.Contains("cannot start without it", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Factorio_AWholeUpdate_FetchesDeploysAndCreatesTheSave()
    {
        using ScriptWorld world = FactorioWorld();
        world.Serve(FactorioApi, """{"stable":{"headless":"2.0.8"}}""");
        world.Serve(
            "https://factorio.com/get-download/2.0.8/headless/linux64",
            TarXz(("factorio/bin/x64/factorio", "#!/usr/bin/env bash\n[[ \"$1\" == --create ]] && echo created >\"$2.zip\"\n")));
        File.WriteAllText(world.VersionFile, "2.0.7\n");
        File.WriteAllText(Path.Combine(world.Saves, "keep.zip"), "k");

        ScriptRun run = await world.RunAsync("update");

        Assert.Equal(0, run.Exit);
        Assert.Equal("updated 2.0.8\n", run.Out);
        Assert.True(File.Exists(Path.Combine(world.Saves, "default.zip")));
        Assert.Equal("2.0.8", File.ReadAllText(world.VersionFile).Trim());
    }

    private static ScriptWorld FactorioWorld()
    {
        ScriptWorld world = World("factorio", c => c with
        {
            ExecutableSubdirectory = "bin/x64",
            ExecutableFile = "./factorio",
            LevelName = "default",
        });
        File.Delete(Path.Combine(world.Install, "server"));
        return world;
    }

    // --- minecraft ---

    private const string MojangManifest = "https://launchermeta.mojang.com/mc/game/version_manifest.json";

    private static void ServeMinecraft(ScriptWorld world)
    {
        world.Serve(MojangManifest, """{"latest":{"release":"1.21.4","snapshot":"25w01a"},"versions":[{"id":"25w01a","url":"https://meta.example/25w01a.json"},{"id":"1.21.4","url":"https://meta.example/1.21.4.json"}]}""");
        world.Serve("https://meta.example/1.21.4.json", """{"downloads":{"client":{"url":"https://dl.example/client.jar"},"server":{"url":"https://dl.example/server.jar"}}}""");
        world.Serve("https://dl.example/server.jar", "jar bytes");
    }

    [Fact]
    public async Task Minecraft_TheLatestVersionIsTheLatestRelease_NotTheSnapshot()
    {
        using ScriptWorld world = World("minecraft");
        ServeMinecraft(world);

        Assert.Equal("1.21.4\n", (await world.RunAsync("version", "--latest")).Out);
    }

    [Fact]
    public async Task Minecraft_TheDownloadFetchesTheServerJarOfThatRelease()
    {
        using ScriptWorld world = World("minecraft");
        ServeMinecraft(world);

        Assert.Equal(0, (await world.RunAsync("download", "1.21.4")).Exit);

        Assert.Equal("jar bytes", File.ReadAllText(Path.Combine(Staging(world), "minecraft_server.1.21.4.jar")));
    }

    [Fact]
    public async Task Minecraft_ADownloadOfAVersionTheManifestDoesNotList_Fails()
    {
        using ScriptWorld world = World("minecraft");
        ServeMinecraft(world);

        ScriptRun run = await world.RunAsync("download", "0.0.1");

        Assert.Equal(1, run.Exit);
        Assert.Contains("0.0.1", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Minecraft_AReleaseThatNamesNoServerJar_Fails()
    {
        using ScriptWorld world = World("minecraft");
        ServeMinecraft(world);
        world.Serve("https://meta.example/1.21.4.json", """{"downloads":{"client":{"url":"https://dl.example/client.jar"}}}""");

        ScriptRun run = await world.RunAsync("download", "1.21.4");

        Assert.Equal(1, run.Exit);
        Assert.Contains("names no server jar", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Minecraft_TheDeployMovesTheJarToReleaseJar_AndAcceptsTheEula()
    {
        using ScriptWorld world = World("minecraft");
        PutStaged(world, ("minecraft_server.1.21.4.jar", "jar bytes"));

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        Assert.Equal("jar bytes", File.ReadAllText(Path.Combine(world.Install, "release.jar")));
        Assert.Equal("eula=true\n", File.ReadAllText(Path.Combine(world.Install, "eula.txt")));
        Assert.Empty(Directory.GetFileSystemEntries(Staging(world)));
    }

    [Fact]
    public async Task Minecraft_ADeployOfAStagingDirectoryWithNoJar_Fails()
    {
        using ScriptWorld world = World("minecraft");
        PutStaged(world, ("readme.txt", "x"));

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(1, run.Exit);
        Assert.Contains("no server jar", run.Err, StringComparison.Ordinal);
    }

    // --- terraria ---

    private const string TerrariaNames = "https://terraria.org/api/get/dedicated-servers-names";

    private static byte[] TerrariaZip(string version, bool withLinux = true)
    {
        string root = Path.Combine(Path.GetTempPath(), "zip-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(root);
        try
        {
            WriteTree(Path.Combine(root, version), ("Windows/TerrariaServer.exe", "win"), ("Mac/TerrariaServer.bin.osx", "mac"));
            if (withLinux) WriteTree(Path.Combine(root, version), ("Linux/TerrariaServer.bin.x86_64", "linux"), ("Linux/lib/libx.so", "lib"));
            string zip = Path.Combine(root + ".zip");
            ZipFile.CreateFromDirectory(root, zip);
            byte[] bytes = File.ReadAllBytes(zip);
            File.Delete(zip);
            return bytes;
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task Terraria_TheLatestVersionIsTheNumberInTheNewestArchivesName()
    {
        using ScriptWorld world = World("terraria");
        world.Serve(TerrariaNames, """["terraria-server-1453.zip","terraria-server-1449.zip"]""");

        Assert.Equal("1453\n", (await world.RunAsync("version", "--latest")).Out);
    }

    [Fact]
    public async Task Terraria_ANameThatHoldsNoNumber_IsUnknown()
    {
        using ScriptWorld world = World("terraria");
        world.Serve(TerrariaNames, """["terraria-server-latest.zip"]""");

        ScriptRun run = await world.RunAsync("check-update");

        Assert.Equal(1, run.Exit);
        Assert.Equal("unknown\n", run.Out);
    }

    [Fact]
    public async Task Terraria_TheDownloadKeepsOnlyTheLinuxFiles()
    {
        using ScriptWorld world = World("terraria");
        world.Serve("https://terraria.org/api/download/pc-dedicated-server/terraria-server-1453.zip", TerrariaZip("1453"));

        Assert.Equal(0, (await world.RunAsync("download", "1453")).Exit);

        Assert.Equal("linux", File.ReadAllText(Path.Combine(Staging(world), "TerrariaServer.bin.x86_64")));
        Assert.True(File.Exists(Path.Combine(Staging(world), "lib", "libx.so")));
        Assert.False(Directory.Exists(Path.Combine(Staging(world), "Windows")));
        Assert.False(Directory.Exists(Path.Combine(Staging(world), "Mac")));
        Assert.False(Directory.Exists(Path.Combine(Staging(world), "1453")));
        Assert.False(File.Exists(Path.Combine(Staging(world), "terraria-server-1453.zip")));
    }

    [Fact]
    public async Task Terraria_AnArchiveWithNoLinuxDirectory_FailsTheDownload()
    {
        using ScriptWorld world = World("terraria");
        world.Serve("https://terraria.org/api/download/pc-dedicated-server/terraria-server-1453.zip", TerrariaZip("1453", withLinux: false));

        ScriptRun run = await world.RunAsync("download", "1453");

        Assert.Equal(1, run.Exit);
        Assert.Contains("no Linux directory", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Terraria_TheDeployMovesTheFilesAndMakesTheServerExecutable()
    {
        using ScriptWorld world = World("terraria");
        PutStaged(world, ("TerrariaServer.bin.x86_64", "bin"), ("TerrariaServer", "wrapper"), ("lib/libx.so", "lib"), (".hidden", "h"));

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        Assert.Empty(Directory.GetFileSystemEntries(Staging(world)));
        Assert.Equal("h", File.ReadAllText(Path.Combine(world.Install, ".hidden")));
        Assert.Equal("lib", File.ReadAllText(Path.Combine(world.Install, "lib", "libx.so")));
        Assert.True(File.GetUnixFileMode(Path.Combine(world.Install, "TerrariaServer.bin.x86_64")).HasFlag(UnixFileMode.UserExecute));
        Assert.True(File.GetUnixFileMode(Path.Combine(world.Install, "TerrariaServer")).HasFlag(UnixFileMode.UserExecute));
    }

    [Fact]
    public async Task Terraria_ADeployWithNoServerBinary_Fails()
    {
        using ScriptWorld world = World("terraria");
        PutStaged(world, ("readme.txt", "x"));

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(1, run.Exit);
        Assert.Contains("No TerrariaServer binary", run.Err, StringComparison.Ordinal);
    }

    // --- veloren ---

    [Fact]
    public async Task Veloren_TheLatestVersionIsTheFixedNameWeekly_WithoutAskingTheNetwork()
    {
        using ScriptWorld world = World("veloren");

        Assert.Equal("weekly\n", (await world.RunAsync("version", "--latest")).Out);
        Assert.Empty(world.Recorded("curl/log"));
    }

    [Fact]
    public async Task Veloren_TheDownloadUnpacksTheWeeklyBuild_AndLeavesNoArchive()
    {
        using ScriptWorld world = World("veloren");
        string root = Path.Combine(world.Sandbox.Root, "veloren-zip");
        WriteTree(root, ("veloren-server-cli", "server"), ("assets/a.ron", "a"));
        string zip = Path.Combine(world.Sandbox.Root, "weekly.zip");
        ZipFile.CreateFromDirectory(root, zip);
        world.Serve("https://download.veloren.net/latest/linux/x86_64/weekly", File.ReadAllBytes(zip));

        Assert.Equal(0, (await world.RunAsync("download")).Exit);

        Assert.Equal("server", File.ReadAllText(Path.Combine(Staging(world), "veloren-server-cli")));
        Assert.True(File.Exists(Path.Combine(Staging(world), "assets", "a.ron")));
        Assert.False(File.Exists(Path.Combine(Staging(world), "weekly")));
    }

    // --- barotrauma ---

    [Fact]
    public async Task Barotrauma_ADeployCreatesTheDirectoryTheServerKeepsItsSettingsIn()
    {
        using ScriptWorld world = World("barotrauma");
        PutStaged(world, ("DedicatedServer", "bin"));

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        Assert.True(Directory.Exists(Path.Combine(world.Environment["HOME"], ".local", "share", "Daedalic Entertainment GmbH", "Barotrauma")));
        Assert.True(File.Exists(Path.Combine(world.Install, "DedicatedServer")));
    }

    [Fact]
    public async Task Barotrauma_ADeployWithNoHome_Fails()
    {
        using ScriptWorld world = World("barotrauma");
        PutStaged(world, ("DedicatedServer", "bin"));
        world.Environment.Remove("HOME");

        ScriptRun run = await world.RunAsync("deploy");

        Assert.Equal(1, run.Exit);
        Assert.Contains("HOME is not set", run.Err, StringComparison.Ordinal);
    }

    // --- project zomboid ---

    [Fact]
    public async Task ProjectZomboid_EveryDeployReplacesTheShippedLauncherWithOneThatReportsTheServersExitCode()
    {
        using ScriptWorld world = World("projectzomboid");
        PutStaged(world, ("start-server.sh", "#!/bin/bash\n./ProjectZomboid64 \"$@\"\nexit 0\n"), ("ProjectZomboid64", "bin"));

        Assert.Equal(0, (await world.RunAsync("deploy")).Exit);

        string launcher = Path.Combine(world.Install, "start-server.sh");
        string text = File.ReadAllText(launcher);
        Assert.Contains("exec ./ProjectZomboid64 \"$@\"", text, StringComparison.Ordinal);
        Assert.DoesNotMatch("(?m)^exit 0", text);
        Assert.True(File.GetUnixFileMode(launcher).HasFlag(UnixFileMode.UserExecute));
        Assert.Null(BashSyntax.Check(text));
        Assert.Equal("bin", File.ReadAllText(Path.Combine(world.Install, "ProjectZomboid64")));
    }

    [Fact]
    public async Task ProjectZomboid_TheLauncherRunsTheServerAndReturnsItsExitCode()
    {
        using ScriptWorld world = World("projectzomboid");
        PutStaged(world, ("start-server.sh", "#!/bin/bash\nexit 0\n"));
        Directory.CreateDirectory(Path.Combine(world.Install, "jre64", "bin"));
        await world.RunAsync("deploy");
        File.WriteAllText(Path.Combine(world.Install, "jre64", "bin", "java"), "#!/usr/bin/env bash\nexit 0\n");
        File.SetUnixFileMode(Path.Combine(world.Install, "jre64", "bin", "java"), UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        File.WriteAllText(Path.Combine(world.Install, "ProjectZomboid64"), "#!/usr/bin/env bash\nexit 7\n");
        File.SetUnixFileMode(Path.Combine(world.Install, "ProjectZomboid64"), UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);

        var start = new ProcessStartInfo(HostTools.Find("bash")!) { UseShellExecute = false };
        start.ArgumentList.Add(Path.Combine(world.Install, "start-server.sh"));
        start.Environment.Clear();
        start.Environment["PATH"] = world.Environment["PATH"];
        using Process launcher = Process.Start(start)!;
        await launcher.WaitForExitAsync();

        Assert.Equal(7, launcher.ExitCode);
    }

    // --- helpers ---

    private static void PutStaged(ScriptWorld world, params (string Path, string Content)[] files)
    {
        WriteTree(Staging(world), files);
        foreach ((string path, string content) in files)
        {
            if (content.StartsWith("#!", StringComparison.Ordinal))
                File.SetUnixFileMode(Path.Combine(Staging(world), path), UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
    }

    private static void WriteTree(string root, params (string Path, string Content)[] files)
    {
        foreach ((string path, string content) in files)
        {
            string full = Path.Combine(root, path);
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllText(full, content);
        }
    }

    private static byte[] TarXz(params (string Path, string Content)[] files)
    {
        string root = Path.Combine(Path.GetTempPath(), "tar-" + Guid.NewGuid().ToString("N")[..8]);
        try
        {
            WriteTree(root, files);
            foreach ((string path, string content) in files)
            {
                if (content.StartsWith("#!", StringComparison.Ordinal))
                    File.SetUnixFileMode(Path.Combine(root, path), UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            }

            string archive = root + ".tar.xz";
            var start = new ProcessStartInfo(HostTools.Find("tar")!) { UseShellExecute = false };
            foreach (string argument in (string[])["-cJf", archive, "-C", root, .. files.Select(f => f.Path.Split('/')[0]).Distinct()])
                start.ArgumentList.Add(argument);
            using Process tar = Process.Start(start)!;
            tar.WaitForExit();
            Assert.Equal(0, tar.ExitCode);
            byte[] bytes = File.ReadAllBytes(archive);
            File.Delete(archive);
            return bytes;
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }
}
