#!/usr/bin/env bash

# KGSM Config + Instances Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between commands/config.sh and commands/instances.sh
#
# Integration points tested:
# - config_instance_suffix_length affects generated instance name length
# - Config default values are embedded into instance config at creation time
#   (save_command_timeout_seconds, stop_command_timeout_seconds, compress_backups,
#    auto_update_before_start)
# - Config `set` command changes flow through to newly created instances
# - Config validate remains passing after instance creation/removal operations
# - Config merge preserves instance-related default settings
# - Config `get` retrieves instance-default keys correctly

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="config_instances_integration"
readonly CONFIG_MODULE="$KGSM_ROOT/commands/config.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

TEST_INSTALL_DIR=""

# Per-test cleanup tracking (used by teardown hook)
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up config+instances integration tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$CONFIG_MODULE" "commands/config.sh should exist"
  assert_file_executable "$CONFIG_MODULE" "commands/config.sh should be executable"
  assert_file_exists "$INSTANCES_MODULE" "commands/instances.sh should exist"
  assert_file_executable "$INSTANCES_MODULE" "commands/instances.sh should be executable"

  # Ensure a valid config file exists in the sandbox
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
  fi

  log_test_step "Config+instances integration test environment validated"
}

function setup() {
  _TEARDOWN_INSTANCES=()
  # Snapshot config state for guaranteed restoration
  cp "$CONFIG_FILE" "${CONFIG_FILE}.pre-test-snapshot"
  _SNAPSHOT_suffix_length="${config_instance_suffix_length:-}"
  _SNAPSHOT_save_timeout="${config_instance_save_command_timeout_seconds:-}"
  _SNAPSHOT_stop_timeout="${config_instance_stop_command_timeout_seconds:-}"
  _SNAPSHOT_backup_compression="${config_enable_backup_compression:-}"
}

function teardown() {
  # Restore config file from snapshot
  if [[ -f "${CONFIG_FILE}.pre-test-snapshot" ]]; then
    cp "${CONFIG_FILE}.pre-test-snapshot" "$CONFIG_FILE"
    rm -f "${CONFIG_FILE}.pre-test-snapshot"
  fi

  # Restore exported config variables
  export config_instance_suffix_length="${_SNAPSHOT_suffix_length}"
  export config_instance_save_command_timeout_seconds="${_SNAPSHOT_save_timeout}"
  export config_instance_stop_command_timeout_seconds="${_SNAPSHOT_stop_timeout}"
  export config_enable_backup_compression="${_SNAPSHOT_backup_compression}"

  # Clean up tracked instances
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" "$TEST_INSTALL_DIR" 2>/dev/null || true
  done
}

# =============================================================================
# TEST 1: instance_suffix_length config affects generated instance name suffix
# =============================================================================

function test_instance_suffix_length_affects_name_generation() {
  log_test_step "Testing: config instance_suffix_length flows into instance ID generation"

  # Export directly so subprocesses (which inherit KGSM_CONFIG_LOADED=1) use the new value
  export config_instance_suffix_length=5
  sed -i "s/^instance_suffix_length=.*/instance_suffix_length=5/" "$CONFIG_FILE"

  # Clean up any stale dangling symlink for the "factorio" blueprint-name slot
  # (can be left by previous test runs pointing to now-deleted sandbox paths)
  local factorio_slot="${KGSM_INSTANCES_DIR}/factorio/factorio"
  if [[ -L "$factorio_slot" && ! -e "$factorio_slot" ]]; then
    rm -f "$factorio_slot"
  fi

  # Determine current state: is the "factorio" blueprint-name slot already occupied?
  local probe_id
  probe_id=$("$INSTANCES_MODULE" generate-id factorio 2>&1)

  if [[ "$probe_id" == *"-"* ]]; then
    # Slot is pre-occupied; probe_id already has a suffix — verify its length
    local existing_suffix="${probe_id##*-}"
    assert_equals 5 "${#existing_suffix}" \
      "Suffix should be 5 digits when instance_suffix_length=5 (pre-occupied slot)"
  else
    # Slot is free; create "factorio" instance to occupy it
    local first_name
    first_name=$(create_test_instance "factorio" "" "$TEST_INSTALL_DIR" 2>/dev/null)
    assert_equals 0 "$?" "First instance creation should succeed"

    # Generate a second ID — slot is now occupied, should produce a 5-digit suffix
    local second_id
    second_id=$("$INSTANCES_MODULE" generate-id factorio 2>&1)
    assert_equals 0 "$?" "generate-id should succeed after first instance created"
    assert_not_null "$second_id" "generate-id should return a name"
    assert_contains "$second_id" "-" "Second generated ID should include suffix separator"

    local suffix="${second_id##*-}"
    assert_equals 5 "${#suffix}" \
      "Suffix should be 5 digits when instance_suffix_length=5"

    _TEARDOWN_INSTANCES+=("factorio:$first_name")
  fi
}

