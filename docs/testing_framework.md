# KGSM Testing Framework - Functional Overview

This document explains how the KGSM testing framework works at a functional level, covering environment setup, file management, sandboxing, and execution flow.

## High-Level Architecture

The KGSM testing framework is designed around **complete isolation and real code testing**. Every test runs in its own sandboxed environment with a complete copy of KGSM, ensuring no interference between tests and no impact on the host system.

## 1. Environment Setup & Sandboxing

### Complete KGSM Duplication

- **Every test gets its own complete copy of KGSM** - The framework copies the entire KGSM project (`cp -r "$KGSM_ROOT"/* "$sandbox_path/"`) into a temporary sandbox directory
- **Sandbox Location**: `/tmp/kgsm-test-sandbox-<random_id>/<test_type>_<test_name>_<process_id>/`
- **Full Isolation**: Each test runs in complete isolation with its own:
  - KGSM installation
  - Configuration files
  - Modules and scripts
  - Blueprints directory
  - Instances directory
  - Logs directory
  - Templates and overrides

### Test-Specific Configuration

The framework creates a customized `config.ini` for each test by:

1. **Copying** `config.default.ini` to `config.ini` in the sandbox
2. **Appending test overrides** that disable system integration features:
   - `enable_systemd=false` - No systemd integration
   - `enable_firewall_management=false` - No UFW/firewall changes
   - `enable_port_forwarding=false` - No UPnP/port forwarding
   - `enable_event_broadcasting=false` - No external notifications
   - `enable_command_shortcuts=false` - No system-wide shortcuts
3. **Setting sandbox-specific paths**:
   - `default_install_directory=$sandbox_path/instances`
   - Reduced timeouts for faster testing
   - Smaller log sizes to prevent disk bloat

## 2. Test Execution Flow

### Environment Variables

Each test runs with these key environment variables:
- `KGSM_ROOT` - Points to the sandboxed KGSM copy (not the original)
- `KGSM_TEST_SANDBOX` - Path to the current test's sandbox
- `KGSM_TEST_MODE=true` - Indicates running in test mode
- `KGSM_TEST_LOG` - Path to the individual test's log file

### Test Types & Structure

**Unit Tests** (`tests/unit/`)
- Test individual modules in isolation
- Example: `test_instances_module.sh` tests just the `instances.sh` module
- Focus on single component functionality

**Integration Tests** (`tests/integration/`)
- Test interaction between multiple modules
- Example: `test_blueprint_instance_integration.sh` tests how blueprints and instances work together
- Verify module compatibility and data flow

**End-to-End Tests** (`tests/e2e/`)
- Test complete workflows from start to finish
- Example: `test_instance_lifecycle.sh` creates, manages, and removes a complete game server instance
- Simulate real user scenarios

## 3. What Gets Tested

### Real Code, No Mocking

- **Actual KGSM Scripts**: Tests run the real `kgsm.sh` and module scripts
- **Real File Operations**: Creates actual config files, directories, instances
- **Real Command Execution**: Calls actual KGSM commands with real arguments
- **Real Error Handling**: Tests actual error conditions and edge cases

### Test Scope Examples

```bash
# Unit test example - testing instances module directly
"$INSTANCES_MODULE" help
"$INSTANCES_MODULE" list
"$INSTANCES_MODULE" generate-id "factorio.bp"

# Integration test example - testing module interaction
BLUEPRINTS_JSON=$("$BLUEPRINTS_MODULE" list --json)
INSTANCES_JSON=$("$INSTANCES_MODULE" list --json)

# E2E test example - full workflow
TEST_INSTANCE=$("$INSTANCES_MODULE" create "factorio.bp" --name "test_server")
"$INSTANCES_MODULE" info "$TEST_INSTANCE"
"$INSTANCES_MODULE" remove "$TEST_INSTANCE"
```

## 4. Logging & Debugging

### Structured Logging System

The testing framework uses a centralized logging module (`tests/framework/logging.sh`) that provides:

