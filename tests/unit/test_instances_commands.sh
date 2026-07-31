#!/usr/bin/env bash

# KGSM Instances Command Tests
#
# Test Type: UNIT
# Target: commands/instances.sh - CLI interface

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instances_commands"
readonly MODULE="$KGSM_ROOT/commands/instances.sh"

# Test-specific paths
TEST_INSTALL_DIR=""

# Per-test cleanup tracking (used by teardown hook)
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up instances commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "instances.sh command should exist"
  assert_file_executable "$MODULE" "instances.sh command should be executable"

  log_test_step "Test environment validated"
}

function setup() {
  _TEARDOWN_INSTANCES=()
}

function teardown() {
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" "$TEST_INSTALL_DIR" 2>/dev/null || true
  done
}

# =============================================================================
# TEST: help - Shows Usage
# =============================================================================

function test_help_command() {
  log_test_step "Testing 'help' command"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help command should exit 0"
  assert_contains "$output" "create" "help should mention create"
  assert_contains "$output" "remove" "help should mention remove"
  assert_contains "$output" "list" "help should mention list"
  assert_contains "$output" "info" "help should mention info"
  assert_contains "$output" "find" "help should mention find"
  assert_contains "$output" "generate-id" "help should mention generate-id"
}

function test_help_subcommands() {
  log_test_step "Testing help sub-commands"

  local commands=("create" "remove" "list" "info" "status" "find" "generate-id")

  for cmd in "${commands[@]}"; do
    local output
    output=$("$MODULE" help "$cmd" 2>&1)
    assert_equals 0 "$?" "help $cmd should exit 0"
    assert_not_null "$output" "help $cmd should produce output"
  done
}

function test_no_args_shows_usage() {
  log_test_step "Testing that no arguments shows usage and fails"

  "$MODULE" 2>/dev/null
  assert_not_equals 0 "$?" "No arguments should exit non-zero"
}

# =============================================================================
# TEST: list - Lists Instances
# =============================================================================

