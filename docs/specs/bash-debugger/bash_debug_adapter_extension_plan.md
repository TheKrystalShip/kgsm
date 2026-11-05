# Implementation Plan: VS Code Bash Debug Extension (bashdb DAP Adapter)

> **Project**: A new VS Code debugger extension that fully exposes bashdb's capabilities via the Debug Adapter Protocol.
> **Codename**: `vscode-bashdb` (working name)
> **Based on**: Analysis in `docs/bash_debugging_analysis.md`

## Problem Statement

The existing `rogalmic.bash-debug` VS Code extension is abandoned (no updates since 2021), uses an outdated DAP SDK (`vscode-debugadapter` 1.40.0), and only exposes a fraction of bashdb's capabilities. Bash developers are stuck with a debugging experience far below what bashdb itself can provide.

## Approach

Build a modern VS Code debugger extension from scratch using:
- **TypeScript** with the current `@vscode/debugadapter` SDK
- **Inline debug adapter** pattern (runs inside the extension host process — simplest architecture, recommended by Microsoft for TypeScript-based adapters)
- **bashdb** as the underlying debug engine (system-installed, not bundled)
- **`bash --debugger`** invocation (fixes `$0` and call stack issues)
- **Robust text protocol layer** with structured parsers for bashdb output

The extension will be organized as a clean separation between:
1. **DAP Session** (`src/bashDebugSession.ts`) — Implements DAP request handlers
2. **Bashdb Runtime** (`src/bashdbRuntime.ts`) — Manages the bashdb process and provides a typed API
3. **Output Parser** (`src/parsers/`) — Parses bashdb's text output into structured data
4. **Extension Entry** (`src/extension.ts`) — VS Code extension activation, configuration provider

## Phased Implementation

### Phase 1: Project Scaffolding & Core Lifecycle

**Goal**: Create a working extension that can launch a bash script under bashdb, step through it, and terminate cleanly.

#### Tasks

1. **Initialize project structure**
   - `package.json` with extension manifest, `contributes.debuggers`, `contributes.breakpoints`
   - TypeScript config (`tsconfig.json`)
   - Dependencies: `@vscode/debugadapter`, `@vscode/debugprotocol`, `@types/vscode`
   - ESLint config, `.vscodeignore`, build scripts
   - Use `DebugAdapterInlineImplementation` pattern (no separate process)

2. **Create `src/extension.ts`**
   - Register `DebugConfigurationProvider` for type `bashdb`
   - Implement `resolveDebugConfiguration()` to validate paths and fill defaults
   - Register `DebugAdapterDescriptorFactory` returning `DebugAdapterInlineImplementation`
   - Auto-detect `bash` and `bashdb` paths (check common locations)
   - Activation events: `onDebugResolve:bashdb`

