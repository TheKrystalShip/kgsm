/**
 * BashdbRuntime — core process manager for the bashdb debugger.
 *
 * Manages the bash --debugger process lifecycle, serializes commands
 * through a sentinel-based protocol, parses stdout/stderr, and emits
 * typed events consumed by the DAP session layer.
 */

import { EventEmitter } from 'events';
import { ChildProcess, execFileSync, execSync, spawn } from 'child_process';
import { randomUUID } from 'crypto';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

import {
  LaunchRequestArguments,
  BashdbPosition,
  BashdbStackFrame,
  BashdbVariable,
  BashdbBreakpoint,
  CommandResponse,
  StopReason,
  RuntimeState,
} from './types';
import {
  parsePosition,
  parsePrompt,
  parseTerminated,
  parseBreakpointHit,
  parseBreakpointSet,
  parseSentinel,
  parseError,
  stripAnsi,
} from './parsers/outputParser';
import {
  parseExamineOutput,
  parseInfoVariables,
} from './parsers/variableParser';
import {
  parseInfoBreakpoints,
  parseConditionError,
  parseDeleteConfirmation,
  parseFunctionBreakpointError,
  parseActionSet,
} from './parsers/breakpointParser';
import {
  parseWatchpointSet,
  parseWatchpointHit,
  parseInfoWatchpoints,
} from './parsers/watchpointParser';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const COMMAND_TIMEOUT_MS = 10_000;

// Stepping sentinel: print "<<STEP_DONE:uuid>>" — detected after execution pauses
const STEP_DONE_RE = /^<<STEP_DONE:([a-f0-9-]+)>>$/;

// Backtrace line: "->0 in file `/path' at line 10" or "##1 func() called from file `/path' at line 5"
const BT_CURRENT_RE = /^->\s*(\d+)\s+(?:(\S+)\(([^)]*)\)\s+called from\s+)?(?:in\s+)?file\s+[`']([^']+)'\s+at\s+line\s+(\d+)/;
const BT_FRAME_RE  = /^##\s*(\d+)\s+(?:(\S+)\(([^)]*)\)\s+called from\s+)?(?:in\s+)?file\s+[`']([^']+)'\s+at\s+line\s+(\d+)/;

/**
 * Split a single argument string into multiple tokens, respecting
 * single and double quotes.  E.g. `create --name "my server"` →
 * `["create", "--name", "my server"]`.  If the string contains no
 * whitespace it is returned as-is in a single-element array.
 */
function splitArg(arg: string): string[] {
  const tokens: string[] = [];
  let current = '';
  let quote: string | null = null;

  for (let i = 0; i < arg.length; i++) {
    const ch = arg[i];
    if (quote) {
      if (ch === quote) {
        quote = null;
      } else {
        current += ch;
      }
    } else if (ch === '"' || ch === "'") {
      quote = ch;
    } else if (ch === ' ' || ch === '\t') {
      if (current.length > 0) {
        tokens.push(current);
        current = '';
      }
    } else {
      current += ch;
    }
  }
  if (current.length > 0) {
    tokens.push(current);
  }
  return tokens;
}

// ---------------------------------------------------------------------------
// Pending command descriptor
// ---------------------------------------------------------------------------

interface PendingCommand {
  commandId: string;
  resolve: (resp: CommandResponse) => void;
  reject: (err: Error) => void;
  lines: string[];
  collecting: boolean;
  timer: ReturnType<typeof setTimeout>;
}

// ---------------------------------------------------------------------------
// Pending stepping descriptor
// ---------------------------------------------------------------------------

interface PendingStepping {
  steppingId: string;
  resolve: () => void;
  reject: (err: Error) => void;
  timer?: ReturnType<typeof setTimeout>;
}

// ---------------------------------------------------------------------------
// BashdbRuntime
// ---------------------------------------------------------------------------

export class BashdbRuntime extends EventEmitter {
  private _state: RuntimeState = 'uninitialized';
  private _currentPosition: BashdbPosition | null = null;
  private _process: ChildProcess | null = null;

  // FIFO-based I/O — debugger protocol goes through FIFOs so that it
  // survives stdout redirection inside $(...) command substitutions.
  private _fifoDir: string | null = null;
  private _outputFifoPath: string | null = null;
  private _inputFifoPath: string | null = null;
  private _fifoReadFd: number | null = null;
  private _fifoWriteFd: number | null = null;
  // Manual read loop state (replaces createReadStream for deterministic cleanup)
  private _fifoReading = false;
  private _fifoReadStoppedCb: (() => void) | null = null;
  private _fifoReadBuf = Buffer.alloc(8192);

  // Line buffer for debug protocol data (from FIFO)
  private _stdoutBuffer = '';

  // Sentinel-based command queue (serialised — one at a time)
  private _pendingCommand: PendingCommand | null = null;
  private _commandQueue: Array<{
    command: string;
    resolve: (resp: CommandResponse) => void;
    reject: (err: Error) => void;
  }> = [];

  // Stepping waiter (step/next/continue/finish)
  private _pendingStepping: PendingStepping | null = null;

  // Initial launch waiter — resolves when first position line is seen
  private _launchWaiter: { resolve: () => void; reject: (err: Error) => void } | null = null;

