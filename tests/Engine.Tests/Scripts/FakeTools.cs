using System.Diagnostics;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>
/// The tools a generated script may use, as the test sees them: a directory of links to the host's own
/// coreutils, findutils, procps, tar, jq and bash, and nothing else. steamcmd, docker, curl, wget and the
/// game are never the host's; a test puts a fake of each it needs in front of this directory.
/// </summary>
internal static class HostTools
{
    private static readonly string[] Names =
    [
        "bash", "jq", "cat", "date", "stat", "du", "od", "timeout", "tail", "head", "sort", "sed", "tr", "wc", "cut",
        "find", "ps", "pgrep", "sleep", "mkdir", "rm", "mv", "cp", "ls", "chmod", "readlink", "tar", "gzip", "xz",
        "unzip", "sha256sum", "mkfifo", "touch", "basename", "dirname", "env", "grep", "awk", "id", "uniq", "ln",
        "tee", "true", "false", "xargs", "mktemp", "uname", "kill", "base64",
    ];

    private static readonly Lazy<string> Directory = new(Build);

    /// <summary>The directory of links.</summary>
    public static string Path => Directory.Value;

    /// <summary>The absolute path of the host's tool of that name, or null when it has none.</summary>
    public static string? Find(string name)
    {
        foreach (string directory in (Environment.GetEnvironmentVariable("PATH") ?? string.Empty).Split(':', StringSplitOptions.RemoveEmptyEntries))
        {
            string candidate = System.IO.Path.Combine(directory, name);
            if (File.Exists(candidate)) return candidate;
        }

        return null;
    }

    private static string Build()
    {
        string directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "hosttools-" + Guid.NewGuid().ToString("N")[..8]);
        System.IO.Directory.CreateDirectory(directory);

        foreach (string name in Names)
        {
            string? real = Find(name);
            if (real is not null) File.CreateSymbolicLink(System.IO.Path.Combine(directory, name), real);
        }

        return directory;
    }
}

/// <summary>The text of each fake tool. Every fake logs its arguments to a file in the world's control directory and does what the test scripted there.</summary>
internal static class FakeScripts
{
    /// <summary>
    /// steamcmd. Prints a build id for <c>+app_info_print</c> (from <c>steam/buildid</c>), and for
    /// <c>+app_update</c> writes <c>game.bin</c> into the <c>+force_install_dir</c> unless <c>steam/empty</c>
    /// exists. <c>steam/exit</c> sets the exit status and <c>steam/no-buildid</c> prints no build.
    /// </summary>
    public const string Steamcmd = """
        #!/usr/bin/env bash
        ctl="$FAKE_DIR/steam"
        mkdir -p "$ctl"
        { printf '%s\037' "$@"; printf '\n'; } >>"$ctl/log"
        dest=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
          +force_install_dir) dest="$2"; shift ;;
          +app_info_print)
            if [[ -f "$ctl/no-buildid" ]]; then
              echo '"depots" { }'
            else
              printf '"%s"\n{\n  "depots"\n  {\n    "branches"\n    {\n      "public"\n      {\n        "buildid"  "%s"\n        "timeupdated"  "1"\n      }\n    }\n  }\n}\n' "$2" "$(cat "$ctl/buildid")"
            fi
            shift ;;
          +app_update)
            if [[ -n "$dest" && ! -f "$ctl/empty" ]]; then
              mkdir -p "$dest/steamapps"
              echo manifest >"$dest/steamapps/appmanifest.acf"
              echo game >"$dest/game.bin"
            fi
            shift ;;
          esac
          shift
        done
        exit "$(cat "$ctl/exit" 2>/dev/null || echo 0)"
        """;

    /// <summary>
    /// curl for hook tests: serves the fixture a test stored for the url, writes it to <c>-o</c> or to stdout,
    /// and exits 22 for a url without one. A watchdog test uses the host's own curl instead.
    /// </summary>
    public const string Curl = """
        #!/usr/bin/env bash
        ctl="$FAKE_DIR/curl"
        mkdir -p "$ctl"
        url="" out=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
          -o) out="$2"; shift ;;
          --max-time) echo "$2" >"$ctl/max-time"; shift ;;
          http*) url="$1" ;;
          esac
          shift
        done
        echo "$url" >>"$ctl/log"
        key="$(printf '%s' "$url" | sha256sum | cut -c1-16)"
        [[ -f "$ctl/$key" ]] || exit 22
        if [[ -n "$out" ]]; then cp "$ctl/$key" "$out"; else cat "$ctl/$key"; fi
        """;

