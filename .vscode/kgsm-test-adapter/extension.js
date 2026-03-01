// KGSM Test Adapter - VS Code Extension
// Integrates KGSM's bash testing framework with VS Code's native Testing API.
// Discovers tests via `tests/run.sh --list-json` and runs them via `tests/run.sh` (TAP output).

const vscode = require("vscode");
const { spawn } = require("child_process");
const path = require("path");

/** @type {vscode.TestController} */
let controller;

/** @type {string} */
let workspaceRoot;

/** @type {vscode.OutputChannel} */
let outputChannel;

function activate(context) {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) return;

  workspaceRoot = folders[0].uri.fsPath;

  controller = vscode.tests.createTestController("kgsm", "KGSM Tests");
  context.subscriptions.push(controller);

  // Discover tests when the panel is opened
  controller.resolveHandler = async (item) => {
    if (!item) {
      await discoverTests();
    }
  };

  // Refresh button
  controller.refreshHandler = async () => {
    await discoverTests();
  };

  // Run profile
  controller.createRunProfile(
    "Run",
    vscode.TestRunProfileKind.Run,
    runTests,
    true
  );

  // Debug profile (uses rogalmic.bash-debug / bashdb)
  controller.createRunProfile(
    "Debug",
    vscode.TestRunProfileKind.Debug,
    debugTests,
    false
  );

  // Watch for test file changes
  const watcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(workspaceRoot, "tests/{unit,integration,e2e}/test_*.sh")
  );
  watcher.onDidCreate(() => discoverTests());
  watcher.onDidDelete(() => discoverTests());
  watcher.onDidChange(() => {}); // Content changes handled by document watcher below
  context.subscriptions.push(watcher);

  // Update function ranges when test files are edited (line shifts)
  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument((doc) => {
      if (doc.uri.fsPath.includes("/tests/") && doc.uri.fsPath.endsWith(".sh")) {
        updateFunctionRanges(doc);
      }
    })
  );

  // Output channel for full logs
  outputChannel = vscode.window.createOutputChannel("KGSM Tests");
  context.subscriptions.push(outputChannel);

  // CodeLens provider
  const codeLensSelector = {
    language: "shellscript",
    pattern: new vscode.RelativePattern(workspaceRoot, "tests/{unit,integration,e2e}/test_*.sh"),
  };
  context.subscriptions.push(
    vscode.languages.registerCodeLensProvider(codeLensSelector, new KgsmTestCodeLensProvider())
  );

  // Command triggered by Run CodeLens click
  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.runTestFunction", async (testId, fnId) => {
      const testItem = findTestItem(testId);
      if (!testItem) return;
      let fnItem = null;
      testItem.children.forEach((child) => {
        if (child.id === fnId) fnItem = child;
      });
      if (!fnItem) return;

      const request = new vscode.TestRunRequest([fnItem]);
      await runTests(request);
    })
  );

  // Command triggered by Debug CodeLens click
  context.subscriptions.push(
    vscode.commands.registerCommand("kgsm.debugTestFunction", async (testId, fnId) => {
      const testItem = findTestItem(testId);
      if (!testItem) return;
      let fnItem = null;
      testItem.children.forEach((child) => {
        if (child.id === fnId) fnItem = child;
      });
      if (!fnItem) return;

      const request = new vscode.TestRunRequest([fnItem]);
      await debugTests(request);
    })
  );
}

// ---------------------------------------------------------------------------
// Test Discovery
// ---------------------------------------------------------------------------

