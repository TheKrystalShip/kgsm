using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;

namespace TheKrystalShip.KGSM.Engine.Tests;

public class BlueprintTests
{
    private static string ShippedDirectory => Path.Combine(AppContext.BaseDirectory, "blueprints");

    private static readonly BlueprintParser Parser = new();

    private static BlueprintParseResult ParseText(string yaml) => Parser.Parse(yaml, "/test/x.bp.yaml");

    private const string ValidNative = """
        schema_version: 1
        name: mygame
        runtime: native
        metadata:
          display_name: "My Game"
          max_players: null
        native:
          executable_file: server
        """;

    // --- the blueprints the engine ships ---

    public static TheoryData<string> ShippedFiles()
    {
        var data = new TheoryData<string>();
        foreach (string file in Directory.EnumerateFiles(ShippedDirectory, "*.bp.yaml").Order(StringComparer.Ordinal))
            data.Add(Path.GetFileName(file));
        return data;
    }

    [Fact]
    public void TheShippedBlueprints_AreAllThere()
    {
        Assert.NotEmpty(Directory.EnumerateFiles(ShippedDirectory, "*.bp.yaml"));
    }

    [Theory]
    [MemberData(nameof(ShippedFiles))]
    public void EveryShippedBlueprint_Validates(string fileName)
    {
        BlueprintParseResult result = Parser.ParseFile(Path.Combine(ShippedDirectory, fileName));

        Assert.True(result.Valid, string.Join("; ", result.Validation.Errors));
        Assert.NotNull(result.Blueprint);
        Assert.Equal(fileName[..^".bp.yaml".Length], result.Blueprint.Name);
    }

    [Fact]
    public void ANativeBlueprint_ReadsFieldForField()
    {
        Blueprint terraria = Parser.ParseFile(Path.Combine(ShippedDirectory, "terraria.bp.yaml")).Blueprint!;

        Assert.Equal(BlueprintRuntime.Native, terraria.Runtime);
        Assert.Null(terraria.Container);
        Assert.Equal("Terraria", terraria.Metadata.DisplayName);
        Assert.Equal(255, terraria.Metadata.MaxPlayers);
        Assert.Equal(1024, terraria.Metadata.MinRamMb);
        Assert.Equal("kick {name}", terraria.KickCommand);
        Assert.Equal(string.Empty, terraria.UnbanCommand);
        Assert.Equal("say {message}", terraria.BroadcastCommand);
        Assert.Null(terraria.RconPort);
        Assert.Equal(10, terraria.RconPollIntervalSeconds);

        NativeBlueprint native = terraria.Native!;
        Assert.Equal("7777/tcp", native.Ports);
        Assert.Equal(0, native.SteamAppId);
        Assert.Equal(105600, native.ClientSteamAppId);
        Assert.False(native.IsSteamAccountRequired);
        Assert.Equal("TerrariaServer.bin.x86_64", native.ExecutableFile);
        Assert.Equal(
            "-world $instance_saves_dir/$instance_level_name -autocreate 3 -worldname $instance_level_name",
            native.ExecutableArguments);
        Assert.Equal("Server started", native.StartupSuccessRegex);
    }

    [Fact]
    public void UnknownMetadataFigures_StayNull_NeverZero()
    {
        Blueprint factorio = Parser.ParseFile(Path.Combine(ShippedDirectory, "factorio.bp.yaml")).Blueprint!;

        Assert.Null(factorio.Metadata.MaxPlayers);
        Assert.Equal(289, factorio.Metadata.BaseDiskMb);
    }

    [Fact]
    public void ARconPortThatIsANumber_IsRead_AndAnEmptyOneIsNull()
    {
        Assert.Equal(27015, Parser.ParseFile(Path.Combine(ShippedDirectory, "projectzomboid.bp.yaml")).Blueprint!.RconPort);
        Assert.Null(Parser.ParseFile(Path.Combine(ShippedDirectory, "factorio.bp.yaml")).Blueprint!.RconPort);
    }

