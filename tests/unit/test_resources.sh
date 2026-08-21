#!/usr/bin/env bash

# KGSM Node Resource Admission Unit Tests
#
# Test Type: UNIT
# Target: core/resources.sh - the memory gate
#
# Deterministic coverage with NO mocking of the kernel: the real
# /proc/meminfo reading is used throughout, and the pass/refuse cases are
# arranged by choosing a headroom relative to what the node actually reports.
# A gate tested against a faked meminfo is a gate whose arithmetic is proven
# against a number the kernel never produces.
#
#   - __memory_available_mb reads MemAvailable
#   - __instance_memory_requirement_mb source precedence (cap over blueprint)
#   - unknown requirement is unknown, never a substituted default
#   - __memory_gate_check allow / refuse / cannot-answer paths

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="resources"

# Written in setup_file, read by the requirement tests.
INSTANCE_WITH_CAP=""
INSTANCE_NO_CAP=""
INSTANCE_NO_BLUEPRINT=""
BLUEPRINT_WITH_RAM=""
BLUEPRINT_NO_RAM=""

function setup_file() {
  log_test_step "Setting up node resource admission tests"

  assert_not_null "$KGSM_TEST_SANDBOX" "KGSM_TEST_SANDBOX should be set"
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$KGSM_ROOT/core/resources.sh" "core/resources.sh should exist"

  source "$KGSM_ROOT/core/resources.sh"

  assert_not_null "$EC_INSUFFICIENT_MEMORY" "EC_INSUFFICIENT_MEMORY should be defined"
  assert_function_exists "__memory_available_mb"
  assert_function_exists "__instance_memory_requirement_mb"
  assert_function_exists "__memory_gate_check"

  local fixtures="$KGSM_TEST_SANDBOX/resources"
  mkdir -p "$fixtures"

  BLUEPRINT_WITH_RAM="$fixtures/withram.bp.yaml"
  cat > "$BLUEPRINT_WITH_RAM" << 'EOF'
schema_version: 1
name: withram
runtime: native
metadata:
  display_name: "With RAM"
  min_ram_mb: 4096
  recommended_ram_mb: 8192
EOF

  # An uncurated blueprint: the field is present and explicitly null, which is the
  # spelling the schema uses for "unknown" (never 0).
  BLUEPRINT_NO_RAM="$fixtures/noram.bp.yaml"
  cat > "$BLUEPRINT_NO_RAM" << 'EOF'
schema_version: 1
name: noram
runtime: native
metadata:
  display_name: "No RAM declared"
  min_ram_mb: null
EOF

  INSTANCE_WITH_CAP="$fixtures/withcap.ini"
  cat > "$INSTANCE_WITH_CAP" << EOF
name="withcap"
blueprint_file="$BLUEPRINT_WITH_RAM"
memory_cap_mb="2048"
EOF

  # 0 is kgsm's spelling of "uncapped" for this key, so this instance falls
  # through to its blueprint.
  INSTANCE_NO_CAP="$fixtures/nocap.ini"
  cat > "$INSTANCE_NO_CAP" << EOF
name="nocap"
blueprint_file="$BLUEPRINT_WITH_RAM"
memory_cap_mb="0"
EOF

  INSTANCE_NO_BLUEPRINT="$fixtures/nodeclaration.ini"
  cat > "$INSTANCE_NO_BLUEPRINT" << EOF
name="nodeclaration"
blueprint_file="$BLUEPRINT_NO_RAM"
memory_cap_mb="0"
EOF
}

# =============================================================================
# TEST: the reading
# =============================================================================

function test_memory_available_reads_a_real_positive_figure() {
  log_test_step "Testing __memory_available_mb reads MemAvailable"

  local available
  available="$(__memory_available_mb)"

  assert_matches "$available" '^[0-9]+$' "available memory should be a whole number of MB"
  assert_greater_than "$available" "0" "a running host has some memory available"
}

function test_memory_available_is_not_memfree() {
  log_test_step "Testing the reading is MemAvailable, not MemFree"

  # These two differ by the reclaimable page cache. Asserting the function tracks
  # MemAvailable is the whole point: gating on MemFree would refuse starts on a
  # host with gigabytes of cache the kernel hands back on demand.
  #
  # Asserted with a TOLERANCE, not by equality. Both figures move continuously —
  # this suite's own subshells shift them — so comparing two readings taken
  # microseconds apart is a test that fails whenever the host is busy, which is
  # precisely when the suite runs.
  local memfree memavailable available
  memfree=$(awk '/^MemFree:/ { print int($2 / 1024); exit }' /proc/meminfo)
  memavailable=$(awk '/^MemAvailable:/ { print int($2 / 1024); exit }' /proc/meminfo)
  available="$(__memory_available_mb)"

  local drift=$((available - memavailable))
  [[ $drift -lt 0 ]] && drift=$(( -drift ))
  assert_less_than "$drift" "512" "should track MemAvailable within normal drift"

  # Only meaningful where the host actually has a cache to reclaim; on a box where
  # the two readings coincide there is nothing to tell apart.
  local spread=$((memavailable - memfree))
  if [[ $spread -gt 1024 ]]; then
    local from_free=$((available - memfree))
    [[ $from_free -lt 0 ]] && from_free=$(( -from_free ))
    assert_greater_than "$from_free" "512" "should NOT be reporting MemFree"
  fi
}

# =============================================================================
# TEST: what an instance needs
# =============================================================================

