# Manage Templates: Post-Refactor Code Review Findings

> **Date**: 2026-03-05
> **Scope**: `templates/manage.native.tp` and `templates/manage.container.tp`
> **Context**: Code review performed after applying all recommendations from `manage-templates-review-spec.md`. These are NEW findings not covered by the original spec.

---

## Container Template (`manage.container.tp`)

### 🔴 Critical

#### C-C1: `__print_error` called before it is defined
**Lines:** 113–119
**Description:** The top-level docker dependency checks call `__print_error` at lines 113 and 118, but `__print_error` is not defined until line 144 (after color setup and function definitions). If docker or docker-compose is missing at script load time, bash emits `command not found: __print_error` instead of the intended error message.

**Recommendation:** Move `__print_*` function definitions above the docker dependency checks, or replace those two calls with plain `echo "ERROR: ..." >&2`.

---

#### C-C2: `command -v docker compose` is broken for Docker Compose v2
**Lines:** 117–120
**Description:** Docker Compose v2 is a CLI plugin, not a standalone binary. `command -v docker compose` looks up `docker` and `compose` as separate executables. Since `compose` is not a standalone binary on v2 installations, this check always fails, causing every container instance script to abort with "Docker Compose is not installed" even on working systems.

**Recommendation:** Replace with `docker compose version >/dev/null 2>&1` to actually invoke the plugin.

---

### 🟠 High

#### C-H1: `_update` else-branch starts the container then immediately stops it
**Lines:** 979–983
**Description:** When the server is not active at update time, the code runs `docker compose up -d` followed immediately by `docker compose down`. The intent comment says "Just recreate without starting," but `up -d` actually starts containers. Any startup side effects (entrypoint scripts, port binds) occur in the window between the two commands. Neither command has error checking.

**Recommendation:** Replace with `docker compose create --force-recreate` (recreates without starting), or remove the else-branch entirely since the preceding `pull` already stages the new image.

---

#### C-H2: `_print_logs` follow mode orphans background process on SIGINT
**Lines:** 1265–1268
**Description:** The follow-mode implementation backgrounds `docker compose logs -f` and waits on its PID. The `_cleanup_on_exit` trap does not kill `$tail_pid`. When the user presses Ctrl+C, the background subshell becomes orphaned and continues streaming output after the prompt returns.

**Recommendation:** Run the `docker compose logs -f` command in the foreground (remove `&`, `tail_pid=$!`, and `wait "$tail_pid"`). Foreground execution naturally propagates SIGINT.

---

### 🟡 Medium

#### C-M1: `_cmd_attach` hardcodes `$instance_name` as Docker Compose service name
**Line:** 1717
**Description:** `docker compose exec "${instance_name}" /bin/sh` uses the instance name as the service name. Docker Compose service names are defined in `docker-compose.yml` and are not guaranteed to match the instance name (e.g., `game-server`, `app`). All other `docker compose` commands in the file operate at the project level.

**Explanation**: During the instance install procedure, the "$instance_name" values is assigned to the container for that instance, guaranteeing a unique container name and also a unique instance name for KGSM.

**Recommendation:** Introduce a config variable (e.g., `instance_compose_service`) for the service name, or document the coupling requirement.

---

#### C-M2: `_update` does not check if `docker compose pull` succeeded
**Line:** 975
**Description:** `docker compose pull` at line 975 (in `_update`) is not wrapped in error checking. If the pull fails, the function silently continues to recreate/restart with the old image and writes `"latest"` to the version file, falsely marking it as updated. (Note: `_download` at line 946 was correctly fixed, but `_update` was missed.)

**Recommendation:** Wrap in `if ! (...); then __print_error ...; return $EC_ERROR; fi`.

---

### 🔵 Low

#### C-L1: `_restore_backup` declares `local backup_version` twice
**Lines:** 1070, 1081
**Description:** First declaration at line 1070 is dead code; second at line 1081 re-initializes to `"unknown"`. Harmless but confusing.

**Recommendation:** Remove the first `local backup_version` at line 1070.

---

#### C-L2: `tar -xzf "$source" .` uses fragile member filter
**Line:** 1138
**Description:** The trailing `.` tells GNU tar to extract only members whose paths begin with `./`. This works only when the archive was created with `tar -czf output .`. If the archive format changes, extraction silently extracts nothing.

**Recommendation:** Remove the trailing `.` — `tar -xzf "$source"` extracts everything to the current directory.

---

## Native Template (`manage.native.tp`)

### 🔴 Critical

