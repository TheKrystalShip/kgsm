// KGSM Test Adapter - VS Code Extension
// Integrates KGSM's bash testing framework with VS Code's native Testing API.
// Discovers tests via `tests/run.sh --list-json` and runs them via `tests/run.sh --tap`.

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
  const funcPattern = /^function (test_\w+|setup_test)/gm;

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

  // Build args
  const args = ["--tap"];
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

  // Run and parse TAP
  const tapOutput = await runCommand(
    path.join(workspaceRoot, "tests/run.sh"),
    args,
    token,
    true
  );

  if (tapOutput === null) {
    // Cancelled or error
    for (const t of testsToRun) {
      run.skipped(t);
      t.children.forEach((fn) => {
        if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
          run.skipped(fn);
        }
      });
    }
    run.end();
    return;
  }

  // Parse TAP output
  const results = parseTap(tapOutput);
  const testMap = new Map(testsToRun.map((t) => [t.id, t]));

  for (const r of results) {
    const testItem = testMap.get(r.name);
    if (!testItem) continue;

    if (r.status === "pass") {
      run.passed(testItem, r.duration);
      // Only mark function children that were actually run
      testItem.children.forEach((fn) => {
        if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
          run.passed(fn, r.duration);
        }
      });
    } else if (r.status === "skip") {
      run.skipped(testItem);
      testItem.children.forEach((fn) => {
        if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
          run.skipped(fn);
        }
      });
    } else {
      const messages = [];
      const failedFunctions = new Set();

      if (r.failures && r.failures.length > 0) {
        // Create a TestMessage for each individual assertion failure
        for (const f of r.failures) {
          const msg = new vscode.TestMessage(
            `${f.function}(): ${f.message}`
          );
          // Set expected/actual for diff view
          if (f.expected !== undefined) msg.expectedOutput = f.expected;
          if (f.actual !== undefined) msg.actualOutput = f.actual;
          // Set location to the exact line in the test file
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
        // Fallback: generic failure message
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

      // Map results to function-level children (only those requested)
      testItem.children.forEach((fn) => {
        if (requestedFnIds.size > 0 && !requestedFnIds.has(fn.id)) return;
        const fnName = fn.label;
        if (failedFunctions.has(fnName)) {
          const fnMsgs = messages.filter((m) =>
            m.message?.toString().startsWith(`${fnName}()`)
          );
          run.failed(fn, fnMsgs.length > 0 ? fnMsgs : messages, r.duration);
        } else {
          run.passed(fn, r.duration);
        }
      });
    }
  }

  // Any tests not in results — mark as errored
  for (const t of testsToRun) {
    if (!results.find((r) => r.name === t.id)) {
      run.errored(t, new vscode.TestMessage("Test did not produce TAP output"));
      t.children.forEach((fn) => {
        if (requestedFnIds.size === 0 || requestedFnIds.has(fn.id)) {
          run.errored(fn, new vscode.TestMessage("Test did not produce TAP output"));
        }
      });
    }
  }

  // Auto-show output channel on failures
  if (results.some((r) => r.status === "fail")) {
    outputChannel.show(true); // true = preserve focus
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
      "KGSM: Failed to start debug session. Is the Bash Debug extension (rogalmic.bash-debug) installed?"
    );
  }
}

// ---------------------------------------------------------------------------
// TAP Parser
// ---------------------------------------------------------------------------

function parseTap(output) {
  const results = [];
  const lines = output.split("\n");
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    // Match: ok N - test_name [type] # comment
    // Match: not ok N - test_name [type]
    const match = line.match(
      /^(ok|not ok)\s+\d+\s+-\s+(\S+)\s+\[(\w+)\](.*)$/
    );

    if (match) {
      const [, status, name, , rest] = match;
      const result = {
        name,
        status: "fail",
        message: "",
        duration: undefined,
        failures: [],
      };

      if (status === "ok") {
        if (rest.includes("# SKIP")) {
          result.status = "skip";
        } else {
          result.status = "pass";
          // Parse duration from "# 44 assertions in 309ms"
          const durMatch = rest.match(/(\d+)ms/);
          if (durMatch) result.duration = parseInt(durMatch[1], 10);
        }
      } else {
        // not ok — look for YAML diagnostic block
        result.status = "fail";
        if (i + 1 < lines.length && lines[i + 1].trim() === "---") {
          i++; // skip ---
          const yamlLines = [];
          while (++i < lines.length && lines[i].trim() !== "...") {
            yamlLines.push(lines[i]);
          }
          // Parse YAML fields
          let currentFailure = null;
          for (const yl of yamlLines) {
            const msgMatch = yl.match(/^\s+message:\s+"(.+)"$/);
            const durMatch = yl.match(/^\s+duration_ms:\s+(\d+)$/);
            const failStart = yl.match(/^\s+failures:\s*$/);
            const failLine = yl.match(/^\s+- line:\s+(\d+)$/);
            const failFunc = yl.match(/^\s+function:\s+"(.+)"$/);
            const failMsg = yl.match(/^\s+message:\s+"(.+)"$/);
            const failFile = yl.match(/^\s+file:\s+"(.+)"$/);
            const failExpected = yl.match(/^\s+expected:\s+"(.+)"$/);
            const failActual = yl.match(/^\s+actual:\s+"(.+)"$/);

            if (failStart) {
              // Entering failures array
              continue;
            } else if (failLine) {
              // New failure entry
              if (currentFailure) result.failures.push(currentFailure);
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
            } else if (msgMatch && !currentFailure) {
              result.message = msgMatch[1];
            } else if (durMatch) {
              result.duration = parseInt(durMatch[1], 10);
            }
          }
          if (currentFailure) result.failures.push(currentFailure);
        }
      }

      results.push(result);
    }

    i++;
  }

  return results;
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

function runCommand(cmd, args, token, logToChannel = false) {
  return new Promise((resolve) => {
    const proc = spawn(cmd, args, {
      cwd: workspaceRoot,
      env: { ...process.env, NO_COLOR: "1" },
    });

    let stdout = "";

    proc.stdout.on("data", (data) => (stdout += data.toString()));
    proc.stderr.on("data", (data) => {
      if (logToChannel && outputChannel) {
        outputChannel.append(data.toString());
      }
    });

    proc.on("close", () => resolve(stdout));
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
