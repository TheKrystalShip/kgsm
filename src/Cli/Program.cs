namespace TheKrystalShip.KGSM.Cli;

/// <summary>The binary's entry point.</summary>
internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        using var cancellation = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            cancellation.Cancel();
        };

        return await CliApp.RunAsync(args, CliEnvironment.FromProcess(), Console.Out, Console.Error, cancellation.Token).ConfigureAwait(false);
    }
}
