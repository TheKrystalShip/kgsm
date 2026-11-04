using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Scripts;

/// <summary>A game's hooks file is not acceptable: it is not valid bash, or it defines a function outside the allow-list.</summary>
public sealed class HookFileException(string path, IReadOnlyList<string> problems)
    : EngineException("hooks", $"'{path}' cannot be inlined: {string.Join("; ", problems)}")
{
    public string Path { get; } = path;

    public IReadOnlyList<string> Problems { get; } = problems;
}

/// <summary>A game's hooks file, found by the blueprint's <c>name:</c>.</summary>
/// <param name="Path">The file.</param>
/// <param name="Text">Its text.</param>
/// <param name="Digest">The SHA-256 of its bytes, lowercase hex.</param>
/// <param name="IsUser">Whether it is the person's file, which replaces the system file whole.</param>
public sealed record HookFile(string Path, string Text, string Digest, bool IsUser);

/// <summary>
/// Finds and checks hook files. One file per game, <c>overrides/&lt;name&gt;/hooks.sh</c>; a file in the
/// person's overrides directory replaces the system file whole, never merging with it.
/// </summary>
public static partial class HookFiles
{
    public const string FileName = "hooks.sh";

    /// <summary>The digest a script records when it was built from no hooks.</summary>
    public const string NoHooksDigest = "none";

    /// <summary>The functions a hooks file may define besides helpers prefixed <c>_hook_</c>.</summary>
    public static IReadOnlyList<string> HookNames { get; } =
        ["kgsm_hook_latest_version", "kgsm_hook_download", "kgsm_hook_deploy", "kgsm_hook_post_deploy"];

    /// <summary>
    /// The path of the hooks file for a blueprint name, or null when the game has none or the name is
    /// not a blueprint name. A user file replaces the system file whole.
    /// </summary>
    public static string? FindPath(EnginePaths paths, string blueprintName)
    {
        ArgumentNullException.ThrowIfNull(paths);
        if (!Blueprints.BlueprintParser.IsValidName(blueprintName)) return null;

        foreach (string directory in new[] { paths.UserOverridesDirectory, paths.SystemOverridesDirectory })
        {
            string file = System.IO.Path.Combine(directory, blueprintName, FileName);
            if (File.Exists(file)) return file;
        }

        return null;
    }

    /// <summary>The hooks file for a blueprint name, read and checked; null when the game has none.</summary>
    /// <exception cref="HookFileException">The file is not acceptable.</exception>
    public static HookFile? Find(EnginePaths paths, string blueprintName) =>
        FindPath(paths, blueprintName) is { } file
            ? Load(file, isUser: file.StartsWith(paths.UserOverridesDirectory, StringComparison.Ordinal))
            : null;

    /// <summary>Reads a hooks file and checks it.</summary>
    /// <exception cref="HookFileException">The file is not acceptable.</exception>
    public static HookFile Load(string path, bool isUser)
    {
        byte[] bytes = File.ReadAllBytes(path);
        string text = Encoding.UTF8.GetString(bytes);
        Validate(path, text);
        return new HookFile(path, text, Convert.ToHexStringLower(SHA256.HashData(bytes)), isUser);
    }

    /// <summary>
    /// Checks a hooks text: <c>bash -n</c> must accept it, and every function it defines must be one of
    /// the four hooks or a helper prefixed <c>_hook_</c>.
    /// </summary>
    /// <exception cref="HookFileException">The text is not acceptable.</exception>
    public static void Validate(string path, string text)
    {
        var problems = new List<string>();

        foreach (string name in DefinedFunctions(text).Distinct(StringComparer.Ordinal))
        {
            if (!IsAllowed(name)) problems.Add($"defines the function '{name}', which is not a hook or a _hook_ helper");
        }

        if (BashSyntax.Check(text) is { } syntax) problems.Add($"bash -n rejects it: {syntax}");
        if (problems.Count > 0) throw new HookFileException(path, problems);
    }

    public static bool IsAllowed(string function) =>
        HookNames.Contains(function, StringComparer.Ordinal) || HelperPattern().IsMatch(function);

    /// <summary>The names of the functions a text defines, in either bash spelling.</summary>
    public static IEnumerable<string> DefinedFunctions(string text)
    {
        foreach (Match match in DefinitionPattern().Matches(text))
            yield return match.Groups["keyword"].Success ? match.Groups["keyword"].Value : match.Groups["paren"].Value;
    }

    [GeneratedRegex(@"^\s*(?:function\s+(?<keyword>[^\s(){};&|<>=]+)|(?<paren>[^\s(){};&|<>=]+)\s*\(\s*\))", RegexOptions.Multiline)]
    private static partial Regex DefinitionPattern();

    [GeneratedRegex("^_hook_[A-Za-z0-9_]+$")]
    private static partial Regex HelperPattern();
}

/// <summary>Syntax checks by the shell that will run the text.</summary>
public static class BashSyntax
{
    /// <summary>Runs <c>bash -n</c> over a script's text; null when it parses, else bash's first complaint.</summary>
    public static string? Check(string script)
    {
        var start = new ProcessStartInfo("bash")
        {
            RedirectStandardInput = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
        };
        start.ArgumentList.Add("-n");

        try
        {
            using Process process = Process.Start(start) ?? throw new EngineException("bash", "bash could not be started");
            Task<string> error = process.StandardError.ReadToEndAsync();
            Task<string> output = process.StandardOutput.ReadToEndAsync();
            process.StandardInput.Write(script);
            process.StandardInput.Close();

            if (!process.WaitForExit(TimeSpan.FromSeconds(30)))
            {
                process.Kill(entireProcessTree: true);
                throw new EngineException("bash", "bash -n did not finish");
            }

            output.GetAwaiter().GetResult();
            string complaint = error.GetAwaiter().GetResult();
            return process.ExitCode == 0
                ? null
                : complaint.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).FirstOrDefault() ?? "no message";
        }
        catch (System.ComponentModel.Win32Exception ex)
        {
            throw new EngineException("bash", "bash is required to check a hooks file and is not installed", ex);
        }
    }
}