#### N-C1: `__print_error` called before it is defined
**Lines:** 114–117
**Description:** Same issue as C-C1. The top-level config-file existence check calls `__print_error` before the function is defined. If `CONFIG_FILE` is absent, the user sees `bash: __print_error: command not found` instead of the intended diagnostic.

**Recommendation:** Same fix as C-C1.

---

#### N-C2: `help deploy` routes to `show_usage_download` instead of `show_usage_deploy`
**Lines:** 482–484
**Description:** `show_usage_deploy` does not exist. Running `manage.sh help deploy` silently shows Download Command help instead of Deploy Command help.

**Recommendation:** Create a `show_usage_deploy` function, or if deploy and download intentionally share help, rename to `show_usage_download_deploy` and document the coupling.

---

### 🟠 High

#### N-H1: `_cleanup_on_exit` trap missing `EXIT` signal
**Line:** 843
**Description:** The trap is `trap _cleanup_on_exit INT TERM` but the function's own comment says it handles "INT, TERM, and EXIT signals." Normal-exit paths (all `exit $?` calls in the main dispatch) bypass cleanup — PID files are never removed, UPnP is never torn down on clean shutdown.

**Recommendation:** Add `EXIT` to the trap: `trap _cleanup_on_exit INT TERM EXIT`.

---

#### N-H2: `_kill_all_processes` returns early on partial kill failure
**Lines:** 799–803
**Description:** If any child PID has already died between `pgrep` and `kill` (a normal race condition), `kill` returns non-zero and the function aborts before reaching the main process kill at lines 809–816. The server's primary process stays alive.

**Recommendation:** Log a warning but continue to the main-process kill instead of returning `$EC_ERROR`.

---

#### N-H3: `_cmd_restart` doesn't abort if stop fails
**Lines:** 1689–1690
**Description:** `_timed_stop 0 0` is not checked for failure. If the stop fails, `_start_background` launches a second server process sharing the same PID file, socket, and log file with the first.

**Recommendation:** Add `|| return $?` after `_timed_stop`: `_timed_stop 0 0 || return $?`.

> **Note:** The previous round of fixes (from `manage-templates-review-spec.md` M3) was applied to container but appears to have not taken effect in native, or the edit was reverted/lost.

---

### 🟡 Medium

#### N-M1: Shell-global INT trap in `_attach_to_instance` persists after function returns
**Line:** 663
**Description:** `trap '_stop_server && echo "" && return $EC_SUCCESS' INT` is shell-global. After the user detaches from the console, this trap remains active, overriding the `_cleanup_on_exit` trap. Any subsequent Ctrl+C silently calls `_stop_server` on a live server the user didn't intend to stop.

**Recommendation:** Save and restore the previous INT trap:
```bash
local old_int_trap
old_int_trap=$(trap -p INT)
trap '_stop_server && echo ""' INT
# ... function body ...
eval "$old_int_trap"
```

---

#### N-M2: `_get_status` issues two SteamCMD queries per invocation
**Lines:** 1466–1467
**Description:** `_compare_versions` internally calls `_get_latest_version`, then `_get_status` calls `_get_latest_version` again on success. This doubles SteamCMD latency and introduces a race where the second call could return a different version.

**Recommendation:** Capture `_compare_versions` output:
```bash
if latest_version=$(_compare_versions 2>/dev/null); then
  updates_available="true"
else
  latest_version="$current_version"
fi
```

---

#### N-M3: Backup version parsing fails for instance names containing hyphens
**Lines:** 1225, 1231–1233
**Description:** Backup filenames use `$instance_name-$version-$datetime.backup`. For `my-game-server`, the regex and array fallback both extract the wrong field as the version. After restore, `_save_version "unknown"` clobbers the real version, breaking subsequent update comparisons.

**Recommendation:** Strip the known instance name prefix before parsing: `backup_filename="${backup_filename#"${instance_name}-"}"`, then take the first `-`-delimited token as the version.

---

#### N-M4: `local backup_version` declared twice in `_restore_backup`
**Lines:** 1211, 1222
**Description:** Same pattern as C-L1 — dead first declaration, effective second declaration. Harmless but misleading.

**Recommendation:** Remove the first declaration at line 1211.

---

### 🔵 Low

#### N-L1: Orphaned comment block between EC_* constants and section header
**Lines:** 44–46
**Description:** A partial comment ("…by ensuring" with no conclusion) is stranded outside a section header. Reads as a documentation fragment from a refactor.

**Recommendation:** Complete the sentence and attach it to the relevant function, or remove the orphaned lines.

