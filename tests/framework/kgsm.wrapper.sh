#!/usr/bin/env bash

#
# KGSM Testing Framework - Test Discovery Module
#
# Responsible for finding and filtering test files across all test types.
# Implements pattern matching, skip conditions, and test listing functionality.
#
# Module: tests/framework/discovery.sh
# Version: 1.0
# Date: December 19, 2025
#

# =============================================================================
# LOAD GUARD
# =============================================================================

if [[ -n "${TEST_KGSM_WRAPPER_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# PRIVATE HELPER FUNCTIONS
# =============================================================================

#
# __test_library_name()
#
# The library name a root is registered under in this sandbox. Derived from the
# root's own path so that two roots never collide on one name, and so the same
# root always resolves to the same library across calls.
#
# Arguments:
#   $1 - root (string, required): The library root
#
# Output:
#   Echoes the library name
#
function __test_library_name() {
  local root="${1%/}"

  local base="${root##*/}"
  base="${base,,}"
  base="${base//[^a-z0-9]/-}"
  [[ "$base" =~ ^[a-z0-9] ]] || base="lib-${base}"

  local hash
  hash="$(printf '%s' "$root" | cksum | cut -d' ' -f1)"

  echo "${base}-${hash}"
}

#
# __ensure_test_library()
#
# Register a root as a KGSM library, once. Placement goes through libraries, so
# a test that wants instances in a directory of its own registers it first.
#
# Arguments:
#   $1 - root (string, required): The library root
#
# Output:
#   Echoes the library name the root is registered under
#
# Return Codes:
#   0 - Success
#   1 - Failure (registration failed)
#
function __ensure_test_library() {
  local root="${1%/}"

  mkdir -p "$root" || return 1

  local name
  name="$(__test_library_name "$root")"

  # Already registered under that name: nothing to do. The marker in the root is
  # what makes a re-registration an adoption rather than a second library, and
  # the registry refuses a duplicate path outright.
  if [[ -f "${root}/.kgsm-library" ]]; then
    echo "$name"
    return 0
  fi

  "$KGSM_ROOT/kgsm.sh" libraries add "$root" --name "$name" > /dev/null 2>&1 || return 1

  echo "$name"
  return 0
}

export -f __test_library_name
export -f __ensure_test_library

#
# __setup_instance_prereqs()
#
# Setup instance prerequisites (working directory + symlink) before instance creation.
# This mirrors the setup that install.sh performs before calling instances.sh create.
#
# Arguments:
#   $1 - blueprint (string, required): The blueprint name
#   $2 - instance_name (string, required): The instance name
#   $3 - install_dir (string, required): The library root
#
# Output:
#   None
#
# Return Codes:
#   0 - Success
#   1 - Failure (directory creation or symlink failed)
#
function __setup_instance_prereqs() {
  local blueprint="$1"
  local instance_name="$2"
  local install_dir="$3"

  __ensure_test_library "$install_dir" > /dev/null || return 1

  local working_dir="$install_dir/instances/$blueprint/$instance_name"

  # Create working directory
  mkdir -p "$working_dir" || return 1

  # Create blueprint directory in instances
  mkdir -p "$KGSM_INSTANCES_DIR/$blueprint" || return 1

  # Create symlink from instances dir to working dir
  ln -s "$working_dir" "$KGSM_INSTANCES_DIR/$blueprint/$instance_name" || return 1

  return 0
}

#
# __cleanup_instance()
#
# Cleanup instance structures (symlink + working dir + blueprint dir if empty).
#
# Arguments:
#   $1 - blueprint (string, required): The blueprint name
#   $2 - instance_name (string, required): The instance name
#   $3 - install_dir (string, required): The library root
#
# Output:
#   None
#
# Return Codes:
#   0 - Always succeeds (uses || true for all operations)
#
function __cleanup_instance() {
  local blueprint="$1"
  local instance_name="$2"
  local install_dir="$3"

  # Remove symlink
  rm -f "${KGSM_INSTANCES_DIR:?}/${blueprint:?}/$instance_name" 2>/dev/null || true

  # Remove blueprint directory if empty
  rmdir "${KGSM_INSTANCES_DIR:?}/${blueprint:?}" 2>/dev/null || true

  # Remove working directory
  rm -rf "${install_dir:?}/instances/${blueprint:?}/$instance_name" 2>/dev/null || true

  # Remove blueprint install dir if empty
  rmdir "${install_dir:?}/instances/${blueprint:?}" 2>/dev/null || true

  return 0
}

# =============================================================================
# PUBLIC FUNCTIONS
# =============================================================================

#
# create_test_instance()
#
# Create a temporary KGSM instance for testing with proper prerequisite setup.
# This function mimics the full instance creation workflow from install.sh:
#   1. Generate instance name (if not provided)
#   2. Create working directory
#   3. Create symlink from instances to working directory
#   4. Create instance config
#
# Arguments:
#   $1 - blueprint (string, required): The blueprint to use for the instance
#   $2 - instance_name (string, optional): Name for the instance; auto-generated if omitted
#   $3 - install_dir (string, optional): Library root; defaults to TEST_INSTALL_DIR or TEST_SANDBOX_INSTANCES_INSTALL_DIR
#
# Output:
#   Echoes the instance name (either provided or generated) to stdout
#
# Return Codes:
#   0 - Success
#   1 - Failure (prerequisite setup or instance creation failed)
#
function create_test_instance() {
  local blueprint="$1"
  local instance_name="$2"
  local install_dir="${3:-${TEST_INSTALL_DIR:-$TEST_SANDBOX_INSTANCES_INSTALL_DIR}}"

  # Generate instance name if not provided
  if [[ -z "$instance_name" ]]; then
    instance_name=$("$KGSM_MAIN_SCRIPT" instances generate-id "$blueprint") || return 1
  fi

  # Setup prerequisites (library registration + working dir + symlink)
  __setup_instance_prereqs "$blueprint" "$instance_name" "$install_dir" || return 1

  local library
  library="$(__test_library_name "$install_dir")"

  local generated_instance_name

  # Create instance config
  generated_instance_name=$("$KGSM_ROOT/kgsm.sh" instances create "$blueprint" --name "$instance_name" --library "$library" 2>/dev/null) || return 1

  # Create instance management script
  "$KGSM_ROOT/kgsm.sh" files management create "$instance_name" 1>/dev/null 2>&1 || return 1

  echo "$generated_instance_name"
}

export -f create_test_instance

#
# remove_test_instance()
#
# Remove a temporary KGSM instance used for testing with complete cleanup.
# This function performs:
#   1. Remove instance config
#   2. Remove symlink from instances directory
#   3. Remove working directory
#   4. Remove empty parent directories
#
# Arguments:
#   $1 - blueprint (string, required): The blueprint name
#   $2 - instance_name (string, required): Name of the instance to remove
#   $3 - install_dir (string, optional): Library root; defaults to TEST_INSTALL_DIR or TEST_SANDBOX_INSTANCES_INSTALL_DIR
#
# Output:
#   None
#
# Return Codes:
#   0 - Success
#   1 - Failure (instance removal failed)
#
function remove_test_instance() {
  local blueprint="$1"
  local instance_name="$2"
  local install_dir="${3:-${TEST_INSTALL_DIR:-$TEST_SANDBOX_INSTANCES_INSTALL_DIR}}"

  # Remove instance config
  "$KGSM_ROOT/kgsm.sh" instances remove "$instance_name" || return 1

  # Cleanup directory structures
  __cleanup_instance "$blueprint" "$instance_name" "$install_dir"

  return 0
}

export -f remove_test_instance

#
# setup_instance_prereqs()
#
# Public wrapper for manual prerequisite setup. Use this when you need fine-grained
# control over instance creation steps (e.g., for testing edge cases).
#
# Arguments:
#   $1 - blueprint (string, required): The blueprint name
#   $2 - instance_name (string, required): The instance name
#   $3 - install_dir (string, optional): Library root; defaults to TEST_INSTALL_DIR or TEST_SANDBOX_INSTANCES_INSTALL_DIR
#
# Output:
#   None
#
# Return Codes:
#   0 - Success
#   1 - Failure (directory creation or symlink failed)
#
function setup_instance_prereqs() {
  local blueprint="$1"
  local instance_name="$2"
  local install_dir="${3:-${TEST_INSTALL_DIR:-$TEST_SANDBOX_INSTANCES_INSTALL_DIR}}"

  __setup_instance_prereqs "$blueprint" "$instance_name" "$install_dir"
  return $?
}

export -f setup_instance_prereqs

#
# generate_test_id()
#
# Generate a unique test instance ID based on a blueprint.
#
# Arguments:
#   $1 - blueprint (string, optional): The blueprint to base the ID on
#
# Output:
#   Writes generated instance ID to stdout (single line)
#
# Return Codes:
#   0 - Success
#   1 - Failure
#
function generate_test_id() {
  local blueprint="${1:-test_blueprint}"

  "$KGSM_ROOT/kgsm.sh" instances generate-id "$blueprint"
  return $?
}

export -f generate_test_id

declare -g TEST_KGSM_WRAPPER_LOADED=1
export TEST_KGSM_WRAPPER_LOADED
