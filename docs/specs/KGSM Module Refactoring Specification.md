# KGSM Module Refactoring Specification

## Document Purpose

This specification provides a comprehensive guide for refactoring KGSM modules from the legacy dash-argument style to the modern command-based architecture with separated I/O and logic layers.

## Table of Contents

1. Overview
2. Argument Style Migration
3. Architecture Separation
4. Command Structure Patterns
5. Exit Code Handling
6. Event Dispatching
7. Help System
8. Refactoring Checklist
9. Examples

---

## Overview

### Legacy Pattern (Dash-Arguments)
```bash
# Old style - dash-based flags
./files.sh --instance myserver --create
./events.sh --emit --instance-created myserver
```

### Modern Pattern (Command-Based)
```bash
# New style - command-based with options
./config.sh set enable_logging=true
./lifecycle.sh start myserver
./directories.sh create --instance myserver
```

### Key Differences

| Aspect                | Legacy                         | Modern                                  |
| --------------------- | ------------------------------ | --------------------------------------- |
| **Primary Interface** | Flags (`--create`, `--remove`) | Commands (`create`, `remove`)           |
| **Arguments**         | Mixed with flags               | Positional after command                |
| **Options**           | Interleaved with commands      | After command and arguments             |
| **Help**              | Single `--help` flag           | `help [command]` + per-command `--help` |
| **Logic Location**    | Inline in module               | Separate `commands/handlers/*.sh` file          |
| **I/O Handling**      | Mixed with logic               | Only in `_cmd_*()` functions            |
| **Exit Codes**        | Direct returns                 | Centralized handling with events        |

---

## Argument Style Migration

### Command Hierarchy

All refactored modules follow this structure:

```
module.sh [global-options] <command> [arguments] [command-options]
```

#### Components:

1. **Global Options** (before command)
   - `--help`, `-h` - Show main usage
   - `--debug` - Enable debug mode
   
2. **Command** (required)
   - Primary action verb: `create`, `remove`, `set`, `get`, `list`, `start`, `stop`
   - Subcommands where applicable
   
3. **Arguments** (positional, after command)
   - Required parameters specific to command
   - Order matters
   
4. **Command Options** (after arguments)
   - `--help` - Show command-specific help
   - Command-specific flags

### Argument Parsing Pattern

```bash
#!/usr/bin/env bash

# No arguments passed are treated as an error
# Show usage and exit
if [[ $# -eq 0 ]]; then
  show_usage
  exit $EC_GENERAL
fi

# Parse command
command="$1"
shift

# Command-specific parsing
case "$command" in
  set)
    _cmd_set "$@"
    exit $?
    ;;
  get)
    _cmd_get "$@"
    exit $?
    ;;
  -h | --help | help)
    _cmd_help "$@"
    exit $?
    ;;
  # ... other commands
  *)
    __print_error "Unknown command: $command"
    exit $EC_INVALID_ARG
    ;;
esac
```

### Command Function Pattern

Each command gets its own function that handles validation and delegates to logic:

```bash
function _cmd_create() {
  local instance_name=""
  local optional_param=""

  # Parse command-specific options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -i | --instance)
        shift
        [[ -z "$1" ]] && __print_error "Missing argument for --instance" && exit $EC_MISSING_ARG
        instance_name="$1"
        ;;
      --optional-flag)
        optional_param="value"
        ;;
      --help)
        usage_create && exit 0
        ;;
      *)
        __print_error "Invalid option for create command: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required option: --instance"
    __print_error "Use '$(basename "$0") create --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Call pure logic function
  __print_info "Creating resource for $instance_name"
  local exit_code
  __logic_create_resource "$instance_name" "$optional_param"
  exit_code=$?

  # Handle result based on exit code
  case $exit_code in
    $EC_SUCCESS_RESOURCE_CREATED)
      __print_success "Resource created successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      exit 0
      ;;
    *)
      __print_error "Failed to create resource"
      exit $exit_code
      ;;
  esac
}
```

