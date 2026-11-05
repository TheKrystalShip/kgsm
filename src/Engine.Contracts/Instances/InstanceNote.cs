using System.Text;

namespace TheKrystalShip.KGSM.Engine.Contracts.Instances;

/// <summary>The rules for an instance's note: what a body may hold and how long it may be.</summary>
public static class InstanceNote
{
    /// <summary>The longest note body, in characters, after sanitizing. A longer body is refused, never truncated.</summary>
    public const int MaxLength = 600;

    /// <summary>
    /// Normalizes a note body for storage: CRLF and a lone CR become LF, control characters other than LF are
    /// dropped, and surrounding whitespace is trimmed. The result is what <see cref="MaxLength"/> is measured against.
    /// </summary>
    public static string Sanitize(string? body)
    {
        if (string.IsNullOrEmpty(body)) return string.Empty;

        var builder = new StringBuilder(body.Length);
        for (int i = 0; i < body.Length; i++)
        {
            char c = body[i];
            if (c == '\r')
            {
                if (i + 1 < body.Length && body[i + 1] == '\n') i++;
                builder.Append('\n');
                continue;
            }

            if (c == '\n' || !char.IsControl(c)) builder.Append(c);
        }

        return builder.ToString().Trim();
    }
}
