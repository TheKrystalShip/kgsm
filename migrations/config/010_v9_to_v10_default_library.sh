#!/usr/bin/env bash
# Migration: 010 - Instance placement moves from one path to named libraries
# From schema: 9 ([resources] and the memory gate)
# To schema: 10 ([instance_defaults] carries default_library)
#
# A library is a named root that instances are placed in: registered with
# `kgsm libraries add`, carrying a `.kgsm-library` marker, enumerable with its
# free space. `default_library` names this host's default one; empty is legal,
# and with exactly one library registered that one is the default anyway.
#
# The path a host had in `default_install_directory` becomes the library
# `default`, so the root its instances already live in is carried across as a
# named, enumerable thing rather than lost with the key. The registry entry is
# written whether or not the path is reachable — an unmounted disk is still a
# library this host knows about — while the marker is written only when the root
# is there to write it into, so a library whose disk is absent reports offline
# rather than being invented into existence.
#
# Idempotent: a config that already carries default_library is only bumped to v10,
# and re-registering a path the registry already holds is a no-op.

# Disabling SC2086 globally
# shellcheck disable=SC2086

# Source bootstrap if available (for error codes and print functions)
if [[ -n "$KGSM_ROOT" ]] && [[ -f "$KGSM_ROOT/core/bootstrap.sh" ]]; then
  source "$KGSM_ROOT/core/bootstrap.sh"
else
  # Fallback print functions if bootstrap not available
  __print_info() { echo "INFO: $*"; }
  __print_warning() { echo "WARNING: $*" >&2; }
  __print_error() { echo "ERROR: $*" >&2; }
  __print_success() { echo "SUCCESS: $*"; }
fi

function migrate() {
  local config_file="$1"

  if [[ -z "$config_file" ]]; then
    __print_error "Config file path must be provided"
    return 1
  fi

  if [[ ! -f "$config_file" ]]; then
    __print_error "Config file not found: $config_file"
    return 1
  fi

  if grep -qE '^[[:space:]]*default_library=' "$config_file"; then
    __print_info "default_library already present, nothing to add"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v9 to v10 (instance placement through libraries)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v10.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  # The path this host has been installing into, before the key that held it is
  # removed below.
  local install_directory
  install_directory="$(grep -m 1 -E '^[[:space:]]*default_install_directory=' "$config_file" | cut -d= -f2-)"
  install_directory="${install_directory%\"}"
  install_directory="${install_directory#\"}"

  local library_name=""
  if [[ -n "$install_directory" ]]; then
    if __register_default_library "$install_directory"; then
      library_name="default"
    else
      __print_warning "Could not register $install_directory as a library"
      __print_warning "Register a library by hand: kgsm libraries add <path>"
    fi
  fi

  if ! __add_default_library "$config_file" "$library_name"; then
    __print_error "Failed to add default_library"
    mv "${config_file}.pre-migration-v10.bak" "$config_file"
    return 1
  fi

  if ! __remove_default_install_directory "$config_file"; then
    __print_error "Failed to remove default_install_directory"
    mv "${config_file}.pre-migration-v10.bak" "$config_file"
    return 1
  fi

  # Bump the schema version in place
  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v10.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v10 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v10.bak"
  return 0
}

