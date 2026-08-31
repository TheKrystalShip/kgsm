#!/usr/bin/env bash

# KGSM Files Symlink Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/files.symlink.sh
#
# Tests all logic functions from files.symlink.sh:
# - __logic_enable_symlink_integration()
# - __logic_disable_symlink_integration()

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_symlink_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.symlink.sh"

# Temp shortcuts directory used across tests
_TEST_SHORTCUTS_DIR=""
_ORIGINAL_CONFIG_SHORTCUTS_VALUE=""

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

# Create a minimal instance config file for testing
# Args: $1 = output_dir, $2 = instance_name, $3 = management_file (optional)
# Outputs: echoes the config file path
function __create_symlink_test_config() {
  local output_dir="$1"
  local instance_name="$2"
  local management_file="${3:-}"

  local config_file="${output_dir}/${instance_name}.config.ini"

  cat > "$config_file" << EOF
# KGSM Test Instance Configuration
name=${instance_name}
management_file=${management_file}
enable_command_shortcuts=false
command_shortcut_file=
EOF

  echo "$config_file"
}

# Create a minimal executable management file for testing
# Args: $1 = output_path
function __create_symlink_test_management_file() {
  local output_path="$1"

  cat > "$output_path" << 'EOF'
#!/usr/bin/env bash
# Test management script
function start() { echo "start"; }
EOF

  chmod +x "$output_path"
}

# Update CONFIG_FILE to use a custom shortcuts directory.
# Args: $1 = new_shortcuts_dir
# Side effect: saves original value to _ORIGINAL_CONFIG_SHORTCUTS_VALUE
function __set_test_shortcuts_dir() {
  local new_dir="$1"

  # Save original value for restoration
  _ORIGINAL_CONFIG_SHORTCUTS_VALUE=$(grep "^command_shortcuts_directory=" "$CONFIG_FILE" 2>/dev/null || echo "")

  # Update the config file
  if grep -q "^command_shortcuts_directory=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^command_shortcuts_directory=.*|command_shortcuts_directory=${new_dir}|" "$CONFIG_FILE"
  else
    echo "command_shortcuts_directory=${new_dir}" >> "$CONFIG_FILE"
  fi
}

# Restore CONFIG_FILE shortcuts directory to original value
function __restore_test_shortcuts_dir() {
  if [[ -z "$_ORIGINAL_CONFIG_SHORTCUTS_VALUE" ]]; then
    # Key was not originally present; remove the line we added
    sed -i '/^command_shortcuts_directory=/d' "$CONFIG_FILE" 2>/dev/null || true
  else
    sed -i "s|^command_shortcuts_directory=.*|${_ORIGINAL_CONFIG_SHORTCUTS_VALUE}|" "$CONFIG_FILE"
  fi
  _ORIGINAL_CONFIG_SHORTCUTS_VALUE=""
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up files.symlink logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM_ROOT directory should exist"
  assert_file_exists "$HANDLER" "Handler file should exist"

  # Source the handler
  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_not_null "${KGSM_LOGIC_FILES_SYMLINK_LOADED:-}" "Handler should be loaded after sourcing"

  # Verify required error codes
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_CONFIG" "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FAILED_LN" "EC_FAILED_LN should be defined"
  assert_not_null "$EC_FAILED_RM" "EC_FAILED_RM should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"
  assert_not_null "$EC_FAILED_UPDATE_CONFIG" "EC_FAILED_UPDATE_CONFIG should be defined"
  assert_not_null "$EC_SUCCESS_SYMLINK_CREATED" "EC_SUCCESS_SYMLINK_CREATED should be defined"
  assert_not_null "$EC_SUCCESS_SYMLINK_REMOVED" "EC_SUCCESS_SYMLINK_REMOVED should be defined"

  # Verify handler functions are exported
  assert_function_exists "__logic_enable_symlink_integration" \
    "__logic_enable_symlink_integration should be exported"
  assert_function_exists "__logic_disable_symlink_integration" \
    "__logic_disable_symlink_integration should be exported"

  # Create temp shortcuts directory
  _TEST_SHORTCUTS_DIR="$KGSM_TEST_SANDBOX/test_shortcuts_$$"
  mkdir -p "$_TEST_SHORTCUTS_DIR"

  assert_dir_exists "$_TEST_SHORTCUTS_DIR" "Test shortcuts directory should be created"

  log_test_step "Environment validated"
}

# =============================================================================
# __logic_enable_symlink_integration() TESTS
# =============================================================================

