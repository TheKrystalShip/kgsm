#!/usr/bin/env bash

# KGSM Exit-Code Honesty Unit Tests
#
# Test Type: UNIT
# Target: commands/, core/ — the status a module returns when it reports a failure
#
# A module that prints an error and returns 0 tells its caller the opposite of
# what it told the operator, and the caller is the one that acts. kgsm-api marks
# a job succeeded on a 0, so a 0 out of a failed install becomes a chat message
# telling somebody their server exists.
#
# Bash offers three ways to lose the status, and all three are silent:
#
#   `__print_error "..."; return $?`  — $? is the PRINTER's status, and a
#                                       printer succeeds
#   `if ! cmd; then exit $?; fi`      — $? inside the branch is the status of
#                                       the NEGATION, which is always 0
#   `return $EC_TYPO`                 — an unset name expands to nothing, making
#                                       it a bare `return`, which yields the
#                                       status of whatever ran last (a print)
#
# The first is covered for install.sh by test_install_failure_exit_codes.sh.
# This file covers the other two across every module, because each is a whole
# class rather than a site: nothing warns, no test fails, and the module reports
# success.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="exit_code_honesty"
readonly ERRORS_MODULE="$KGSM_ROOT/core/errors.sh"
readonly LOGGING_MODULE="$KGSM_ROOT/core/logging.sh"

# Every tree holding shell that returns a status to a caller. templates/ and
# overrides/ are here because a management script is generated from them and
# runs in its own process, and migrations/ because a migration that reports
# success unapplied lets the schema version move past it.
readonly -a SCANNED_DIRS=("commands" "core" "migrations" "templates" "overrides")

# The files that define their own print helpers instead of using core/logging.sh.
# A generated management script is standalone and carries its own, so the
# contract has to hold in each family or it only holds in the engine's process.
readonly -a STANDALONE_PRINTER_FILES=(
  "$KGSM_ROOT/templates/manage.native.d/01-config.sh"
  "$KGSM_ROOT/templates/manage.container.d/01-config.sh"
)

readonly -a PRINTERS=(__print_error __print_warning __print_info __print_success)

function setup_file() {
  log_test_step "Setting up exit-code honesty tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM_ROOT directory should exist"
  assert_file_exists "$ERRORS_MODULE" "core/errors.sh should exist"

  log_test_step "Environment validated"
}

# Lists every scanned shell file, one per line.
function __scanned_files() {
  local dir
  for dir in "${SCANNED_DIRS[@]}"; do
    find "$KGSM_ROOT/$dir" -name '*.sh' -type f
  done
}

# =============================================================================
# THE PREMISE
# =============================================================================

function test_unset_code_makes_return_yield_the_previous_status() {
  log_test_step "Testing that a return with an unset code yields the previous status"

  # This is why a mistyped constant is invisible rather than noisy: `return
  # $EC_NOT_A_REAL_NAME` is not an error, it is a bare `return`, and a bare
  # return hands back whatever ran last. After an error print, that is 0.
  local exit_code
  bash -c 'f() { echo reporting-a-failure; return $EC_NOT_A_REAL_NAME; }; f >/dev/null 2>&1'
  exit_code=$?

  assert_equals 0 "$exit_code" \
    "An unset EC_ name should make return yield 0 — which is why every name must be defined"
}

function test_negated_branch_hides_the_status() {
  log_test_step "Testing that \$? inside an 'if !' branch is the negated status"

  # The reason `if ! cmd; then exit $?; fi` cannot work: the branch is entered
  # BECAUSE the negation succeeded, so $? is that success, never the command's
  # failure.
  local exit_code
  bash -c 'if ! (exit 42); then exit $?; fi'
  exit_code=$?

  assert_equals 0 "$exit_code" \
    "\$? inside an 'if !' branch should be 0 — which is why the status must be taken with ||"
}

# =============================================================================
# THE INVARIANTS
# =============================================================================

