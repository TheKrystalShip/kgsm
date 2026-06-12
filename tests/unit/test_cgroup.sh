#!/usr/bin/env bash

# KGSM cgroup Primitives Unit Tests
#
# Test Type: UNIT
# Target: core/cgroup.sh - cgroup v2 process-supervision primitives
#
# Deterministic coverage (no privilege needed):
#   - __cgroup_base / __cgroup_path / __cgroup_enable_string
#   - __cgroup_kernel_has_kill / __cgroup_supported
#   - argument validation + absent-cgroup behavior
#
# A live create -> attach -> kill -> remove round-trip runs ONLY when a real
# delegated base exists (i.e. `kgsm system setup-cgroups` has been run). With no
# mocks, it exercises real cgroupfs or skips — never fakes the kernel.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="cgroup"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up cgroup primitives tests"

  assert_not_null "$KGSM_TEST_SANDBOX" "KGSM_TEST_SANDBOX should be set"
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$KGSM_ROOT/core/cgroup.sh" "core/cgroup.sh should exist"

  # Source the module (bootstrap is already loaded by the test runner)
  source "$KGSM_ROOT/core/cgroup.sh"

  # Verify required error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_CGROUP" "EC_CGROUP should be defined"
  assert_not_null "$EC_CGROUP_UNSUPPORTED" "EC_CGROUP_UNSUPPORTED should be defined"
}

# =============================================================================
# TEST: base + path resolution
# =============================================================================

function test_cgroup_base_resolves_from_config() {
  log_test_step "Testing __cgroup_base resolves mount + base from config"

  local config_cgroup_mount_point="/sys/fs/cgroup"
  local config_cgroup_base_name="kgsm.slice"

  local base
  base="$(__cgroup_base)"
  assert_equals "$base" "/sys/fs/cgroup/kgsm.slice" "base should be mount/base_name"
}

function test_cgroup_path_appends_instance_and_strips_ini() {
  log_test_step "Testing __cgroup_path appends instance and strips .ini"

  local config_cgroup_mount_point="/sys/fs/cgroup"
  local config_cgroup_base_name="kgsm.slice"

  local path
  path="$(__cgroup_path "factorio-42")"
  assert_equals "$path" "/sys/fs/cgroup/kgsm.slice/factorio-42" "path should be base/instance"

  path="$(__cgroup_path "factorio-42.ini")"
  assert_equals "$path" "/sys/fs/cgroup/kgsm.slice/factorio-42" "trailing .ini should be stripped"
}

function test_cgroup_path_rejects_empty() {
  log_test_step "Testing __cgroup_path rejects empty instance name"

  __cgroup_path ""
  local rc=$?
  assert_equals "$rc" "$EC_INVALID_ARG" "empty name should return EC_INVALID_ARG"
}

# =============================================================================
# TEST: controller enable-string formatting
# =============================================================================

function test_cgroup_enable_string_formats_controllers() {
  log_test_step "Testing __cgroup_enable_string formats +controller tokens"

  local config_cgroup_controllers="cpu memory io pids"
  local str
  str="$(__cgroup_enable_string)"
  assert_equals "$str" "+cpu +memory +io +pids" "should prefix each controller with +"
}

# =============================================================================
# TEST: capability detection
# =============================================================================

function test_cgroup_kernel_has_kill_on_modern_kernel() {
  log_test_step "Testing __cgroup_kernel_has_kill against the running kernel"

  local kver major minor
  kver="$(uname -r)"
  major="${kver%%.*}"
  minor="${kver#*.}"
  minor="${minor%%.*}"

  if [[ "$major" -lt 5 ]] || { [[ "$major" -eq 5 ]] && [[ "$minor" -lt 14 ]]; }; then
    skip_test "kernel $kver < 5.14 (cgroup.kill unavailable)" && return
  fi

  __cgroup_kernel_has_kill
  assert_equals "$?" "0" "kernel >= 5.14 should report cgroup.kill support"
}

function test_cgroup_supported_false_when_base_missing() {
  log_test_step "Testing __cgroup_supported fails when the base is absent"

  local config_cgroup_mount_point="/sys/fs/cgroup"
  local config_cgroup_base_name="kgsm-nonexistent-${RANDOM}.slice"

  __cgroup_supported
  local rc=$?
  assert_equals "$rc" "$EC_CGROUP_UNSUPPORTED" \
    "missing/unwritable base should be unsupported"
}

