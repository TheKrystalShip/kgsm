---
name: create-test
description: "Create a new KGSM test file. Use when: adding tests for a module, writing unit/integration/E2E tests, creating test coverage for new or existing features, or adding test functions to the testing framework."
argument-hint: "Module name and test type (e.g., 'lifecycle unit logic' or 'config integration')"
---

# Create KGSM Test

Guided workflow for creating new test files in the KGSM testing framework. Delegates all implementation to the `@testing` agent.

## When to Use

- Adding test coverage for a new or existing module
- Creating unit tests (logic layer or command layer)
- Creating integration tests between two modules
- Creating E2E tests for complete workflows
- Adding test functions to an existing test file

## Procedure

### 1. Determine Test Parameters

Identify these from the user's request or ask if unclear:

| Parameter      | Options                                                   | Example     |
| -------------- | --------------------------------------------------------- | ----------- |
| **Module**     | Any KGSM module in `commands/`                            | `lifecycle` |
| **Test Type**  | `unit`, `integration`, `e2e`                              | `unit`      |
| **Test Layer** | `logic` (handlers), `commands` (CLI)                      | `logic`     |
| **Blueprints** | `factorio`, `terraria`, `starbound`, `necesse`, `vrising` | `factorio`  |

### 2. Determine the File Name

Apply naming conventions:

| Type         | Pattern                                   | Directory            |
| ------------ | ----------------------------------------- | -------------------- |
| Logic Unit   | `test_<module>_logic.sh`                  | `tests/unit/`        |
| Command Unit | `test_<module>_commands.sh`               | `tests/unit/`        |
| Integration  | `test_<module1>_<module2>_integration.sh` | `tests/integration/` |
| E2E          | `test_<workflow>_e2e.sh`                  | `tests/e2e/`         |

### 3. Check for Existing Tests

Before creating, verify no test already exists:

```bash
ls tests/unit/test_<module>_*.sh
ls tests/integration/test_<module>_*.sh
ls tests/e2e/test_<module>_*.sh
```

If a test file already exists, add functions to it rather than creating a new one.

### 4. Delegate to @testing

Invoke the `@testing` agent as a subagent with a prompt that includes:

- **Module name** and path (`commands/<module>.sh`, `commands/handlers/<module>.sh`)
- **Test type and layer** (unit logic, unit commands, integration, e2e)
- **Target file path** (determined in step 2)
- **What to test** — specific functions, behaviors, error cases
- **Blueprints to use** — which real blueprints to test with
- **Context gathered** — any module code or behavior you've already examined

Example delegation prompt:
> Create a unit logic test for the `network` module.
> - File: `tests/unit/test_network_logic.sh`
> - Handler: `commands/handlers/network.sh`
> - Test the `__logic_check_port` and `__logic_get_public_ip` functions
> - Use the `factorio` blueprint for instance-dependent tests
> - Test success cases, missing argument errors, and invalid input errors

### 5. Verify

After `@testing` creates the test, run it:

```bash
./tests/run.sh --pattern '<test_name>'
```

## Quick Reference

### Test Structure (No main!)

```bash
#!/usr/bin/env bash
readonly TEST_NAME="<test_name>"

function setup_test() {
  log_test_step "Setting up tests"
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
}

function test_operation_succeeds() {
  log_test_step "Testing operation with valid input"
  # arrange, act, assert
}

# NO main() — framework auto-discovers test_* functions
```

### Key Rules

- Every `test_*()` starts with `log_test_step`
- Use real blueprints, not synthetic fixtures
- Test both success AND failure paths
- Clean up instances with `remove_test_instance`
- No mocking (except system services)

### Available Assertions

Read `tests/framework/assert.sh` for the complete, always-up-to-date list of assertion functions.

### Running Tests

```bash
./tests/run.sh                          # All tests
./tests/run.sh unit                     # Unit tests only
./tests/run.sh --pattern "module_name"  # Filter by name
./tests/run.sh --function "test_func"   # Single function
```
