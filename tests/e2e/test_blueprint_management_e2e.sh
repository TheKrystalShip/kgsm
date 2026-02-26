#!/usr/bin/env bash

# KGSM Blueprint Management End-to-End Tests
#
# Test Type: E2E
# Target: Complete blueprint discovery and management workflow
#
# Covers the full blueprint management workflow:
# - Blueprint listing (all, native-only, container-only, default, custom)
# - Blueprint finding (native and container)
# - Blueprint info retrieval and field validation
# - Standard test blueprints: factorio, terraria, starbound, necesse (native), vrising (container)
# - Error handling for invalid/missing blueprints
# - Cross-blueprint consistency checks
# - Native and container submodule direct access

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="blueprint_management_e2e"
readonly MODULE="$KGSM_ROOT/commands/blueprints.sh"
readonly NATIVE_MODULE="$KGSM_ROOT/commands/blueprints.native.sh"
readonly CONTAINER_MODULE="$KGSM_ROOT/commands/blueprints.container.sh"

# Standard test blueprints per testing specification
readonly NATIVE_BLUEPRINTS=("factorio" "terraria" "starbound" "necesse")
readonly CONTAINER_BLUEPRINTS=("vrising")

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up blueprint management e2e tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  assert_file_exists "$MODULE" "blueprints.sh should exist"
  assert_file_executable "$MODULE" "blueprints.sh should be executable"

  assert_file_exists "$NATIVE_MODULE" "blueprints.native.sh should exist"
  assert_file_executable "$NATIVE_MODULE" "blueprints.native.sh should be executable"

  assert_file_exists "$CONTAINER_MODULE" "blueprints.container.sh should exist"
  assert_file_executable "$CONTAINER_MODULE" "blueprints.container.sh should be executable"

  # Verify blueprint directories exist
  assert_dir_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR" \
    "Native blueprints directory should exist"
  assert_dir_exists "$KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR" \
    "Container blueprints directory should exist"

  # Verify standard test blueprints exist on disk
  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/${bp}.bp" \
      "Standard native blueprint '${bp}' should exist"
  done

  for bp in "${CONTAINER_BLUEPRINTS[@]}"; do
    assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR/${bp}.docker-compose.yml" \
      "Standard container blueprint '${bp}' should exist"
  done

  log_test_step "Blueprint management e2e environment validated"
}

# =============================================================================
# WORKFLOW 1: List all blueprints
# Verify the list command returns results and includes all known blueprints
# =============================================================================

