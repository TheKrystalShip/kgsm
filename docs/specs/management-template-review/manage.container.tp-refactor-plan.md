# Refactoring Plan: `templates/manage.container.tp`

## Problem Statement

`templates/manage.container.tp` (1491 lines) is the Docker-based counterpart to the now-refactored `manage.native.tp`. It suffers from all the same organizational issues the native template had before refactoring — old logging system, `--flag` CLI style, no `_cmd_*` pattern, no help system, no section grouping, no exit code constants — plus its interface is completely incompatible with the refactored native template's subcommand-style CLI.

**Goal**: Refactor `manage.container.tp` to have an **identical external interface** and the **same internal structure** as the refactored `manage.native.tp`, while preserving container-specific implementation details (Docker Compose operations, container ID tracking, input sanitization, container monitoring).

**Key constraint**: Both templates generate standalone scripts. They cannot depend on `core/bootstrap.sh`. They must be self-contained.

---

## Analysis: Current State vs Target

### Structure Comparison

| Aspect | `manage.native.tp` (target) | `manage.container.tp` (current) |
|--------|---------------------------|-------------------------------|
| Exit codes | `EC_SUCCESS`, `EC_ERROR`, `EC_MISSING_ARG`, `EC_INVALID_ARG` | Hardcoded `exit 1` everywhere |
| Logging | Inline color codes in `__print_*` functions | Intermediate `SUCCESS`/`INFO`/`ERROR`/`WARNING` variables |
| Help system | `show_usage()` + 11 `show_usage_*()` + `_cmd_help()` | Simple `usage()` function |
| CLI style | Subcommands: `start`, `stop`, `backup create`, etc. | Flags: `--start`, `--stop`, `--create-backup`, etc. |
| Command handlers | `_cmd_*` pattern with per-command arg parsing | Logic called directly from main `while/case` loop |
| Section headers | 12 labeled `=====` sections | No section grouping |
| Cleanup function | `_cleanup_on_exit` | `_term_cleanup` |
| Kill function | `_kill_all_processes` | `_kill_container` |
| Missing commands | — | No `restart`, no `attach` |
| Start flag | `start -d` / `start --detached` | `--start --background` |
| Docker checks | N/A | At bottom before CLI parsing (line 1274) |
| Early arg check | In main dispatch (`""` case) | Between logging and functions (line 195) |
| Container-specific | N/A | `_get_container_process_info`, `_monitor_container_state`, `__sanitize_input_command`, docker checks |

### Caller Interface Requirements

All callers were already updated during the native refactoring. They now call manage scripts with the subcommand interface. Since callers use `manage.${_instance_runtime}.tp` dynamically, the container template **MUST** support the exact same CLI:

- `commands/handlers/lifecycle.sh`: `start -d`, `stop`, `is-active`, `status`, `logs`
- `commands/instances.sh`: `status`, `save`, `input`
- `commands/install.sh`: `version --latest`, `download`, `deploy`, `version --save`
- `commands/handlers/wizards.sh`: `backup list`
- `templates/service.tp`: `start --detached`, `stop`

**These callers will BREAK with container instances until this refactoring is done.**

### Container-Specific Functions to Preserve

These functions exist only in the container template and must be preserved:

1. **`_get_container_process_info()`** (L401-428): Gets container stats via `docker stats`
2. **`_monitor_container_state()`** (L433-470): Gets detailed container state via `docker inspect`
3. **`__sanitize_input_command()`** (L474-504): Security validation for container input commands
4. **Docker dependency checks** (L1274-1283): Verify `docker` and `docker compose` are available

### Container-Specific Implementation Differences

These functions have the same interface as native but different implementations:

