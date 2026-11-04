using System.Security.Cryptography;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>The shape of an instance id and how a fresh one is minted.</summary>
public static class InstanceIds
{
    public const int MaxLength = 64;

    private const string SuffixAlphabet = "0123456789abcdefghijklmnopqrstuvwxyz";

    /// <summary>An id starts with a letter or digit, then letters, digits, dots, underscores and hyphens, up to 64 characters in all.</summary>
    public static bool IsValid(string? id)
    {
        if (string.IsNullOrEmpty(id) || id.Length > MaxLength) return false;
        if (!char.IsAsciiLetterOrDigit(id[0])) return false;

        foreach (char c in id)
        {
            if (!char.IsAsciiLetterOrDigit(c) && c is not ('.' or '_' or '-')) return false;
        }

        return true;
    }

    /// <summary>
    /// Mints <c>&lt;blueprint&gt;-&lt;suffix&gt;</c> with a random suffix of the given length that no taken id uses.
    /// Ids are unique across the host, so the check is against every registered id.
    /// </summary>
    /// <returns>The id, or null when every suffix of that length is taken.</returns>
    public static string? Generate(string blueprint, int suffixLength, Func<string, bool> isTaken)
    {
        ArgumentException.ThrowIfNullOrEmpty(blueprint);
        ArgumentOutOfRangeException.ThrowIfLessThan(suffixLength, 1);
        ArgumentNullException.ThrowIfNull(isTaken);

        // Walk the suffix space from a random start rather than drawing until one is free: a full space
        // ends the search instead of looping forever.
        double space = Math.Pow(SuffixAlphabet.Length, suffixLength);
        if (space > int.MaxValue) space = int.MaxValue;
        int total = (int)space;
        int start = RandomNumberGenerator.GetInt32(total);

        for (int offset = 0; offset < total; offset++)
        {
            int value = (int)(((long)start + offset) % total);
            string candidate = $"{blueprint}-{Suffix(value, suffixLength)}";
            if (IsValid(candidate) && !isTaken(candidate)) return candidate;
        }

        return null;
    }

    private static string Suffix(int value, int length)
    {
        Span<char> chars = stackalloc char[length];
        for (int i = length - 1; i >= 0; i--)
        {
            chars[i] = SuffixAlphabet[value % SuffixAlphabet.Length];
            value /= SuffixAlphabet.Length;
        }

        return new string(chars);
    }
}
