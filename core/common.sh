#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_COMMON_LOADED:-}" ]]; then
  return 0
fi

function __load_core_module() {
  local module_name="$1"
  local module_file="$KGSM_ROOT/core/${module_name}"

  if [[ ! -f "$module_file" ]]; then
    echo "${0##*/} ERROR: Failed to locate ${module_name}" >&2
    echo "${0##*/} ERROR: File structure might be compromised" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$module_file" || {
    echo -e "ERROR: Failed to load ${module_name} core module" >&2
    exit 1
  }
}

# Module loader
__load_core_module "loader.sh"

# Error codes and definitions
__load_core_module "errors.sh"

# From this point forward, we can use the error codes defined in errors.sh
__load_core_module "delegator.sh"

# Events
__load_core_module "events.sh"

# System
__load_core_module "system.sh"

# User config.ini
__load_core_module "config.sh"

# File logging
__load_core_module "logging.sh"

# Parser
__load_core_module "parser.sh"

# Validation
__load_core_module "validation.sh"

# cgroup v2 process supervision primitives
__load_core_module "cgroup.sh"

# Node resource admission (the memory gate). After config.sh, which is what
# flattens the config_* values it reads, and after parser.sh, whose
# __get_config_value it uses to read an instance's own cap.
__load_core_module "resources.sh"

# Cleanup
unset -f __load_core_module

# Export this to check before loading this file again
declare -g KGSM_COMMON_LOADED=1
export KGSM_COMMON_LOADED
