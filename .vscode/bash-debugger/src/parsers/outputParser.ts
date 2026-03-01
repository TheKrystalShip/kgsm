/**
 * Output parser for bashdb debugger text output.
 *
 * Converts raw bashdb text into structured data. All functions are pure
 * and stateless — they take a string and return parsed results or null.
 */

// ---------------------------------------------------------------------------
// ANSI stripping
// ---------------------------------------------------------------------------

const ANSI_RE = /\x1B(?:\[[0-9;]*[A-Za-z]|\([A-B])/g;

/**
 * Strip ANSI escape codes from bashdb output.
 */
export function stripAnsi(text: string): string {
  return text.replace(ANSI_RE, "");
}

// ---------------------------------------------------------------------------
// Position
// ---------------------------------------------------------------------------

// Matches "(filepath:line):" with optional trailing source text.
// Filepath may contain spaces and most characters except ')'.
const POSITION_RE = /\(([^)]+):(\d+)\):/;

/**
 * Parse a file:line position from bashdb stopped output.
 * Input format: "(/path/to/file.sh:42):" or sometimes "(filename:42):\nline_content"
 * Returns null if not a position line.
 */
export function parsePosition(
  line: string,
): { file: string; line: number } | null {
  const m = POSITION_RE.exec(line);
  if (!m) {
    return null;
  }
  return { file: m[1], line: parseInt(m[2], 10) };
}

// ---------------------------------------------------------------------------
// Prompt
// ---------------------------------------------------------------------------

// "bashdb<1> " or nested subshell "bashdb<<2> "
const PROMPT_RE = /bashdb<+(\d+)>\s/;

/**
 * Parse bashdb prompt to detect command readiness.
 * Input format: "bashdb<N> " where N is command number.
 * Also handles subshell nesting: "bashdb<<N> "
 * Returns the command number or null if not a prompt.
 */
export function parsePrompt(line: string): number | null {
  const m = PROMPT_RE.exec(line);
  if (!m) {
    return null;
  }
  return parseInt(m[1], 10);
}

// ---------------------------------------------------------------------------
// Termination
// ---------------------------------------------------------------------------

const TERMINATED_PATTERNS: { re: RegExp; reason: string }[] = [
  {
    re: /Debugged program terminated normally\./,
    reason: "exited normally",
  },
  {
    re: /Debugged program terminated with code (\d+)\./,
    reason: "", // filled dynamically with exit code
  },
  {
    re: /Program terminated with signal (\S+)/,
    reason: "", // filled dynamically with signal name
  },
  {
    re: /The program finished and will be restarted/,
    reason: "program finished (will restart)",
  },
];

/**
 * Check if output indicates program termination.
 * Returns the termination reason or null.
 */
export function parseTerminated(output: string): string | null {
  for (const { re, reason } of TERMINATED_PATTERNS) {
    const m = re.exec(output);
    if (m) {
      if (m[1]) {
        // Check if it's a numeric exit code or a signal name
        if (/^\d+$/.test(m[1])) {
          return `exited with code ${m[1]}`;
        }
        return `terminated by signal ${m[1]}`;
      }
      return reason;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Signal
// ---------------------------------------------------------------------------

const SIGNAL_RE = /Program received signal (SIG\w+),\s*(.+)\./;

/**
 * Check if output indicates a signal was received.
 * Pattern: "Program received signal SIGxxx, Description."
 * Returns { signal, description } or null.
 */
export function parseSignal(
  line: string,
): { signal: string; description: string } | null {
  const m = SIGNAL_RE.exec(line);
  if (!m) {
    return null;
  }
  return { signal: m[1], description: m[2].trim() };
}

// ---------------------------------------------------------------------------
// Breakpoint set
// ---------------------------------------------------------------------------

const BP_SET_RE = /Breakpoint\s+(\d+)\s+set\s+in\s+file\s+(.+),\s+line\s+(\d+)\./;

/**
 * Parse a breakpoint-set confirmation from bashdb.
 * Pattern: "Breakpoint N set in file FILENAME, line LINE."
 * Returns parsed info or null.
 */
export function parseBreakpointSet(
  line: string,
): { id: number; file: string; line: number } | null {
  const m = BP_SET_RE.exec(line);
  if (!m) {
    return null;
  }
  return { id: parseInt(m[1], 10), file: m[2].trim(), line: parseInt(m[3], 10) };
}

// ---------------------------------------------------------------------------
// Breakpoint hit
// ---------------------------------------------------------------------------

const BP_HIT_RE = /Breakpoint\s+(\d+)\s+hit(?:\s+\((\d+)\s+times?\))?\./;

/**
 * Parse a breakpoint-hit notification.
 * Pattern: "Breakpoint N hit." or "Breakpoint N hit (M times)."
 * Returns { id, hitCount } or null.
 */
export function parseBreakpointHit(
  line: string,
): { id: number; hitCount?: number } | null {
  const m = BP_HIT_RE.exec(line);
  if (!m) {
    return null;
  }
  const result: { id: number; hitCount?: number } = {
    id: parseInt(m[1], 10),
  };
  if (m[2]) {
    result.hitCount = parseInt(m[2], 10);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Sentinel markers
// ---------------------------------------------------------------------------

const SENTINEL_START_RE = /<<CMD_START:([^>]+)>>/;
const SENTINEL_END_RE = /<<CMD_END:([^>]+)>>/;

/**
 * Check if a line is a sentinel marker (either start or end).
 * Returns { type: 'start' | 'end', commandId } or null.
 */
export function parseSentinel(
  line: string,
): { type: "start" | "end"; commandId: string } | null {
  let m = SENTINEL_START_RE.exec(line);
  if (m) {
    return { type: "start", commandId: m[1] };
  }
  m = SENTINEL_END_RE.exec(line);
  if (m) {
    return { type: "end", commandId: m[1] };
  }
  return null;
}

/**
 * Extract content between sentinel markers for a specific command ID.
 * Returns the content between markers, or null if markers not found.
 */
export function extractSentinelContent(
  output: string,
  commandId: string,
): string | null {
  // Escape special regex chars in commandId (UUIDs are safe, but be defensive)
  const escaped = commandId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(
    `<<CMD_START:${escaped}>>[^\\S\\n]*\\n?([\\s\\S]*?)<<CMD_END:${escaped}>>`,
  );
  const m = re.exec(output);
  if (!m) {
    return null;
  }
  return m[1];
}

// ---------------------------------------------------------------------------
// Error messages
// ---------------------------------------------------------------------------

const ERROR_RE = /^\*{2,3}\s*Error:\s*(.+)/m;

/**
 * Parse an error message from bashdb.
 * Common patterns: "** Error: ..." / "*** Error: ..."
 * Returns the error message or null.
 */
export function parseError(line: string): string | null {
  const m = ERROR_RE.exec(line);
  if (!m) {
    return null;
  }
  return m[1].trim();
}
