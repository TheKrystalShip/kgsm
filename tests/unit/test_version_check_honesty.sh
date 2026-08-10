#!/usr/bin/env bash

# KGSM Version-Check Honesty Unit Tests
#
# Test Type: UNIT
# Target: templates/manage.{native,container}.d/05-version.sh + 11-status.sh
#
# An update check has three outcomes, not two: an update is available, the
# server is current, or the remote could not be asked. Collapsing the third into
# the second reports a server as up to date on the strength of a check that
# never completed — a fabricated status, and the one this module must never
# produce.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="version_check_honesty"
readonly CONTAINER_VERSION_MODULE="$KGSM_ROOT/templates/manage.container.d/05-version.sh"
readonly CONTAINER_STATUS_MODULE="$KGSM_ROOT/templates/manage.container.d/11-status.sh"
readonly NATIVE_STATUS_MODULE="$KGSM_ROOT/templates/manage.native.d/11-status.sh"

# =============================================================================
# TEST SETUP FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up version-check honesty tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM_ROOT directory should exist"

  assert_file_exists "$CONTAINER_VERSION_MODULE" "Container version module should exist"
  assert_file_exists "$CONTAINER_STATUS_MODULE" "Container status module should exist"
  assert_file_exists "$NATIVE_STATUS_MODULE" "Native status module should exist"

  log_test_step "Environment validated"
}

function setup() {
  VERSION_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kgsm-version-test-XXXXXX")"
  export VERSION_TEST_DIR
}

function teardown() {
  [[ -n "${VERSION_TEST_DIR:-}" && -d "$VERSION_TEST_DIR" ]] &&
    rm -rf "$VERSION_TEST_DIR"
  return 0
}

# Runs a snippet with the container version module sourced and the instance
# variables it reads pointed at a scratch directory. The module is a fragment of
# the generated management script, so it needs the print helpers and exit-code
# constants that script's earlier modules define.
function run_in_version_module() {
  local compose_body="$1"
  local snippet="$2"

  mkdir -p "$VERSION_TEST_DIR/work"
  printf '%s\n' "$compose_body" >"$VERSION_TEST_DIR/work/docker-compose.yml"

  bash <<EOF 2>/dev/null
readonly EC_SUCCESS=0
readonly EC_ERROR=1
function __print_info()    { :; }
function __print_error()   { :; }
function __print_warning() { :; }
function __print_success() { :; }
instance_working_dir="$VERSION_TEST_DIR/work"
instance_compose_file="$VERSION_TEST_DIR/work/docker-compose.yml"
instance_version_file="$VERSION_TEST_DIR/work/.test.version"
source "$CONTAINER_VERSION_MODULE"
$snippet
EOF
}

# =============================================================================
# THE STATUS SURFACE MUST NOT CONFLATE THE TWO FAILURES
# =============================================================================

# _compare_versions returns the same error for "already current" as for "the
# remote did not answer" — that is its documented override-API contract and it
# is fine for callers that only want "is there something newer". The status
# surface is not such a caller: it has to report unchecked separately from up to
# date, so it must read the latest version itself.
function test_status_modules_do_not_use_compare_versions() {
  log_test_step "Testing that neither status module decides from _compare_versions"

  assert_command_fails "grep -q '_compare_versions' '$NATIVE_STATUS_MODULE'" \
    "Native status must not call _compare_versions: its error means 'current OR unreachable', and reporting the second as the first fabricates 'up to date'"

  assert_command_fails "grep -q '_compare_versions' '$CONTAINER_STATUS_MODULE'" \
    "Container status must not call _compare_versions, for the same reason"
}

function test_status_modules_report_unchecked_when_latest_is_empty() {
  log_test_step "Testing that an empty latest version drives updates_checked=false"

  local module
  for module in "$NATIVE_STATUS_MODULE" "$CONTAINER_STATUS_MODULE"; do
    # The branch that matters: latest read back empty (the remote said nothing)
    # must clear the flag rather than fall through to a comparison. Grepped in
    # the test body rather than through assert_command_succeeds, which evals the
    # string it is given and would run the command substitution in the pattern.
    local window found="no"
    window=$(grep -A 16 -F '_get_latest_version 2>/dev/null)' "$module" || true)
    if grep -q 'updates_checked="false"' <<< "$window"; then
      found="yes"
    fi

    assert_equals "yes" "$found" \
      "$(basename "$(dirname "$module")")/11-status.sh should report unchecked when no latest version came back"
  done
}

# =============================================================================
# CONTAINERS: A TAG IS NOT A VERSION
# =============================================================================

