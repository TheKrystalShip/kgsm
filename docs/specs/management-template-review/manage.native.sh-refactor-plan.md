# Refactoring Plan: `templates/manage.native.tp`

## Problem Statement

`templates/manage.native.tp` (1533 lines) is a standalone template that generates per-instance management scripts. It has grown organically and does not follow the organizational patterns, argument handling conventions, and code cleanliness standards established by `kgsm.sh` and the `commands/*.sh` scripts. This plan describes a comprehensive refactoring to bring it up to par.

**Important constraint**: This template generates **standalone scripts** that run independently in instance directories. It cannot depend on `core/bootstrap.sh` or the KGSM module system. Therefore, some self-contained infrastructure (config parsing, logging) must remain. However, the organization, argument handling, and code quality can be dramatically improved to match the command scripts' patterns.

---

## Analysis Summary

### Current Issues

#### 1. Inconsistent Argument Handling (Critical)
- **Mixed CLI style**: Some operations use flag-style (`--is-active`, `--status`, `--logs`, `--version`, `--kill`, `--save`, `--input`, `--download`, `--deploy`, `--update`, `--create-backup`, `--restore-backup`, `--list-backups`, `--enable-upnp`, `--disable-upnp`) while `start`, `stop`, and `attach` use subcommand-style. Commands use consistent subcommand-style throughout.
- **Flat monolithic parser**: Lines 1292-1531 are a single `while/case` loop that mixes argument parsing with dispatch. Commands use `command="${1:-}"; shift; case "$command"` → `_cmd_*` pattern.
- **No `_cmd_*` function pattern**: Logic is called directly from the argument parser instead of through dedicated command handler functions.
- **`--internal-stop` leak**: Internal implementation detail for timeout mechanism is exposed in the public CLI interface.

#### 2. Duplicated Logging System (Medium)
- Lines 165-209 reimplement `__print_success`, `__print_info`, `__print_error`, `__print_warning` with custom color detection. While self-containment is necessary, the implementation can be simplified and the redundant `SUCCESS`/`INFO`/`ERROR`/`WARNING` intermediate variables (lines 165-168) are unnecessary.

#### 3. Missing Help System (Medium)
- Has a simple `usage()` function (lines 109-163) instead of the standard rich, formatted `show_usage()` + per-command `show_usage_<cmd>()` pattern.
- Missing `help [command]` subcommand.
- No per-command help (e.g., `help start`, `help backup`, `help version`).

#### 4. No Functional Grouping (Medium)
Functions are defined in no particular order. Standard commands group related functions with section comments. Current function order:
- `_rotate_log_file` (line 218) — logs
- `_enable_upnp` (line 243) — network
- `_disable_upnp` (line 267) — network
- `_is_upnp_enabled` (line 292) — network
- `_cleanup_on_exit` (line 299) — lifecycle
- `_start` (line 324) — lifecycle
- `_attach_to_instance` (line 341) — lifecycle
- `_start_background` (line 390) — lifecycle
- `_kill_all_processes` (line 465) — lifecycle
- `_stop_server` (line 518) — lifecycle
- `_timed_stop` (line 568) — lifecycle
- `_send_save_command` (line 581) — I/O
- `_send_input` (line 599) — I/O
- `_is_active` (line 611) — lifecycle
- `_print_logs` (line 651) — logs
- `_update` (line 679) — deployment
- `_create_backup` (line 730) — backup
- `_restore_backup` (line 803) — backup
- `_list_backups` (line 895) — backup
- `_get_installed_version` (line 906) — version
- `_get_latest_version` (line 913) — version
- `_compare_versions` (line 952) — version
- `_save_version` (line 972) — version
- `_download` (line 983) — deployment
- `_download_wrapper` (line 1037) — deployment
- `_deploy` (line 1055) — deployment
- `_deploy_wrapper` (line 1083) — deployment
- `_get_status` (line 1096) — status

#### 5. Dead/Redundant Code (Low)
- **`_download_wrapper` (lines 1037-1053)**: Trivial wrapper that adds print messages around `_download`. The wrapper adds no meaningful logic.
- **`_deploy_wrapper` (lines 1083-1094)**: Same issue — trivial wrapper around `_deploy`.
- **Double argument parsing for `--logs`**: The main parser (lines 1416-1451) parses log options and converts them to positional args, then `_print_logs` (lines 651-677) parses them AGAIN as flags. This is redundant.