function test_enable_symlink_empty_arg() {
  log_test_step "Testing __logic_enable_symlink_integration with empty argument"

  __logic_enable_symlink_integration "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG when no config file path provided"
}

function test_enable_symlink_config_not_found() {
  log_test_step "Testing __logic_enable_symlink_integration with non-existent config file"

  __logic_enable_symlink_integration "/nonexistent/path/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND when config file does not exist"
}

function test_enable_symlink_missing_name_in_config() {
  log_test_step "Testing __logic_enable_symlink_integration with missing 'name' field in config"

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_missing_name_$$"
  mkdir -p "$test_dir"

  # Create config without 'name' field
  local config_file="$test_dir/test.config.ini"
  cat > "$config_file" << EOF
management_file=$test_dir/manage.sh
enable_command_shortcuts=false
command_shortcut_file=
EOF

  __logic_enable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" \
    "Should return EC_INVALID_CONFIG when 'name' field is missing from config"

  rm -rf "$test_dir"
}

function test_enable_symlink_missing_management_file_field() {
  log_test_step "Testing __logic_enable_symlink_integration with missing 'management_file' field"

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_missing_manage_$$"
  mkdir -p "$test_dir"

  # Create config without 'management_file' field
  local config_file="$test_dir/test.config.ini"
  cat > "$config_file" << EOF
name=test_instance
enable_command_shortcuts=false
command_shortcut_file=
EOF

  __logic_enable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" \
    "Should return EC_INVALID_CONFIG when 'management_file' field is missing from config"

  rm -rf "$test_dir"
}

function test_enable_symlink_management_file_not_found() {
  log_test_step "Testing __logic_enable_symlink_integration when management_file does not exist"

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_manage_missing_$$"
  mkdir -p "$test_dir"

  local config_file
  config_file=$(__create_symlink_test_config \
    "$test_dir" "test_instance" "/nonexistent/manage.sh")

  __logic_enable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND when management_file does not exist"

  rm -rf "$test_dir"
}

function test_enable_symlink_shortcuts_dir_not_configured() {
  log_test_step "Testing __logic_enable_symlink_integration when shortcuts dir not in KGSM config"

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_no_shortcuts_cfg_$$"
  mkdir -p "$test_dir"

  local management_file="$test_dir/manage.sh"
  __create_symlink_test_management_file "$management_file"

  local config_file
  config_file=$(__create_symlink_test_config \
    "$test_dir" "test_instance" "$management_file")

  # Temporarily remove/blank the command_shortcuts_directory from CONFIG_FILE
  local original_line
  original_line=$(grep "^command_shortcuts_directory=" "$CONFIG_FILE" 2>/dev/null || echo "")
  sed -i '/^command_shortcuts_directory=/d' "$CONFIG_FILE"

  __logic_enable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  # Restore original config line
  if [[ -n "$original_line" ]]; then
    echo "$original_line" >> "$CONFIG_FILE"
  fi

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" \
    "Should return EC_INVALID_CONFIG when command_shortcuts_directory is not in KGSM config"

  rm -rf "$test_dir"
}

function test_enable_symlink_shortcuts_dir_not_exist() {
  log_test_step "Testing __logic_enable_symlink_integration when shortcuts directory does not exist"

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_no_shortcuts_dir_$$"
  mkdir -p "$test_dir"

  local management_file="$test_dir/manage.sh"
  __create_symlink_test_management_file "$management_file"

  local config_file
  config_file=$(__create_symlink_test_config \
    "$test_dir" "test_instance" "$management_file")

  # Set shortcuts dir to a non-existent path
  __set_test_shortcuts_dir "/nonexistent/shortcuts/dir"

  __logic_enable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  __restore_test_shortcuts_dir

  # Distinct from the missing management file above: a missing shortcuts
  # directory is a configuration problem the operator can fix, and the command
  # layer says so only because the two arrive as different codes.
  assert_equals "$EC_DIRECTORY_NOT_FOUND" "$exit_code" \
    "Should return EC_DIRECTORY_NOT_FOUND when shortcuts directory does not exist"

  rm -rf "$test_dir"
}

