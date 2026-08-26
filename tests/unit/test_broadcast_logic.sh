#!/usr/bin/env bash

# KGSM Broadcast Command Tests
#
# Test Type: UNIT
# Target: the blueprint broadcast_command contract and _send_broadcast's refusals
#
# _send_broadcast lives in the management-script modules
# (templates/manage.{native,container}.d/04-io.sh), which are concatenated into a
# per-instance script rather than sourced as a library. The delivery half needs a
# live FIFO and a running game, so what is asserted here is everything that runs
# BEFORE the write: the template contract, the substitution, and every refusal.
# Those are the paths that decide whether an announcement is sent at all.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="broadcast_logic"

# Created in setup_file, removed in teardown_file. A FIFO needs a real directory
# on disk, and every test file in this suite owns its own.
BROADCAST_TEST_TEMP_DIR=""

readonly NATIVE_IO="$KGSM_ROOT/templates/manage.native.d/04-io.sh"
readonly CONTAINER_IO="$KGSM_ROOT/templates/manage.container.d/04-io.sh"

# A harness that runs _send_broadcast with the module's own code but a writable
# destination in place of the game's FIFO. The module is sourced, so the function
# under test is the shipped one; only the socket it writes to is substituted.
# Echoes the resolved line the game would have received, or nothing on refusal.
# Args: $1 = template, $2 = message
function __run_broadcast() {
  local template="$1"
  local message="$2"
  local out="$BROADCAST_TEST_TEMP_DIR/broadcast.out"

  rm -f "$out"
  mkfifo "$out" 2>/dev/null || return 1

  # Hold the read end open for the whole call. A FIFO discards its buffer the
  # moment every descriptor closes, so opening to read only after the writer has
  # finished races it away — the function under test opens, writes and closes
  # without waiting for anybody.
  local rfd
  exec {rfd}<>"$out"

  (
    # shellcheck disable=SC1090
    source "$KGSM_ROOT/core/errors.sh"
    function __print_error() { echo "$*" >&2; }
    instance_name="test-instance"
    instance_broadcast_command="$template"
    instance_socket_file="$out"
    # shellcheck disable=SC1090
    source "$NATIVE_IO"
    _send_broadcast "$message"
  ) 2>"$BROADCAST_TEST_TEMP_DIR/broadcast.err"
  local rc=$?

  local line=""
  read -r -t 2 line <&"${rfd}" || true

  exec {rfd}>&-
  rm -f "$out"

  echo "$line"
  return $rc
}

function setup_file() {
  log_test_step "Setting up broadcast tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$NATIVE_IO" "Native io module should exist"
  assert_file_exists "$CONTAINER_IO" "Container io module should exist"

  BROADCAST_TEST_TEMP_DIR=$(mktemp -d -t "kgsm-broadcast-test-XXXXXX")
  assert_dir_exists "$BROADCAST_TEST_TEMP_DIR" "Temp directory should be created"

  # The harness must be able to observe a send before any refusal test trusts an
  # empty result. Without this, a harness that cannot write at all makes every
  # "nothing was sent" assertion pass for the wrong reason.
  local probe
  probe="$(__run_broadcast 'probe {message}' 'ok')"
  assert_equals "probe ok" "$probe" \
    "The harness should observe a delivered line before refusals are asserted"

  log_test_step "Test environment validated"
}

function teardown_file() {
  log_test_step "Cleaning up broadcast test resources"

  if [[ -n "$BROADCAST_TEST_TEMP_DIR" && -d "$BROADCAST_TEST_TEMP_DIR" ]]; then
    rm -rf "$BROADCAST_TEST_TEMP_DIR"
  fi
}

# =============================================================================
# THE TEMPLATE CONTRACT
# =============================================================================

function test_both_runtimes_define_send_broadcast() {
  log_test_step "Testing both runtime io modules define _send_broadcast"

  assert_file_contains "$NATIVE_IO" "function _send_broadcast" \
    "Native io module should define _send_broadcast"
  assert_file_contains "$CONTAINER_IO" "function _send_broadcast" \
    "Container io module should define _send_broadcast"
}

function test_broadcast_does_not_use_the_input_sanitizer() {
  log_test_step "Testing _send_broadcast bypasses __sanitize_input_command"

  # The sanitizer rejects ! ? ( ) and more, which is most of ordinary prose. An
  # announcement routed through it could not carry a sentence, so the two paths
  # must stay separate — this asserts they have not been merged.
  local body
  body="$(sed -n '/^function _send_broadcast/,/^}/p' "$NATIVE_IO")"
  assert_not_contains "$body" "__sanitize_input_command" \
    "Broadcast must not route through the free-form input sanitizer"
}

