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
DISPLAY_TEST_SEQ=0
CREATED_ID=""
_TEARDOWN_INSTANCES=()

# The user blueprint the creation-path tests build from. One file, rewritten by
# whichever test needs it and removed after each.
POISONED_BLUEPRINT="poisoned"

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
  # Counted, not drawn. The library a test registers is named after the
  # directory it points at, so two tests handed the same directory are handed
  # the same library name, and the second registration is refused as a
  # duplicate — every instance that test tries to create then fails for a reason
  # that has nothing to do with what it asserts.
  DISPLAY_TEST_SEQ=$((DISPLAY_TEST_SEQ + 1))
  DISPLAY_TEST_DIR="${KGSM_TEST_SANDBOX}/display_${DISPLAY_TEST_SEQ}_$$"
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

  # The registry entry goes with the tree it describes. One left pointing at a
  # deleted directory is a library the next test has to work around.
  "$KGSM_ROOT/kgsm.sh" libraries remove "$(__test_library_name "$DISPLAY_TEST_DIR")" \
    --force > /dev/null 2>&1 || true

  rm -f "${KGSM_USER_BLUEPRINTS_DIR}/${POISONED_BLUEPRINT}.bp.yaml"
  rm -rf "$DISPLAY_TEST_DIR"
}

# Reports a fixture step that did not do its job. A helper that gives up quietly
# leaves the test asserting against an empty id, which reads in the log as the
# code under test having answered wrongly.
#
# Args: $1 = what was being done
function _fixture_failed() {
  assert_not_null "" "Test fixture: $1"
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
  _library="$(__ensure_test_library "$DISPLAY_TEST_DIR")" || {
    _fixture_failed "registering a library at $DISPLAY_TEST_DIR"
    return 1
  }

  # The id has to be settled before the working directory and the symlink can be
  # made, which is the order install.sh works in.
  local -a _generate_args=(factorio)
  [[ -n "$_id" ]] && _generate_args+=(--id "$_id")

  local _resolved_id
  _resolved_id="$("$INSTANCES_MODULE" generate-id "${_generate_args[@]}" 2> /dev/null)" || {
    _fixture_failed "settling the id for '${_id:-<generated>}'"
    return 1
  }

  setup_instance_prereqs "factorio" "$_resolved_id" "$DISPLAY_TEST_DIR" || {
    _fixture_failed "preparing the working directory for '$_resolved_id'"
    return 1
  }

  local -a _create_args=(factorio --library "$_library" --id "$_resolved_id")
  [[ -n "$_display_name" ]] && _create_args+=(--name "$_display_name")

  "$INSTANCES_MODULE" create "${_create_args[@]}" > /dev/null 2>&1 || {
    _fixture_failed "creating instance '$_resolved_id'"
    return 1
  }

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

  _create "" "  bad/name here!  "
  local id="$CREATED_ID"
  assert_not_null "$id" "A display name is free text and is never refused"

  # Refused nothing: the slash, the space and the bang an id could never carry
  # are all stored. Only the surrounding whitespace goes, because a label made of
  # spaces is a server with no visible name. (The dollar is the one character a
  # label cannot keep — it is dropped so a sourcing reader cannot expand it; that
  # is covered on its own above.)
  assert_equals "bad/name here!" "$(__get_instance_config_value "$id" display_name)" \
    "The display name should keep every character an id could not"
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
      'select(.EventType == "server.renamed" and .Data.InstanceName == $id)' \
    | tail -n 1)"

  assert_not_null "$payload" "A rename should emit server.renamed"
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

  assert_contains "$types" "config.changed" \
    "A config-set should record the generic config change"
  assert_contains "$types" "server.renamed" \
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