# =============================================================================
# TEST 2: Config save_command_timeout_seconds embedded in instance config
# =============================================================================

function test_config_save_timeout_embedded_in_instance() {
  log_test_step "Testing: config save_command_timeout_seconds flows into instance config"

  # Export directly so the subprocess (which inherits KGSM_CONFIG_LOADED=1) sees the new value
  export config_instance_save_command_timeout_seconds=42
  sed -i "s/^instance_save_command_timeout_seconds=.*/instance_save_command_timeout_seconds=42/" "$CONFIG_FILE"

  local instance_name="test-save-to-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  # Find instance config file
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should succeed"
  assert_file_exists "$instance_config" "Instance config file should exist"

  # Verify the timeout value is embedded
  assert_file_contains "$instance_config" 'save_command_timeout_seconds="42"' \
    "Instance config should contain the configured save timeout"
}

# =============================================================================
# TEST 3: Config stop_command_timeout_seconds embedded in instance config
# =============================================================================

function test_config_stop_timeout_embedded_in_instance() {
  log_test_step "Testing: config stop_command_timeout_seconds flows into instance config"

  # Export directly so the subprocess (which inherits KGSM_CONFIG_LOADED=1) sees the new value
  export config_instance_stop_command_timeout_seconds=99
  sed -i "s/^instance_stop_command_timeout_seconds=.*/instance_stop_command_timeout_seconds=99/" "$CONFIG_FILE"

  local instance_name="test-stop-to-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should succeed"
  assert_file_exists "$instance_config" "Instance config file should exist"

  assert_file_contains "$instance_config" 'stop_command_timeout_seconds="99"' \
    "Instance config should contain the configured stop timeout"
}

# =============================================================================
# TEST 4: Config enable_backup_compression embedded in instance config
# =============================================================================

function test_config_backup_compression_embedded_in_instance() {
  log_test_step "Testing: config enable_backup_compression flows into instance config"

  # Export directly so the subprocess (which inherits KGSM_CONFIG_LOADED=1) sees the new value
  export config_enable_backup_compression=true
  sed -i "s/^enable_backup_compression=.*/enable_backup_compression=true/" "$CONFIG_FILE"

  local instance_name="test-compress-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should succeed"
  assert_file_exists "$instance_config" "Instance config file should exist"

  assert_file_contains "$instance_config" 'compress_backups="true"' \
    "Instance config should reflect compress_backups=true"
}

# =============================================================================
# TEST 5: Config validate remains valid after instance create and remove
# =============================================================================

function test_config_validate_after_instance_operations() {
  log_test_step "Testing: config validate passes before, during, and after instance operations"

  # Validate before
  "$KGSM_ROOT/kgsm.sh" config validate >/dev/null 2>&1
  local pre_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$pre_code" \
    "Config should be valid before instance operations"

  # Create an instance
  local instance_name="test-cfg-valid-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  # Validate during (instance exists)
  "$KGSM_ROOT/kgsm.sh" config validate >/dev/null 2>&1
  local mid_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$mid_code" \
    "Config should still be valid with an active instance"

  # Remove the instance
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"

  # Validate after
  "$KGSM_ROOT/kgsm.sh" config validate >/dev/null 2>&1
  local post_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$post_code" \
    "Config should remain valid after instance removal"
}

# =============================================================================
# TEST 6: Config merge preserves instance-related settings
# =============================================================================