function test_every_authored_template_carries_the_placeholder() {
  log_test_step "Testing every blueprint broadcast_command declares {message}"

  # A template with no placeholder would send its bare verb and drop the text —
  # a different command than the one asked for. Empty is fine (the game declares
  # none); malformed is not.
  local bp template name
  for bp in "$KGSM_ROOT"/blueprints/*.bp.yaml; do
    template="$(yq -r '.broadcast_command // ""' "$bp" 2>/dev/null)"
    [[ -z "$template" || "$template" == "null" ]] && continue
    name="$(basename "$bp" .bp.yaml)"
    assert_contains "$template" "{message}" \
      "Blueprint '$name' broadcast_command should carry a {message} placeholder"
  done
}

# =============================================================================
# SUBSTITUTION
# =============================================================================

function test_prefixed_template_resolves() {
  log_test_step "Testing a template with a verb resolves around the message"

  local line
  line="$(__run_broadcast '/say {message}' 'Hello world')"
  assert_equals "/say Hello world" "$line" \
    "The message should be substituted into the template"
}

function test_bare_placeholder_template_resolves() {
  log_test_step "Testing a template that is only the placeholder"

  # A console that treats any bare line as chat declares '{message}' and nothing
  # else. Rejecting that shape would silently drop every such game.
  local line
  line="$(__run_broadcast '{message}' 'Hello world')"
  assert_equals "Hello world" "$line" \
    "A bare-placeholder template should resolve to the message alone"
}

function test_quoted_template_resolves_inside_the_quotes() {
  log_test_step "Testing a template that quotes its message"

  local line
  line="$(__run_broadcast 'servermsg "{message}"' 'Back in 5')"
  assert_equals 'servermsg "Back in 5"' "$line" \
    "The message should land inside the template's quotes"
}

function test_prose_punctuation_survives() {
  log_test_step "Testing punctuation the input sanitizer rejects"

  # Every one of these characters is refused by __sanitize_input_command. An
  # announcement is prose and must carry them.
  local line
  line="$(__run_broadcast 'say {message}' 'Restarting in 5 minutes! (save first?)')"
  assert_equals 'say Restarting in 5 minutes! (save first?)' "$line" \
    "Prose punctuation should reach the console untouched"
}

# =============================================================================
# REFUSALS
# =============================================================================

function test_absent_template_is_refused() {
  log_test_step "Testing an instance with no broadcast_command refuses"

  local line
  line="$(__run_broadcast '' 'anything')"
  local rc=$?

  assert_not_equals "0" "$rc" "An undeclared broadcast command should fail"
  assert_null "$line" "Nothing should be sent when the game declares no command"
}

function test_template_without_placeholder_is_refused() {
  log_test_step "Testing a malformed template refuses rather than sending a bare verb"

  local line
  line="$(__run_broadcast 'say' 'anything')"
  local rc=$?

  assert_not_equals "0" "$rc" "A template with no placeholder should fail"
  assert_null "$line" "A bare verb should never be sent in place of the message"
}

function test_empty_message_is_refused() {
  log_test_step "Testing an empty message refuses"

  local line
  line="$(__run_broadcast 'say {message}' '')"
  local rc=$?

  assert_not_equals "0" "$rc" "An empty message should fail"
  assert_null "$line" "Nothing should be sent for an empty message"
}

function test_newline_in_message_is_refused() {
  log_test_step "Testing a line break in the message refuses"

  # The console reads one command per line, so a newline would deliver a second
  # command nobody issued. This is the one character the message may not carry.
  local line
  line="$(__run_broadcast 'say {message}' 'first
second')"
  local rc=$?

  assert_not_equals "0" "$rc" "A message containing a newline should fail"
  assert_null "$line" "Nothing should be sent when the message spans lines"
}

function test_carriage_return_in_message_is_refused() {
  log_test_step "Testing a carriage return in the message refuses"

  local line
  line="$(__run_broadcast 'say {message}' "$(printf 'first\rsecond')")"
  local rc=$?

  assert_not_equals "0" "$rc" "A message containing a carriage return should fail"
  assert_null "$line" "Nothing should be sent when the message carries a CR"
}

function test_overlong_message_is_refused() {
  log_test_step "Testing a message past the length cap refuses"

  local long
  long="$(printf 'a%.0s' {1..1001})"
  local line
  line="$(__run_broadcast 'say {message}' "$long")"
  local rc=$?

  assert_not_equals "0" "$rc" "A message over the cap should fail"
  assert_null "$line" "Nothing should be sent for an overlong message"
}
