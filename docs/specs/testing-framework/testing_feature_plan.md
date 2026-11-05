# KGSM Testing Framework & TAP Adapter — Feature Analysis & Plan

## Executive Summary

After deep analysis of the testing framework (3,300 LOC across 11 modules), the VS Code
test adapter extension, 62 test files with 900+ test functions, the TAP v14 specification,
and the VS Code Testing API, this document identifies concrete, industry-standard features
to add — organized by where they live (framework vs extension) and prioritized by impact
on the goal of making the framework more generic and less KGSM-coupled.

---

## Part 1: TAP Protocol Compliance Gaps

The current TAP parser and producer are functional but miss several TAP v14 spec features
that industry tools expect.

### 1.1 TODO Directive Support

**What:** TAP v14 defines `# TODO reason` as a directive for tests that are expected to
fail. A `not ok` with `# TODO` is NOT a test failure — it's a known issue. An `ok` with
`# TODO` is a bonus pass (unexpected success).

**Current behavior:** The parser ignores directives entirely. A `not ok ... # TODO` is
treated as a hard failure.

**Framework side:**
- Add `todo_test "reason"` function (analogous to `skip_test`)
- Emit TAP line: `not ok N - name [type] # TODO reason`
- The execution engine should NOT count TODO failures in `TAP_HAS_FAILURES`

**Extension side:**
- Parser regex already captures `(.*)$` after `[type]` — needs to check for `# TODO`
- Map TODO tests to a distinct state (VS Code doesn't have a native "todo" state, so
  use `run.skipped()` with a message indicating TODO, or `run.passed()` with a note)

**Why it matters:** Industry TAP consumers (prove, tap-parser, node-tap) all support TODO.
Without it, there's no way to mark known-failing tests without breaking CI.

---

### 1.2 Bail Out! Support

**What:** `Bail out! reason` immediately aborts the entire test run. Used when a
catastrophic failure makes continuing pointless (e.g., database connection lost).

**Current behavior:** Silently ignored as an unmatched line.

**Framework side:**
- Add `bail_out "reason"` function that emits `Bail out! reason` to stdout and exits
- Useful in `setup_test()` when critical preconditions fail

**Extension side:**
- Parser should detect `^Bail out!(.*)$` and immediately:
  - Mark all remaining tests as `run.errored()` with the bail reason
  - Call `run.end()`
  - Kill the child process

**Why it matters:** Without Bail out!, a broken sandbox or missing dependency causes N
individual timeout failures instead of one clear abort.

---

### 1.3 Subtests (TAP v14 Child Tests)

**What:** TAP v14 supports nested TAP streams indented by 4 spaces, with a trailing
test point. This maps naturally to the existing three-level tree (type → file → function).

**Current behavior:** Functions within a test file are not individually reported in the
TAP stream. The TAP output is file-level only. Function-level results are inferred from
YAML diagnostic blocks.

**Framework side:**
- Emit per-function TAP results as subtests within each test file's output:
  ```
  not ok 2 - test_paths [unit]
      TAP version 14
      1..3
      ok 1 - test_resolve_paths
      not ok 2 - test_xdg_compliance
        ---
        message: "Expected directory to exist"
        expected: "directory exists"
        actual: "directory missing"
        ...
      ok 3 - test_home_detection
  ```
- This requires `__capture_test_output()` to track per-function results

**Extension side:**
- Parser needs a state for 4-space-indented TAP streams
- Map subtests to function-level `TestItem` pass/fail directly (instead of
  inferring from YAML `failures[].function`)

**Why it matters:** Per-function TAP results are the standard way to report granular
results. The current YAML-inference approach is fragile and non-standard — other TAP
consumers can't use it. This is the single highest-impact change for TAP compliance.

---

### 1.4 SKIP Reason Preservation

**What:** `ok N - name # SKIP reason text` should preserve the reason.

**Current behavior:** The parser detects `# SKIP` but discards the reason text. The
test is marked as skipped with no explanation shown in the UI.

**Framework side:** Already emits skip reason — no change needed.

**Extension side:**
- Extract reason from `rest.match(/# SKIP\S*\s+(.*)/i)` (per TAP v14 spec)
- Pass reason as message to `run.skipped()` — but VS Code's `skipped()` doesn't
  accept a message. Use `run.appendOutput()` to show the reason in the test output
  terminal instead.