function test_uninstall_by_display_name_acts_on_the_id() {
  log_test_step "Testing uninstall resolves a label to the id before it does anything"

  _create "" "Uninstall Me"
  local id="$CREATED_ID"

  local segment segment_before
  segment="$(_journal_segment)"
  segment_before=0
  [[ -n "$segment" ]] && segment_before="$(wc -l < "$segment")"

  # Uninstall by the label, not the id. The whole point of resolving up front is
  # that everything inward — including the events emitted — sees the id, never
  # the label: an event keyed on the label would poison every downstream store
  # the id is meant to hold together. The watchdog is disabled so the sandbox
  # never reaches the host daemon; the running-gate that path guards is exercised
  # against a live instance in the deployed-engine checks, not here.
  KGSM_WATCHDOG_DISABLE=true "$KGSM_ROOT/kgsm.sh" uninstall "Uninstall Me" --force \
    > /dev/null 2>&1

  # The instance is gone.
  assert_command_fails "$INSTANCES_MODULE info $id --json" \
    "The instance should be uninstalled"

  # The uninstall-started event names the id, not the label it was called by.
  local started
  started="$(_journal_since "$segment" "$segment_before" \
    | jq -c 'select(.EventType == "server.uninstall.started")' | tail -n 1)"
  assert_not_null "$started" "Uninstall should emit server.uninstall.started"
  assert_equals "$id" "$(jq -r '.Data.InstanceName' <<< "$started")" \
    "The event should carry the id, never the display name it was called by"
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

# =============================================================================
# TEST: a value cannot carry a character the file has no room for
#
# The config is a line-oriented list of key="value" pairs, and its text readers
# separate a key from its value on a tab and one pair from the next on a
# newline. A value holding either is therefore not one value, and the two
# readers below have to agree about it or a surface renders something the engine
# does not think it stored.
# =============================================================================

# Both text readers' answer for one key, as a single string, so a test asserts
# on the pair rather than on either one of them.
# Args: $1 = instance, $2 = key
function _both_readers() {
  printf '%s\n%s' \
    "$("$INSTANCES_MODULE" info "$1" --json 2> /dev/null | jq -r --arg k "$2" '.[$k]')" \
    "$("$INSTANCES_MODULE" config-list "$1" --json 2> /dev/null \
      | jq -r --arg k "$2" '.[] | select(.key == $k) | .value')"
}

function test_a_tab_never_reaches_the_config() {
  log_test_step "Testing a tab in a label is dropped rather than stored"

  _create "" "Before"
  local id="$CREATED_ID"

  "$INSTANCES_MODULE" config-set "$id" "$(printf 'display_name=Before\tAfter')" \
    > /dev/null 2>&1

  assert_equals "BeforeAfter" "$(__get_instance_config_value "$id" display_name)" \
    "The tab should be gone from the stored value"
  assert_equals "$(printf 'BeforeAfter\nBeforeAfter')" "$(_both_readers "$id" display_name)" \
    "Both readers should report the same label"
}

function test_a_newline_never_reaches_the_config() {
  log_test_step "Testing a newline in a label cannot open a second config line"

  _create "" "Before"
  local id="$CREATED_ID"

  # Shaped to forge a key: were the newline stored, everything after it would
  # parse as another key=value pair and the instance would report an id that is
  # not its own.
  "$INSTANCES_MODULE" config-set "$id" \
    "$(printf 'display_name=Innocent"\nname="forged-id')" > /dev/null 2>&1

  assert_equals "$id" "$("$INSTANCES_MODULE" info "$id" --json 2> /dev/null | jq -r '.name')" \
    "info --json should report the instance's own id"
  assert_equals "$id" \
    "$("$INSTANCES_MODULE" list --detailed --json 2> /dev/null | jq -r --arg id "$id" '.[$id].name')" \
    "The roster should report the instance's own id"

  local config_file
  config_file="$(readlink -f "$(__find_instance_config "$id")")"
  assert_equals 1 "$(grep -c '^name=' "$config_file")" \
    "The config should hold exactly one name key"
}

function test_control_characters_are_stripped_from_every_value() {
  log_test_step "Testing the strip applies to any config value, not only a label"

  _create "" "Before"
  local id="$CREATED_ID"

  # executable_arguments is an ordinary settable value and carries the same rule:
  # the reader is the same reader.
  "$INSTANCES_MODULE" config-set "$id" \
    "$(printf 'executable_arguments=--one\t--two\r--three')" > /dev/null 2>&1

  assert_equals "--one--two--three" \
    "$(__get_instance_config_value "$id" executable_arguments)" \
    "Tab and carriage return should both be gone"
  assert_equals "$(printf -- '--one--two--three\n--one--two--three')" \
    "$(_both_readers "$id" executable_arguments)" \
    "Both readers should report the same value"
}

# The setter is one of the config's two write paths. The other is the template
# the creation path renders, and its values come from a blueprint — a file
# written by hand, whose scalars reach the template exactly as typed. The two
# below hold that path to the same rule.

# A copy of a real blueprint with one native scalar replaced. The `name` inside
# is left alone, so the copy binds to the same override directory the original
# does; the instance it creates is laid out under the copy's own file name,
# which is what the engine derives a blueprint's directory from.
# Args: $1 = the native field to poison, $2 = the value to put in it
function _write_poisoned_blueprint() {
  local field="$1"
  local value="$2"

  mkdir -p "$KGSM_USER_BLUEPRINTS_DIR"

  local source_blueprint
  source_blueprint="$(__find_blueprint factorio)" || return 1

  POISONED_VALUE="$value" yq ".native.${field} = strenv(POISONED_VALUE)" \
    "$source_blueprint" > "${KGSM_USER_BLUEPRINTS_DIR}/${POISONED_BLUEPRINT}.bp.yaml"
}

# Creates an instance from the poisoned blueprint and records it for teardown.
function _create_poisoned() {
  CREATED_ID=""

  local _library
  _library="$(__ensure_test_library "$DISPLAY_TEST_DIR")" || {
    _fixture_failed "registering a library at $DISPLAY_TEST_DIR"
    return 1
  }

  local _resolved_id
  _resolved_id="$("$INSTANCES_MODULE" generate-id "$POISONED_BLUEPRINT" 2> /dev/null)" || {
    _fixture_failed "settling the id for the poisoned blueprint"
    return 1
  }

  setup_instance_prereqs "$POISONED_BLUEPRINT" "$_resolved_id" "$DISPLAY_TEST_DIR" || {
    _fixture_failed "preparing the working directory for '$_resolved_id'"
    return 1
  }

  "$INSTANCES_MODULE" create "$POISONED_BLUEPRINT" \
    --library "$_library" --id "$_resolved_id" > /dev/null 2>&1 || {
    _fixture_failed "creating instance '$_resolved_id'"
    return 1
  }

  _TEARDOWN_INSTANCES+=("${POISONED_BLUEPRINT}:$_resolved_id")
  CREATED_ID="$_resolved_id"
  return 0
}

function test_a_blueprint_tab_never_reaches_a_new_config() {
  log_test_step "Testing a tab in a blueprint value is dropped as the config is written"

  _write_poisoned_blueprint executable_arguments "$(printf -- '--one\t--two')"
  _create_poisoned || return
  local id="$CREATED_ID"

  assert_equals "--one--two" \
    "$(__get_instance_config_value "$id" executable_arguments)" \
    "The tab should be gone from the value the template wrote"
  assert_equals "$(printf -- '--one--two\n--one--two')" \
    "$(_both_readers "$id" executable_arguments)" \
    "Both readers should report the same value"
}

function test_a_blueprint_newline_cannot_forge_the_id() {
  log_test_step "Testing a newline in a blueprint value cannot open a second config line"

  # Shaped to forge a key: were the newline written, everything after it would
  # be a line of its own, and the instance would report an id that is not its
  # own from the moment it was created.
  _write_poisoned_blueprint executable_arguments "$(printf -- '--one\nname=forged-id')"
  _create_poisoned || return
  local id="$CREATED_ID"

  local config_file
  config_file="$(readlink -f "$(__find_instance_config "$id")")"
  assert_equals 1 "$(grep -c '^name=' "$config_file")" \
    "The config should hold exactly one name key"

  assert_equals "$id" "$("$INSTANCES_MODULE" info "$id" --json 2> /dev/null | jq -r '.name')" \
    "info --json should report the instance's own id"
  assert_equals "$id" \
    "$("$INSTANCES_MODULE" list --detailed --json 2> /dev/null | jq -r --arg id "$id" '.[$id].name')" \
    "The roster should report the instance's own id"

  # The reader that takes the last occurrence of a key rather than the first,
  # which is the one a forged line further down the file would win against.
  local reported_name
  reported_name="$(bash -c "source '$KGSM_ROOT/core/bootstrap.sh' > /dev/null 2>&1; \
    __source_instance '$id' > /dev/null 2>&1; printf '%s' \"\$instance_name\"")"
  assert_equals "$id" "$reported_name" \
    "The sourcing reader should report the instance's own id too"

  assert_equals "$(printf -- '--onename=forged-id\n--onename=forged-id')" \
    "$(_both_readers "$id" executable_arguments)" \
    "Both readers should report the whole value on one line"
}