# =============================================================================
# TEST: argument validation + absent-cgroup behavior
# =============================================================================

function test_cgroup_attach_validates_args() {
  log_test_step "Testing __cgroup_attach argument validation"

  __cgroup_attach "" ""
  assert_equals "$?" "$EC_INVALID_ARG" "missing args should return EC_INVALID_ARG"

  __cgroup_attach "someinstance" "not-a-number"
  assert_equals "$?" "$EC_INVALID_ARG" "non-numeric pid should return EC_INVALID_ARG"
}

function test_cgroup_is_populated_absent_returns_inactive() {
  log_test_step "Testing __cgroup_is_populated on an absent cgroup"

  local config_cgroup_mount_point="/sys/fs/cgroup"
  local config_cgroup_base_name="kgsm-nonexistent-${RANDOM}.slice"

  __cgroup_is_populated "ghost-instance"
  assert_equals "$?" "1" "absent cgroup should be reported unpopulated"
}

function test_cgroup_remove_absent_is_success() {
  log_test_step "Testing __cgroup_remove is a no-op when already gone"

  local config_cgroup_mount_point="/sys/fs/cgroup"
  local config_cgroup_base_name="kgsm-nonexistent-${RANDOM}.slice"

  __cgroup_remove "ghost-instance"
  assert_equals "$?" "$EC_SUCCESS" "removing an absent cgroup should succeed"
}

# =============================================================================
# TEST: live round-trip (capability-gated)
# =============================================================================

function test_cgroup_lifecycle_roundtrip() {
  log_test_step "Testing live cgroup create -> attach -> kill -> remove"

  # Only run when a real delegated base exists; otherwise skip (no mocks).
  if ! __cgroup_supported; then
    skip_test "no delegated cgroup base (run 'kgsm system setup-cgroups')" && return
  fi

  local inst="kgsm-cgtest-$$-${RANDOM}"
  local cg
  cg="$(__cgroup_path "$inst")"

  # Create
  __cgroup_create "$inst"
  assert_equals "$?" "$EC_SUCCESS" "cgroup create should succeed"
  assert_dir_exists "$cg" "instance cgroup directory should exist"

  # Spawn a short-lived helper and try to place it in the cgroup. Rootless entry
  # only works from INSIDE a user-owned delegated subtree (the cgroup-v2
  # delegation-containment rule needs write on the source/dest common ancestor);
  # an SSH/system.slice login or CI without delegation cannot, so we skip rather
  # than fail. NOTE: the helper is bounded (sleep 5) and always killed before any
  # wait, so this test can never block the suite.
  sleep 5 &
  local sleep_pid=$!
  __cgroup_attach "$inst" "$sleep_pid"
  local attach_rc=$?

  if [[ "$attach_rc" -ne "$EC_SUCCESS" ]]; then
    kill -9 "$sleep_pid" 2> /dev/null
    wait "$sleep_pid" 2> /dev/null
    rmdir "$cg" 2> /dev/null
    skip_test "cannot enter delegated base from this cgroup context (needs root or a systemd user session)" && return
  fi

  # We have a live process inside the cgroup -> it must read populated.
  __cgroup_is_populated "$inst"
  assert_equals "$?" "0" "cgroup with a live process should be populated"

  # Kill the whole subtree atomically.
  __cgroup_kill "$inst"
  assert_equals "$?" "$EC_SUCCESS" "cgroup kill should succeed"

  # Bounded drain (<= 5s); never an unbounded wait.
  local i=0
  while __cgroup_is_populated "$inst" && [[ "$i" -lt 50 ]]; do
    sleep 0.1
    ((i++)) || true
  done

  # The helper was SIGKILLed by cgroup.kill; kill -9 is a no-op safety net, and
  # wait only ever runs after a kill, so it reaps instantly and cannot block.
  kill -9 "$sleep_pid" 2> /dev/null
  wait "$sleep_pid" 2> /dev/null

  __cgroup_is_populated "$inst"
  assert_equals "$?" "1" "cgroup should be empty after kill"

  # Remove
  __cgroup_remove "$inst"
  assert_equals "$?" "$EC_SUCCESS" "cgroup remove should succeed"
  assert_command_fails "test -d '$cg'" "cgroup directory should be gone"
}
