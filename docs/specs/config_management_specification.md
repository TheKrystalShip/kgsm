# KGSM Configuration Management Specification

**Version**: 1.0  
**Date**: December 16, 2025  
**Status**: Draft  
**Target Release**: KGSM v3.0

---

## Table of Contents

1. [Overview](#overview)
2. [Design Goals](#design-goals)
3. [Schema Versioning System](#schema-versioning-system)
4. [INI Section Format](#ini-section-format)
5. [Configuration Parsing](#configuration-parsing)
6. [Merge Algorithm](#merge-algorithm)
7. [Deprecated Key Handling](#deprecated-key-handling)
8. [Validation System](#validation-system)
9. [Backup and Rollback Strategy](#backup-and-rollback-strategy)
10. [Migration Framework](#migration-framework)
11. [API Reference](#api-reference)
12. [Command-Line Interface](#command-line-interface)
13. [Testing Requirements](#testing-requirements)
14. [Implementation Phases](#implementation-phases)

---

## Overview

KGSM v3.0 introduces a comprehensive configuration management system that enables graceful updates without overwriting user customizations. The system is based on industry-standard patterns used by PostgreSQL, Docker Compose, and systemd.

### Problem Statement

Previous KGSM versions faced challenges when updating:
- New configuration keys were not added to user configs automatically
- User customizations could be lost during updates
- No mechanism for handling breaking configuration changes
- No validation of configuration completeness or correctness

### Solution

Implement a **schema-versioned configuration system** with:
- Automatic merging of new keys from default config
- Preservation of user-customized values
- Migration framework for breaking changes
- Validation and rollback capabilities
- Sectioned INI format for better organization

---

## Design Goals

1. **Automatic Updates**: New configuration keys added automatically without user intervention
2. **Preserve User Intent**: Never overwrite user-customized values
3. **Handle Breaking Changes**: Migration system for configuration schema evolution
4. **Safety First**: Validation before applying, backups before modifying, rollback on failure
5. **Clear Communication**: Users informed about deprecated keys and required actions
6. **Testable**: All migrations and merge logic covered by automated tests
7. **Backward Compatibility**: None required for v3.0 (major version), mandatory for future updates

---

## Schema Versioning System

### Version Field

Every configuration file includes a schema version number:

```ini
config_schema_version=1
```

- **Location**: First non-comment line of configuration file
- **Format**: Positive integer (1, 2, 3, ...)
- **Semantics**: Schema version increments when configuration structure changes
- **Immutability**: Once set in user config, only changed by migrations

### Version Comparison

```bash
# Get current schema version from default config
CURRENT_SCHEMA_VERSION=1  # Defined in config.default.ini

# Get user's schema version
user_schema=$(__get_config_value "$CONFIG_FILE" "config_schema_version")

# Trigger migrations if needed
if [[ "$user_schema" -lt "$CURRENT_SCHEMA_VERSION" ]]; then
  __run_config_migrations "$user_schema" "$CURRENT_SCHEMA_VERSION"
fi
```

### When to Increment Schema Version

Schema version increments when:
- **Section structure changes** (new section added/removed)
- **Key renamed** (old key must be migrated to new key)
- **Value format changes** (e.g., `ports="8080"` → `ports="8080/tcp"`)
- **Required keys added** (keys that must exist for KGSM to function)
- **Keys removed permanently** (after deprecation period)

Schema version does NOT increment when:
- **New optional keys added** (can be merged automatically)
- **Default values change** (user values preserved anyway)
- **Documentation/comments updated**
- **Key order changes**

---

## INI Section Format

### Section Definitions

KGSM v3.0 uses 8 predefined sections matching the logical organization of config.default.ini:

```ini
config_schema_version=1

[system]
# Core KGSM settings: updates, logging, timeouts

[network]
# Network-related settings: firewall, port forwarding

[steam]
# Steam integration credentials

[services]
# Service management: systemd integration

[instance_defaults]
# Default settings for new game server instances

[events]
# Event broadcasting and webhooks

[watchers]
# Watcher process configuration

[accessibility]
# Command shortcuts and convenience features
```

### Section Naming Rules

- **Lowercase**: All section names use lowercase
- **Underscores**: Use underscores for multi-word sections (e.g., `instance_defaults`)
- **No spaces**: Section names are bash-friendly identifiers
- **Descriptive**: Name indicates content category
- **Stable**: Section names should rarely change (requires migration)

### Key Naming Within Sections

Keys maintain current flat naming convention:

```ini
[system]
update_channel=main
enable_logging=false

[network]
enable_firewall_management=false
```

**Important**: Variables are still exported as `config_update_channel`, `config_enable_logging`, etc. The section is only for file organization, not for variable namespacing.

### Comment Block Structure

Each key should have a documentation block:

```ini
# KEY NAME
# Description of what this setting does and when to use it.
# Additional context and examples.
#
# Dependencies: required-tool (if applicable)
#
# Expected values:
#   value1  - Description
#   value2  - Description
#
# Default: value
key_name=value
```

---

## Configuration Parsing

### Parser Requirements

The configuration parser must:
1. **Handle sections**: Track current section while parsing
2. **Preserve flat export**: Still export variables as `config_*` (no section prefix)
3. **Skip comments**: Ignore lines starting with `#` or `;`
4. **Trim whitespace**: Remove leading/trailing spaces from keys and values
5. **Validate keys**: Ensure key names are valid bash identifiers
6. **Handle empty values**: Allow `key=` (empty string)
7. **Support quotes**: Parse quoted values: `key="value with spaces"`

### Parsing Algorithm

```bash
function __parse_config_file() {
  local config_file="$1"
  local current_section=""
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Detect section headers
    if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi
    
    # Parse key=value
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      
      # Trim whitespace
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      
      # Remove quotes
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"
      
      # Export as config_* variable
      declare -g "config_${key}=${value}"
      export "config_${key}"
      
      # Optionally track section for merge operations
      declare -g "_config_section_${key}=${current_section}"
    fi
  done < "$config_file"
}
```

### Backward Compatibility

KGSM v3.0 does **not** require backward compatibility with pre-v3.0 configs. Users must migrate to the new format.

Future versions (v3.1+) should support both flat and sectioned formats during a transition period if needed.

---

## Merge Algorithm

### Overview

The merge algorithm combines user configuration with new defaults while preserving user customizations.

### Merge Process

```
INPUT:
- config.default.ini (source of truth for structure and new keys)
- config.ini (user's customized configuration)

OUTPUT:
- config.ini (merged configuration)
- config.ini.0 (backup of previous user config)

ALGORITHM:
1. Create numbered backup of user config
2. Check schema versions, run migrations if needed
3. Parse both files into key-value maps with section tracking
4. Iterate through default config section by section:
   a. For each key in default:
      - If key exists in user config: Use user's value
      - If key doesn't exist: Use default value (new key added)
   b. Preserve comment blocks for all keys
5. Handle deprecated keys (see next section)
6. Write merged config maintaining section structure
7. Validate merged configuration
8. Rollback if validation fails
```

### Detailed Algorithm

```bash
function __merge_user_config_with_default() {
  # 1. Create numbered backup
  __create_config_backup || return $EC_FAILED_BACKUP
  
  # 2. Check schema versions
  local user_schema current_schema
  user_schema=$(__get_config_value "$CONFIG_FILE" "config_schema_version")
  current_schema=$(__get_config_value "$DEFAULT_CONFIG_FILE" "config_schema_version")
  
  if [[ "$user_schema" -lt "$current_schema" ]]; then
    __run_config_migrations "$user_schema" "$current_schema" || return $EC_MIGRATION_FAILED
  fi
  
  # 3. Parse both configs
  declare -A user_keys default_keys key_sections
  __parse_config_to_map "$CONFIG_FILE" user_keys key_sections
  __parse_config_to_map "$DEFAULT_CONFIG_FILE" default_keys key_sections
  
  # 4. Build merged config
  local merged_file="${CONFIG_FILE}.merged"
  local current_section=""
  
  # Write schema version first
  echo "config_schema_version=$current_schema" > "$merged_file"
  echo "" >> "$merged_file"
  
  # Iterate through default config preserving structure
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Preserve section headers and comments
    if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      echo "$line" >> "$merged_file"
      continue
    fi
    
    if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
      echo "$line" >> "$merged_file"
      continue
    fi
    
    # Process key=value lines
    if [[ "$line" =~ ^([^=]+)= ]]; then
      local key="${BASH_REMATCH[1]}"
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      
      if [[ -n "${user_keys[$key]}" ]]; then
        # User has customized this key - use their value
        echo "$key=${user_keys[$key]}" >> "$merged_file"
      else
        # New key or user never customized - use default
        echo "$line" >> "$merged_file"
      fi
    fi
  done < "$DEFAULT_CONFIG_FILE"
  
  # 5. Handle deprecated keys
  __handle_deprecated_keys user_keys "$merged_file"
  
  # 6. Atomic replace
  mv "$merged_file" "$CONFIG_FILE"
  
  # 7. Validate
  if ! __validate_current_config; then
    __rollback_config 0
    return $EC_INVALID_CONFIG
  fi
  
  return $EC_SUCCESS_CONFIG_MERGED
}
```

### Key Preservation Logic

- **User value exists**: Always use user's value (preservation)
- **Key doesn't exist in user config**: Add with default value (new feature)
- **Default value changed**: Use user's value anyway (preservation over update)
- **Key only in user config**: Handle as potentially deprecated (see next section)

---

## Deprecated Key Handling

### Deprecation Lifecycle

1. **Announcement**: Key marked as deprecated in documentation
2. **Warning Period**: Key still works but warnings logged (at least 1 major version)
3. **Removal**: Key removed from default config, migrations provided

### Handling Deprecated Keys in User Config

When a key exists in user config but not in default config:

```bash
function __handle_deprecated_keys() {
  local -n user_map=$1
  local merged_file="$2"
  
  # Get all keys from default config
  declare -A default_keys_set
  while IFS= read -r key; do
    default_keys_set["$key"]=1
  done < <(__get_all_config_keys)
  
  # Find keys in user config not in default
  local has_deprecated=0
  for key in "${!user_map[@]}"; do
    if [[ -z "${default_keys_set[$key]}" ]]; then
      # Key is deprecated - comment it out and add warning
      echo "" >> "$merged_file"
      echo "# DEPRECATED: The following key is no longer used by KGSM" >> "$merged_file"
      echo "# It has been preserved here for reference but will be ignored" >> "$merged_file"
      echo "# $key=${user_map[$key]}" >> "$merged_file"
      
      __print_warning "Deprecated configuration key found: $key"
      __print_warning "This key has been commented out in your config"
      has_deprecated=1
    fi
  done
  
  if [[ "$has_deprecated" -eq 1 ]]; then
    __print_info "Review commented-out deprecated keys in $CONFIG_FILE"
  fi
}
```

### User Experience

When deprecated keys are found:
- Keys are **commented out** (not removed)
- **Warning message** printed to console
- **Explanation added** in config file comments
- User can manually remove or migrate values as needed

---

## Validation System

### Validation Goals

- Ensure all required keys are present
- Verify values match expected types
- Check dependencies (e.g., systemd binary exists if enabled)
- Catch configuration errors before they cause runtime failures

### Validation Levels

#### Level 1: Structural Validation

```bash
function __validate_config_structure() {
  # Check schema version exists
  local schema_version
  schema_version=$(__get_config_value "$CONFIG_FILE" "config_schema_version")
  [[ -z "$schema_version" ]] && return $EC_INVALID_CONFIG
  
  # Check all required keys present
  local required_keys=(
    "update_channel"
    "auto_update_check"
    "enable_logging"
    # ... more required keys
  )
  
  for key in "${required_keys[@]}"; do
    if ! grep -q "^${key}=" "$CONFIG_FILE"; then
      __print_error "Required configuration key missing: $key"
      return $EC_MISSING_CONFIG_KEY
    fi
  done
  
  return 0
}
```

#### Level 2: Type Validation

```bash
function __validate_config_types() {
  # Boolean validation
  local bool_keys=(
    "auto_update_check"
    "enable_logging"
    "enable_systemd"
    # ... more boolean keys
  )
  
  for key in "${bool_keys[@]}"; do
    local value
    value=$(__get_config_value "$CONFIG_FILE" "$key")
    if [[ "$value" != "true" && "$value" != "false" ]]; then
      __print_error "Invalid boolean value for $key: $value (expected: true or false)"
      return $EC_INVALID_CONFIG_VALUE
    fi
  done
  
  # Integer validation
  local int_keys=(
    "wget_timeout_seconds"
    "instance_suffix_length"
    "webhook_retry_count"
    # ... more integer keys
  )
  
  for key in "${int_keys[@]}"; do
    local value
    value=$(__get_config_value "$CONFIG_FILE" "$key")
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
      __print_error "Invalid integer value for $key: $value"
      return $EC_INVALID_CONFIG_VALUE
    fi
  done
  
  return 0
}
```

#### Level 3: Dependency Validation

```bash
function __validate_config_dependencies() {
  # Check systemd binary if enabled
  if [[ "${config_enable_systemd}" == "true" ]]; then
    if ! command -v systemctl >/dev/null 2>&1; then
      __print_error "systemd is enabled but systemctl not found"
      return $EC_MISSING_DEPENDENCY
    fi
  fi
  
  # Check ufw if firewall management enabled
  if [[ "${config_enable_firewall_management}" == "true" ]]; then
    if ! command -v ufw >/dev/null 2>&1; then
      __print_error "Firewall management enabled but ufw not found"
      return $EC_MISSING_DEPENDENCY
    fi
  fi
  
  # More dependency checks...
  
  return 0
}
```

### Validation Command

```bash
./kgsm.sh config validate
```

Runs all three validation levels and reports results.

---

## Backup and Rollback Strategy

### Numbered Backup System

Replace version-tagged backups with numbered generations:

```
config.ini          # Current active config
config.ini.0        # Most recent backup (previous config)
config.ini.1        # Before that
config.ini.2        # Before that
...
config.ini.9        # Oldest backup kept
```

### Backup Creation

```bash
function __create_config_backup() {
  local max_backups=10
  
  # Rotate existing backups
  for ((i=max_backups-1; i>=0; i--)); do
    local current="${CONFIG_FILE}.${i}"
    local next="${CONFIG_FILE}.$((i+1))"
    
    if [[ -f "$current" ]]; then
      if [[ $i -eq $((max_backups-1)) ]]; then
        # Remove oldest backup
        rm -f "$current"
      else
        # Rotate backup
        mv "$current" "$next"
      fi
    fi
  done
  
  # Create new backup
  cp "$CONFIG_FILE" "${CONFIG_FILE}.0"
  
  return 0
}
```

### Rollback Mechanism

```bash
function __rollback_config() {
  local backup_number="${1:-0}"
  local backup_file="${CONFIG_FILE}.${backup_number}"
  
  if [[ ! -f "$backup_file" ]]; then
    __print_error "Backup $backup_number not found"
    return $EC_FILE_NOT_FOUND
  fi
  
  # Create backup of current before rollback
  cp "$CONFIG_FILE" "${CONFIG_FILE}.rollback-$(date +%s)"
  
  # Restore backup
  cp "$backup_file" "$CONFIG_FILE"
  
  __print_success "Configuration rolled back to backup $backup_number"
  return 0
}
```

### Rollback Command

```bash
./kgsm.sh config rollback      # Rollback to most recent backup (.0)
./kgsm.sh config rollback 2    # Rollback to .2 backup
```

---

## Migration Framework

### Migration Script Structure

Location: `$KGSM_ROOT/migrations/config/`

Naming: `NNN_description.sh` (e.g., `001_flat_to_sectioned.sh`)

```bash
#!/usr/bin/env bash
# Migration: 001 - Convert flat config to sectioned format
# From schema: 0 (flat)
# To schema: 1 (sectioned)

source "$KGSM_ROOT/core/bootstrap.sh"

function migrate() {
  local config_file="$1"
  
  __print_info "Migrating config from flat to sectioned format..."
  
  # Create temporary file for new format
  local temp_file="${config_file}.migrating"
  
  # Write new format header
  echo "config_schema_version=1" > "$temp_file"
  echo "" >> "$temp_file"
  
  # Map old keys to new sections
  # [system]
  echo "[system]" >> "$temp_file"
  __migrate_key "$config_file" "$temp_file" "update_channel"
  __migrate_key "$config_file" "$temp_file" "auto_update_check"
  __migrate_key "$config_file" "$temp_file" "enable_logging"
  # ... more keys
  echo "" >> "$temp_file"
  
  # [network]
  echo "[network]" >> "$temp_file"
  __migrate_key "$config_file" "$temp_file" "enable_firewall_management"
  # ... more keys
  echo "" >> "$temp_file"
  
  # Atomic replace
  mv "$temp_file" "$config_file"
  
  __print_success "Migration to schema v1 complete"
  return 0
}

function __migrate_key() {
  local source="$1"
  local dest="$2"
  local key="$3"
  
  local value
  value=$(grep "^${key}=" "$source" | cut -d= -f2-)
  
  if [[ -n "$value" ]]; then
    echo "${key}=${value}" >> "$dest"
  fi
}

# Execute migration
migrate "$@"
```

### Migration Runner

```bash
function __run_config_migrations() {
  local from_version="$1"
  local to_version="$2"
  
  __print_info "Running config migrations from v${from_version} to v${to_version}..."
  
  local migrations_dir="$KGSM_ROOT/migrations/config"
  
  # Find applicable migration scripts
  for ((v=from_version; v<to_version; v++)); do
    local next=$((v+1))
    local pattern="${migrations_dir}/*_v${v}_to_v${next}.sh"
    
    local migration_script
    migration_script=$(find "$migrations_dir" -name "*_v${v}_to_v${next}.sh" | sort | head -1)
    
    if [[ -z "$migration_script" ]]; then
      __print_error "Migration script not found for v${v} -> v${next}"
      return $EC_MIGRATION_NOT_FOUND
    fi
    
    __print_info "Executing migration: $(basename "$migration_script")"
    
    # Execute migration
    if ! bash "$migration_script" "$CONFIG_FILE"; then
      __print_error "Migration failed: $(basename "$migration_script")"
      return $EC_MIGRATION_FAILED
    fi
  done
  
  __print_success "All migrations completed successfully"
  return 0
}
```

### Migration Testing

Every migration must have a corresponding test:

```bash
# tests/unit/test_config_migrations.sh

function test_migration_001_flat_to_sectioned() {
  # Create flat config
  local test_config="${TEST_SANDBOX_ROOT}/test_config.ini"
  cat > "$test_config" << 'EOF'
update_channel=main
enable_logging=true
enable_systemd=false
EOF

  # Run migration
  bash "$KGSM_ROOT/migrations/config/001_flat_to_sectioned.sh" "$test_config"
  
  # Verify schema version updated
  local schema_version
  schema_version=$(grep "^config_schema_version=" "$test_config" | cut -d= -f2)
  assert_equals "$schema_version" "1" "Schema version should be 1"
  
  # Verify sections exist
  assert_command_succeeds grep -q "^\[system\]" "$test_config"
  assert_command_succeeds grep -q "^\[services\]" "$test_config"
  
  # Verify values preserved
  local value
  value=$(grep "^update_channel=" "$test_config" | cut -d= -f2)
  assert_equals "$value" "main" "update_channel value preserved"
}
```

---

## API Reference

### Core Functions

#### `__merge_user_config_with_default()`
Merge user config with default config, preserving customizations.

**Returns**:
- `$EC_SUCCESS_CONFIG_MERGED` - Merge successful
- `$EC_MIGRATION_FAILED` - Migration failed
- `$EC_INVALID_CONFIG` - Validation failed

---

#### `__run_config_migrations(from_version, to_version)`
Execute migration scripts sequentially.

**Parameters**:
- `$1` - From schema version (integer)
- `$2` - To schema version (integer)

**Returns**:
- `0` - All migrations successful
- `$EC_MIGRATION_NOT_FOUND` - Migration script missing
- `$EC_MIGRATION_FAILED` - Migration execution failed

---

#### `__create_config_backup()`
Create numbered backup of current config.

**Returns**:
- `0` - Backup created
- `$EC_FAILED_BACKUP` - Backup creation failed

---

#### `__rollback_config(backup_number)`
Restore config from numbered backup.

**Parameters**:
- `$1` - Backup number (0-9, default: 0)

**Returns**:
- `0` - Rollback successful
- `$EC_FILE_NOT_FOUND` - Backup not found

---

#### `__validate_config_structure()`
Validate config has all required keys.

**Returns**:
- `0` - Valid
- `$EC_MISSING_CONFIG_KEY` - Required key missing

---

#### `__validate_config_types()`
Validate config values match expected types.

**Returns**:
- `0` - Valid
- `$EC_INVALID_CONFIG_VALUE` - Type mismatch

---

#### `__validate_config_dependencies()`
Validate external dependencies are met.

**Returns**:
- `0` - Valid
- `$EC_MISSING_DEPENDENCY` - Required tool missing

---

#### `__validate_current_config()`
Run all validation levels.

**Returns**:
- `$EC_SUCCESS_CONFIG_VALIDATED` - Valid
- `1` - Validation failed

---

### New Error Codes

Add to `core/errors.sh`:

```bash
export EC_SUCCESS_CONFIG_MERGED=121
export EC_MIGRATION_FAILED=122
export EC_MIGRATION_NOT_FOUND=123
export EC_MISSING_CONFIG_KEY=124
export EC_INVALID_CONFIG_VALUE=125
export EC_FAILED_BACKUP=126
```

---

## Command-Line Interface

### New Commands

#### `./kgsm.sh config merge [--dry-run]`
Merge user config with default config.

**Options**:
- `--dry-run` - Show what would be changed without applying

**Example**:
```bash
./kgsm.sh config merge
# Output:
# Creating backup: config.ini.0
# Running migration v0 -> v1
# Merging configuration...
# Added 3 new keys: webhook_urls, webhook_secret, watcher_global_timeout_seconds
# Commented out 1 deprecated key: old_setting
# Configuration merged successfully
```

---

#### `./kgsm.sh config validate`
Validate current configuration.

**Example**:
```bash
./kgsm.sh config validate
# Output:
# Validating configuration structure... OK
# Validating configuration types... OK
# Validating dependencies... WARNING: systemd enabled but systemctl not found
# Configuration validation complete with 1 warning
```

---

#### `./kgsm.sh config rollback [N]`
Rollback to previous config backup.

**Parameters**:
- `N` - Backup number (0-9, default: 0)

**Example**:
```bash
./kgsm.sh config rollback
# Rolls back to config.ini.0

./kgsm.sh config rollback 2
# Rolls back to config.ini.2
```

---

#### `./kgsm.sh config diff`
Show differences between user config and default config.

**Example**:
```bash
./kgsm.sh config diff
# Output:
# User customizations:
#   update_channel: main -> dev
#   enable_logging: false -> true
# 
# New keys in default:
#   webhook_urls
#   webhook_secret
# 
# Deprecated keys in user config:
#   old_setting=value
```

---

## Testing Requirements

### Unit Tests

Location: `tests/unit/test_config_management.sh`

Required tests:
- `test_parse_sectioned_config()` - Parse INI sections correctly
- `test_merge_adds_new_keys()` - New keys added from default
- `test_merge_preserves_user_values()` - User customizations preserved
- `test_merge_handles_deprecated_keys()` - Deprecated keys commented out
- `test_merge_creates_backup()` - Backup created before merge
- `test_rollback_restores_config()` - Rollback works
- `test_validation_catches_errors()` - Validation detects invalid config

### Migration Tests

Location: `tests/unit/test_config_migrations.sh`

Required for **each migration**:
- Test migration with minimal config
- Test migration with full config
- Test migration preserves all user values
- Test migration updates schema version
- Test migration is idempotent (can run twice safely)

### Integration Tests

Location: `tests/integration/test_config_workflow.sh`

Required tests:
- `test_full_update_workflow()` - Simulate KGSM update with config merge
- `test_migration_chain()` - Test migrating through multiple versions
- `test_merge_and_validate()` - Merge followed by validation
- `test_failed_merge_rollback()` - Failed merge triggers automatic rollback

### Example Test

```bash
function test_merge_preserves_user_values() {
  # Setup: Create user config with custom values
  cat > "$TEST_CONFIG_FILE" << 'EOF'
config_schema_version=1

[system]
update_channel=dev
enable_logging=true
EOF

  # Setup: Create default config with different values
  cat > "$TEST_DEFAULT_CONFIG_FILE" << 'EOF'
config_schema_version=1

[system]
update_channel=main
enable_logging=false
new_setting=value
EOF

  # Execute merge
  CONFIG_FILE="$TEST_CONFIG_FILE" \
  DEFAULT_CONFIG_FILE="$TEST_DEFAULT_CONFIG_FILE" \
  __merge_user_config_with_default
  
  # Verify user values preserved
  local channel logging
  channel=$(grep "^update_channel=" "$TEST_CONFIG_FILE" | cut -d= -f2)
  logging=$(grep "^enable_logging=" "$TEST_CONFIG_FILE" | cut -d= -f2)
  
  assert_equals "$channel" "dev" "User's update_channel preserved"
  assert_equals "$logging" "true" "User's enable_logging preserved"
  
  # Verify new key added
  assert_command_succeeds grep -q "^new_setting=value" "$TEST_CONFIG_FILE"
}
```

---

## Implementation Phases

### Phase 1: Specification and Preparation
- ✓ Create this specification document
- Create migration directory structure
- Add new error codes to `core/errors.sh`
- Set up test framework stubs

### Phase 2: Configuration Format Migration
- Restructure `config.default.ini` to sectioned format
- Add `config_schema_version=1` 
- Update section-aware parser in `core/config.sh`
- Create first migration script (flat → sectioned)
- Add migration tests

### Phase 3: Merge Engine Implementation
- Rewrite `__merge_user_config_with_default()`
- Implement section-aware merging
- Add deprecated key handling
- Implement numbered backup system
- Add merge tests

### Phase 4: Validation System
- Implement structural validation
- Implement type validation
- Implement dependency validation
- Add validation tests

### Phase 5: Command Integration
- Add `config merge` command to CLI
- Add `config validate` command
- Add `config rollback` command
- Add `config diff` command
- Wire into installer for automatic updates
- Add integration tests

### Phase 6: Documentation and Migration Guide
- Update README with new config commands
- Create user migration guide for v3.0
- Document all config sections and keys
- Add examples to documentation

---

## Migration Guide for KGSM v3.0 Users

### For End Users

When upgrading to KGSM v3.0:

1. **Backup your config**: Your existing `config.ini` will be backed up automatically
2. **Run installer**: The installer will detect old config format and migrate automatically
3. **Review changes**: Check `config.ini` for any deprecated keys that were commented out
4. **Test configuration**: Run `./kgsm.sh config validate` to ensure everything is correct

### For Developers

When adding new configuration keys:

1. **Add to `config.default.ini`** in the appropriate section
2. **Do NOT increment schema version** (unless structure changes)
3. **Add validation** if the key has constraints
4. **Document** the key with comment block
5. **Add test** that validates the key

When making breaking configuration changes:

1. **Increment schema version** in `config.default.ini`
2. **Create migration script** in `migrations/config/`
3. **Add migration tests** 
4. **Update this specification**
5. **Document breaking change** in CHANGELOG

---

## Appendix A: Configuration File Example

### Default Configuration (config.default.ini)

```ini
# ============================================================================
# KGSM - Krystal Game Server Manager
# Configuration File
# ============================================================================
#
# This is the main configuration file for the Krystal Game Server Manager.
# You can customize your KGSM installation by modifying the settings below.
#
# IMPORTANT NOTES:
#  - All settings can also be set as environment variables
#  - Uncommented values in this file override environment variables
#  - Use '#' for comments to maintain bash script compatibility
#  - All paths should be absolute unless otherwise specified
#
# ============================================================================

config_schema_version=1

# ============================================================================
# SYSTEM CORE SETTINGS
# ============================================================================

[system]

# UPDATE CHANNEL
# Which update channel should KGSM use when checking for updates?
# The main channel offers stable releases while dev provides bleeding-edge features.
#
# Expected values:
#   main   - Stable, well-tested releases (recommended)
#   dev    - Latest features but may include experimental changes
#
# Default: main
update_channel=main

# AUTO UPDATE CHECK
# Should KGSM automatically check for updates when launched?
# When enabled, KGSM will check the selected update channel for new versions
# each time kgsm.sh is run.
#
# Dependencies: wget
#
# Expected values:
#   false  - Disable update checks
#   true   - Enable automatic update checks
#
# Default: false
auto_update_check=false

# ... more system settings ...

# ============================================================================
# NETWORK SETTINGS
# ============================================================================

[network]

# ENABLE FIREWALL MANAGEMENT
# Should KGSM automatically configure firewall rules for game servers?
# When enabled, KGSM will create and manage UFW firewall rules for each
# game server instance.
#
# Dependencies: ufw
#
# Expected values:
#   false  - Don't manage firewall rules
#   true   - Automatically manage firewall rules
#
# Default: false
enable_firewall_management=false

# ... more network settings ...
```

---

## Appendix B: Exit Code Reference

All config-related exit codes:

```bash
# Success codes (100-120)
EC_SUCCESS_CONFIG_SET=117
EC_SUCCESS_CONFIG_RESET=118
EC_SUCCESS_CONFIG_VALIDATED=119
EC_SUCCESS_CONFIG_MERGED=121

# Error codes (config-specific)
EC_INVALID_CONFIG=40
EC_KEY_NOT_FOUND=41
EC_MIGRATION_FAILED=122
EC_MIGRATION_NOT_FOUND=123
EC_MISSING_CONFIG_KEY=124
EC_INVALID_CONFIG_VALUE=125
EC_FAILED_BACKUP=126
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-16 | KGSM Team | Initial specification |

---

**End of Specification**