---

## Architecture Separation

### Module Layer (User-Facing)

**Location**: `commands/*.sh`

**Responsibilities**:
- Argument parsing and validation
- User interaction (printing messages)
- Event dispatching
- Calling pure logic functions
- Exit code interpretation

**Pattern**:
```bash
# commands/example.sh
#!/usr/bin/env bash

# shellcheck disable=SC2086
# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  # Main usage display
}

function _cmd_action() {
  # Parse arguments
  # Validate inputs
  # Call __logic_action()
  # Handle exit codes
  # Dispatch events
  # Print user messages
}

# Main argument processing
# Command routing
```

### Logic Layer (Pure Functions)

**Location**: `commands/handlers/*.sh`

**Responsibilities**:
- Pure business logic only
- No user-facing I/O (`__print_*` functions)
- No argument parsing
- Returns meaningful exit codes
- Handles all error conditions

**Pattern**:
```bash
# commands/handlers/example.sh
#!/usr/bin/env bash

# shellcheck disable=SC2086

# Creates a resource
# Args: $1 = resource_name, $2 = optional_param
# Returns: EC_SUCCESS_RESOURCE_CREATED on success, error codes on failure
function __logic_create_resource() {
  local resource_name="$1"
  local optional_param="$2"

  # Validate required parameters
  if [[ -z "$resource_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Perform operations - suppress all output
  if ! some_operation >/dev/null 2>&1; then
    return $EC_OPERATION_FAILED
  fi

  # Return success event code
  return $EC_SUCCESS_RESOURCE_CREATED
}

export -f __logic_create_resource

# Mark module as loaded
export KGSM_LOGIC_EXAMPLE_LOADED=1
```

### Integration Pattern

```bash
# In module file
logic_library=$(__find_command_handler example.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load example logic library"
  exit $EC_FAILED_SOURCE
}

# Call logic function
__logic_create_resource "$name" "$param"
exit_code=$?

# Handle result
case $exit_code in
  $EC_SUCCESS_RESOURCE_CREATED)
    __print_success "Resource created"
    __dispatch_event_from_exit_code "$exit_code" "$name"
    ;;
  *)
    __print_error "Failed to create resource"
    exit $exit_code
    ;;
esac
```

---

## Command Structure Patterns

### Single-Level Commands

Used when operations are distinct and don't share context.

**Example**: config.sh

```bash
config.sh set key=value
config.sh get key
config.sh list
config.sh reset
config.sh validate
```

**Implementation**:
```bash
case "$command" in
  set)
    _cmd_set "$@"
    exit $?
    ;;
  get)
    _cmd_get "$@"
    exit $?
    ;;
  # ...
esac
```

### Instance-Based Commands

Used when all operations require an instance context.

**Example**: lifecycle.sh

```bash
lifecycle.sh start myserver
lifecycle.sh stop myserver [options]
lifecycle.sh status myserver --json
```

**Implementation**:
```bash
function _cmd_start() {
  local instance_name="$1"
  shift
  
  # Validate instance_name first
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    exit $EC_MISSING_ARG
  fi
  
  # Then parse remaining options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        usage_start && exit 0
        ;;
      *)
        __print_error "Invalid option: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
    shift
  done
  
  # Execute logic
}
```

### Hierarchical Commands (Subcommands)

Used when operations have logical groupings.

**Example**: files.sh (to be refactored)

```bash
# Current (legacy)
files.sh --instance myserver --create --systemd

# Proposed (modern)
files.sh create myserver
files.sh create myserver --systemd
files.sh remove myserver
files.sh remove myserver --systemd
```

**Implementation**:
```bash
case "$command" in
  create)
    shift
    instance_name="$1"
    shift
    
    # If no subcommand, create all
    if [[ -z "$1" ]]; then
      _cmd_create_all "$instance_name"
      exit $?
    fi
    
    # Otherwise, route to specific subcommand
    case "$1" in
      --systemd)
        _cmd_create_systemd "$instance_name"
        ;;
      --ufw)
        _cmd_create_ufw "$instance_name"
        ;;
      # ...
    esac
    ;;
  remove)
    # Similar pattern
    ;;
esac
```