  // Maps bashdb breakpoint ID → breakpoint info
  private _breakpoints: Map<number, BashdbBreakpoint> = new Map();
  // Maps file path → set of bashdb breakpoint IDs (for per-file clearing)
  private _fileBreakpoints: Map<string, Set<number>> = new Map();
  // Tracks function breakpoint IDs separately
  private _functionBreakpointIds: Set<number> = new Set();
  // Tracks action (logpoint) IDs
  private _actionIds: Set<number> = new Set();
  // Stores the last breakpoint hit ID for stop reason detection
  private _lastBreakpointHitId: number | null = null;
  // Tracks watchpoint IDs (0-based indices used by bashdb)
  private _watchpointIds: Set<number> = new Set();
  // Stores the last watchpoint hit info for stop reason detection
  private _lastWatchpointHit: { id: number; expression: string; oldValue: string; newValue: string } | null = null;
  // Multi-line buffer for watchpoint hit detection (bashdb outputs 3 lines)
  private _watchpointHitBuffer: string[] = [];
  // Stored launch args for restart support
  private _launchArgs: LaunchRequestArguments | null = null;
  // Flag to suppress TerminatedEvent during restart
  private _isRestarting = false;
  // Monotonically increasing counter — incremented each time execution stops.
  // Used by the session layer to discard stale variable responses.
  private _stopVersion = 0;
  // Cached cleanup promise to avoid double-cleanup races
  private _cleanupPromise: Promise<void> | null = null;

  // -----------------------------------------------------------------------
  // Public accessors
  // -----------------------------------------------------------------------

  get state(): RuntimeState {
    return this._state;
  }

  /** Current stop version — changes each time execution stops at a new location. */
  get stopVersion(): number {
    return this._stopVersion;
  }

  get currentPosition(): BashdbPosition | null {
    return this._currentPosition;
  }

  // -----------------------------------------------------------------------
  // Launch
  // -----------------------------------------------------------------------

  async launch(args: LaunchRequestArguments): Promise<void> {
    this._state = 'launching';
    this._launchArgs = args;
    this._cleanupPromise = null;

    // Quick validation — check that bash is accessible
    const bashPath = args.pathBash || 'bash';
    try {
      execFileSync(bashPath, ['--version'], { timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] });
    } catch {
      throw new Error(`Cannot execute bash at '${bashPath}'. Ensure bash is installed and the path is correct.`);
    }

    // Create named FIFOs for debugger I/O.  Using FIFOs (instead of
    // stdin/stdout) keeps the debug protocol alive inside $(...) command
    // substitutions, where bash redirects stdout to capture output.
    this._fifoDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bashdb-'));
    this._outputFifoPath = path.join(this._fifoDir, 'output');
    this._inputFifoPath = path.join(this._fifoDir, 'input');
    execSync(`mkfifo "${this._outputFifoPath}" "${this._inputFifoPath}"`);

    // Open both FIFOs with O_RDWR. On Linux, O_RDWR on a FIFO succeeds
    // immediately (no blocking) and keeps both a reader and writer on the fd,
    // which prevents EOF when bashdb closes its end between writes.
    this._fifoReadFd = fs.openSync(this._outputFifoPath, fs.constants.O_RDWR);
    this._fifoWriteFd = fs.openSync(this._inputFifoPath, fs.constants.O_RDWR);

    // Start a manual read loop on the output FIFO.  Using a manual loop
    // (instead of createReadStream) gives us deterministic cancellation:
    // we can write a wake-up byte to the O_RDWR fd to unblock the pending
    // read(2), then wait for the callback to confirm the loop has stopped
    // before closing the fd.  This prevents fd-reuse races.
    this._startFifoRead();

    // Use bashdb directly (not bash --debugger) so that script arguments
    // with dashes (e.g. --debug-run) are not consumed by bashdb's option parser.
    // The '--' separates bashdb options from the script and its arguments.
    // --tty routes debugger output to the FIFO (not stdout)
    // --tty_in routes debugger input from the FIFO (not stdin)
    const bashdbPath = args.pathBashdb || 'bashdb';
    // Split individual arg strings by whitespace so that a single prompt
    // input like "create factorio --name test" becomes multiple argv entries.
    // Respects simple single/double quoting (e.g. --name "my server").
    const scriptArgs = (args.args ?? []).flatMap(a => splitArg(a));
    const spawnArgs = [
      '--quiet', '--no-highlight',
      '--tty', this._outputFifoPath,
      '--tty_in', this._inputFifoPath,
      '--', args.program, ...scriptArgs,
    ];

    const env = args.env
      ? { ...process.env, ...args.env }
      : { ...process.env };