function test_enable_symlink_success() {
  log_test_step "Testing __logic_enable_symlink_integration success path (writable dir, no sudo)"

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_success_$$"
  mkdir -p "$test_dir"

  local management_file="$test_dir/manage.sh"
  __create_symlink_test_management_file "$management_file"

  local instance_name="test_symlink_instance_$$"
  local config_file
  config_file=$(__create_symlink_test_config \
    "$test_dir" "$instance_name" "$management_file")

  # Point shortcuts dir to our writable temp directory
  __set_test_shortcuts_dir "$_TEST_SHORTCUTS_DIR"

  __logic_enable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  __restore_test_shortcuts_dir

  local expected_symlink="${_TEST_SHORTCUTS_DIR}/${instance_name}"

  assert_equals "$EC_SUCCESS_SYMLINK_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_SYMLINK_CREATED on success"

  local is_link="false"
  [[ -L "$expected_symlink" ]] && is_link="true"
  assert_true "$is_link" \
    "Symlink should be created at shortcuts directory"

  # Verify config was updated
  local enable_val
  enable_val=$(grep "^enable_command_shortcuts=" "$config_file" | cut -d= -f2)
  assert_equals "true" "$enable_val" \
    "Config should have enable_command_shortcuts=true after enabling"

  local shortcut_val
  shortcut_val=$(grep "^command_shortcut_file=" "$config_file" | cut -d= -f2)
  assert_equals "$expected_symlink" "$shortcut_val" \
    "Config should record the symlink path"

  # Cleanup symlink
  rm -f "$expected_symlink" 2>/dev/null || true
  rm -rf "$test_dir"
}

function test_enable_symlink_recreates_existing() {
  log_test_step "Testing __logic_enable_symlink_integration replaces an existing symlink"

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_recreate_$$"
  mkdir -p "$test_dir"

  local management_file="$test_dir/manage.sh"
  __create_symlink_test_management_file "$management_file"

  local instance_name="test_recreate_instance_$$"
  local config_file
  config_file=$(__create_symlink_test_config \
    "$test_dir" "$instance_name" "$management_file")

  __set_test_shortcuts_dir "$_TEST_SHORTCUTS_DIR"

  # Pre-create a stale symlink at the target location
  local expected_symlink="${_TEST_SHORTCUTS_DIR}/${instance_name}"
  ln -s "/some/old/path" "$expected_symlink" 2>/dev/null || true

  local stale_present="false"
  [[ -L "$expected_symlink" ]] && stale_present="true"
  assert_true "$stale_present" "Pre-created stale symlink should exist"

  # Now enable - should replace the stale symlink
  __logic_enable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  __restore_test_shortcuts_dir

  assert_equals "$EC_SUCCESS_SYMLINK_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_SYMLINK_CREATED even when symlink already exists"

  local is_link="false"
  [[ -L "$expected_symlink" ]] && is_link="true"
  assert_true "$is_link" \
    "New symlink should exist after replacement"

  # Verify it now points to the correct management file (not the old stale path)
  local link_target
  link_target=$(readlink "$expected_symlink" 2>/dev/null)
  assert_equals "$management_file" "$link_target" \
    "Symlink should point to current management file"

  # Cleanup
  rm -f "$expected_symlink" 2>/dev/null || true
  rm -rf "$test_dir"
}

# =============================================================================
# __expand_home_path() + no-escalation TESTS
# =============================================================================

function test_expand_home_path() {
  log_test_step "Testing __expand_home_path expands ~ and \$HOME, leaves absolutes alone"

  local result

  # The literal $HOME / ~ inputs are intentional — the function under test is
  # what does the expansion, so they must reach it unexpanded.
  # shellcheck disable=SC2016,SC2088
  result=$(__expand_home_path '$HOME/.local/bin')
  assert_equals "$HOME/.local/bin" "$result" \
    "\$HOME prefix should expand to the home directory"

  # shellcheck disable=SC2016
  result=$(__expand_home_path '${HOME}/bin')
  assert_equals "$HOME/bin" "$result" \
    "\${HOME} prefix should expand to the home directory"

  # shellcheck disable=SC2088
  result=$(__expand_home_path '~/.local/bin')
  assert_equals "$HOME/.local/bin" "$result" \
    "Leading ~ should expand to the home directory"

  result=$(__expand_home_path '/usr/local/bin')
  assert_equals "/usr/local/bin" "$result" \
    "An absolute path without ~ or \$HOME should be unchanged"
}