---

## Part 2: VS Code Testing API Gaps

### 2.1 Test Output Streaming (`appendOutput`)

**What:** `TestRun.appendOutput(str)` sends raw output to a per-run terminal panel.
This is separate from test messages and lets users see the full test output.

**Current behavior:** stderr goes to the "KGSM Tests" output channel, but stdout
(the TAP stream) and per-test log content are not surfaced in the test output terminal.

**Extension side:**
- During `runTests()`, call `run.appendOutput()` for each TAP line received
- Use CRLF line endings (`\r\n`) as required by VS Code terminal rendering
- Optionally include the test's log file content on failure

**Why it matters:** Users currently can't see raw test output without checking log files.
Every major test framework extension (Jest, pytest, Go) provides inline output.

---

### 2.2 Coverage Profile

**What:** VS Code Testing API supports `TestRunProfileKind.Coverage` as a third profile
type alongside Run and Debug. Extensions report `FileCoverage` with statement/branch
counts, and VS Code renders inline coverage decorations.

**Current behavior:** Not implemented. No coverage tooling exists.

**Framework side:**
- Integrate with `kcov` (a bash code coverage tool) or `bashcov`:
  - `kcov --include-path=core/,commands/ /tmp/coverage tests/run.sh`
  - Produces Cobertura XML or JSON coverage data
- Add `--coverage` flag to `run.sh` that wraps execution with kcov
- Emit coverage data path in a TAP comment or separate file

**Extension side:**
- Create a third `TestRunProfileKind.Coverage` profile
- After the test run, parse the kcov/bashcov output (Cobertura XML or JSON)
- Call `run.addCoverage(new FileCoverage(...))` for each source file
- Implement `loadDetailedCoverage` to return `StatementCoverage` objects

**Why it matters:** Coverage is table-stakes for modern testing. Bash has working
coverage tools (kcov). This is a differentiator — very few bash test frameworks
integrate with VS Code coverage.

---

### 2.3 Continuous Run / Watch Mode

**What:** VS Code supports a `supportsContinuousRun` flag on test run profiles. When
enabled, users can toggle "auto-run on change" in the Test Explorer.

**Current behavior:** Tests only run on explicit user action. The file watcher triggers
re-discovery (not re-execution).

**Extension side:**
- Set `runProfile.supportsContinuousRun = true`
- In `runHandler`, check `request.continuous` — if true, set up a file watcher
  that re-runs affected tests on save
- Scope re-runs to changed files only (watch `onDidSaveTextDocument`, match to
  test items by URI)

**Why it matters:** Watch mode is standard in Jest, pytest-watch, Go test. It
dramatically speeds up the development loop.

---

### 2.4 Configurable Test Run (configureHandler)

**What:** VS Code allows a `configureHandler` on profiles that opens a configuration
UI before a test run.

**Current behavior:** No configuration UI. TEST_PARALLEL and other settings require
editing config.test.ini or setting env vars.

**Extension side:**
- Set `runProfile.configureHandler` to show a QuickPick with:
  - Parallelism level (1, 2, 4, 8, auto)
  - Timeout override
  - Skip flags (network, docker, steamcmd)
- Pass selected options as environment variables to the spawned process

---

## Part 3: Framework Capability Gaps

### 3.1 Per-Function Setup/Teardown Hooks

**What:** `setup_each()` / `teardown_each()` functions called before/after EACH
`test_*` function (not just once per file like `setup_test()`/`cleanup_test()`).

**Current behavior:** Only file-level hooks exist. Tests manually save/restore state,
causing significant code duplication. Found in ~40% of test files.

**Implementation in execution.common.sh:**
```bash
# In __capture_test_output, around the test function loop:
for func in "${test_functions[@]}"; do
  if declare -F setup_each >/dev/null 2>&1; then
    setup_each
  fi
  $func
  if declare -F teardown_each >/dev/null 2>&1; then
    teardown_each
  fi
done
```

**Why it matters:** This is the #1 most common pattern in xUnit frameworks (JUnit,
pytest, RSpec, BATS). Its absence forces every test to be fully self-contained with
manual cleanup, leading to fragile tests and duplicated code.

---

### 3.2 Parameterized Tests

**What:** Run the same test logic with different inputs, generating distinct TAP results
for each combination.