function test_config_merge_preserves_instance_defaults() {
  log_test_step "Testing: config merge preserves customized instance default settings"

  # Customize instance defaults in config
  "$CONFIG_MODULE" set instance_save_command_timeout_seconds=77 >/dev/null 2>&1
  "$CONFIG_MODULE" set instance_stop_command_timeout_seconds=88 >/dev/null 2>&1

  # Run merge
  "$KGSM_ROOT/kgsm.sh" config merge >/dev/null 2>&1
  local merge_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_MERGED" "$merge_code" \
    "Config merge should succeed"

  # Verify custom values survived the merge
  local save_timeout
  save_timeout=$("$CONFIG_MODULE" get instance_save_command_timeout_seconds 2>&1)
  assert_equals "77" "$save_timeout" \
    "Merge should preserve custom instance_save_command_timeout_seconds=77"

  local stop_timeout
  stop_timeout=$("$CONFIG_MODULE" get instance_stop_command_timeout_seconds 2>&1)
  assert_equals "88" "$stop_timeout" \
    "Merge should preserve custom instance_stop_command_timeout_seconds=88"
}

# =============================================================================
# TEST 7: Config get retrieves instance-default keys
# =============================================================================

function test_config_get_instance_default_keys() {
  log_test_step "Testing: config get retrieves instance-related configuration keys"

  # Retrieve instance_suffix_length
  local suffix_len
  suffix_len=$("$CONFIG_MODULE" get instance_suffix_length 2>&1)
  assert_equals 0 "$?" "config get instance_suffix_length should succeed"
  assert_not_null "$suffix_len" "instance_suffix_length should have a value"
  assert_matches "$suffix_len" "^[0-9]+$" \
    "instance_suffix_length should be a positive integer"

  # Retrieve instance_save_command_timeout_seconds
  local save_to
  save_to=$("$CONFIG_MODULE" get instance_save_command_timeout_seconds 2>&1)
  assert_equals 0 "$?" "config get instance_save_command_timeout_seconds should succeed"
  assert_not_null "$save_to" "instance_save_command_timeout_seconds should have a value"

  # Retrieve instance_stop_command_timeout_seconds
  local stop_to
  stop_to=$("$CONFIG_MODULE" get instance_stop_command_timeout_seconds 2>&1)
  assert_equals 0 "$?" "config get instance_stop_command_timeout_seconds should succeed"
  assert_not_null "$stop_to" "instance_stop_command_timeout_seconds should have a value"

  # Retrieve enable_backup_compression
  local compress
  compress=$("$CONFIG_MODULE" get enable_backup_compression 2>&1)
  assert_equals 0 "$?" "config get enable_backup_compression should succeed"
  assert_not_null "$compress" "enable_backup_compression should have a value"
}

# =============================================================================
# TEST 8: Config set invalid value is rejected and does not corrupt instance creation
# =============================================================================

function test_config_set_invalid_value_rejected() {
  log_test_step "Testing: config set with invalid value is rejected cleanly"

  # Try setting a boolean key to a non-boolean value
  "$CONFIG_MODULE" set enable_backup_compression=notabool >/dev/null 2>&1
  local set_code=$?
  assert_not_equals 0 "$set_code" \
    "config set enable_backup_compression=notabool should be rejected"

  # Verify the config value was not changed (still default false)
  local val
  val=$("$CONFIG_MODULE" get enable_backup_compression 2>&1)
  assert_not_equals "notabool" "$val" \
    "enable_backup_compression should not have been set to invalid value"

  # Config should still be valid
  "$KGSM_ROOT/kgsm.sh" config validate >/dev/null 2>&1
  local validate_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$validate_code" \
    "Config should still be valid after rejected set"
}

# =============================================================================
# TEST 9: Config list shows instance-related keys
# =============================================================================

function test_config_list_shows_instance_keys() {
  log_test_step "Testing: config list output includes instance-related configuration keys"

  local output
  output=$("$CONFIG_MODULE" list 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "config list should succeed"
  assert_contains "$output" "instance_suffix_length" \
    "config list should show instance_suffix_length"
  assert_contains "$output" "instance_save_command_timeout_seconds" \
    "config list should show instance_save_command_timeout_seconds"
  assert_contains "$output" "instance_stop_command_timeout_seconds" \
    "config list should show instance_stop_command_timeout_seconds"
  assert_contains "$output" "enable_backup_compression" \
    "config list should show enable_backup_compression"
}

