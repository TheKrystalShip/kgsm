import * as path from 'path';

import {
  LoggingDebugSession,
  InitializedEvent,
  StoppedEvent,
  TerminatedEvent,
  OutputEvent,
  Breakpoint,
  Thread,
  StackFrame,
  Source,
  Handles,
  Scope,
  logger,
} from '@vscode/debugadapter';
import { DebugProtocol } from '@vscode/debugprotocol';

import { LaunchRequestArguments, StopReason, BashdbPosition, BashdbVariable } from './types';
import { BashdbRuntime } from './bashdbRuntime';
import { shellEscape } from './util';

const THREAD_ID = 1;

interface VariableReference {
  type: 'scope' | 'variable';
  scope?: string;         // for type='scope': 'locals' | 'globals' | 'environment'
  frameId?: number;       // stack frame this reference belongs to
  variable?: BashdbVariable;  // for type='variable': the parent variable with children
}

export class BashDebugSession extends LoggingDebugSession {
  private _runtime: BashdbRuntime;
  private _variableHandles = new Handles<VariableReference>();
  private _stopOnEntry = true;

  public constructor() {
    super('bashdb-debug.txt');

    this.setDebuggerLinesStartAt1(true);
    this.setDebuggerColumnsStartAt1(true);

    this._runtime = new BashdbRuntime();

    this._runtime.on('stopped', (reason: StopReason, _position: BashdbPosition) => {
      this._variableHandles.reset();
      this.sendEvent(new StoppedEvent(reason, THREAD_ID));
    });

    this._runtime.on('terminated', () => {
      this.sendEvent(new TerminatedEvent());
    });

    this._runtime.on('output', (text: string, category: string) => {
      this.sendEvent(new OutputEvent(text + '\n', category));
    });

    this._runtime.on('error', (msg: string) => {
      this.sendEvent(new OutputEvent(msg + '\n', 'stderr'));
    });

    this._runtime.on('watchpointHit', (
      _watchpointId: number,
      expression: string,
      oldValue: string,
      newValue: string,
      _position: BashdbPosition,
    ) => {
      this.sendEvent(new OutputEvent(
        `Watchpoint hit: ${expression}\n  Old value: ${oldValue}\n  New value: ${newValue}\n`,
        'console',
      ));
    });
  }

  protected initializeRequest(
    response: DebugProtocol.InitializeResponse,
    _args: DebugProtocol.InitializeRequestArguments,
  ): void {
    response.body = response.body || {};

    response.body.supportsConfigurationDoneRequest = true;
    response.body.supportsEvaluateForHovers = true;
    response.body.supportsConditionalBreakpoints = true;
    response.body.supportsHitConditionalBreakpoints = true;
    response.body.supportsFunctionBreakpoints = true;
    response.body.supportsLogPoints = true;
    response.body.supportsSetVariable = true;
    response.body.supportsSetExpression = true;
    response.body.supportsTerminateRequest = true;

    response.body.supportsDataBreakpoints = true;
    response.body.supportsRestartRequest = true;
    response.body.supportsCompletionsRequest = true;
    response.body.supportsLoadedSourcesRequest = true;
    // Goto targets disabled — bashdb's `skip` only skips N statements,
    // it cannot jump to an arbitrary line number reliably
    response.body.supportsGotoTargetsRequest = false;
    response.body.supportsStepBack = false;

    response.body.exceptionBreakpointFilters = [
      {
        filter: 'err',
        label: 'Break on ERR',
        description: 'Stop when a command returns a non-zero exit status (bash ERR trap)',
        default: false,
        supportsCondition: false,
      },
      {
        filter: 'sigint',
        label: 'Break on SIGINT',
        description: 'Stop when the script receives SIGINT (Ctrl+C)',
        default: false,
        supportsCondition: false,
      },
      {
        filter: 'sigterm',
        label: 'Break on SIGTERM',
        description: 'Stop when the script receives SIGTERM',
        default: false,
        supportsCondition: false,
      },
    ];

    this.sendEvent(new InitializedEvent());
    this.sendResponse(response);
  }