function test_list_all_blueprints() {
  log_test_step "Workflow: list all blueprints returns results with known blueprints"

  local output
  output=$("$MODULE" list 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints list should succeed"
  assert_not_null "$output" "blueprints list should produce output"

  # All standard native blueprints must appear
  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    assert_contains "$output" "$bp" \
      "blueprints list should include native blueprint '${bp}'"
  done

  # Standard container blueprint must appear
  for bp in "${CONTAINER_BLUEPRINTS[@]}"; do
    assert_contains "$output" "$bp" \
      "blueprints list should include container blueprint '${bp}'"
  done
}

# =============================================================================
# WORKFLOW 2: Find native blueprint
# Verify find returns a valid, readable file path
# =============================================================================

function test_find_native_blueprint() {
  log_test_step "Workflow: find native blueprint returns valid file path"

  local path
  path=$("$MODULE" find factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints find factorio should succeed"
  assert_not_null "$path" "blueprints find should return a path"
  assert_file_exists "$path" "blueprints find should return path to an existing file"
  assert_contains "$path" "factorio.bp" "found path should contain factorio.bp"
  assert_ends_with "$path" ".bp" "native blueprint path should end with .bp"
}

# =============================================================================
# WORKFLOW 3: Get blueprint info for native blueprint
# Verify info populates key required fields
# =============================================================================

function test_get_native_blueprint_info() {
  log_test_step "Workflow: get native blueprint info returns populated key fields"

  local info
  info=$("$MODULE" info factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints info factorio should succeed"
  assert_not_null "$info" "blueprints info should produce output"

  # Required fields must be present
  assert_contains "$info" "name=" "info output should contain name field"
  assert_contains "$info" "executable_file=" "info output should contain executable_file field"
  assert_contains "$info" "level_name=" "info output should contain level_name field"

  # Values must be non-empty (field=value where value is not empty)
  local name_val
  name_val=$(echo "$info" | grep "^name=" | cut -d= -f2)
  assert_not_null "$name_val" "factorio blueprint name field should not be empty"
  assert_equals "factorio" "$name_val" "factorio blueprint name should equal 'factorio'"

  local exe_val
  exe_val=$(echo "$info" | grep "^executable_file=" | cut -d= -f2)
  assert_not_null "$exe_val" "factorio blueprint executable_file should not be empty"
}

# =============================================================================
# WORKFLOW 4: Find container blueprint
# Verify find returns valid docker-compose.yml path
# =============================================================================

function test_find_container_blueprint() {
  log_test_step "Workflow: find container blueprint returns valid docker-compose.yml path"

  local path
  path=$("$MODULE" find vrising 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints find vrising should succeed"
  assert_not_null "$path" "blueprints find vrising should return a path"
  assert_file_exists "$path" "blueprints find vrising should return path to an existing file"
  assert_contains "$path" "vrising" "found path should contain vrising"
  assert_contains "$path" "docker-compose.yml" "container blueprint path should contain docker-compose.yml"
}

# =============================================================================
# WORKFLOW 5: List native-only blueprints via native submodule
# Verify blueprints.native.sh list only returns native blueprints
# =============================================================================

function test_list_native_only() {
  log_test_step "Workflow: native submodule list returns only native blueprints"

  local output
  output=$("$NATIVE_MODULE" list 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.native.sh list should succeed"
  assert_not_null "$output" "blueprints.native.sh list should produce output"

  # All standard native blueprints must appear
  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    assert_contains "$output" "$bp" \
      "native list should include '${bp}'"
  done

  # Container blueprint should NOT appear in native list
  assert_not_contains "$output" "vrising" \
    "native list should not include container blueprint 'vrising'"
}

# =============================================================================
# WORKFLOW 6: List container-only blueprints via container submodule
# Verify blueprints.container.sh list only returns container blueprints
# =============================================================================

function test_list_container_only() {
  log_test_step "Workflow: container submodule list returns only container blueprints"

  local output
  output=$("$CONTAINER_MODULE" list 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.container.sh list should succeed"
  assert_not_null "$output" "blueprints.container.sh list should produce output"

  # Standard container blueprint must appear
  assert_contains "$output" "vrising" "container list should include 'vrising'"

  # Native blueprints should NOT appear in container list
  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    assert_not_contains "$output" "$bp" \
      "container list should not include native blueprint '${bp}'"
  done
}

# =============================================================================
# WORKFLOW 7: Blueprint field validation for all standard blueprints
# Verify every standard native blueprint has required fields with values
# =============================================================================

function test_all_native_blueprints_have_required_fields() {
  log_test_step "Workflow: all standard native blueprints have required fields populated"

  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    local info
    info=$("$MODULE" info "$bp" 2>&1)
    local exit_code=$?

    assert_equals 0 "$exit_code" \
      "blueprints info ${bp} should succeed"
    assert_not_null "$info" \
      "blueprints info ${bp} should produce output"

    # name field must be present and non-empty
    local name_val
    name_val=$(echo "$info" | grep "^name=" | cut -d= -f2)
    assert_not_null "$name_val" \
      "${bp}: name field should not be empty"

    # executable_file must be present and non-empty
    local exe_val
    exe_val=$(echo "$info" | grep "^executable_file=" | cut -d= -f2)
    assert_not_null "$exe_val" \
      "${bp}: executable_file field should not be empty"

    # level_name must be present and non-empty
    local level_val
    level_val=$(echo "$info" | grep "^level_name=" | cut -d= -f2)
    assert_not_null "$level_val" \
      "${bp}: level_name field should not be empty"
  done
}

# =============================================================================
# WORKFLOW 8: Invalid blueprint returns error
# Verify clean error handling for nonexistent blueprint names
# =============================================================================

function test_invalid_blueprint_returns_error() {
  log_test_step "Workflow: invalid blueprint name returns non-zero exit code"

  assert_command_fails "$MODULE find nonexistent_blueprint_xyz_abc" \
    "find with nonexistent blueprint should fail"

  assert_command_fails "$MODULE info nonexistent_blueprint_xyz_abc" \
    "info with nonexistent blueprint should fail"

  # Native submodule should also fail cleanly
  assert_command_fails "$NATIVE_MODULE find nonexistent_blueprint_xyz_abc" \
    "blueprints.native.sh find with nonexistent blueprint should fail"

  # Container submodule should also fail cleanly
  assert_command_fails "$CONTAINER_MODULE find nonexistent_blueprint_xyz_abc" \
    "blueprints.container.sh find with nonexistent blueprint should fail"
}

# =============================================================================
# WORKFLOW 9: Cross-blueprint consistency
# Each known blueprint found via 'list' can also be found via 'find'
# =============================================================================

function test_list_find_consistency() {
  log_test_step "Workflow: every blueprint from list can be found via find"

  # All standard native blueprints in list should resolve via find
  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    local path
    path=$("$MODULE" find "$bp" 2>&1)
    local exit_code=$?

    assert_equals 0 "$exit_code" \
      "blueprints find '${bp}' (from list) should succeed"
    assert_file_exists "$path" \
      "blueprints find '${bp}' should return a path to an existing file"
  done

  # Container blueprints in list should also resolve via find
  for bp in "${CONTAINER_BLUEPRINTS[@]}"; do
    local path
    path=$("$MODULE" find "$bp" 2>&1)
    local exit_code=$?

    assert_equals 0 "$exit_code" \
      "blueprints find '${bp}' (container, from list) should succeed"
    assert_file_exists "$path" \
      "blueprints find '${bp}' (container) should return a path to an existing file"
  done
}

# =============================================================================
# WORKFLOW 10: Blueprint metadata completeness for all standard blueprints
# Verify all standard test blueprints (native + container) are accessible
# =============================================================================

function test_all_standard_blueprints_accessible() {
  log_test_step "Workflow: all standard test blueprints are accessible end-to-end"

  # Native: find + info must succeed for all standard blueprints
  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    local find_output info_output
    find_output=$("$MODULE" find "$bp" 2>&1)
    assert_equals 0 "$?" "find '${bp}' should succeed"
    assert_file_exists "$find_output" "'${bp}' blueprint file should exist at found path"

    info_output=$("$MODULE" info "$bp" 2>&1)
    assert_equals 0 "$?" "info '${bp}' should succeed"
    assert_not_null "$info_output" "info '${bp}' should return content"
  done

  # Container: find + info via container submodule
  for bp in "${CONTAINER_BLUEPRINTS[@]}"; do
    local find_output info_output
    find_output=$("$CONTAINER_MODULE" find "$bp" 2>&1)
    assert_equals 0 "$?" "container find '${bp}' should succeed"
    assert_file_exists "$find_output" "'${bp}' container blueprint file should exist at found path"

    info_output=$("$CONTAINER_MODULE" info "$bp" 2>&1)
    assert_equals 0 "$?" "container info '${bp}' should succeed"
    assert_not_null "$info_output" "container info '${bp}' should return content"
  done
}

# =============================================================================
# WORKFLOW 11: Steam vs non-Steam blueprint differentiation
# starbound (steam, account required) and necesse (steam, no account) differ
# =============================================================================

function test_steam_blueprint_field_differentiation() {
  log_test_step "Workflow: Steam blueprints have steam_app_id; non-Steam do not"

  # Steam blueprints (starbound, necesse) must have steam_app_id
  for bp in "starbound" "necesse"; do
    local info steam_app_id
    info=$("$MODULE" info "$bp" 2>&1)
    assert_equals 0 "$?" "blueprints info ${bp} should succeed"

    steam_app_id=$(echo "$info" | grep "^steam_app_id=" | cut -d= -f2)
    assert_not_null "$steam_app_id" \
      "${bp}: steam_app_id should be set for Steam blueprint"
  done

  # factorio is non-Steam; steam_app_id should be 0 (no Steam ID)
  local factorio_info factorio_steam_id
  factorio_info=$("$MODULE" info factorio 2>&1)
  assert_equals 0 "$?" "blueprints info factorio should succeed"

  factorio_steam_id=$(echo "$factorio_info" | grep "^steam_app_id=" | cut -d= -f2)
  assert_equals "0" "$factorio_steam_id" \
    "factorio: steam_app_id should be 0 for non-Steam blueprint"
}

# =============================================================================
# WORKFLOW 12: JSON output for blueprints list and info
# Verify --json flag produces output containing expected blueprint names
# =============================================================================

function test_json_output() {
  log_test_step "Workflow: blueprints list and info --json output contains expected data"

  local list_json
  list_json=$("$MODULE" list --json 2>&1)
  assert_equals 0 "$?" "blueprints list --json should succeed"
  assert_not_null "$list_json" "blueprints list --json should produce output"
  assert_contains "$list_json" "factorio" \
    "list --json output should include factorio"
  assert_contains "$list_json" "vrising" \
    "list --json output should include vrising"

  local info_json
  info_json=$("$MODULE" info factorio --json 2>&1)
  assert_equals 0 "$?" "blueprints info factorio --json should succeed"
  assert_not_null "$info_json" "blueprints info factorio --json should produce output"
  assert_contains "$info_json" "factorio" \
    "info factorio --json output should include factorio"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting blueprint management e2e tests"

  setup_test

  # Workflow tests
  test_list_all_blueprints
  test_find_native_blueprint
  test_get_native_blueprint_info
  test_find_container_blueprint
  test_list_native_only
  test_list_container_only
  test_all_native_blueprints_have_required_fields
  test_invalid_blueprint_returns_error
  test_list_find_consistency
  test_all_standard_blueprints_accessible
  test_steam_blueprint_field_differentiation
  test_json_output

  log_test_step "Blueprint management e2e tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All blueprint management e2e tests passed"
  else
    fail_test "Some blueprint management e2e tests failed"
  fi
}

main "$@"