function test_enable_symlink_expands_home_and_autocreates() {
  log_test_step "Testing enable expands \$HOME and auto-creates a dir under HOME (no sudo)"

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_expand_home_$$"
  mkdir -p "$test_dir"

  local management_file="$test_dir/manage.sh"
  __create_symlink_test_management_file "$management_file"

  local instance_name="test_expand_instance_$$"
  local config_file
  config_file=$(__create_symlink_test_config \
    "$test_dir" "$instance_name" "$management_file")

  # Treat a sandbox subdir as HOME so the auto-create-under-home path runs
  # without touching the real home directory.
  local fake_home="$test_dir/home"
  mkdir -p "$fake_home"

  # Store the directory verbatim with a literal $HOME (single-quoted so the
  # test shell does not expand it) — the handler must expand it on read.
  # shellcheck disable=SC2016
  __set_test_shortcuts_dir '$HOME/.local/bin'

  # Run the handler with HOME pointed at the sandbox (subshell isolates it).
  (
    export HOME="$fake_home"
    __logic_enable_symlink_integration "$config_file" 2>/dev/null
  )
  local exit_code=$?

  __restore_test_shortcuts_dir

  local expected_dir="${fake_home}/.local/bin"
  local expected_symlink="${expected_dir}/${instance_name}"

  assert_equals "$EC_SUCCESS_SYMLINK_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_SYMLINK_CREATED after expanding \$HOME"

  assert_dir_exists "$expected_dir" \
    "Shortcuts directory under HOME should be auto-created"

  local is_link="false"
  [[ -L "$expected_symlink" ]] && is_link="true"
  assert_true "$is_link" \
    "Symlink should be created in the expanded, auto-created directory"

  # Config should record the fully-expanded shortcut path
  local shortcut_val
  shortcut_val=$(grep "^command_shortcut_file=" "$config_file" | cut -d= -f2)
  assert_equals "$expected_symlink" "$shortcut_val" \
    "Config should record the expanded symlink path"

  rm -rf "$test_dir"
}

function test_enable_symlink_dir_not_writable_no_escalation() {
  log_test_step "Testing enable returns EC_PERMISSION on a non-writable dir (never escalates)"

  if [[ "$EUID" -eq 0 ]]; then
    skip_test "Root bypasses directory write permissions" && return
  fi

  local test_dir="$KGSM_TEST_SANDBOX/test_enable_unwritable_$$"
  mkdir -p "$test_dir"

  local management_file="$test_dir/manage.sh"
  __create_symlink_test_management_file "$management_file"

  local instance_name="test_unwritable_instance_$$"
  local config_file
  config_file=$(__create_symlink_test_config \
    "$test_dir" "$instance_name" "$management_file")

  # A directory that exists but is not writable by this (non-root) user.
  # It lives outside HOME, so the auto-create branch never applies.
  local ro_dir="$test_dir/readonly_shortcuts"
  mkdir -p "$ro_dir"
  chmod 555 "$ro_dir"

  __set_test_shortcuts_dir "$ro_dir"

  __logic_enable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  __restore_test_shortcuts_dir

  # Restore perms so teardown can clean up
  chmod 755 "$ro_dir" 2>/dev/null || true

  assert_equals "$EC_PERMISSION" "$exit_code" \
    "Should return EC_PERMISSION when shortcuts dir is not writable (no sudo)"

  local created="false"
  [[ -e "$ro_dir/$instance_name" ]] && created="true"
  assert_false "$created" \
    "No symlink should be created when the directory is not writable"

  rm -rf "$test_dir"
}

# =============================================================================
# __logic_disable_symlink_integration() TESTS
# =============================================================================

function test_disable_symlink_empty_arg() {
  log_test_step "Testing __logic_disable_symlink_integration with empty argument"

  __logic_disable_symlink_integration "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG when no config file path provided"
}

function test_disable_symlink_config_not_found() {
  log_test_step "Testing __logic_disable_symlink_integration with non-existent config file"

  __logic_disable_symlink_integration "/nonexistent/path/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND when config file does not exist"
}

function test_disable_symlink_no_shortcut_configured() {
  log_test_step "Testing __logic_disable_symlink_integration when no shortcut is configured"

  local test_dir="$KGSM_TEST_SANDBOX/test_disable_no_shortcut_$$"
  mkdir -p "$test_dir"

  # Config with empty command_shortcut_file (nothing to disable)
  local config_file
  config_file=$(__create_symlink_test_config \
    "$test_dir" "test_instance" "/tmp/manage.sh")
  # command_shortcut_file= is already empty in the helper

  __logic_disable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYMLINK_REMOVED" "$exit_code" \
    "Should return EC_SUCCESS_SYMLINK_REMOVED when no shortcut is configured (no-op)"

  rm -rf "$test_dir"
}