---

#### N-L2: `help kill`, `help save`, `help input`, `help is-active` show generic usage
**Lines:** 488–490
**Description:** These four commands have no dedicated `show_usage_*` function. `help kill` dumps the full 40-line command listing instead of focused help.

**Recommendation:** Create minimal `show_usage_kill`, `show_usage_save`, `show_usage_input`, `show_usage_is_active` functions.

---

## Cross-Template Issues

### Shared: `__print_error` before definition (C-C1, N-C1)
Both templates have the same pattern of calling logging functions before they are defined. Should be fixed consistently in both files.

### Shared: Duplicate `local backup_version` (C-L1, N-M4)
Same dead-code pattern in `_restore_backup` in both templates. Remove first declaration in both.

---

## Previous Spec Verification

All recommendations from `manage-templates-review-spec.md` were verified:

| Original Finding                          | Container | Native                             |
| ----------------------------------------- | --------- | ---------------------------------- |
| H1: `_print_logs` interface mismatch      | ✅ Fixed   | N/A                                |
| H2: Invalid `docker compose run --update` | ✅ Fixed   | N/A                                |
| H3: Inconsistent boolean check (steam)    | N/A       | ✅ Fixed                            |
| M1: Missing input sanitization            | N/A       | ✅ Added                            |
| M2: `_disable_upnp` idempotency           | N/A       | ✅ Added                            |
| M3: `_cmd_restart` error handling         | ✅ Fixed   | ✅ Fixed (was missing, now applied) |
| M4: `_download` error handling            | ✅ Fixed   | N/A                                |
| M5: `envsubst` injection risk             | N/A       | ✅ Added                            |
| M6: tar syntax                            | N/A       | ✅ Fixed                            |
| L1: UPnP error messages                   | ✅ Fixed   | ✅ Consistent                       |
| L2: Version init `0` → `""`               | ✅ Fixed   | N/A                                |
| L3: `_is_active` clean output             | ✅ Fixed   | ✅ Fixed                            |
| L4: `_compare_versions` return codes      | ✅ Fixed   | ✅ Fixed                            |
| L5: `_cmd_attach` suppress output         | ✅ Fixed   | N/A                                |
| L6: `$EC_SUCCESS`/`$EC_ERROR` constants   | ✅ Applied | ✅ Applied                          |
| L7: Socket write operators                | N/A       | ✅ Standardized                     |

---

## Recommendations Summary

| Priority     | ID         | Template  | Issue                                    | Action                                       |
| ------------ | ---------- | --------- | ---------------------------------------- | -------------------------------------------- |
| **Critical** | C-C1, N-C1 | Both      | `__print_error` called before defined    | Move function defs above or use `echo`       |
| **Critical** | C-C2       | Container | `command -v docker compose` broken on v2 | Use `docker compose version`                 |
| **Critical** | N-C2       | Native    | `help deploy` routes to wrong function   | Create `show_usage_deploy`                   |
| **High**     | C-H1       | Container | `_update` start-then-stop anti-pattern   | Use `docker compose create --force-recreate` |
| **High**     | C-H2       | Container | Follow-mode orphans background process   | Run in foreground                            |
| **High**     | N-H1       | Native    | Trap missing `EXIT` signal               | Add `EXIT` to trap                           |
| **High**     | N-H2       | Native    | `_kill_all_processes` early return       | Warn and continue                            |
| **High**     | N-H3       | Native    | `_cmd_restart` missing stop check        | ~~Add `\|\| return $?`~~ **FIXED**           |
| **Medium**   | C-M1       | Container | Hardcoded service name in attach         | Add config var or document                   |
| **Medium**   | C-M2       | Container | `_update` pull not error-checked         | Wrap in `if !`                               |
| **Medium**   | N-M1       | Native    | INT trap persists after attach           | Save/restore trap                            |
| **Medium**   | N-M2       | Native    | Double SteamCMD query in status          | Capture `_compare_versions` output           |
| **Medium**   | N-M3       | Native    | Backup version parsing with hyphens      | Strip instance name prefix                   |
| **Medium**   | N-M4, C-L1 | Both      | Duplicate `local backup_version`         | Remove first declaration                     |
| **Low**      | C-L2       | Container | `tar` fragile `.` member filter          | Remove trailing `.`                          |
| **Low**      | N-L1       | Native    | Orphaned comment block                   | Remove or complete                           |
| **Low**      | N-L2       | Native    | Missing `show_usage_*` for 4 commands    | Create minimal help functions                |
