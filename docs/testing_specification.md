# KGSM Testing Specification

**Version:** 2.0  
**Last Updated:** December 8, 2025  
**Purpose:** Authoritative reference for writing tests in the KGSM project

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Testing Philosophy](#testing-philosophy)
3. [Test Types](#test-types)
4. [Test Structure](#test-structure)
5. [Writing Tests](#writing-tests)
6. [Assertion Library](#assertion-library)
7. [Exit Codes](#exit-codes)
8. [Best Practices](#best-practices)

---

## Quick Start

### Running Tests

```bash
# Run all tests
./tests/run.sh

# Run specific test type
./tests/run.sh unit|integration|e2e

# Run tests matching pattern
./tests/run.sh --pattern lifecycle

# Debug mode (preserves sandbox)
./tests/run.sh --debug --pattern mytest
```

### Creating a New Test

```bash
# 1. Copy the template
cp tests/templates/test.template.sh tests/unit/test_mymodule_logic.sh

# 2. Edit the file:
#    - Replace <PLACEHOLDERS>
#    - Implement test functions
#    - Update main() to call your functions

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
- ✅ Tests clean up after themselves
- ✅ Use real blueprints from `blueprints/default/`

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
2. Modify permissions with `chmod` to make files unreadable
3. Execute the test operation
4. Restore permissions immediately after the test
5. Clean up in test function, not relying on framework cleanup

**Example:**
```bash
function test_permission_error() {
  log_step "Testing permission denied scenario"
  
  local blueprint_path="$BLUEPRINTS_NATIVE_DEFAULT_DIR/factorio.bp"
  local original_perms=$(stat -c "%a" "$blueprint_path")
  
  # Make unreadable
  chmod 000 "$blueprint_path"
  
  # Test
  __logic_get_blueprint_path "factorio" 2>/dev/null
  local exit_code=$?
  
  # Restore immediately
  chmod "$original_perms" "$blueprint_path"
  
  assert_equals "$exit_code" "$EC_PERMISSION" "Should return permission error"
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

All tests follow this structure (see `tests/templates/test.template.sh`):

```bash
#!/usr/bin/env bash

# KGSM <Description> Tests

# =============================================================================
# TEST SETUP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Framework common functions
source "$SCRIPT_DIR/../framework/common.sh"

# KGSM bootstrapper
source "$KGSM_ROOT/core/bootstrap.sh"

# Test variables
readonly TEST_NAME="<test_name>"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up tests"
  # Test-specific setup
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
}

function test_something() {
  log_step "Testing something"  # REQUIRED: First call in every test
  # Test implementation
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting tests"
  
  setup_test
  test_something
  # ... more tests
  
  log_test "Tests completed"
  
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All tests passed"
  else
    fail_test "Some tests failed"
  fi
}

main "$@"
```

### Required Elements

- **Minimal global code**: Only sourcing and constants at file level
- **All logic in functions**: Every test operation inside a function
- **log_step first**: Every test function MUST start with `log_step`
- **main() entry point**: Single orchestration function
- **Direct execution**: File ends with `main "$@"`

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
  log_step "Setting up <name> tests"
  
  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  
  # Source handlers (for logic tests)
  # source "$KGSM_ROOT/commands/handlers/<module>.sh"
  
  # Verify modules exist (for command tests)
  # assert_file_exists "$MODULE" "Module should exist"
  
  log_test "Environment validated"
}
```

**4. Write test functions:**
```bash
function test_operation_success() {
  log_step "Testing operation with valid input"
  
  # Setup
  local instance
  instance=$(create_test_instance "factorio" "$(generate_test_id)")
  
  # Execute
  __logic_operation "$instance"
  local exit_code=$?
  
  # Assert
  assert_equals "$exit_code" "$EC_SUCCESS_EVENT" \
    "Should return success code"
  
  # Cleanup
  remove_test_instance "$instance"
}
```

**5. Update main():**
```bash
function main() {
  log_test "Starting tests"
  
  setup_test
  test_operation_success
  test_operation_error
  # ... all your tests
  
  log_test "Tests completed"
  
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All tests passed"
  else
    fail_test "Some tests failed"
  fi
}

main "$@"
```

### Common Test Patterns

#### Testing Logic Functions

```bash
function test_logic_success() {
  log_step "Testing __logic_operation with valid parameters"
  
  local instance=$(create_test_instance "factorio" "$(generate_test_id)")
  
  __logic_operation "$instance"
  assert_equals "$?" "$EC_SUCCESS_EVENT" "Should succeed"
  
  remove_test_instance "$instance"
}
```

#### Testing Commands

```bash
function test_command_execution() {
  log_step "Testing 'command' execution"
  
  local instance=$(create_test_instance "factorio" "$(generate_test_id)")
  
  assert_command_succeeds "$MODULE command $instance" \
    "Command should succeed"
  
  local output=$("$MODULE" command "$instance" 2>&1)
  assert_contains "$output" "success" "Should show success message"
  
  remove_test_instance "$instance"
}
```

#### Testing Error Handling

```bash
function test_error_handling() {
  log_step "Testing error with invalid input"
  
  __logic_operation "invalid_input" 2>/dev/null
  assert_equals "$?" "$EC_INVALID_ARG" "Should return error code"
}
```

#### Testing Integration Workflows

```bash
function test_workflow() {
  log_step "Testing workflow: module1 → module2"
  
  # Execute first operation
  local result1=$("$MODULE1" create <args> 2>&1)
  assert_not_null "$result1" "Should create resource"
  
  # Execute second operation using first result
  assert_command_succeeds "$MODULE2 modify $result1" \
    "Should modify created resource"
  
  # Verify final state
  assert_file_exists "$KGSM_ROOT/expected/file" \
    "Expected file should exist"
}
```

#### Testing Complete Workflows (E2E)

```bash
function test_complete_lifecycle() {
  log_step "Testing complete instance lifecycle"
  
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
  
  log_step "Testing with Docker"
  # Test implementation
}
```

---

## Assertion Library

### Basic Assertions

| Function                                      | Description             |
| --------------------------------------------- | ----------------------- |
| `assert_equals <actual> <expected> <msg>`     | Values are equal        |
| `assert_not_equals <actual> <expected> <msg>` | Values are not equal    |
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

1. **Always start with log_step**
   ```bash
   function test_something() {
     log_step "Testing something"  # REQUIRED
     # Test code
   }
   ```

2. **Test success AND failure paths**
   ```bash
   test_operation_success()
   test_operation_missing_arg()
   test_operation_invalid_input()
   ```

3. **Clean up resources**
   ```bash
   local instance=$(create_test_instance ...)
   # ... test code ...
   remove_test_instance "$instance"
   ```

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
4. **Clean up in test functions** - Don't rely on framework cleanup

### Debugging

1. **Use debug mode** - `./tests/run.sh --debug --pattern mytest`
2. **Check logs** - `$KGSM_TEST_LOG` contains detailed output
3. **Inspect sandbox** - Debug mode preserves `/tmp/kgsm-test-sandbox-*/`
4. **Use log_test** - Add debug logging in test functions

---

## Framework Utilities

### Test Instance Management

```bash
# Create test instance
instance=$(create_test_instance "factorio" "$(generate_test_id)")

# Remove test instance
remove_test_instance "$instance"

# Generate unique test ID
test_id=$(generate_test_id)          # Default prefix: "test"
test_id=$(generate_test_id "custom") # Custom prefix: "custom"
```

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
# Pass test (exits with 0)
pass_test "Test passed message"

# Fail test (exits with 1)
fail_test "Test failed message"

# Skip test (exits with 77)
skip_test "Reason for skipping"
```

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
├── run.sh                    # Main test runner
├── README.md                 # Testing documentation
├── templates/
│   └── test.template.sh      # Universal test template
├── framework/
│   ├── runner.sh             # Test orchestrator
│   ├── assert.sh             # Assertion library
│   └── common.sh             # Test utilities
├── unit/                     # Unit tests
├── integration/              # Integration tests
└── e2e/                      # End-to-end tests
```

---

## Troubleshooting

### Common Issues

**Tests fail in sandbox:**
- Verify `KGSM_ROOT` points to sandbox, not real installation
- Check test uses `$KGSM_ROOT` in all paths

**Assertion failures:**
- Use `--debug` to see full output
- Check `$KGSM_TEST_LOG` for detailed logs
- Verify assertion messages are descriptive

**Cleanup issues:**
- Always clean up in test functions, don't rely on framework
- Use `remove_test_instance()` for test instances
- Debug mode preserves sandbox for inspection

**Missing dependencies:**
- Use `require_*()` functions to skip tests gracefully
- Check `is_docker_available()`, `is_steamcmd_available()`

### Getting Help

- Check existing tests in `tests/unit/`, `tests/integration/`, `tests/e2e/`
- Review `tests/framework/common.sh` for available utilities
- See `tests/framework/assert.sh` for all assertion functions
- Look at `test_lifecycle_module.sh` as reference implementation

---

**For complete framework details, see:**
- `tests/README.md` - Testing framework overview
- `tests/framework/assert.sh` - All assertion functions
- `core/errors.sh` - Complete exit code reference
- `docs/testing_framework.md` - Framework implementation details