function test_list_empty() {
  log_test_step "Testing 'list' with no instances"

  local output
  output=$("$MODULE" list 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list should succeed even with no instances"
}

function test_list_json_empty() {
  log_test_step "Testing 'list --json' with no instances"

  local output
  output=$("$MODULE" list --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list --json should succeed"
  # Should output valid JSON array
  echo "$output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "list --json output should be valid JSON"
}

# =============================================================================
# TEST: generate-id - Produces Instance ID
# =============================================================================

function test_generate_id_valid_blueprint() {
  log_test_step "Testing 'generate-id factorio' produces output"

  local output
  output=$("$MODULE" generate-id factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "generate-id should succeed with valid blueprint"
  assert_not_null "$output" "generate-id should produce output"
}

function test_generate_id_with_bp_extension() {
  log_test_step "Testing 'generate-id factorio.bp' with extension"

  local output
  output=$("$MODULE" generate-id factorio.bp 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "generate-id should succeed with .bp extension"
  assert_not_null "$output" "generate-id should produce output"
}

function test_generate_id_missing_blueprint() {
  log_test_step "Testing 'generate-id' without blueprint argument"

  "$MODULE" generate-id 2>/dev/null
  assert_not_equals 0 "$?" "generate-id without blueprint should fail"
}

function test_generate_id_invalid_blueprint() {
  log_test_step "Testing 'generate-id' with nonexistent blueprint"

  "$MODULE" generate-id totally_nonexistent_blueprint_xyz 2>/dev/null
  assert_not_equals 0 "$?" "generate-id with invalid blueprint should fail"
}

# =============================================================================
# TEST: create - Creates Instance
# =============================================================================

function test_create_instance() {
  log_test_step "Testing 'create' command creates instance"

  local instance_name
  instance_name="test-create-$$"

  # Setup prerequisites
  setup_instance_prereqs "factorio" "$instance_name" "$TEST_INSTALL_DIR"

  local output
  output=$("$MODULE" create factorio \
    --install-dir "$TEST_INSTALL_DIR" \
    --name "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "create should succeed"
  assert_not_null "$output" "create should output the instance name"
  assert_contains "$output" "$instance_name" "create should echo back instance name"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")
}

function test_create_missing_blueprint() {
  log_test_step "Testing 'create' without blueprint argument fails"

  "$MODULE" create --install-dir "$TEST_INSTALL_DIR" 2>/dev/null
  assert_not_equals 0 "$?" "create without blueprint should fail"
}

function test_create_invalid_blueprint() {
  log_test_step "Testing 'create' with invalid blueprint fails"

  "$MODULE" create nonexistent_xyz_blueprint --install-dir "$TEST_INSTALL_DIR" 2>/dev/null
  assert_not_equals 0 "$?" "create with invalid blueprint should fail"
}

# =============================================================================
# TEST: info - Shows Instance Info
# =============================================================================

function test_info_instance() {
  log_test_step "Testing 'info' command shows instance configuration"

  local instance_name="test-info-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for info test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" info "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info should succeed"
  assert_not_null "$output" "info should produce output"
  assert_contains "$output" "name=" "info output should contain name key"
}

function test_info_json_instance() {
  log_test_step "Testing 'info --json' outputs valid JSON"

  local instance_name="test-info-json-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for info --json test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" info "$instance_name" --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info --json should succeed"
  echo "$output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "info --json output should be valid JSON"
}

# A native instance must surface a derived cgroup_path (kgsm.slice/<name>) so kgsm-monitor
# can sample its cgroup counters directly instead of falling back to the /proc tree.
function test_info_json_native_emits_cgroup_path() {
  log_test_step "Testing 'info --json' emits cgroup_path for a native instance"

  local instance_name="test-cgpath-native-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Native instance should be created for cgroup_path test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local cgroup_path
  cgroup_path=$("$MODULE" info "$instance_name" --json 2>/dev/null | jq -r '.cgroup_path')

  assert_not_null "$cgroup_path" "native cgroup_path should be present"
  assert_not_equals "" "$cgroup_path" "native cgroup_path should be non-empty"
  assert_contains "$cgroup_path" "kgsm.slice" "native cgroup_path should sit under the cgroup base"
  assert_contains "$cgroup_path" "$instance_name" "native cgroup_path should end in the instance name"
}

# A container instance is supervised by Docker, which owns its cgroup; KGSM must NOT
# claim one, so cgroup_path is the empty string (the monitor reads the Docker cgroup).
function test_info_json_container_cgroup_path_empty() {
  log_test_step "Testing 'info --json' emits empty cgroup_path for a container instance"

  local instance_name="test-cgpath-container-$$"
  create_test_instance "vrising" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Container instance should be created for cgroup_path test"
  _TEARDOWN_INSTANCES+=("vrising:$instance_name")

  local cgroup_path
  cgroup_path=$("$MODULE" info "$instance_name" --json 2>/dev/null | jq -r '.cgroup_path')

  assert_equals "" "$cgroup_path" "container cgroup_path should be empty (Docker owns the cgroup)"
}

function test_info_missing_instance() {
  log_test_step "Testing 'info' with missing instance argument fails"

  "$MODULE" info 2>/dev/null
  assert_not_equals 0 "$?" "info without instance should fail"
}

function test_info_invalid_instance() {
  log_test_step "Testing 'info' with nonexistent instance fails loudly"

  "$MODULE" info totally_nonexistent_instance_xyz 2>/dev/null
  assert_equals "$EC_FILE_NOT_FOUND" "$?" \
    "info with nonexistent instance should fail with EC_FILE_NOT_FOUND"
}

function test_info_json_invalid_instance() {
  log_test_step "Testing 'info --json' with nonexistent instance fails (no skeletal JSON)"

  # The bug this guards: a missing instance must NOT render a skeletal object
  # ({cgroup_path:"",ports:[]}) with exit 0 — a consumer (kgsm-lib/watchdog) must
  # be able to tell "no such instance" apart from real data.
  local output exit_code
  output=$("$MODULE" info totally_nonexistent_instance_xyz --json 2>/dev/null)
  exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "info --json for a nonexistent instance should fail with EC_FILE_NOT_FOUND"
  assert_null "$output" \
    "info --json for a nonexistent instance must emit no JSON on stdout"
}

# =============================================================================
# TEST: find - Returns Instance Config Path
# =============================================================================

function test_find_instance() {
  log_test_step "Testing 'find' command returns instance config path"

  local instance_name="test-find-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for find test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" find "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "find should succeed"
  assert_not_null "$output" "find should return a path"
  assert_file_exists "$output" "find should return path to existing file"
}

function test_find_missing_instance_arg() {
  log_test_step "Testing 'find' without instance argument fails"

  "$MODULE" find 2>/dev/null
  assert_not_equals 0 "$?" "find without instance should fail"
}

function test_find_nonexistent_instance() {
  log_test_step "Testing 'find' with nonexistent instance fails"

  "$MODULE" find totally_nonexistent_instance_xyz 2>/dev/null
  assert_not_equals 0 "$?" "find with nonexistent instance should fail"
}

# =============================================================================
# TEST: list - Lists Instances After Creation
# =============================================================================

function test_list_after_creation() {
  log_test_step "Testing 'list' shows created instance"

  local instance_name="test-list-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" list 2>&1)

  assert_contains "$output" "$instance_name" "list should include the created instance"
}

function test_list_json_after_creation() {
  log_test_step "Testing 'list --json' includes created instance"

  local instance_name="test-list-json-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" list --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list --json should succeed"
  echo "$output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "list --json output should be valid JSON"
  assert_contains "$output" "$instance_name" "list --json should include the created instance"
}

function test_list_filter_by_blueprint() {
  log_test_step "Testing 'list factorio' filters by blueprint"

  local instance_name="test-list-filter-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" list factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list factorio should succeed"
  assert_contains "$output" "$instance_name" "list factorio should include factorio instance"
}

# =============================================================================
# TEST: remove - Removes Instance
# =============================================================================

function test_remove_instance() {
  log_test_step "Testing 'remove' command removes instance"

  local instance_name="test_remove_instance"
  create_test_instance "factorio" "$instance_name" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for remove test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" remove "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "remove should succeed"

  # Instance should no longer be findable
  "$MODULE" find "$instance_name" 2>/dev/null
  assert_not_equals 0 "$?" "find should fail after remove"
}

function test_remove_missing_instance_arg() {
  log_test_step "Testing 'remove' without instance argument fails"

  "$MODULE" remove 2>/dev/null
  assert_not_equals 0 "$?" "remove without instance should fail"
}

function test_remove_nonexistent_instance() {
  log_test_step "Testing 'remove' with nonexistent instance fails"

  "$MODULE" remove totally_nonexistent_instance_xyz 2>/dev/null
  assert_not_equals 0 "$?" "remove with nonexistent instance should fail"
}

# =============================================================================
# TEST: config-set / config-get
# =============================================================================

function test_config_set_get_roundtrip() {
  log_test_step "Testing config-set then config-get round-trips a simple value"

  local instance_name="test-cfg-roundtrip-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" config-set "$instance_name" "auto_update=true" 2>&1)
  assert_equals 0 "$?" "config-set should succeed"
  assert_contains "$output" "Set" "config-set should report success"

  output=$("$MODULE" config-get "$instance_name" "auto_update" 2>&1)
  assert_equals 0 "$?" "config-get should succeed"
  assert_equals "true" "$output" "config-get should return the value just set"
}

function test_config_set_complex_value_roundtrip() {
  log_test_step "Testing config-set preserves spaces, '=', and backslashes via the CLI"

  local instance_name="test-cfg-complex-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  # The whole key=value rides as a single argv element; the value contains
  # spaces, an embedded '=', and a backslash.
  local value='--start-server saves/my=world.zip --regex \d+'
  "$MODULE" config-set "$instance_name" "executable_arguments=$value" >/dev/null 2>&1
  assert_equals 0 "$?" "config-set should succeed with a complex value"

  local output
  output=$("$MODULE" config-get "$instance_name" "executable_arguments" 2>&1)
  assert_equals 0 "$?" "config-get should succeed"
  assert_equals "$value" "$output" \
    "Complex value must round-trip verbatim through the CLI"
}

function test_config_set_value_with_dashdash_flag() {
  log_test_step "Testing config-set value containing '--json' is not consumed as a flag"

  local instance_name="test-cfg-flagval-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local value='--json --verbose'
  "$MODULE" config-set "$instance_name" "executable_arguments=$value" >/dev/null 2>&1
  assert_equals 0 "$?" "config-set should succeed even when the value contains --json"

  local output
  output=$("$MODULE" config-get "$instance_name" "executable_arguments" 2>&1)
  assert_equals "$value" "$output" \
    "A value containing --json must not be stripped by global flag parsing"
}

function test_config_set_refuses_protected_key() {
  log_test_step "Testing config-set refuses an identity key and leaves it unchanged"

  local instance_name="test-cfg-protected-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  "$MODULE" config-set "$instance_name" "name=hacked" 2>/dev/null
  assert_not_equals 0 "$?" "config-set should refuse the identity key 'name'"

  local output
  output=$("$MODULE" config-get "$instance_name" "name" 2>&1)
  assert_equals "$instance_name" "$output" "'name' must be unchanged after refusal"
}

function test_config_set_toggle_key_hints_dedicated_flow() {
  log_test_step "Testing config-set refuses a toggle and points to the files flow"

  local instance_name="test-cfg-toggle-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" config-set "$instance_name" "enable_firewall_management=true" 2>&1)
  assert_not_equals 0 "$?" "config-set should refuse the integration toggle"
  assert_contains "$output" "files firewall" \
    "Refusal should point to the dedicated 'files firewall' flow"
}

function test_config_set_rejects_missing_assignment() {
  log_test_step "Testing config-set with a non-assignment argument fails"

  local instance_name="test-cfg-noassign-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  "$MODULE" config-set "$instance_name" "auto_update" 2>/dev/null
  assert_not_equals 0 "$?" "config-set without '=' should fail"
}

function test_config_set_missing_args() {
  log_test_step "Testing config-set with missing arguments fails"

  "$MODULE" config-set 2>/dev/null
  assert_not_equals 0 "$?" "config-set with no arguments should fail"
}

function test_config_get_missing_args() {
  log_test_step "Testing config-get with missing arguments fails"

  "$MODULE" config-get 2>/dev/null
  assert_not_equals 0 "$?" "config-get with no arguments should fail"
}

function test_config_get_unknown_instance() {
  log_test_step "Testing config-get on an unknown instance fails"

  "$MODULE" config-get totally_nonexistent_instance_xyz auto_update 2>/dev/null
  assert_not_equals 0 "$?" "config-get on a missing instance should fail"
}

function test_help_config_subcommands() {
  log_test_step "Testing help output covers config-get and config-set"

  local output
  output=$("$MODULE" help 2>&1)
  assert_contains "$output" "config-get" "main help should mention config-get"
  assert_contains "$output" "config-set" "main help should mention config-set"

  output=$("$MODULE" help config-set 2>&1)
  assert_equals 0 "$?" "help config-set should exit 0"
  assert_contains "$output" "config-set" "help config-set should describe the command"

  output=$("$MODULE" help config-get 2>&1)
  assert_equals 0 "$?" "help config-get should exit 0"
  assert_contains "$output" "config-get" "help config-get should describe the command"
}

# =============================================================================
# TEST: Tier-1 ops — backups / create-backup / restore-backup / update /
#       check-update. These forward to the per-instance management file (which
#       accepts the same dash-free command names) and back the kgsm-api Tier-1
#       endpoints. See commands/instances.sh and templates/manage.*.d.
# =============================================================================

function test_help_lists_tier1_ops() {
  log_test_step "Testing main help lists the Tier-1 ops commands"

  local output
  output=$("$MODULE" help 2>&1)
  assert_contains "$output" "backups" "help should mention backups"
  assert_contains "$output" "create-backup" "help should mention create-backup"
  assert_contains "$output" "restore-backup" "help should mention restore-backup"
  assert_contains "$output" "check-update" "help should mention check-update"
  assert_contains "$output" "update" "help should mention update"
}

function test_help_tier1_subcommands() {
  log_test_step "Testing help sub-commands for Tier-1 ops"

  local commands=("backups" "create-backup" "restore-backup" "update" "check-update")
  for cmd in "${commands[@]}"; do
    local output
    output=$("$MODULE" help "$cmd" 2>&1)
    assert_equals 0 "$?" "help $cmd should exit 0"
    assert_not_null "$output" "help $cmd should produce output"
    assert_contains "$output" "$cmd" "help $cmd should describe the command"
  done
}

# Point a created instance at a real backups dir we control. A freshly created
# test instance is not fully provisioned (no directory step), so its config's
# backups_dir is empty; the management file's 01-config sources every config
# line with last-wins semantics, so an appended key takes effect at runtime.
function _seed_backups_dir() {
  local instance_name="$1"
  local bdir="$2"
  local cfg
  cfg=$("$MODULE" find "$instance_name" 2>/dev/null)
  [[ -f "$cfg" ]] || return 1
  mkdir -p "$bdir"
  printf 'backups_dir="%s"\n' "$bdir" >> "$cfg"
}

# Write one backup into a seeded store: a directory holding the manifest that
# makes it a backup. A directory without a manifest is not a backup, which is
# what test_backups_ignores_unmanifested_dirs relies on.
# Args: $1 = backups dir, $2 = backup id, $3 = created_at (ISO-8601 UTC)
function _seed_backup() {
  local bdir="$1"
  local id="$2"
  local created_at="$3"

  mkdir -p "$bdir/$id" || return 1
  jq -n --arg id "$id" --arg created_at "$created_at" \
    '{schema_version: 1, id: $id, instance: "seeded", blueprint: "factorio",
      version: "1.0.0", created_at: $created_at, compressed: true,
      consistency: "cold", sources: ["install", "saves"], size_bytes: 1024,
      file_count: 3, sha256: null}' > "$bdir/$id/manifest.json"
}

function test_backups_lists_one_per_line() {
  log_test_step "Testing 'backups' prints each backup id on its own line, newest first"

  local instance_name="test-backups-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for backups test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local bdir="$TEST_INSTALL_DIR/${instance_name}-backups"
  _seed_backups_dir "$instance_name" "$bdir"
  assert_equals 0 "$?" "should be able to seed a backups dir for the instance"

  local older="${instance_name}-20260621T100000Z-aaaaaa"
  local newer="${instance_name}-20260621T110000Z-bbbbbb"
  _seed_backup "$bdir" "$older" "2026-06-21T10:00:00Z"
  _seed_backup "$bdir" "$newer" "2026-06-21T11:00:00Z"

  local output line_count
  output=$("$MODULE" backups "$instance_name" 2>/dev/null)
  assert_equals 0 "$?" "backups should succeed"
  # One backup per line — the contract kgsm-api parses. A regression to
  # space-separated output would collapse both ids onto a single line.
  line_count=$(printf '%s\n' "$output" | grep -c "^${instance_name}-")
  assert_equals 2 "$line_count" "backups should print exactly two backup lines"
  assert_contains "$output" "$older" "backups should list the older backup"
  assert_contains "$output" "$newer" "backups should list the newer backup"

  # Newest first, ordered by the manifest's created_at.
  assert_equals "$newer" "$(printf '%s\n' "$output" | head -n1)" \
    "backups should list the newest backup first"
}

function test_backups_json_emits_manifests() {
  log_test_step "Testing 'backups --json' emits the full manifests"

  local instance_name="test-backups-json-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for backups --json test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local bdir="$TEST_INSTALL_DIR/${instance_name}-backups-json"
  _seed_backups_dir "$instance_name" "$bdir"
  assert_equals 0 "$?" "should be able to seed a backups dir for the instance"

  local id="${instance_name}-20260621T100000Z-aaaaaa"
  _seed_backup "$bdir" "$id" "2026-06-21T10:00:00Z"

  local output
  output=$("$MODULE" backups "$instance_name" --json 2>/dev/null)
  assert_equals 0 "$?" "backups --json should succeed"

  # Must be valid JSON — the API deserializes it directly, so any stray progress
  # line or normalization would break the consumer.
  assert_command_succeeds "printf '%s' '$output' | jq -e 'type == \"array\"'" \
    "backups --json should emit a JSON array"

  assert_equals "$id" "$(printf '%s' "$output" | jq -r '.[0].id')" \
    "the manifest should carry the backup id"
  assert_equals "1024" "$(printf '%s' "$output" | jq -r '.[0].size_bytes')" \
    "the manifest should carry the recorded size"
  assert_equals "saves" "$(printf '%s' "$output" | jq -r '.[0].sources[1]')" \
    "the manifest should record that saves were captured"
}

function test_backups_ignores_unmanifested_dirs() {
  log_test_step "Testing 'backups' ignores store directories that carry no manifest"

  local instance_name="test-backups-nomanifest-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local bdir="$TEST_INSTALL_DIR/${instance_name}-backups-nomanifest"
  _seed_backups_dir "$instance_name" "$bdir"
  assert_equals 0 "$?" "should be able to seed a backups dir for the instance"

  local id="${instance_name}-20260621T100000Z-aaaaaa"
  _seed_backup "$bdir" "$id" "2026-06-21T10:00:00Z"

  # An interrupted build leaves a directory with no manifest. It is not a backup
  # and must never be offered for restore.
  mkdir -p "$bdir/${instance_name}-20260621T120000Z-cccccc"

  local output line_count
  output=$("$MODULE" backups "$instance_name" 2>/dev/null)
  assert_equals 0 "$?" "backups should succeed"
  line_count=$(printf '%s\n' "$output" | grep -c "^${instance_name}-")
  assert_equals 1 "$line_count" "only the manifest-bearing directory is a backup"
  assert_equals "$id" "$output" "backups should list only the complete backup"
}

# Container parity: the dash-free commands + one-per-line listing are added
# identically to manage.container.d, so a container instance must behave the
# same. (vrising is the suite's standard container blueprint.)
function test_backups_container_lists_one_per_line() {
  log_test_step "Testing 'backups' on a container instance lists one backup per line"

  local instance_name="test-backups-ctr-$$"
  create_test_instance "vrising" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Container instance should be created for backups test"
  _TEARDOWN_INSTANCES+=("vrising:$instance_name")

  local bdir="$TEST_INSTALL_DIR/${instance_name}-backups"
  _seed_backups_dir "$instance_name" "$bdir"
  assert_equals 0 "$?" "should be able to seed a backups dir for the container instance"
  _seed_backup "$bdir" "${instance_name}-20260621T100000Z-aaaaaa" "2026-06-21T10:00:00Z"
  _seed_backup "$bdir" "${instance_name}-20260621T110000Z-bbbbbb" "2026-06-21T11:00:00Z"

  local output line_count
  output=$("$MODULE" backups "$instance_name" 2>/dev/null)
  assert_equals 0 "$?" "backups should succeed for a container instance"
  line_count=$(printf '%s\n' "$output" | grep -c "^${instance_name}-")
  assert_equals 2 "$line_count" "container backups should print exactly two backup lines"
}

function test_backups_empty_is_honest() {
  log_test_step "Testing 'backups' prints nothing (never a fabricated 0) with no snapshots"

  local instance_name="test-backups-empty-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local bdir="$TEST_INSTALL_DIR/${instance_name}-backups-empty"
  _seed_backups_dir "$instance_name" "$bdir"
  assert_equals 0 "$?" "should be able to seed an empty backups dir for the instance"

  local output
  output=$("$MODULE" backups "$instance_name" 2>/dev/null)
  assert_equals 0 "$?" "backups should succeed with no snapshots"
  assert_equals "" "$output" "backups should print nothing when there are no snapshots"
}

function test_backups_unprovisioned_no_root_glob() {
  log_test_step "Testing 'backups' on an instance with no backups dir emits nothing (never a root glob)"

  local instance_name="test-backups-unprov-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  # A freshly created (unprovisioned) instance has an empty backups_dir. The
  # command must report nothing — never forward to a bare "$dir"/* glob that
  # would expand to "/" and fabricate names (bin, boot, ...).
  local output
  output=$("$MODULE" backups "$instance_name" 2>/dev/null)
  assert_equals 0 "$?" "backups should succeed on an unprovisioned instance"
  assert_equals "" "$output" \
    "backups must emit nothing (never a root-glob) when no backups dir is configured"
}

function test_backups_missing_instance() {
  log_test_step "Testing 'backups' without instance argument fails"

  "$MODULE" backups 2>/dev/null
  assert_not_equals 0 "$?" "backups without instance should fail"
}

function test_backups_unknown_instance() {
  log_test_step "Testing 'backups' on a nonexistent instance fails"

  "$MODULE" backups totally_nonexistent_instance_xyz 2>/dev/null
  assert_not_equals 0 "$?" "backups on a missing instance should fail"
}

function test_create_backup_missing_instance() {
  log_test_step "Testing 'create-backup' without instance argument fails"

  "$MODULE" create-backup 2>/dev/null
  assert_not_equals 0 "$?" "create-backup without instance should fail"
}

function test_restore_backup_missing_instance() {
  log_test_step "Testing 'restore-backup' without instance argument fails"

  "$MODULE" restore-backup 2>/dev/null
  assert_not_equals 0 "$?" "restore-backup without instance should fail"
}

function test_restore_backup_missing_source() {
  log_test_step "Testing 'restore-backup <instance>' without a source fails"

  local instance_name="test-restore-noarg-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  "$MODULE" restore-backup "$instance_name" 2>/dev/null
  assert_not_equals 0 "$?" "restore-backup without <source> should fail"
}

function test_update_missing_instance() {
  log_test_step "Testing 'update' without instance argument fails"

  "$MODULE" update 2>/dev/null
  assert_not_equals 0 "$?" "update without instance should fail"
}

function test_check_update_missing_instance() {
  log_test_step "Testing 'check-update' without instance argument fails"

  "$MODULE" check-update 2>/dev/null
  assert_not_equals 0 "$?" "check-update without instance should fail"
}

function test_check_update_unknown_instance() {
  log_test_step "Testing 'check-update' on a nonexistent instance fails"

  "$MODULE" check-update totally_nonexistent_instance_xyz 2>/dev/null
  assert_not_equals 0 "$?" "check-update on a missing instance should fail"
}

# =============================================================================
# TEST: version — installed/latest version query (backs kgsm-lib
#       GetInstalledVersion/GetLatestVersion: `instances version <i> --installed`
#       / `--latest`). Forwards to the management file's `version` command.
# =============================================================================

function test_help_lists_version() {
  log_test_step "Testing main help lists the version command"

  local output
  output=$("$MODULE" help 2>&1)
  assert_contains "$output" "version" "help should mention version"
}

function test_help_version_subcommand() {
  log_test_step "Testing 'help version' describes the command"

  local output
  output=$("$MODULE" help version 2>&1)
  assert_equals 0 "$?" "help version should exit 0"
  assert_contains "$output" "version" "help version should describe the command"
  assert_contains "$output" "--latest" "help version should document --latest"
}

function test_version_installed_default() {
  log_test_step "Testing 'version <instance>' and '--installed' return the installed version"

  local instance_name="test-version-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for version test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  # No installed version file yet → the management file reports "unknown"
  # (honest), never empty/fabricated; both bare and --installed take that path.
  local bare installed
  bare=$("$MODULE" version "$instance_name" 2>/dev/null)
  assert_equals 0 "$?" "version <instance> should succeed"
  assert_not_null "$bare" "version <instance> should print the installed version"

  installed=$("$MODULE" version "$instance_name" --installed 2>/dev/null)
  assert_equals 0 "$?" "version --installed should succeed"
  assert_equals "$bare" "$installed" "--installed should match the bare default"
}

function test_version_missing_instance() {
  log_test_step "Testing 'version' without instance argument fails"

  "$MODULE" version 2>/dev/null
  assert_not_equals 0 "$?" "version without instance should fail"
}

function test_version_unknown_instance() {
  log_test_step "Testing 'version' on a nonexistent instance fails"

  "$MODULE" version totally_nonexistent_instance_xyz 2>/dev/null
  assert_not_equals 0 "$?" "version on a missing instance should fail"
}

function test_version_invalid_flag() {
  log_test_step "Testing 'version <instance> --bogus' rejects an unknown flag"

  local instance_name="test-version-badflag-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  "$MODULE" version "$instance_name" --bogus 2>/dev/null
  assert_not_equals 0 "$?" "version with an unknown flag should fail"
}

