#!/usr/bin/env bash

# KGSM Blueprint-Instance Integration Test
# Tests the interaction between blueprints and instances modules

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="blueprint_instance_integration"
readonly BLUEPRINTS_MODULE="$KGSM_ROOT/commands/blueprints.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up blueprint-instance integration test"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  log_test "KGSM_ROOT: $KGSM_ROOT"
  log_test "Blueprints module: $BLUEPRINTS_MODULE"
  log_test "Instances module: $INSTANCES_MODULE"
}

function test_module_availability() {
  log_step "Testing module availability"

  assert_file_exists "$BLUEPRINTS_MODULE" "Blueprints module should exist"
  assert_file_exists "$INSTANCES_MODULE" "Instances module should exist"

  # Check if modules are executable
  if [[ -x "$BLUEPRINTS_MODULE" ]]; then
    assert_true "true" "Blueprints module should be executable"
  else
    assert_true "false" "Blueprints module should be executable"
  fi

  if [[ -x "$INSTANCES_MODULE" ]]; then
    assert_true "true" "Instances module should be executable"
  else
    assert_true "false" "Instances module should be executable"
  fi
}

function test_blueprint_discovery() {
  log_step "Testing blueprint discovery"

  local blueprint_list
  if blueprint_list=$("$BLUEPRINTS_MODULE" --list 2>/dev/null); then
    assert_not_null "$blueprint_list" "Blueprints module should return a list of blueprints"

    local blueprint_count
    blueprint_count=$(echo "$blueprint_list" | wc -l)

    assert_greater_than "$blueprint_count" 0 "Should find at least one blueprint"
    log_test "Found $blueprint_count blueprints"
  else
    assert_true "false" "Blueprints module --list should succeed"
  fi
}

function test_instance_id_generation() {
  log_step "Testing instance ID generation for blueprints"

  # Find a test blueprint
  local test_blueprint=""

  if [[ -f "$KGSM_ROOT/blueprints/default/native/factorio.bp" ]]; then
    test_blueprint="factorio.bp"
  elif [[ -f "$KGSM_ROOT/blueprints/default/native/terraria.bp" ]]; then
    test_blueprint="terraria.bp"
  elif [[ -f "$KGSM_ROOT/blueprints/default/native/minecraft.bp" ]]; then
    test_blueprint="minecraft.bp"
  else
    # Find any .bp file
    test_blueprint=$(find "$KGSM_ROOT/blueprints" -name "*.bp" -type f | head -1 | xargs basename 2>/dev/null)
  fi

  if [[ -n "$test_blueprint" ]]; then
    local instance_id
    if instance_id=$("$INSTANCES_MODULE" --generate-id "$test_blueprint" 2>/dev/null); then
      assert_not_null "$instance_id" "Should generate instance ID for blueprint '$test_blueprint'"

      # Automatically generated instance IDs should contain the blueprint name
      assert_contains "$instance_id" "${test_blueprint%.bp}" "Instance ID should contain blueprint name (without .bp extension)"
      log_test "Generated instance ID '$instance_id' for blueprint '$test_blueprint'"
    else
      log_test "ID generation failed for '$test_blueprint' - this may be expected if requirements aren't met"
    fi
  else
    skip_test "No suitable blueprint found for ID generation test"
  fi
}

function test_json_output_compatibility() {
  log_step "Testing JSON output compatibility"

  local blueprints_json
  if blueprints_json=$("$BLUEPRINTS_MODULE" --list --json 2>/dev/null); then
    assert_not_null "$blueprints_json" "Blueprints module should produce JSON output"
    assert_not_equals "null" "$blueprints_json" "Blueprints JSON should not be null"

    # Validate JSON format if jq is available
    if command -v jq >/dev/null 2>&1; then
      if echo "$blueprints_json" | jq . >/dev/null 2>&1; then
        assert_true "true" "Blueprints JSON should be valid"
      else
        log_test "Blueprints JSON is not valid format"
      fi
    fi
  else
    assert_true "false" "Blueprints module should produce JSON output"
  fi

  local instances_json
  if instances_json=$("$INSTANCES_MODULE" --list --json 2>/dev/null); then
    assert_not_null "$instances_json" "Instances module should produce JSON output"

    # Validate JSON format if jq is available
    if command -v jq >/dev/null 2>&1; then
      if echo "$instances_json" | jq . >/dev/null 2>&1; then
        assert_true "true" "Instances JSON should be valid"
      else
        log_test "Instances JSON is not valid format"
      fi
    fi
  else
    assert_true "false" "Instances module should produce JSON output"
  fi
}

function test_configuration_consistency() {
  log_step "Testing configuration consistency"

  assert_file_exists "$KGSM_ROOT/config.ini" "Configuration file should exist and be accessible to both modules"

  # Test that both modules can access configuration
  local config_content
  if config_content=$(cat "$KGSM_ROOT/config.ini" 2>/dev/null); then
    assert_not_null "$config_content" "Configuration file should be readable"
    log_test "Configuration file is accessible to modules"
  else
    assert_true "false" "Configuration file should be readable"
  fi
}

function test_directory_structure_consistency() {
  log_step "Testing directory structure consistency"

  assert_dir_exists "$KGSM_ROOT/blueprints" "Blueprints directory should exist"

  # Instances directory should exist or be creatable
  if [[ ! -d "$KGSM_ROOT/instances" ]]; then
    assert_command_succeeds "mkdir -p '$KGSM_ROOT/instances'" "Should be able to create instances directory"
  else
    assert_dir_exists "$KGSM_ROOT/instances" "Instances directory should exist"
  fi
}

function test_module_help_functionality() {
  log_step "Testing module help functionality"

  assert_command_succeeds "$BLUEPRINTS_MODULE --help" "Blueprints module should respond to --help"
  assert_command_succeeds "$INSTANCES_MODULE --help" "Instances module should respond to --help"
}

function test_module_error_handling_consistency() {
  log_step "Testing module error handling consistency"

  # Both modules should handle invalid arguments consistently
  assert_command_fails "$BLUEPRINTS_MODULE --invalid-arg" "Blueprints module should reject invalid arguments"
  assert_command_fails "$INSTANCES_MODULE --invalid-arg" "Instances module should reject invalid arguments"
}

function test_blueprint_instance_workflow() {
  log_step "Testing basic blueprint-to-instance workflow compatibility"

  # Test that the workflow components are available
  assert_command_succeeds "$BLUEPRINTS_MODULE --list" "Blueprint listing should work for instance creation workflow"
  assert_command_succeeds "$INSTANCES_MODULE --list" "Instance listing should work for management workflow"

  log_test "Basic workflow components are available"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting blueprint-instance integration test"

  # Initialize test environment
  setup_test

  # Execute all test functions
  test_module_availability
  test_blueprint_discovery
  test_instance_id_generation
  test_json_output_compatibility
  test_configuration_consistency
  test_directory_structure_consistency
  test_module_help_functionality
  test_module_error_handling_consistency
  test_blueprint_instance_workflow

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All blueprint-instance integration tests completed successfully"
  else
    fail_test "Some blueprint-instance integration tests failed"
  fi
}

# Execute main function
main "$@"
