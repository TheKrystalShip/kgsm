#!/usr/bin/env bash

# KGSM Instance Display Name Unit Tests
#
# Test Type: UNIT
# Target: the two halves of an instance's identity. The id is generated,
# path-safe and immutable; the display name beside it is free text that any
# consumer may change at any time and that nothing keys on. What is exercised
# here is that the two never trade places: --name never reaches a path, --id is
# always checked, the label round-trips through the config's escaping, a rename
# leaves the id alone, and an argument resolves as an id first and as a label
# only when exactly one instance carries it.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instance_display_name"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"
readonly INSTALL_MODULE="$KGSM_ROOT/commands/install.sh"

# The awkward label every escaping test uses: a quote that would close the
# key="value" string, a backslash that would collapse, a backtick that would
# open a command substitution, an apostrophe, spaces and a character outside
# ASCII.
# shellcheck disable=SC2016  # the backticks are literal — that is the point
readonly AWKWARD_NAME='Ana'"'"'s "Big" \Factory\ `here` 🏭'

DISPLAY_TEST_DIR=""
CREATED_ID=""
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up instance display name tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"
  assert_file_executable "$INSTALL_MODULE" "install.sh should be executable"
  assert_function_exists "validate_instance_id_format" \
    "validate_instance_id_format should be exported"
  assert_function_exists "__resolve_instance_id" \
    "__resolve_instance_id should be exported"

  log_test_step "Test environment validated"
}

function setup() {
  DISPLAY_TEST_DIR="${KGSM_TEST_SANDBOX}/display_${RANDOM}_$$"
  mkdir -p "$DISPLAY_TEST_DIR"
  _TEARDOWN_INSTANCES=()
}

function teardown() {
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" "$DISPLAY_TEST_DIR" 2> /dev/null || true
  done
  rm -rf "$DISPLAY_TEST_DIR"
}

# Creates an instance through the command layer, with whatever id and label the
# caller wants, and records it for teardown.
#
# The id it landed under is left in CREATED_ID rather than echoed: a caller that
# read it through a command substitution would run this in a subshell, and the
# teardown list it appends to would die with that subshell.
#
# Args: $1 = id ("" to let KGSM generate one), $2 = display name ("" for none)
# Returns: 0 with CREATED_ID set, 1 when anything in the sequence failed
function _create() {
  local _id="$1"
  local _display_name="$2"

  CREATED_ID=""

  local _library
  _library="$(__ensure_test_library "$DISPLAY_TEST_DIR")" || return 1

  # The id has to be settled before the working directory and the symlink can be
  # made, which is the order install.sh works in.
  local -a _generate_args=(factorio)
  [[ -n "$_id" ]] && _generate_args+=(--id "$_id")

  local _resolved_id
  _resolved_id="$("$INSTANCES_MODULE" generate-id "${_generate_args[@]}" 2> /dev/null)" || return 1

  setup_instance_prereqs "factorio" "$_resolved_id" "$DISPLAY_TEST_DIR" || return 1

  local -a _create_args=(factorio --library "$_library" --id "$_resolved_id")
  [[ -n "$_display_name" ]] && _create_args+=(--name "$_display_name")

  "$INSTANCES_MODULE" create "${_create_args[@]}" > /dev/null 2>&1 || return 1

  _TEARDOWN_INSTANCES+=("factorio:$_resolved_id")
  CREATED_ID="$_resolved_id"
  return 0
}

# The journal segment the sandbox writes to. The sandbox redirects
# event_journal_dir into itself, so nothing here reaches the host's journal.
# Newest segment, by name: segment names are dates, so ordinal order is
# chronological.
function _journal_segment() {
  local journal_dir="${config_event_journal_dir:-$KGSM_TEST_SANDBOX/events}"
  find "$journal_dir" -maxdepth 1 -type f -name '*.ndjson' 2> /dev/null | sort | tail -1
}

# Every journal line written since the caller took its mark.
# Args: $1 = segment path (may be empty), $2 = line count at the mark
function _journal_since() {
  local segment="$1"
  local mark="$2"

  local current
  current="$(_journal_segment)"
  [[ -n "$current" ]] || return 0

  # A day boundary between the mark and now means a new segment, and everything
  # in it is new.
  if [[ "$current" != "$segment" ]]; then
    cat "$current"
    return 0
  fi

  tail -n "+$((mark + 1))" "$current"
}

# =============================================================================
# TEST: creation defaults
# =============================================================================

function test_creation_without_a_name_shows_the_id() {
  log_test_step "Testing an instance created with no --name is shown by its id"

  _create "" ""
  local id="$CREATED_ID"
  assert_not_null "$id" "The instance should be created"

  assert_equals "$id" "$(__get_instance_config_value "$id" display_name)" \
    "display_name should default to the instance id"
}

