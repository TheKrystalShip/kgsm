using TheKrystalShip.Testing;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>Console input, save, announcements and moderation, through a native instance's console pipe.</summary>
public class ScriptConsoleTests
{
    [Fact]
    public async Task Input_WritesTheLineToTheGame()
    {
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();

        Assert.Equal(0, (await world.RunAsync("input", "say hello there")).Exit);

        await Eventually.Holds(() => world.Recorded("game/input").Contains("say hello there"), "the game read the line");
    }

    [Theory]
    [InlineData(";")]
    [InlineData("&")]
    [InlineData("|")]
    [InlineData("`")]
    [InlineData("$")]
    [InlineData("$(id)")]
    [InlineData(")")]
    [InlineData("{")]
    [InlineData("}")]
    [InlineData("[")]
    [InlineData("]")]
    [InlineData("\\")]
    [InlineData("<")]
    [InlineData(">")]
    [InlineData("*")]
    [InlineData("?")]
    [InlineData("~")]
    [InlineData("!")]
    public async Task Input_RejectsEachCharacterThatCouldTurnALineIntoSomethingElse(string character)
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.MakeFifo(world.InputFifo);

        ScriptRun run = await world.RunAsync("input", $"say a{character}b");

        Assert.Equal(1, run.Exit);
        Assert.Contains("dangerous characters", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Input_RejectsALineOverAThousandCharacters()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.MakeFifo(world.InputFifo);

        ScriptRun run = await world.RunAsync("input", new string('a', 1001));

        Assert.Equal(1, run.Exit);
        Assert.Contains("too long", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Input_WithNoArgument_IsAMissingArgument()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(7, (await world.RunAsync("input")).Exit);
    }

    [Fact]
    public async Task Input_Fails_WhenThereIsNoConsolePipe()
    {
        using ScriptWorld world = ScriptWorld.Native();

        ScriptRun run = await world.RunAsync("input", "say hi");

        Assert.Equal(1, run.Exit);
        Assert.Contains("No active server", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task EveryWriteToTheConsolePipe_ReturnsWhenNothingReadsIt()
    {
        // A plain append to a pipe blocks until something opens the read end, so a server that died
        // leaving its pipe behind would hang the caller. The pipe is opened read-write instead.
        using ScriptWorld world = ScriptWorld.Native();
        world.MakeFifo(world.InputFifo);

        Assert.Equal(0, (await world.RunAsync("input", "say hi")).Exit);
        Assert.Equal(0, (await world.RunAsync("save")).Exit);
        Assert.Equal(0, (await world.RunAsync("announce", "hello")).Exit);
        Assert.Equal(0, (await world.RunAsync("kick", "Bob")).Exit);
    }

    // --- save ---

    [Fact]
    public async Task Save_WritesTheSaveCommand()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { SaveCommand = "/save-all" });
        await world.StartGameAsync();

        Assert.Equal(0, (await world.RunAsync("save")).Exit);

        await Eventually.Holds(() => world.Recorded("game/input").Contains("/save-all"), "the game read the save command");
    }

    [Fact]
    public async Task Save_WithNoSaveCommandDeclared_SaysSoAndWritesNothing()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { SaveCommand = string.Empty });
        world.MakeFifo(world.InputFifo);

        ScriptRun run = await world.RunAsync("save");

        Assert.Equal(0, run.Exit);
        Assert.Contains("No save command", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Save_Fails_WhenThereIsNoConsolePipe()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(1, (await world.RunAsync("save")).Exit);
    }

    // --- announce ---

    [Fact]
    public async Task Announce_PutsTheMessageInTheBroadcastTemplate()
    {
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();

        Assert.Equal(0, (await world.RunAsync("announce", "Restart in 5 minutes!")).Exit);

        await Eventually.Holds(() => world.Recorded("game/input").Contains("say Restart in 5 minutes!"), "the game read the announcement");
    }

    [Fact]
    public async Task Announce_PutsAnAmpersandAndABackslashInTheMessageThroughLiterally()
    {
        // Bash 5.2 reads an & in an unquoted replacement as the matched text; the script switches that off.
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();

        Assert.Equal(0, (await world.RunAsync("announce", @"fish & chips \1 {message}")).Exit);

        await Eventually.Holds(() => world.Recorded("game/input").Contains(@"say fish & chips \1 {message}"), "the game read the announcement");
    }