### Event-Emission Commands

Special case where command is the event type itself.

**Example**: events.sh (to be refactored)

```bash
# Current (legacy)
events.sh --emit --instance-created myserver blueprint

# Proposed (modern)
events.sh emit server.install.created myserver blueprint
events.sh emit server.started myserver systemd
```

**Implementation**:
```bash
case "$command" in
  emit)
    shift
    event_type="$1"
    shift
    
    # Convert dash-case to underscore for variable lookup
    local event_const="EVENT_${event_type//-/_}"
    event_const="${event_const^^}"  # Uppercase
    
    # Validate event type exists
    if [[ -z "${!event_const}" ]]; then
      __print_error "Unknown event type: $event_type"
      exit $EC_INVALID_ARG
    fi
    
    # Call generic emit function
    _emit_event "${!event_const}" "$@"
    ;;
esac
```

---

## Exit Code Handling

### Success Event Codes

Success operations that trigger events use codes 200-299 (defined in errors.sh):

```bash
# core/errors.sh
export EC_SUCCESS_DIRECTORIES_CREATED=200
export EC_SUCCESS_DIRECTORIES_REMOVED=201
export EC_SUCCESS_CONFIG_SET=202
export EC_SUCCESS_CONFIG_RESET=203
export EC_SUCCESS_INSTANCE_STARTED=210
export EC_SUCCESS_INSTANCE_STOPPED=211
# ... etc
```

### Exit Code Interpretation Pattern

```bash
# In _cmd_* function
__logic_operation "$param1" "$param2"
local exit_code=$?

case $exit_code in
  $EC_SUCCESS_OPERATION_COMPLETE)
    __print_success "Operation completed successfully"
    __dispatch_event_from_exit_code "$exit_code" "$instance_name" "$additional_data"
    exit 0
    ;;
  $EC_INVALID_ARG)
    __print_error "Invalid argument provided"
    __print_error "Details: $param1, $param2"
    exit $exit_code
    ;;
  $EC_FILE_NOT_FOUND)
    __print_error "Required file not found"
    exit $exit_code
    ;;
  $EC_PERMISSION)
    __print_error "Permission denied"
    exit $exit_code
    ;;
  *)
    __print_error "Operation failed with unexpected error"
    exit $exit_code
    ;;
esac
```

### Logic Function Exit Codes

Logic functions should only return:
- `0` - Success without event (rare)
- `200-299` - Success with event emission
- Standard error codes from errors.sh

```bash
function __logic_example() {
  # Validate inputs
  if [[ -z "$required_param" ]]; then
    return $EC_INVALID_ARG
  fi
  
  # Check preconditions
  if [[ ! -f "$required_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi
  
  # Perform operation
  if ! operation >/dev/null 2>&1; then
    return $EC_OPERATION_FAILED
  fi
  
  # Return success event code
  return $EC_SUCCESS_OPERATION_COMPLETE
}
```

---

## Event Dispatching

### Centralized Event Dispatching

Use `__dispatch_event_from_exit_code()` to automatically emit events based on exit codes:

```bash
# After logic function call
case $exit_code in
  $EC_SUCCESS_DIRECTORIES_CREATED)
    __print_success "Directories created"
    __dispatch_event_from_exit_code "$exit_code" "$instance_name"
    exit 0
    ;;
esac
```

### Exit Code to Event Mapping

Defined in events.sh:

```bash
# core/events.sh
case "$exit_code" in
  $EC_SUCCESS_DIRECTORIES_CREATED)
    event_type="$EVENT_INSTANCE_DIRECTORIES_CREATED"
    ;;
  $EC_SUCCESS_DIRECTORIES_REMOVED)
    event_type="$EVENT_INSTANCE_DIRECTORIES_REMOVED"
    ;;
  # ... etc
esac
```

