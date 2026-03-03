# Bash Debug — VS Code Extension

A modern **Debug Adapter Protocol (DAP)** extension for debugging Bash scripts using [bashdb](https://bashdb.sourceforge.net/).

---

## Features

| Feature                            | Description                                                                                      |
| ---------------------------------- | ------------------------------------------------------------------------------------------------ |
| **Source Breakpoints**             | Set breakpoints by clicking the editor gutter                                                    |
| **Conditional Breakpoints**        | Break only when a bash expression evaluates to true                                              |
| **Hit Count Breakpoints**          | Break after a breakpoint has been hit N times                                                    |
| **Function Breakpoints**           | Break when entering a named function                                                             |
| **Log Points**                     | Print a message to the debug console without stopping execution                                  |
| **Data Breakpoints (Watchpoints)** | Break when a variable's value changes                                                            |
| **Variable Inspection**            | View locals, globals, and environment variables in the Variables panel                           |
| **Array/Map Visualization**        | Expandable tree view for indexed and associative arrays                                          |
| **Variable Modification**          | Change variable values live from the Variables panel                                             |
| **Watch Expressions**              | Monitor arbitrary bash expressions as the script runs                                            |
| **Stack Trace**                    | Navigate the call stack and switch frames                                                        |
| **Hover Evaluation**               | Hover over a variable in the editor to see its current value                                     |
| **Debug Console**                  | Evaluate expressions and execute arbitrary bash code mid-session                                 |
| **Completions**                    | Tab-autocomplete in the debug console                                                            |
| **Exception Breakpoints**          | Break on `ERR`, `SIGINT`, or `SIGTERM` signals                                                   |
| **Loaded Sources**                 | View every file sourced during the session                                                       |
| **Path Mappings**                  | Map local source paths to remote execution paths for sandboxes, containers, and remote debugging |
| **Restart**                        | Restart the debug session without re-launching the terminal                                      |
| **Prerequisite Detection**         | Validates that `bash` and `bashdb` are available at launch, with actionable error messages       |

---

## Requirements

- **Bash** ≥ 4.0 (4.4+ recommended; 5.x optimal for full feature support)
- **bashdb** — must match the major version of the installed bash

### Installing bashdb

Follow the instructions at the [sourceforge](https://sourceforge.net/projects/bashdb/) or [github](https://github.com/Trepan-Debuggers/bashdb) repositories.

Verify your installation:
```bash
$ bash --version
$ bashdb --version
```

---

## Getting Started

1. **Install prerequisites** — see [Requirements](#requirements) above.
2. **Open a bash script** in VS Code.
3. **Create a launch configuration** — Check the full [example](#full-example-launchjson) below.
4. **Press F5** to start debugging.

---

## Configuration Reference

All attributes belong to a `launch` configuration with `"type": "bashdb"`.

### `program` *(required)*
```json
"program": "${file}"
```

Absolute path to the bash script to debug. The `${file}` variable resolves to the currently active editor file.


### `args`

```json
"args": ["--port", "8080", "world.txt"]
```

Array of command-line arguments passed to the script. Defaults to `[]`.

---

### `cwd`

```json
"cwd": "${workspaceFolder}"
```

Working directory for the script process. Defaults to `${workspaceFolder}`.

---

### `env`

```json
"env": {
  "MY_VAR": "hello",
  "DEBUG": "true"
}
```

Additional environment variables set for the script. Merged with the inherited shell environment. Defaults to `{}`.

---

### `pathBash`

```json
"pathBash": "/usr/local/bin/bash"
```

Path to a specific `bash` executable. When omitted, `bash` is resolved from `PATH`.

---

### `pathBashdb`

```json
"pathBashdb": "/usr/local/bin/bashdb"
```

Path to a specific `bashdb` executable. When omitted, `bashdb` is resolved from `PATH`.

---

### `stopOnEntry`

```json
"stopOnEntry": true
```

When `true` (default), execution pauses at the very first line of the script. Set to `false` to run until the first breakpoint.

---

### `terminalKind`

```json
"terminalKind": "debugConsole"
```

Where the script's standard I/O is shown. Accepted values:

| Value            | Description                                             |
| ---------------- | ------------------------------------------------------- |
| `"debugConsole"` | Output appears in the VS Code Debug Console *(default)* |
| `"integrated"`   | A VS Code integrated terminal is opened                 |
| `"external"`     | An external terminal window is launched                 |

---

### `pathMappings`

```json
"pathMappings": [
  {
    "localRoot": "${workspaceFolder}",
    "remoteRoot": "/tmp/sandbox/project"
  }
]
```

Map local source paths to remote execution paths. Used when scripts run in a different filesystem location than the source code — for example, test sandboxes, Docker containers, or CI build directories.

Each entry maps a `localRoot` (the path VS Code knows) to a `remoteRoot` (the path where the script actually executes). The debugger translates paths in both directions:

- **Breakpoints**: local paths are converted to remote paths before sending to bashdb
- **Stack traces**: remote paths are converted back to local paths for display

Mappings are evaluated in order — the first match wins. Defaults to `[]` (no mapping, paths pass through unchanged).

#### Environment variable placeholders

Both `localRoot` and `remoteRoot` support `${env:VAR_NAME}` placeholders that are resolved at runtime from the **debuggee's** environment. This is useful when execution paths are created dynamically (e.g., test sandboxes with random directory names).

```json
"pathMappings": [
  {
    "localRoot": "${workspaceFolder}",
    "remoteRoot": "${env:TEST_SANDBOX}"
  }
]
```

The debugger resolves these placeholders after the debuggee starts, so env vars set during script initialization (before the first breakpoint) are available. If a variable cannot be resolved, the raw placeholder is preserved.

---

### Full example `launch.json`

A full example `launch.json` file can be found in the [.vscode](.vscode/) directory.

---

## Known Limitations

- **`BASH_REMATCH` contamination** — bashdb uses regex internally, which may overwrite `BASH_REMATCH` between steps.
- **Performance with many variables** — sessions with hundreds of variables may be slower; lazy loading in the Variables panel mitigates this.
- **No attach mode** — bashdb does not support attaching to a running process.
- **No reverse debugging** — stepping backwards is not supported by bashdb.
- **No `goto` targets** — bashdb's `skip` command does not map to arbitrary line jumps, so the DAP `goto` request is not implemented.

---

## Comparison with rogalmic.bash-debug

| Feature                        | rogalmic.bash-debug | This Extension |
| ------------------------------ | :-----------------: | :------------: |
| Watchpoints (data breakpoints) |          ❌          |       ✅        |
| Conditional Breakpoints        |       Partial       |     ✅ Full     |
| Function Breakpoints           |          ❌          |       ✅        |
| Hit Count Breakpoints          |          ❌          |       ✅        |
| Log Points                     |          ❌          |       ✅        |
| Variable Modification          |          ❌          |       ✅        |
| Exception Breakpoints          |          ❌          |       ✅        |
| Debug Console Completions      |          ❌          |       ✅        |
| Loaded Sources                 |          ❌          |       ✅        |
| Restart                        |          ❌          |       ✅        |
| Prerequisite Detection         |        Basic        |     ✅ Full     |
| DAP SDK                        |     Deprecated      |    Current     |
| Actively maintained            |   ❌ (since 2021)    |       ✅        |

---

## Development

```bash
cd .vscode/bash-debugger

# Install dependencies
npm install

# Compile TypeScript
npm run build

# Watch mode (recompile on save)
npm run watch

# Run all tests
npm test

# Run only unit tests
npm run test:unit

# Run only integration tests
npm run test:integration

# Lint
npm run lint
```

Tests live in `test/unit/` and `test/integration/`. Fixture bash scripts used by integration tests are in `test/scripts/`.

---

## License

[GNU General Public License v3.0](LICENSE)