    /// <summary>
    /// docker with compose and buildx. State is files under <c>docker/</c>: <c>ps.json</c> is what
    /// <c>compose ps</c> prints and is rewritten by <c>up</c> and <c>down</c>; <c>images</c>, <c>services</c>,
    /// <c>remote/&lt;image&gt;</c>, <c>local/&lt;image&gt;</c> and <c>inspect</c> answer the matching queries;
    /// <c>fail-&lt;verb&gt;</c> makes that compose verb exit 1 (<c>fail-dockerkill</c> is <c>docker kill</c>).
    /// </summary>
    public const string Docker = """
        #!/usr/bin/env bash
        ctl="$FAKE_DIR/docker"
        mkdir -p "$ctl"
        { printf '%s\037' "$@"; printf '\n'; } >>"$ctl/log"
        fail() { [[ -f "$ctl/fail-$1" ]] && exit 1; }
        name() { printf '%s' "$1" | tr '/:' '__'; }
        case "$1" in
        compose)
          shift
          if [[ "$1" == version ]]; then echo "Docker Compose version v2"; exit 0; fi
          [[ "$1" == "-f" ]] && shift 2
          pwd >"$ctl/cwd"
          verb="$1"; shift
          fail "$verb"
          case "$verb" in
          ps)
            if [[ "$*" == *"-q"* ]]; then cat "$ctl/container-id" 2>/dev/null; else cat "$ctl/ps.json" 2>/dev/null; fi ;;
          config)
            if [[ "$*" == *"--images"* ]]; then cat "$ctl/images" 2>/dev/null; else cat "$ctl/services" 2>/dev/null; fi ;;
          up)
            echo '[{"Service":"s","State":"running"}]' >"$ctl/ps.json"
            echo "cid0123456789abcdef" >"$ctl/container-id" ;;
          down)
            [[ -f "$FAKE_LIFECYCLE" ]] && echo yes >"$ctl/lifecycle-before-down"
            echo '[]' >"$ctl/ps.json"; rm -f "$ctl/container-id" ;;
          logs) cat "$ctl/logs" 2>/dev/null ;;
          esac
          exit 0 ;;
        buildx)
          image="$4"
          [[ -f "$ctl/remote/$(name "$image")" ]] || exit 1
          cat "$ctl/remote/$(name "$image")" ;;
        image)
          image="$3"
          [[ -f "$ctl/local/$(name "$image")" ]] || exit 0
          cat "$ctl/local/$(name "$image")" ;;
        inspect) cat "$ctl/inspect" 2>/dev/null ;;
        stats) cat "$ctl/stats" 2>/dev/null ;;
        kill) fail dockerkill ;;
        esac
        exit 0
        """;

    /// <summary>
    /// The game. Records its arguments (NUL-separated), its pid and every console line it reads under
    /// <c>$FAKE_DIR/game/</c>. It exits on the line in <c>stop-token</c>, ignores TERM when <c>ignore-term</c>
    /// exists and starts a long-lived child when <c>spawn-child</c> exists.
    /// </summary>
    public const string Game = """
        #!/usr/bin/env bash
        ctl="$FAKE_DIR/game"
        mkdir -p "$ctl"
        printf '%s\0' "$@" >"$ctl/args"
        echo "$$" >"$ctl/pid"
        pwd >"$ctl/cwd"
        [[ -f "$ctl/ignore-term" ]] && trap '' TERM
        if [[ -f "$ctl/spawn-child" ]]; then
          sleep 600 &
          echo $! >"$ctl/child.pid"
        fi
        token=""
        [[ -f "$ctl/stop-token" ]] && token="$(cat "$ctl/stop-token")"
        echo started >"$ctl/started"
        while IFS= read -r line; do
          printf '%s\n' "$line" >>"$ctl/input"
          if [[ -n "$token" && "$line" == "$token" ]]; then
            echo "stopped" >"$ctl/exited-by-token"
            exit 0
          fi
        done
        """;

    /// <summary>Writes a fake tool as an executable file.</summary>
    public static void Install(string directory, string name, string text)
    {
        string path = Path.Combine(directory, name);
        File.WriteAllText(path, text.Replace("\r\n", "\n"));
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }
}

internal static class ProcessTable
{
    /// <summary>Whether a pid names a live process that is not a zombie.</summary>
    public static bool Alive(int pid)
    {
        try
        {
            string stat = File.ReadAllText($"/proc/{pid}/stat");
            int close = stat.LastIndexOf(')');
            return close > 0 && stat[close + 2] != 'Z';
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    public static void Kill(int pid)
    {
        try
        {
            using Process process = Process.GetProcessById(pid);
            process.Kill(entireProcessTree: true);
        }
        catch (ArgumentException)
        {
        }
        catch (InvalidOperationException)
        {
        }
    }
}
