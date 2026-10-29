#!/usr/bin/env bash

# KGSM Transfer Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/transfer.sh and the requirement functions in
# commands/handlers/blueprints.sh
#
# Covered here: which requirements a blueprint declares, how a travelling
# blueprint is renamed and renamed back, how a tree is measured, and the lock
# primitives that need no running instance.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="transfer_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/transfer.sh"

SCRATCH=""

function setup_file() {
  log_test_step "Setting up transfer logic tests"

  assert_file_exists "$HANDLER" "Transfer handler should exist"

  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_function_exists "__logic_transfer_check" "check should be exported"
  assert_function_exists "__logic_transfer_import_finish" "finish should be exported"
  assert_function_exists "__logic_blueprint_requirement_ids" "requirements should be exported"
}

function setup() {
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/kgsm-transfer-unit.XXXXXX")"
}

function teardown() {
  rm -rf "${SCRATCH:?}"
}

# =============================================================================
# REQUIREMENTS
# =============================================================================

function test_a_container_blueprint_needs_the_container_runtime() {
  log_test_step "Testing the requirements of a container blueprint"

  printf 'name: c\nruntime: container\ncontainer:\n  compose: |\n    services: {}\n' > "$SCRATCH/c.bp.yaml"

  assert_equals "container-runtime" "$(__logic_blueprint_requirement_ids "$SCRATCH/c.bp.yaml")" \
    "A container blueprint needs the container runtime"
}

function test_a_steam_blueprint_needs_steamcmd_and_maybe_credentials() {
  log_test_step "Testing the requirements of Steam blueprints"

  printf 'name: s\nruntime: native\nnative:\n  steam_app_id: 4000\n  is_steam_account_required: false\n' > "$SCRATCH/s.bp.yaml"
  assert_equals "steamcmd" "$(__logic_blueprint_requirement_ids "$SCRATCH/s.bp.yaml")" \
    "A Steam app id needs steamcmd"

  printf 'name: a\nruntime: native\nnative:\n  steam_app_id: 4000\n  is_steam_account_required: true\n' > "$SCRATCH/a.bp.yaml"
  assert_equals "steamcmd,steam-credentials" \
    "$(__logic_blueprint_requirement_ids "$SCRATCH/a.bp.yaml" | paste -sd,)" \
    "A required account also needs credentials"

  printf 'name: n\nruntime: native\nnative:\n  steam_app_id: 0\n' > "$SCRATCH/n.bp.yaml"
  assert_equals "" "$(__logic_blueprint_requirement_ids "$SCRATCH/n.bp.yaml")" \
    "A game outside Steam declares nothing"
}

function test_credentials_are_present_when_a_steam_username_is_set() {
  log_test_step "Testing the steam-credentials requirement"

  STEAM_USERNAME="someone" __logic_blueprint_requirement_present steam-credentials
  assert_equals "0" "$?" "A username in the environment satisfies the requirement"

  (
    unset STEAM_USERNAME config_STEAM_USERNAME
    __logic_blueprint_requirement_present steam-credentials
  )
  assert_equals "1" "$?" "No username anywhere leaves it missing"

  __logic_blueprint_requirement_present unknown-requirement
  assert_equals "1" "$?" "A requirement nobody defined is never present"
}

# =============================================================================
# THE TRAVELLING BLUEPRINT
# =============================================================================

function test_rendering_a_blueprint_suffixes_its_name_and_strips_it_back() {
  log_test_step "Testing that the blueprint rename round-trips byte for byte"

  printf 'schema_version: 1\nname: 7dtd\nruntime: native\nmetadata:\n  name: keep\n' > "$SCRATCH/in.bp.yaml"

  __transfer_render_blueprint "$SCRATCH/in.bp.yaml" "$SCRATCH/out.bp.yaml" add walter
  assert_file_contains "$SCRATCH/out.bp.yaml" "name: 7dtd-walter" "The top-level name takes the suffix"
  assert_file_contains "$SCRATCH/out.bp.yaml" "  name: keep" "A nested name is left alone"

  __transfer_render_blueprint "$SCRATCH/out.bp.yaml" "$SCRATCH/back.bp.yaml" strip walter
  assert_equals "$(sha256sum < "$SCRATCH/in.bp.yaml")" "$(sha256sum < "$SCRATCH/back.bp.yaml")" \
    "Stripping the suffix gives back exactly what travelled"

  printf 'name: "quoted"  # note\n' > "$SCRATCH/q.bp.yaml"
  __transfer_render_blueprint "$SCRATCH/q.bp.yaml" "$SCRATCH/q2.bp.yaml" add x
  assert_equals 'name: "quoted-x"  # note' "$(cat "$SCRATCH/q2.bp.yaml")" \
    "Quotes and trailing comments survive"
}

# =============================================================================
# MEASURING
# =============================================================================

function test_measure_counts_files_and_bytes_but_not_directories() {
  log_test_step "Testing the tree measure"

  mkdir -p "$SCRATCH/t/sub"
  printf 'abcde' > "$SCRATCH/t/a"
  printf 'xyz' > "$SCRATCH/t/sub/b"
  ln -s a "$SCRATCH/t/link"
  printf '12' > "$SCRATCH/single"

  assert_equals "8 3" "$(__transfer_measure_dirs "$SCRATCH/t")" \
    "Regular files add their bytes; a symlink counts as an entry with no bytes"
  assert_equals "10 4" "$(__transfer_measure_dirs "$SCRATCH/t" "$SCRATCH/single")" \
    "A path that is a file counts as one file"
  assert_equals "0 0" "$(__transfer_measure_dirs "$SCRATCH/absent")" \
    "A directory that is not there counts for nothing"
}

# =============================================================================
# THE LOCK TOKEN
# =============================================================================

function test_tokens_are_held_to_a_safe_alphabet() {
  log_test_step "Testing lock token validation"

  __transfer_token_valid "transfer-01.a:b@c_d"
  assert_equals "0" "$?" "Ids and account-like tokens are accepted"

  __transfer_token_valid 'a"b'
  assert_equals "1" "$?" "A quote would break the sourced config"

  __transfer_token_valid ""
  assert_equals "1" "$?" "An empty token is no token"
}