    this._process = spawn(bashdbPath, spawnArgs, {
      cwd: args.cwd,
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    // stdout now carries only the script's own output (echo, printf, etc.)
    this._process.stdout!.on('data', (chunk: Buffer) => {
      this.emit('output', chunk.toString(), 'stdout');
    });
    this._process.stderr!.on('data', (chunk: Buffer) => this._onStderr(chunk));
    this._process.on('exit', (code, signal) => this._onExit(code, signal));
    this._process.on('error', (err) => {
      this.emit('error', `Failed to start bash process: ${err.message}`);
      this._state = 'terminated';
      this.emit('terminated');
    });

    // Wait for the initial position line (arrives via the output FIFO)
    await this._waitForLaunch();

    // Configure bashdb defaults
    await this.sendCommand('set listsize 0');
    await this.sendCommand('set width 10000');

    this._state = 'stopped';
    this._stopVersion++;
    // The session layer will call continueAfterConfigDone() after all
    // breakpoints have been set.
  }

  /**
   * Resume execution after configuration is done.
   * Called by the session layer after configurationDoneRequest.
   * Handles the stopOnEntry logic that was previously in launch().
   */
  continueAfterConfigDone(stopOnEntry: boolean): void {
    if (stopOnEntry) {
      this.emit('stopped', 'entry' as StopReason, this._currentPosition!);
    } else {
      this.continue().catch(() => {
        // Errors handled via terminated/error events
      });
    }
  }

  // -----------------------------------------------------------------------
  // Stepping commands (no sentinels — wait for next position/termination)
  // -----------------------------------------------------------------------

  async step(): Promise<void> {
    return this._sendSteppingCommand('step');
  }

  async next(): Promise<void> {
    return this._sendSteppingCommand('next');
  }

  async continue(): Promise<void> {
    return this._sendSteppingCommand('continue');
  }

  async stepOut(): Promise<void> {
    return this._sendSteppingCommand('finish');
  }

  // -----------------------------------------------------------------------
  // Pause — send SIGINT to the bash process
  // -----------------------------------------------------------------------

  async pause(): Promise<void> {
    if (!this._process || !this._process.pid) {
      throw new Error('No running process to pause');
    }

    // Send SIGINT and a stepping sentinel. After SIGINT interrupts execution,
    // bashdb will read the print command and emit the sentinel.
    return new Promise<void>((resolve, reject) => {
      const steppingId = randomUUID();
      const timer = setTimeout(() => {
        this._pendingStepping = null;
        reject(new Error('Pause timed out'));
      }, 10000);

      this._pendingStepping = { steppingId, resolve, reject, timer };
      this._process!.kill('SIGINT');
      this._writeToStdin(`print "<<STEP_DONE:${steppingId}>>"\n`);
    });
  }

  // -----------------------------------------------------------------------
  // Terminate
  // -----------------------------------------------------------------------

  async terminate(): Promise<void> {
    if (!this._process) {
      // Process already gone — but cleanup may still be in progress
      if (this._cleanupPromise) {
        await this._cleanupPromise;
      }
      return;
    }

    // Try graceful quit first (via the input FIFO)
    try {
      this._writeToStdin('quit\n');
    } catch {
      // FIFO may already be closed
    }

    const proc = this._process;

    // Give bashdb a moment, then force kill
    await new Promise<void>((resolve) => {
      const killTimeout = setTimeout(() => {
        try {
          proc.kill('SIGKILL');
        } catch {
          // already dead
        }
        resolve();
      }, 2000);

      proc.once('exit', () => {
        clearTimeout(killTimeout);
        resolve();
      });

      try {
        proc.kill('SIGTERM');
      } catch {
        clearTimeout(killTimeout);
        resolve();
      }
    });

    await this._runCleanup();
  }

  // -----------------------------------------------------------------------
  // Inspection commands (use sentinels)
  // -----------------------------------------------------------------------

  async getStackTrace(): Promise<BashdbStackFrame[]> {
    const resp = await this.sendCommand('T');
    return this._parseBacktrace(resp.lines);
  }

  /**
   * Get all variable names for a scope.
   * Uses bashdb `info variables` command.
   * @param scope - 'locals' | 'globals' | 'environment'
   */
  async getVariableNames(scope: string): Promise<string[]> {
    let command: string;
    switch (scope) {
      case 'environment':
        command = 'info variables -x';  // exported variables only
        break;
      case 'locals':
        command = 'info variables';     // variables in current scope
        break;
      case 'globals':
      default:
        command = 'info variables';     // all variables
        break;
    }
    const resp = await this.sendCommand(command);
    return parseInfoVariables(resp.output);
  }

  /**
   * Get detailed info for a specific variable.
   * Uses bashdb `examine` command which invokes `typeset -p`.
   */
  async getVariable(name: string): Promise<BashdbVariable | null> {
    const resp = await this.sendCommand(`x ${name}`);
    const vars = parseExamineOutput(resp.output);
    return vars.length > 0 ? vars[0] : null;
  }

  /**
   * Get detailed info for multiple variables at once.
   * Uses a single `eval typeset -p name1 name2 ...` command for efficiency.
   */
  async getVariables(names: string[]): Promise<BashdbVariable[]> {
    if (names.length === 0) return [];

    // Batch all names into a single typeset -p call
    const nameList = names.join(' ');
    const resp = await this.sendCommand(`eval typeset -p ${nameList}`);
    return parseExamineOutput(resp.output);
  }

  /**
   * Evaluate an expression in the current context.
   * @param expression - bash expression to evaluate
   * @param context - 'hover' | 'watch' | 'repl'
   */
  async evaluate(expression: string, context: string): Promise<{ result: string; type?: string; variablesReference?: BashdbVariable }> {
    if (context === 'repl') {
      // For REPL (debug console), use eval to execute arbitrary bash
      const resp = await this.sendCommand(`eval ${expression}`);
      return { result: resp.output.trim() || '(no output)' };
    }

    // For hover and watch, try examine first (works for variables)
    const resp = await this.sendCommand(`x ${expression}`);
    const vars = parseExamineOutput(resp.output);
    if (vars.length > 0) {
      const v = vars[0];
      return {
        result: v.value,
        type: v.type,
        variablesReference: v.children ? v : undefined,
      };
    }

    // If examine fails, try eval (works for expressions like $((1+2)))
    const evalResp = await this.sendCommand(`eval echo ${expression}`);
    const evalOutput = evalResp.output.trim();
    if (evalOutput) {
      return { result: evalOutput };
    }

    return { result: '' };
  }

  /**
   * Set a variable's value.
   * Uses bashdb eval to perform assignment, then re-examines for verification.
   */
  async setVariable(name: string, value: string): Promise<BashdbVariable> {
    // Perform the assignment
    await this.sendCommand(`eval ${name}=${value}`);

    // Re-examine to get the actual new value
    const updated = await this.getVariable(name);
    if (!updated) {
      throw new Error(`Failed to verify variable ${name} after setting`);
    }
    return updated;
  }

  /**
   * Evaluate and assign an expression.
   * Used for setExpression DAP request.
   */
  async setExpression(expression: string, value: string): Promise<string> {
    await this.sendCommand(`eval ${expression}=${value}`);
    // Try to read back the result
    const resp = await this.sendCommand(`eval echo ${expression}`);
    return resp.output.trim();
  }

  /**
   * Switch to a specific stack frame.
   * Uses bashdb `frame N` command.
   */
  async selectFrame(frameIndex: number): Promise<void> {
    await this.sendCommand(`frame ${frameIndex}`);
  }

  /**
   * Get all loaded/sourced script files.
   * Uses bashdb `info files` command.
   * Output format: "  file: canonic_file, N lines"
   */
  async getLoadedSources(): Promise<Array<{ file: string; lines: number }>> {
    const resp = await this.sendCommand('info files');
    const sources: Array<{ file: string; lines: number }> = [];
    // Parse each line: "  file: canonic_file, N lines"
    const lineRe = /^\s+(.+?):\s+(.+?),\s+(\d+)\s+lines?\s*$/;
    for (const line of resp.lines) {
      const m = lineRe.exec(line);
      if (m) {
        sources.push({ file: m[2].trim(), lines: parseInt(m[3], 10) });
      }
    }
    return sources;
  }

  /**
   * Restart the debugging session.
   * bashdb's restart command uses exec which replaces the process.
   * Instead, we terminate and re-launch with the stored args.
   */
  async restart(): Promise<void> {
    if (!this._launchArgs) {
      throw new Error('Cannot restart: no launch arguments stored');
    }
    const args = this._launchArgs;
    this._isRestarting = true;
    try {
      await this.terminate();
      await this.launch(args);
    } finally {
      this._isRestarting = false;
    }
  }

  /**
   * Get command completions from bashdb.
   * Uses the `complete` command. Returns one match per line.
   */
  async getCompletions(text: string): Promise<string[]> {
    const resp = await this.sendCommand(`complete ${text}`);
    return resp.lines.filter(line => line.trim().length > 0);
  }

  /**
   * Configure how bashdb handles a signal.
   * Uses the `handle` command.
   * @param signal - Signal name (e.g., 'ERR', 'INT', 'TERM')
   * @param stop - Whether to stop when the signal fires
   * @param print - Whether to print when the signal fires
   */
  async handleSignal(signal: string, stop: boolean, print: boolean): Promise<void> {
    const stopFlag = stop ? 'stop' : 'nostop';
    const printFlag = print ? 'print' : 'noprint';
    await this.sendCommand(`handle ${signal} ${stopFlag} ${printFlag}`);
  }

  /**
   * Skip the next N statements without executing them.
   * Uses bashdb's `skip` command.
   * Note: skipped statements return $?=0.
   */
  async skip(count: number = 1): Promise<void> {
    return this._sendSteppingCommand(`skip ${count}`);
  }

  // -----------------------------------------------------------------------
  // Breakpoint management
  // -----------------------------------------------------------------------

  /**
   * Set a source breakpoint at file:line.
   * Returns the bashdb breakpoint info including the assigned ID.
   */
  async setBreakpoint(file: string, line: number, condition?: string, hitCondition?: string): Promise<BashdbBreakpoint> {
    const resp = await this.sendCommand(`break ${file}:${line}`);
    const parsed = parseBreakpointSet(resp.output);
    if (!parsed) {
      throw new Error(`Failed to set breakpoint at ${file}:${line}: ${resp.output}`);
    }

    const bp: BashdbBreakpoint = {
      id: parsed.id,
      file: parsed.file,
      line: parsed.line,
      verified: true,
      enabled: true,
    };

    // Build the final condition expression combining user condition and hit count
    let finalCondition: string | null = null;

    if (condition) {
      finalCondition = condition;
      bp.condition = condition;
    }

    if (hitCondition) {
      const hitExpr = this._translateHitCondition(parsed.id, hitCondition);
      if (hitExpr) {
        // Combine with user condition if both are present
        finalCondition = finalCondition ? `(${finalCondition}) && ${hitExpr}` : hitExpr;
      }
    }

    if (finalCondition) {
      const condResp = await this.sendCommand(`condition ${parsed.id} ${finalCondition}`);
      const condErr = parseConditionError(condResp.output);
      if (condErr) {
        bp.verified = false;
        bp.message = `Condition error: ${condErr}`;
      }
    }

    // Track the breakpoint
    this._breakpoints.set(bp.id, bp);
    if (!this._fileBreakpoints.has(file)) {
      this._fileBreakpoints.set(file, new Set());
    }
    this._fileBreakpoints.get(file)!.add(bp.id);

    return bp;
  }

  /**
   * Clear all breakpoints in a specific file.
   * Returns the number of breakpoints cleared.
   */
  async clearFileBreakpoints(file: string): Promise<number> {
    const ids = this._fileBreakpoints.get(file);
    if (!ids || ids.size === 0) {
      return 0;
    }

    let cleared = 0;
    for (const id of ids) {
      // Skip if it's a function breakpoint (managed separately)
      if (this._functionBreakpointIds.has(id)) {
        continue;
      }
      try {
        await this.sendCommand(`delete ${id}`);
        this._breakpoints.delete(id);
        cleared++;
      } catch {
        // Breakpoint may already be gone
      }
    }

    // Also clear any actions (logpoints) associated with this file
    // We don't have file-level action tracking so skip for now

    this._fileBreakpoints.delete(file);
    return cleared;
  }

  /**
   * Delete a specific breakpoint by ID.
   */
  async deleteBreakpoint(id: number): Promise<void> {
    await this.sendCommand(`delete ${id}`);
    this._breakpoints.delete(id);
    this._functionBreakpointIds.delete(id);

    // Remove from file tracking
    for (const [file, ids] of this._fileBreakpoints) {
      if (ids.has(id)) {
        ids.delete(id);
        if (ids.size === 0) {
          this._fileBreakpoints.delete(file);
        }
        break;
      }
    }
  }

  /**
   * Set a function breakpoint.
   * Returns the breakpoint info (bashdb resolves function name to file:line).
   */
  async setFunctionBreakpoint(functionName: string, condition?: string): Promise<BashdbBreakpoint> {
    const resp = await this.sendCommand(`break ${functionName}`);

    // Check for error
    const funcErr = parseFunctionBreakpointError(resp.output);
    if (funcErr) {
      throw new Error(funcErr);
    }

    const parsed = parseBreakpointSet(resp.output);
    if (!parsed) {
      throw new Error(`Failed to set function breakpoint for '${functionName}': ${resp.output}`);
    }

    const bp: BashdbBreakpoint = {
      id: parsed.id,
      file: parsed.file,
      line: parsed.line,
      verified: true,
      enabled: true,
    };

    if (condition) {
      await this.sendCommand(`condition ${parsed.id} ${condition}`);
      bp.condition = condition;
    }

    this._breakpoints.set(bp.id, bp);
    this._functionBreakpointIds.add(bp.id);

    if (!this._fileBreakpoints.has(bp.file)) {
      this._fileBreakpoints.set(bp.file, new Set());
    }
    this._fileBreakpoints.get(bp.file)!.add(bp.id);

    return bp;
  }

  /**
   * Clear all function breakpoints.
   */
  async clearFunctionBreakpoints(): Promise<void> {
    for (const id of this._functionBreakpointIds) {
      try {
        await this.sendCommand(`delete ${id}`);
        this._breakpoints.delete(id);
        // Remove from file tracking
        for (const [, ids] of this._fileBreakpoints) {
          ids.delete(id);
        }
      } catch {
        // Already gone
      }
    }
    this._functionBreakpointIds.clear();
  }

  /**
   * Set a logpoint (action) at file:line.
   * The expression is evaluated and printed each time execution reaches the line.
   * Execution does NOT stop.
   */
  async setAction(file: string, line: number, expression: string): Promise<{ id: number }> {
    const resp = await this.sendCommand(`action ${file}:${line} ${expression}`);
    const parsed = parseActionSet(resp.output);
    if (!parsed) {
      throw new Error(`Failed to set action at ${file}:${line}: ${resp.output}`);
    }
    this._actionIds.add(parsed.id);
    return { id: parsed.id };
  }

  /**
   * Clear all actions (logpoints).
   */
  async clearActions(): Promise<void> {
    for (const id of this._actionIds) {
      try {
        await this.sendCommand(`delete ${id}`);
      } catch {
        // Already gone
      }
    }
    this._actionIds.clear();
  }

  // -----------------------------------------------------------------------
  // Watchpoint (data breakpoint) management
  // -----------------------------------------------------------------------

  /**
   * Check if a variable can be watched.
   * Verifies the variable exists by examining it.
   */
  async canWatch(variable: string): Promise<boolean> {
    try {
      const resp = await this.sendCommand(`examine ${variable}`);
      const error = parseError(resp.output);
      return !error;
    } catch {
      return false;
    }
  }

  /**
   * Set a watchpoint on a variable. Uses `watch $variable`.
   * Returns the watchpoint ID and current value.
   */
  async setWatchpoint(variable: string): Promise<{ id: number; expression: string; currentValue: string }> {
    const resp = await this.sendCommand(`watch $${variable}`);
    const parsed = parseWatchpointSet(resp.output);
    if (!parsed) {
      throw new Error(`Failed to set watchpoint on ${variable}: ${resp.output}`);
    }
    this._watchpointIds.add(parsed.id);
    return { id: parsed.id, expression: parsed.expression, currentValue: parsed.currentValue };
  }

  /**
   * Set a watchpoint on an arbitrary expression. Uses `watche expression`.
   * Returns the watchpoint ID and current value.
   */
  async setWatchExpression(expression: string): Promise<{ id: number; expression: string; currentValue: string }> {
    // Reject newlines/control chars to prevent command injection into bashdb's stdin
    if (/[\r\n]/.test(expression)) {
      throw new Error(`Watch expression cannot contain newlines: '${expression}'`);
    }
    const resp = await this.sendCommand(`watche ${expression}`);
    const parsed = parseWatchpointSet(resp.output);
    if (!parsed) {
      throw new Error(`Failed to set watch expression '${expression}': ${resp.output}`);
    }
    this._watchpointIds.add(parsed.id);
    return { id: parsed.id, expression: parsed.expression, currentValue: parsed.currentValue };
  }

  /**
   * Delete a specific watchpoint by ID.
   * Bashdb uses the `Nw` suffix to distinguish watchpoints from breakpoints.
   */
  async deleteWatchpoint(id: number): Promise<void> {
    await this.sendCommand(`delete ${id}w`);
    this._watchpointIds.delete(id);
  }

  /**
   * Clear all watchpoints.
   */
  async clearWatchpoints(): Promise<void> {
    // Delete each tracked watchpoint individually
    for (const id of Array.from(this._watchpointIds)) {
      try {
        await this.sendCommand(`delete ${id}w`);
      } catch {
        // Watchpoint may already be gone
      }
    }
    this._watchpointIds.clear();
  }

  // -----------------------------------------------------------------------
  // sendCommand — sentinel-based, serialised
  // -----------------------------------------------------------------------

  sendCommand(command: string): Promise<CommandResponse> {
    return new Promise<CommandResponse>((resolve, reject) => {
      this._commandQueue.push({ command, resolve, reject });
      this._drainQueue();
    });
  }

  // -----------------------------------------------------------------------
  // Private — command queue
  // -----------------------------------------------------------------------

  private _drainQueue(): void {
    if (this._pendingCommand || this._commandQueue.length === 0) {
      return;
    }

    const { command, resolve, reject } = this._commandQueue.shift()!;
    const commandId = randomUUID();

    const timer = setTimeout(() => {
      if (this._pendingCommand?.commandId === commandId) {
        this._pendingCommand = null;
        reject(new Error(`Command timed out after ${COMMAND_TIMEOUT_MS}ms: ${command}`));
        this._drainQueue();
      }
    }, COMMAND_TIMEOUT_MS);

    this._pendingCommand = {
      commandId,
      resolve,
      reject,
      lines: [],
      collecting: false,
      timer,
    };

    const payload =
      `print "<<CMD_START:${commandId}>>"\n` +
      `${command}\n` +
      `print "<<CMD_END:${commandId}>>"\n`;

    this._writeToStdin(payload);
  }

  // -----------------------------------------------------------------------
  // Private — stepping command
  // -----------------------------------------------------------------------

  private _sendSteppingCommand(command: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      this._state = 'running';
      const steppingId = randomUUID();

      // Flush queued inspection commands — they're from a stale stop and would
      // delay the stepping command. The pending command (if any) must complete
      // naturally since bashdb is already processing it.
      this._flushQueuedCommands();

      // `continue` has no timeout — the script may run for any duration
      // before hitting the next breakpoint.  Other stepping commands
      // (step, next, finish) complete within one line so a timeout is useful.
      let timer: ReturnType<typeof setTimeout> | undefined;
      if (command !== 'continue') {
        timer = setTimeout(() => {
          if (this._pendingStepping) {
            this._pendingStepping = null;
            reject(new Error(`Stepping command timed out: ${command}`));
          }
        }, COMMAND_TIMEOUT_MS);
      }

      this._pendingStepping = { steppingId, resolve, reject, timer };

      // Send the stepping command followed by a sentinel that bashdb will
      // only process after execution pauses at the next stop point.
      this._writeToStdin(`${command}\nprint "<<STEP_DONE:${steppingId}>>"\n`);
    });
  }

  /**
   * Reject and discard all queued (not yet sent) commands. This is called when
   * a stepping command is about to be sent — any queued inspection commands are
   * from a stale stop and would delay the step.
   */
  private _flushQueuedCommands(): void {
    const queued = this._commandQueue.splice(0);
    for (const item of queued) {
      item.reject(new Error('Command cancelled: execution resumed'));
    }
  }

  // -----------------------------------------------------------------------
  // Private — manual FIFO read loop
  // -----------------------------------------------------------------------

  /**
   * Start the manual read loop on the output FIFO.
   */
  private _startFifoRead(): void {
    this._fifoReading = true;
    this._readFifoChunk();
  }

  /**
   * Issue a single fs.read and schedule the next one on completion.
   * Checks `_fifoReading` both before and after each read to support
   * deterministic cancellation via `_stopFifoRead()`.
   */
  private _readFifoChunk(): void {
    if (!this._fifoReading || this._fifoReadFd === null) {
      this._notifyFifoReadStopped();
      return;
    }

    const fd = this._fifoReadFd;
    fs.read(fd, this._fifoReadBuf, 0, this._fifoReadBuf.length, null,
      (err, bytesRead) => {
        if (!this._fifoReading || this._fifoReadFd === null) {
          this._notifyFifoReadStopped();
          return;
        }
        if (err) {
          if (err.code === 'EAGAIN' || err.code === 'EINTR') {
            setImmediate(() => this._readFifoChunk());
            return;
          }
          this._notifyFifoReadStopped();
          return;
        }
        if (bytesRead > 0) {
          this._onDebugData(Buffer.from(this._fifoReadBuf.subarray(0, bytesRead)));
        }
        setImmediate(() => this._readFifoChunk());
      },
    );
  }

  /**
   * Stop the FIFO read loop and wait for any in-flight read to complete.
   * Writes a wake-up byte to the O_RDWR fd to unblock a pending `read(2)`.
   */
  private _stopFifoRead(): Promise<void> {
    if (!this._fifoReading) {
      return Promise.resolve();
    }
    this._fifoReading = false;

    // Unblock the pending read(2) by writing to the FIFO (O_RDWR fd)
    if (this._fifoReadFd !== null) {
      try { fs.writeSync(this._fifoReadFd, '\n'); } catch { /* already closed */ }
    }

    return new Promise<void>((resolve) => {
      this._fifoReadStoppedCb = resolve;
    });
  }

  private _notifyFifoReadStopped(): void {
    if (this._fifoReadStoppedCb) {
      const cb = this._fifoReadStoppedCb;
      this._fifoReadStoppedCb = null;
      cb();
    }
  }

  // -----------------------------------------------------------------------
  // Private — debug protocol processing (from output FIFO)
  // -----------------------------------------------------------------------

  private _onDebugData(chunk: Buffer): void {
    this._stdoutBuffer += chunk.toString();

    let newlineIdx: number;
    while ((newlineIdx = this._stdoutBuffer.indexOf('\n')) !== -1) {
      const rawLine = this._stdoutBuffer.slice(0, newlineIdx);
      this._stdoutBuffer = this._stdoutBuffer.slice(newlineIdx + 1);
      this._processLine(stripAnsi(rawLine));
    }

    // Check for prompt at end of buffer (prompts may not end with \n)
    const stripped = stripAnsi(this._stdoutBuffer);
    if (parsePrompt(stripped) !== null) {
      this._stdoutBuffer = '';
      this._onPromptDetected();
    }
  }

  private _processLine(line: string): void {
    // 1. Sentinel markers — route to pending command
    const sentinel = parseSentinel(line);
    if (sentinel && this._pendingCommand && sentinel.commandId === this._pendingCommand.commandId) {
      if (sentinel.type === 'start') {
        this._pendingCommand.collecting = true;
        return;
      }
      if (sentinel.type === 'end') {
        this._completePendingCommand();
        return;
      }
    }

    // Collect lines between sentinels
    if (this._pendingCommand?.collecting) {
      this._pendingCommand.lines.push(line);
      return;
    }

    // 1b. Stepping sentinel — stepping command completed
    const stepMatch = STEP_DONE_RE.exec(line);
    if (stepMatch) {
      if (this._pendingStepping && stepMatch[1] === this._pendingStepping.steppingId) {
        this._onSteppingComplete();
        return;
      }
      // Fallback: STEP_DONE arrived but _pendingStepping was already cleared
      // (e.g. a timeout fired before the script reached the breakpoint).
      // If we have a current position and we're still nominally running,
      // emit a stopped event so the UI updates.
      if (!this._pendingStepping && this._state === 'running' && this._currentPosition) {
        this._state = 'stopped';
        this._stopVersion++;
        let reason: StopReason = 'step';
        if (this._lastBreakpointHitId !== null) {
          reason = 'breakpoint';
          this._lastBreakpointHitId = null;
        }
        this.emit('stopped', reason, this._currentPosition);
        return;
      }
      return;
    }

    // 2. Position markers — execution stopped at a new location
    const pos = parsePosition(line);
    if (pos) {
      this._currentPosition = { file: pos.file, line: pos.line };

      // Resolve launch waiter on first position
      if (this._launchWaiter) {
        const waiter = this._launchWaiter;
        this._launchWaiter = null;
        waiter.resolve();
      }
      return;
    }

    // 3. Breakpoint hit
    const bpHit = parseBreakpointHit(line);
    if (bpHit) {
      this._lastBreakpointHitId = bpHit.id;
      return;
    }

    // 2b. Watchpoint hit detection (multi-line: header + old value + new value)
    if (this._watchpointHitBuffer.length > 0) {
      this._watchpointHitBuffer.push(line);
      if (this._watchpointHitBuffer.length >= 3) {
        const combined = this._watchpointHitBuffer.join('\n');
        const wpHit = parseWatchpointHit(combined);
        this._watchpointHitBuffer = [];
        if (wpHit) {
          this._lastWatchpointHit = wpHit;
          return;
        }
        // Not a valid watchpoint hit — emit buffered lines as output
        for (const buffered of combined.split('\n')) {
          this.emit('output', buffered, 'stdout');
        }
      }
      return;
    }

    // Check if this line starts a watchpoint hit
    if (/^Watchpoint\s+\d+:/.test(line)) {
      this._watchpointHitBuffer = [line];
      return;
    }

    // 4. Termination
    const terminated = parseTerminated(line);
    if (terminated) {
      this._state = 'terminated';

      // Resolve any pending stepping command
      if (this._pendingStepping) {
        clearTimeout(this._pendingStepping.timer);
        this._pendingStepping.resolve();
        this._pendingStepping = null;
      }

      if (!this._isRestarting) {
        this.emit('terminated');
      }
      return;
    }

    // 5. Error messages
    const error = parseError(line);
    if (error) {
      this.emit('error', error);
      return;
    }

    // 6. Prompt (handled in _onDebugData for partial-line prompts, but also here)
    if (parsePrompt(line) !== null) {
      this._onPromptDetected();
      return;
    }

    // 7. Everything else — unrecognized debug protocol output
    if (line.length > 0) {
      this.emit('output', line, 'console');
    }
  }

  private _completePendingCommand(): void {
    const pending = this._pendingCommand!;
    clearTimeout(pending.timer);

    // Filter out bashdb's "$? is N" status lines from eval command output
    const filteredLines = pending.lines.filter(l => !/^\$\? is \d+$/.test(l));

    const output = filteredLines.join('\n');
    const resp: CommandResponse = {
      commandId: pending.commandId,
      output,
      lines: filteredLines,
    };

    this._pendingCommand = null;
    pending.resolve(resp);
    this._drainQueue();
  }

  private _onPromptDetected(): void {
    // Flush any partial watchpoint hit buffer — stale lines from interrupted output
    if (this._watchpointHitBuffer.length > 0) {
      for (const buffered of this._watchpointHitBuffer) {
        this.emit('output', buffered, 'stdout');
      }
      this._watchpointHitBuffer = [];
    }

    // Prompts may appear with TTY setups — handle as secondary sync.
    // Primary sync uses sentinel markers (CMD_START/CMD_END, STEP_DONE).
  }

  /**
   * Called when a stepping sentinel (<<STEP_DONE:uuid>>) is detected,
   * indicating that execution has paused after a step/next/continue/finish.
   */
  private _onSteppingComplete(): void {
    // Flush any partial watchpoint hit buffer
    if (this._watchpointHitBuffer.length > 0) {
      for (const buffered of this._watchpointHitBuffer) {
        this.emit('output', buffered, 'stdout');
      }
      this._watchpointHitBuffer = [];
    }

    if (this._pendingStepping && this._currentPosition) {
      const stepping = this._pendingStepping;
      this._pendingStepping = null;
      clearTimeout(stepping.timer!);

      this._state = 'stopped';
      this._stopVersion++;

      let reason: StopReason = 'step';
      if (this._lastWatchpointHit !== null) {
        reason = 'data breakpoint';
        this.emit('watchpointHit', this._lastWatchpointHit.id, this._lastWatchpointHit.expression,
          this._lastWatchpointHit.oldValue, this._lastWatchpointHit.newValue, this._currentPosition);
        this._lastWatchpointHit = null;
      } else if (this._lastBreakpointHitId !== null) {
        reason = 'breakpoint';
        this.emit('breakpointHit', this._lastBreakpointHitId, this._currentPosition);
        this._lastBreakpointHitId = null;
      }
      this.emit('stopped', reason, this._currentPosition);
      stepping.resolve();
    }
  }

  // -----------------------------------------------------------------------
  // Private — stderr processing
  // -----------------------------------------------------------------------

  private _onStderr(chunk: Buffer): void {
    const text = chunk.toString();
    // Filter known bashdb noise when stdin is piped
    if (text.includes('/dev/stdin: No such device or address')) {
      return;
    }
    this.emit('output', text, 'stderr');
  }

  // -----------------------------------------------------------------------
  // Private — process exit
  // -----------------------------------------------------------------------

  private _onExit(_code: number | null, _signal: string | null): void {
    if (this._state !== 'terminated') {
      this._state = 'terminated';
      if (!this._isRestarting) {
        this.emit('terminated');
      }
    }
    // Fire-and-forget — terminate() will await the same cached promise
    this._runCleanup();
  }

  // -----------------------------------------------------------------------
  // Private — helpers
  // -----------------------------------------------------------------------

  private _writeToStdin(data: string): void {
    if (this._fifoWriteFd === null) {
      throw new Error('Input FIFO is not open');
    }
    fs.writeSync(this._fifoWriteFd, data);
  }

  private _waitForLaunch(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this._launchWaiter = null;
        reject(new Error('Timed out waiting for bashdb to start. Ensure the script exists and bash --debugger works.'));
      }, COMMAND_TIMEOUT_MS);

      this._launchWaiter = {
        resolve: () => {
          clearTimeout(timer);
          resolve();
        },
        reject: (err: Error) => {
          clearTimeout(timer);
          reject(err);
        },
      };
    });
  }

  private _parseBacktrace(lines: string[]): BashdbStackFrame[] {
    const frames: BashdbStackFrame[] = [];

    for (const line of lines) {
      let m = BT_CURRENT_RE.exec(line);
      if (m) {
        frames.push({
          index: parseInt(m[1], 10),
          functionName: m[2] || undefined,
          args: m[3] || undefined,
          file: m[4],
          line: parseInt(m[5], 10),
          isCurrent: true,
        });
        continue;
      }

      m = BT_FRAME_RE.exec(line);
      if (m) {
        frames.push({
          index: parseInt(m[1], 10),
          functionName: m[2] || undefined,
          args: m[3] || undefined,
          file: m[4],
          line: parseInt(m[5], 10),
          isCurrent: false,
        });
      }
    }

    return frames;
  }

  /**
   * Translate a DAP hitCondition string to a bashdb condition expression.
   * DAP hitCondition examples: ">5", "==3", ">=10", "5" (treated as ==5)
   * Bashdb tracks hit counts internally, but we can't easily access them in conditions.
   * As a workaround, we use a counter variable.
   */
  private _translateHitCondition(bpId: number, hitCondition: string): string | null {
    const trimmed = hitCondition.trim();
    // If it's just a number, treat as "== N"
    if (/^\d+$/.test(trimmed)) {
      return `(( (_dbg_hitcount_${bpId}+=1) == ${trimmed} ))`;
    }
    // If it starts with a comparison operator
    const match = /^([><=!]+)\s*(\d+)$/.exec(trimmed);
    if (match) {
      return `(( (_dbg_hitcount_${bpId}+=1) ${match[1]} ${match[2]} ))`;
    }
    return null;
  }

  /**
   * Return (and cache) the cleanup promise so that both `terminate()`
   * and `_onExit()` can safely call it — only the first call does work.
   */
  private _runCleanup(): Promise<void> {
    if (!this._cleanupPromise) {
      this._cleanupPromise = this._doCleanup();
    }
    return this._cleanupPromise;
  }

  private async _doCleanup(): Promise<void> {
    this._process = null;
    this._stdoutBuffer = '';

    // Stop the FIFO read loop and wait for the in-flight read to complete.
    // This must happen BEFORE closing the fd to prevent fd-reuse races.
    await this._stopFifoRead();

    // Now safe to close FIFO file descriptors
    if (this._fifoReadFd !== null) {
      try { fs.closeSync(this._fifoReadFd); } catch { /* already closed */ }
      this._fifoReadFd = null;
    }
    if (this._fifoWriteFd !== null) {
      try { fs.closeSync(this._fifoWriteFd); } catch { /* already closed */ }
      this._fifoWriteFd = null;
    }
    if (this._outputFifoPath) {
      try { fs.unlinkSync(this._outputFifoPath); } catch { /* may not exist */ }
      this._outputFifoPath = null;
    }
    if (this._inputFifoPath) {
      try { fs.unlinkSync(this._inputFifoPath); } catch { /* may not exist */ }
      this._inputFifoPath = null;
    }
    if (this._fifoDir) {
      try { fs.rmdirSync(this._fifoDir); } catch { /* may not be empty */ }
      this._fifoDir = null;
    }

    if (this._pendingCommand) {
      clearTimeout(this._pendingCommand.timer);
      this._pendingCommand.reject(new Error('Process terminated'));
      this._pendingCommand = null;
    }

    for (const queued of this._commandQueue) {
      queued.reject(new Error('Process terminated'));
    }
    this._commandQueue = [];

    if (this._pendingStepping) {
      clearTimeout(this._pendingStepping.timer);
      this._pendingStepping.reject(new Error('Process terminated'));
      this._pendingStepping = null;
    }

    if (this._launchWaiter) {
      this._launchWaiter.reject(new Error('Process terminated'));
      this._launchWaiter = null;
    }

    this._breakpoints.clear();
    this._fileBreakpoints.clear();
    this._functionBreakpointIds.clear();
    this._actionIds.clear();
    this._lastBreakpointHitId = null;
    this._watchpointIds.clear();
    this._lastWatchpointHit = null;
    this._watchpointHitBuffer = [];
  }
}