3. **Create `src/bashdbRuntime.ts`** — Core bashdb process manager
   - Spawn bashdb via `bash --debugger -- <script> <args>` using Node `child_process`
   - Communication: stdin/stdout pipes (not FIFOs — simpler and more reliable)
   - Command queue with serialization (bashdb is single-threaded, can't handle concurrent commands)
   - Unique end-of-response sentinel per command (e.g., `echo "<<RESP_ID:uuid>>"`)
   - Event emitter API for: `stopped`, `terminated`, `output`, `breakpointHit`
   - Methods: `launch()`, `step()`, `next()`, `continue()`, `stepOut()`, `pause()`, `terminate()`

4. **Create `src/bashDebugSession.ts`** — DAP session implementation
   - Extend `LoggingDebugSession` from `@vscode/debugadapter`
   - Implement DAP lifecycle: `initializeRequest`, `launchRequest`, `disconnectRequest`
   - Implement stepping: `nextRequest`, `stepInRequest`, `stepOutRequest`, `continueRequest`, `pauseRequest`
   - Implement `threadsRequest` (single thread, hardcoded ID)
   - Report capabilities in `initializeRequest`

5. **Create `src/parsers/outputParser.ts`** — Bashdb output parsing
   - Parse position output: `(/path/to/file.sh:42):` → `{ file, line }`
   - Parse prompt: `bashdb<N>` → ready for next command
   - Parse "Debugged program terminated" → terminated event
   - Parse "Program received signal" → stopped event

6. **Define `launch.json` schema** in `package.json`
   - `program`: path to script (required)
   - `args`: script arguments (string array)
   - `cwd`: working directory
   - `env`: environment variables
   - `pathBash`: override bash path
   - `pathBashdb`: override bashdb path
   - `stopOnEntry`: boolean (default true)
   - `terminalKind`: `integrated` | `external` | `debugConsole`
   - `noDebug`: run without debugging

#### Deliverables
- Extension that can launch, step, and terminate a bash script
- Basic output in debug console
- `stopOnEntry` support

---

### Phase 2: Breakpoints (Source, Conditional, Function)

**Goal**: Full breakpoint support matching bashdb's capabilities.

#### Tasks

1. **Source breakpoints** (`setBreakpointsRequest`)
   - Map DAP `SetBreakpointsArguments` to bashdb `break <file>:<line>` commands
   - Track breakpoint IDs returned by bashdb (format: `Breakpoint N set in file X, line Y`)
   - Clear previous breakpoints per file before setting new ones (`clear <file>:<line>` or `delete N`)
   - Parse bashdb's response to get verified breakpoint info
   - Handle breakpoint hit events: parse `Breakpoint N hit` from stopped output

2. **Conditional breakpoints** (`supportsConditionalBreakpoints = true`)
   - Map DAP `condition` field to bashdb `condition <bp_id> <expr>`
   - Parse condition validation errors from bashdb

3. **Function breakpoints** (`supportsFunctionBreakpoints = true`, `setFunctionBreakpointsRequest`)
   - Map DAP `FunctionBreakpoint` to bashdb `break <function_name>`
   - Track and manage function breakpoint IDs separately

4. **Hit count breakpoints** (`supportsHitConditionalBreakpoints = true`)
   - Map DAP `hitCondition` to bashdb's built-in hit count tracking
   - Parse hit count from `Breakpoint N hit(M times)`

5. **Log points** (`supportsLogPoints = true`)
   - Map DAP `logMessage` to bashdb `action <file>:<line> <expression>` (actions execute without stopping)
   - Parse and relay logged output

#### Deliverables
- Set/clear/hit breakpoints in VS Code gutter
- Conditional breakpoints with expression validation
- Function breakpoints via the breakpoints panel
- Log points (print without stopping)

---

### Phase 3: Variable Inspection & Modification

**Goal**: Full Variables panel with all in-scope variables, array/map visualization, and modification support.

#### Tasks

1. **Stack trace** (`stackTraceRequest`)
   - Send bashdb `backtrace` command (alias `T`)
   - Parse output format: `->N in file 'filename' at line M` and `##N function(args) called from file 'filename' at line M`
   - Create `src/parsers/stackParser.ts` for structured parsing
   - Map to DAP `StackFrame[]` with proper `Source` objects
   - Support frame navigation: track current frame ID

2. **Scopes** (`scopesRequest`)
   - For each frame, provide scopes: `Locals`, `Globals`, `Environment`
   - `Locals`: variables local to the current function (use `info variables` after `frame N`)
   - `Globals`: all global variables (use `info variables` at frame 0)
   - `Environment`: environment variables (use `info variables -x` for exported vars)
   - Use `Handles<>` to manage variable references

3. **Variables** (`variablesRequest`)
   - Create `src/parsers/variableParser.ts`
   - Send bashdb `info variables` to list all variable names
   - For each variable, use `examine <varname>` (which calls `typeset -p`) to get type and value
   - Parse `declare` output formats:
     - `declare -- name="value"` → string
     - `declare -i name="42"` → integer
     - `declare -a name='([0]="a" [1]="b")'` → indexed array (expandable in UI)
     - `declare -A name='([key1]="val1" [key2]="val2")'` → associative array (expandable)
     - `declare -r name="readonly"` → read-only indicator
     - `declare -x name="exported"` → exported indicator
   - Create hierarchical `variablesReference` for arrays/maps (children expandable)
   - Filter out bashdb internal variables (`_Dbg_*` prefix)

4. **Evaluate / hover** (`evaluateRequest`, `supportsEvaluateForHovers = true`)
   - Context `hover`: use bashdb `examine <expr>` and return value
   - Context `watch`: same, for watch panel expressions
   - Context `repl`: use bashdb `eval <expr>` for debug console input
   - Handle evaluation errors gracefully

5. **Set variable** (`setVariableRequest`, `supportsSetVariable = true`)
   - Map to bashdb `eval <varname>=<value>` or direct shell assignment
   - Validate by re-examining the variable after setting
   - Return new value in response

6. **Set expression** (`setExpressionRequest`, `supportsSetExpression = true`)
   - Map to bashdb `eval <expression>`
   - Useful for modifying variables via the debug console

#### Deliverables
- Variables panel auto-populated with all in-scope variables
- Arrays and associative arrays expandable as trees
- Variable type indicators (integer, readonly, exported, array, assoc)
- Hover shows variable values
- Watch expressions
- Debug console with full expression evaluation
- Modify variables from the Variables panel

---

### Phase 4: Watchpoints (Data Breakpoints)

**Goal**: Break when a variable's value changes.

#### Tasks

1. **Data breakpoint info** (`dataBreakpointInfoRequest`, `supportsDataBreakpoints = true`)
   - Check if a variable can be watched (bashdb `watch` requires a defined variable)
   - Return `dataId` = variable name, `description` = human-readable text
   - Report `accessTypes: ['write']` (bashdb watches for value changes)

2. **Set data breakpoints** (`setDataBreakpointsRequest`)
   - Map DAP `DataBreakpoint` to bashdb `watch $<varname>` (or `watche <expr>` for expressions)
   - Track watchpoint IDs from bashdb response
   - Clear previous watchpoints before setting new ones

3. **Watchpoint hit detection**
   - Parse bashdb output for watchpoint triggers (value change notifications)
   - Send `StoppedEvent` with reason `'data breakpoint'`

#### Deliverables
- Right-click variable → "Break When Value Changes"
- Watchpoint indicators in Variables panel
- Stop on watchpoint hit with old/new value display

---

### Phase 5: Advanced Features & Polish

**Goal**: Configuration done, loaded sources, restart, attach, completions, exception handling.

#### Tasks

1. **Configuration done** (`supportsConfigurationDoneRequest = true`)
   - Properly sequence: initialize → set breakpoints → configurationDone → resume/stop
   - Only start execution after all breakpoints are configured

2. **Loaded sources** (`supportsLoadedSourcesRequest = true`)
   - Use bashdb `info files` to list all sourced files
   - Track files as they're sourced during execution

3. **Restart** (`supportsRestartRequest = true`)
   - Use bashdb `restart` command (or `R`)
   - Reset all state and re-apply breakpoints

4. **Terminate** (`supportsTerminateRequest = true`)
   - Graceful termination via bashdb `quit` followed by process cleanup
   - Force-kill if graceful fails

5. **Attach mode** (future, if feasible)
   - Use bashdb's `source bashdb-trace` mechanism
   - Would require the user to instrument their script or have a running bashdb session

6. **Completions** (`supportsCompletionsRequest = true`)
   - Use bashdb `complete <partial>` for debug console autocomplete
   - Provide variable name completions, command completions

7. **Exception breakpoints** (`exceptionBreakpointFilters`)
   - Map bash `ERR` trap to "Break on Error" exception filter
   - Map bash signals (SIGINT, SIGTERM, etc.) to exception categories
   - Use bashdb `handle` command to configure signal handling

8. **Goto targets** (`supportsGotoTargetsRequest = true`)
   - Use bashdb `skip` command to jump to a specific line

#### Deliverables
- Robust session lifecycle with proper initialization sequence
- Restart without re-launching
- Break on error / signal handling
- Debug console autocomplete
- Source file tracking

---

### Phase 6: Testing, Documentation & Publishing

**Goal**: Production-ready extension with tests, docs, and marketplace listing.

#### Tasks

1. **Unit tests**
   - Parser tests (output parser, stack parser, variable parser, breakpoint parser)
   - Runtime command serialization tests
   - Mock bashdb process for integration tests

2. **Integration tests**
   - Use `@vscode/debugadapter-testsupport` for DAP-level testing
   - Test scripts covering: simple step, breakpoints, variables, watchpoints, function calls, sourced files, arrays, error handling

3. **E2E test scripts**
   - `test/scripts/simple.sh` — basic stepping
   - `test/scripts/functions.sh` — function calls, stack frames
   - `test/scripts/variables.sh` — all variable types (string, integer, array, assoc, readonly, exported)
   - `test/scripts/sourced.sh` — multi-file debugging
   - `test/scripts/error.sh` — error handling, exit codes
   - `test/scripts/subshells.sh` — subshell behavior documentation

4. **Documentation**
   - README.md with features, requirements, setup
   - CHANGELOG.md
   - Configuration reference (all `launch.json` attributes)
   - Known limitations (subshell opacity, BASH_REMATCH, performance)
   - Comparison with `rogalmic.bash-debug`

5. **Publishing**
   - Extension icon and branding
   - Marketplace metadata (categories, tags, badges)
   - CI/CD with GitHub Actions (lint, test, build, publish)

6. **Pre-requisite detection**
   - Check bash version ≥ 4.0 (preferably 5.x)
   - Check bashdb is installed and compatible
   - Provide actionable error messages with install instructions

#### Deliverables
- Comprehensive test suite
- Published on VS Code Marketplace
- User-facing documentation

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                    VS Code UI                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐  │
│  │Breakpoint│ │Variables │ │  Stack   │ │ Debug  │  │
│  │  Gutter  │ │  Panel   │ │  Trace   │ │Console │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘  │
│       └────────────┴────────────┴───────────┘       │
│                         │ DAP (JSON)                │
└─────────────────────────┼───────────────────────────┘
                          │
┌─────────────────────────┼────────────────────────────┐
│              Extension Host Process                  │
│                         │                            │
│  ┌──────────────────────▼──────────────────────────┐ │
│  │           bashDebugSession.ts                   │ │
│  │    (DAP Request Handlers - inline adapter)      │ │
│  │                                                 │ │
│  │  initializeRequest()  setBreakpointsRequest()   │ │
│  │  launchRequest()      variablesRequest()        │ │
│  │  nextRequest()        evaluateRequest()         │ │
│  │  stackTraceRequest()  setVariableRequest()      │ │
│  │  scopesRequest()      dataBreakpointInfoReq()   │ │
│  │  ...                  ...                       │ │
│  └──────────────────────┬──────────────────────────┘ │
│                         │ Typed API                  │
│  ┌──────────────────────▼──────────────────────────┐ │
│  │           bashdbRuntime.ts                      │ │
│  │    (Bashdb Process Manager & Command Queue)     │ │
│  │                                                 │ │
│  │  launch()    getVariables()   setBreakpoint()   │ │
│  │  step()      getStackTrace()  setWatchpoint()   │ │
│  │  evaluate()  setVariable()    getCompletions()  │ │
│  └──────────────────────┬──────────────────────────┘ │
│                         │ stdin/stdout               │
│  ┌──────────────────────▼──────────────────────────┐ │
│  │              parsers/                           │ │
│  │  outputParser.ts   stackParser.ts               │ │
│  │  variableParser.ts breakpointParser.ts          │ │
│  │  (Structured text parsing of bashdb output)     │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────────┼────────────────────────────┘
                          │ stdin/stdout pipes
┌─────────────────────────▼────────────────────────────┐
│              bash --debugger                         │
│           (bashdb running inside bash)               │
│                                                      │
│   Commands:  step, next, continue, break, examine,   │
│              info variables, backtrace, watch,       │
│              eval, frame, handle, complete, ...      │
└──────────────────────────────────────────────────────┘
```

## DAP Capabilities Matrix

Summary of all DAP capabilities and their planned support status:

| DAP Capability                      | Phase | Bashdb Command               | Notes                                    |
| ----------------------------------- | ----- | ---------------------------- | ---------------------------------------- |
| `supportsConfigurationDoneRequest`  | 5     | —                            | Proper init sequence                     |
| `supportsConditionalBreakpoints`    | 2     | `condition N expr`           |                                          |
| `supportsHitConditionalBreakpoints` | 2     | Built-in hit counts          |                                          |
| `supportsFunctionBreakpoints`       | 2     | `break funcname`             |                                          |
| `supportsLogPoints`                 | 2     | `action file:line expr`      |                                          |
| `supportsDataBreakpoints`           | 4     | `watch $var` / `watche expr` |                                          |
| `supportsEvaluateForHovers`         | 3     | `examine expr`               |                                          |
| `supportsSetVariable`               | 3     | `eval var=value`             |                                          |
| `supportsSetExpression`             | 3     | `eval expr`                  |                                          |
| `supportsRestartRequest`            | 5     | `restart` / `R`              |                                          |
| `supportsTerminateRequest`          | 5     | `quit` + kill                |                                          |
| `supportsCompletionsRequest`        | 5     | `complete partial`           |                                          |
| `supportsLoadedSourcesRequest`      | 5     | `info files`                 |                                          |
| `supportsGotoTargetsRequest`        | 5     | `skip`                       |                                          |
| `supportsStepBack`                  | ❌    | —                            | Bashdb doesn't support reverse execution |
| `supportsReadMemoryRequest`         | ❌    | —                            | Not applicable to bash                   |
| `supportsDisassembleRequest`        | ❌    | —                            | Not applicable to bash                   |
| `supportsInstructionBreakpoints`    | ❌    | —                            | Not applicable to bash                   |

## Key Technical Decisions

### 1. Communication: stdin/stdout pipes vs FIFOs
**Decision**: Use stdin/stdout pipes.
- The old extension used named FIFOs (`/tmp/vscode-bash-debug-fifo-*`), which caused many platform-specific issues (WSL path translation, macOS compatibility, cleanup failures).
- stdin/stdout pipes are simpler, cross-platform, and managed by Node's `child_process`.

### 2. Invocation: `bash --debugger` vs `bashdb script`
**Decision**: Use `bash --debugger -- script args`.
- Fixes `$0` showing `bashdb` instead of the script name.
- Cleaner call stack (no bashdb frame at the bottom).
- Requires bashdb to be properly installed so bash can find it.
- Fallback to `bashdb -- script args` if `--debugger` fails.

### 3. Adapter mode: inline vs external process
**Decision**: Use `DebugAdapterInlineImplementation`.
- The debug adapter runs inside the extension host process (no separate Node process).
- Simplest architecture, easiest to debug, recommended by Microsoft for TypeScript adapters.
- The bashdb process itself still runs externally (spawned via `child_process`).

### 4. Bashdb version management
**Decision**: Use system-installed bashdb, not bundled.
- The old extension bundled an old copy that drifted out of date.
- Require bashdb to be installed separately (`apt install bashdb`, `brew install bashdb`, etc.).
- Detect version at launch time and warn about incompatibilities.
- Document minimum supported version (bashdb for bash 4.4+).

### 5. Variable discovery strategy
**Decision**: Use `info variables` + `examine` in two passes.
- Pass 1: `info variables` → list of all variable names (filtered by scope)
- Pass 2: `examine <name>` (or `typeset -p <name>`) for each variable → type and value
- Cache results per stopped state to avoid re-querying on panel expansion
- Performance concern: if hundreds of variables, use lazy loading (only query expanded items)

### 6. Output parsing robustness
**Decision**: Use unique sentinel markers per command.
- Before each bashdb command, inject a `print '<<CMD_START:uuid>>'`
- After each command, inject a `print '<<CMD_END:uuid>>'`
- Parse response between matching start/end markers
- This isolates command responses from interleaved program output

## File Structure

```
vscode-bashdb/
├── .vscode/
│   ├── launch.json          # Extension dev launch configs
│   └── tasks.json           # Build tasks
├── src/
│   ├── extension.ts         # Extension entry point
│   ├── bashDebugSession.ts  # DAP session (all request handlers)
│   ├── bashdbRuntime.ts     # Bashdb process manager & typed API
│   ├── parsers/
│   │   ├── outputParser.ts  # General bashdb output parsing
│   │   ├── stackParser.ts   # Backtrace output → StackFrame[]
│   │   ├── variableParser.ts # declare -p output → Variable[]
│   │   └── breakpointParser.ts # Breakpoint set/hit parsing
│   ├── types.ts             # Shared interfaces and types
│   └── util.ts              # Path handling, validation, helpers
├── test/
│   ├── unit/
│   │   ├── outputParser.test.ts
│   │   ├── stackParser.test.ts
│   │   ├── variableParser.test.ts
│   │   └── breakpointParser.test.ts
│   ├── integration/
│   │   └── debugSession.test.ts
│   └── scripts/             # Test bash scripts
│       ├── simple.sh
│       ├── functions.sh
│       ├── variables.sh
│       ├── sourced.sh
│       ├── error.sh
│       └── subshells.sh
├── package.json             # Extension manifest
├── tsconfig.json
├── .eslintrc.json
├── .vscodeignore
├── README.md
├── CHANGELOG.md
└── LICENSE
```

## Risk Mitigation

| Risk                                           | Mitigation                                                                                                  |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Bashdb output format changes between versions  | Parser tests with output samples from multiple versions. Version detection at startup.                      |
| bashdb not installed on user's system          | Clear error message with install instructions per platform. Link to bashdb repo.                            |
| Performance with many variables                | Lazy variable loading. Only query variables for expanded scopes. Cache per stop.                            |
| BASH_REMATCH contamination by bashdb           | Document as known limitation. Can't fix without bashdb changes.                                             |
| Interleaved program output and debugger output | Sentinel-based response isolation. Separate stdout (program) from debugger communication.                   |
| WSL / macOS / Linux path differences           | Minimal path handling. Let bash resolve paths. No WSL path translation (target Linux/macOS only initially). |

## Dependencies

### Runtime
- `bash` ≥ 4.4 (preferably 5.x)
- `bashdb` (matching the bash version)

### Development
- Node.js ≥ 18
- `@vscode/debugadapter` (latest)
- `@vscode/debugprotocol` (latest)
- `@types/vscode` (latest)
- TypeScript 5.x
- `@vscode/debugadapter-testsupport` (for integration tests)
- `@vscode/vsce` (for packaging/publishing)
