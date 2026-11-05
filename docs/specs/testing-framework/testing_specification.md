# KGSM Testing Specification

**Version:** 3.0
**Last Updated:** February 2026
**Purpose:** Authoritative reference for writing tests in the KGSM project

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Testing Philosophy](#testing-philosophy)
3. [Test Types](#test-types)
4. [Test Structure](#test-structure)
5. [TAP Output Format](#tap-output-format)
6. [VS Code Integration](#vs-code-integration)
7. [Writing Tests](#writing-tests)
8. [Assertion Library](#assertion-library)
9. [Exit Codes](#exit-codes)
10. [Framework Modules](#framework-modules)
11. [Best Practices](#best-practices)

---

## Quick Start

### Running Tests

The primary workflow uses **VS Code Test Explorer**. The CLI is available for CI pipelines and one-off use.

```bash
# VS Code (primary): Open Test Explorer or use CodeLens above test_* functions

# CLI (for CI or one-off use):
./tests/run.sh                              # All tests
./tests/run.sh unit                          # Unit tests only
./tests/run.sh --pattern "config" unit       # Filter by name
TEST_PARALLEL=4 ./tests/run.sh unit          # 4 concurrent tests
```

#### CLI Flags

| Flag                     | Description                                |
| ------------------------ | ------------------------------------------ |
| `--list-json [types...]` | JSON discovery for VS Code                 |
| `--pattern <glob>`       | Filter tests by name (repeatable, unioned) |
| `--function <name>`      | Run only a specific test function          |
| `--debug-run <file>`     | Inline execution for interactive debuggers |
| `unit\|integration\|e2e` | Test type selectors                        |

A `--pattern` matches a test file either as a glob over its name
(`test_config_*.sh` — the `.sh` is optional) or as a fragment of it (`config`).
Repeating the flag unions the selections. A pattern that matches nothing exits
non-zero rather than reporting an empty pass, so a mistyped filter cannot go
green.

Parallelism is controlled via the `TEST_PARALLEL` environment variable (not a CLI flag).

### Creating a New Test

```bash
# 1. Copy the template
cp tests/templates/test.template.sh tests/unit/test_mymodule_logic.sh

# 2. Edit the file:
#    - Replace <PLACEHOLDERS>
#    - Implement test functions (test_* naming)
#    - No main() needed — the framework auto-discovers test_* functions

# 3. Run it
./tests/run.sh --pattern mymodule
```

---

## Testing Philosophy

### Core Principles

1. **Complete Isolation** - Each test runs in a sandboxed copy of KGSM (`/tmp/kgsm-test-sandbox-*/`)
2. **Real Code Testing** - No mocking; tests execute actual KGSM modules
3. **Behavioral Certainty** - Tests verify defined, deterministic outcomes
4. **Real Data Usage** - Tests use actual KGSM blueprints and configurations, not synthetic fixtures

### Key Rules

- ❌ No tests with uncertain outcomes
- ❌ No mocking (except system services like systemctl)
- ❌ No synthetic test fixtures when real data exists
- ✅ Every test must have defined behavior
- ✅ All tests run in complete isolation
- ✅ Tests use `teardown()` hooks for cleanup to guarantee execution even on failure
- ✅ Use `setup()` / `teardown()` hooks for repeating per-test state management
- ✅ Use real blueprints from `blueprints/native/` or `blueprints/container/`

### Standard Test Blueprints

**Always use these real blueprints for testing to cover all variations:**

**Native Blueprints:**
- `factorio` - Non-Steam game with overrides (install/update logic)
- `terraria` - Non-Steam game with overrides
- `starbound` - Steam game requiring Steam account (`is_steam_account_required=true`)
- `necesse` - Steam game not requiring Steam account (`is_steam_account_required=false`)

**Container Blueprints:**
- `vrising` - Docker-based game server

These blueprints cover all blueprint variations (Steam/non-Steam, account requirements, native/container) and should be used consistently across all tests.

### Permission Error Testing

When testing permission-related errors (e.g., `EC_PERMISSION`):

1. Use real blueprints from the sandbox
2. Save original permissions in `setup()` and modify them with `chmod`
3. Execute the test operation
4. Restore permissions in `teardown()` to guarantee restoration even on failure

**Example:**
```bash
# File-level variable shared between hooks and test functions
BLUEPRINT_PATH=""
SAVED_PERMS=""

function setup() {
  BLUEPRINT_PATH="$BLUEPRINTS_NATIVE_DEFAULT_DIR/factorio.bp"
  SAVED_PERMS=$(stat -c "%a" "$BLUEPRINT_PATH")
}

function teardown() {
  # Restore permissions — guaranteed to run even if the test fails
  if [[ -n "$SAVED_PERMS" && -n "$BLUEPRINT_PATH" ]]; then
    chmod "$SAVED_PERMS" "$BLUEPRINT_PATH"
  fi
}

function test_permission_error() {
  log_test_step "Testing permission denied scenario"

  # Make unreadable
  chmod 000 "$BLUEPRINT_PATH"

  # Test
  __logic_get_blueprint_path "factorio" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_PERMISSION" "$exit_code" "Should return permission error"
}
```

---

## Test Types

### Unit Tests (`tests/unit/`)

Test individual components in isolation.

**Two subtypes:**

1. **Logic Layer** (`test_<module>_logic.sh`)
   - Tests pure `__logic_*` functions from `commands/handlers/*.sh`
   - Validates exit codes only (functions suppress output)
   - Fast execution, no external dependencies

2. **Command Layer** (`test_<module>_commands.sh`)
   - Tests command-based CLI from `commands/*.sh`
   - Validates argument parsing, help system, user messages
   - Tests exit code handling and event dispatching

### Integration Tests (`tests/integration/`)

Test interaction between multiple modules.

**Naming:** `test_<module1>_<module2>_integration.sh`

**Tests:**
- Module orchestration flows
- Data flow between components
- State consistency across modules
- Cross-module error handling

### End-to-End Tests (`tests/e2e/`)

Test complete user workflows.

**Naming:** `test_<workflow>_e2e.sh`

**Tests:**
- Complete feature workflows
- Real-world usage scenarios
- Multi-module coordination
- May require external dependencies (SteamCMD, Docker)

---

## Test Structure

### Universal Structure

All tests follow this structure (see `tests/templates/test.template.sh`). The framework **auto-discovers** `test_*` functions — there is **no `main()` function**.

```bash
#!/usr/bin/env bash

# KGSM <Description> Tests

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="<test_name>"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up tests"
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
}

# Optional: setup() is called by the framework BEFORE EACH test_*() function.
# Use for per-test resource creation, config reset, etc.
# function setup() {
#   log_test_step "Per-test setup"
#   # Create test-specific resources here
# }

function test_something() {
  log_test_step "Testing something"  # REQUIRED: First call in every test
  # Test implementation
}

# Optional: teardown() is called by the framework AFTER EACH test_*() function.
# Runs even if the test fails. Failures here do not affect the test result.
# function teardown() {
#   log_test_step "Per-test cleanup"
#   # Clean up test-specific resources here
# }

# Optional:
# function cleanup_test() { ... }

# NO main() — framework auto-discovers and runs test_* functions
# Framework calls: setup_test() → [setup() → test_*() → teardown()] … → print_assert_summary() → cleanup_test()
```

### Required Elements

- **Minimal global code**: Only sourcing and constants at file level
- **All logic in functions**: Every test operation inside a function
- **log_test_step first**: Every test function MUST start with `log_test_step`
- **No `main()`**: The framework handles orchestration, discovery, and summary reporting

### Framework Execution Order

For each test file, the framework executes:

1. Function discovery — the `test_*()` functions the file declares are recorded
   to the test log as a `KGSM_FUNC_PLAN:` marker before the file is sourced
2. `setup_test()` — once per file: environment validation and shared setup
3. For each `test_*()` function, in file order:
   - `setup()` — if defined, runs before each test function
   - `test_*()` — the test function itself
   - `teardown()` — if defined, runs after each test function (failures ignored)
   - a `KGSM_FUNC_RESULT:` marker recording that function's outcome
4. `print_assert_summary()` — framework-managed, reports results
5. `cleanup_test()` — once per file, if defined
6. Reconciliation — the plan is compared against the recorded results. A declared
   function with no result is reported as a failing subtest and fails the file,
   so a run can never be green over tests that did not execute.

```
┌─────────────────────────────────────────────────────────┐
│ Test File Execution                                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. setup_test()          ← once per file               │
│                                                         │
│  2. ┌── setup()           ← before test_1               │
│     ├── test_1()                                        │
│     └── teardown()        ← after test_1                │
│                                                         │
│  3. ┌── setup()           ← before test_2               │
│     ├── test_2()                                        │
│     └── teardown()        ← after test_2                │
│                                                         │
│  4. print_assert_summary()                              │
│  5. cleanup_test()        ← once per file               │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Per-Test vs Per-File Setup

Choose the right hook based on the scope and cost of the operation:

| Use Case | Hook | Why |
| -------- | ---- | --- |
| Validate environment, source modules, verify sandbox | `setup_test()` | Only needs to happen once per file |
| Create test-specific files/directories | `setup()` | Each test needs a clean slate |
| Reset config values between tests | `setup()` / `teardown()` | Prevents state pollution |
| Create/destroy instances per test | `setup()` / `teardown()` | Per-test isolation |
| Final resource cleanup | `cleanup_test()` | Rarely needed (sandbox handles it) |

---

## TAP Output Format

The test runner produces **TAP version 14** output, enabling integration with VS Code and other TAP consumers.

### Example Output

```
TAP version 14
1..3
ok 1 - test_config [unit] # 5 assertions in 142ms
not ok 2 - test_paths [unit]
  ---
  severity: fail
  message: "1/2 assertions failed"
  exit_code: 1
  duration_ms: 89
  assertions_passed: 1
  assertions_failed: 1
  assertions_total: 2
  file: "tests/unit/test_paths.sh"
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

### Result Line Format

Each test produces a TAP result line:

```
(ok|not ok) N - {name} [{type}] {details}
```

| Field           | Description                                   |
| --------------- | --------------------------------------------- |
| `ok` / `not ok` | Pass or fail status                           |
| `N`             | Sequential test number                        |
| `{name}`        | Test file/function name                       |
| `[{type}]`      | Test type: `unit`, `integration`, or `e2e`    |
| `{details}`     | Assertion count, duration, or `# SKIP reason` |

### YAML Diagnostic Blocks

Failed tests include a YAML diagnostic block (indented with two spaces, between `---` and `...` markers) containing:

- `severity` — always `fail`
- `message` — summary of failures
- `exit_code` — process exit code
- `duration_ms` — execution time in milliseconds
- `assertions_passed` / `assertions_failed` / `assertions_total` — assertion counts
- `file` — path to the test file
- `failures` — list of individual assertion failures with `line`, `function`, `message`, `expected`, and `actual`

The TAP diagnostic output is generated by `tests/framework/reporting.tap.sh`.

---

## VS Code Integration

### Test Adapter Extension

KGSM includes a custom VS Code Test Adapter at `.vscode/kgsm-test-adapter/`. It integrates with VS Code's native **Test Explorer** to provide a seamless testing workflow.

### Features

- **Three-level test tree**: type group (`unit`/`integration`/`e2e`) → test file → `test_*` function
- **CodeLens**: "Run" and "Debug" buttons appear above each `test_*` function in the editor
- **Test Explorer**: Full test suite visible in the VS Code sidebar
- **TAP parsing**: Results from the TAP v14 output are displayed inline

### Prerequisites

- Install the `rogalmic.bash-debug` extension for debugging support

### How It Works

1. The adapter calls `./tests/run.sh --list-json` to discover available tests
2. When running tests, it invokes `./tests/run.sh` with `--pattern` and/or `--function` flags
3. TAP v14 output is parsed and mapped back to the test tree
4. For debugging, it uses `--debug-run <file> --function <name>` for inline execution

See `.vscode/kgsm-test-adapter/README.md` for full extension documentation.

---

## Writing Tests

### Step-by-Step Guide

**1. Copy the template:**
```bash
cp tests/templates/test.template.sh tests/<type>/test_<name>.sh
```

**2. Set test metadata:**
```bash
readonly TEST_NAME="<module>_<layer>"

# For unit/integration tests:
readonly MODULE="$KGSM_ROOT/commands/<module>.sh"
# or
readonly HANDLER="$KGSM_ROOT/commands/handlers/<module>.sh"
```

**3. Implement setup_test():**
```bash
function setup_test() {
  log_test_step "Setting up <name> tests"

  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"

  # Source handlers (for logic tests)
  # source "$KGSM_ROOT/commands/handlers/<module>.sh"

  # Verify modules exist (for command tests)
  # assert_file_exists "$MODULE" "Module should exist"

  log_test_step "Environment validated"
}
```

**4. (Required when tests have side effects) Implement per-test hooks:**

**Always** define `setup()` and `teardown()` when tests in the file create resources, modify config, or produce side effects. This is the **required pattern** for managing per-test state — do not duplicate setup/cleanup code inside individual test functions. Inline cleanup is only acceptable for one-off resources unique to a single test function.

```bash
# Runs before EACH test_*() function
function setup() {
  log_test_step "Per-test setup"
  # Create test-specific resources here
}

# Runs after EACH test_*() function, even on failure
function teardown() {
  log_test_step "Per-test cleanup"
  # Clean up test-specific resources here
}
```

`teardown()` is guaranteed to run even if the test fails, so it is the correct place for cleanup that must not be skipped. Unlike inline cleanup code at the end of a test function, `teardown()` executes even when an assertion failure or early return prevents the test from completing.

**5. Write test functions:**

Use `setup()` / `teardown()` hooks for instance lifecycle and repeating resources. Test functions should focus on the test logic itself:

```bash
# Per-test hooks handle instance lifecycle
function setup() {
  INSTANCE_NAME=$(create_test_instance "factorio" "$(generate_test_id)")
}

function teardown() {
  remove_test_instance "factorio" "$INSTANCE_NAME"
}

function test_operation_success() {
  log_test_step "Testing operation with valid input"

  __logic_operation "$INSTANCE_NAME"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_EVENT" "Should return success code"
}
```

The framework discovers and runs all `test_*` functions automatically — no `main()` needed.

### Common Test Patterns

#### Testing Logic Functions

```bash
function setup() {
  INSTANCE_NAME=$(create_test_instance "factorio" "$(generate_test_id)")
}

function teardown() {
  remove_test_instance "factorio" "$INSTANCE_NAME"
}

function test_logic_success() {
  log_test_step "Testing __logic_operation with valid parameters"

  __logic_operation "$INSTANCE_NAME"
  assert_equals "$EC_SUCCESS_EVENT" "$?" "Should succeed"
}
```

#### Testing Commands

```bash
function setup() {
  INSTANCE_NAME=$(create_test_instance "factorio" "$(generate_test_id)")
}

function teardown() {
  remove_test_instance "factorio" "$INSTANCE_NAME"
}

function test_command_execution() {
  log_test_step "Testing 'command' execution"

  assert_command_succeeds "$MODULE command $INSTANCE_NAME" "Command should succeed"

  local output=$("$MODULE" command "$INSTANCE_NAME" 2>&1)
  assert_contains "$output" "success" "Should show success message"
}
```

#### Testing Error Handling

```bash
function test_error_handling() {
  log_test_step "Testing error with invalid input"

  __logic_operation "invalid_input" 2>/dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return error code"
}
```

#### Testing Integration Workflows

```bash
function test_workflow() {
  log_test_step "Testing workflow: module1 → module2"

  # Execute first operation
  local result1=$("$MODULE1" create <args> 2>&1)
  assert_not_null "$result1" "Should create resource"

  # Execute second operation using first result
  assert_command_succeeds "$MODULE2 modify $result1" "Should modify created resource"

  # Verify final state
  assert_file_exists "$KGSM_ROOT/expected/file" "Expected file should exist"
}
```

#### Testing Complete Workflows (E2E)

```bash
function test_complete_lifecycle() {
  log_test_step "Testing complete instance lifecycle"

  local instance=$(generate_test_id)

  # Create
  local created=$("$KGSM_ROOT/commands/instances.sh" create factorio --name "$instance" 2>&1)
  assert_not_null "$created" "Instance created"

  # Setup
  assert_command_succeeds "$KGSM_ROOT/commands/directories.sh create --instance $created"
  assert_command_succeeds "$KGSM_ROOT/commands/files.sh create --instance $created"

  # Start
  assert_command_succeeds "$KGSM_ROOT/commands/lifecycle.sh start $created"
  sleep 5
  assert_command_succeeds "$KGSM_ROOT/commands/lifecycle.sh is-active $created"

  # Stop
  assert_command_succeeds "$KGSM_ROOT/commands/lifecycle.sh stop $created"

  # Remove
  assert_command_succeeds "$KGSM_ROOT/commands/files.sh remove --instance $created"
  assert_command_succeeds "$KGSM_ROOT/commands/directories.sh remove --instance $created"
  assert_command_succeeds "$KGSM_ROOT/commands/instances.sh remove $created"
}
```

#### Conditional Test Skipping

```bash
function test_requires_docker() {
  if ! is_docker_available; then
    skip_test "Docker not available"
  fi

  log_test_step "Testing with Docker"
  # Test implementation
}
```

---

## Assertion Library

### Basic Assertions

| Function                                      | Description             |
| --------------------------------------------- | ----------------------- |
| `assert_equals <expected> <actual> <msg>`     | Values are equal        |
| `assert_not_equals <expected> <actual> <msg>` | Values are not equal    |
| `assert_true <condition> <msg>`               | Condition is true       |
| `assert_false <condition> <msg>`              | Condition is false      |
| `assert_null <value> <msg>`                   | Value is null/empty     |
| `assert_not_null <value> <msg>`               | Value is not null/empty |

### String Assertions

| Function                                         | Description                      |
| ------------------------------------------------ | -------------------------------- |
| `assert_contains <string> <substring> <msg>`     | String contains substring        |
| `assert_not_contains <string> <substring> <msg>` | String doesn't contain substring |
| `assert_matches <string> <regex> <msg>`          | String matches regex pattern     |
| `assert_not_matches <string> <regex> <msg>`      | String doesn't match regex       |

### File/Directory Assertions

| Function                                   | Description             |
| ------------------------------------------ | ----------------------- |
| `assert_file_exists <path> <msg>`          | File exists             |
| `assert_file_not_exists <path> <msg>`      | File doesn't exist      |
| `assert_dir_exists <path> <msg>`           | Directory exists        |
| `assert_dir_not_exists <path> <msg>`       | Directory doesn't exist |
| `assert_file_executable <path> <msg>`      | File is executable      |
| `assert_file_contains <path> <text> <msg>` | File contains text      |

### Command Assertions

| Function                              | Description                      |
| ------------------------------------- | -------------------------------- |
| `assert_command_succeeds <cmd> <msg>` | Command exits with 0             |
| `assert_command_fails <cmd> <msg>`    | Command exits with non-zero      |
| `assert_exit_code <cmd> <code> <msg>` | Command exits with specific code |

### KGSM-Specific Assertions

| Function                                  | Description            |
| ----------------------------------------- | ---------------------- |
| `assert_instance_exists <name> <msg>`     | Instance exists        |
| `assert_instance_not_exists <name> <msg>` | Instance doesn't exist |
| `assert_function_exists <name> <msg>`     | Function is defined    |

### Numeric Assertions

| Function                                            | Description        |
| --------------------------------------------------- | ------------------ |
| `assert_greater_than <actual> <expected> <msg>`     | actual > expected  |
| `assert_less_than <actual> <expected> <msg>`        | actual < expected  |
| `assert_greater_or_equal <actual> <expected> <msg>` | actual >= expected |
| `assert_less_or_equal <actual> <expected> <msg>`    | actual <= expected |

**See `tests/framework/assert.sh` for complete list of assertions and their definitions.**

---

## Exit Codes

### Success Event Codes (200-255)

Used by logic layer to indicate successful operations that trigger events.

| Code | Constant                        | Event                 |
| ---- | ------------------------------- | --------------------- |
| 200  | `EC_SUCCESS_INSTANCE_CREATED`   | Instance created      |
| 201  | `EC_SUCCESS_INSTANCE_REMOVED`   | Instance removed      |
| 210  | `EC_SUCCESS_INSTANCE_INSTALLED` | Instance installed    |
| 211  | `EC_SUCCESS_INSTANCE_STARTED`   | Instance started      |
| 212  | `EC_SUCCESS_INSTANCE_STOPPED`   | Instance stopped      |
| 213  | `EC_SUCCESS_INSTANCE_RESTARTED` | Instance restarted    |
| 220  | `EC_SUCCESS_CONFIG_UPDATED`     | Configuration updated |
| 230  | `EC_SUCCESS_FILES_CREATED`      | Files created         |
| 231  | `EC_SUCCESS_FILES_REMOVED`      | Files removed         |

### Standard Error Codes (1-45)

| Code | Constant                     | Meaning                   |
| ---- | ---------------------------- | ------------------------- |
| 1    | `EC_GENERAL`                 | General error             |
| 2    | `EC_INVALID_ARG`             | Invalid argument          |
| 3    | `EC_MISSING_ARG`             | Missing required argument |
| 5    | `EC_FILE_NOT_FOUND`          | File not found            |
| 6    | `EC_DIR_NOT_FOUND`           | Directory not found       |
| 10   | `EC_INSTANCE_NOT_FOUND`      | Instance not found        |
| 11   | `EC_INSTANCE_ALREADY_EXISTS` | Instance already exists   |
| 27   | `EC_BLUEPRINT_NOT_FOUND`     | Blueprint not found       |
| 40   | `EC_PERMISSION_DENIED`       | Permission denied         |

**See `core/errors.sh` for complete list.**

---

## Framework Modules

| Module                | Purpose                         | Key Functions                                                |
| --------------------- | ------------------------------- | ------------------------------------------------------------ |
| `bootstrap.sh`        | Init TEST_ROOT, KGSM_ROOT       | Auto-sources common.sh                                       |
| `loader.sh`           | Constants, paths, exit codes    | 40+ exports                                                  |
| `common.sh`           | Module orchestrator             | `__load_module()`                                            |
| `config.sh`           | Load config.test.ini            | `load_test_config()`, `__normalize_test_parallel()`          |
| `sandbox.sh`          | Isolated KGSM copies            | `create_sandbox()`, `cleanup_sandbox()`                      |
| `discovery.sh`        | Find/filter tests, JSON listing | `discover_tests()`, `should_run_test()`, `list_tests_json()` |
| `execution.common.sh` | Test execution engine           | `execute_test_in_sandbox()`, `__execute_test_inline()`       |
| `reporting.tap.sh`    | TAP diagnostic output           | `__tap_emit_failure_details()`                               |
| `logging.sh`          | Structured logging              | `log_debug/info/warn/error()`, `log_test_step()`             |
| `assert.sh`           | 25+ assertion functions         | `assert_equals()`, `assert_true()`, `print_assert_summary()` |
| `kgsm.wrapper.sh`     | Test instance management        | `create_test_instance()`, `remove_test_instance()`           |

---

## Best Practices

### Test Organization

1. **One test file per module/layer**
   - Logic tests: `test_<module>_logic.sh`
   - Command tests: `test_<module>_commands.sh`
   - Integration: `test_<module1>_<module2>_integration.sh`

2. **One test function per scenario**
   - `test_operation_success()`
   - `test_operation_missing_arg()`
   - `test_operation_invalid_input()`

3. **Group related tests**
   - Use comments to separate test sections
   - Follow consistent naming patterns

### Test Quality

1. **Always start with log_test_step**
   ```bash
   function test_something() {
     log_test_step "Testing something"  # REQUIRED
     # Test code
   }
   ```

2. **Test success AND failure paths**
   ```bash
   test_operation_success()
   test_operation_missing_arg()
   test_operation_invalid_input()
   ```

3. **Use `teardown()` for cleanup**
   ```bash
   # Use teardown() for guaranteed cleanup
   function teardown() {
     remove_test_instance "factorio" "$INSTANCE_NAME"
   }
   ```
   `teardown()` is guaranteed to run even on assertion failure, unlike inline cleanup at the end of a test function which is skipped when tests fail mid-function. Only use inline cleanup for one-off resources unique to a single test.

4. **Use descriptive assertion messages**
   ```bash
   assert_equals "$exit_code" "$EC_SUCCESS_EVENT" \
     "Should return EC_SUCCESS_EVENT when instance starts successfully"
   ```

5. **Test edge cases**
   - Empty strings
   - Special characters
   - Very long inputs
   - Concurrent operations (if applicable)

### Performance

1. **Keep unit tests fast** - No external dependencies
2. **Use test utilities** - `create_test_instance()`, `generate_test_id()`
3. **Skip expensive tests conditionally** - Use `skip_test()` when dependencies missing
4. **Use `teardown()` for cleanup** - Guarantees execution even when tests fail

### Debugging

#### VS Code Debugging (Primary)

1. Install the `rogalmic.bash-debug` extension
2. Open a test file → click "Debug" above any `test_*` function (CodeLens)
3. Set breakpoints, step through with bashdb

**How it works internally:**
- The adapter passes `--debug-run <file> --function <name>` to `tests/run.sh`
- `--debug-run` executes tests inline (no subshell) so bashdb can trace execution
- `NO_COLOR=1` is set to prevent ANSI codes from interfering with the debugger

#### CLI Debugging

1. **Check logs** - `$KGSM_TEST_LOG` contains detailed output
2. **Use log_test_step** - Add debug logging in test functions
3. **Run a single function** - `./tests/run.sh --function test_my_func --pattern mytest`

---

## Framework Utilities

### Test Instance Management (kgsm.wrapper.sh)

KGSM provides the `kgsm.wrapper.sh` module for creating and managing test instances. This module handles the complete instance creation workflow, including prerequisite setup (working directories and symlinks).

#### Automatic Instance Creation (Recommended)

Use `create_test_instance()` for end-to-end instance creation:

```bash
# Option A: Auto-generated name
local instance_name
instance_name=$(create_test_instance "factorio")
echo "Created instance: $instance_name"

# Option B: Custom name
local custom_instance
custom_instance=$(create_test_instance "factorio" "my_custom_name")
echo "Created instance: $custom_instance"

# Option C: Custom install directory
local custom_dir_instance
custom_dir_instance=$(create_test_instance "factorio" "test_instance" "/custom/path")
echo "Created instance: $custom_dir_instance"

# Cleanup (enhanced removal with complete cleanup)
remove_test_instance "factorio" "$instance_name"
remove_test_instance "factorio" "$custom_instance"
remove_test_instance "factorio" "$custom_dir_instance" "/custom/path"
```

#### Manual Control (For Edge Case Testing)

Use `setup_instance_prereqs()` when you need fine-grained control over instance creation steps:

```bash
# Example: Testing behavior when symlink exists but config doesn't
local blueprint="factorio"
local instance_name="test_manual_instance"
local install_dir="${TEST_INSTALL_DIR:-$TEST_SANDBOX_INSTANCES_INSTALL_DIR}"

# Step 1: Setup prerequisites only (working dir + symlink)
setup_instance_prereqs "$blueprint" "$instance_name" "$install_dir"

# Step 2: Create instance config (or test other scenarios)
"$KGSM_MAIN_SCRIPT" instances create "$blueprint" --name "$instance_name" --library "$library"

# Cleanup
remove_test_instance "$blueprint" "$instance_name" "$install_dir"
```

#### Available Functions

| Function                                          | Purpose                                   |
| ------------------------------------------------- | ----------------------------------------- |
| `create_test_instance <blueprint> [name] [dir]`   | Full instance creation (prereqs + config) |
| `remove_test_instance <blueprint> <name> [dir]`   | Complete instance removal and cleanup     |
| `setup_instance_prereqs <blueprint> <name> [dir]` | Manual prerequisite setup (dir + symlink) |
| `generate_test_id [prefix]`                       | Generate unique instance ID               |

#### Usage in Test Functions

```bash
BLUEPRINT="factorio"
INSTANCE_NAME=""

function setup() {
  INSTANCE_NAME=$(create_test_instance "$BLUEPRINT") || {
    fail_test "Failed to create instance"
    return 1
  }
}

function teardown() {
  remove_test_instance "$BLUEPRINT" "$INSTANCE_NAME"
}

function test_instance_operation() {
  log_test_step "Testing instance operation"

  assert_file_exists "$KGSM_INSTANCES_DIR/$BLUEPRINT/$INSTANCE_NAME"
  assert_true "[[ -L $KGSM_INSTANCES_DIR/$BLUEPRINT/$INSTANCE_NAME ]]"
}
```

**Benefits:**
- **Consistency**: All tests use the same creation pattern
- **Simplicity**: No need to reimplement prerequisite setup in each test
- **Flexibility**: Automatic or manual control based on testing needs
- **Safety**: Enhanced cleanup removes all artifacts (symlinks, dirs, empty parents)
- **Transparency**: Wrapper behavior matches install.sh workflow exactly

### Conditional Execution

```bash
# Skip test
skip_test "Reason for skipping"

# Check Docker availability
if is_docker_available; then
  # Docker tests
fi

# Require SteamCMD (skips test if not available)
require_steamcmd
```

### Waiting/Timing

```bash
# Wait for condition
wait_for_condition "test -f /path/to/file" 30 1 "file creation"

# Wait for port
wait_for_port "localhost" "34197" 60
```

### Test Lifecycle

```bash
# Record an explicit pass for the current test function
pass_test "Test passed message"

# Record an explicit failure for the current test function
fail_test "Test failed message"

# Mark the current test function skipped, then return
skip_test "Reason for skipping" && return

# Abort the whole run (TAP v14 Bail out!)
bail_out "Reason the run cannot continue"
```

`pass_test` and `fail_test` are assertions: each records one result against the
running test function and returns. Only `bail_out` ends the process, and it is
the one deliberate early stop — every test function a file declares runs, in
file order, in one process.

---

## File Naming Conventions

### Test Files

| Type         | Pattern                                   | Example                                     |
| ------------ | ----------------------------------------- | ------------------------------------------- |
| Logic Unit   | `test_<module>_logic.sh`                  | `test_lifecycle_logic.sh`                   |
| Command Unit | `test_<module>_commands.sh`               | `test_lifecycle_commands.sh`                |
| Integration  | `test_<module1>_<module2>_integration.sh` | `test_instances_directories_integration.sh` |
| E2E          | `test_<workflow>_e2e.sh`                  | `test_instance_lifecycle_e2e.sh`            |

### Directory Structure

```
tests/
├── run.sh                           # TAP v14 test runner (VS Code adapter entry point)
├── framework/
│   ├── assert.sh                    # Testing assertions library (25+ assertions)
│   ├── bootstrap.sh                 # Initial environment setup (TEST_ROOT, KGSM_ROOT)
│   ├── common.sh                    # Module orchestrator and loader
│   ├── config.sh                    # Test configuration (config.test.ini)
│   ├── discovery.sh                 # Test discovery and JSON listing
│   ├── execution.common.sh          # Test execution (sandbox, inline, timeout)
│   ├── kgsm.wrapper.sh              # Test instance creation and management
│   ├── loader.sh                    # Constants and helper function exports
│   ├── logging.sh                   # Structured logging (DEBUG/INFO/WARN/ERROR)
│   ├── reporting.tap.sh             # TAP YAML diagnostic block generation
│   └── sandbox.sh                   # Isolated KGSM copy for test execution
├── templates/
│   └── test.template.sh             # Test template (no main())
├── unit/                            # Unit tests
├── integration/                     # Integration tests
├── e2e/                             # E2E tests
├── logs/                            # Test logs
└── config.test.ini                  # Test configuration
```

---

## Troubleshooting

### Common Issues

**Tests fail in sandbox:**
- Verify `KGSM_ROOT` points to sandbox, not real installation
- Check test uses `$KGSM_ROOT` in all paths

**Assertion failures:**
- Open VS Code Test Explorer to see inline failure details
- Check `$KGSM_TEST_LOG` for detailed logs
- Verify assertion messages are descriptive

**Cleanup issues:**
- Use `teardown()` for repeating cleanup — it runs even if tests fail
- Use `remove_test_instance()` in `teardown()` for test instances
- Only use inline cleanup for one-off resources unique to a single test

**Missing dependencies:**
- Use `require_*()` functions to skip tests gracefully
- Check `is_docker_available()`, `is_steamcmd_available()`

### Getting Help

- Check existing tests in `tests/unit/`, `tests/integration/`, `tests/e2e/`
- Review `tests/framework/common.sh` for available utilities
- See `tests/framework/assert.sh` for all assertion functions

---

**For complete framework details, see:**
- `docs/specs/testing_specification.md` - This specification
- `tests/README.md` - Testing framework overview
- `tests/framework/assert.sh` - All assertion functions
- `core/errors.sh` - Complete exit code reference
- `.vscode/kgsm-test-adapter/README.md` - VS Code test adapter documentation