function test_container_version_module_never_yields_the_latest_tag() {
  log_test_step "Testing that the container version module no longer emits the 'latest' tag as a version"

  # The old module echoed the literal string "latest" as both the installed and
  # the available version, so every container instance compared one placeholder
  # against another and reported an update forever.
  assert_command_fails "grep -qE '^\s*echo \"latest\"' '$CONTAINER_VERSION_MODULE'" \
    "A container's version must be an image digest, never the tag it was pulled by"
}

function test_container_update_records_the_pulled_digest() {
  log_test_step "Testing that a container update records a digest, not a tag"

  local commands_module="$KGSM_ROOT/templates/manage.container.d/12-commands.sh"
  assert_file_exists "$commands_module" "Container commands module should exist"

  assert_command_fails "grep -q 'echo \"latest\" >\"\$instance_version_file\"' '$commands_module'" \
    "_update must not write the tag into the version file"

  assert_command_succeeds "grep -q '_get_local_version' '$commands_module'" \
    "_update should record the digest of the images actually pulled"
}

function test_container_installed_version_is_unknown_without_a_record() {
  log_test_step "Testing that an unrecorded container version reads as Unknown"

  local result
  result=$(run_in_version_module \
    'services:
  game:
    image: alpine:3.20' \
    '_get_installed_version')

  # "Unknown" is what makes the status surface take its unchecked branch. The
  # old module answered "latest" here, which read as a real version.
  assert_equals "Unknown" "$result" \
    "An instance with no recorded version should report Unknown, never a tag"
}

# =============================================================================
# CONTAINERS: AN UNREACHABLE REGISTRY IS AN ERROR, NOT AN ANSWER
# =============================================================================

function test_container_latest_version_fails_on_unreachable_registry() {
  log_test_step "Testing that an unreachable registry produces no version"

  if ! command -v docker >/dev/null 2>&1; then
    skip_test "docker is not installed"
    return 0
  fi

  local result exit_code
  result=$(run_in_version_module \
    'services:
  game:
    image: kgsm-nonexistent-registry.invalid/nope:1' \
    '_get_latest_version')
  exit_code=$?

  assert_not_equals "0" "$exit_code" \
    "A registry that cannot be reached should fail, never return a placeholder"
  assert_null "$result" \
    "A failed registry query must echo nothing at all"
}

function test_container_latest_version_is_a_digest() {
  log_test_step "Testing that a reachable registry yields an image digest"

  if ! command -v docker >/dev/null 2>&1; then
    skip_test "docker is not installed"
    return 0
  fi

  local result
  result=$(run_in_version_module \
    'services:
  game:
    image: alpine:3.20' \
    '_get_latest_version')

  if [[ -z "$result" ]]; then
    skip_test "the registry is not reachable from this host"
    return 0
  fi

  assert_starts_with "$result" "sha256:" \
    "A single-image instance's version should be the image digest"
}

# =============================================================================
# THE MULTI-IMAGE FINGERPRINT IS A FUNCTION OF THE SET, NOT THE ORDER
# =============================================================================

function test_fingerprint_is_order_independent() {
  log_test_step "Testing that the multi-image fingerprint ignores compose ordering"

  local forward reverse
  forward=$(run_in_version_module 'services: {}' \
    "printf '%s\n' sha256:bbbbbbbbbbbbbbbb sha256:aaaaaaaaaaaaaaaa | _fingerprint_digests")
  reverse=$(run_in_version_module 'services: {}' \
    "printf '%s\n' sha256:aaaaaaaaaaaaaaaa sha256:bbbbbbbbbbbbbbbb | _fingerprint_digests")

  assert_equals "$forward" "$reverse" \
    "The same set of images must fingerprint identically whatever order compose lists them in"
  assert_not_null "$forward" "The fingerprint should not be empty"
}

function test_fingerprint_of_one_image_is_the_bare_digest() {
  log_test_step "Testing that a single image fingerprints to its own digest"

  local result
  result=$(run_in_version_module 'services: {}' \
    "printf '%s\n' sha256:abcdef1234567890 | _fingerprint_digests")

  assert_equals "sha256:abcdef1234567890" "$result" \
    "One image should report its digest verbatim, so it stays readable and comparable by hand"
}

function test_fingerprint_of_nothing_is_a_failure() {
  log_test_step "Testing that an empty digest set produces no fingerprint"

  local result exit_code
  result=$(run_in_version_module 'services: {}' "printf '' | _fingerprint_digests")
  exit_code=$?

  assert_not_equals "0" "$exit_code" "No digests should fail rather than fingerprint nothing"
  assert_null "$result" "A failed fingerprint must echo nothing"
}