    [Fact]
    public void AContainerBlueprint_KeepsItsComposeByteForByte()
    {
        string file = Path.Combine(ShippedDirectory, "enshrouded.bp.yaml");
        string[] lines = File.ReadAllLines(file);
        int start = Array.FindIndex(lines, l => l == "  compose: |-") + 1;
        string expected = string.Join('\n', lines.Skip(start).Select(l => l.Length >= 4 ? l[4..] : l));

        Blueprint blueprint = Parser.ParseFile(file).Blueprint!;

        Assert.Equal(BlueprintRuntime.Container, blueprint.Runtime);
        Assert.Null(blueprint.Native);
        Assert.Equal(expected, blueprint.Container!.Compose);
        Assert.Contains("${instance_backups_dir}", blueprint.Container.Compose, StringComparison.Ordinal);
    }

    // --- validation: every rule, every error ---

    [Fact]
    public void AMinimalNativeBlueprint_IsValid()
    {
        BlueprintParseResult result = ParseText(ValidNative);

        Assert.True(result.Valid);
        Assert.Empty(result.Validation.Errors);
        Assert.Equal("/test/x.bp.yaml", result.Validation.Path);
        Assert.Null(result.Blueprint!.Metadata.MaxPlayers);
    }

    [Fact]
    public void AnEmptyFile_IsRefused()
    {
        BlueprintParseResult result = ParseText("  \n");

        Assert.False(result.Valid);
        Assert.Equal(["Blueprint file is empty: /test/x.bp.yaml"], result.Validation.Errors);
    }

    [Fact]
    public void YamlThatDoesNotParse_IsRefused()
    {
        BlueprintParseResult result = ParseText("name: [unclosed\nruntime: native");

        Assert.Equal(["Invalid YAML syntax in blueprint: /test/x.bp.yaml"], result.Validation.Errors);
    }

    [Fact]
    public void AMissingNameAndABadRuntime_AreBothReported()
    {
        BlueprintParseResult result = ParseText("runtime: wasm\n");

        Assert.False(result.Valid);
        Assert.Equal(2, result.Validation.Errors.Count);
        Assert.Contains(result.Validation.Errors, e => e.Contains("missing required field 'name'", StringComparison.Ordinal));
        Assert.Contains(result.Validation.Errors, e => e.Contains("invalid or missing 'runtime'", StringComparison.Ordinal));
        Assert.Null(result.Blueprint);
    }

    [Fact]
    public void ANativeBlueprint_NeedsItsExecutable()
    {
        BlueprintParseResult result = ParseText("name: g\nruntime: native\nnative:\n  ports: '1'\n");

        Assert.Equal(["Native blueprint missing required field 'native.executable_file': /test/x.bp.yaml"], result.Validation.Errors);
    }

    [Fact]
    public void ANativeBlueprintWithNoNativeBlock_NeedsItsExecutable()
    {
        BlueprintParseResult result = ParseText("name: g\nruntime: native\n");

        Assert.Contains("native.executable_file", Assert.Single(result.Validation.Errors), StringComparison.Ordinal);
    }

    [Fact]
    public void AContainerBlueprint_NeedsItsCompose()
    {
        BlueprintParseResult result = ParseText("name: g\nruntime: container\n");

        Assert.Contains("container.compose", Assert.Single(result.Validation.Errors), StringComparison.Ordinal);
    }

    [Fact]
    public void AComposeWithNoServices_IsRefused()
    {
        BlueprintParseResult result = ParseText("name: g\nruntime: container\ncontainer:\n  compose: |-\n    version: '3'\n");

        Assert.Contains("defines no services", Assert.Single(result.Validation.Errors), StringComparison.Ordinal);
    }

    [Fact]
    public void EveryServiceMustBeHostNetworked()
    {
        BlueprintParseResult result = ParseText("""
            name: g
            runtime: container
            container:
              compose: |-
                services:
                  a:
                    network_mode: host
                  b:
                    image: x
            """);

        Assert.False(result.Valid);
        Assert.Contains("network_mode: host", Assert.Single(result.Validation.Errors), StringComparison.Ordinal);
    }