function test_creation_generates_the_id_when_none_is_given() {
  log_test_step "Testing the id is generated from the blueprint when none is given"

  _create "" "Something Entirely Different"
  local id="$CREATED_ID"

  assert_matches "$id" "^factorio(-[0-9]+)?$" \
    "The id should come from the blueprint, never from the display name"
  assert_equals "Something Entirely Different" \
    "$(__get_instance_config_value "$id" display_name)" \
    "The display name should be what --name was given"
}

# =============================================================================
# TEST: --name round-trips, including the characters that would break the file
# =============================================================================

function test_display_name_round_trips_through_the_config() {
  log_test_step "Testing an awkward display name survives write and read"

  _create "" "$AWKWARD_NAME"
  local id="$CREATED_ID"
  assert_not_null "$id" "The instance should be created"

  assert_equals "$AWKWARD_NAME" "$(__get_instance_config_value "$id" display_name)" \
    "config-get should return the display name exactly as it was given"
}

function test_display_name_leaves_the_config_sourceable() {
  log_test_step "Testing an awkward display name does not break sourcing"

  _create "" "$AWKWARD_NAME"
  local id="$CREATED_ID"

  local config_file
  config_file="$(__find_instance_config "$id")"

  # The management script sources this file; a value that closes its own string
  # early makes the whole file unsourceable, which is the failure the escaping
  # exists to prevent.
  local sourced
  sourced="$(bash -c 'source "$1" && printf "%s" "$display_name"' _ "$config_file")"

  assert_equals "$AWKWARD_NAME" "$sourced" \
    "Sourcing the config should yield the display name unchanged"
}

function test_display_name_round_trips_through_info_json() {
  log_test_step "Testing 'info --json' carries the display name verbatim"

  _create "" "$AWKWARD_NAME"
  local id="$CREATED_ID"

  local reported
  reported="$("$INSTANCES_MODULE" info "$id" --json 2> /dev/null | jq -r '.display_name')"

  assert_equals "$AWKWARD_NAME" "$reported" \
    "info --json should report the display name exactly as it was given"
}

function test_list_detailed_json_carries_the_display_name() {
  log_test_step "Testing 'list --detailed --json' carries the display name"

  _create "" "Roster Label"
  local id="$CREATED_ID"

  local reported
  reported="$("$INSTANCES_MODULE" list --detailed --json 2> /dev/null \
    | jq -r --arg id "$id" '.[$id].display_name')"

  assert_equals "Roster Label" "$reported" \
    "The roster entry should carry the instance's display name"
}

# =============================================================================
# TEST: --id is always validated
# =============================================================================

function test_id_flag_sets_the_identifier() {
  log_test_step "Testing --id lands the instance at exactly that id"

  _create "factorio-x1" ""
  local id="$CREATED_ID"

  assert_equals "factorio-x1" "$id" "The instance should land at the requested id"
  assert_file_exists "$DISPLAY_TEST_DIR/instances/factorio/factorio-x1/factorio-x1.config.ini" \
    "The config file should be named after the requested id"
}

function test_id_flag_rejects_a_name_with_spaces() {
  log_test_step "Testing --id refuses an id containing spaces"

  local library
  library="$(__ensure_test_library "$DISPLAY_TEST_DIR")"

  local output
  output="$("$INSTANCES_MODULE" create factorio --library "$library" --id "bad name" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "create should refuse an id with a space as an invalid argument"
  assert_contains "$output" "Invalid instance id" \
    "The refusal should name the id it refused"
}

function test_id_format_validator_accepts_and_refuses() {
  log_test_step "Testing the id charset validator on both sides of the rule"

  local ok
  for ok in factorio factorio-42 Factorio_Prod a a.b-c_d 0start; do
    validate_instance_id_format "$ok" > /dev/null 2>&1
    assert_equals 0 "$?" "'$ok' should be a usable instance id"
  done

  local bad
  for bad in "bad name" "-leading" ".leading" "with/slash" "with\$dollar" ""; do
    validate_instance_id_format "$bad" > /dev/null 2>&1
    assert_equals "$EC_INVALID_ARG" "$?" "'$bad' should not be a usable instance id"
  done

  local too_long
  printf -v too_long '%065d' 0
  validate_instance_id_format "$too_long" > /dev/null 2>&1
  assert_equals "$EC_INVALID_ARG" "$?" "An id of 65 characters should be refused"
}

function test_name_flag_is_never_validated() {
  log_test_step "Testing --name accepts text no id could be"

  _create "" "  bad/name \$here  "
  local id="$CREATED_ID"
  assert_not_null "$id" "A display name is free text and is never refused"

  assert_equals "  bad/name \$here  " "$(__get_instance_config_value "$id" display_name)" \
    "The display name should be stored exactly as typed"
}