# Registers a path as the library `default`.
#
# The registry is written directly rather than through `kgsm libraries add`: a
# migration runs while the config is half-way between two schemas, and the CLI
# loads that config on every invocation.
#
# Args: $1 = the path to register
# Returns: 0 when the registry holds a `default` library at that path afterwards
function __register_default_library() {
  local path="$1"

  local data_dir="${KGSM_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/kgsm}"
  local registry="${data_dir}/libraries.ini"

  if grep -q '^\[default\]$' "$registry" 2> /dev/null; then
    __print_info "Library 'default' is already registered"
    return 0
  fi

  local id
  id="$(od -An -tx1 -N8 /dev/urandom 2> /dev/null | tr -d ' \n')"
  if [[ ${#id} -ne 16 ]]; then
    return 1
  fi

  # The canonical path when the root is there, the configured one when it is not:
  # a library whose disk is absent is still a library, and refusing to record it
  # would lose the only note of where this host's instances live.
  local canonical
  canonical="$(realpath -e "$path" 2> /dev/null)" || canonical="$path"

  if [[ ! -d "$data_dir" ]] && ! mkdir -p "$data_dir" 2> /dev/null; then
    return 1
  fi

  if ! printf '[default]\nid=%s\npath=%s\n\n' "$id" "$canonical" >> "$registry" 2> /dev/null; then
    return 1
  fi

  if [[ -d "$canonical" ]] && [[ -w "$canonical" ]]; then
    if printf 'id=%s\nname=default\n' "$id" > "${canonical}/.kgsm-library" 2> /dev/null; then
      __print_info "Registered library 'default' at $canonical"
      return 0
    fi
  fi

  __print_warning "Library 'default' is registered at $canonical but its marker could not be written"
  __print_warning "It reports offline until the root is reachable and writable"
  return 0
}

# Append the documented key to [instance_defaults], creating the section when a
# config predates it. Appending to the end of the section is enough: the loader
# flattens keys per section, and order within a section carries no meaning.
# Args: $1 = config file, $2 = the value to give default_library
function __add_default_library() {
  local config_file="$1"
  local value="$2"

  local block
  block=$(
    cat <<'EOF'

# DEFAULT LIBRARY
# Which library is this host's default for new game server instances?
# A library is a named root registered with `kgsm libraries add <path>`;
# `kgsm libraries list` shows the registered ones with their free space.
# With exactly one library registered, that one is the default even when this
# key is empty.
#
# Expected values:
#   The name of a registered library (leave empty to choose per instance)
#
# Default: Empty
EOF
  )
  block="${block}
default_library=${value}"

  if ! grep -q '^\[instance_defaults\]' "$config_file"; then
    printf '\n[instance_defaults]\n%s\n' "$block" >> "$config_file"
    return $?
  fi

  # Insert at the end of [instance_defaults] — just before the next section
  # header, or at end-of-file when it is the last section.
  local next_section_line
  next_section_line=$(awk '
    /^\[instance_defaults\]/ { found = 1; next }
    found && /^\[/ { print NR; exit }
  ' "$config_file")

  if [[ -z "$next_section_line" ]]; then
    printf '%s\n' "$block" >> "$config_file"
    return $?
  fi

  local tmp
  tmp=$(mktemp) || return 1
  {
    head -n "$((next_section_line - 1))" "$config_file"
    printf '%s\n' "$block"
    tail -n "+${next_section_line}" "$config_file"
  } > "$tmp" || {
    rm -f "$tmp"
    return 1
  }

  mv "$tmp" "$config_file"
}

# Removes the key and the comment block documenting it. The key is removed
# rather than commented out: a path left in the file invites an operator to set
# it and expect instances to go there.
function __remove_default_install_directory() {
  local config_file="$1"

  local tmp
  tmp=$(mktemp) || return 1

  awk '
    # The documentation block opens with this heading and runs, comment line by
    # comment line, to the key it documents.
    /^# DEFAULT INSTALLATION DIRECTORY$/ { skipping = 1; next }
    skipping {
      if ($0 ~ /^[[:space:]]*default_install_directory=/) { skipping = 0; next }
      if ($0 ~ /^[[:space:]]*#/) { next }
      # Anything else means the block is not shaped the way it is documented.
      # Stop skipping and keep the line, so a reworded config loses the key and
      # nothing else.
      skipping = 0
    }
    /^[[:space:]]*default_install_directory=/ { next }
    { print }
  ' "$config_file" > "$tmp" || {
    rm -f "$tmp"
    return 1
  }

  mv "$tmp" "$config_file"
}

# Set config_schema_version to 10 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=10/' "$config_file"
  else
    sed -i '1i config_schema_version=10' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
