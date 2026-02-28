# KGSM Test Framework

Modular, sandboxed testing framework for KGSM with **TAP v14** output and **VS Code Test Explorer** integration. Follows the **bootstrap → loader → common → specialized modules** pattern.

## Quick Start

### VS Code (Primary)

The recommended way to run and debug tests is through VS Code with the **KGSM Test Adapter** extension (`.vscode/kgsm-test-adapter/`):

1. Open the KGSM workspace in VS Code
2. Open the **Test Explorer** sidebar — tests appear in a three-level tree: **type → file → function**
3. Click **Run** or **Debug** (CodeLens) above any `test_*` function
4. Results appear inline with TAP v14 diagnostics on failure

The extension requires [`rogalmic.bash-debug`](https://marketplace.visualstudio.com/items?itemName=rogalmic.bash-debug) for interactive debugging with bashdb.

### CLI (CI / One-off)

`tests/run.sh` is the VS Code Test Adapter entry point but can also be invoked directly:

```bash
./tests/run.sh                           # All tests
./tests/run.sh unit                      # Unit tests only
./tests/run.sh integration e2e           # Multiple types
./tests/run.sh --pattern "config"        # Filter by name (repeatable)
./tests/run.sh --function "test_merge"   # Run a single test function
TEST_PARALLEL=auto ./tests/run.sh unit   # Parallel execution (CPU cores / 2)
```

**CLI flags:**

| Flag                     | Description                                         |
| ------------------------ | --------------------------------------------------- |
| `--list-json [types...]` | JSON test discovery for VS Code                     |
| `--pattern <regex>`      | Filter tests by name (repeatable)                   |
| `--function <name>`      | Run only a specific test function                   |
| `--debug-run <file>`     | Inline execution for interactive debuggers (bashdb) |
| `unit\|integration\|e2e` | Test type selectors (combinable)                    |

**Environment variables:**

| Variable                   | Description                                              |
| -------------------------- | -------------------------------------------------------- |
| `TEST_PARALLEL=N\|auto`    | Concurrency level (default: `1`, `auto` = CPU cores / 2) |
| `SKIP_NETWORK_TESTS=true`  | Skip network-dependent tests                             |
| `SKIP_STEAMCMD_TESTS=true` | Skip SteamCMD tests                                      |
| `SKIP_<TEST_NAME>=true`    | Skip a specific test                                     |

## TAP v14 Output

All test output follows the [Test Anything Protocol v14](https://testanything.org/). This enables machine-readable results for VS Code, CI systems, and TAP consumers.

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

Assertions write structured lines to `KGSM_TEST_LOG`:
- `PASS:` / `FAIL:` lines with `[file:LINE in func()]` format
- `ASSERT_DETAIL: expected=X actual=Y` on failures
- `KGSM_ASSERT_STATS: passed/failed/total/skipped` summary marker

These are parsed by `reporting.tap.sh` to produce the YAML diagnostic blocks shown above.

## Configuration (`tests/config.test.ini`)

```ini
TEST_PARALLEL=8                   # Parallel count (1=sequential, auto=cores/2)
TEST_DEFAULT_TIMEOUT=300          # Test timeout (seconds)
SKIP_NETWORK_TESTS=false          # Skip network tests
SKIP_STEAMCMD_TESTS=false         # Skip SteamCMD tests
SKIP_<TEST_NAME>=false            # Skip specific test
```

## Framework Architecture

### Modules

| Module                  | Purpose                                    | Key Functions                                          |
| ----------------------- | ------------------------------------------ | ------------------------------------------------------ |
| **bootstrap.sh**        | Init TEST_ROOT, KGSM_ROOT                  | Auto-sources common.sh                                 |
| **loader.sh**           | Constants (paths, colors, exit codes)      | 40+ exports                                            |
| **common.sh**           | Module orchestrator                        | `__load_module()`                                      |
| **logging.sh**          | Structured logging (DEBUG/INFO/WARN/ERROR) | `log_debug/info/warn/error()`                          |
| **config.sh**           | Load config.test.ini                       | `load_test_config()`                                   |
| **reporting.tap.sh**    | TAP v14 result formatting                  | `__tap_emit_failure_details()`                         |
| **discovery.sh**        | Find/filter tests                          | `discover_tests()`, `should_run_test()`                |
| **sandbox.sh**          | Isolated KGSM copies                       | `create_sandbox()`, `cleanup_sandbox()`                |
| **execution.common.sh** | Test execution engine                      | `execute_test_in_sandbox()`, `__execute_test_inline()` |
| **assert.sh**           | 50+ assertion functions                    | `assert_equals()`, `assert_true()`                     |
| **kgsm.wrapper.sh**     | Test instance management                   | `create_test_instance()`, `remove_test_instance()`     |

### Loading Order

```
bootstrap.sh → loader.sh → common.sh → [
    logging.sh, config.sh, reporting.tap.sh,
    discovery.sh, sandbox.sh, execution.common.sh,
    assert.sh, kgsm.wrapper.sh
]
```

**Principles**: Single responsibility, downward dependencies only, load guards, no peer dependencies.

### Execution Contexts

**Host Context** (framework):
```bash
KGSM_ROOT=/home/user/kgsm
TEST_ROOT=/home/user/kgsm/tests
```

**Sandbox Context** (test):
```bash
KGSM_ROOT=/tmp/kgsm-test-sandboxes/unit_test_12345/  # Isolated copy
TEST_ROOT=/home/user/kgsm/tests                       # Unchanged
KGSM_TEST_SANDBOX=/tmp/kgsm-test-sandboxes/unit_test_12345/
KGSM_TEST_MODE=true
```

Framework unsets KGSM module load flags before context switch, forcing reload with sandbox paths.

## Writing Tests

### Test File Structure

The framework **auto-discovers** `test_*` functions — there is **no `main()` function**. Copy `tests/templates/test.template.sh` for the canonical structure:

```bash
#!/usr/bin/env bash
readonly TEST_NAME="<test_name>"

function setup_test() {
  log_test_step "Setting up tests"
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
}

function test_something() {
  log_test_step "Testing something"
  assert_equals "expected" "$actual" "Values should match"
}

# Optional cleanup
# function cleanup_test() { ... }

# NO main() — framework auto-discovers test_* functions
```

> **Important:** Do NOT add `main()` or `main "$@"`. The framework calls `setup_test()` before tests and `print_assert_summary()` after automatically.

### Available Assertions

```bash
# Basic
assert_equals, assert_not_equals, assert_true, assert_false, assert_null, assert_not_null

# Files
assert_file_exists, assert_dir_exists, assert_file_contains

# Commands
assert_command_succeeds, assert_command_fails

# Strings
assert_string_contains, assert_string_matches, assert_empty, assert_not_empty

# Arrays
assert_array_contains, assert_array_length
```

**Check `tests/framework/assert.sh` for exact functions and their definitions.**

### Utility Functions

#### Logging and Test Control

```bash
# Logging
log_debug/info/warn/error "message"
log_test_step "step_name"

# Test control
skip_test "reason"
pass_test "message"
fail_test "message"
```

#### Test Instance Management (kgsm.wrapper.sh)

The framework provides comprehensive instance management utilities:

```bash
# Automatic instance creation (recommended)
local instance_name
instance_name=$(create_test_instance "factorio")  # Auto-generated name

# Custom instance name
instance_name=$(create_test_instance "factorio" "my_custom_name")

# Custom install directory
instance_name=$(create_test_instance "factorio" "test_instance" "/custom/path")

# Complete instance removal
remove_test_instance "factorio" "$instance_name"
remove_test_instance "factorio" "$instance_name" "/custom/path"  # With custom dir

# Manual prerequisite setup (for edge case testing)
setup_instance_prereqs "factorio" "test_instance" "$TEST_INSTALL_DIR"

# Generate unique test ID
test_id=$(generate_test_id)          # Default prefix: "test"
test_id=$(generate_test_id "custom") # Custom prefix: "custom"
```

**Functions:**
- `create_test_instance <blueprint> [name] [dir]` - Full instance creation with prereqs
- `remove_test_instance <blueprint> <name> [dir]` - Complete cleanup (config + symlink + dirs)
- `setup_instance_prereqs <blueprint> <name> [dir]` - Manual working dir + symlink setup
- `generate_test_id [prefix]` - Generate unique instance name

## VS Code Integration

The KGSM Test Adapter extension (`.vscode/kgsm-test-adapter/`) provides deep integration with VS Code:

- **Test Explorer** — Three-level tree: test type → file → function
- **CodeLens** — "Run" and "Debug" buttons above each `test_*` function
- **Debugging** — Interactive bashdb sessions via `rogalmic.bash-debug`
- **Live updates** — Function ranges update on file save
- **File watching** — Auto-discovery when test files are created or deleted

Under the hood, the extension invokes `tests/run.sh --list-json` for discovery and `tests/run.sh --debug-run <file>` for debugging.

## Debugging

### Interactive Debugging (VS Code — Primary)

1. Open a test file in VS Code
2. Click **Debug** (CodeLens) above any `test_*` function
3. Set breakpoints and step through code with bashdb

The `--debug-run <file>` flag runs the test inline (no subshell) so bashdb can trace execution.

### CLI Debugging

```bash
# Run sequentially for easier output reading
TEST_PARALLEL=1 ./tests/run.sh unit

# Run a single function in isolation
./tests/run.sh --function "test_config_merge" --pattern "config"

# Inline execution for manual bashdb attachment
./tests/run.sh --debug-run tests/unit/test_config_merge_logic.sh
```

### Logs

```bash
# Logs in tests/logs/YYYY-MM-DD_HH-MM-SS/
cat tests/logs/2025-12-22_14-30-45/test_config.log
grep ERROR tests/logs/2025-12-22_14-30-45/*.log
```

**Log format:** `[TIMESTAMP] [LEVEL] [SOURCE:LINE in function()] message`

**Levels:** DEBUG, INFO (default), WARN, ERROR

### Sandbox Inspection

```bash
./tests/run.sh --pattern "my_test"
# Sandbox path shown in output:
# /tmp/kgsm-test-sandboxes/unit_my_test_1734890445_1234

cd /tmp/kgsm-test-sandboxes/unit_my_test_1734890445_1234
ls -la
./kgsm.sh blueprints --list
```

### Common Issues

```bash
# Verify sandbox paths
# Add to test: log_debug "KGSM_ROOT: $KGSM_ROOT"
# Should show sandbox path during execution

# Run sequentially for debugging
TEST_PARALLEL=1 ./tests/run.sh unit

# Skip unavailable dependencies
echo "SKIP_STEAMCMD_TESTS=true" >> tests/config.test.ini
```

## Best Practices

### Test Design

1. **Keep focused**: One test = one behavior
2. **Descriptive names**: `test_instance_creation_fails_with_invalid_blueprint()`
3. **Test failure paths**: Use `assert_command_fails` for expected failures
4. **Meaningful messages**: `assert_equals "8080" "$port" "Port should match blueprint"`

### Performance

1. **Unit tests first**: Fast feedback (<10s total)
2. **Parallel execution**: `TEST_PARALLEL=auto` or `TEST_PARALLEL=8`
3. **Skip expensive tests**: Set `SKIP_LONG_DOWNLOAD_TESTS=true` in CI

### Reliability

1. **No fixed sleeps**: Use `wait_for_file`, `wait_for_port` instead
2. **Clean up resources**: Kill processes, close connections
3. **Retry network ops**: Handle transient failures
4. **Test isolation**: Each test independent, no execution order dependency

## Architecture Principles

1. **Separation of Concerns**: Each module has one job
2. **Dependency Management**: Downward only, no circular, explicit
3. **Context Isolation**: Host vs sandbox contexts clearly separated
4. **Configuration Over Code**: Behavior controlled via config file and env vars
5. **Fail-Safe Design**: Graceful error handling, no resource leaks

## Contributing

### Adding Tests

1. Choose type: unit (<1s), integration (<60s), e2e (minutes)
2. Create file: `tests/unit/test_feature.sh`
3. Copy template: `cp tests/templates/test.template.sh tests/unit/test_feature.sh`
4. Implement `setup_test()` and `test_*` functions (no `main()`)
5. Test: `./tests/run.sh --pattern "feature"`

### Improving Framework

1. Follow bash best practices (shellcheck-compliant)
2. Maintain backward compatibility
3. Add error handling
4. Use appropriate log levels
5. Write tests for framework changes
6. Update documentation

### Code Review Checklist

- [ ] All existing tests pass
- [ ] New tests for new functionality
- [ ] Shellcheck passes
- [ ] Load guards for new modules
- [ ] Functions exported if used in subshells
- [ ] Error handling comprehensive
- [ ] Documentation updated

## Resources

- **Testing Specification**: `docs/specs/testing_specification.md` (required reading)
- **Test Template**: `tests/templates/test.template.sh`
- **Example Tests**: `tests/unit/test_config_merge_logic.sh`
- **VS Code Extension**: `.vscode/kgsm-test-adapter/README.md`

---

The modular architecture ensures framework improvements don't break existing tests. New test types can be added without modifying core framework code.
