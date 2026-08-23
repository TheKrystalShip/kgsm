#!/usr/bin/env bash

# KGSM Library Placement Unit Tests
#
# Test Type: UNIT
# Target: placement through libraries — which library a new instance lands in,
# the free-space gate that guards it, the layout inside the library, and the
# key an instance records its root in.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="library_placement"
readonly HANDLER="$KGSM_ROOT/commands/handlers/libraries.sh"
readonly INSTALL_MODULE="$KGSM_ROOT/commands/install.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up library placement tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Library handler should exist"
  assert_file_executable "$INSTALL_MODULE" "install.sh should be executable"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"

  source "$HANDLER"

  assert_not_null "$EC_LIBRARY_OFFLINE" "EC_LIBRARY_OFFLINE should be defined"
  assert_not_null "$EC_INSUFFICIENT_DISK" "EC_INSUFFICIENT_DISK should be defined"

  assert_function_exists "__logic_library_resolve_placement" \
    "__logic_library_resolve_placement should be exported"
  assert_function_exists "__logic_library_space_check" \
    "__logic_library_space_check should be exported"
  assert_function_exists "__logic_stamp_instance_library_dir" \
    "__logic_stamp_instance_library_dir should be exported"
  assert_function_exists "__library_instances_subdir" \
    "__library_instances_subdir should be exported"
}

