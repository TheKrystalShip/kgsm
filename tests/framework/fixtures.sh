#!/usr/bin/env bash

# KGSM Test Framework - Test Fixtures
#
# Author: The Krystal Ship Team
# Version: 1.0
#
# Reusable test data creation helpers for KGSM tests.
# This module provides functions to create mock configs, blueprints,
# override files, and management scripts for testing purposes.

# =============================================================================
# INSTANCE CONFIG FIXTURES
# =============================================================================

# Create a mock instance config file
# Args: $1 = instance_name, $2 = blueprint_file_path
# Returns: Echoes the path to the created config file
function create_mock_instance_config() {
  local instance_name="$1"
  local blueprint_file_path="$2"

  if [[ -z "$instance_name" || -z "$blueprint_file_path" ]]; then
    echo "ERROR: create_mock_instance_config requires instance_name and blueprint_file_path" >&2
    return 1
  fi

  # Extract blueprint name from the blueprint file's 'name' field
  local blueprint_name
  blueprint_name=$(__get_config_value "$blueprint_file_path" "name" 2>/dev/null)

  if [[ -z "$blueprint_name" ]]; then
    echo "ERROR: Could not extract blueprint name from $blueprint_file_path" >&2
    return 1
  fi

  # Create instance directory structure
  local instance_dir="$KGSM_ROOT/instances/$blueprint_name"
  mkdir -p "$instance_dir"

  # Create instance config file
  local config_file="$instance_dir/${instance_name}.ini"

  cat > "$config_file" << EOF
# KGSM Instance Configuration
# Auto-generated for testing

name=$instance_name
blueprint_file=$blueprint_file_path
blueprint_name=$blueprint_name
type=native
created=$(date '+%Y-%m-%d %H:%M:%S')
EOF

  log_debug "Created mock instance config: $config_file" 3
  echo "$config_file"
}

export -f create_mock_instance_config

# =============================================================================
# OVERRIDE FILE FIXTURES
# =============================================================================

# Create a mock override file with specified functions
# Args: $1 = blueprint_name, $2+ = function_names (space-separated or array)
# Returns: Echoes the path to the created override file
function create_mock_override_file() {
  local blueprint_name="$1"
  shift
  local function_names=("$@")

  if [[ -z "$blueprint_name" ]]; then
    echo "ERROR: create_mock_override_file requires blueprint_name" >&2
    return 1
  fi

  if [[ ${#function_names[@]} -eq 0 ]]; then
    echo "ERROR: create_mock_override_file requires at least one function name" >&2
    return 1
  fi

  # Create override file
  local override_file="$OVERRIDES_SOURCE_DIR/${blueprint_name}.overrides.sh"

  cat > "$override_file" << 'EOF'
#!/usr/bin/env bash

# Mock override file for testing
# Auto-generated

EOF

  # Add each function
  for func_name in "${function_names[@]}"; do
    cat >> "$override_file" << EOF
function ${func_name}() {
  echo "Mock ${func_name} implementation"
  return 0
}

EOF
  done

  chmod +x "$override_file"

  log_debug "Created mock override file: $override_file with functions: ${function_names[*]}" 3
  echo "$override_file"
}

export -f create_mock_override_file

# =============================================================================
# MANAGEMENT SCRIPT FIXTURES
# =============================================================================

# Create a mock management script with placeholder functions
# Args: $1 = script_path, $2+ = function_names (space-separated or array)
# Returns: Echoes the path to the created script
function create_mock_management_script() {
  local script_path="$1"
  shift
  local function_names=("$@")

  if [[ -z "$script_path" ]]; then
    echo "ERROR: create_mock_management_script requires script_path" >&2
    return 1
  fi

  if [[ ${#function_names[@]} -eq 0 ]]; then
    echo "ERROR: create_mock_management_script requires at least one function name" >&2
    return 1
  fi

  # Create parent directory if needed
  mkdir -p "$(dirname "$script_path")"

  # Create management script with placeholder functions
  cat > "$script_path" << 'EOF'
#!/usr/bin/env bash

# Mock management script for testing
# Auto-generated

EOF

  # Add each placeholder function
  for func_name in "${function_names[@]}"; do
    cat >> "$script_path" << EOF
function ${func_name}() {
  echo "Placeholder ${func_name}"
  return 1
}

EOF
  done

  chmod +x "$script_path"

  log_debug "Created mock management script: $script_path with functions: ${function_names[*]}" 3
  echo "$script_path"
}

export -f create_mock_management_script

# =============================================================================
# BLUEPRINT FIXTURES
# =============================================================================

# Create a minimal mock blueprint file
# Args: $1 = blueprint_name, $2 = blueprint_type (native|container)
# Returns: Echoes the path to the created blueprint file
function create_mock_blueprint() {
  local blueprint_name="$1"
  local blueprint_type="${2:-native}"

  if [[ -z "$blueprint_name" ]]; then
    echo "ERROR: create_mock_blueprint requires blueprint_name" >&2
    return 1
  fi

  local blueprint_dir
  if [[ "$blueprint_type" == "container" ]]; then
    blueprint_dir="$KGSM_ROOT/blueprints/container/custom"
    local blueprint_file="$blueprint_dir/${blueprint_name}.docker-compose.yml"

    mkdir -p "$blueprint_dir"

    cat > "$blueprint_file" << EOF
# Mock Docker Compose Blueprint
version: '3'
services:
  ${blueprint_name}:
    image: mock/${blueprint_name}:latest
    container_name: ${blueprint_name}
EOF

  else
    blueprint_dir="$KGSM_ROOT/blueprints/native/custom"
    local blueprint_file="$blueprint_dir/${blueprint_name}.bp"

    mkdir -p "$blueprint_dir"

    cat > "$blueprint_file" << EOF
# Mock KGSM Blueprint
name=${blueprint_name}
ports='27015'
steam_app_id=0
is_steam_account_required=false
executable_file=mock.sh
executable_arguments=""
level_name=world
EOF

  fi

  log_debug "Created mock blueprint: $blueprint_file" 3
  echo "$blueprint_file"
}

export -f create_mock_blueprint

# =============================================================================
# CLEANUP UTILITIES
# =============================================================================

# Clean up mock files and directories
# Args: $@ = file/directory paths to remove
function cleanup_mock_files() {
  local paths=("$@")

  for path in "${paths[@]}"; do
    if [[ -e "$path" ]]; then
      rm -rf "$path"
      log_debug "Cleaned up mock file/directory: $path" 3
    fi
  done
}

export -f cleanup_mock_files

# Mark module as loaded
export KGSM_TEST_FIXTURES_LOADED=1
