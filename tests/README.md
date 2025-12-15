# KGSM Test Framework

A comprehensive, robust testing framework for the Krystal Game Server Manager (KGSM) designed to ensure reliability, maintainability, and quality of the codebase.

## Overview

This testing framework provides three levels of testing:

- **Unit Tests**: Fast tests that verify individual functions and modules in isolation
- **Integration Tests**: Medium-speed tests that verify interactions between modules
- **End-to-End Tests**: Comprehensive tests that verify complete workflows with real game servers

## Key Features

### 🔒 **Sandboxed Environments**
- Each test runs in a completely isolated copy of KGSM
- No test can interfere with another or with your main KGSM installation
- Automatic cleanup after test completion (unless debugging)

### 🎯 **Real Code Testing**
- No mocking or stubbing - tests use actual KGSM code
- Tests with real game servers (Factorio, Necesse, V Rising)
- Authentic testing conditions for maximum confidence

### 📊 **Comprehensive Reporting**
- Colored console output for easy reading
- Detailed test logs with timestamps (saved in `tests/logs/`)
- CSV results file for analysis
- Pass/fail/skip counters with summary

### ⚙️ **Flexible Configuration**
- Easy test skipping via configuration
- Pattern-based test filtering
- Debug mode for troubleshooting
- Configurable timeouts and behavior

### 🚀 **Performance Optimized**
- Parallel test execution support
- Minimal dependencies
- Fast unit tests for rapid feedback
- Longer E2E tests for thorough validation

## Quick Start

### Prerequisites

**Required:**
- Bash 4.0+
- Standard Unix utilities: `grep`, `find`, `mktemp`, `date`, `tar`, `sed`, `coreutils`

**Optional (enables additional tests):**
- `jq` - JSON processing (for enhanced output formatting)
- `steamcmd` - Steam game server downloads
- `docker` - Container-based game servers
- `wget` - Network operations
- `unzip` - Archive extraction

### Running Tests

```bash
# Run all tests
./tests/run.sh

# Run only unit tests (fast)
./tests/run.sh unit

# Run with debug mode (preserves test environments)
./tests/run.sh --debug

# Run tests matching a pattern
./tests/run.sh --pattern "instance"

# List available tests
./tests/run.sh --list

# Get help
./tests/run.sh --help
```

## Test Types

### Unit Tests (`tests/unit/`)

Fast tests that verify individual components:

- **Module Testing**: Each KGSM module is tested in isolation
- **Function Testing**: Individual functions are validated
- **Input Validation**: Argument parsing and error handling
- **Configuration**: Config file parsing and validation

Example:
```bash
# Run only unit tests
./tests/run.sh unit

# Run specific unit test
./tests/run.sh --pattern "instances_module"
```

### Integration Tests (`tests/integration/`)

Medium-speed tests that verify module interactions:

- **Blueprint Loading**: Integration between blueprint and instance modules
- **Configuration Management**: Config consistency across modules
- **File Operations**: Directory and file management integration
- **Error Propagation**: How errors flow between components

Example:
```bash
# Run integration tests
./tests/run.sh integration

# Run blueprint-related integration tests
./tests/run.sh --pattern "blueprint"
```

### End-to-End Tests (`tests/e2e/`)

Comprehensive tests with real game servers:

- **Server Lifecycle**: Complete install → start → operate → stop → remove
- **Game Server Tests**: Factorio, Necesse, V Rising server testing
- **Backup/Restore**: Full backup and restoration workflows
- **Update Management**: Server update processes

Example:
```bash
# Run E2E tests (requires network and time)
./tests/run.sh e2e

# Run only Factorio E2E tests
./tests/run.sh --pattern "factorio"
```

## Configuration

### Test Configuration (`tests/config/test.conf`)

Customize test behavior by editing the configuration file:

```bash
# Skip individual tests
SKIP_FACTORIO_TESTS=true
SKIP_LONG_DOWNLOAD_TESTS=true

# Configure timeouts
TEST_DEFAULT_TIMEOUT=300
TEST_SERVER_STARTUP_TIMEOUT=120

# Set log level (DEBUG|INFO|WARN|ERROR)
export KGSM_TEST_LOG_LEVEL=INFO  # Default is INFO

# Select test games
TEST_GAMES="factorio necesse"
```