# Every test starts from an empty registry, an empty instance tree and no
# configured default, so no test can pass or fail on what another one left.
function setup() {
  rm -f "$(__library_registry_file)"
  rm -rf "${KGSM_INSTANCES_DIR:?}"/*
  unset config_default_library
  declare -g PLACEMENT_TEST_DIR="${KGSM_TEST_SANDBOX}/placement_${RANDOM}_$$"
  mkdir -p "$PLACEMENT_TEST_DIR"
}

function teardown() {
  rm -f "$(__library_registry_file)"
  rm -rf "${KGSM_INSTANCES_DIR:?}"/*
  rm -rf "${PLACEMENT_TEST_DIR:?}"
  rm -f "${KGSM_USER_BLUEPRINTS_DIR}/hungry.bp.yaml"
}

# Registers a library under the per-test scratch directory and echoes its root.
# Args: $1 = library name
function _add_library() {
  local root="${PLACEMENT_TEST_DIR}/$1"
  mkdir -p "$root"
  __logic_library_add "$root" "$1" > /dev/null
  echo "$root"
}

# Writes an instance config carrying the keys the stamping logic reads.
# Args: $1 = config file path, $2 = working directory
function _write_instance_config() {
  local config_file="$1"
  local working_dir="$2"

  mkdir -p "$(dirname "$config_file")"
  {
    printf 'name="probe"\n'
    printf 'working_dir="%s"\n' "$working_dir"
    printf 'runtime="native"\n'
  } > "$config_file"
}

# A blueprint declaring more disk than any filesystem here can have.
# Args: $1 = base_disk_mb
function _write_hungry_blueprint() {
  local base_disk_mb="$1"

  mkdir -p "$KGSM_USER_BLUEPRINTS_DIR"
  local source_blueprint
  source_blueprint="$(__find_blueprint factorio)"

  yq ".name = \"hungry\" | .metadata.base_disk_mb = ${base_disk_mb}" \
    "$source_blueprint" > "${KGSM_USER_BLUEPRINTS_DIR}/hungry.bp.yaml"
}

# =============================================================================
# RESOLUTION ORDER
# =============================================================================

function test_resolve_prefers_the_named_library() {
  log_test_step "Testing --library wins over the configured default"

  _add_library one > /dev/null
  _add_library two > /dev/null
  declare -g config_default_library="one"

  local resolved
  resolved="$(__logic_library_resolve_placement "two")"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" "A named library should resolve"
  assert_equals "two" "$resolved" "The named library should win"
}

function test_resolve_falls_back_to_the_configured_default() {
  log_test_step "Testing default_library answers when no library is named"

  _add_library one > /dev/null
  _add_library two > /dev/null
  declare -g config_default_library="two"

  local resolved
  resolved="$(__logic_library_resolve_placement "")"

  assert_equals "two" "$resolved" "The configured default should answer"
}

function test_resolve_falls_back_to_the_sole_library() {
  log_test_step "Testing a single registered library is the implicit default"

  _add_library only > /dev/null

  local resolved
  resolved="$(__logic_library_resolve_placement "")"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" "The sole library should resolve"
  assert_equals "only" "$resolved" "The sole library should answer"
}

function test_resolve_refuses_when_nothing_is_registered() {
  log_test_step "Testing resolution with an empty registry"

  __logic_library_resolve_placement ""
  assert_equals "$?" "$EC_NOT_FOUND" \
    "An empty registry should report nothing to place into"
}

function test_resolve_refuses_an_ambiguous_choice() {
  log_test_step "Testing resolution with several libraries and no default"

  _add_library one > /dev/null
  _add_library two > /dev/null

  __logic_library_resolve_placement ""
  assert_equals "$?" "$EC_MISSING_ARG" \
    "Several libraries and no default should ask rather than guess"
}

function test_resolve_refuses_an_unregistered_name() {
  log_test_step "Testing resolution of a library that is not registered"

  _add_library one > /dev/null

  __logic_library_resolve_placement "nope"
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" \
    "An unregistered name should not resolve"
  assert_equals "flag" "$__library_resolve_source_out" \
    "The refusal should report which source named it"
}

function test_resolve_reports_an_unregistered_default() {
  log_test_step "Testing resolution when default_library names nothing"

  _add_library one > /dev/null
  declare -g config_default_library="ghost"

  __logic_library_resolve_placement ""
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" \
    "An unregistered default should not resolve"
  assert_equals "default" "$__library_resolve_source_out" \
    "The refusal should name the config as the source"
  assert_equals "ghost" "$__library_resolve_name_out" \
    "The refusal should carry the configured name"
}

# =============================================================================
# SPACE GATE
# =============================================================================

function test_space_check_passes_with_room() {
  log_test_step "Testing the space gate against a modest requirement"

  local root
  root="$(_add_library roomy)"

  __logic_library_space_check "$root" 1 0
  assert_equals "$?" "$EC_SUCCESS" "One megabyte should fit"
  assert_matches "$__library_space_free_out" "^[0-9]+$" \
    "The gate should report the free bytes it measured"
}

function test_space_check_refuses_without_room() {
  log_test_step "Testing the space gate against an impossible requirement"

  local root
  root="$(_add_library tight)"

  __logic_library_space_check "$root" 999999999 0
  assert_equals "$?" "$EC_INSUFFICIENT_DISK" \
    "A petabyte should not fit"
  assert_greater_than "$__library_space_required_out" "$__library_space_free_out" \
    "The refusal should report a requirement above the free space"
}

function test_space_check_counts_the_margin() {
  log_test_step "Testing the margin is added to the declared requirement"

  local root
  root="$(_add_library margined)"

  __logic_library_space_check "$root" 1 1
  local required="$__library_space_required_out"

  assert_equals "$((2 * 1024 * 1024))" "$required" \
    "The requirement should be the declared size plus the margin"
}

function test_space_check_skips_an_undeclared_requirement() {
  log_test_step "Testing a blueprint that declares no size"

  local root
  root="$(_add_library unknown)"

  __logic_library_space_check "$root" "" 1024
  assert_equals "$?" "$EC_NOT_FOUND" \
    "An undeclared size should leave the gate unable to answer"
  assert_null "$__library_space_required_out" \
    "Nothing should be reported as required when nothing was declared"
}

function test_install_refuses_a_library_without_room() {
  log_test_step "Testing install refuses before creating anything"

  local root
  root="$(_add_library hungry-lib)"
  _write_hungry_blueprint 999999999

  local output
  output=$("$INSTALL_MODULE" hungry --library hungry-lib --name hungry-probe 2>&1)
  local exit_code=$?

  assert_equals "$EC_INSUFFICIENT_DISK" "$exit_code" \
    "install should refuse with EC_INSUFFICIENT_DISK"
  assert_contains "$output" "free" "The refusal should report the measured free space"
  assert_dir_not_exists "${root}/instances" \
    "Nothing should be created in the library when the gate refuses"
}

function test_install_skip_space_check_still_reports_the_shortfall() {
  log_test_step "Testing --skip-space-check reports what it skipped"

  _add_library hungry-lib > /dev/null
  _write_hungry_blueprint 999999999

  local output
  output=$("$INSTALL_MODULE" hungry --library hungry-lib --name hungry-probe \
    --skip-space-check 2>&1)
  local exit_code=$?

  assert_not_equals "$EC_INSUFFICIENT_DISK" "$exit_code" \
    "--skip-space-check should carry past the gate"
  assert_contains "$output" "free" \
    "--skip-space-check should still print the measured shortfall"
}

# =============================================================================
# LAYOUT AND THE RECORDED ROOT
# =============================================================================

function test_instances_subdir_is_the_library_namespace() {
  log_test_step "Testing the namespace directory a library holds instances under"

  local subdir
  subdir="$(__library_instances_subdir "/mnt/ssd/kgsm")"

  assert_equals "/mnt/ssd/kgsm/instances" "$subdir" \
    "Instances live under <library>/instances"
}

function test_create_places_the_instance_nested_in_the_library() {
  log_test_step "Testing an instance is created at <library>/instances/<bp>/<name>"

  local root
  root="$(_add_library nested)"

  local instance_name="placement-nested-$$"
  mkdir -p "${root}/instances/factorio/${instance_name}"
  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "${root}/instances/factorio/${instance_name}" \
    "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"

  "$INSTANCES_MODULE" create factorio --library nested --id "$instance_name" \
    > /dev/null 2>&1
  local exit_code=$?

  assert_equals 0 "$exit_code" "create should succeed"

  local config_file="${root}/instances/factorio/${instance_name}/${instance_name}.config.ini"
  assert_file_exists "$config_file" \
    "The instance config should live inside the library's instances directory"
  assert_file_contains "$config_file" \
    "working_dir=\"${root}/instances/factorio/${instance_name}\"" \
    "The working directory should be nested under the library"

  rm -f "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"
}

function test_create_records_the_library_root() {
  log_test_step "Testing library_dir is stamped at creation"

  local root
  root="$(_add_library stamped)"

  local instance_name="placement-stamped-$$"
  mkdir -p "${root}/instances/factorio/${instance_name}"
  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "${root}/instances/factorio/${instance_name}" \
    "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"

  "$INSTANCES_MODULE" create factorio --library stamped --id "$instance_name" \
    > /dev/null 2>&1

  local config_file="${root}/instances/factorio/${instance_name}/${instance_name}.config.ini"
  assert_file_contains "$config_file" "library_dir=\"${root}\"" \
    "The instance should record the library root it was placed in"

  rm -f "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"
}

function test_create_without_a_flag_uses_the_sole_library() {
  log_test_step "Testing create with no --library and one registered library"

  local root
  root="$(_add_library implicit)"

  local instance_name="placement-implicit-$$"
  mkdir -p "${root}/instances/factorio/${instance_name}"
  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "${root}/instances/factorio/${instance_name}" \
    "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"

  "$INSTANCES_MODULE" create factorio --id "$instance_name" > /dev/null 2>&1
  local exit_code=$?

  assert_equals 0 "$exit_code" "create should resolve the sole library"

  local config_file="${root}/instances/factorio/${instance_name}/${instance_name}.config.ini"
  assert_file_contains "$config_file" "library_dir=\"${root}\"" \
    "The instance should land in the sole registered library"

  rm -f "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"
}

function test_create_without_a_flag_uses_the_configured_default() {
  log_test_step "Testing create with no --library and a configured default"

  local first second
  first="$(_add_library first-lib)"
  second="$(_add_library second-lib)"

  # The sandbox loads the config once and exports it, and every kgsm invocation
  # from a test inherits that environment rather than re-reading the file, so
  # the configured default is stated in the form the engine reads it in.
  export config_default_library="second-lib"

  local instance_name="placement-default-$$"
  mkdir -p "${second}/instances/factorio/${instance_name}"
  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "${second}/instances/factorio/${instance_name}" \
    "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"

  "$INSTANCES_MODULE" create factorio --id "$instance_name" > /dev/null 2>&1
  local exit_code=$?

  unset config_default_library

  assert_equals 0 "$exit_code" "create should resolve the configured default"

  local instance_config="${second}/instances/factorio/${instance_name}/${instance_name}.config.ini"
  assert_file_contains "$instance_config" "library_dir=\"${second}\"" \
    "The instance should land in the configured default library"
  assert_dir_not_exists "${first}/instances" \
    "Nothing should be placed in the library that is not the default"

  rm -f "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"
}

function test_create_refuses_an_unregistered_library() {
  log_test_step "Testing create with a library that is not registered"

  _add_library registered > /dev/null

  local output
  output=$("$INSTANCES_MODULE" create factorio --library ghost 2>&1)
  local exit_code=$?

  assert_equals "$EC_LIBRARY_NOT_FOUND" "$exit_code" \
    "create should refuse an unregistered library"
  assert_contains "$output" "ghost" "The refusal should name the library"
}

function test_create_refuses_an_offline_library() {
  log_test_step "Testing create into a library whose root has gone"

  local root
  root="$(_add_library vanishing)"
  mv "$root" "${root}-moved"

  local output
  output=$("$INSTANCES_MODULE" create factorio --library vanishing 2>&1)
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "create should refuse an offline library"
  assert_contains "$output" "not reachable" \
    "The refusal should say the library could not be reached"

  rm -rf "${root}-moved"
}

# =============================================================================
# LAZY STAMPING
# =============================================================================

function test_stamp_derives_the_root_of_a_flat_instance() {
  log_test_step "Testing the root derived for an instance placed before libraries"

  local root="${PLACEMENT_TEST_DIR}/flat"
  local working_dir="${root}/factorio/flat-probe"
  local config_file="${working_dir}/flat-probe.config.ini"
  _write_instance_config "$config_file" "$working_dir"

  __logic_stamp_instance_library_dir "$config_file"
  assert_equals "$?" "$EC_SUCCESS" "Stamping should succeed"
  assert_file_contains "$config_file" "library_dir=\"${root}\"" \
    "The root should be the working directory minus two components"
}

function test_stamp_leaves_a_recorded_root_alone() {
  log_test_step "Testing stamping is idempotent"

  local root="${PLACEMENT_TEST_DIR}/already"
  local working_dir="${root}/instances/factorio/already-probe"
  local config_file="${working_dir}/already-probe.config.ini"
  _write_instance_config "$config_file" "$working_dir"
  printf 'library_dir="%s"\n' "$root" >> "$config_file"

  __logic_stamp_instance_library_dir "$config_file"
  assert_equals "$?" "$EC_SUCCESS" "Stamping an already stamped instance succeeds"

  local count
  count=$(grep -c '^library_dir=' "$config_file")
  assert_equals 1 "$count" "The key should not be written twice"
  assert_file_contains "$config_file" "library_dir=\"${root}\"" \
    "The recorded root should be left as it was"
}

function test_stamp_refuses_a_config_without_a_working_dir() {
  log_test_step "Testing stamping an instance with nothing to derive from"

  local config_file="${PLACEMENT_TEST_DIR}/empty/empty.config.ini"
  mkdir -p "$(dirname "$config_file")"
  printf 'name="empty"\n' > "$config_file"

  __logic_stamp_instance_library_dir "$config_file"
  assert_equals "$?" "$EC_INVALID_ARG" \
    "Nothing should be stamped when there is no working directory to derive from"
}

# =============================================================================
# WHAT AN INSTANCE REPORTS
# =============================================================================

function test_info_json_carries_the_library_and_its_root() {
  log_test_step "Testing instances info --json reports placement"

  local root
  root="$(_add_library reported)"

  local instance_name="placement-json-$$"
  mkdir -p "${root}/instances/factorio/${instance_name}"
  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "${root}/instances/factorio/${instance_name}" \
    "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"

  "$INSTANCES_MODULE" create factorio --library reported --id "$instance_name" \
    > /dev/null 2>&1

  local output
  output=$("$INSTANCES_MODULE" info "$instance_name" --json 2>/dev/null)

  assert_equals "reported" "$(echo "$output" | jq -r '.library')" \
    "The resolved library name should be reported"
  assert_equals "$root" "$(echo "$output" | jq -r '.library_dir')" \
    "The recorded library root should be reported"

  rm -f "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"
}

function test_info_json_reports_an_unregistered_placement() {
  log_test_step "Testing an instance under no registered library"

  local instance_name="placement-orphan-$$"
  local working_dir="${PLACEMENT_TEST_DIR}/nowhere/factorio/${instance_name}"
  local config_file="${working_dir}/${instance_name}.config.ini"
  _write_instance_config "$config_file" "$working_dir"

  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "$working_dir" "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"

  local output
  output=$("$INSTANCES_MODULE" info "$instance_name" --json 2>/dev/null)

  assert_equals "unregistered" "$(echo "$output" | jq -r '.library')" \
    "An instance in no registered library should be reported as unregistered"

  rm -f "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"
}

function test_info_stamps_a_pre_library_instance() {
  log_test_step "Testing instances info records the root of a flat instance"

  local root
  root="$(_add_library legacy)"

  local instance_name="placement-legacy-$$"
  local working_dir="${root}/factorio/${instance_name}"
  local config_file="${working_dir}/${instance_name}.config.ini"
  _write_instance_config "$config_file" "$working_dir"

  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "$working_dir" "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"

  assert_command_fails "grep -q '^library_dir=' '$config_file'" \
    "The instance should start without a recorded root"

  "$INSTANCES_MODULE" info "$instance_name" --json > /dev/null 2>&1

  assert_file_contains "$config_file" "library_dir=\"${root}\"" \
    "info should record the root it derived"

  rm -f "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"
}

# =============================================================================
# THE WIZARD
# =============================================================================

function test_wizard_install_requires_a_library() {
  log_test_step "Testing the wizard refuses an install with no library"

  source "$KGSM_ROOT/commands/handlers/wizards.sh"

  __logic_wizard_install "factorio" "" "" "wizard-probe"
  assert_equals "$?" "$EC_MISSING_ARG" \
    "The wizard should refuse an install with no library named"
}

function test_wizard_install_places_into_the_named_library() {
  log_test_step "Testing the wizard places into the library it was given"

  source "$KGSM_ROOT/commands/handlers/wizards.sh"

  local root
  root="$(_add_library wizard-lib)"

  # The wizard collects a display name; the id it lands under is generated, so
  # the assertion is that something landed in the named library rather than that
  # it landed under a name the test chose.
  __logic_wizard_install "factorio" "wizard-lib" "" "Placement Wizard $$"

  # The install fails at the download step in a sandbox with no network, but
  # placement happens before it: what is asserted is where the instance landed,
  # not that the game arrived.
  local -a placed=("${root}/instances/factorio"/*)
  assert_equals 1 "${#placed[@]}" \
    "The wizard should place exactly one instance inside the named library"
  assert_dir_exists "${placed[0]}" \
    "The wizard should place the instance inside the named library"

  local placed_id
  placed_id="$(basename "${placed[0]}")"
  assert_equals "Placement Wizard $$" \
    "$(__get_instance_config_value "$placed_id" display_name)" \
    "The name the wizard collected should be the instance's display name"

  rm -f "${KGSM_INSTANCES_DIR}/factorio/${placed_id}"
}

# =============================================================================
# THE RETIRED FLAG
# =============================================================================

function test_install_refuses_the_install_dir_flag() {
  log_test_step "Testing --install-dir is refused by install"

  local output
  output=$("$INSTALL_MODULE" factorio --install-dir "$PLACEMENT_TEST_DIR" 2>&1)
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "install should refuse --install-dir as an unknown argument"
  assert_contains "$output" "Invalid argument" \
    "The refusal should read like any other unknown argument"
}

function test_create_refuses_the_install_dir_flag() {
  log_test_step "Testing --install-dir is refused by instances create"

  local output
  output=$("$INSTANCES_MODULE" create factorio --install-dir "$PLACEMENT_TEST_DIR" 2>&1)
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "create should refuse --install-dir as an unknown option"
  assert_contains "$output" "Invalid option" \
    "The refusal should read like any other unknown option"
}