**Current behavior:** Tests use manual `for` loops. Found in ~10 test files. No per-
iteration reporting — if iteration 3/5 fails, the whole test fails with no clarity on
which input caused it.

**Design:**
```bash
# In test file:
function test_parse_port__data() {
  echo "8080/tcp 8080 tcp"
  echo "25565/udp 25565 udp"
  echo "invalid fail fail"
}

function test_parse_port() {
  local input="$1" expected_port="$2" expected_proto="$3"
  log_test_step "Testing parse_port with input: $input"
  # ... assertions using $input, $expected_port, $expected_proto
}
```

**Framework support:**
- Discovery detects `test_*__data()` companion functions
- Execution calls the data function, reads lines, splits by whitespace
- Each line becomes a separate invocation with positional args
- TAP output: `ok N - test_parse_port[8080/tcp]` (parameterized name)
- JSON discovery: `{ "name": "test_parse_port", "parameterized": true }`

**Why it matters:** Parameterized tests are standard in pytest, JUnit 5, Go table-driven
tests. The manual for-loop workaround produces opaque failures.

---

### 3.3 Test Retry / Flaky Test Detection

**What:** Automatically retry failed tests N times before declaring failure. Track
flakiness across runs.

**Current behavior:** Tests fail once with no retry. No flakiness tracking.

**Implementation:**
- Add `TEST_RETRY_COUNT=0` config variable (default: no retry)
- In execution engine, re-run failed tests up to N times
- TAP output for retried tests: use a comment or directive
  `ok 3 - test_network [integration] # retried 2 times`
- Track flakiness in results.csv: add `retry_count` column

**Why it matters:** Network-dependent and E2E tests are inherently flaky. Retry with
reporting is standard in CI (GitHub Actions has `continue-on-error`, Jest has
`--retries`, pytest has `pytest-rerunfailures`).

---

### 3.4 Test Fixtures / Shared Context

**What:** Reusable, named setup/teardown blocks that can be referenced by tests.

**Current behavior:** `create_test_instance()` is the closest thing, but it's a
function call, not a declarative fixture. Tests manually call it and clean up.

**Design:**
```bash
# Define a fixture
fixture_factorio_instance() {
  local instance_name
  instance_name=$(create_test_instance "factorio" "$(generate_test_id)")
  echo "$instance_name"  # stdout = fixture value
  # Cleanup runs automatically when test ends (via trap or teardown)
}

# Use in test
function test_with_fixture() {
  use_fixture "factorio_instance" INSTANCE_NAME
  log_test_step "Testing with instance: $INSTANCE_NAME"
  assert_instance_exists "$INSTANCE_NAME"
  # No manual cleanup needed — fixture handles it
}
```

**Implementation:**
- Fixtures are functions named `fixture_*`
- `use_fixture "name" VAR` calls the function, stores result in VAR, and
  registers a cleanup trap
- Cleanup runs in reverse order after the test function returns

**Why it matters:** pytest fixtures are one of its most loved features. This pattern
eliminates cleanup boilerplate and makes tests more readable.

---

### 3.5 Assertion Enhancements

#### 3.5.1 `assert_eventually` (Polling Assertion)

```bash
assert_eventually "test -f /tmp/server.pid" 30 1 "Server PID file should appear"
# Polls condition every 1s for up to 30s
```

Currently tests use `wait_for_condition` from kgsm.wrapper.sh but it's not an
assertion — it doesn't increment assertion counters or produce ASSERT_DETAIL output.

#### 3.5.2 `assert_exit_code` (Exact Exit Code)

```bash
assert_exit_code "$EC_BLUEPRINT_NOT_FOUND" "$MODULE find nonexistent" \
  "Should return blueprint not found"
```

Currently exists in assert.sh but should be verified and documented.

#### 3.5.3 `assert_output_contains` / `assert_output_matches`

```bash
assert_output_contains "$MODULE list" "factorio" "Should list factorio"
# Runs command, captures stdout+stderr, asserts content
```

Combines `assert_command_succeeds` + output capture + `assert_contains` into one call.

#### 3.5.4 `assert_array_equals`

```bash
local expected=("a" "b" "c")
local actual=("a" "b" "c")
assert_array_equals expected actual "Arrays should match"
```

No array assertions exist currently.

---

### 3.6 Test Tagging / Labeling

