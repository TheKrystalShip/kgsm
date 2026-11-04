namespace TheKrystalShip.KGSM.Engine.Journal;

/// <summary>
/// Who drove an action and through which surface (<c>systems/events/provenance.md</c>). Both are repeated,
/// never vouched for, and never invented: an actor that is not <c>provider:name</c> and an origin outside
/// the closed set are dropped to null, and an absent one stays null.
/// </summary>
public readonly record struct Provenance(string? Actor, string? Origin)
{
    /// <summary>The surfaces an action can come through.</summary>
    public static IReadOnlyList<string> Origins { get; } =
        ["ui", "assistant", "discord", "api", "notification", "system", "reactor"];

    public static Provenance None => default;

    /// <summary>An actor of the form <c>provider:name</c>, both halves present, or null.</summary>
    public static string? NormalizeActor(string? actor)
    {
        if (string.IsNullOrWhiteSpace(actor)) return null;

        int colon = actor.IndexOf(':', StringComparison.Ordinal);
        return colon > 0 && colon < actor.Length - 1 && actor.IndexOf(':', colon + 1) < 0 ? actor : null;
    }

    /// <summary>An origin from the closed set, or null.</summary>
    public static string? NormalizeOrigin(string? origin) =>
        origin is not null && Origins.Contains(origin, StringComparer.Ordinal) ? origin : null;

    /// <summary>The provenance with each half normalised.</summary>
    public Provenance Normalized() => new(NormalizeActor(Actor), NormalizeOrigin(Origin));

    /// <summary>Whether a supplied half was dropped by normalisation.</summary>
    public bool DropsAnything =>
        (Actor is not null && NormalizeActor(Actor) is null) || (Origin is not null && NormalizeOrigin(Origin) is null);
}