function test_disable_symlink_shortcut_file_not_a_symlink() {
  log_test_step "Testing __logic_disable_symlink_integration when shortcut file is not a symlink"

  local test_dir="$KGSM_TEST_SANDBOX/test_disable_not_symlink_$$"
  mkdir -p "$test_dir"

  # Create a regular (non-symlink) file at the shortcut path
  local fake_shortcut="$test_dir/fake_shortcut"
  touch "$fake_shortcut"

  local config_file="${test_dir}/test_instance.config.ini"
  cat > "$config_file" << EOF
name=test_instance
management_file=$test_dir/manage.sh
enable_command_shortcuts=true
command_shortcut_file=${fake_shortcut}
EOF

  # Since fake_shortcut is a regular file (not a symlink), rm block is skipped
  __logic_disable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYMLINK_REMOVED" "$exit_code" \
    "Should return EC_SUCCESS_SYMLINK_REMOVED even when configured path is not a symlink"

  # Config should be updated to disabled state
  local enable_val
  enable_val=$(grep "^enable_command_shortcuts=" "$config_file" | cut -d= -f2)
  assert_equals "false" "$enable_val" \
    "Config should have enable_command_shortcuts=false after disabling"

  rm -rf "$test_dir"
}

function test_disable_symlink_shortcut_does_not_exist() {
  log_test_step "Testing __logic_disable_symlink_integration when shortcut path does not exist"

  local test_dir="$KGSM_TEST_SANDBOX/test_disable_missing_$$"
  mkdir -p "$test_dir"

  local config_file="${test_dir}/test_instance.config.ini"
  cat > "$config_file" << EOF
name=test_instance
management_file=$test_dir/manage.sh
enable_command_shortcuts=true
command_shortcut_file=/nonexistent/path/shortcut
EOF

  # Non-existent path: -L check fails, rm is skipped, config is updated
  __logic_disable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYMLINK_REMOVED" "$exit_code" \
    "Should return EC_SUCCESS_SYMLINK_REMOVED when shortcut path does not exist"

  # Config should be updated to reflect disabled state
  local shortcut_val
  shortcut_val=$(grep "^command_shortcut_file=" "$config_file" | cut -d= -f2)
  assert_equals "" "$shortcut_val" \
    "Config command_shortcut_file should be cleared after disabling"

  rm -rf "$test_dir"
}

function test_disable_symlink_success() {
  log_test_step "Testing __logic_disable_symlink_integration with an actual symlink (no sudo)"

  local test_dir="$KGSM_TEST_SANDBOX/test_disable_success_$$"
  mkdir -p "$test_dir"

  local management_file="$test_dir/manage.sh"
  __create_symlink_test_management_file "$management_file"

  # Create the symlink to be removed
  local shortcut_path="$_TEST_SHORTCUTS_DIR/test_disable_instance_$$"
  ln -s "$management_file" "$shortcut_path"

  local pre_present="false"
  [[ -L "$shortcut_path" ]] && pre_present="true"
  assert_true "$pre_present" "Symlink should exist before disable"

  local config_file="${test_dir}/test_instance.config.ini"
  cat > "$config_file" << EOF
name=test_instance
management_file=${management_file}
enable_command_shortcuts=true
command_shortcut_file=${shortcut_path}
EOF

  __logic_disable_symlink_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYMLINK_REMOVED" "$exit_code" \
    "Should return EC_SUCCESS_SYMLINK_REMOVED on success"

  local still_present="false"
  [[ -L "$shortcut_path" ]] && still_present="true"
  assert_false "$still_present" \
    "Symlink should be removed after disabling"

  # Verify config is updated
  local enable_val
  enable_val=$(grep "^enable_command_shortcuts=" "$config_file" | cut -d= -f2)
  assert_equals "false" "$enable_val" \
    "Config should have enable_command_shortcuts=false after disabling"

  local shortcut_val
  shortcut_val=$(grep "^command_shortcut_file=" "$config_file" | cut -d= -f2)
  assert_equals "" "$shortcut_val" \
    "Config command_shortcut_file should be cleared after disabling"

  rm -rf "$test_dir"
}

# =============================================================================
# CLEANUP
# =============================================================================

# File-level cleanup. The framework invokes teardown_file once after all tests
# (the per-test hook it calls is bare `teardown`); a `teardown_test` name would
# never run.
function teardown_file() {
  log_test_step "Cleaning up test artifacts"

  # Remove temp shortcuts directory
  if [[ -n "$_TEST_SHORTCUTS_DIR" ]] && [[ -d "$_TEST_SHORTCUTS_DIR" ]]; then
    rm -rf "$_TEST_SHORTCUTS_DIR" 2>/dev/null || true
  fi

  # Ensure CONFIG_FILE shortcuts dir is restored (safety net)
  if [[ -n "$_ORIGINAL_CONFIG_SHORTCUTS_VALUE" ]]; then
    __restore_test_shortcuts_dir
  fi
}