**What:** Arbitrary tags on test functions for filtering (e.g., `@slow`, `@network`,
`@smoke`, `@regression`).

**Design:**
```bash
# Convention: comment above function
# @tags: slow, network
function test_download_server() {
  log_test_step "Testing server download"
  # ...
}
```

**Framework support:**
- Discovery parses `# @tags: tag1, tag2` comments above `test_*` functions
- JSON discovery includes tags: `{ "name": "test_download", "tags": ["slow", "network"] }`
- Filtering: `./tests/run.sh --tag slow` or `--exclude-tag slow`
- Config: `SKIP_TAGS="slow,network"` in config.test.ini

**Extension support:**
- Map tags to VS Code `TestTag` objects
- Users can filter by tag in Test Explorer
- Tags shown in test item description

**Why it matters:** Tags enable flexible test selection beyond the rigid unit/integration/e2e
categorization. Standard in pytest (`@pytest.mark.slow`), JUnit (`@Tag`), Go (`//go:build`).

---

## Part 4: Generic Framework Transition

### 4.1 Decouple Sandbox from KGSM

**Current coupling:** `sandbox.sh` copies the entire KGSM project, applies KGSM-specific
config overrides, and validates KGSM-specific files (kgsm.sh, config.ini, etc.).

**Generalization:**
- Extract project-specific config into a `sandbox.conf` or hook system:
  ```bash
  # tests/sandbox.conf (user-provided)
  SANDBOX_COPY_ROOT="$PROJECT_ROOT"
  SANDBOX_EXCLUDE=(".git" "node_modules" "logs")
  SANDBOX_CONFIG_OVERRIDES="tests/sandbox.overrides.ini"
  SANDBOX_VALIDATE_FILES=("main.sh" "config.ini")
  ```
- Replace hardcoded KGSM paths with `$PROJECT_ROOT`
- Replace `KGSM_ROOT` switching with generic `PROJECT_ROOT` switching
- Move KGSM-specific overrides to `tests/sandbox.overrides.ini`

### 4.2 Extract KGSM Assertions to Plugin

**Current coupling:** 4 assertions are KGSM-specific:
- `assert_kgsm_succeeds` / `assert_kgsm_fails`
- `assert_instance_exists` / `assert_instance_not_exists`

**Generalization:**
- Move to `tests/framework/assertions.kgsm.sh` (plugin)
- Core `assert.sh` remains generic
- Framework loads assertion plugins from a configurable directory
- KGSM-specific assertions become an example of the plugin pattern

### 4.3 Extract Instance Wrapper to Plugin

**Current coupling:** `kgsm.wrapper.sh` directly calls `kgsm.sh` and depends on
KGSM-specific paths (`$KGSM_INSTANCES_DIR`, `$KGSM_MAIN_SCRIPT`).

**Generalization:**
- Move to `tests/framework/plugins/kgsm.wrapper.sh`
- Core framework provides a generic `use_fixture` / `register_cleanup` API
- Project-specific helpers load as plugins

### 4.4 Generic Module Loading

**Current coupling:** `execution.common.sh` unsets KGSM-specific module flags
(`KGSM_BOOTSTRAP_LOADED`, `KGSM_COMMON_LOADED`, etc.) and sources KGSM's
`core/bootstrap.sh`.

**Generalization:**
- Define a `tests/hooks/pre_test.sh` and `tests/hooks/post_test.sh` convention
- Framework calls hooks instead of hardcoding KGSM module loading
- KGSM implements its hooks to handle module flag unsetting and bootstrap sourcing

---

## Part 5: Priority Matrix

### Tier 1 — High Impact, Moderate Effort (Do First)

| # | Feature | Where | Rationale |
|---|---------|-------|-----------|
| 1 | Per-function setup/teardown | Framework | Eliminates #1 source of code duplication |
| 2 | Subtests (per-function TAP) | Framework + Extension | TAP v14 compliance + reliable function-level results |
| 3 | TODO directive | Framework + Extension | TAP v14 compliance, enables "expected failure" workflow |
| 4 | `appendOutput` streaming | Extension | Users need to see raw test output |
| 5 | Bail out! support | Framework + Extension | Prevents cascading timeout failures |

### Tier 2 — High Impact, Higher Effort