#### 6. Inconsistent Exit Codes (Low)
- Uses hardcoded `1` instead of domain-specific exit codes throughout (lines 101, 216, 1310, 1334, 1360, 1411, 1429, 1438, 1471, 1489, 1527).
- The standalone script can't use `EC_*` constants from `core/errors.sh`, but it should define its own local constants for clarity and consistency.

#### 7. `_stop_server` Bug (Low)
- Lines 541 and 545 use `[[ ! "$no_save" ]]` and `[[ ! "$no_graceful" ]]` which test string truthiness, not numeric value. Since `no_save` is set to `0` (a non-empty string), `[[ ! "0" ]]` evaluates to `false`, meaning the save and graceful shutdown are NEVER executed. Should be `[[ "$no_save" -eq 0 ]]` and `[[ "$no_graceful" -eq 0 ]]`.

---

## Refactoring Plan

### Todo 1: Unify CLI to subcommand-style with `_cmd_*` pattern
**Description**: Convert all `--flag` style operations to subcommand-style and route through `_cmd_*` handler functions. Replace the flat `while/case` argument loop with the standard `command="${1:-}"; shift; case "$command"` dispatch pattern.

**New CLI interface**:
```
manage.sh <command> [arguments] [options]

Commands:
  start [-d, --detached]      Start the server
  stop [--no-save] [--no-graceful]  Stop the server
  restart                     Restart the server
  attach                      Attach to running server console
  kill                        Kill the server process
  save                        Save the current game state
  input <command>             Send a command to the server
  is-active                   Check if the server is running
  status [--json] [--fast]    Display runtime status
  logs [--follow] [--tail N]  View server logs
  version [--latest|--compare|--save <ver>]  Version management
  download [version]          Download game server files
  deploy                      Deploy files from temp directory
  update                      Update to latest version
  backup create               Create a backup
  backup restore <source>     Restore a backup
  backup list                 List available backups
  upnp enable                 Enable UPnP port forwarding
  upnp disable                Disable UPnP port forwarding
  help [command]              Display help information
```

**Changes**:
- Remove `--` prefix from all top-level commands
- Create `_cmd_start`, `_cmd_stop`, `_cmd_restart`, `_cmd_attach`, `_cmd_kill`, `_cmd_save`, `_cmd_input`, `_cmd_is_active`, `_cmd_status`, `_cmd_logs`, `_cmd_version`, `_cmd_download`, `_cmd_deploy`, `_cmd_update`, `_cmd_backup`, `_cmd_upnp`, `_cmd_help` functions
- Each `_cmd_*` function handles its own argument parsing (per the command pattern)
- Remove `--internal-stop` from public interface; make `_timed_stop` call `_stop_server` directly instead of recursively invoking `$0`
- Replace bottom-of-file `while/case` with top-level `case "$command"` dispatch

### Todo 2: Add comprehensive help system
**Description**: Implement `show_usage()` + per-command `show_usage_<cmd>()` pattern matching the command scripts. Add `help [command]` subcommand with `_cmd_help`.

**Changes**:
- Rename `usage()` to `show_usage()` and reformat with ANSI formatting (UNDERLINE, BOLD, END) matching commands
- Create `show_usage_start`, `show_usage_stop`, `show_usage_logs`, `show_usage_version`, `show_usage_backup`, `show_usage_status`, `show_usage_upnp` etc.
- Each `_cmd_*` function supports `-h|--help|help` → calls corresponding `show_usage_*`
- Add `_cmd_help` that dispatches to individual usage functions

### Todo 3: Group functions by domain with section comments
**Description**: Reorganize all functions into logical sections with clear section header comments, matching the style used in command scripts.

