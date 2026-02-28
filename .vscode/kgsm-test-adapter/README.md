# KGSM VS Code Test Adapter

This document explains the KGSM VS Code Test Adapter extension—its purpose, architecture, internal structure, and critical implementation details. It is aimed at developers (and AI models) working on or extending the extension.

---

## Table of Contents

- [KGSM VS Code Test Adapter](#kgsm-vs-code-test-adapter)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [File Structure](#file-structure)
  - [Activation](#activation)
  - [Architecture Overview](#architecture-overview)
  - [Extension Lifecycle](#extension-lifecycle)
    - [`activate(context)`](#activatecontext)
    - [`deactivate()`](#deactivate)
  - [Test Discovery](#test-discovery)
    - [Expected `--list-json` Output Schema](#expected---list-json-output-schema)
    - [Three-Level Tree Structure](#three-level-tree-structure)
    - [Test Item ID Conventions](#test-item-id-conventions)
  - [Test Execution (`runTests`)](#test-execution-runtests)
    - [Request Decomposition](#request-decomposition)
    - [Argument Construction](#argument-construction)
    - [Pattern Limit Heuristic](#pattern-limit-heuristic)
    - [Incremental TAP Parsing](#incremental-tap-parsing)
  - [TAP Stream Parser (`TapStreamParser`)](#tap-stream-parser-tapstreamparser)
    - [Expected TAP Format](#expected-tap-format)
    - [YAML Diagnostic Block Schema](#yaml-diagnostic-block-schema)
    - [State Machine](#state-machine)
    - [YAML Parsing Limitations](#yaml-parsing-limitations)
  - [Test Debugging (`debugTests`)](#test-debugging-debugtests)
  - [Function Range Updates (`updateFunctionRanges`)](#function-range-updates-updatefunctionranges)
  - [CodeLens Provider (`KgsmTestCodeLensProvider`)](#codelens-provider-kgsmtestcodelensprovider)
  - [`runCommand` Helper](#runcommand-helper)
  - [`findTestItem` Helper](#findtestitem-helper)
  - [Module-Level Globals](#module-level-globals)
  - [Critical Considerations](#critical-considerations)
    - [1. Only the First Workspace Folder Is Used](#1-only-the-first-workspace-folder-is-used)
    - [2. `tests/run.sh` Must Support `--list-json`](#2-testsrunsh-must-support---list-json)
    - [3. TAP Line Format Is Rigid](#3-tap-line-format-is-rigid)
    - [4. `expected` and `actual` in YAML Are Strings Only](#4-expected-and-actual-in-yaml-are-strings-only)
    - [5. CodeLenses Require Prior Discovery](#5-codelenses-require-prior-discovery)
    - [6. `item.parent` Is Not Guaranteed](#6-itemparent-is-not-guaranteed)
    - [7. Pattern Limit of 58 Is a Magic Number](#7-pattern-limit-of-58-is-a-magic-number)
    - [8. `NO_COLOR=1` Is Mandatory](#8-no_color1-is-mandatory)
    - [9. File Watcher Only Detects Create and Delete](#9-file-watcher-only-detects-create-and-delete)
    - [10. `updateFunctionRanges` Only Affects Existing Items](#10-updatefunctionranges-only-affects-existing-items)
    - [11. Type Groups Are Always Recreated](#11-type-groups-are-always-recreated)
    - [12. Debug Requires `rogalmic.bash-debug`](#12-debug-requires-rogalmicbash-debug)

---

## Overview

The extension lives at `.vscode/kgsm-test-adapter/` and is a **plain JavaScript VS Code extension** with no build step, no bundler, and no npm dependencies beyond the VS Code API and Node.js built-ins. It integrates KGSM's bash testing framework with VS Code's native Testing API (the Test Explorer panel), providing:

- **Test discovery** — reads test metadata from `tests/run.sh --list-json`.
- **Test execution** — runs `tests/run.sh` and parses its TAP v14 output.
- **Test debugging** — launches a `bashdb` debug session via the `rogalmic.bash-debug` extension.
- **CodeLens** — inline "Run" and "Debug" buttons above each `test_*` function in test files.
- **Live range updates** — keeps gutter icons aligned as test files are edited.

---

## File Structure

```
.vscode/kgsm-test-adapter/
├── package.json    # Extension manifest (activation, commands)
└── extension.js   # Entire extension in a single file
```

There is no `node_modules/`, no `tsconfig.json`, and no compilation step.

---

## Activation

The extension declares a **lazy activation event**:

```json
"activationEvents": ["workspaceContains:tests/run.sh"]
```

VS Code only activates this extension if `tests/run.sh` exists in the workspace root. It will not activate for arbitrary workspaces.

Once active, tests are not auto-discovered on startup — they are discovered when:
- The user opens the Test Explorer panel (VS Code calls `controller.resolveHandler` with `null`).
- The user clicks the Refresh button (`controller.refreshHandler`).
- A test file matching `tests/{unit,integration,e2e}/test_*.sh` is created or deleted (file system watcher).

---

## Architecture Overview

```
VS Code Testing API
       │
       ▼
  TestController ("kgsm")
       │
       ├─ resolveHandler ──► discoverTests() ──► tests/run.sh --list-json ──► JSON
       ├─ refreshHandler ──► discoverTests()
       │
       ├─ Run profile ──────► runTests(request) ──► tests/run.sh [args] ──► TAP output ──► TapStreamParser
       └─ Debug profile ────► debugTests(request) ──► vscode.debug.startDebugging (bashdb)

VS Code Editor
       │
       ├─ FileSystemWatcher ──► discoverTests() on .sh file create/delete
       ├─ onDidSaveTextDocument ──► updateFunctionRanges(doc)
       └─ CodeLensProvider ──► "Run" / "Debug" above each test_* function
```

---

## Extension Lifecycle

### `activate(context)`

1. Reads `workspaceFolders[0].uri.fsPath` as `workspaceRoot`. If no folders are open, returns immediately.
2. Creates the `TestController` with ID `"kgsm"` and registers it on `context.subscriptions`.
3. Assigns `resolveHandler` and `refreshHandler`.
4. Creates a **Run** profile (default) and a **Debug** profile on the controller.
5. Creates a `FileSystemWatcher` for `tests/{unit,integration,e2e}/test_*.sh` and wires create/delete events to `discoverTests()`. The `onDidChange` event is a no-op (content changes handled by `onDidSaveTextDocument`).
6. Registers `onDidSaveTextDocument` to call `updateFunctionRanges(doc)` for test files.
7. Creates the `"KGSM Tests"` output channel.
8. Registers the `KgsmTestCodeLensProvider` for shell scripts matching the test file glob.
9. Registers the `kgsm.runTestFunction` and `kgsm.debugTestFunction` commands.

All resources (controller, watcher, output channel, commands) are pushed to `context.subscriptions` and are auto-disposed when the extension is deactivated.

### `deactivate()`

Empty — all cleanup is handled by `context.subscriptions` disposal. Unlike the `kgsm-extension`, there is no manual timer to clear.

---

## Test Discovery

### Expected `--list-json` Output Schema

Discovery calls `tests/run.sh --list-json` and expects a JSON array on stdout:

```json
[
  {
    "type": "unit",
    "name": "test_config",
    "file": "tests/unit/test_config.sh",
    "functions": [
      { "name": "test_parse_key", "line": 42 },
      { "name": "test_merge_defaults", "line": 67 }
    ]
  },
  {
    "type": "integration",
    "name": "test_lifecycle",
    "file": "tests/integration/test_lifecycle.sh",
    "functions": ["test_start", "test_stop"]
  }
]
```

Fields:

| Field       | Type     | Description                                                       |
| ----------- | -------- | ----------------------------------------------------------------- |
| `type`      | `string` | Category: `"unit"`, `"integration"`, or `"e2e"`                   |
| `name`      | `string` | Used as the test item ID and display label                        |
| `file`      | `string` | Path relative to `workspaceRoot` — used to build the `vscode.Uri` |
| `functions` | `array`  | Each element is either a `string` (name only) or `{ name, line }` |

The `functions[].line` value is a **1-based line number**. The extension stores it as `fnItem.range` using `line - 1` (0-based).

If `functions` is missing or empty, no child items are created for that test file.

### Three-Level Tree Structure

```
unit                      ← type group  (no uri, id = "unit")
  ├─ test_config          ← test file   (uri = .../tests/unit/test_config.sh, id = "test_config")
  │    ├─ test_parse_key  ← function    (id = "test_config::test_parse_key")
  │    └─ test_merge_...  ← function    (id = "test_config::test_merge_defaults")
  └─ test_paths           ← test file   ...
integration               ← type group
  └─ test_lifecycle       ← test file
e2e                       ← type group
  └─ ...
```

Type groups are created on every `discoverTests()` call. All existing items are deleted first (`controller.items.forEach(item => controller.items.delete(item.id))`).

### Test Item ID Conventions

| Level      | ID format              | Example                         |
| ---------- | ---------------------- | ------------------------------- |
| Type group | `"{type}"`             | `"unit"`                        |
| Test file  | `"{name}"` (from JSON) | `"test_config"`                 |
| Function   | `"{name}::{fnName}"`   | `"test_config::test_parse_key"` |

The double-colon `::` separator is the key discriminator used throughout the execution and debug logic. Any code that needs to distinguish a function-level item from a file-level item checks `item.id.includes("::")`.

---

## Test Execution (`runTests`)

`runTests(request, token)` is the Run profile callback. It receives a `vscode.TestRunRequest` and an optional `CancellationToken`.

### Request Decomposition

The function classifies each item in `request.include` into one of three categories:

| Condition                             | Classification      | Action                                               |
| ------------------------------------- | ------------------- | ---------------------------------------------------- |
| `item.id.includes("::")`              | Function-level item | Find parent file item; record in `functionItems` map |
| `item.children.size > 0 && !item.uri` | Type group          | Expand into its file-level children                  |
| Otherwise                             | File-level item     | Add directly to `testsToRun`                         |

If `request.include` is `null` or empty, all file-level items from all groups are collected (run-all mode).

After decomposition:
- `testsToRun`: array of file-level `TestItem` objects.
- `functionItems`: `Map<parentId, fnItem[]>` — which functions were explicitly requested per file.
- `requestedFnIds`: flat `Set` of all explicitly requested function item IDs.

### Argument Construction

Arguments for `tests/run.sh` are built as follows:

```
[--pattern <name1|name2|...>]   (omitted if names.length >= 58)
[--function <fnName>]           (only if exactly 1 file and 1 function requested)
[...types]                      (unique parent IDs of all testsToRun items)
```

The `types` array appended at the end contains the distinct type group IDs (`"unit"`, `"integration"`, `"e2e"`). This tells `tests/run.sh` which test categories to run.

### Pattern Limit Heuristic

```js
if (names.length < 58) {
  args.push("--pattern", names.join("|"));
}
```

When 58 or more test file names are present, the `--pattern` filter is silently dropped and all tests are run. This threshold is a rough heuristic to avoid an excessively long command line and to treat "almost all tests selected" as "run all tests". There is no configuration for this threshold.

### Incremental TAP Parsing

`runCommand` is called with an `onLine` callback, allowing `TapStreamParser` to receive and process each TAP line as it is streamed from the process. This means test results appear in the Test Explorer **as the test run progresses**, not all at once at the end.

For each parsed result `r`, the runner:
- **Pass**: calls `run.passed(testItem, r.duration)` and `run.passed(fnItem, ...)` for each child (or only requested children if `requestedFnIds` is non-empty).
- **Skip**: calls `run.skipped(testItem)` and child items similarly.
- **Fail**: constructs `vscode.TestMessage` objects from `r.failures`, attaches `location` (file + line), and calls `run.failed(testItem, messages, r.duration)`. Individual function items are marked failed or passed based on whether their name appears in `r.failures[].function`.

After `runCommand` resolves:
- `parser.flush()` emits any result left buffered (last line with no trailing newline).
- Any `testsToRun` items not in `emittedTests` are marked `run.errored(...)` with the message `"Test did not produce TAP output"`.
- `run.end()` is called unconditionally.

If `runCommand` returns `null` (cancelled or spawn error), all un-emitted tests are marked `run.skipped()` and the run ends.

---

## TAP Stream Parser (`TapStreamParser`)

### Expected TAP Format

The parser expects **TAP version 14** output from `tests/run.sh`:

```
TAP version 14
1..3
ok 1 - test_config [unit] 142ms
not ok 2 - test_paths [unit]
  ---
  duration_ms: 89
  failures:
    - line: 42
      function: "test_xdg_compliance"
      message: "Expected /home/user/.config/kgsm to exist"
      file: "tests/unit/test_paths.sh"
      expected: "directory exists"
      actual: "directory missing"
  ...
ok 3 - test_lifecycle [integration] # SKIP not implemented
```

Key format details:
- The TAP result line pattern is: `(ok|not ok) N - {name} [{type}]{rest}`
- Duration for passing tests is in `{rest}` as `Nms` (e.g., `142ms`).
- Skip tests have `# SKIP` in `{rest}`.
- Failing tests are followed by a YAML block between `---` and `...`.

### YAML Diagnostic Block Schema

```yaml
  ---
  duration_ms: 456
  failures:
    - line: 42
      function: "test_function_name"
      message: "human readable failure reason"
      file: "tests/unit/test_file.sh"
      expected: "expected value"
      actual: "actual value"
    - line: 67
      function: "another_function"
      message: "another failure"
      file: "tests/unit/test_file.sh"
  ...
```

Fields parsed per failure entry:

| Field      | Required                 | Description                                       |
| ---------- | ------------------------ | ------------------------------------------------- |
| `line`     | Yes (starts a new entry) | 1-based line number in the test file              |
| `function` | No                       | Name of the bash function that failed             |
| `message`  | No                       | Human-readable failure description                |
| `file`     | No                       | Relative path to the test file                    |
| `expected` | No                       | Expected value (shown in Test Explorer diff view) |
| `actual`   | No                       | Actual value (shown in Test Explorer diff view)   |

A top-level `message` field (outside the `failures` block) is also accepted and stored in `currentResult.message`.

### State Machine

```
INITIAL
  │
  ├─ "TAP version" / "1..N" ──► skip line (stay in INITIAL)
  │
  ├─ "ok N - name [type] rest" ──► emit pass/skip immediately ──► INITIAL
  │
  ├─ "not ok N - name [type]" ──► hold in currentResult ──► AWAITING_YAML
  │
  └─ any other line (no current result) ──► ignore

AWAITING_YAML
  │
  ├─ "---" ──► YAML_BLOCK
  │
  └─ any other line ──► emit pending "fail" without YAML ──► process line in INITIAL

YAML_BLOCK
  │
  ├─ "  ..." ──► _parseYamlBlock() ──► emit result ──► INITIAL
  │
  └─ any other line ──► accumulate in yamlLines
```

`flush()` is called after `runCommand` resolves to emit any result still in `currentResult` (handles the case where the stream ends without a trailing newline after the last YAML close marker).

### YAML Parsing Limitations

The YAML parser is **not a real YAML parser** — it matches each line against a fixed set of regex patterns. This has several implications:

1. **Values with embedded quotes** — patterns like `failMsg = yl.match(/^\s+message:\s+"(.+)"$/)` assume the value is double-quoted with no escaped quotes inside. A message like `Failed: "foo" != "bar"` will not parse correctly (the regex will still match the outer quotes, but the captured value will include internal quotes as-is — this is actually fine since `(.+)` is greedy).
2. **Multi-line values** are not supported. A `message` value split across lines will only capture the first line.
3. **Indentation is flexible** (`\s+`) but the structure is positional — `- line: N` must appear before `function`, `message`, etc. to correctly open a new failure entry. A `function` field before any `- line:` will be silently ignored.
4. **Unknown fields** are silently skipped.

---

## Test Debugging (`debugTests`)

The debug profile requires the **`rogalmic.bash-debug`** VS Code extension to be installed. Without it, `vscode.debug.startDebugging()` returns `false` and the extension shows an error message.

Debugging is only meaningful at the **function or file level** — if a type group is selected, a warning is shown and the debug session is not started.

The debug configuration sent to VS Code:

```js
{
  type: "bashdb",
  request: "launch",
  name: `Debug: ${debugLabel}`,
  program: path.join(workspaceRoot, "tests/run.sh"),
  args: ["--debug-run", testFilePath, "--function", functionName],
  cwd: workspaceRoot,
  terminalKind: "integrated",
  env: { NO_COLOR: "1" }
}
```

- `--debug-run <file>` is passed as the first argument to `tests/run.sh`, telling it to run in debug mode for that specific file.
- `--function <name>` is appended only when a function-level item was selected.
- `NO_COLOR: "1"` prevents ANSI escape codes from interfering with bashdb's output.

The `item.parent` property of a function-level `TestItem` is used to resolve the parent file path. If `item.parent` is not set (possible depending on VS Code version), `findTestItem(parentId)` is used as a fallback.

---

## Function Range Updates (`updateFunctionRanges`)

Called on every `onDidSaveTextDocument` event for `.sh` files inside `tests/`. It:

1. Reads the full document text.
2. Scans for `^function test_\w+` with a global multiline regex.
3. For each test function item in the tree whose `uri` matches the saved document, re-computes the line using `doc.positionAt(match.index).line` and updates `fnItem.range`.

This keeps the gutter run/debug icons aligned with the correct line numbers after lines are added or removed above a function definition.

**Important:** This function only updates existing `fnItem.range` values — it does **not** add or remove function items from the tree. New or deleted test functions only appear after a full `discoverTests()` call (triggered by file-system watcher on create/delete, not on content change).

---

## CodeLens Provider (`KgsmTestCodeLensProvider`)

Implements `vscode.CodeLensProvider` for shell scripts matching `tests/{unit,integration,e2e}/test_*.sh`.

For each document, `provideCodeLenses(document)`:

1. Walks the test item tree to find the `TestItem` whose `uri.fsPath` matches the current document. If not found (tests not yet discovered), returns an empty array — **no CodeLenses appear until discovery has run at least once**.
2. Scans the document text for `^function test_\w+` with a global multiline regex.
3. For each match, emits two `CodeLens` items at the function line:
   - **"Run"** — triggers `kgsm.runTestFunction` with `[parentTestItem.id, "${parentTestItem.id}::${fnName}"]`
   - **"Debug"** — triggers `kgsm.debugTestFunction` with the same arguments

These commands look up the function-level `TestItem` by ID and create a targeted `TestRunRequest`.

---

## `runCommand` Helper

```js
function runCommand(cmd, args, token, logToChannel = false, onLine = null)
```

Spawns a child process using `spawn` (not `execFile`). Key characteristics:

- **Environment**: inherits `process.env` and adds `NO_COLOR: "1"` to prevent ANSI escape codes from corrupting TAP output or JSON discovery.
- **Working directory**: always `workspaceRoot`.
- **Streaming**: when `onLine` is provided, incoming stdout chunks are split on `\n`. All complete lines are passed to `onLine` immediately. The last partial line is buffered and flushed on process close.
- **stderr**: written to `outputChannel` only if `logToChannel` is `true`. This is enabled during test runs but not during discovery.
- **Cancellation**: if `token` is provided and a cancellation is requested, the process is killed (`proc.kill()`) and the promise resolves with `null`.
- **Errors**: spawn errors (e.g., script not found, permission denied) show an error message and resolve with `null`.
- **Return value**: resolves with the full concatenated stdout string, or `null` on error/cancellation.

`runCommand` is called in two modes:

| Caller            | `logToChannel` | `onLine`         | Purpose                                |
| ----------------- | -------------- | ---------------- | -------------------------------------- |
| `discoverTests()` | `false`        | `null`           | Collect full JSON, no streaming needed |
| `runTests()`      | `true`         | `parser.addLine` | Stream TAP lines incrementally         |

---

## `findTestItem` Helper

```js
function findTestItem(id)
```

O(n) linear search through `controller.items` (type groups) and their children (test file items). Returns the matching `TestItem` or `null`. This does **not** search function-level items (grandchildren).

Used as a fallback when `item.parent` is not set on a function-level `TestItem`.

---

## Module-Level Globals

Three module-level variables are used throughout:

| Variable        | Type                    | Description                                                        |
| --------------- | ----------------------- | ------------------------------------------------------------------ |
| `controller`    | `vscode.TestController` | The single test controller. Registered on `context.subscriptions`. |
| `workspaceRoot` | `string`                | `workspaceFolders[0].uri.fsPath`. Fixed at activation time.        |
| `outputChannel` | `vscode.OutputChannel`  | "KGSM Tests" channel. Used for stderr from test runs.              |

Unlike the `kgsm-extension`, there is no module-level timer. All resources are on `context.subscriptions` and `deactivate()` is empty.

---

## Critical Considerations

### 1. Only the First Workspace Folder Is Used

`workspaceRoot` is always `folders[0].uri.fsPath`. Multi-root workspaces (where KGSM is not the first folder) will point to the wrong directory for all child process invocations.

### 2. `tests/run.sh` Must Support `--list-json`

Discovery is entirely dependent on `tests/run.sh --list-json` returning valid JSON. If the script does not implement this flag, `discoverTests()` silently returns with no tests shown. There is no user-visible error for a non-zero exit code from the discovery command — only a JSON parse failure produces a notification.

### 3. TAP Line Format Is Rigid

`TapStreamParser` matches result lines with the regex:

```
/^(ok|not ok)\s+\d+\s+-\s+(\S+)\s+\[(\w+)\](.*)$/
```

This requires:
- The test name to be a single non-whitespace token (`\S+`).
- The type to be in square brackets immediately after the name.
- No variation in the separator format.

If `tests/run.sh` changes its TAP output format (e.g., adds spaces in test names, changes the bracket format, or switches to a different TAP version), the parser will fail to match lines and tests will be reported as `"Test did not produce TAP output"`.

### 4. `expected` and `actual` in YAML Are Strings Only

The YAML parser captures `expected` and `actual` as whatever is between the double quotes on that line. They are passed to `vscode.TestMessage.expectedOutput` and `actualOutput` as plain strings. VS Code's diff view requires both to be set for the diff to appear — if only one is present in the YAML, both must be populated or neither will show.

### 5. CodeLenses Require Prior Discovery

`KgsmTestCodeLensProvider.provideCodeLenses()` returns early if the file is not found in `controller.items`. This means CodeLenses are invisible until the user opens the Test Explorer panel (triggering `discoverTests()`) or refreshes it manually. There is no fallback that discovers tests on document open.

### 6. `item.parent` Is Not Guaranteed

When a function-level `TestItem` is passed to `debugTests` or processed in `runTests`, the code does:

```js
const parentItem = item.parent || findTestItem(parentId);
```

The `parent` property on `vscode.TestItem` is available in VS Code ≥ 1.87. For older versions (the extension requires only `^1.80.0`), `item.parent` will be `undefined` and `findTestItem` is the fallback. If `findTestItem` also returns `null` (item not in tree), the debug session will not start and an error is shown.

### 7. Pattern Limit of 58 Is a Magic Number

The threshold `names.length < 58` that suppresses the `--pattern` argument has no documentation or configuration. It exists to avoid an argument list that may exceed shell limits, but the number is arbitrary. For workspaces with 57 test files targeted selectively, the pattern is still sent; with 58, all tests run.

### 8. `NO_COLOR=1` Is Mandatory

Both discovery and execution set `NO_COLOR: "1"` in the child process environment. The KGSM testing framework and `kgsm.sh` emit ANSI color codes by default. Without this override, color escape sequences in the JSON output would cause `JSON.parse` to fail, and escape sequences in TAP output would break the regex matching in `TapStreamParser`.

### 9. File Watcher Only Detects Create and Delete

The `FileSystemWatcher` wired to `discoverTests()` only fires on `onDidCreate` and `onDidDelete`. The `onDidChange` handler is an explicit no-op. This is intentional — content changes are handled by `updateFunctionRanges()` which only adjusts line numbers without a full rediscovery. However, if a test function is **renamed or added** without also creating/deleting a file, the tree will be stale until the user clicks Refresh.

### 10. `updateFunctionRanges` Only Affects Existing Items

Adding a new `test_*` function to an existing test file will not add a new function item to the tree. Removing one will not remove it. Only a full `discoverTests()` call reconciles the tree with the actual file contents. Users who add new test functions should manually refresh the Test Explorer.

### 11. Type Groups Are Always Recreated

`discoverTests()` deletes all items and rebuilds the entire tree on every call. There is no incremental update. For large test suites, this may cause a brief flicker in the Test Explorer as items disappear and reappear.

### 12. Debug Requires `rogalmic.bash-debug`

The `bashdb` debug type is provided by the `rogalmic.bash-debug` marketplace extension. It is not listed as a dependency in `package.json` (`extensionDependencies` is absent). If it is not installed, `vscode.debug.startDebugging()` returns `false` and the error message directs the user to install it — but VS Code will not prompt automatically.