# =============================================================================
# TEST: a label cannot carry a shell expansion into a sourcing reader
#
# Every other free-text config value keeps its '$' live on purpose, so the
# escape helper leaves it be — and several surfaces read the config by sourcing
# it (the log and port watchers, the interactive wizard). A display name is
# opaque decoration no reader should expand, so '$' is dropped from it before it
# is stored. These assert the character is gone from the file and that sourcing
# the file — exactly what watchers.sh does — expands nothing.
# =============================================================================

# Source the config the way watchers.sh:34 does and echo the raw display_name.
# Any surviving $(...) would run here; the sandbox teardown removes the marker
# path regardless. Args: $1 = instance
function _source_display_name() {
  local config_file
  config_file="$(__find_instance_config "$1")" || return 1
  (
    # shellcheck disable=SC1090
    source "$config_file" 2> /dev/null
    printf '%s' "$display_name"
  )
}

function test_a_command_substitution_in_a_label_never_executes() {
  log_test_step "Testing \$(...) in a label is neutralized, not run when sourced"

  _create "" "safe"
  local id="$CREATED_ID"

  local marker="$DISPLAY_TEST_DIR/injection_proof_$$"
  rm -f "$marker"

  # shellcheck disable=SC2016  # single quotes are intentional: feed the literal string
  "$INSTANCES_MODULE" rename "$id" "$(printf 'pwn$(touch %s)end' "$marker")" \
    > /dev/null 2>&1

  # Sourcing the config must not create the marker.
  _source_display_name "$id" > /dev/null
  assert_file_not_exists "$marker" \
    "Sourcing a label with \$(...) must not execute it"

  # The stored value is the literal text with the dollar removed, and both text
  # readers agree on it.
  assert_equals "pwn(touch $marker)end" \
    "$(__get_instance_config_value "$id" display_name)" \
    "The dollar should be gone and the rest kept literally"
  assert_equals "$(printf 'pwn(touch %s)end\npwn(touch %s)end' "$marker" "$marker")" \
    "$(_both_readers "$id" display_name)" \
    "Both readers should report the same neutralized label"
}

