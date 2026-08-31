#!/usr/bin/env bash

# KGSM Install Failure Exit-Code Tests
#
# Test Type: UNIT
# Target: commands/install.sh - the status an install returns when a step fails
#
# An install that could not create its files must not report success. The way it
# comes to: `step || { __print_error "..."; return $?; }` reads the status of the
# PRINTER, and a printer succeeds — so the block reports that the step it was
# complaining about worked. Anything scripting an install then believes it has a
# server, which is a fabricated outcome no later check can contradict, because
# every later check is about a server that was never built.
#
# The failure's own status is captured before anything else runs.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="install_failure_exit_codes"
readonly MODULE="$KGSM_ROOT/commands/install.sh"
readonly LOGGING_MODULE="$KGSM_ROOT/core/logging.sh"

function setup_file() {
  log_test_step "Setting up install failure exit-code tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "install.sh module should exist"
  assert_file_exists "$LOGGING_MODULE" "logging module should exist"

  log_test_step "Test environment validated"
}

# =============================================================================
# THE PREMISE
# =============================================================================

function test_print_error_succeeds() {
  log_test_step "Testing that __print_error itself returns success"

  # This is what makes the pattern dangerous rather than merely odd: reporting a
  # problem is not itself a problem, so the printer exits 0 and `return $?`
  # after it returns 0 too. If this ever stopped being true the bug would hide.
  local exit_code
  bash -c "source '$LOGGING_MODULE' >/dev/null 2>&1; __print_error 'probe' >/dev/null 2>&1"
  exit_code=$?

  assert_equals 0 "$exit_code" "__print_error should exit 0 — which is why \$? after it is useless"
}

# =============================================================================
# THE INVARIANT
# =============================================================================

function test_no_failure_block_returns_the_printers_status() {
  log_test_step "Testing that no failure block returns the status of its own error print"

  # Every `return $?` on the line after an error print, anywhere in the module.
  # The status wanted there belongs to the step that failed and was overwritten
  # the moment anything else ran.
  local offenders
  offenders=$(grep -A1 '__print_error' "$MODULE" | grep -c 'return \$?' || true)

  assert_equals 0 "$offenders" \
    "An error print must not be followed by 'return \$?' — capture the failure's status first"
}

function test_failure_blocks_return_a_captured_status() {
  log_test_step "Testing that the install's failure blocks return a captured status"

  # The four steps that build an instance on disk. Each must hand back the status
  # of the step, which means capturing it before the print.
  local -a steps=(
    "Failed to create instance working directory"
    "Failed to create instance symlink"
    "Failed to create directory structure"
    "Failed to create instance files"
  )

  local step block
  for step in "${steps[@]}"; do
    # The three lines around the print: the capture above it, the print, the return below.
    block=$(grep -B1 -A1 "$step" "$MODULE")

    assert_contains "$block" 'exit_code=$?' \
      "'$step' should capture the failing step's status before printing"
    assert_contains "$block" 'return $exit_code' \
      "'$step' should return the captured status, not the printer's"
  done
}

function test_exit_code_is_a_local() {
  log_test_step "Testing that the install command declares its exit_code local"

  # Assigned inside the failure blocks, so an undeclared one leaks into the shell
  # that sourced the command and outlives the install that set it.
  local body
  body=$(sed -n '/^function _cmd_install()/,/^}/p' "$MODULE")

  assert_contains "$body" "local exit_code" \
    "_cmd_install should declare exit_code local"
}