# =============================================================================
# TEST: mutability — config-set, rename, and the key that stays protected
# =============================================================================

function test_config_set_changes_the_display_name() {
  log_test_step "Testing 'config-set display_name' changes the label"

  _create "" "Before"
  local id="$CREATED_ID"

  assert_command_succeeds "$INSTANCES_MODULE config-set $id display_name=After" \
    "display_name should be settable through config-set"

  assert_equals "After" "$(__get_instance_config_value "$id" display_name)" \
    "config-set should have written the new label"
}

function test_rename_changes_the_display_name() {
  log_test_step "Testing 'rename' joins its arguments into the new label"

  _create "" "Before"
  local id="$CREATED_ID"

  "$INSTANCES_MODULE" rename "$id" Weekend Server > /dev/null 2>&1
  assert_equals 0 "$?" "rename should succeed"

  assert_equals "Weekend Server" "$(__get_instance_config_value "$id" display_name)" \
    "rename should join its remaining arguments with single spaces"
}

function test_rename_leaves_the_id_and_its_paths_alone() {
  log_test_step "Testing a rename moves nothing on disk"

  _create "factorio-keep" "Before"
  local id="$CREATED_ID"

  local working_dir
  working_dir="$(__get_instance_config_value "$id" working_dir)"

  "$INSTANCES_MODULE" rename "$id" "After" > /dev/null 2>&1

  assert_equals "factorio-keep" "$(__get_instance_config_value "$id" name)" \
    "The instance's id should be untouched by a rename"
  assert_equals "$working_dir" "$(__get_instance_config_value "$id" working_dir)" \
    "The working directory should be untouched by a rename"
  assert_file_exists "$DISPLAY_TEST_DIR/instances/factorio/factorio-keep/factorio-keep.config.ini" \
    "The config file should still be named after the id"
}

function test_rename_emits_the_display_name_event() {
  log_test_step "Testing a rename records what the label was and now is"

  _create "" "Before"
  local id="$CREATED_ID"

  local segment segment_before
  segment="$(_journal_segment)"
  segment_before=0
  [[ -n "$segment" ]] && segment_before="$(wc -l < "$segment")"

  "$INSTANCES_MODULE" rename "$id" "After" > /dev/null 2>&1

  local payload
  payload="$(_journal_since "$segment" "$segment_before" \
    | jq -c --arg id "$id" \
      'select(.EventType == "instance_display_name_changed" and .Data.InstanceName == $id)' \
    | tail -n 1)"

  assert_not_null "$payload" "A rename should emit instance_display_name_changed"
  assert_equals "Before" "$(jq -r '.Data.OldDisplayName' <<< "$payload")" \
    "The event should carry the label the instance had"
  assert_equals "After" "$(jq -r '.Data.NewDisplayName' <<< "$payload")" \
    "The event should carry the label the instance now has"
  assert_not_null "$(jq -r '.Actor' <<< "$payload")" \
    "The event should carry an actor like every other event"
  assert_not_null "$(jq -r '.Timestamp' <<< "$payload")" \
    "The event should carry a timestamp like every other event"
}

function test_config_set_display_name_emits_the_same_event() {
  log_test_step "Testing config-set on display_name records the same change"

  _create "" "Before"
  local id="$CREATED_ID"

  local segment segment_before
  segment="$(_journal_segment)"
  segment_before=0
  [[ -n "$segment" ]] && segment_before="$(wc -l < "$segment")"

  "$INSTANCES_MODULE" config-set "$id" "display_name=After" > /dev/null 2>&1

  local types
  types="$(_journal_since "$segment" "$segment_before" \
    | jq -r --arg id "$id" 'select(.Data.InstanceName == $id) | .EventType' | sort -u)"

  assert_contains "$types" "instance_config_changed" \
    "A config-set should record the generic config change"
  assert_contains "$types" "instance_display_name_changed" \
    "A config-set on display_name should also record the label change"
}

function test_name_key_stays_protected() {
  log_test_step "Testing the id is still refused by config-set"

  _create "" ""
  local id="$CREATED_ID"

  local output
  output="$("$INSTANCES_MODULE" config-set "$id" "name=something-else" 2>&1)"
  local exit_code=$?

  assert_not_equals 0 "$exit_code" "config-set should refuse the name key"
  assert_contains "$output" "protected" "The refusal should say the key is protected"
  assert_equals "$id" "$(__get_instance_config_value "$id" name)" \
    "The id should be unchanged by the refused set"
}