  protected launchRequest(
    response: DebugProtocol.LaunchResponse,
    args: DebugProtocol.LaunchRequestArguments,
  ): void {
    const launchArgs = args as unknown as LaunchRequestArguments;

    if (launchArgs.stopOnEntry === undefined) {
      launchArgs.stopOnEntry = true;
    }

    if (!launchArgs.cwd) {
      launchArgs.cwd = path.dirname(launchArgs.program);
    }

    this._stopOnEntry = launchArgs.stopOnEntry !== false;

    this._runtime
      .launch(launchArgs)
      .then(() => {
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err.message;
        this.sendResponse(response);
      });
  }

  protected configurationDoneRequest(
    response: DebugProtocol.ConfigurationDoneResponse,
    _args: DebugProtocol.ConfigurationDoneArguments,
  ): void {
    // All breakpoints have been set — now start/stop execution
    this._runtime.continueAfterConfigDone(this._stopOnEntry);
    this.sendResponse(response);
  }

  protected disconnectRequest(
    response: DebugProtocol.DisconnectResponse,
    _args: DebugProtocol.DisconnectArguments,
  ): void {
    this._runtime
      .terminate()
      .then(() => {
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err.message;
        this.sendResponse(response);
      });
  }

  protected threadsRequest(response: DebugProtocol.ThreadsResponse): void {
    response.body = {
      threads: [new Thread(THREAD_ID, 'Main Thread')],
    };
    this.sendResponse(response);
  }

  protected stackTraceRequest(
    response: DebugProtocol.StackTraceResponse,
    _args: DebugProtocol.StackTraceArguments,
  ): void {
    this._runtime
      .getStackTrace()
      .then((frames) => {
        response.body = {
          stackFrames: frames.map(
            (f, i) =>
              new StackFrame(
                i,
                f.functionName || '<global>',
                new Source(path.basename(f.file), f.file),
                f.line,
              ),
          ),
          totalFrames: frames.length,
        };
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err.message;
        this.sendResponse(response);
      });
  }

  protected scopesRequest(
    response: DebugProtocol.ScopesResponse,
    args: DebugProtocol.ScopesArguments,
  ): void {
    const frameId = args.frameId;
    response.body = {
      scopes: [
        new Scope(
          'Local',
          this._variableHandles.create({ type: 'scope', scope: 'locals', frameId }),
          false,
        ),
        new Scope(
          'Global',
          this._variableHandles.create({ type: 'scope', scope: 'globals', frameId }),
          true,
        ),
        new Scope(
          'Environment',
          this._variableHandles.create({ type: 'scope', scope: 'environment', frameId }),
          true,
        ),
      ],
    };
    this.sendResponse(response);
  }

  protected variablesRequest(
    response: DebugProtocol.VariablesResponse,
    args: DebugProtocol.VariablesArguments,
  ): void {
    const ref = this._variableHandles.get(args.variablesReference);
    if (!ref) {
      response.body = { variables: [] };
      this.sendResponse(response);
      return;
    }

    if (ref.type === 'scope') {
      this._getScopeVariables(ref)
        .then((variables) => {
          response.body = { variables };
          this.sendResponse(response);
        })
        .catch((err) => {
          // Silently return empty when commands were cancelled due to resumed execution
          if (err instanceof Error && err.message.includes('cancelled')) {
            response.body = { variables: [] };
            this.sendResponse(response);
            return;
          }
          response.success = false;
          response.message = err instanceof Error ? err.message : String(err);
          this.sendResponse(response);
        });
    } else if (ref.type === 'variable' && ref.variable?.children) {
      // Return children of an array or associative array
      const variables: DebugProtocol.Variable[] = ref.variable.children.map((child) => ({
        name: child.name,
        value: child.value,
        type: child.type,
        variablesReference: 0,
        evaluateName: `${ref.variable!.name}${child.name}`,  // e.g., myarray[0]
      }));
      response.body = { variables };
      this.sendResponse(response);
    } else {
      response.body = { variables: [] };
      this.sendResponse(response);
    }
  }

  protected continueRequest(
    response: DebugProtocol.ContinueResponse,
    _args: DebugProtocol.ContinueArguments,
  ): void {
    // Send the response immediately per DAP protocol — the StoppedEvent
    // will be sent later when execution actually pauses at the next breakpoint.
    response.body = { allThreadsContinued: true };
    this.sendResponse(response);
    this._runtime.continue().catch(() => {
      // Errors surface via terminated/error events
    });
  }

