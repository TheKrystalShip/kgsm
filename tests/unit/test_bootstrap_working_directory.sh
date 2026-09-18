#!/usr/bin/env bash

# KGSM Bootstrap Working Directory Unit Tests
#
# Test Type: UNIT
# Target: core/bootstrap.sh - leaving a working directory this account cannot enter
#
# The engine is run as the service account from a person's login shell
# (`sudo -u kgsm -H kgsm ...`), so it starts in that person's home, which is
# typically closed to the service account. Every `find` the engine runs then
# fails to restore its starting directory and prints an error for it, burying
# the command's real output.

readonly MODULE="$KGSM_ROOT/core/bootstrap.sh"

function setup_file() {
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "bootstrap.sh should exist"
}

function setup() {
  CWD_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kgsm-cwd-test-XXXXXX")"
  export CWD_TEST_DIR
}

function teardown() {
  [[ -n "${CWD_TEST_DIR:-}" && -d "$CWD_TEST_DIR" ]] && {
    chmod -R u+rwx "$CWD_TEST_DIR" 2> /dev/null
    rm -rf "$CWD_TEST_DIR"
  }
  return 0
}

function test_a_closed_working_directory_produces_no_find_errors() {
  log_test_step "Testing that a command started in an unenterable directory prints no find errors"

  # Entering the directory and then closing it gives the same shape without a
  # second account: the process holds a working directory it cannot enter.
  mkdir -p "$CWD_TEST_DIR/closed"

  local output
  output="$(cd "$CWD_TEST_DIR/closed" && chmod 000 . && "$KGSM_ROOT/kgsm.sh" instances list 2>&1)"

  assert_not_contains "$output" "Failed to restore initial working directory" \
    "The engine should leave a working directory it cannot enter before running any find"
}
