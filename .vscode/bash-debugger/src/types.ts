import { DebugProtocol } from '@vscode/debugprotocol';

/**
 * Launch request arguments extending DAP's LaunchRequestArguments.
 * These map to the configurationAttributes in package.json.
 */
export interface LaunchRequestArguments extends DebugProtocol.LaunchRequestArguments {
  program: string;        // Absolute path to bash script
  args?: string[];        // Script arguments
  cwd?: string;           // Working directory
  env?: Record<string, string>;  // Environment variables
  pathBash?: string;      // Override bash path
  pathBashdb?: string;    // Override bashdb path
  stopOnEntry?: boolean;  // Stop at first line (default true)
  terminalKind?: 'integrated' | 'external' | 'debugConsole';
}

/**
 * Parsed position from bashdb output.
 * bashdb reports positions like: (/path/to/file.sh:42):
 */
export interface BashdbPosition {
  file: string;
  line: number;
}

/**
 * Information about a breakpoint managed by bashdb.
 */
export interface BashdbBreakpoint {
  id: number;              // bashdb's internal breakpoint number
  file: string;
  line: number;
  verified: boolean;
  condition?: string;
  hitCount?: number;
  message?: string;         // error message for invalid conditions
  enabled: boolean;
}

/**
 * A parsed variable from bashdb's examine/typeset output.
 */
export interface BashdbVariable {
  name: string;
  value: string;
  type: BashVariableType;
  attributes: BashVariableAttribute[];
  // For arrays/assoc arrays, the children
  children?: BashdbVariable[];
}

/**
 * Bash variable types inferred from declare flags.
 */
export type BashVariableType =
  | 'string'       // declare -- name="value"
  | 'integer'      // declare -i name="42"
  | 'array'        // declare -a name='([0]="a")'
  | 'associative'  // declare -A name='([key]="val")'
  | 'function'     // declare -f name
  | 'nameref';     // declare -n name="other"

/**
 * Bash variable attributes from declare flags.
 */
export type BashVariableAttribute =
  | 'readonly'    // -r
  | 'exported'    // -x
  | 'integer'     // -i
  | 'trace'       // -t
  | 'lowercase'   // -l
  | 'uppercase'   // -u
  | 'nameref';    // -n

/**
 * A parsed stack frame from bashdb's backtrace output.
 */
export interface BashdbStackFrame {
  index: number;           // Frame number
  file: string;
  line: number;
  functionName?: string;   // Function name if inside a function
  args?: string;           // Function arguments
  isCurrent: boolean;      // Whether this is the current frame (marked with ->)
}

/**
 * Wraps a bashdb command response after sentinel-based isolation.
 */
export interface CommandResponse {
  commandId: string;       // UUID matching the sentinel
  output: string;          // Raw text output between sentinels
  lines: string[];         // Output split into lines
}

/**
 * Events emitted by the BashdbRuntime.
 */
export interface RuntimeEvents {
  /** Execution stopped (step, breakpoint, etc.) */
  stopped: (reason: StopReason, position: BashdbPosition) => void;
  /** Debugged program terminated */
  terminated: () => void;
  /** Program output (stdout/stderr) */
  output: (text: string, category: 'stdout' | 'stderr' | 'console') => void;
  /** A breakpoint was hit */
  breakpointHit: (breakpointId: number, position: BashdbPosition) => void;
  /** A watchpoint was hit (value changed) */
  watchpointHit: (watchpointId: number, expression: string, oldValue: string, newValue: string, position: BashdbPosition) => void;
  /** Bashdb is ready to accept commands */
  ready: () => void;
  /** An error occurred in the runtime */
  error: (message: string) => void;
}

/**
 * Reasons execution can stop.
 */
export type StopReason =
  | 'step'
  | 'breakpoint'
  | 'pause'
  | 'entry'
  | 'exception'
  | 'data breakpoint'
  | 'function breakpoint';

/**
 * Scope categories for the variables panel.
 */
export type ScopeCategory = 'locals' | 'globals' | 'environment';

/**
 * Internal state of the bashdb runtime.
 */
export type RuntimeState =
  | 'uninitialized'
  | 'launching'
  | 'running'
  | 'stopped'
  | 'terminated';