| # | Feature | Where | Rationale |
|---|---------|-------|-----------|
| 6 | Test tagging | Framework + Extension | Flexible filtering beyond type groups |
| 7 | Parameterized tests | Framework + Extension | Eliminates manual for-loop patterns in ~10 files |
| 8 | Coverage integration (kcov) | Framework + Extension | Table-stakes modern testing feature |
| 9 | Watch / continuous run mode | Extension | Standard dev workflow acceleration |
| 10 | Decouple sandbox from KGSM | Framework | Required for generic framework |

### Tier 3 — Medium Impact, Moderate Effort

| # | Feature | Where | Rationale |
|---|---------|-------|-----------|
| 11 | Test retry / flaky detection | Framework | CI robustness for network/E2E tests |
| 12 | Test fixtures | Framework | Cleaner test resource management |
| 13 | SKIP reason preservation | Extension | Better UX for skipped tests |
| 14 | Assertion enhancements | Framework | Reduce boilerplate (assert_eventually, assert_array_equals) |
| 15 | Extract KGSM assertions to plugin | Framework | Generic framework step |

### Tier 4 — Lower Impact, Nice to Have

| # | Feature | Where | Rationale |
|---|---------|-------|-----------|
| 16 | Configurable test run UI | Extension | Convenience (QuickPick for parallelism, skips) |
| 17 | Generic module loading hooks | Framework | Full generic framework decoupling |
| 18 | Extract wrapper to plugin | Framework | Full generic framework decoupling |
| 19 | Multi-workspace support | Extension | Edge case, low user impact currently |

---

## Part 6: Implementation Notes

### Subtests — Key Design Decision

The most impactful architectural choice is how per-function results flow from framework
to extension. Two approaches:

**Option A: True TAP Subtests (Recommended)**
- Framework emits indented TAP within each test's output
- Extension parser handles 4-space-indented TAP streams
- Standard-compliant; works with any TAP consumer
- Requires significant changes to `__capture_test_output()` and `TapStreamParser`

**Option B: Enhanced YAML Diagnostics (Current Approach, Extended)**
- Keep current file-level TAP lines
- Add per-function pass/fail details in YAML block (not just failures)
- Non-standard but simpler to implement
- Only works with the custom extension, not generic TAP tools

Recommendation: **Option A** aligns with the generic framework goal. Other TAP consumers
(prove, tap-parser, Jenkins TAP plugin) understand subtests. Option B locks the framework
into the custom extension.

### Coverage — Tool Selection

For bash coverage, the viable options are:

| Tool | Mechanism | Output | Maintenance |
|------|-----------|--------|-------------|
| kcov | DWARF debug info + ptrace | Cobertura XML, JSON, HTML | Active, Linux-only |
| bashcov | bash BASH_XTRACEFD | SimpleCov JSON | Ruby dependency |
| PS4 tracing | Manual `set -x` + PS4 | Custom parsing needed | DIY |

**Recommendation:** `kcov` — no runtime dependencies beyond the binary, produces
standard Cobertura XML that VS Code coverage extensions and CI tools understand.

### Tagging — Discovery Format Change

Adding tags to JSON discovery requires extending the schema:

```json
{
  "name": "test_download",
  "type": "unit",
  "file": "tests/unit/test_download.sh",
  "functions": [
    {
      "name": "test_download_server",
      "line": 42,
      "tags": ["slow", "network"]
    }
  ],
  "tags": ["network"]
}
```

The extension needs to:
1. Create `TestTag` instances for each unique tag
2. Assign tags to `TestItem.tags`
3. Support `--tag` and `--exclude-tag` CLI args passed to `run.sh`

---

## Appendix: Current State Summary

| Metric | Value |
|--------|-------|
| Framework LOC | ~3,300 |
| Extension LOC | ~770 |
| Test files | 62 |
| Test functions | 900+ |
| Assertions available | 26 |
| KGSM-specific assertions | 4 |
| Framework modules | 11 |
| KGSM-coupled modules | 3 (sandbox.sh, kgsm.wrapper.sh, execution.common.sh) |
| TAP v14 features supported | 5/9 (version, plan, ok/not ok, YAML diagnostics, SKIP status) |
| TAP v14 features missing | 4/9 (TODO, Bail out, subtests, pragmas) |
| VS Code API features used | 12/18 |
| VS Code API features missing | 6/18 (continuous run, coverage, appendOutput, configureHandler, tag filtering, rich messages) |