### Direct Event Emission (Alternative)

For complex events with multiple parameters:

```bash
# After operation
__print_success "Version updated"
events.sh emit server.updated "$instance_name" "$old_version" "$new_version"
```

---

## Help System

### Three-Tier Help Structure

1. **Main Usage** (`show_usage()`)
   - Overview of module
   - List of all commands
   - Global options
   - Basic examples
   
2. **Command-Specific Usage** (`usage_<command>()`)
   - Detailed command description
   - Command syntax
   - Command-specific options
   - Command-specific examples
   
3. **Help Command** (`help [command]`)
   - Routes to appropriate usage function

### Main Usage Template

```bash
function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}[Module Title] for Krystal Game Server Manager${END}

[Brief description of module purpose]

${UNDERLINE}Usage:${END}
  ${self} [command] [arguments] [options]

${UNDERLINE}Commands:${END}
  command1 <arg>              Description of command1
  command2 <arg> [opt]        Description of command2
  help [command]              Show help information

${UNDERLINE}Options:${END}
  -h, --help                  Show help and exit
  --debug                     Enable debug output

${UNDERLINE}Examples:${END}
  ${self} command1 value
  ${self} command2 value --option
  ${self} help command1

${UNDERLINE}Notes:${END}
  • Important note 1
  • Important note 2
"
}
```

### Command Usage Template

```bash
function usage_command() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Command Name${END}

[Detailed description of what this command does]

${UNDERLINE}Usage:${END}
  ${self} command <required-arg> [optional-arg] [options]

${UNDERLINE}Arguments:${END}
  required-arg                Description of required argument
  optional-arg                Description of optional argument

${UNDERLINE}Options:${END}
  --option                    Description of option
  --help                      Display this help information

${UNDERLINE}Description:${END}
[Extended description, including:
 - What the command does
 - What files/resources it affects
 - Any important warnings or notes]

${UNDERLINE}Examples:${END}
  ${self} command value1
  ${self} command value1 value2 --option
"
}
```

### Help Command Implementation

```bash
function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
  else
    case "$command" in
      command1)
        usage_command1
        ;;
      command2)
        usage_command2
        ;;
      *)
        __print_error "Unknown command: $command"
        __print_error "Use '$(basename "$0") help' for available commands"
        return $EC_INVALID_ARG
        ;;
    esac
  fi
  return 0
}

# In main command routing
case "$command" in
  -h | --help | help)
    _cmd_help "$1"
    exit $?
    ;;
  # ... other commands
esac
```

### Inline Help (--help flag)

Each command function should support `--help`:

```bash
function _cmd_create() {
  # ... argument parsing
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        usage_create && exit 0
        ;;
      # ... other options
    esac
    shift
  done
  # ... rest of function
}
```

---

## Refactoring Checklist

### Pre-Refactoring Analysis

- [ ] Identify all current commands/operations in legacy module
- [ ] Map dash-arguments to command structure
- [ ] Identify pure logic vs I/O code
- [ ] List all exit codes used
- [ ] Document all events emitted
- [ ] Identify all user-facing messages

### Module Layer Refactoring

- [ ] Update shebang and bootstrap sourcing
- [ ] Add SC2086 disable comment
- [ ] Create `show_usage()` function
- [ ] Create `usage_<command>()` for each command
- [ ] Implement global option parsing (--help, --debug)
- [ ] Create `_cmd_<command>()` for each operation
  - [ ] Implement argument validation
  - [ ] Add command-specific --help support
  - [ ] Call logic function
  - [ ] Handle exit codes with case statement
  - [ ] Add user-facing messages
  - [ ] Dispatch events
- [ ] Implement main command routing
- [ ] Add `_cmd_help()` function

### Logic Layer Creation