function test_every_referenced_error_code_is_defined() {
  log_test_step "Testing that every EC_ name used is defined in core/errors.sh"

  # An undefined name is not a typo the shell reports; it is a `return 0` in a
  # branch written to report a failure. The check is name-level rather than
  # site-level because a name that exists nowhere cannot be right anywhere.
  local defined_list undefined
  defined_list="$(grep -oP 'declare -g -r \KEC_[A-Z0-9_]*' "$ERRORS_MODULE" | sort -u)"

  assert_not_null "$defined_list" "core/errors.sh should declare EC_ constants"

  # EC_SYSTEMD names a retired code and survives only in the comment recording
  # that its number is not to be reused, so it is read out of the same file that
  # defines the vocabulary rather than being listed here.
  local used_list
  used_list="$(
    __scanned_files | xargs grep -ohE '\$EC_[A-Z0-9_]+|\bEC_[A-Z0-9_]+' 2>/dev/null |
      tr -d '$' | grep -vx 'EC_' | sort -u
  )"

  undefined="$(comm -23 <(printf '%s\n' "$used_list") <(printf '%s\n' "$defined_list") |
    grep -vx 'EC_SYSTEMD' || true)"

  assert_equals "" "$undefined" \
    "Every EC_ name used in commands/ and core/ should be defined in core/errors.sh"
}

function test_no_status_is_read_inside_a_negated_branch() {
  log_test_step "Testing that no module reads \$? inside an 'if !' branch"

  # Matches the shape, not a list of known sites: a return or exit of $? as the
  # FIRST statement after `if ! ...; then`, which is the position where $? can
  # only be the negation. A `return $?` further down the branch is reporting on
  # whatever ran immediately before it and is usually correct — several
  # migrations end a branch with `printf ...; return $?`, which is right — so
  # widening the window past one line turns a defect scan into noise.
  local offenders
  offenders="$(
    __scanned_files | while read -r file; do
      awk 'prev ~ /^[[:space:]]*if ! .*; then[[:space:]]*$/ &&
           $0 ~ /^[[:space:]]*(return|exit) \$\?[[:space:]]*$/ {
             print FILENAME ":" FNR
           }
           { prev = $0 }' "$file"
    done
  )"

  assert_equals "" "$offenders" \
    "No module should read \$? as the first statement of an 'if !' branch — \$? there is the negation, always 0"
}

function test_every_printer_family_returns_success() {
  log_test_step "Testing that every print helper returns success"

  # The premise, checked where it actually has to hold. core/logging.sh is the
  # engine's; a generated management script is standalone and defines its own,
  # so `return $?` after a print is equally wrong in a per-instance script and
  # equally invisible there. Checking one family would leave the guarantee true
  # only in the engine's own process.
  local printer exit_code
  for printer in "${PRINTERS[@]}"; do
    bash -c "source '$LOGGING_MODULE' >/dev/null 2>&1; $printer 'probe' >/dev/null 2>&1"
    exit_code=$?
    assert_equals 0 "$exit_code" \
      "core/logging.sh $printer should return 0 — which is why \$? after it is useless"
  done

  # Extracted rather than sourced: these files are fragments of a generated
  # script and exit early when run outside one, which would leave the function
  # undefined and the call reporting 127 rather than the printer's status.
  local file body
  for file in "${STANDALONE_PRINTER_FILES[@]}"; do
    assert_file_exists "$file" "Management script config fragment should exist"

    for printer in "${PRINTERS[@]}"; do
      body="$(awk "/^function ${printer}\(\)/,/^}/" "$file")"
      assert_not_null "$body" "$file should define $printer"

      bash -c "$body
$printer 'probe' >/dev/null 2>&1"
      exit_code=$?
      assert_equals 0 "$exit_code" \
        "${file##*/} $printer should return 0 — the contract holds in every printer family or in none"
    done
  done
}

# =============================================================================
# THE BEHAVIOUR
# =============================================================================

function test_uninstall_reports_a_missing_instance_as_a_failure() {
  log_test_step "Testing that uninstalling an instance that does not exist fails"

  # The end-to-end shape of the bug: the module printed "not found" twice and
  # exited 0, so nothing scripting an uninstall could tell a removal from a
  # refusal.
  local exit_code
  "$KGSM_ROOT/commands/uninstall.sh" no-such-instance-exit-code-probe < /dev/null > /dev/null 2>&1
  exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "Uninstalling a nonexistent instance should return a failure status, not 0"
}

function test_directories_create_reports_a_missing_instance_as_a_failure() {
  log_test_step "Testing that creating directories for a missing instance fails"

  # install.sh guards this call with `|| { ... }`, so a 0 here means the install
  # walks past its own directory step believing the tree exists.
  local exit_code
  "$KGSM_ROOT/commands/directories.sh" create no-such-instance-exit-code-probe < /dev/null > /dev/null 2>&1
  exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "Creating directories for a nonexistent instance should return a failure status, not 0"
}