    [Fact]
    public void AHostNetworkedCompose_IsValid()
    {
        BlueprintParseResult result = ParseText("""
            name: g
            runtime: container
            container:
              compose: |-
                services:
                  a:
                    network_mode: host
                    ports:
                      - 1:1/udp
            """);

        Assert.True(result.Valid, string.Join("; ", result.Validation.Errors));
    }

    [Theory]
    [InlineData("Has Space")]
    [InlineData("UPPER")]
    [InlineData("../escape")]
    [InlineData("a/b")]
    public void ANameThatIsNotAFileAndDirectoryName_IsRefused(string name)
    {
        BlueprintParseResult result = ParseText($"name: \"{name}\"\nruntime: native\nnative:\n  executable_file: s\n");

        Assert.Contains("'name' must be lowercase", Assert.Single(result.Validation.Errors), StringComparison.Ordinal);
    }

    [Fact]
    public void ASchemaVersionThisEngineDoesNotKnow_IsRefused_AndAnAbsentOneIsAccepted()
    {
        Assert.Contains("schema_version '2'", Assert.Single(ParseText("schema_version: 2\n" + ValidNative.Replace("schema_version: 1\n", "")).Validation.Errors), StringComparison.Ordinal);
        Assert.True(ParseText(ValidNative.Replace("schema_version: 1\n", "")).Valid);
    }

    [Fact]
    public void AFigureThatIsNotANumber_IsAnErrorNotAGuess()
    {
        BlueprintParseResult result = ParseText("""
            name: g
            runtime: native
            metadata:
              max_players: lots
              base_disk_mb: "12"
            native:
              executable_file: s
              steam_app_id: abc
              is_steam_account_required: maybe
            """);

        Assert.Equal(3, result.Validation.Errors.Count);
        Assert.Contains(result.Validation.Errors, e => e.Contains("metadata.max_players", StringComparison.Ordinal));
        Assert.Contains(result.Validation.Errors, e => e.Contains("native.steam_app_id", StringComparison.Ordinal));
        Assert.Contains(result.Validation.Errors, e => e.Contains("native.is_steam_account_required", StringComparison.Ordinal));
    }

    [Fact]
    public void AnUnreadableFile_IsReportedAsAnError_NotThrown()
    {
        BlueprintParseResult result = Parser.ParseFile(Path.Combine(Sandbox.Create().Root, "missing.bp.yaml"));

        Assert.False(result.Valid);
        Assert.Contains("cannot be read", Assert.Single(result.Validation.Errors), StringComparison.Ordinal);
    }

    // --- resolution ---

    private static (Sandbox Sandbox, BlueprintCatalog Catalog) NewCatalog()
    {
        var sandbox = Sandbox.Create();
        return (sandbox, new BlueprintCatalog(sandbox.Paths, Parser));
    }

    private static string Native(string name) => $"name: {name}\nruntime: native\nnative:\n  executable_file: s\n";