async function discoverTests() {
  // Clear existing items
  controller.items.forEach((item) => controller.items.delete(item.id));

  const json = await runCommand(
    path.join(workspaceRoot, "tests/run.sh"),
    ["--list-json"]
  );

  if (!json) return;

  let tests;
  try {
    tests = JSON.parse(json);
  } catch {
    vscode.window.showErrorMessage("KGSM: Failed to parse test list JSON");
    return;
  }

  // Group by type
  const groups = {};
  for (const t of tests) {
    if (!groups[t.type]) groups[t.type] = [];
    groups[t.type].push(t);
  }

  for (const [type, items] of Object.entries(groups)) {
    const groupItem = controller.createTestItem(type, type, undefined);
    controller.items.add(groupItem);

    for (const t of items) {
      const fileUri = vscode.Uri.file(path.join(workspaceRoot, t.file));
      const testItem = controller.createTestItem(t.name, t.name, fileUri);
      testItem.tags = [new vscode.TestTag(type)];

      // Add per-function children if available
      if (t.functions && t.functions.length > 0) {
        for (const fn of t.functions) {
          const fnName = typeof fn === "object" ? fn.name : fn;
          const fnLine = typeof fn === "object" ? fn.line : undefined;

          const fnItem = controller.createTestItem(
            `${t.name}::${fnName}`,
            fnName,
            fileUri
          );
          fnItem.tags = [new vscode.TestTag(type)];

          // Set range to the function definition line for gutter icons
          if (fnLine !== undefined && fnLine > 0) {
            fnItem.range = new vscode.Range(
              new vscode.Position(fnLine - 1, 0),
              new vscode.Position(fnLine - 1, 0)
            );
          }

          testItem.children.add(fnItem);
        }

        // Set file-level item range to the first function
        const firstLine =
          typeof t.functions[0] === "object" ? t.functions[0].line : undefined;
        if (firstLine !== undefined && firstLine > 0) {
          testItem.range = new vscode.Range(
            new vscode.Position(0, 0),
            new vscode.Position(0, 0)
          );
        }
      }

      groupItem.children.add(testItem);
    }
  }
}

// ---------------------------------------------------------------------------
// Range Updates (keeps gutter icons aligned after edits)
// ---------------------------------------------------------------------------

