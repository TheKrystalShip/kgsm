using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;

namespace TheKrystalShip.KGSM.Engine.Blueprints;

/// <summary>
/// The blueprint format's authoring side: renders a native blueprint draft into the YAML the engine reads,
/// and reads such a file back into a draft. The format is the engine's, so a surface that authors a
/// blueprint asks the core instead of building the text itself. Deterministic string work, no YAML library
/// and no reflection; the engine's own parser (<see cref="BlueprintParser"/>) is what validates the result.
/// </summary>
public static partial class BlueprintScaffold
{
    private const int MaxNameLength = 64;

    [GeneratedRegex(@"^[a-z0-9]+(?:[-_][a-z0-9]+)*$")]
    private static partial Regex SafeNamePattern();

    /// <summary>Whether a name is a safe lowercase slug usable as a blueprint file name.</summary>
    public static bool IsSafeName(string? name) =>
        !string.IsNullOrEmpty(name) && name.Length <= MaxNameLength && SafeNamePattern().IsMatch(name);

    /// <summary>
    /// Templates the draft into a native blueprint file, field order matching the engine's authoring
    /// reference. Every string scalar is single-quoted (YAML's one escape: double an embedded quote), so
    /// placeholders, colons and quotes are always safe; nullable fields render the literal <c>null</c>.
    /// </summary>
    public static string Render(NativeBlueprintDraft draft)
    {
        ArgumentNullException.ThrowIfNull(draft);
        return RenderYaml(draft);
    }

    /// <summary>The draft a native blueprint file describes, or the reason it cannot be read as one. Structural checks only.</summary>
    public static (NativeBlueprintDraft? Draft, string? Problem) TryParse(string yaml)
    {
        ArgumentNullException.ThrowIfNull(yaml);
        return ParseYaml(yaml);
    }

    private static string RenderYaml(NativeBlueprintDraft draft)
    {
        NativeBlueprintMetadataDraft m = draft.Metadata;
        NativeBlueprintNativeDraft n = draft.Native;

        var sb = new StringBuilder();
        sb.Append("schema_version: 1\n");
        sb.Append("name: ").Append(draft.Name).Append('\n');
        sb.Append("runtime: native\n");
        sb.Append("metadata:\n");
        sb.Append("  display_name: ").Append(YamlNullableString(m.DisplayName)).Append('\n');
        sb.Append("  description: ").Append(YamlNullableString(m.Description)).Append('\n');
        sb.Append("  rawg_slug: ").Append(YamlNullableString(m.RawgSlug)).Append('\n');
        sb.Append("  max_players: ").Append(YamlNullableInt(m.MaxPlayers)).Append('\n');
        sb.Append("  min_ram_mb: ").Append(YamlNullableInt(m.MinRamMb)).Append('\n');
        sb.Append("  recommended_ram_mb: ").Append(YamlNullableInt(m.RecommendedRamMb)).Append('\n');
        sb.Append("  base_disk_mb: ").Append(YamlNullableInt(m.BaseDiskMb)).Append('\n');

        // Top-level, OPTIONAL — omitted entirely (not even as `null`) when unset, matching how real
        // blueprints without player-presence detection simply lack these lines (e.g. factorio.bp.yaml).
        if (!string.IsNullOrEmpty(draft.PlayerJoinedRegex))
            sb.Append("player_joined_regex: ").Append(YamlQuoted(draft.PlayerJoinedRegex)).Append('\n');
        if (!string.IsNullOrEmpty(draft.PlayerLeftRegex))
            sb.Append("player_left_regex: ").Append(YamlQuoted(draft.PlayerLeftRegex)).Append('\n');

        sb.Append("native:\n");
        sb.Append("  ports: ").Append(YamlQuoted(n.Ports)).Append('\n');
        sb.Append("  steam_app_id: ").Append(n.SteamAppId.ToString(CultureInfo.InvariantCulture)).Append('\n');
        sb.Append("  client_steam_app_id: ").Append(n.ClientSteamAppId.ToString(CultureInfo.InvariantCulture)).Append('\n');
        sb.Append("  steamcmd_arguments: ").Append(YamlQuoted(n.SteamcmdArguments)).Append('\n');
        sb.Append("  is_steam_account_required: ").Append(n.IsSteamAccountRequired ? "true" : "false").Append('\n');
        sb.Append("  platform: ").Append(YamlQuoted(n.Platform)).Append('\n');
        sb.Append("  level_name: ").Append(YamlQuoted(n.LevelName)).Append('\n');
        sb.Append("  executable_subdirectory: ").Append(YamlQuoted(n.ExecutableSubdirectory)).Append('\n');
        sb.Append("  executable_file: ").Append(YamlQuoted(n.ExecutableFile)).Append('\n');
        sb.Append("  executable_arguments: ").Append(YamlQuoted(n.ExecutableArguments)).Append('\n');
        sb.Append("  stop_command: ").Append(YamlQuoted(n.StopCommand)).Append('\n');
        sb.Append("  save_command: ").Append(YamlQuoted(n.SaveCommand)).Append('\n');
        sb.Append("  startup_success_regex: ").Append(YamlQuoted(n.StartupSuccessRegex)).Append('\n');

        return sb.ToString();
    }