- **`_is_active()`**: Checks both numeric PIDs and Docker container IDs (alphanumeric, length > 10)
- **`_start_background()`**: Uses `docker compose up -d` instead of screen sessions
- **`_start()`**: Uses `docker compose up` (foreground) instead of direct execution
- **`_stop_server()`**: Uses `docker compose down` instead of signal-based shutdown; uses string `"true"`/`"false"` for no_save/no_graceful (works correctly unlike native's old numeric bug)
- **`_kill_container()`**: Kills via `docker kill` + `docker compose down --remove-orphans`
- **`_send_input()`**: Uses `docker exec` with `$MANAGEMENT_FILE` inside container
- **`_print_logs()`**: Uses `docker compose logs` instead of file-based logs
- **`_update()`**: Pulls latest images + recreates containers via compose
- **`_download()`**: Runs `docker compose pull`
- **`_deploy()`**: No-op for containers
- **`_get_status()`**: Handles container IDs, uses `docker inspect` for state

---

## Refactoring Todos

### Todo 1: Add exit code constants and simplify logging

**Description**: Add local `EC_*` constants matching native template. Simplify the logging system by removing intermediate `SUCCESS`/`INFO`/`ERROR`/`WARNING` variables and using inline color codes directly in `__print_*` functions.

**Changes**:
- Add after line 24 (after debug block):
  ```bash
  # Local exit code constants (mirrors core/errors.sh for standalone use)
  readonly EC_SUCCESS=0
  readonly EC_ERROR=1
  readonly EC_MISSING_ARG=7
  readonly EC_INVALID_ARG=8
  ```
- Replace lines 147-175 (color detection + intermediate variables) with the native template's compact pattern:
  ```bash
  COLOR_RED="" COLOR_GREEN="" COLOR_ORANGE="" COLOR_BLUE="" COLOR_END=""
  if test -t 1 && command -v tput >/dev/null 2>&1; then
    if [[ "$(tput colors 2>/dev/null)" -gt 8 ]] 2>/dev/null; then
      COLOR_RED="\033[0;31m"
      COLOR_GREEN="\033[0;32m"
      COLOR_ORANGE="\033[0;33m"
      COLOR_BLUE="\033[0;34m"
      COLOR_END="\033[0m"
    fi
  fi
  ```
- Update `__print_*` functions to use inline color codes:
  ```bash
  function __print_success() {
    echo -e "[${COLOR_GREEN}SUCCESS${COLOR_END}] ${BASH_SOURCE[-1]##*/}:${BASH_LINENO[0]} $1"
  }
  ```
  (Same for `__print_info`, `__print_error`, `__print_warning`)
- Replace all `exit 1` with appropriate `EC_*` constants throughout the file
- Remove the early `if [[ $# -eq 0 ]]; then` check (lines 195-198) — this will be handled in the main dispatch section

### Todo 2: Rename functions and clean up for consistency

**Description**: Rename functions to match native template's naming. Move docker dependency checks to the initialization section. Adjust `_stop_server` to use numeric flags matching native pattern.

**Changes**:
- Rename `_term_cleanup` → `_cleanup_on_exit` (and update the trap reference)
- Rename `_kill_container` → `_kill_all_processes` (for interface consistency; implementation stays container-specific)
- Move docker dependency checks (currently lines 1274-1283) to initialization section (after config sourcing, before logging setup)
- Update `_stop_server` to accept numeric `0`/`1` flags for `no_save` and `no_graceful` instead of string `"true"`/`"false"`, matching the native template's `_cmd_stop` pattern:
  ```bash
  local no_save=$1   # 0 = save, 1 = no save
  local no_graceful=$2  # 0 = graceful, 1 = no graceful
  if [[ "$no_save" -eq 0 ]]; then _send_save_command; fi
  if [[ "$no_graceful" -eq 0 ]]; then ...graceful stop...; fi
  ```
- Add a `_timed_stop` function wrapper around `_stop_server` for interface parity with native. For containers, this can simply call `_stop_server` directly since `docker compose down` handles its own timeout.

### Todo 3: Group functions by domain with section headers

**Description**: Reorganize all functions into 12 labeled sections matching the exact section order from the refactored native template.

**Section order** (matching native template exactly):
```
# ============================== CONFIGURATION AND INITIALIZATION
# ============================== HELP SYSTEM
# ============================== PROCESS MANAGEMENT
# ============================== SERVER I/O
# ============================== VERSION MANAGEMENT
# ============================== DOWNLOAD AND DEPLOYMENT
# ============================== BACKUP MANAGEMENT
# ============================== NETWORK (UPnP)
# ============================== LOGGING
# ============================== STATUS
# ============================== COMMAND HANDLERS
# ============================== MAIN DISPATCH
```

**Function-to-section mapping**:
- **Configuration and Initialization**: `__validate_config_key`, `__source_instance_config`, config sourcing, docker dependency checks, color setup, `__print_*` functions
- **Help System**: `show_usage`, all `show_usage_*` functions, `_cmd_help` (new)
- **Process Management**: `_is_active`, `_start`, `_start_background`, `_stop_server`, `_timed_stop` (new), `_kill_all_processes` (renamed from `_kill_container`), `_cleanup_on_exit` (renamed from `_term_cleanup`), trap setup
- **Server I/O**: `__sanitize_input_command`, `_send_input`, `_send_save_command`
- **Version Management**: `_get_installed_version`, `_get_latest_version`, `_compare_versions`, `_save_version`
- **Download and Deployment**: `_download`, `_deploy`, `_update`
- **Backup Management**: `_create_backup`, `_restore_backup`, `_list_backups`
- **Network (UPnP)**: `_enable_upnp`, `_disable_upnp`, `_is_upnp_enabled`
- **Logging**: `_rotate_log_file`, `_print_logs`
- **Status**: `_get_container_process_info`, `_monitor_container_state`, `_get_status`
- **Command Handlers**: All `_cmd_*` functions (new)
- **Main Dispatch**: Top-level `case "$command"` dispatch (new)

### Todo 4: Convert CLI to subcommand-style with `_cmd_*` pattern

**Description**: Replace the `while/case` argument loop (lines 1286-1489) with subcommand-style dispatch using `_cmd_*` handler functions, matching native template exactly.

**New CLI interface** (identical to native template):
```
manage.sh <command> [arguments] [options]

Commands:
  start [-d, --detached]                Start the container
  stop [--no-save] [--no-graceful]      Stop the container
  restart                               Restart the container
  attach                                Attach to running container console
  kill                                  Force kill the container
  save                                  Save the current game state
  input <command>                       Send a command to the container
  is-active                             Check if the container is running
  status [--json] [--fast]              Display runtime status
  logs [--follow] [--tail N]            View container logs
  version [--latest|--compare|--save <ver>]  Version management
  download [version]                    Pull container images
  deploy                                Deploy container (no-op for containers)
  update                                Update to latest container images
  backup create                         Create a backup
  backup restore <source>               Restore a backup
  backup list                           List available backups
  upnp enable                           Enable UPnP port forwarding
  upnp disable                          Disable UPnP port forwarding
  help [command]                        Display help information
```

**Changes**:
- Create 16 `_cmd_*` functions: `_cmd_start`, `_cmd_stop`, `_cmd_restart` (new), `_cmd_attach` (new), `_cmd_kill`, `_cmd_save`, `_cmd_input`, `_cmd_is_active`, `_cmd_status`, `_cmd_logs`, `_cmd_version`, `_cmd_download`, `_cmd_deploy`, `_cmd_update`, `_cmd_backup`, `_cmd_upnp`
- Each `_cmd_*` handles its own argument parsing with `-h|--help|help` support
- Replace bottom-of-file `while/case` with:
  ```bash
  command="${1:-}"
  shift 2>/dev/null || true
  case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  ...per-command dispatch...
  esac
  ```
- **`_cmd_restart`** implementation: Stop (with save and graceful), then start in detached mode
- **`_cmd_attach`** implementation: Use `docker compose exec <service> /bin/sh` for interactive shell or `docker compose attach` for attaching to the container's main process

### Todo 5: Add comprehensive help system

**Description**: Replace simple `usage()` with `show_usage()` + per-command `show_usage_*()` functions + `_cmd_help()` dispatcher, matching native template's format exactly.

**Changes**:
- Rename `usage()` → `show_usage()` and reformat with ANSI formatting (UNDERLINE, BOLD, END)
- Create `show_usage_start`, `show_usage_stop`, `show_usage_restart`, `show_usage_attach`, `show_usage_status`, `show_usage_logs`, `show_usage_version`, `show_usage_backup`, `show_usage_upnp`, `show_usage_download`, `show_usage_update`
- Create `_cmd_help()` that dispatches to individual `show_usage_*` functions based on argument
- Each `_cmd_*` function supports `-h|--help|help` → calls corresponding `show_usage_*`

---

## Execution Order

Execute todos in order: **1 → 2 → 3 → 4 → 5**

- **Todo 1** (foundation): Exit codes and logging — no dependencies
- **Todo 2** (cleanup): Renames and docker check relocation — depends on Todo 1
- **Todo 3** (reorganization): Section grouping — depends on Todo 2
- **Todo 4** (major restructure): CLI conversion + `_cmd_*` pattern — depends on Todo 3
- **Todo 5** (new feature): Help system — depends on Todo 4

Todos 1 and 2 can potentially be parallelized. Todos 4 and 5 are closely related and could be combined into one wave.

---

## Implementation Notes for Agents

1. **Reference file**: Use `templates/manage.native.tp` as the exact reference for structure, naming, patterns, and formatting. When in doubt, copy the native template's pattern and adapt the implementation for containers.

2. **Preserve container-specific code**: Do not remove or simplify `_get_container_process_info`, `_monitor_container_state`, `__sanitize_input_command`, or docker dependency checks. These are legitimate container-specific features.

3. **Override functions**: `_get_latest_version`, `_download`, `_deploy` are designed to be overridden by `overrides/*.overrides.sh`. Do NOT rename these.

4. **Template variables**: The file contains template placeholders (e.g., `$KGSM_ROOT`). Do not modify those.

5. **No `--internal-stop` issue**: Unlike the native template refactoring, the container template does not have the recursive `$0 --internal-stop` anti-pattern. However, for interface parity with native, add a `_timed_stop` function that wraps `_stop_server` with timeout behavior, but using `docker compose down` timeout semantics instead of the bash `timeout` command.

6. **Docker compose pattern**: All docker compose commands use the pattern `(cd "$instance_working_dir" && docker compose -f "$instance_compose_file" ...)`. Preserve this pattern consistently.

7. **Testing**: Run `shellcheck templates/manage.container.tp` after each significant change. Run `./tests/run.sh unit` to verify no test regressions.

8. **Callers already updated**: All files that call manage scripts were already updated to use the subcommand interface during the native template refactoring. No caller changes are needed — just making the container template conform.

9. **`_stop_server` flag semantics**: Convert from string `"true"`/`"false"` to numeric `0`/`1` to match native template. In `_cmd_stop`, use `local no_save=0; local no_graceful=0` and set to `1` when flags are passed.