  protected nextRequest(
    response: DebugProtocol.NextResponse,
    _args: DebugProtocol.NextArguments,
  ): void {
    this.sendResponse(response);
    this._runtime.next().catch(() => {});
  }

  protected stepInRequest(
    response: DebugProtocol.StepInResponse,
    _args: DebugProtocol.StepInArguments,
  ): void {
    this.sendResponse(response);
    this._runtime.step().catch(() => {});
  }

  protected stepOutRequest(
    response: DebugProtocol.StepOutResponse,
    _args: DebugProtocol.StepOutArguments,
  ): void {
    this.sendResponse(response);
    this._runtime.stepOut().catch(() => {});
  }

  protected pauseRequest(
    response: DebugProtocol.PauseResponse,
    _args: DebugProtocol.PauseArguments,
  ): void {
    this._runtime
      .pause()
      .then(() => {
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err.message;
        this.sendResponse(response);
      });
  }

  protected evaluateRequest(
    response: DebugProtocol.EvaluateResponse,
    args: DebugProtocol.EvaluateArguments,
  ): void {
    const context = args.context || 'hover';

    this._runtime
      .evaluate(args.expression, context)
      .then((result) => {
        let variablesReference = 0;
        if (result.variablesReference?.children) {
          variablesReference = this._variableHandles.create({
            type: 'variable',
            variable: result.variablesReference,
          });
        }

        response.body = {
          result: result.result,
          type: result.type,
          variablesReference,
        };
        this.sendResponse(response);
      })
      .catch((err) => {
        // For hover, silently return empty instead of erroring
        if (context === 'hover') {
          response.body = { result: '', variablesReference: 0 };
          this.sendResponse(response);
        } else {
          response.success = false;
          response.message = err instanceof Error ? err.message : String(err);
          this.sendResponse(response);
        }
      });
  }