- **Standardized Format**: `[TIMESTAMP] [LEVEL] [SOURCE] message`
- **Log Levels**: DEBUG, INFO, WARN, ERROR with filtering support
- **Dual Output**: Console (colored) and file (plain text)
- **No Duplication**: Each event logged exactly once
- **ANSI Stripping**: Clean, parseable log files
- **Caller Tracking**: Preserves file:line in function() for debugging

#### Log Organization

- **Project-Based Logs**: `tests/logs/YYYY-MM-DD_HH-MM-SS/`
- **Individual Test Logs**: Each test gets its own log file
- **Runner Log**: Overall framework execution log
- **CSV Results**: Machine-readable results for CI/CD integration

#### Log Level Configuration

Set the log level via environment variable:

```bash
# Set log level for test run (default: INFO)
KGSM_TEST_LOG_LEVEL=DEBUG ./tests/run.sh unit

# Or set in config file
export KGSM_TEST_LOG_LEVEL=WARN

# Available levels: DEBUG, INFO, WARN, ERROR
```

**Log Level Behavior:**
- `DEBUG` - Shows all internal operations, fixture creation, detailed trace
- `INFO` - Test steps, assertions, general progress (default)
- `WARN` - Only warnings and errors
- `ERROR` - Only critical errors

#### Example Log Output

```log
[2025-12-15T10:30:45-05:00] [INFO] [test.sh:40 in test_feature()] [STEP] Testing feature foo
[2025-12-15T10:30:45-05:00] [INFO] [test.sh:42 in test_feature()] PASS: Should work correctly
```

### Debug Mode

When `--debug` is used:
- **Sandboxes are preserved** after test completion
- **Log level set to DEBUG** showing all internal operations
- **Detailed output** shows sandbox creation and cleanup
- **Environment inspection** possible by examining preserved sandboxes
- **Full command tracing** with `set -x`

### Log Structure

```
tests/logs/2025-06-21_01-15-39/
├── results.csv                    # Machine-readable results
├── runner.log                     # Main framework log
├── test_simple.log                # Individual test logs
├── test_instances_module.log
└── test_instance_lifecycle.log
```

## 5. Safety & Isolation Features

### Complete Isolation

- **No system modification**: Tests can't affect the host system
- **No cross-test contamination**: Each test gets a fresh KGSM copy
- **Configurable timeouts**: Prevents runaway tests
- **Resource cleanup**: Automatic cleanup of temporary resources

### Test Configuration

- **Skip toggles**: `SKIP_TEST_NAME=true` in `tests/config/test.conf`
- **Pattern filtering**: `--pattern module` to run specific tests
- **Exclude filtering**: `--exclude simple` to skip certain tests
- **Category skipping**: `SKIP_STEAMCMD_TESTS=true` for tests requiring external dependencies

## 6. Framework Components

### Core Files

**`tests/framework/runner.sh`** - Main orchestrator
- Sandbox creation and management
- Test discovery and execution
- Logging and reporting
- Signal handling and cleanup

**`tests/framework/common.sh`** - Shared utilities
- KGSM-specific test functions
- Environment setup helpers
- Wait conditions and timeouts
- Test resource management

**`tests/framework/assert.sh`** - Assertion library
- File system assertions (`assert_file_exists`)
- Command assertions (`assert_command_succeeds`)
- KGSM-specific assertions (`assert_instance_exists`)
- Colored output and detailed error reporting

**`tests/framework/fixtures.sh`** - Test data fixtures
- Mock instance config creation (`create_mock_instance_config`)
- Mock override file generation (`create_mock_override_file`)
- Mock management script creation (`create_mock_management_script`)
- Mock blueprint generation (`create_mock_blueprint`)
- Test resource cleanup utilities (`cleanup_mock_files`)

### Configuration Files

**`tests/config/test.conf`** - Test configuration
- Individual test skip toggles
- Category-based skipping options
- Timeout configurations
- Debug and logging settings

