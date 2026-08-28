#!/usr/bin/env bash

# KGSM First-Run Bootstrap Integration Tests
#
# Test Type: INTEGRATION
# Target: what core/config.sh does on a host that has never run the engine
#
# The engine creates its config, seeds a library and then runs the command it was
# given, all in one invocation. These drive kgsm.sh as a subprocess with its own
# XDG roots, because that first-run branch is skipped entirely on a sandbox that
# already carries a config — which every other test's does.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="first_run_bootstrap"

# Each test gets a host that has never run the engine: its own XDG roots, empty.
# Echoes the root; the caller reads the two paths off it.
function __virgin_host() {
  local root
  root="$(mktemp -d "${TEST_SANDBOX_DIR:-${TEST_TEMP_BASE:-/tmp}}/kgsm-first-run-XXXXXX")" || return 1
  mkdir -p "${root}/config" "${root}/data" || return 1
  echo "$root"
}

# Runs an engine against a virgin host, with no KGSM_* in its environment.
#
# Scrubbing them is what makes this a first run rather than a run inside this
# test's sandbox. The framework exports KGSM_PATHS_LOADED, and core/paths.sh
# returns on it before it reads XDG_CONFIG_HOME — so a child that inherits it
# resolves its config to the sandbox and the first-run branch never fires. The
# engine derives KGSM_ROOT from its own location when it is unset, so removing
# that one costs nothing.
function __run_engine() {
  local engine="$1" root="$2"
  shift 2

  local -a scrub=()
  local line name
  while IFS= read -r line; do
    name="${line%%=*}"
    [[ "$name" == KGSM_* ]] && scrub+=("-u" "$name")
  done < <(env)

  env "${scrub[@]}" \
    XDG_CONFIG_HOME="${root}/config" XDG_DATA_HOME="${root}/data" \
    "${engine}/kgsm.sh" "$@" 2>&1
}

function __run_on() {
  local root="$1"
  shift
  __run_engine "$KGSM_ROOT" "$root" "$@"
}

function setup_file() {
  log_test_step "Setting up first-run bootstrap integration tests"

  assert_file_exists "$KGSM_ROOT/kgsm.sh" "kgsm.sh should exist"
  assert_file_exists "$KGSM_ROOT/config.default.ini" "config.default.ini should exist"

  log_test_step "First-run bootstrap test environment validated"
}

# =============================================================================
# TEST: the first command runs, rather than reporting success for nothing
# =============================================================================

function test_first_invocation_runs_the_command_it_was_given() {
  log_test_step "Testing that the first invocation does what it was asked"

  local root
  root="$(__virgin_host)"
  assert_not_null "$root" "A virgin host should be created"

  local output
  output="$(__run_on "$root" libraries list)"
  local exit_code=$?

  assert_equals "$exit_code" "0" "The first invocation should succeed"
  # The command's own output, not just the bootstrap chatter: a run that created
  # the config and stopped would print neither of these.
  assert_contains "$output" "NAME" "The first invocation should print the library table header"
  assert_contains "$output" "default" "The first invocation should list the seeded library"

  rm -rf "$root"
}

# =============================================================================
# TEST: the config is created from the shipped defaults
# =============================================================================

function test_first_invocation_creates_the_user_config() {
  log_test_step "Testing that a user config is created from the shipped defaults"

  local root
  root="$(__virgin_host)"
  assert_not_null "$root" "A virgin host should be created"

  __run_on "$root" --version > /dev/null

  local created="${root}/config/kgsm/config.ini"
  assert_file_exists "$created" "A user config should be created on first run"
  assert_command_succeeds "grep -q '^config_schema_version=' '$created'" \
    "The created config should carry the schema version"

  rm -rf "$root"
}

# =============================================================================
# TEST: a library is registered, named, and reachable
# =============================================================================