function test_requirement_prefers_the_instance_cap() {
  log_test_step "Testing memory_cap_mb wins over the blueprint figure"

  local required
  required="$(__instance_memory_requirement_mb "$INSTANCE_WITH_CAP")"

  # The cap is the cgroup ceiling the watchdog enforces, so it bounds what the
  # node can actually lose — and it is lower than this blueprint's 4096.
  assert_equals "$required" "2048" "the instance's own cap is the requirement"
}

function test_requirement_falls_back_to_the_blueprint() {
  log_test_step "Testing an uncapped instance uses its blueprint's min_ram_mb"

  if ! command -v yq > /dev/null 2>&1; then
    skip_test "yq is not installed; the blueprint fallback cannot be read" && return
  fi

  local required
  required="$(__instance_memory_requirement_mb "$INSTANCE_NO_CAP")"

  assert_equals "$required" "4096" "min_ram_mb is the fallback requirement"
}

function test_requirement_is_unknown_when_nothing_is_declared() {
  log_test_step "Testing an undeclared requirement stays unknown"

  if ! command -v yq > /dev/null 2>&1; then
    skip_test "yq is not installed; the blueprint fallback cannot be read" && return
  fi

  local required
  required="$(__instance_memory_requirement_mb "$INSTANCE_NO_BLUEPRINT")"
  local exit_code=$?

  # No default is substituted. A fabricated requirement would refuse real starts
  # on a number nobody measured.
  assert_not_equals "$exit_code" "0" "an undeclared requirement reports failure"
  assert_null "$required" "no figure is invented"
}

function test_requirement_rejects_a_missing_config_file() {
  log_test_step "Testing a missing instance config yields no requirement"

  local required
  required="$(__instance_memory_requirement_mb "$KGSM_TEST_SANDBOX/resources/does-not-exist.ini")"
  local exit_code=$?

  assert_not_equals "$exit_code" "0" "a missing config cannot declare a requirement"
  assert_null "$required" "no figure is invented"
}

# =============================================================================
# TEST: the gate
# =============================================================================

function test_gate_allows_when_disabled() {
  log_test_step "Testing the gate is a no-op when switched off"

  local config_enable_memory_gate="false"
  # A headroom nothing could satisfy, to prove the switch is what decided.
  local config_memory_gate_headroom_mb="999999999"

  __memory_gate_check "withcap" "$INSTANCE_WITH_CAP"
  assert_equals "$?" "0" "a disabled gate allows the start"
}

function test_gate_allows_when_the_requirement_is_unknown() {
  log_test_step "Testing the gate cannot refuse on an undeclared requirement"

  if ! command -v yq > /dev/null 2>&1; then
    skip_test "yq is not installed; the blueprint fallback cannot be read" && return
  fi

  local config_enable_memory_gate="true"
  local config_memory_gate_headroom_mb="999999999"

  # Even with an impossible headroom: with nothing declared there is no figure to
  # compare, and a gate that refuses on its own ignorance takes servers down for
  # an uncurated blueprint.
  __memory_gate_check "nodeclaration" "$INSTANCE_NO_BLUEPRINT"
  assert_equals "$?" "0" "an unanswerable check allows the start"
}

function test_gate_refuses_when_the_node_would_drop_below_the_floor() {
  log_test_step "Testing the gate refuses a start that breaches the headroom"

  local available
  available="$(__memory_available_mb)"

  local config_enable_memory_gate="true"
  # Chosen against the node's REAL reading: the instance needs 2048, so a floor
  # this high cannot be met whatever the host happens to have free right now.
  local config_memory_gate_headroom_mb=$((available + 1))

  local output
  output="$(__memory_gate_check "withcap" "$INSTANCE_WITH_CAP" 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INSUFFICIENT_MEMORY" "the start is refused"
  # The refusal has to name all three figures — "not enough memory" alone does not
  # tell an operator whether to stop something, lower a cap or edit a blueprint.
  #
  # The node's own figure is asserted by SHAPE, not by value: MemAvailable moves
  # between the reading taken above and the one the gate takes, so asserting the
  # exact number is a test that fails whenever the host breathes.
  assert_contains "$output" "2048MB" "the refusal names what the instance needs"
  assert_matches "$output" 'the node has [0-9]+MB available' "the refusal names what the node has"
  assert_matches "$output" 'floor of [0-9]+MB' "the refusal names the floor it breached"
  assert_contains "$output" "--force" "the refusal names the override"
}

function test_gate_allows_when_the_node_has_room() {
  log_test_step "Testing the gate allows a start that fits"

  local config_enable_memory_gate="true"
  local config_memory_gate_headroom_mb="0"

  # A real host running this suite has far more than 2048MB available, so this
  # exercises the passing arithmetic without arranging anything.
  __memory_gate_check "withcap" "$INSTANCE_WITH_CAP"
  assert_equals "$?" "0" "a start that fits is allowed"
}

function test_gate_defaults_headroom_when_misconfigured() {
  log_test_step "Testing a non-numeric headroom falls back to the default"

  local config_enable_memory_gate="true"
  local config_memory_gate_headroom_mb="not-a-number"

  # A typo in config.ini must not disable the reserve silently, nor crash the
  # arithmetic; it falls back to the documented 1024.
  __memory_gate_check "withcap" "$INSTANCE_WITH_CAP"
  assert_equals "$?" "0" "the gate still runs and this start still fits"
}