- [ ] Create new file in logic
- [ ] Add SC2086 disable comment
- [ ] Create `__logic_<operation>()` functions
  - [ ] Add comprehensive function documentation
  - [ ] Implement parameter validation
  - [ ] Use only exit codes for communication
  - [ ] Suppress all output (`>/dev/null 2>&1`)
  - [ ] Return appropriate exit codes
  - [ ] Export functions
- [ ] Add module loaded guard
- [ ] Test logic functions in isolation

### Integration

- [ ] Source logic library in module
- [ ] Add error handling for source failure
- [ ] Verify all exit code constants exist in errors.sh
- [ ] Add new success event codes if needed
- [ ] Update event dispatcher mappings if needed
- [ ] Test all commands
- [ ] Verify event emission
- [ ] Check error handling paths

### Documentation

- [ ] Update module comments
- [ ] Add usage examples to help text
- [ ] Document new exit codes in errors.sh
- [ ] Update relevant architecture docs
- [ ] Add/update tests

### Testing

- [ ] Create unit tests for logic functions
- [ ] Create integration tests for module commands
- [ ] Test all help variants (main, command, --help)
- [ ] Test error conditions
- [ ] Test event emission
- [ ] Run full test suite

---

## Examples

### Example 1: Simple Refactoring (config.sh style)

**Legacy files.sh fragment**:
```bash
--install)
  shift
  [[ -z "$1" ]] && echo "Missing instance" && exit 1
  instance=$1
  # ... inline logic
  echo "Installed"
  ;;
```

**Refactored**:
```bash
# commands/files.sh
function _cmd_install() {
  local instance_name="$1"
  shift
  
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    exit $EC_MISSING_ARG
  fi
  
  __print_info "Installing files for $instance_name"
  __logic_install_files "$instance_name"
  local exit_code=$?
  
  case $exit_code in
    $EC_SUCCESS_FILES_INSTALLED)
      __print_success "Files installed successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      exit 0
      ;;
    *)
      __print_error "Failed to install files"
      exit $exit_code
      ;;
  esac
}

# commands/handlers/files.sh
function __logic_install_files() {
  local instance_name="$1"
  
  if [[ -z "$instance_name" ]]; then
    return $EC_INVALID_ARG
  fi
  
  # Perform installation
  if ! install_operation >/dev/null 2>&1; then
    return $EC_FAILED_INSTALL
  fi
  
  return $EC_SUCCESS_FILES_INSTALLED
}
```

## Validation Patterns

### Argument Validation

Use centralized validation functions from common.sh:

```bash
# Validate non-empty argument
if ! validate_not_empty "$instance_name" "instance name"; then
  exit $EC_MISSING_ARG
fi

# Validate instance exists
if ! validate_instance_name "$instance_name"; then
  exit $?
fi

# Validate config value
if ! validate_working_directory "$config_file"; then
  exit $?
fi
```

### Parameter Validation in Logic Functions

```bash
function __logic_operation() {
  local required_param="$1"
  local optional_param="$2"
  
  # Always validate required parameters
  if [[ -z "$required_param" ]]; then
    return $EC_INVALID_ARG
  fi
  
  # Validate types/formats
  if [[ ! "$required_param" =~ ^[a-z0-9-]+$ ]]; then
    return $EC_INVALID_ARG
  fi
  
  # ... rest of logic
}
```

---

## Final Notes

### Behavioral Consistency

- Commands should have **deterministic** outcomes
- Exit codes must be **consistent** across similar operations
- Error messages should be **helpful** and actionable
- Help text should be **comprehensive** yet concise

### Testing Requirements

Every refactored module must have:
- Unit tests for all logic functions
- Integration tests for all commands
- Help text validation tests
- Error condition tests

### Backward Compatibility

During transition period:
- Old dash-style arguments may be supported with deprecation warnings
- Use wrapper functions to redirect old calls to new structure
- Document migration path for users

---

**Document Version**: 1.0
**Last Updated**: 2025-10-31
**Maintainer**: KGSM Development Team