  protected setVariableRequest(
    response: DebugProtocol.SetVariableResponse,
    args: DebugProtocol.SetVariableArguments,
  ): void {
    this._runtime
      .setVariable(args.name, args.value)
      .then((updated) => {
        let variablesReference = 0;
        if (updated.children && updated.children.length > 0) {
          variablesReference = this._variableHandles.create({
            type: 'variable',
            variable: updated,
          });
        }

        response.body = {
          value: updated.value,
          type: updated.type,
          variablesReference,
        };
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }

  protected setExpressionRequest(
    response: DebugProtocol.SetExpressionResponse,
    args: DebugProtocol.SetExpressionArguments,
  ): void {
    this._runtime
      .setExpression(args.expression, args.value)
      .then((result) => {
        response.body = {
          value: result,
          variablesReference: 0,
        };
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }

  private async _getScopeVariables(ref: VariableReference): Promise<DebugProtocol.Variable[]> {
    // Capture the stop version so we can detect if execution resumed mid-fetch
    const version = this._runtime.stopVersion;

    // Select the appropriate frame if specified
    if (ref.frameId !== undefined && ref.frameId > 0) {
      await this._runtime.selectFrame(ref.frameId);
    }

    // Abort if execution resumed since we started
    if (this._runtime.stopVersion !== version) return [];

    const names = await this._runtime.getVariableNames(ref.scope || 'locals');
    if (this._runtime.stopVersion !== version) return [];

    const vars = await this._runtime.getVariables(names);
    if (this._runtime.stopVersion !== version) return [];

    return vars.map((v) => {
      let variablesReference = 0;
      if (v.children && v.children.length > 0) {
        variablesReference = this._variableHandles.create({
          type: 'variable',
          variable: v,
        });
      }

      // Build a readable display value
      let displayValue = v.value;
      if (v.type === 'array' || v.type === 'associative') {
        const count = v.children ? v.children.length : 0;
        displayValue = v.type === 'array'
          ? `Array(${count})`
          : `AssocArray(${count})`;
      }

      // Build type string with attributes
      let typeStr = v.type;
      if (v.attributes.length > 0) {
        typeStr += ` [${v.attributes.join(', ')}]`;
      }

      return {
        name: v.name,
        value: displayValue,
        type: typeStr,
        variablesReference,
        evaluateName: v.name,
      } as DebugProtocol.Variable;
    });
  }

  protected setBreakPointsRequest(
    response: DebugProtocol.SetBreakpointsResponse,
    args: DebugProtocol.SetBreakpointsArguments,
  ): void {
    const sourcePath = args.source.path;
    if (!sourcePath) {
      response.body = { breakpoints: [] };
      this.sendResponse(response);
      return;
    }

    const clientBreakpoints = args.breakpoints || [];

    // Clear existing breakpoints for this file, then set new ones
    this._runtime
      .clearFileBreakpoints(sourcePath)
      .then(async () => {
        const resultBreakpoints: DebugProtocol.Breakpoint[] = [];

        for (const sbp of clientBreakpoints) {
          try {
            // Check if this is a logpoint
            if (sbp.logMessage) {
              // Logpoints use bashdb actions — they print without stopping
              // Shell-escape the message to handle embedded quotes safely
              const escaped = shellEscape(sbp.logMessage);
              const action = await this._runtime.setAction(
                sourcePath,
                sbp.line,
                `printf '%s\\n' ${escaped}`,
              );
              const bp = new Breakpoint(true, sbp.line);
              bp.setId(action.id);
              resultBreakpoints.push(bp);
            } else {
              // Regular breakpoint (with optional condition and hit condition)
              const bashdbBp = await this._runtime.setBreakpoint(
                sourcePath,
                sbp.line,
                sbp.condition,
                sbp.hitCondition,
              );
              const bp = new Breakpoint(true, bashdbBp.line);
              bp.setId(bashdbBp.id);
              resultBreakpoints.push(bp);
            }
          } catch (err) {
            // Breakpoint failed to set — mark as unverified
            const bp = new Breakpoint(false, sbp.line);
            (bp as DebugProtocol.Breakpoint).message = err instanceof Error ? err.message : String(err);
            resultBreakpoints.push(bp);
          }
        }

        response.body = { breakpoints: resultBreakpoints };
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }

  protected setFunctionBreakPointsRequest(
    response: DebugProtocol.SetFunctionBreakpointsResponse,
    args: DebugProtocol.SetFunctionBreakpointsArguments,
  ): void {
    const funcBreakpoints = args.breakpoints || [];

    // Clear all existing function breakpoints, then set new ones
    this._runtime
      .clearFunctionBreakpoints()
      .then(async () => {
        const resultBreakpoints: DebugProtocol.Breakpoint[] = [];

        for (const fbp of funcBreakpoints) {
          try {
            const bashdbBp = await this._runtime.setFunctionBreakpoint(
              fbp.name,
              fbp.condition,
            );
            const bp = new Breakpoint(true, bashdbBp.line);
            bp.setId(bashdbBp.id);
            (bp as DebugProtocol.Breakpoint).message = `${fbp.name} → ${path.basename(bashdbBp.file)}:${bashdbBp.line}`;
            resultBreakpoints.push(bp);
          } catch (err) {
            const bp = new Breakpoint(false);
            (bp as DebugProtocol.Breakpoint).message = err instanceof Error ? err.message : String(err);
            resultBreakpoints.push(bp);
          }
        }

        response.body = { breakpoints: resultBreakpoints };
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }

  protected dataBreakpointInfoRequest(
    response: DebugProtocol.DataBreakpointInfoResponse,
    args: DebugProtocol.DataBreakpointInfoArguments,
  ): void {
    const variableName = args.name;

    this._runtime
      .canWatch(variableName)
      .then((canWatch) => {
        if (canWatch) {
          response.body = {
            dataId: variableName,
            description: `Watch: ${variableName}`,
            accessTypes: ['write'],
            canPersist: false,
          };
        } else {
          response.body = {
            dataId: null,
            description: `Cannot watch '${variableName}': variable not found or not watchable`,
          };
        }
        this.sendResponse(response);
      })
      .catch((err) => {
        response.body = {
          dataId: null,
          description: err instanceof Error ? err.message : String(err),
        };
        this.sendResponse(response);
      });
  }

  protected setDataBreakpointsRequest(
    response: DebugProtocol.SetDataBreakpointsResponse,
    args: DebugProtocol.SetDataBreakpointsArguments,
  ): void {
    const dataBreakpoints = args.breakpoints || [];

    this._runtime
      .clearWatchpoints()
      .then(async () => {
        const resultBreakpoints: DebugProtocol.Breakpoint[] = [];

        for (const dbp of dataBreakpoints) {
          try {
            const wp = await this._runtime.setWatchpoint(dbp.dataId);
            resultBreakpoints.push({
              verified: true,
              id: wp.id,
              message: `Watching ${wp.expression} (current: ${wp.currentValue})`,
            });
          } catch (err) {
            resultBreakpoints.push({
              verified: false,
              message: err instanceof Error ? err.message : String(err),
            });
          }
        }

        response.body = { breakpoints: resultBreakpoints };
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }

  protected setExceptionBreakPointsRequest(
    response: DebugProtocol.SetExceptionBreakpointsResponse,
    args: DebugProtocol.SetExceptionBreakpointsArguments,
  ): void {
    const filters = args.filters || [];

    // Configure signal handling based on selected filters
    const configureSignals = async () => {
      // ERR trap — break on non-zero exit status
      await this._runtime.handleSignal('ERR', filters.includes('err'), filters.includes('err'));

      // SIGINT
      await this._runtime.handleSignal('INT', filters.includes('sigint'), filters.includes('sigint'));

      // SIGTERM
      await this._runtime.handleSignal('TERM', filters.includes('sigterm'), filters.includes('sigterm'));
    };

    configureSignals()
      .then(() => {
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }

  protected terminateRequest(
    response: DebugProtocol.TerminateResponse,
    _args: DebugProtocol.TerminateArguments,
  ): void {
    this._runtime
      .terminate()
      .then(() => {
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err.message;
        this.sendResponse(response);
      });
  }

  protected restartRequest(
    response: DebugProtocol.RestartResponse,
    _args: DebugProtocol.RestartArguments,
  ): void {
    this._runtime
      .restart()
      .then(() => {
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }

  protected loadedSourcesRequest(
    response: DebugProtocol.LoadedSourcesResponse,
    _args: DebugProtocol.LoadedSourcesArguments,
  ): void {
    this._runtime
      .getLoadedSources()
      .then((sources) => {
        response.body = {
          sources: sources.map((s) => new Source(path.basename(s.file), s.file)),
        };
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }

  protected completionsRequest(
    response: DebugProtocol.CompletionsResponse,
    args: DebugProtocol.CompletionsArguments,
  ): void {
    const text = args.text.substring(0, args.column - 1).trim();

    this._runtime
      .getCompletions(text)
      .then((matches) => {
        response.body = {
          targets: matches.map((m) => ({
            label: m,
            type: 'text' as DebugProtocol.CompletionItemType,
          })),
        };
        this.sendResponse(response);
      })
      .catch(() => {
        // Silently return empty completions on error
        response.body = { targets: [] };
        this.sendResponse(response);
      });
  }

  protected gotoTargetsRequest(
    response: DebugProtocol.GotoTargetsResponse,
    args: DebugProtocol.GotoTargetsArguments,
  ): void {
    // Report the requested line as a valid goto target
    // bashdb's `skip` command skips N statements, but we present it as "jump to line"
    const target: DebugProtocol.GotoTarget = {
      id: args.line,
      label: `Line ${args.line}`,
      line: args.line,
    };
    response.body = { targets: [target] };
    this.sendResponse(response);
  }

  protected gotoRequest(
    response: DebugProtocol.GotoResponse,
    args: DebugProtocol.GotoArguments,
  ): void {
    // Use skip to advance past statements
    // Note: this is an approximation — skip doesn't jump to a specific line,
    // it skips N statements. We skip 1 as a basic implementation.
    this._runtime
      .skip(1)
      .then(() => {
        this.sendResponse(response);
      })
      .catch((err) => {
        response.success = false;
        response.message = err instanceof Error ? err.message : String(err);
        this.sendResponse(response);
      });
  }
}

export default BashDebugSession;