    [Fact]
    public void AUserFile_ShadowsASystemFile_OfTheSameFileName()
    {
        var (sandbox, catalog) = NewCatalog();
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemBlueprintsDirectory, "game.bp.yaml"), Native("game"));
        string user = sandbox.WriteFile(Path.Combine(sandbox.Paths.UserBlueprintsDirectory, "game.bp.yaml"), Native("game") + "  ports: '9'\n");

        BlueprintResolution resolution = catalog.Find("game");

        Assert.Equal(user, resolution.Resolved);
        Assert.Equal(BlueprintTier.User, resolution.Tier);
        Assert.Equal([BlueprintTier.User, BlueprintTier.System], resolution.Candidates.Select(c => c.Tier));
        Assert.All(resolution.Candidates, c => Assert.True(c.Exists));
        Assert.Equal("9", catalog.Read("game")!.Blueprint!.Native!.Ports);
    }

    [Fact]
    public void ASystemOnlyFile_Resolves_AndANameWithNoFileDoesNot()
    {
        var (sandbox, catalog) = NewCatalog();
        string system = sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemBlueprintsDirectory, "game.bp.yaml"), Native("game"));

        BlueprintResolution found = catalog.Find("game");
        BlueprintResolution missing = catalog.Find("nothing");

        Assert.Equal(system, found.Resolved);
        Assert.Equal(BlueprintTier.System, found.Tier);
        Assert.False(found.Candidates[0].Exists);
        Assert.Null(missing.Resolved);
        Assert.Null(missing.Tier);
        Assert.All(missing.Candidates, c => Assert.False(c.Exists));
        Assert.Null(catalog.Read("nothing"));
    }

    [Fact]
    public void ABrokenFile_CanStillBeFound_ForRepair()
    {
        var (sandbox, catalog) = NewCatalog();
        string broken = sandbox.WriteFile(Path.Combine(sandbox.Paths.UserBlueprintsDirectory, "game.bp.yaml"), "name: [");

        Assert.Equal(broken, catalog.Find("game").Resolved);
        Assert.False(catalog.Read("game")!.Valid);
    }

    [Fact]
    public void AFileNameThatIsNotAKey_IsRefused()
    {
        Assert.Throws<ArgumentException>(() => NewCatalog().Catalog.Find("../etc/passwd"));
    }

    [Fact]
    public void TheListing_IsByFileName_ShadowingApplied_AndKeepsInvalidFilesWithTheirErrors()
    {
        var (sandbox, catalog) = NewCatalog();
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemBlueprintsDirectory, "b.bp.yaml"), Native("b"));
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemBlueprintsDirectory, "a.bp.yaml"), Native("a"));
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemBlueprintsDirectory, "notes.txt"), "ignored");
        sandbox.WriteFile(Path.Combine(sandbox.Paths.UserBlueprintsDirectory, "a.bp.yaml"), "name: [");
        sandbox.WriteFile(Path.Combine(sandbox.Paths.UserBlueprintsDirectory, "c.bp.yaml"), Native("c"));

        var listing = catalog.List();

        Assert.Equal(["a", "b", "c"], listing.Select(l => l.Key));
        Assert.Equal([BlueprintTier.User, BlueprintTier.System, BlueprintTier.User], listing.Select(l => l.Tier));
        Assert.Null(listing[0].Blueprint);
        Assert.NotEmpty(listing[0].Errors);
        Assert.Equal("b", listing[1].Blueprint!.Name);
    }

    [Fact]
    public void TheListing_OfNoDirectories_IsEmpty()
    {
        Assert.Empty(NewCatalog().Catalog.List());
    }

    [Fact]
    public void SeveralFilesMayShareOneName_AndOneHooksDirectory()
    {
        var (sandbox, catalog) = NewCatalog();
        sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemBlueprintsDirectory, "terraria.bp.yaml"), Native("terraria"));
        sandbox.WriteFile(Path.Combine(sandbox.Paths.UserBlueprintsDirectory, "terraria-modded.bp.yaml"), Native("terraria"));

        var listing = catalog.List();

        Assert.Equal(["terraria", "terraria"], listing.Select(l => l.Blueprint!.Name));
        Assert.Equal(["terraria", "terraria-modded"], listing.Select(l => l.Key));
    }

    [Fact]
    public void Hooks_AreFoundByTheBlueprintName_AndAUserFileReplacesTheSystemFile()
    {
        var (sandbox, catalog) = NewCatalog();
        string system = sandbox.WriteFile(Path.Combine(sandbox.Paths.SystemOverridesDirectory, "terraria", "hooks.sh"), "# system");

        Assert.Equal(system, catalog.FindHooks("terraria"));

        string user = sandbox.WriteFile(Path.Combine(sandbox.Paths.UserOverridesDirectory, "terraria", "hooks.sh"), "# user");

        Assert.Equal(user, catalog.FindHooks("terraria"));
        Assert.Null(catalog.FindHooks("factorio"));
        Assert.Null(catalog.FindHooks("../terraria"));
    }
}