function test_first_invocation_seeds_a_reachable_library() {
  log_test_step "Testing that the seeded library is registered, named and reachable"

  local root
  root="$(__virgin_host)"
  assert_not_null "$root" "A virgin host should be created"

  __run_on "$root" --version > /dev/null

  local registry="${root}/data/kgsm/libraries.ini"
  local marker="${root}/data/kgsm/instances/.kgsm-library"
  local created="${root}/config/kgsm/config.ini"

  assert_file_exists "$registry" "The library registry should be created"
  assert_file_contains "$registry" "[default]" "The registry should hold the default library"

  # The marker is what __logic_library_is_online reads. Registered without it,
  # the library is permanently offline and every install refuses as unreachable.
  assert_file_exists "$marker" "The library root should carry its marker"
  assert_file_contains "$marker" "name=default" "The marker should name the library"

  # The config key holds a NAME validated against the registry, so the two are
  # only correct together.
  assert_command_succeeds "grep -q '^default_library=default$' '$created'" \
    "The created config should name the seeded library as the default"

  local output
  output="$(__run_on "$root" libraries list)"
  assert_contains "$output" "online" "The seeded library should be reachable"

  rm -rf "$root"
}

# =============================================================================
# TEST: an existing registry is left alone
# =============================================================================

function test_existing_registry_is_not_reseeded() {
  log_test_step "Testing that a host which kept its data keeps its libraries"

  local root
  root="$(__virgin_host)"
  assert_not_null "$root" "A virgin host should be created"

  __run_on "$root" --version > /dev/null

  local registry="${root}/data/kgsm/libraries.ini"
  local before
  before="$(cat "$registry")"

  # A host that kept its data and lost its config.
  rm -f "${root}/config/kgsm/config.ini"
  __run_on "$root" --version > /dev/null

  assert_equals "$(cat "$registry")" "$before" \
    "An existing registry should be left exactly as it was"

  rm -rf "$root"
}

# =============================================================================
# TEST: a removed library stays removed
# =============================================================================

function test_removed_library_stays_removed() {
  log_test_step "Testing that removing the seeded library is respected"

  local root
  root="$(__virgin_host)"
  assert_not_null "$root" "A virgin host should be created"

  __run_on "$root" --version > /dev/null
  __run_on "$root" libraries remove default --force > /dev/null

  # Losing the config must not bring it back: the registry file is what says
  # this host has already been seeded.
  rm -f "${root}/config/kgsm/config.ini"
  local output
  output="$(__run_on "$root" libraries list)"

  assert_not_contains "$output" "[default]" "A removed library should not be re-seeded"
  assert_contains "$output" "No libraries registered" "The host should report no libraries"

  rm -rf "$root"
}

# =============================================================================
# TEST: a default config that names a library is left alone
# =============================================================================

function test_default_config_naming_a_library_seeds_nothing() {
  log_test_step "Testing that a stated placement intent suppresses the seed"

  local root engine
  root="$(__virgin_host)"
  assert_not_null "$root" "A virgin host should be created"

  # A shipped default that already names a library states an intent about
  # placement. Seeding `default` beside it would leave that name pointing at
  # nothing, so all three writes happen or none do.
  # An engine of its own, because the file being varied is a shipped one. tests/
  # and node_modules/ are no part of an engine and are most of its size, so the
  # copy is a few megabytes rather than tens.
  engine="${root}/engine"
  rsync -a --exclude='tests/' --exclude='node_modules/' --exclude='.git/' \
    "$KGSM_ROOT/" "${engine}/"
  sed -i 's|^default_library=$|default_library=elsewhere|' "${engine}/config.default.ini"

  __run_engine "$engine" "$root" --version > /dev/null

  assert_file_not_exists "${root}/data/kgsm/libraries.ini" \
    "No registry should be written when the default config names a library"
  assert_file_not_exists "${root}/data/kgsm/instances/.kgsm-library" \
    "No marker should be written when the default config names a library"

  rm -rf "$root"
}