    [Fact]
    public async Task Announce_RefusesALineBreak_ASecondCommandNobodyIssued()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.MakeFifo(world.InputFifo);

        Assert.Equal(8, (await world.RunAsync("announce", "a\nb")).Exit);
    }

    [Fact]
    public async Task Announce_RefusesAMessageOverAThousandCharacters()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.MakeFifo(world.InputFifo);

        Assert.Equal(8, (await world.RunAsync("announce", new string('x', 1001))).Exit);
    }

    [Fact]
    public async Task Announce_WithNoBroadcastTemplate_IsRefused()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { BroadcastCommand = string.Empty });
        world.MakeFifo(world.InputFifo);

        ScriptRun run = await world.RunAsync("announce", "hi");

        Assert.Equal(1, run.Exit);
        Assert.Contains("does not support announcements", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Announce_WithATemplateThatLacksThePlaceholder_IsRefused()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { BroadcastCommand = "say" });
        world.MakeFifo(world.InputFifo);

        ScriptRun run = await world.RunAsync("announce", "hi");

        Assert.Equal(1, run.Exit);
        Assert.Contains("{message}", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Announce_WithNoMessage_IsAMissingArgument()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(7, (await world.RunAsync("announce")).Exit);
    }

    // --- moderation ---

    [Theory]
    [InlineData("kick", "Bob", "kick Bob")]
    [InlineData("ban", "10.0.0.7", "ban 10.0.0.7")]
    [InlineData("unban", "76561198000000001", "pardon 76561198000000001")]
    public async Task Moderation_PutsTheTargetInTheTemplatesPlaceholder(string verb, string target, string expected)
    {
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();

        Assert.Equal(0, (await world.RunAsync(verb, target)).Exit);

        await Eventually.Holds(() => world.Recorded("game/input").Contains(expected), "the game read the command");
    }

    [Theory]
    [InlineData("kick")]
    [InlineData("ban")]
    [InlineData("unban")]
    public async Task Moderation_WithNoTemplateDeclared_IsRefused(string verb)
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { KickCommand = string.Empty, BanCommand = string.Empty, UnbanCommand = string.Empty });
        world.MakeFifo(world.InputFifo);

        ScriptRun run = await world.RunAsync(verb, "Bob");

        Assert.Equal(1, run.Exit);
        Assert.Contains($"does not support '{verb}'", run.Err, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Moderation_WithNoTarget_IsAMissingArgument()
    {
        using ScriptWorld world = ScriptWorld.Native();

        Assert.Equal(7, (await world.RunAsync("kick")).Exit);
    }

    [Fact]
    public async Task Moderation_RefusesATargetWithALineBreak()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.MakeFifo(world.InputFifo);

        Assert.Equal(8, (await world.RunAsync("kick", "Bob\nop Eve")).Exit);
    }

    [Fact]
    public async Task Moderation_WithATemplateThatNamesNoPlaceholder_IsRefused()
    {
        using ScriptWorld world = ScriptWorld.Native(c => c with { KickCommand = "kick" });
        world.MakeFifo(world.InputFifo);

        ScriptRun run = await world.RunAsync("kick", "Bob");

        Assert.Equal(1, run.Exit);
        Assert.Contains("placeholder", run.Err, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("Bob[1]")]
    [InlineData("a;b")]
    [InlineData("$x")]
    [InlineData("a & b | c > d")]
    [InlineData("`id` $(id) \\ * ? ~ !")]
    public async Task Moderation_PassesEveryOtherCharacterOfATargetThroughLiterally(string target)
    {
        using ScriptWorld world = ScriptWorld.Native();
        await world.StartGameAsync();

        Assert.Equal(0, (await world.RunAsync("kick", target)).Exit);

        await Eventually.Holds(() => world.Recorded("game/input").Contains($"kick {target}"), "the game read the target as written");
    }

    [Fact]
    public async Task Moderation_RefusesATargetOverAThousandCharacters_LikeAnAnnouncement()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.MakeFifo(world.InputFifo);

        Assert.Equal(0, (await world.RunAsync("kick", new string('x', 1000))).Exit);
        Assert.Equal(8, (await world.RunAsync("kick", new string('x', 1001))).Exit);
    }

    [Fact]
    public async Task Moderation_RefusesACarriageReturnToo()
    {
        using ScriptWorld world = ScriptWorld.Native();
        world.MakeFifo(world.InputFifo);

        Assert.Equal(8, (await world.RunAsync("ban", "a\rb")).Exit);
    }
}
