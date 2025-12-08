#!/usr/bin/env bash

# KGSM Pure Logic Layer - Template Management
#
# This module provides centralized template handling functionality for KGSM.
# All template discovery, expansion, and validation operations should use these functions.
#
# Exit Code Conventions:
# - 0: Success
# - EC_INVALID_ARG: Invalid arguments provided
# - EC_FILE_NOT_FOUND: Template file not found
# - EC_FAILED_TEMPLATE: Template expansion failed

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Find a template file by name
# Args: $1 = template_name (with or without .tp extension)
# Returns: 0 on success, EC_FILE_NOT_FOUND if template doesn't exist
# Outputs: Full path to template file on stdout (only on success)
function __logic_find_template() {
  local template_name="$1"

  if [[ -z "$template_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Add .tp extension if not present
  if [[ "$template_name" != *.tp ]]; then
    template_name="${template_name}.tp"
  fi

  # Use existing __find_template from loader
  local template_file
  template_file=$(__find_template "$template_name" 2> /dev/null)

  if [[ ! -f "$template_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  echo "$template_file"
  return 0
}

export -f __logic_find_template

# Check if a template exists
# Args: $1 = template_name (with or without .tp extension)
# Returns: 0 if exists, 1 if not found
function __logic_template_exists() {
  local template_name="$1"

  if [[ -z "$template_name" ]]; then
    return 1
  fi

  __logic_find_template "$template_name" &> /dev/null
  return $?
}

export -f __logic_template_exists

# Expand a template file with current environment variables
# Args: $1 = template_name (without .tp extension), $2 = output_file
# Returns: 0 on success, error code on failure
function __logic_expand_template() {
  local template_name="$1"
  local output_file="$2"

  # Validate input
  if [[ -z "$template_name" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -z "$output_file" ]]; then
    return $EC_INVALID_ARG
  fi

  # Find template file
  local template_file
  template_file=$(__logic_find_template "$template_name" 2> /dev/null)

  if [[ -z "$template_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Expand template using bash's built-in heredoc expansion
  # This allows variable substitution from the current environment
  if ! eval "cat <<EOF
$(< "$template_file")
EOF
" > "$output_file" 2> /dev/null; then
    return $EC_FAILED_TEMPLATE
  fi

  return 0
}

export -f __logic_expand_template

# Expand a template with explicit variable map
# Args: $1 = template_name, $2 = output_file, $3+ = VAR=value pairs
# Returns: 0 on success, error code on failure
# Example: __logic_expand_template_with_vars "mytemplate" "output.txt" "NAME=test" "PORT=8080"
function __logic_expand_template_with_vars() {
  local template_name="$1"
  local output_file="$2"
  shift 2

  if [[ -z "$template_name" ]] || [[ -z "$output_file" ]]; then
    return $EC_INVALID_ARG
  fi

  # Find template file
  local template_file
  template_file=$(__logic_find_template "$template_name" 2> /dev/null)

  if [[ -z "$template_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Create temporary script to evaluate template in isolated environment
  local tmp_script
  tmp_script=$(mktemp)

  # Export provided variables
  for var_pair in "$@"; do
    if [[ "$var_pair" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      echo "export ${BASH_REMATCH[1]}='${BASH_REMATCH[2]}'" >> "$tmp_script"
    fi
  done

  # Add template expansion command
  cat >> "$tmp_script" << 'SCRIPT_EOF'
eval "cat <<EOF
$(<"$TEMPLATE_FILE")
EOF
"
SCRIPT_EOF

  # Execute in subshell with template file path
  if ! TEMPLATE_FILE="$template_file" bash "$tmp_script" > "$output_file" 2> /dev/null; then
    rm -f "$tmp_script"
    return $EC_FAILED_TEMPLATE
  fi

  rm -f "$tmp_script"
  return 0
}

export -f __logic_expand_template_with_vars

# Validate that a template contains required variables
# Args: $1 = template_name, $2+ = required variable names
# Returns: 0 if all variables present, 1 if any missing
# Outputs: Missing variable names to stderr
function __logic_validate_template_vars() {
  local template_name="$1"
  shift

  if [[ -z "$template_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Find template file
  local template_file
  template_file=$(__logic_find_template "$template_name" 2> /dev/null)

  if [[ -z "$template_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  local missing_vars=()
  local template_content
  template_content=$(< "$template_file")

  # Check each required variable
  for var_name in "$@"; do
    # Look for variable references: $VAR or ${VAR}
    if ! grep -qE "\\\$\{?${var_name}\}?" <<< "$template_content"; then
      missing_vars+=("$var_name")
    fi
  done

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    printf "Missing variables in template '%s': %s\n" "$template_name" "${missing_vars[*]}" >&2
    return 1
  fi

  return 0
}

export -f __logic_validate_template_vars

# Get template content without expansion (raw content)
# Args: $1 = template_name
# Returns: 0 on success, error code on failure
# Outputs: Template content to stdout
function __logic_get_template_content() {
  local template_name="$1"

  if [[ -z "$template_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local template_file
  template_file=$(__logic_find_template "$template_name" 2> /dev/null)

  if [[ -z "$template_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  cat "$template_file"
  return 0
}

export -f __logic_get_template_content

# List all available templates
# Args: None
# Returns: 0 on success
# Outputs: Template names (without .tp extension) to stdout, one per line
function __logic_list_templates() {
  local templates_dir="${KGSM_ROOT}/templates"

  if [[ ! -d "$templates_dir" ]]; then
    return $EC_DIR_NOT_FOUND
  fi

  find "$templates_dir" -name "*.tp" -type f -exec basename {} .tp \; 2> /dev/null | sort
  return 0
}

export -f __logic_list_templates

# Mark module as loaded
export KGSM_LOGIC_TEMPLATES_LOADED=1