function test_a_variable_expansion_in_a_label_is_inert() {
  log_test_step "Testing \${IFS} and \$HOME in a label expand to nothing"

  _create "" "safe"
  local id="$CREATED_ID"

  # shellcheck disable=SC2016  # single quotes are intentional: feed the literal string
  "$INSTANCES_MODULE" rename "$id" "$(printf 'a${IFS}b $HOME z')" \
    > /dev/null 2>&1

  # The braces and names survive as literal text; only the dollar is gone, so
  # nothing expands when the file is sourced.
  local sourced
  sourced="$(_source_display_name "$id")"
  assert_equals "a{IFS}b HOME z" "$sourced" \
    "A sourced label should hold no expansion"
  assert_equals "a{IFS}b HOME z" \
    "$(__get_instance_config_value "$id" display_name)" \
    "The stored label should match what a reader sources"
}

function test_a_label_of_only_a_dollar_reads_as_the_id() {
  log_test_step "Testing a label made only of dollars empties to the id"

  _create "" "safe"
  local id="$CREATED_ID"

  "$INSTANCES_MODULE" rename "$id" '$$$' > /dev/null 2>&1

  assert_equals "$id" \
    "$("$INSTANCES_MODULE" info "$id" --json 2> /dev/null | jq -r '.display_name')" \
    "A label with nothing left after the dollars is gone reads as the id"
}

function test_a_dollar_bearing_label_still_leaves_the_config_sourceable() {
  log_test_step "Testing a hostile label keeps the whole config sourceable"

  _create "" "safe"
  local id="$CREATED_ID"

  # shellcheck disable=SC2016  # single quotes are intentional: feed the literal string
  "$INSTANCES_MODULE" rename "$id" \
    "$(printf 'x$(id)`whoami` "q" \\b ${HOME}')" > /dev/null 2>&1

  # The config as a whole still sources without error — the other keys are intact
  # and the label carries no live metacharacter.
  local config_file
  config_file="$(__find_instance_config "$id")"
  assert_command_succeeds "bash -c 'source \"$config_file\"'" \
    "The config should still source cleanly with a hostile label"
}

function test_sanitizer_keeps_text_outside_ascii() {
  log_test_step "Testing the strip leaves multi-byte characters alone"

  assert_equals "a🏭b" "$(__sanitize_instance_config_value "$(printf 'a\t🏭\vb')")" \
    "A multi-byte character should survive a byte-oriented strip"
  assert_equals "Ana's \"Big\" Factory" \
    "$(__sanitize_instance_config_value "Ana's \"Big\" Factory")" \
    "Nothing but control characters should be removed"
}