**`tests/run.sh`** - Main entry point
- Dependency validation
- User-friendly interface
- Test execution orchestration

## 7. Example Test Execution

When you run `./tests/run.sh --pattern simple unit`:

1. **Framework startup**: Validates dependencies, loads configuration
2. **Sandbox creation**: Creates `/tmp/kgsm-test-sandbox-<id>/unit_test_simple_<pid>/`
3. **KGSM duplication**: Copies entire KGSM project to sandbox
4. **Config customization**: Creates test-specific `config.ini`
5. **Environment setup**: Sets `KGSM_ROOT` to sandbox path
6. **Test execution**: Runs `tests/unit/test_simple.sh` in sandbox environment
7. **Result logging**: Records results in timestamped log directory
8. **Cleanup**: Removes sandbox (unless `--debug` mode)

### Sandbox Directory Structure

```
/tmp/kgsm-test-sandbox-<id>/unit_test_simple_<pid>/
├── blueprints/           # Complete copy of blueprints
├── config.ini           # Test-specific configuration
├── config.default.ini   # Original default config
├── docs/                # Documentation
├── instances/           # Test instances directory
├── kgsm.sh             # Main KGSM script
├── logs/               # Test logs
├── commands/            # All KGSM modules
├── overrides/          # Override scripts
├── templates/          # Template files
└── tests/              # Test framework (copied but not used)
```

## 8. Running Tests

### Basic Usage

```bash
# Run all tests
./tests/run.sh

# Run specific test types
./tests/run.sh unit
./tests/run.sh integration e2e

# Pattern matching
./tests/run.sh --pattern instance
./tests/run.sh --exclude simple

# Debug mode (preserves sandboxes)
./tests/run.sh --debug

# Verbose output
./tests/run.sh --verbose

# Clean old logs
./tests/run.sh --clean-logs
```

### Test Configuration

Edit `tests/config/test.conf` to customize test behavior:

```bash
# Skip individual tests
SKIP_TEST_SIMPLE=true
SKIP_TEST_INSTANCE_LIFECYCLE=false

# Skip test categories
SKIP_STEAMCMD_TESTS=true
SKIP_DOCKER_TESTS=false

# Timeout settings
DEFAULT_TEST_TIMEOUT=300
STEAMCMD_TEST_TIMEOUT=600
```

## 9. Writing New Tests

### Test Structure

```bash
#!/usr/bin/env bash

# Test header with description
echo "[INFO] Starting my new test"

# Environment validation
if [[ -z "$KGSM_ROOT" ]]; then
    echo "[FAIL] KGSM_ROOT not set"
    exit 1
fi

# Test steps
echo "[STEP] Testing feature X"
if some_test_condition; then
    echo "[PASS] Feature X works"
else
    echo "[FAIL] Feature X failed"
    exit 1
fi

echo "[SUCCESS] Test completed"
exit 0
```

### Using the Framework

Tests can use the common utilities:

```bash
# Source the common framework (automatically done)
# Test utilities are available:

# Run KGSM commands
run_kgsm "help"
run_kgsm "instances list"

# Create test instances
create_test_instance "factorio.bp" "$(generate_test_id)"

# Use assertions
assert_file_exists "$KGSM_ROOT/config.ini"
assert_command_succeeds "$INSTANCES_MODULE help"

# Wait for conditions
wait_for_condition "test -f /some/file" 30 "file creation"

# Create test fixtures
## 10. Test Fixtures System

### Purpose

The fixtures system (`tests/framework/fixtures.sh`) provides reusable helpers for creating test data that closely resembles real KGSM configurations. This reduces code duplication and ensures consistency across tests.

### Available Fixtures

**Instance Configuration**
```bash
# Create a mock instance config file
config_file=$(create_mock_instance_config "instance-name" "/path/to/blueprint.bp")
# Creates: $KGSM_ROOT/instances/<blueprint_name>/<instance-name>.ini
```

**Override Files**
```bash
# Create mock override file with specified functions
override_file=$(create_mock_override_file "factorio" "_get_latest_version" "_download" "_deploy")
# Creates: $OVERRIDES_SOURCE_DIR/factorio.overrides.sh with valid bash functions
```

**Management Scripts**
```bash
## 12. Troubleshootingript with placeholder functions
mgmt_script=$(create_mock_management_script "/path/to/manage.sh" "_get_latest_version" "_download")
# Creates executable script with stub functions
```

**Blueprints**
```bash
# Create minimal blueprint file
blueprint_file=$(create_mock_blueprint "mygame" "native")
# Creates: $KGSM_ROOT/blueprints/native/custom/mygame.bp