### Skipping Tests

Skip specific tests by setting environment variables:

```bash
# Skip by test name
export SKIP_INSTANCE_CREATION=true

# Skip by category
export SKIP_STEAMCMD_TESTS=true
export SKIP_DOCKER_TESTS=true
export SKIP_NETWORK_TESTS=true
```

## Framework Architecture

### Core Components

```
tests/
├── framework/          # Test framework core
│   ├── runner.sh      # Main test orchestrator
│   ├── assert.sh      # Assertion library
│   └── common.sh      # Shared utilities
├── config/            # Test configuration
│   └── test.conf      # Main config file
├── unit/              # Unit tests
├── integration/       # Integration tests
├── e2e/               # End-to-end tests
├── run.sh            # Main entry point
└── README.md         # This documentation
```

### Writing Tests

Create a new test file:

```bash
#!/usr/bin/env bash

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="my_new_test"

setup_test() {
    log_step "Setting up my test"
    # Test setup code here
}

test_something() {
    log_step "Testing something important"

    # Use assertions
    assert_equals "expected" "actual" "Values should match"
    assert_file_exists "/path/to/file" "File should exist"
    assert_command_succeeds "some_command" "Command should work"

    log_test "Test completed"
}

main() {
    setup_test
    test_something

    if print_assert_summary "$TEST_NAME"; then
        pass_test "All tests passed"
    else
        fail_test "Some tests failed"
    fi
}

main "$@"
```

### Available Assertions

```bash
# Basic assertions
assert_equals "expected" "actual" "message"
assert_not_equals "unexpected" "actual" "message"
assert_true "$condition" "message"
assert_false "$condition" "message"
assert_null "$value" "message"
assert_not_null "$value" "message"

# File system assertions
assert_file_exists "/path/to/file" "message"
assert_dir_exists "/path/to/dir" "message"

# Command assertions
assert_command_succeeds "command" "message"
assert_command_fails "command" "message"

# KGSM-specific assertions
assert_kgsm_succeeds "args" "message"
assert_instance_exists "instance_name" "message"
```

### Utility Functions

```bash
# Logging (centralized logging system)
log_debug "message"         # Log at DEBUG level (internal details)
log_info "message"          # Log at INFO level (general info)
log_warn "message"          # Log at WARN level (warnings)
log_error "message"         # Log at ERROR level (errors)
log_step "step_name"        # Log test step (INFO level with marker)
log_test "message"          # Legacy: logs at DEBUG level

# Test management
skip_test "reason"          # Skip current test
pass_test "message"         # Mark test as passed
fail_test "message"         # Mark test as failed

# KGSM operations
run_kgsm "args"            # Run KGSM command
create_test_instance "blueprint" "id"
remove_test_instance "name"
instance_exists "name"

# Waiting utilities
wait_for_condition "condition" timeout interval
wait_for_file "/path" timeout
wait_for_port "host" port timeout
```

## Debugging Tests

### Debug Mode

Enable debug mode to preserve test environments:

```bash
./tests/run.sh --debug unit
```

This will:
- Preserve sandbox directories after test completion
- Show debug output during execution
- Set log level to DEBUG (shows all internal operations)
- Enable verbose logging
- Display sandbox paths for manual inspection

### Log Format

The testing framework uses a standardized log format across all logs:

```
[TIMESTAMP] [LEVEL] [SOURCE] message
```

**Example log entries:**
```
[2025-12-15T10:30:45-05:00] [INFO] [test_example.sh:42 in test_function()] Testing feature X
[2025-12-15T10:30:45-05:00] [ERROR] [test_example.sh:45 in test_function()] FAIL: Expected value did not match
[2025-12-15T10:30:46-05:00] [DEBUG] [fixtures.sh:62 in create_mock_config()] Created mock config: /tmp/test.ini
```