function test_display_name_of_only_whitespace_reads_as_the_id() {
  log_test_step "Testing a label made of whitespace leaves the instance shown by its id"

  _create "" "Before"
  local id="$CREATED_ID"

  "$INSTANCES_MODULE" rename "$id" "   " > /dev/null 2>&1

  assert_equals "" "$(__get_instance_config_value "$id" display_name)" \
    "A label of only whitespace should store as empty"
  assert_equals "$id" "$("$INSTANCES_MODULE" info "$id" --json 2> /dev/null | jq -r '.display_name')" \
    "An empty label should read as the instance id, never as blank"
}

function test_a_legacy_tab_in_a_value_is_read_whole() {
  log_test_step "Testing a tab already in a config file no longer truncates"

  _create "" "Before"
  local id="$CREATED_ID"

  # Exactly what a config written before the strip existed holds. Put there
  # directly, because no write path can produce it any more.
  local config_file
  config_file="$(readlink -f "$(__find_instance_config "$id")")"
  local tabbed
  tabbed="$(printf 'Legacy\tValue')"
  sed -i "s|^display_name=.*|display_name=\"${tabbed}\"|" "$config_file"

  assert_equals "$(printf 'Legacy\tValue\nLegacy\tValue')" \
    "$(_both_readers "$id" display_name)" \
    "Both readers should report the whole value, tab included"
  assert_equals "$tabbed" "$(__get_instance_config_value "$id" display_name)" \
    "config-get should report the whole value too"
}

function test_a_legacy_duplicate_key_cannot_redefine_the_id() {
  log_test_step "Testing a stray duplicate key in a config loses to the real one"

  _create "" "Before"
  local id="$CREATED_ID"

  # What the newline case left behind in a config corrupted before the strip:
  # an orphaned line the setter never owned and so never rewrites.
  local config_file
  config_file="$(readlink -f "$(__find_instance_config "$id")")"
  printf 'name="forged-id"\n' >> "$config_file"

  assert_equals "$id" "$("$INSTANCES_MODULE" info "$id" --json 2> /dev/null | jq -r '.name')" \
    "The key the template wrote should win over the stray one that follows it"
  assert_equals "$id" \
    "$("$INSTANCES_MODULE" list --detailed --json 2> /dev/null | jq -r --arg id "$id" '.[$id].name')" \
    "The roster should agree"
}

# =============================================================================
# TEST: a label that looks like a flag is still a label
# =============================================================================

function test_rename_accepts_a_label_that_is_a_help_flag() {
  log_test_step "Testing '--help' and 'help' are written as labels, not read as help"

  _create "" "Before"
  local id="$CREATED_ID"

  local label
  for label in "--help" "help" "-h"; do
    "$INSTANCES_MODULE" rename "$id" "$label" > /dev/null 2>&1
    assert_equals 0 "$?" "rename should succeed with '$label' as the label"
    assert_equals "$label" "$(__get_instance_config_value "$id" display_name)" \
      "'$label' should have been written as the display name"
  done
}

function test_rename_accepts_a_help_word_inside_a_longer_label() {
  log_test_step "Testing a help word among the label's other words is just a word"

  _create "" "Before"
  local id="$CREATED_ID"

  "$INSTANCES_MODULE" rename "$id" Ana needs --help now > /dev/null 2>&1

  assert_equals "Ana needs --help now" "$(__get_instance_config_value "$id" display_name)" \
    "Every argument after the instance should be part of the label"
}

function test_rename_still_shows_usage_in_the_first_position() {
  log_test_step "Testing help is still recognised where it is meant to be"

  local flag
  for flag in "-h" "--help" "help"; do
    local output
    output="$("$INSTANCES_MODULE" rename "$flag" 2>&1)"
    assert_equals 0 "$?" "rename $flag should exit 0"
    assert_contains "$output" "Rename Instance" "rename $flag should print usage"
  done
}

function test_rename_without_a_label_is_refused() {
  log_test_step "Testing a rename with nothing to rename to is refused, not silent"

  _create "" "Before"
  local id="$CREATED_ID"

  local output
  output="$("$INSTANCES_MODULE" rename "$id" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "rename with no label should exit EC_MISSING_ARG"
  assert_contains "$output" "display name" "The refusal should name what is missing"
  assert_equals "Before" "$(__get_instance_config_value "$id" display_name)" \
    "The label should be untouched by the refused rename"
}