    private static string YamlNullableString(string? value) => value is null ? "null" : YamlQuoted(value);

    private static string YamlNullableInt(int? value) =>
        value is null ? "null" : value.Value.ToString(CultureInfo.InvariantCulture);

    private static string YamlQuoted(string value) => "'" + value.Replace("'", "''") + "'";

    // A `key: value` line. The key is a bare identifier anchored at the (trimmed) line start, so the first
    // colon after it always separates key from value — a colon INSIDE a quoted value (e.g. a port range
    // "2456:2458/tcp") never confuses the split.
    [GeneratedRegex(@"^([A-Za-z0-9_]+)\s*:\s?(.*)$")]
    private static partial Regex KeyLine();

    /// <summary>Parses native blueprint YAML back into a <see cref="NativeBlueprintDraft"/>. The flat
    /// two-level schema (top-level keys + a <c>metadata:</c> block + a <c>native:</c> block) is walked line
    /// by line, tracking which block each indented key belongs to; scalars are un-quoted as the inverse of
    /// <see cref="YamlQuoted"/>/<see cref="YamlNullableString"/>. Structural checks only — see
    /// <see cref="TryParse"/>.</summary>
    private static (NativeBlueprintDraft? Draft, string? Problem) ParseYaml(string yaml)
    {
        var top = new Dictionary<string, string?>(StringComparer.Ordinal);
        var meta = new Dictionary<string, string?>(StringComparer.Ordinal);
        var nat = new Dictionary<string, string?>(StringComparer.Ordinal);

        string? section = null; // null = top-level, "metadata", or "native"
        foreach (string raw in yaml.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        {
            if (string.IsNullOrWhiteSpace(raw) || raw.TrimStart().StartsWith('#'))
                continue;

            bool indented = raw[0] is ' ' or '\t';
            Match m = KeyLine().Match(raw.Trim());
            if (!m.Success)
                continue; // not a key line (a stray list item, say) — ignore

            string key = m.Groups[1].Value;
            string value = m.Groups[2].Value.TrimEnd();

            // A non-indented header with no value opens a block; a recognised one switches section, an
            // unrecognised one drops back to top so its (indented) children are ignored.
            if (!indented && value.Length == 0)
            {
                section = key switch { "metadata" => "metadata", "native" => "native", _ => null };
                continue;
            }

            if (!indented)
            {
                section = null; // a fresh top-level key ends any open block
                top[key] = value;
            }
            else
            {
                (section == "metadata" ? meta : section == "native" ? nat : top)[key] = value;
            }
        }

        // Structural gates (mirroring Create): a non-native runtime is out of scope; name + executable_file
        // are the two required identity fields.
        string? runtime = Unquote(top.GetValueOrDefault("runtime"));
        if (!string.IsNullOrEmpty(runtime) && !string.Equals(runtime, "native", StringComparison.OrdinalIgnoreCase))
            return (null, $"only native blueprints are supported here (runtime was '{runtime}')");

        string name = Unquote(top.GetValueOrDefault("name")) ?? string.Empty;
        if (!IsSafeName(name))
            return (null, "name must be a safe lowercase slug ([a-z0-9_-], 1–64 chars)");

        string executableFile = Str(nat, "executable_file");
        if (string.IsNullOrWhiteSpace(executableFile))
            return (null, "native.executable_file is required");

        var draft = new NativeBlueprintDraft
        {
            Name = name,
            PlayerJoinedRegex = Unquote(top.GetValueOrDefault("player_joined_regex")),
            PlayerLeftRegex = Unquote(top.GetValueOrDefault("player_left_regex")),
            Metadata = new NativeBlueprintMetadataDraft
            {
                DisplayName = Unquote(meta.GetValueOrDefault("display_name")),
                Description = Unquote(meta.GetValueOrDefault("description")),
                RawgSlug = Unquote(meta.GetValueOrDefault("rawg_slug")),
                MaxPlayers = Int(meta, "max_players"),
                MinRamMb = Int(meta, "min_ram_mb"),
                RecommendedRamMb = Int(meta, "recommended_ram_mb"),
                BaseDiskMb = Int(meta, "base_disk_mb"),
            },
            Native = new NativeBlueprintNativeDraft
            {
                Ports = Str(nat, "ports"),
                SteamAppId = Int(nat, "steam_app_id") ?? 0,
                ClientSteamAppId = Int(nat, "client_steam_app_id") ?? 0,
                SteamcmdArguments = Str(nat, "steamcmd_arguments"),
                IsSteamAccountRequired = string.Equals(Str(nat, "is_steam_account_required"), "true", StringComparison.OrdinalIgnoreCase),
                Platform = nat.ContainsKey("platform") ? Str(nat, "platform") : "linux",
                LevelName = nat.ContainsKey("level_name") ? Str(nat, "level_name") : "default",
                ExecutableSubdirectory = Str(nat, "executable_subdirectory"),
                ExecutableFile = executableFile,
                ExecutableArguments = Str(nat, "executable_arguments"),
                StopCommand = Str(nat, "stop_command"),
                SaveCommand = Str(nat, "save_command"),
                StartupSuccessRegex = Str(nat, "startup_success_regex"),
            },
        };

        return (draft, null);
    }

    /// <summary>Un-quotes one scalar as the inverse of <see cref="YamlQuoted"/>: single-quoted (doubling
    /// the one escape), double-quoted (common hand-edit), a bare <c>null</c> → <see langword="null"/>, or a
    /// plain scalar returned verbatim. A missing key (<see langword="null"/> input) stays null.</summary>
    private static string? Unquote(string? value)
    {
        if (value is null) return null;
        string v = value.Trim();
        if (v.Length == 0) return string.Empty;
        if (string.Equals(v, "null", StringComparison.Ordinal)) return null;
        if (v.Length >= 2 && v[0] == '\'' && v[^1] == '\'')
            return v[1..^1].Replace("''", "'");
        if (v.Length >= 2 && v[0] == '"' && v[^1] == '"')
            return v[1..^1].Replace("\\\"", "\"").Replace("\\\\", "\\");
        return v;
    }

    /// <summary>A required-string native field: the un-quoted value, or the empty string when the key is
    /// absent or was written as <c>null</c> (these fields render empty, never as a fabricated placeholder).</summary>
    private static string Str(Dictionary<string, string?> d, string key) =>
        d.TryGetValue(key, out string? v) ? Unquote(v) ?? string.Empty : string.Empty;

    /// <summary>A nullable-int field: null when absent or <c>null</c>, else the parsed integer (an
    /// unparseable value is treated as unknown → null, never a fabricated 0).</summary>
    private static int? Int(Dictionary<string, string?> d, string key)
    {
        string? v = d.TryGetValue(key, out string? raw) ? Unquote(raw) : null;
        if (string.IsNullOrEmpty(v)) return null;
        return int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out int n) ? n : null;
    }
}
