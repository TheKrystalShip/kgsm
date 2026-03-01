/**
 * Parser for bashdb watchpoint-related output.
 *
 * Converts raw bashdb text into structured watchpoint data. All functions
 * are pure and stateless — they take a string and return parsed results or null.
 *
 * Bashdb watchpoint commands:
 *   watch $var      — string-equality watch (arith: 0)
 *   watche expr     — arithmetic watch   (arith: 1)
 *   delete Nw       — delete watchpoint N (the 'w' suffix distinguishes from breakpoints)
 *   info watchpoints
 */

// ---------------------------------------------------------------------------
// parseWatchpointSet
// ---------------------------------------------------------------------------

// " 0: ($myvar)==hello arith: 0"
// N is printed with at least one space of leading padding; expression is in parens.
const WATCHPOINT_SET_RE =
  /^\s*(\d+):\s+\(([^)]*)\)==(.*?)\s+arith:\s+(0|1)\s*$/;

/**
 * Parse the output from a `watch` or `watche` command.
 *
 * Bashdb prints a single line of the form:
 *   " 0: ($myvar)==hello arith: 0"
 *
 * Returns watchpoint info or null if the output does not match.
 */
export function parseWatchpointSet(output: string): {
  id: number;
  expression: string;
  currentValue: string;
  isArithmetic: boolean;
} | null {
  const m = WATCHPOINT_SET_RE.exec(output.trim());
  if (!m) {
    return null;
  }
  return {
    id: parseInt(m[1], 10),
    expression: m[2],
    currentValue: m[3],
    isArithmetic: m[4] === '1',
  };
}

// ---------------------------------------------------------------------------
// parseWatchpointHit
// ---------------------------------------------------------------------------

// "Watchpoint 0: ($myvar)"
const WATCHPOINT_HIT_HEADER_RE = /^Watchpoint\s+(\d+):\s+\(([^)]*)\)\s*$/;

// "Old value: hello"
const OLD_VALUE_RE = /^Old value:\s*(.*)$/;

// "New value: world"
const NEW_VALUE_RE = /^New value:\s*(.*)$/;

/**
 * Parse a multi-line watchpoint hit notification.
 *
 * Bashdb outputs three lines when a watched value changes:
 *   Watchpoint 0: ($myvar)
 *   Old value: hello
 *   New value: world
 *
 * The input may be the three lines joined with '\n'.
 * Returns parsed info or null if the output does not match.
 */
export function parseWatchpointHit(output: string): {
  id: number;
  expression: string;
  oldValue: string;
  newValue: string;
} | null {
  const lines = output.split('\n').map((l) => l.trim()).filter(Boolean);

  if (lines.length < 3) {
    return null;
  }

  const headerMatch = WATCHPOINT_HIT_HEADER_RE.exec(lines[0]);
  if (!headerMatch) {
    return null;
  }

  const oldMatch = OLD_VALUE_RE.exec(lines[1]);
  const newMatch = NEW_VALUE_RE.exec(lines[2]);
  if (!oldMatch || !newMatch) {
    return null;
  }

  return {
    id: parseInt(headerMatch[1], 10),
    expression: headerMatch[2],
    oldValue: oldMatch[1],
    newValue: newMatch[1],
  };
}

// ---------------------------------------------------------------------------
// parseInfoWatchpoints
// ---------------------------------------------------------------------------

// Header line (skip it): "Num Type       Enb  Expression"
const INFO_WP_HEADER_RE = /^Num\s+Type\s+Enb\s+Expression/;

// Main watchpoint line: "0   watchpoint yes  ($myvar)"
const INFO_WP_LINE_RE =
  /^(\d+)\s+watchpoint\s+(yes|no)\s+\(([^)]*)\)\s*$/;

// Hit count line: "    breakpoint already hit 1 time(s)."
const WP_HIT_COUNT_RE = /^\s+breakpoint already hit\s+(\d+)\s+time/;

/**
 * Parse `info watchpoints` output into an array of structured descriptors.
 *
 * Bashdb format:
 *   Num Type       Enb  Expression
 *   0   watchpoint yes  ($myvar)
 *       breakpoint already hit 1 time(s).
 *
 * Returns an empty array when no watchpoints are present.
 */
export function parseInfoWatchpoints(output: string): Array<{
  id: number;
  enabled: boolean;
  expression: string;
  hitCount: number;
}> {
  const lines = output.split('\n');
  const watchpoints: Array<{
    id: number;
    enabled: boolean;
    expression: string;
    hitCount: number;
  }> = [];
  let current: (typeof watchpoints)[number] | null = null;

  for (const line of lines) {
    if (INFO_WP_HEADER_RE.test(line)) {
      continue;
    }

    const wpMatch = INFO_WP_LINE_RE.exec(line);
    if (wpMatch) {
      // Push the previous entry before starting a new one
      if (current !== null) {
        watchpoints.push(current);
      }
      current = {
        id: parseInt(wpMatch[1], 10),
        enabled: wpMatch[2] === 'yes',
        expression: wpMatch[3],
        hitCount: 0,
      };
      continue;
    }

    if (current !== null) {
      const hitMatch = WP_HIT_COUNT_RE.exec(line);
      if (hitMatch) {
        current.hitCount = parseInt(hitMatch[1], 10);
      }
    }
  }

  // Push the last entry
  if (current !== null) {
    watchpoints.push(current);
  }

  return watchpoints;
}

// ---------------------------------------------------------------------------
// parseNoWatchpoints
// ---------------------------------------------------------------------------

// "No watch expressions have been set."
const NO_WATCHPOINTS_RE = /No watch expressions have been set\./;

/**
 * Check whether the output indicates that no watchpoints are currently set.
 *
 * Bashdb prints "No watch expressions have been set." when `info watchpoints`
 * is run with an empty watchpoint list.
 */
export function parseNoWatchpoints(output: string): boolean {
  return NO_WATCHPOINTS_RE.test(output);
}
