/**
 * Parser for bashdb breakpoint-related output.
 *
 * Converts raw bashdb text into structured breakpoint data. All functions
 * are pure and stateless — they take a string and return parsed results or null.
 */

import { BashdbBreakpoint } from '../types';

// ---------------------------------------------------------------------------
// parseInfoBreakpoints
// ---------------------------------------------------------------------------

// Header line pattern (skip it)
const INFO_BP_HEADER_RE = /^Num\s+Type\s+Disp\s+Enb\s+What/;

// Main breakpoint line: "  1 breakpoint keep y   /path/script.sh:10"
const INFO_BP_LINE_RE =
  /^\s+(\d+)\s+breakpoint\s+\S+\s+(y|n)\s+(\S+):(\d+)\s*$/;

// Condition line following a breakpoint line: "        stop only if (expr)"
const CONDITION_RE = /^\s+stop only if\s+(.+)$/;

// Hit count line: "        breakpoint already hit N times"
const HIT_COUNT_RE = /^\s+breakpoint already hit\s+(\d+)\s+times?\s*$/;

/**
 * Parse the output of bashdb's `info breakpoints` command.
 * Returns an array of breakpoint descriptors.
 */
export function parseInfoBreakpoints(output: string): BashdbBreakpoint[] {
  const lines = output.split('\n');
  const breakpoints: BashdbBreakpoint[] = [];
  let current: BashdbBreakpoint | null = null;

  for (const line of lines) {
    if (INFO_BP_HEADER_RE.test(line)) {
      continue;
    }

    const bpMatch = INFO_BP_LINE_RE.exec(line);
    if (bpMatch) {
      // Push previous breakpoint before starting a new one
      if (current !== null) {
        breakpoints.push(current);
      }
      current = {
        id: parseInt(bpMatch[1], 10),
        enabled: bpMatch[2] === 'y',
        file: bpMatch[3],
        line: parseInt(bpMatch[4], 10),
        verified: true,
      };
      continue;
    }

    if (current !== null) {
      const condMatch = CONDITION_RE.exec(line);
      if (condMatch) {
        current.condition = condMatch[1].trim();
        continue;
      }

      const hitMatch = HIT_COUNT_RE.exec(line);
      if (hitMatch) {
        current.hitCount = parseInt(hitMatch[1], 10);
        continue;
      }
    }
  }

  // Push the last breakpoint
  if (current !== null) {
    breakpoints.push(current);
  }

  return breakpoints;
}

// ---------------------------------------------------------------------------
// parseConditionError
// ---------------------------------------------------------------------------

// "** Error: condition: Breakpoint number 99 out of range."
const CONDITION_ERROR_RE = /^\*\* Error:\s*condition:\s*(.+)$/m;

/**
 * Parse a condition-set error response.
 * Returns the error message or null if no error.
 */
export function parseConditionError(output: string): string | null {
  const m = CONDITION_ERROR_RE.exec(output);
  return m ? m[1].trim() : null;
}

// ---------------------------------------------------------------------------
// parseDeleteConfirmation
// ---------------------------------------------------------------------------

// "Deleted breakpoint 1." or "Deleted action 1."
const DELETE_CONFIRM_RE = /^Deleted (?:breakpoint|action)\s+(\d+)\.\s*$/m;

/**
 * Parse a breakpoint/action deletion confirmation.
 * Returns the deleted ID or null.
 */
export function parseDeleteConfirmation(output: string): number | null {
  const m = DELETE_CONFIRM_RE.exec(output);
  return m ? parseInt(m[1], 10) : null;
}

// ---------------------------------------------------------------------------
// parseDeleteError
// ---------------------------------------------------------------------------

// "** Error: delete: No breakpoint number 99."
const DELETE_ERROR_RE = /^\*\* Error:\s*delete:\s*(.+)$/m;

/**
 * Parse a delete error response.
 * Returns the error message or null.
 */
export function parseDeleteError(output: string): string | null {
  const m = DELETE_ERROR_RE.exec(output);
  return m ? m[1].trim() : null;
}

// ---------------------------------------------------------------------------
// parseActionSet
// ---------------------------------------------------------------------------

// "Action 1 set in file /path/script.sh, line 10."
const ACTION_SET_RE =
  /^Action\s+(\d+)\s+set\s+in\s+file\s+(.+),\s+line\s+(\d+)\.\s*$/m;

/**
 * Parse an action-set confirmation.
 * Returns { id, file, line } or null.
 */
export function parseActionSet(
  output: string,
): { id: number; file: string; line: number } | null {
  const m = ACTION_SET_RE.exec(output);
  if (!m) {
    return null;
  }
  return {
    id: parseInt(m[1], 10),
    file: m[2].trim(),
    line: parseInt(m[3], 10),
  };
}

// ---------------------------------------------------------------------------
// parseFunctionBreakpointError
// ---------------------------------------------------------------------------

// "** Error: break: Function 'funcname' not found."
const FUNC_BP_ERROR_RE = /^\*\* Error:\s*break:\s*(.+)$/m;

/**
 * Parse a function-breakpoint resolution error.
 * Returns the error message or null.
 */
export function parseFunctionBreakpointError(output: string): string | null {
  const m = FUNC_BP_ERROR_RE.exec(output);
  return m ? m[1].trim() : null;
}