**Proposed section order**:
```bash
# =============================================================================
# CONFIGURATION AND INITIALIZATION
# =============================================================================
# __validate_config_key, __source_instance_config, color setup, logging functions

# =============================================================================
# HELP SYSTEM
# =============================================================================
# show_usage, show_usage_start, show_usage_stop, etc.

# =============================================================================
# PROCESS MANAGEMENT
# =============================================================================
# _is_active, _start, _start_background, _attach_to_instance,
# _stop_server, _timed_stop, _kill_all_processes, _cleanup_on_exit

# =============================================================================
# SERVER I/O
# =============================================================================
# _send_input, _send_save_command

# =============================================================================
# VERSION MANAGEMENT
# =============================================================================
# _get_installed_version, _get_latest_version, _compare_versions, _save_version

# =============================================================================
# DOWNLOAD AND DEPLOYMENT
# =============================================================================
# _download, _deploy, _update

# =============================================================================
# BACKUP MANAGEMENT
# =============================================================================
# _create_backup, _restore_backup, _list_backups

# =============================================================================
# NETWORK (UPnP)
# =============================================================================
# _enable_upnp, _disable_upnp, _is_upnp_enabled

# =============================================================================
# LOGGING
# =============================================================================
# _rotate_log_file, _print_logs

# =============================================================================
# STATUS
# =============================================================================
# _get_status

# =============================================================================
# COMMAND HANDLERS
# =============================================================================
# _cmd_start, _cmd_stop, _cmd_restart, etc.

# =============================================================================
# MAIN DISPATCH
# =============================================================================
# Top-level case statement
```

### Todo 4: Remove dead/redundant code
**Description**: Eliminate unnecessary wrapper functions and duplicated argument parsing.

**Changes**:
- **Remove `_download_wrapper`**: Inline the success/error messages into `_cmd_download` (the new command handler), call `_download` directly.
- **Remove `_deploy_wrapper`**: Same approach — inline messages into `_cmd_deploy`, call `_deploy` directly.
- **Remove `_update`'s wrappers usage**: `_update` currently calls `_download_wrapper` and `_deploy_wrapper`. Change to call `_download` and `_deploy` directly.
- **Fix `_print_logs` double-parsing**: The `_cmd_logs` handler will parse args once and pass clean positional parameters to `_print_logs` (follow_flag, line_count), removing the internal arg parsing from `_print_logs`.

### Todo 5: Simplify logging infrastructure
**Description**: Clean up the self-contained logging system while preserving standalone capability.

**Changes**:
- Remove intermediate `SUCCESS`/`INFO`/`ERROR`/`WARNING` variables (lines 165-168, 188-191). Use the color codes directly in the `__print_*` functions.
- Simplify color detection block to be more concise.
- Ensure format matches `core/logging.sh` output style as closely as possible.

### Todo 6: Fix `_stop_server` bug and use consistent exit codes
**Description**: Fix the no_save/no_graceful boolean check bug and define local exit code constants for the standalone script.

**Changes**:
- **Fix bug**: Change `[[ ! "$no_save" ]]` to `[[ "$no_save" -eq 0 ]]` (and same for `no_graceful`) in `_stop_server`.
- **Define local exit codes**: Add a local constants section near the top of the file with the most commonly used codes (mirroring `core/errors.sh` naming):
  ```bash
  readonly EC_SUCCESS=0
  readonly EC_ERROR=1
  readonly EC_MISSING_ARG=7
  readonly EC_INVALID_ARG=8
  ```
- Replace all hardcoded `exit 1` with appropriate `EC_*` constants.

### Todo 7: Eliminate `--internal-stop` recursive invocation
**Description**: The `_timed_stop` function currently re-invokes `$0 --internal-stop` via `timeout`. This is an anti-pattern that leaks internal implementation into the CLI. Refactor to call `_stop_server` directly within the timeout mechanism.

**Changes**:
- Replace `timeout ... "$0" --internal-stop` with a subshell-based timeout: `timeout "$instance_stop_command_timeout_seconds" bash -c '_stop_server "$@"'` or use the `timeout` builtin with a function call.
- Remove the `--internal-stop` case from the argument parser entirely.
- If the timeout approach requires exported functions, add `export -f _stop_server _kill_all_processes _disable_upnp _is_active _send_save_command` etc.

---

## Execution Notes for Agent

1. **Order**: Execute todos in order 6 → 5 → 4 → 3 → 7 → 1 → 2 (fix bugs first, then clean up, then restructure, then add new features).
2. **Testing**: Run `shellcheck templates/manage.native.tp` after each significant change. The file is a template, so it won't execute directly, but shellcheck can catch syntax issues.
3. **Preserve overridability**: Functions like `_get_latest_version`, `_download`, `_deploy` are designed to be overridden by game-specific `overrides/*.overrides.sh` files. Do NOT rename these functions — only rename functions that are purely internal.
4. **Template variables**: The file contains template placeholders. Do not modify those.
5. **The `_timed_stop` refactor (Todo 7)** is the trickiest part. The current design re-invokes the entire script to get a clean process for timeout. The replacement needs to handle function availability in subshells carefully.