function updateFunctionRanges(doc) {
  const text = doc.getText();
  const funcPattern = /^function (test_\w+)/gm;

  // Find all test items associated with this file
  controller.items.forEach((group) => {
    group.children.forEach((testItem) => {
      if (testItem.uri?.fsPath !== doc.uri.fsPath) return;

      testItem.children.forEach((fnItem) => {
        const fnName = fnItem.label;
        // Find the current line for this function in the document
        const regex = new RegExp(`^function ${fnName}\\b`, "m");
        const match = regex.exec(text);
        if (match) {
          const line = doc.positionAt(match.index).line;
          fnItem.range = new vscode.Range(
            new vscode.Position(line, 0),
            new vscode.Position(line, 0)
          );
        }
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Test Execution
// ---------------------------------------------------------------------------

async function runTests(request, token) {
  const run = controller.createTestRun(request);

  // Collect tests to run (file-level items for execution)
  const testsToRun = [];
  const functionItems = new Map(); // parentId -> [fnItem, ...]

  if (request.include) {
    for (const item of request.include) {
      // Function-level item: id contains "::" (e.g., "test_paths::test_xdg_compliance")
      if (item.id.includes("::")) {
        const parentId = item.id.split("::")[0];
        // Find or add the parent file-level item
        let parentItem = testsToRun.find((t) => t.id === parentId);
        if (!parentItem) {
          // Walk up to find the parent TestItem
          parentItem = item.parent || findTestItem(parentId);
          if (parentItem) testsToRun.push(parentItem);
        }
        if (!functionItems.has(parentId)) functionItems.set(parentId, []);
        functionItems.get(parentId).push(item);
      } else if (item.children.size > 0 && !item.uri) {
        // Type group (no uri) — collect its file-level children
        item.children.forEach((child) => testsToRun.push(child));
      } else {
        // File-level item or type with uri
        testsToRun.push(item);
      }
    }
  } else {
    // Run all
    controller.items.forEach((group) => {
      group.children.forEach((child) => testsToRun.push(child));
    });
  }

  // Determine which function items were explicitly requested
  const requestedFnIds = new Set();
  for (const fns of functionItems.values()) {
    for (const fn of fns) requestedFnIds.add(fn.id);
  }

  // Mark as queued (only requested functions, not all children)
  for (const t of testsToRun) {
    run.enqueued(t);
    t.children.forEach((fn) => {
      if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
        run.enqueued(fn);
      }
    });
  }

  // Build patterns and determine types
  const names = testsToRun.map((t) => t.id);
  const types = [...new Set(testsToRun.map((t) => t.parent?.id).filter(Boolean))];

  // Check if we're running a single function from a single test file
  const isSingleFunction =
    testsToRun.length === 1 &&
    functionItems.size === 1 &&
    functionItems.get(testsToRun[0].id)?.length === 1;

  // Build args — TAP is now the default output format
  const args = [];
  if (names.length < 58) {
    // Only add pattern filter if not running all tests
    args.push("--pattern", names.join("|"));
  }
  if (isSingleFunction) {
    const fnName = functionItems.get(testsToRun[0].id)[0].label;
    args.push("--function", fnName);
  }
  args.push(...types);

  // Mark as started
  for (const t of testsToRun) {
    run.started(t);
    t.children.forEach((fn) => {
      if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
        run.started(fn);
      }
    });
  }

  // Run and parse TAP incrementally — update Test Explorer as each test completes
  const testMap = new Map(testsToRun.map((t) => [t.id, t]));
  const emittedTests = new Set();
  let hasFailures = false;
  let bailedOut = false;

  const parser = new TapStreamParser((r) => {
    // Handle Bail out!
    if (r.status === "bail") {
      bailedOut = true;
      // Mark all remaining tests as errored
      for (const t of testsToRun) {
        if (!emittedTests.has(t.id)) {
          emittedTests.add(t.id);
          const bailMsg = new vscode.TestMessage(`Bail out! ${r.message}`);
          run.errored(t, bailMsg);
          t.children.forEach((fn) => {
            if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
              run.errored(fn, bailMsg);
            }
          });
        }
      }
      return;
    }

    emittedTests.add(r.name);
    const testItem = testMap.get(r.name);
    if (!testItem) return;

    // Build subtest lookup for per-function mapping
    const subtestMap = new Map();
    if (r.subtests && r.subtests.length > 0) {
      for (const sub of r.subtests) {
        subtestMap.set(sub.name, sub);
      }
    }

    if (r.status === "pass") {
      run.passed(testItem, r.duration);
      testItem.children.forEach((fn) => {
        if (requestedFnIds.size > 0 && !requestedFnIds.has(fn.id)) return;
        const sub = subtestMap.get(fn.label);
        if (sub) {
          if (sub.status === "skip") {
            run.skipped(fn);
            if (sub.reason) {
              run.appendOutput(`SKIP: ${sub.reason}\r\n`, undefined, fn);
            }
          } else {
            run.passed(fn, r.duration);
          }
        } else {
          run.passed(fn, r.duration);
        }
      });
    } else if (r.status === "skip") {
      run.skipped(testItem);
      if (r.skipReason) {
        run.appendOutput(`SKIP: ${r.skipReason}\r\n`, undefined, testItem);
      }
      testItem.children.forEach((fn) => {
        if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
          run.skipped(fn);
        }
      });
    } else if (r.status === "todo") {
      // TODO tests: not a real failure — mark as skipped with reason
      run.skipped(testItem);
      const reason = r.todoReason || "TODO";
      run.appendOutput(`TODO: ${reason}\r\n`, undefined, testItem);
      testItem.children.forEach((fn) => {
        if (requestedFnIds.size > 0 && !requestedFnIds.has(fn.id)) return;
        const sub = subtestMap.get(fn.label);
        if (sub && sub.status === "todo") {
          run.skipped(fn);
          run.appendOutput(`TODO: ${sub.reason || reason}\r\n`, undefined, fn);
        } else if (sub && sub.status === "skip") {
          run.skipped(fn);
        } else {
          run.skipped(fn);
        }
      });
    } else {
      hasFailures = true;
      const messages = [];
      const failedFunctions = new Set();

      if (r.failures && r.failures.length > 0) {
        for (const f of r.failures) {
          const msg = new vscode.TestMessage(
            `${f.function}(): ${f.message}`
          );
          if (f.expected !== undefined) msg.expectedOutput = f.expected;
          if (f.actual !== undefined) msg.actualOutput = f.actual;
          const filePath = f.file || (testItem.uri ? undefined : null);
          const uri = filePath
            ? vscode.Uri.file(path.join(workspaceRoot, filePath))
            : testItem.uri;
          if (uri && f.line > 0) {
            msg.location = new vscode.Location(
              uri,
              new vscode.Position(f.line - 1, 0)
            );
          }
          messages.push(msg);
          if (f.function) failedFunctions.add(f.function);
        }
      } else {
        const msg = new vscode.TestMessage(r.message || "Test failed");
        if (testItem.uri) {
          msg.location = new vscode.Location(
            testItem.uri,
            new vscode.Position(0, 0)
          );
        }
        messages.push(msg);
      }

      run.failed(testItem, messages, r.duration);

      // Per-function results: prefer subtests over YAML inference
      testItem.children.forEach((fn) => {
        if (requestedFnIds.size > 0 && !requestedFnIds.has(fn.id)) return;
        const fnName = fn.label;
        const sub = subtestMap.get(fnName);

        if (sub) {
          // Use subtest result
          if (sub.status === "pass") {
            run.passed(fn, r.duration);
          } else if (sub.status === "skip") {
            run.skipped(fn);
            if (sub.reason) {
              run.appendOutput(`SKIP: ${sub.reason}\r\n`, undefined, fn);
            }
          } else if (sub.status === "todo") {
            run.skipped(fn);
            run.appendOutput(`TODO: ${sub.reason || "TODO"}\r\n`, undefined, fn);
          } else {
            // Failed — find matching failure messages
            const fnMsgs = messages.filter((m) =>
              m.message?.toString().startsWith(`${fnName}()`)
            );
            run.failed(fn, fnMsgs.length > 0 ? fnMsgs : messages, r.duration);
          }
        } else if (failedFunctions.has(fnName)) {
          // Fallback: YAML inference
          const fnMsgs = messages.filter((m) =>
            m.message?.toString().startsWith(`${fnName}()`)
          );
          run.failed(fn, fnMsgs.length > 0 ? fnMsgs : messages, r.duration);
        } else {
          run.passed(fn, r.duration);
        }
      });

      outputChannel.show(true);
    }
  });

  const tapOutput = await runCommand(
    path.join(workspaceRoot, "tests/run.sh"),
    args,
    token,
    true,
    (line) => parser.addLine(line)
  );

  if (tapOutput === null) {
    // Cancelled or error
    for (const t of testsToRun) {
      if (!emittedTests.has(t.id)) {
        run.skipped(t);
        t.children.forEach((fn) => {
          if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
            run.skipped(fn);
          }
        });
      }
    }
    run.end();
    return;
  }

  // Flush any remaining buffered result
  parser.flush();

  // Any tests not in results — mark as errored
  for (const t of testsToRun) {
    if (!emittedTests.has(t.id)) {
      run.errored(t, new vscode.TestMessage("Test did not produce TAP output"));
      t.children.forEach((fn) => {
        if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
          run.errored(fn, new vscode.TestMessage("Test did not produce TAP output"));
        }
      });
    }
  }

  run.end();
}

// ---------------------------------------------------------------------------
// Test Debugging (launches bashdb via rogalmic.bash-debug)
// ---------------------------------------------------------------------------

async function debugTests(request) {
  // Collect what to debug — only a single test function is meaningful
  let testFilePath = "";
  let functionName = "";
  let debugLabel = "";

  if (request.include && request.include.length > 0) {
    const item = request.include[0];

    if (item.id.includes("::")) {
      // Function-level: "test_config::test_parse_key"
      functionName = item.label;
      const parentId = item.id.split("::")[0];
      const parentItem = item.parent || findTestItem(parentId);
      if (parentItem && parentItem.uri) {
        testFilePath = parentItem.uri.fsPath;
      }
      debugLabel = `${parentId}::${functionName}`;
    } else if (item.uri) {
      // File-level item
      testFilePath = item.uri.fsPath;
      debugLabel = item.id;
    } else {
      // Group-level — can't debug an entire group
      vscode.window.showWarningMessage(
        "KGSM: Select a specific test file or function to debug"
      );
      return;
    }
  } else {
    vscode.window.showWarningMessage(
      "KGSM: Select a specific test to debug"
    );
    return;
  }

  if (!testFilePath) {
    vscode.window.showErrorMessage("KGSM: Could not determine test file path");
    return;
  }

  // Build args for the debug wrapper
  const debugArgs = ["--debug-run", testFilePath];
  if (functionName) {
    debugArgs.push("--function", functionName);
  }

  // Launch a bashdb debug session
  const debugConfig = {
    type: "bashdb",
    request: "launch",
    name: `Debug: ${debugLabel}`,
    program: path.join(workspaceRoot, "tests/run.sh"),
    args: debugArgs,
    cwd: workspaceRoot,
    terminalKind: "integrated",
    env: {
      NO_COLOR: "1",
    },
  };

  const started = await vscode.debug.startDebugging(
    vscode.workspace.workspaceFolders[0],
    debugConfig
  );

  if (!started) {
    vscode.window.showErrorMessage(
      "KGSM: Failed to start debug session."
    );
  }
}

// ---------------------------------------------------------------------------
// TAP Parser
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Streaming TAP v14 Parser
// ---------------------------------------------------------------------------
// Parses TAP output line-by-line, emitting results via callback as each test
// (including multi-line YAML diagnostic blocks) completes.

class TapStreamParser {
  constructor(onResult) {
    this.onResult = onResult;
    this.currentResult = null;
    this.inYaml = false;
    this.yamlLines = [];
    this.inSubtest = false;
    this.subtestResults = [];
    this.subtestName = null;
  }

  addLine(line) {
    // TAP header lines — skip
    if (line.match(/^TAP version/) || line.match(/^1\.\.\d+/)) return;

    // Bail out! — immediately emit and signal abort
    const bailMatch = line.match(/^Bail out!\s*(.*)$/);
    if (bailMatch) {
      this._emitCurrent();
      if (this.onResult) {
        this.onResult({
          name: "__bail_out__",
          status: "bail",
          message: bailMatch[1] || "Test run aborted",
          duration: undefined,
          failures: [],
          subtests: [],
        });
      }
      return;
    }

    // Inside a YAML diagnostic block
    if (this.inYaml) {
      if (line.trim() === "...") {
        this._parseYamlBlock();
        this.inYaml = false;
        this._emitCurrent();
      } else {
        this.yamlLines.push(line);
      }
      return;
    }

    // Inside a subtest block (4-space indented lines)
    if (this.inSubtest) {
      // Indented subtest plan line (e.g., "    1..3")
      if (line.match(/^\s{4}1\.\.\d+/)) return;

      // Indented TAP result line
      const subMatch = line.match(
        /^\s{4}(ok|not ok)\s+\d+\s+-\s+(\S+)(.*)$/
      );
      if (subMatch) {
        const [, subStatus, subName, subRest] = subMatch;
        const subResult = { name: subName, status: "pass" };

        if (subStatus === "ok") {
          const skipMatch = subRest.match(/# SKIP\s*(.*)/i);
          const todoMatch = subRest.match(/# TODO\s*(.*)/i);
          if (skipMatch) {
            subResult.status = "skip";
            subResult.reason = skipMatch[1] || "";
          } else if (todoMatch) {
            subResult.status = "todo";
            subResult.reason = todoMatch[1] || "";
          }
        } else {
          const todoMatch = subRest.match(/# TODO\s*(.*)/i);
          if (todoMatch) {
            subResult.status = "todo";
            subResult.reason = todoMatch[1] || "";
          } else {
            subResult.status = "fail";
          }
        }

        this.subtestResults.push(subResult);
        return;
      }

      // Non-indented line — end of subtest, process as parent line
      this.inSubtest = false;
      // Fall through to process the line as a normal TAP line
    }

    // Subtest header comment (e.g., "# Subtest: test_config")
    const subtestHeader = line.match(/^# Subtest:\s+(\S+)/);
    if (subtestHeader) {
      this.subtestName = subtestHeader[1];
      this.inSubtest = true;
      this.subtestResults = [];
      return;
    }

    // Match: ok N - test_name [type] # comment
    // Match: not ok N - test_name [type]
    const match = line.match(
      /^(ok|not ok)\s+\d+\s+-\s+(\S+)\s+\[(\w+)\](.*)$/
    );

    if (match) {
      // Emit any previous result that had no YAML block
      this._emitCurrent();

      const [, status, name, , rest] = match;
      this.currentResult = {
        name,
        status: "fail",
        message: "",
        duration: undefined,
        failures: [],
        subtests: this.subtestResults.length > 0 ? [...this.subtestResults] : [],
      };
      // Reset subtest state
      this.subtestResults = [];
      this.subtestName = null;

      if (status === "ok") {
        const todoMatch = rest.match(/# TODO\s*(.*)/i);
        if (rest.includes("# SKIP")) {
          this.currentResult.status = "skip";
          const skipReasonMatch = rest.match(/# SKIP\s*(.*)/i);
          if (skipReasonMatch) {
            this.currentResult.skipReason = skipReasonMatch[1] || "";
          }
        } else if (todoMatch) {
          this.currentResult.status = "todo";
          this.currentResult.todoReason = todoMatch[1] || "";
        } else {
          this.currentResult.status = "pass";
          const durMatch = rest.match(/(\d+)ms/);
          if (durMatch)
            this.currentResult.duration = parseInt(durMatch[1], 10);
        }
        // Passing/skip/todo tests have no YAML block — emit immediately
        this._emitCurrent();
      } else {
        // "not ok" — check for TODO directive
        const todoMatch = rest.match(/# TODO\s*(.*)/i);
        if (todoMatch) {
          this.currentResult.status = "todo";
          this.currentResult.todoReason = todoMatch[1] || "";
          this._emitCurrent();
        } else {
          // May be followed by YAML block on next line(s)
          this.currentResult.status = "fail";
        }
      }
      return;
    }

    // Start of YAML block (must follow a "not ok" line)
    if (line.trim() === "---" && this.currentResult) {
      this.inYaml = true;
      this.yamlLines = [];
      return;
    }

    // If we have a pending "not ok" with no YAML block and hit a non-YAML line,
    // emit it as-is
    if (
      this.currentResult &&
      this.currentResult.status === "fail" &&
      !this.inYaml
    ) {
      this._emitCurrent();
    }
  }

  flush() {
    this._emitCurrent();
  }

  _emitCurrent() {
    if (this.currentResult) {
      const r = this.currentResult;
      this.currentResult = null;
      if (this.onResult) this.onResult(r);
    }
  }

  _parseYamlBlock() {
    if (!this.currentResult) return;

    let currentFailure = null;
    for (const yl of this.yamlLines) {
      const durMatch = yl.match(/^\s+duration_ms:\s+(\d+)$/);
      const failStart = yl.match(/^\s+failures:\s*$/);
      const failLine = yl.match(/^\s+- line:\s+(\d+)$/);
      const failFunc = yl.match(/^\s+function:\s+"(.+)"$/);
      const failMsg = yl.match(/^\s+message:\s+"(.+)"$/);
      const failFile = yl.match(/^\s+file:\s+"(.+)"$/);
      const failExpected = yl.match(/^\s+expected:\s+"(.+)"$/);
      const failActual = yl.match(/^\s+actual:\s+"(.+)"$/);

      if (failStart) {
        continue;
      } else if (failLine) {
        if (currentFailure) this.currentResult.failures.push(currentFailure);
        currentFailure = {
          line: parseInt(failLine[1], 10),
          function: "",
          message: "",
          file: "",
        };
      } else if (currentFailure && failFunc) {
        currentFailure.function = failFunc[1];
      } else if (currentFailure && failMsg) {
        currentFailure.message = failMsg[1];
      } else if (currentFailure && failFile) {
        currentFailure.file = failFile[1];
      } else if (currentFailure && failExpected) {
        currentFailure.expected = failExpected[1];
      } else if (currentFailure && failActual) {
        currentFailure.actual = failActual[1];
      } else if (failMsg && !currentFailure) {
        this.currentResult.message = failMsg[1];
      } else if (durMatch) {
        this.currentResult.duration = parseInt(durMatch[1], 10);
      }
    }
    if (currentFailure) this.currentResult.failures.push(currentFailure);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function findTestItem(id) {
  let found = null;
  controller.items.forEach((group) => {
    group.children.forEach((child) => {
      if (child.id === id) found = child;
    });
  });
  return found;
}

function runCommand(cmd, args, token, logToChannel = false, onLine = null) {
  return new Promise((resolve) => {
    const proc = spawn(cmd, args, {
      cwd: workspaceRoot,
      env: { ...process.env, NO_COLOR: "1" },
    });

    let stdout = "";
    let lineBuffer = "";

    proc.stdout.on("data", (data) => {
      const chunk = data.toString();
      stdout += chunk;

      if (onLine) {
        lineBuffer += chunk;
        const lines = lineBuffer.split("\n");
        // All but last element are complete lines
        for (let i = 0; i < lines.length - 1; i++) {
          onLine(lines[i]);
        }
        lineBuffer = lines[lines.length - 1];
      }
    });

    proc.stderr.on("data", (data) => {
      if (logToChannel && outputChannel) {
        outputChannel.append(data.toString());
      }
    });

    proc.on("close", () => {
      if (onLine && lineBuffer) {
        onLine(lineBuffer);
      }
      resolve(stdout);
    });
    proc.on("error", (err) => {
      vscode.window.showErrorMessage(`KGSM: ${err.message}`);
      resolve(null);
    });

    if (token) {
      token.onCancellationRequested(() => {
        proc.kill();
        resolve(null);
      });
    }
  });
}

// ---------------------------------------------------------------------------
// CodeLens Provider — "▶ Run Test" above each test function
// ---------------------------------------------------------------------------

class KgsmTestCodeLensProvider {
  provideCodeLenses(document) {
    const lenses = [];
    const text = document.getText();
    const funcPattern = /^function (test_\w+)/gm;

    // Find the parent test item for this file
    let parentTestItem = null;
    controller.items.forEach((group) => {
      group.children.forEach((testItem) => {
        if (testItem.uri?.fsPath === document.uri.fsPath) {
          parentTestItem = testItem;
        }
      });
    });
    if (!parentTestItem) return lenses;

    let match;
    while ((match = funcPattern.exec(text)) !== null) {
      const fnName = match[1];
      const pos = document.positionAt(match.index);
      const range = new vscode.Range(pos, pos);

      lenses.push(
        new vscode.CodeLens(range, {
          title: "Run",
          command: "kgsm.runTestFunction",
          arguments: [parentTestItem.id, `${parentTestItem.id}::${fnName}`],
        })
      );

      lenses.push(
        new vscode.CodeLens(range, {
          title: "Debug",
          command: "kgsm.debugTestFunction",
          arguments: [parentTestItem.id, `${parentTestItem.id}::${fnName}`],
        })
      );
    }

    return lenses;
  }
}

function deactivate() {}

module.exports = { activate, deactivate };