function test_config_list_reports_display_name_as_settable() {
  log_test_step "Testing config-list agrees that the label can be changed"

  _create "" "Label"
  local id="$CREATED_ID"

  local settable
  settable="$("$INSTANCES_MODULE" config-list "$id" --json 2> /dev/null \
    | jq -r '.[] | select(.key == "display_name") | .settable')"

  assert_equals "true" "$settable" \
    "config-list should report display_name as settable"
}

# =============================================================================
# TEST: resolution — by id, by a unique label, and the ambiguous refusal
# =============================================================================

function test_resolution_by_id() {
  log_test_step "Testing an id resolves as itself"

  _create "factorio-r1" "A Label"
  local id="$CREATED_ID"

  assert_equals "factorio-r1" "$(__resolve_instance_id factorio-r1)" \
    "An id should resolve to itself"
}

function test_resolution_by_a_unique_display_name() {
  log_test_step "Testing a display name only one instance carries resolves to its id"

  _create "factorio-r2" "The Only One"
  local id="$CREATED_ID"

  assert_equals "factorio-r2" "$(__resolve_instance_id "The Only One")" \
    "A display name carried by exactly one instance should resolve to its id"

  local output
  output="$("$INSTANCES_MODULE" info "The Only One" --json 2> /dev/null | jq -r '.name')"
  assert_equals "factorio-r2" "$output" \
    "A command should accept the display name in place of the id"
}

function test_resolution_refuses_an_ambiguous_display_name() {
  log_test_step "Testing a display name two instances share is refused, never guessed"

  _create "factorio-r3" "Shared Label"
  local first="$CREATED_ID"
  _create "factorio-r4" "Shared Label"
  local second="$CREATED_ID"

  local output
  output="$(__resolve_instance_id "Shared Label" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "An ambiguous display name should be refused"
  assert_contains "$output" "$first" "The refusal should list the first candidate id"
  assert_contains "$output" "$second" "The refusal should list the second candidate id"
}

function test_resolution_leaves_an_unknown_argument_alone() {
  log_test_step "Testing an argument matching nothing is handed back untouched"

  assert_equals "no-such-thing" "$(__resolve_instance_id "no-such-thing")" \
    "An unmatched argument should be echoed back so the caller can report it"

  local output
  output="$("$INSTANCES_MODULE" info "no-such-thing" 2>&1)"
  assert_not_equals 0 "$?" "info on an unknown instance should still fail"
  assert_contains "$output" "no-such-thing" \
    "The not-found message should name what the caller typed"
}

function test_an_id_wins_over_a_display_name() {
  log_test_step "Testing an argument that is both an id and another's label resolves as the id"

  _create "factorio-r5" ""
  local decoy="$CREATED_ID"

  # A second instance takes the first one's id as its label. The id is the
  # answer: it is the thing that is unique, and guessing the other way would
  # make an instance unreachable by its own name.
  _create "factorio-r6" "factorio-r5"
  local imposter="$CREATED_ID"

  assert_equals "factorio-r5" "$(__resolve_instance_id "factorio-r5")" \
    "An existing id should resolve as itself regardless of any label matching it"
}

# =============================================================================
# TEST: a config written before instances carried a label
# =============================================================================

function test_a_config_without_the_key_reads_as_the_id() {
  log_test_step "Testing an instance whose config predates display_name"

  _create "factorio-legacy" "Temporary"
  local id="$CREATED_ID"

  local config_file
  config_file="$(__find_instance_config "$id")"
  config_file="$(readlink -f "$config_file")"

  # Exactly what a config written before the key existed looks like.
  sed -i '/^display_name=/d' "$config_file"
  assert_command_fails "grep -q '^display_name=' $config_file" \
    "The key should be gone from the config"

  assert_equals "$id" \
    "$("$INSTANCES_MODULE" info "$id" --json 2> /dev/null | jq -r '.display_name')" \
    "info --json should report the id as the display name"
  assert_contains "$("$INSTANCES_MODULE" info "$id" 2>&1)" "display_name=\"$id\"" \
    "info should report the id as the display name"
  assert_equals "$id" "$(__resolve_instance_id "$id")" \
    "The instance should still resolve by its id"
}

function test_an_instance_without_the_key_can_still_be_renamed() {
  log_test_step "Testing a rename on a config that carries no label yet"

  _create "factorio-legacy2" "Temporary"
  local id="$CREATED_ID"

  local config_file
  config_file="$(readlink -f "$(__find_instance_config "$id")")"
  sed -i '/^display_name=/d' "$config_file"

  "$INSTANCES_MODULE" rename "$id" "Now It Has One" > /dev/null 2>&1
  assert_equals 0 "$?" "rename should succeed on a config with no display_name key"

  assert_equals "Now It Has One" "$(__get_instance_config_value "$id" display_name)" \
    "The label should have been added to the config"
}
