# KGSM Test Framework

Modular, sandboxed testing framework for KGSM. Follows **bootstrap → loader → common → specialized modules** pattern.

## Quick Start

```bash
./tests/run.sh                    # All tests
./tests/run.sh unit               # Unit tests only (fast)
./tests/run.sh --pattern "config" # Filter by name
./tests/run.sh --parallel 4       # 4 concurrent tests
./tests/run.sh --debug            # Preserve sandboxes
./tests/run.sh --failed           # Re-run tests that failed last time
```

## Configuration (`tests/config.test.ini`)

```ini
TEST_PARALLEL=8                   # Parallel count (1=sequential)
TEST_DEFAULT_TIMEOUT=300          # Test timeout (seconds)
SKIP_NETWORK_TESTS=false          # Skip network tests
SKIP_STEAMCMD_TESTS=false         # Skip SteamCMD tests
SKIP_<TEST_NAME>=false            # Skip specific test
```

## Framework Architecture

### Modules

| Module           | Purpose                                    | Key Functions                       |
| ---------------- | ------------------------------------------ | ----------------------------------- |
| **bootstrap.sh** | Init TEST_ROOT, KGSM_ROOT                  | Auto-sources common.sh              |
| **loader.sh**    | Constants (paths, colors, exit codes)      | 40+ exports                         |
| **common.sh**    | Module orchestrator                        | __load_module()                     |
| **config.sh**    | Load config.test.ini                       | load_test_config()                  |
| **sandbox.sh**   | Isolated KGSM copies                       | create_sandbox(), cleanup_sandbox() |
| **discovery.sh** | Find/filter tests                          | discover_tests(), should_run_test() |
| **execution.sh** | Sequential/parallel delegation             | execute_tests()                     |
| **reporting.sh** | Results and summaries                      | generate_summary()                  |
| **logging.sh**     | Structured logging (DEBUG/INFO/WARN/ERROR) | log_debug/info/warn/error()         |
| **assert.sh**      | 50+ assertion functions                    | assert_equals(), assert_true()      |
| **kgsm.wrapper.sh** | Test instance management                   | create_test_instance(), remove_test_instance() |
| **runner.sh**      | Main orchestrator                          | Coordinate all phases               |

### Loading Order

```
bootstrap.sh → loader.sh → common.sh → [
    logging.sh, config.sh, reporting.sh,
    discovery.sh, sandbox.sh, execution.sh,
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

**Check `tests/templates/test.template.sh` for an exact structure of a test file.**

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

## Debugging

### Debug Mode

```bash
./tests/run.sh --debug unit
```

**Provides:**
- Preserved sandboxes (not deleted)
- Verbose output (all log levels)
- Module load status
- Execution trace (file:line:function)

### Logs

```bash
# Logs in tests/logs/YYYY-MM-DD_HH-MM-SS/
cat tests/logs/2025-12-22_14-30-45/test_config.log
grep ERROR tests/logs/2025-12-22_14-30-45/*.log
```

**Log format:** `[TIMESTAMP] [LEVEL] [SOURCE:LINE in function()] message`

**Levels:** DEBUG (TEST_DEBUG=true only), INFO (default), WARN, ERROR

### Failed Test Re-runs

The framework automatically tracks test results and allows re-running only failed tests:

```bash
# Re-run tests that failed in the most recent run
./tests/run.sh --failed

# Re-run failed tests from a specific results file
./tests/run.sh --failed tests/logs/2026-01-30_16-26-11/results.csv
```

**How it works:**
- After each test run, a `tests/logs/latest` symlink points to the most recent results
- The `--failed` flag reads the `results.csv` file and filters for tests with non-zero exit codes
- If no tests failed, prints success message and exits
- Compatible with other flags: `./tests/run.sh --failed --debug --parallel 4`

**Use cases:**
- Quick iteration when fixing failing tests
- CI/CD pipelines for flaky test detection
- Performance optimization (skip passing tests during development)

### Sandbox Inspection

```bash
./tests/run.sh --debug --pattern "my_test"
# Sandbox path shown in output:
# /tmp/kgsm-test-sandboxes/unit_my_test_1734890445_1234

cd /tmp/kgsm-test-sandboxes/unit_my_test_1734890445_1234
ls -la
./kgsm.sh blueprints --list
```

### Common Issues

```bash
# Check dependencies
./tests/run.sh --help

# Framework module loading
./tests/run.sh --debug --pattern "simple" 2>&1 | grep "loaded"

# Verify sandbox paths
# Add to test: log_debug "KGSM_ROOT: $KGSM_ROOT"
# Should show sandbox path during execution

# Run sequentially for debugging
TEST_PARALLEL=1 ./tests/run.sh unit

# Re-run only failed tests from last run
./tests/run.sh --failed

# Re-run failed tests from specific results file
./tests/run.sh --failed tests/logs/2026-01-30_16-26-11/results.csv

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
2. **Parallel execution**: `TEST_PARALLEL=8` or `--parallel 8`
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
4. **Configuration Over Code**: Behavior controlled via config file
5. **Fail-Safe Design**: Graceful error handling, no resource leaks

## Contributing

### Adding Tests

1. Choose type: unit (<1s), integration (<60s), e2e (minutes)
2. Create file: `tests/unit/test_feature.sh`
3. Copy template: `cp tests/templates/test.template.sh tests/unit/test_feature.sh`
4. Follow structure (see Writing Tests section)
5. Test with debug: `./tests/run.sh --debug --pattern "feature"`

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

- **Testing Specification**: `docs/testing_specification.md` (required reading)
- **Architecture Spec**: `docs/testing_framework_refactoring_specification.md`
- **Test Template**: `tests/templates/test.template.sh`
- **Example Tests**: `tests/unit/test_config_merge_logic.sh`

---

The modular architecture ensures framework improvements don't break existing tests. New test types can be added without modifying core framework code.
