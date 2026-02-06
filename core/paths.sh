#!/usr/bin/env bash

# KGSM Path Configuration
# Implements XDG Base Directory Specification
# shellcheck disable=SC2086

if [[ -n "${KGSM_PATHS_LOADED:-}" ]]; then
  return 0
fi

# ============================================================================
# SYSTEM PATHS (Read-only, package-managed)
# ============================================================================

export KGSM_CORE_DIR="${KGSM_ROOT}/core"
export KGSM_COMMANDS_DIR="${KGSM_ROOT}/commands"
export KGSM_HANDLERS_DIR="${KGSM_ROOT}/commands/handlers"
export KGSM_TEMPLATES_DIR="${KGSM_ROOT}/templates"
export KGSM_MIGRATIONS_DIR="${KGSM_ROOT}/migrations"

export KGSM_SYSTEM_BLUEPRINTS_DIR="${KGSM_ROOT}/blueprints"
export KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR="${KGSM_SYSTEM_BLUEPRINTS_DIR}/native/default"
export KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR="${KGSM_SYSTEM_BLUEPRINTS_DIR}/container/default"

export KGSM_SYSTEM_OVERRIDES_DIR="${KGSM_ROOT}/overrides"

export KGSM_DEFAULT_CONFIG_FILE="${KGSM_ROOT}/config.default.ini"

# ============================================================================
# USER PATHS (Writable, XDG-compliant)
# ============================================================================

export KGSM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kgsm"
export KGSM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kgsm"

export KGSM_CONFIG_FILE="${KGSM_CONFIG_DIR}/config.ini"

export KGSM_INSTANCES_DIR="${KGSM_DATA_DIR}/instances"
export KGSM_LOGS_DIR="${KGSM_DATA_DIR}/logs"

export KGSM_USER_BLUEPRINTS_DIR="${KGSM_DATA_DIR}/blueprints"
export KGSM_USER_BLUEPRINTS_NATIVE_DIR="${KGSM_USER_BLUEPRINTS_DIR}/native"
export KGSM_USER_BLUEPRINTS_CONTAINER_DIR="${KGSM_USER_BLUEPRINTS_DIR}/container"

export KGSM_USER_OVERRIDES_DIR="${KGSM_DATA_DIR}/overrides"

# ============================================================================
# INITIALIZATION
# ============================================================================

function __init_user_directories() {
  local dirs=(
    "$KGSM_CONFIG_DIR"
    "$KGSM_DATA_DIR"
    "$KGSM_INSTANCES_DIR"
    "$KGSM_LOGS_DIR"
    "$KGSM_USER_BLUEPRINTS_DIR"
    "$KGSM_USER_BLUEPRINTS_NATIVE_DIR"
    "$KGSM_USER_BLUEPRINTS_CONTAINER_DIR"
    "$KGSM_USER_OVERRIDES_DIR"
  )

  for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir" || {
        echo "ERROR: Failed to create directory: $dir" >&2
        return 1
      }
    fi
  done

  return 0
}

export -f __init_user_directories

# ============================================================================
# LEGACY COMPATIBILITY ALIASES
# ============================================================================

export BLUEPRINTS_SOURCE_DIR="$KGSM_SYSTEM_BLUEPRINTS_DIR"
export BLUEPRINTS_NATIVE_DIR="${KGSM_ROOT}/blueprints/native"
export BLUEPRINTS_CONTAINER_DIR="${KGSM_ROOT}/blueprints/container"
export BLUEPRINTS_NATIVE_DEFAULT_DIR="$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR"
export BLUEPRINTS_NATIVE_CUSTOM_DIR="$KGSM_USER_BLUEPRINTS_NATIVE_DIR"
export BLUEPRINTS_CONTAINER_DEFAULT_DIR="$KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR"
export BLUEPRINTS_CONTAINER_CUSTOM_DIR="$KGSM_USER_BLUEPRINTS_CONTAINER_DIR"
export OVERRIDES_SOURCE_DIR="$KGSM_SYSTEM_OVERRIDES_DIR"
export TEMPLATES_SOURCE_DIR="$KGSM_TEMPLATES_DIR"
export COMMANDS_SOURCE_DIR="$KGSM_COMMANDS_DIR"
export COMMAND_HANDLERS_SOURCE_DIR="$KGSM_HANDLERS_DIR"
export CORE_SOURCE_DIR="$KGSM_CORE_DIR"
export INSTANCES_SOURCE_DIR="$KGSM_INSTANCES_DIR"

declare -g KGSM_PATHS_LOADED=1
export KGSM_PATHS_LOADED