# Or for container blueprints
blueprint_file=$(create_mock_blueprint "mygame" "container")
# Creates: $KGSM_ROOT/blueprints/container/custom/mygame.docker-compose.yml
```

**Cleanup**
```bash
# Clean up multiple fixtures at once
cleanup_mock_files "$config_file" "$override_file" "$mgmt_script" "$blueprint_file"

# Also remove parent directories if needed
rm -rf "$(dirname "$config_file")"
```

### Design Philosophy

- **Real data over mocks**: Use actual blueprints (e.g., `factorio.bp`) when available
- **Minimal but valid**: Generated fixtures contain only essential fields
- **Self-contained**: Each fixture function returns the path to the created resource
- **Explicit cleanup**: Tests are responsible for cleaning up fixtures they create

### Best Practices

1. **Use real blueprints when possible**
   ```bash
   # Prefer this
   blueprint_file="$KGSM_ROOT/blueprints/native/default/factorio.bp"
   
   # Over this (unless testing edge cases)
   blueprint_file=$(create_mock_blueprint "testgame" "native")
   ```

2. **Clean up in the same function that creates fixtures**
   ```bash
   function test_something() {
     local config=$(create_mock_instance_config "test" "$blueprint")
     
     # ... test code ...
     
     cleanup_mock_files "$config"
     rm -rf "$(dirname "$config")"
   }
   ```

3. **Keep fixtures minimal**
   - Only create what's needed for the specific test
   - Use fixture functions instead of inline file creation
   - Avoid complex setups when simple ones suffice

## 11. Benefits of This Approach

This testing framework design ensures:

- ✅ **Tests are completely isolated** from each other and the host system
- ✅ **Real KGSM code is tested** without mocking or simulation
- ✅ **Test environments are reproducible** and consistent
- ✅ **Debugging is straightforward** with preserved sandboxes and detailed logs
- ✅ **Framework is safe to run** without system modification risks
- ✅ **Comprehensive coverage** from unit to end-to-end testing
- ✅ **CI/CD integration** with machine-readable results
- ✅ **Developer-friendly** with colored output and verbose modes

The framework essentially creates a "virtual KGSM installation" for each test, allowing comprehensive testing of real functionality while maintaining complete safety and isolation.

## 11. Troubleshooting

### Common Issues

**Tests hanging or timing out**
- Check `tests/config/test.conf` timeout settings
- Use `--debug` mode to inspect sandbox state
- Check individual test logs in `tests/logs/`

**Sandbox cleanup issues**
- Sandboxes are preserved in debug mode by design
- Use `find /tmp -name "kgsm-test-sandbox-*" -type d` to locate them
- Manual cleanup: `rm -rf /tmp/kgsm-test-sandbox-*`

**Permission errors**
- Ensure test user has write access to `/tmp`
- Check that KGSM scripts have execute permissions
- Verify no readonly files in the source directory

**Test failures**
- Use `--verbose` mode for detailed error output
- Check individual test logs for specific failure reasons
- Use `--debug` to preserve sandbox for manual inspection

### Getting Help

- Check `tests/README.md` for detailed usage instructions
- Use `./tests/run.sh --help` for command-line options
- Examine existing tests as examples for writing new ones
- Review framework source code in `tests/framework/` for advanced usage
