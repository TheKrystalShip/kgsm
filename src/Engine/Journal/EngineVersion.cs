using System.Reflection;

namespace TheKrystalShip.KGSM.Engine.Journal;

/// <summary>The engine's own release number, as the journal's <c>ProducerVersion</c> spells it.</summary>
public static class EngineVersion
{
    /// <summary>The release number of the engine core assembly, without build metadata: <c>4.0.0-dev.1</c>.</summary>
    public static string Current { get; } = Read();

    private static string Read()
    {
        string? informational = typeof(EngineVersion).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;

        if (string.IsNullOrEmpty(informational)) return "0.0.0";

        int plus = informational.IndexOf('+', StringComparison.Ordinal);
        return plus < 0 ? informational : informational[..plus];
    }
}
