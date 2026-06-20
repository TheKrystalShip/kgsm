#!/usr/bin/env bash

# KGSM Parser Logic Unit Tests
#
# Test Type: UNIT
# Target: core/parser.sh - UFW port-spec parsing
#
# The single canonical UFW-spec parser (__parse_ufw_port_spec) and the two forms
# derived from it: the structured JSON array (__ufw_ports_to_json, the machine-readable
# port format on `instances info --json`) and the flat expanded list
# (__expand_ufw_ports_flat, consumed by the non-watchdog fallback's port-forwarding
# + the port-conflict scan). Fixtures are pinned to output captured from the real
# functions.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="parser_logic"
readonly MODULE="$KGSM_ROOT/core/parser.sh"

function setup_file() {
  log_test_step "Setting up parser logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "Parser module should exist"

  source "$MODULE"

  assert_not_null "$EC_ERROR" "EC_ERROR should be defined"
  assert_not_null "$EC_SUCCESS" "EC_SUCCESS should be defined"

  assert_function_exists "__parse_ufw_port_spec" "canonical parser should be exported"
  assert_function_exists "__ufw_ports_to_json" "json form should be exported"
  assert_function_exists "__expand_ufw_ports_flat" "flat form should be exported"

  log_test_step "Parser logic test environment validated"
}

# =============================================================================
# __parse_ufw_port_spec() — the canonical "<start> <end> <proto>" triples
# =============================================================================

function test_port_spec_single_with_proto() {
  log_test_step "Single port with protocol -> one triple"
  assert_equals "27016 27016 tcp" "$(__parse_ufw_port_spec '27016/tcp')" \
    "single port/proto should map start==end"
}

function test_port_spec_range_with_proto_is_range_preserving() {
  log_test_step "Range with protocol stays ONE triple (range-preserving)"
  assert_equals "27015 27020 udp" "$(__parse_ufw_port_spec '27015:27020/udp')" \
    "a range must not be unrolled in the canonical form"
}

function test_port_spec_protoless_single_expands_to_both() {
  log_test_step "Proto-less single port -> both tcp and udp"
  local expected; expected=$'34197 34197 tcp\n34197 34197 udp'
  assert_equals "$expected" "$(__parse_ufw_port_spec '34197')" \
    "proto-less should expand to both protocols"
}

function test_port_spec_protoless_range_expands_to_both() {
  log_test_step "Proto-less range -> both tcp and udp, each range-preserving"
  local expected; expected=$'27015 27020 tcp\n27015 27020 udp'
  assert_equals "$expected" "$(__parse_ufw_port_spec '27015:27020')" \
    "proto-less range should yield two range triples"
}

function test_port_spec_pipe_separated_multi() {
  log_test_step "Pipe-separated entries parse in order"
  local expected; expected=$'27015 27017 udp\n27016 27016 tcp'
  assert_equals "$expected" "$(__parse_ufw_port_spec '27015:27017/udp|27016/tcp')" \
    "multiple entries should each produce a triple"
}

function test_port_spec_empty_is_silent_success() {
  log_test_step "Empty spec -> no output, success"
  local output; output="$(__parse_ufw_port_spec '')"
  assert_equals "" "$output" "empty spec should echo nothing"
  assert_command_succeeds "__parse_ufw_port_spec ''" "empty spec should succeed"
}

function test_port_spec_malformed_fails() {
  log_test_step "Malformed entry -> EC_ERROR"
  assert_command_fails "__parse_ufw_port_spec not-a-port" \
    "a malformed entry should return non-zero"
}

# =============================================================================
# __ufw_ports_to_json() — structured array (the canonical machine surface)
# =============================================================================

function test_json_factorio_real_shape() {
  log_test_step "Proto-less single -> the real factorio-test array shape"
  # Captured verbatim from `kgsm instances info factorio-test --json | jq -c .ports`.
  local expected='[{"start":34197,"end":34197,"protocol":"tcp"},{"start":34197,"end":34197,"protocol":"udp"}]'
  assert_equals "$expected" "$(__ufw_ports_to_json '34197')" \
    "factorio proto-less port should match the captured wire shape"
}

function test_json_range_is_preserved() {
  log_test_step "Range stays a single {start,end} object"
  assert_equals '[{"start":27015,"end":27020,"protocol":"udp"}]' \
    "$(__ufw_ports_to_json '27015:27020/udp')" \
    "the JSON form must preserve ranges, not unroll them"
}

function test_json_multi_mixed() {
  log_test_step "Mixed range + single, proto-explicit"
  local expected='[{"start":27015,"end":27017,"protocol":"udp"},{"start":27016,"end":27016,"protocol":"tcp"}]'
  assert_equals "$expected" "$(__ufw_ports_to_json '27015:27017/udp|27016/tcp')" \
    "mixed entries should map element-for-element"
}

function test_json_empty_is_empty_array() {
  log_test_step "Empty spec -> [] (valid JSON, never empty string)"
  assert_equals "[]" "$(__ufw_ports_to_json '')" "empty spec must yield []"
}

function test_json_malformed_is_empty_array() {
  log_test_step "Malformed spec -> [] (graceful, never breaks the JSON pipeline)"
  assert_equals "[]" "$(__ufw_ports_to_json 'abc/xyz' 2>/dev/null)" \
    "malformed spec must degrade to []"
}

# Cross-codebase round-trip fidelity (CONTRACT TEST). The watchdog emits the UPnP
# (and the firewall path the ports) event by rendering the structured Instance.Ports
# back to a UFW string via kgsm-lib PortMappingExtensions.ToUfwSpec(), then kgsm's
# events emit re-parses that string here. The two MUST be exact inverses or the
# audit row's ports silently differ. This locks the kgsm half against the EXACT
# literal kgsm-lib's `ToUfwSpec_renders_single_and_range_entries_pipe_joined` test
# asserts ToUfwSpec produces — if either side changes its format, one of the two
# tests fails loudly. (kgsm-lib: List<PortMapping>{27015:27020/udp, 27016/tcp}.)
function test_json_round_trips_the_lib_toufwspec_format() {
  log_test_step "ToUfwSpec output ('27015:27020/udp|27016/tcp') re-parses to the same structured ports"
  local expected='[{"start":27015,"end":27020,"protocol":"udp"},{"start":27016,"end":27016,"protocol":"tcp"}]'
  assert_equals "$expected" "$(__ufw_ports_to_json '27015:27020/udp|27016/tcp')" \
    "kgsm-lib ToUfwSpec and kgsm __ufw_ports_to_json must be exact inverses"
}

# =============================================================================
# __expand_ufw_ports_flat() — flat expanded form (fallback port-forwarding + conflict scan)
# =============================================================================

function test_flat_range_is_unrolled() {
  log_test_step "Range unrolled to individual 'port proto' pairs"
  assert_equals "27015 udp 27016 udp 27017 udp" \
    "$(__expand_ufw_ports_flat '27015:27017/udp')" \
    "the flat form must list every port of a range"
}

function test_flat_protoless_covers_both() {
  log_test_step "Proto-less single -> both protocols, flat"
  assert_equals "80 tcp 80 udp" "$(__expand_ufw_ports_flat '80')" \
    "proto-less should expand to both tcp and udp"
}

function test_flat_empty_is_empty() {
  log_test_step "Empty spec -> empty flat output"
  assert_equals "" "$(__expand_ufw_ports_flat '')" "empty spec should echo nothing"
}