**Log Levels:**
- `DEBUG` - Internal operations, fixture creation, detailed trace
- `INFO` - Test steps, assertions, general progress
- `WARN` - Non-critical issues, deprecated usage
- `ERROR` - Test failures, critical errors

**Benefits:**
- No duplicate log entries (each event logged once)
- No ANSI escape codes in log files (clean, parseable)
- Caller information preserved (file:line in function())
- Consistent timestamp format (ISO 8601 with timezone)
- Easy to grep and filter by level

### Examining Test Logs

Test logs are saved to timestamped directories in the project:

```bash
# Logs are automatically saved to tests/logs/
./tests/run.sh

# Example log locations (YYYY-MM-DD_HH-MM-SS format)
tests/logs/2025-06-21_01-15-39/runner.log          # Main runner log
tests/logs/2025-06-21_01-15-39/test_name.log       # Individual test log
tests/logs/2025-06-21_01-15-39/results.csv         # Results summary

# Clean up old logs (keeps last 10)
./tests/run.sh --clean-logs
```

### Manual Testing

Inspect preserved sandbox environments:

```bash
# Run with debug mode
./tests/run.sh --debug --pattern "my_test"

# Sandbox location will be shown in output
# Example: /tmp/kgsm-test-sandbox-XXXXXX/unit_my_test_12345

# Navigate to sandbox
cd /tmp/kgsm-test-sandbox-XXXXXX/unit_my_test_12345

# Examine the isolated KGSM environment
ls -la
./kgsm.sh --help
```

## Best Practices

### Test Design

1. **Keep tests focused**: Each test should verify one specific behavior
2. **Use descriptive names**: Test names should clearly indicate what they verify
3. **Include setup/teardown**: Properly initialize and clean up test environments
4. **Handle dependencies**: Check for required tools and skip gracefully if unavailable
5. **Test error conditions**: Verify that failures are handled correctly

### Performance

1. **Start with unit tests**: Fast feedback loop for development
2. **Use integration tests selectively**: Focus on critical interactions
3. **Reserve E2E for workflows**: Test complete user scenarios
4. **Skip expensive tests in CI**: Use configuration to control test execution

### Reliability

1. **Avoid timing dependencies**: Use proper wait conditions instead of fixed sleeps
2. **Clean up resources**: Ensure tests don't leave artifacts behind
3. **Handle network failures**: Make network-dependent tests resilient
4. **Test in isolation**: Don't depend on other tests or shared state

## Troubleshooting

### Common Issues

**Tests fail to start:**
```bash
# Check dependencies
./tests/run.sh --help

# Verify framework files
ls -la tests/framework/
```

**SteamCMD tests fail:**
```bash
# Check SteamCMD installation
which steamcmd
steamcmd +quit

# Skip SteamCMD tests if unavailable
export SKIP_STEAMCMD_TESTS=true
```

**Timeout issues:**
```bash
# Increase timeouts in config
# Edit tests/config/test.conf
TEST_DEFAULT_TIMEOUT=600
TEST_SERVER_STARTUP_TIMEOUT=180
```

**Permission errors:**
```bash
# Ensure scripts are executable
chmod +x tests/run.sh
chmod +x tests/framework/*.sh
```

### Getting Help

1. **Check test logs**: Look in the temporary log directories
2. **Use debug mode**: Run with `--debug` to preserve environments
3. **Enable verbose output**: Use `--verbose` for detailed information
4. **Review configuration**: Check `tests/config/test.conf` for relevant settings

## Contributing

### Adding New Tests

1. Choose the appropriate test type (unit/integration/e2e)
2. Create a new file following the naming convention: `test_feature_name.sh`
3. Use the test template and assertion framework
4. Add configuration options if needed
5. Test your test with debug mode
6. Update documentation if adding new features

### Improving the Framework

1. Follow bash best practices and SOLID principles
2. Maintain backward compatibility when possible
3. Add comprehensive error handling
4. Include detailed logging
5. Write tests for framework components
6. Update documentation for any changes

The KGSM test framework is designed to grow with the project while maintaining reliability and ease of use. Happy testing!
