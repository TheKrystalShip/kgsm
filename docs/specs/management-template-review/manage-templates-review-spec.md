# Manage Template Code Review: Feature Parity & Quality Analysis

> **Date**: 2026-03-04  
> **Scope**: `templates/manage.native.tp` and `templates/manage.container.tp`  
> **Reviewers**: 3 independent code review agents  
> **Purpose**: Assess feature parity, code quality, potential bugs, and interface inconsistencies between the two management templates after refactoring.

---

## Executive Summary

The two templates have **100% CLI interface parity** — identical dispatch blocks, identical `_cmd_*` handler signatures, and identical JSON output structure. Internal implementations diverge appropriately for native-vs-container contexts. However, the review found **3 high-severity issues**, **6 medium-severity issues**, and **several low-severity inconsistencies** that should be addressed.

---

## 1. Interface Parity Assessment: ✅ STRONG

| Aspect                          | Status            | Notes                                                         |
| ------------------------------- | ----------------- | ------------------------------------------------------------- |
| Main dispatch block             | ✅ Identical       | Same `case "$command"` structure                              |
| `_cmd_*` handlers (16)          | ✅ 13/16 identical | 3 differ only in implementation (start, attach, help routing) |
| `show_usage_*` functions (12)   | ✅ 6/12 identical  | Remaining 6 have context-appropriate text differences         |
| JSON output (`_get_status`)     | ✅ Identical       | Same fields, nesting, types, null handling                    |
| Exit code constants             | ✅ Identical       | `EC_SUCCESS`, `EC_ERROR`, `EC_MISSING_ARG`, `EC_INVALID_ARG`  |
| Section structure (12 sections) | ✅ Identical       | Same names, same order                                        |
| Color/logging setup             | ✅ Identical       | Same inline color pattern                                     |

---

## 2. High-Severity Issues

### H1: `_print_logs` interface mismatch between templates
**Files**: Both templates  
**Description**: The internal `_print_logs` function has different parameter semantics. Native expects `"true"`/`"false"` for the follow parameter, while container expects `"--follow"`.

- **Native** `_print_logs`: `if [[ "$follow" == "true" ]]`
- **Container** `_print_logs`: `if [[ "$follow" == "--follow" ]]`
- **Container** `_cmd_logs` sets `follow="true"` when parsing `--follow` flag

**Impact**: Container's `logs --follow` is **broken** — the follow feature will never activate because `_cmd_logs` passes `"true"` but `_print_logs` checks for `"--follow"`.

**Recommendation**: Standardize both templates on the boolean `"true"`/`"false"` pattern (native's approach). Fix container's `_print_logs` to check `== "true"`.

---

### H2: `_update` function has invalid docker compose command
**File**: `manage.container.tp` (line ~982)  
**Description**: The command `docker compose run --rm --update` uses `--update` which is not a valid `docker compose run` flag. This line will fail every time.

**Impact**: The `update` command will always produce an error at this step.

**Recommendation**: Remove the invalid line or replace with the correct command for running updates inside the container.

---

### H3: Inconsistent boolean check for `instance_is_steam_account_required`
**File**: `manage.native.tp` (lines 877 and 972)  
**Description**: This variable is checked as a string (`== "true"`) on line 877 but as a number (`-ne 0`) on line 972. If the config sets this to `"true"` (string), the numeric comparison will fail with a bash error.

**Impact**: Steam account authentication may be silently skipped during downloads depending on how the config value is set.

**Recommendation**: Use consistent string comparison (`== "true"`) in both locations.

---

## 3. Medium-Severity Issues

### M1: Security disparity — input sanitization missing in native template
**Files**: Container has `__sanitize_input_command`; native has no equivalent  
**Description**: Container template validates user input commands (checking for dangerous characters like `;`, `&`, `|`, `` ` ``, `$()`, etc.) and limits command length to 1000 characters. Native template writes user input directly to the socket FIFO without any sanitization.

**Impact**: Potential command injection risk in native template if game server console interpreters evaluate shell metacharacters. The risk level depends on how game servers parse FIFO input.

**Recommendation**: Either add `__sanitize_input_command` to native template, or document why socket-based I/O is inherently safe (FIFO pipes do not interpret shell metacharacters — the game server reads raw text).

---

### M2: `_disable_upnp` behavioral difference
**Files**: Both templates  
**Description**: Container's `_disable_upnp` has an early return if UPnP is not currently enabled. Native's does not — it always attempts `upnpc -f`, potentially producing error messages when UPnP is already disabled.

**Recommendation**: Add the `_is_upnp_enabled` guard to native template for idempotent behavior.

---

### M3: Missing error handling in `_cmd_restart` (container)
**File**: `manage.container.tp`  
**Description**: `_cmd_restart` calls `_timed_stop` then `_start_background` sequentially without checking if the stop succeeded. If stop fails, it proceeds to start anyway.

**Recommendation**: Add `|| return $?` after the `_timed_stop` call.

---

### M4: Missing error handling in `_download` (container)
**File**: `manage.container.tp`  
**Description**: `docker compose pull` runs without error checking — always returns success even if the pull fails.

**Recommendation**: Wrap in `if ! (...); then __print_error ...; return 1; fi`.

---

### M5: Potential command injection via `envsubst` in native
**File**: `manage.native.tp` (line ~599)  
**Description**: `envsubst` is used to expand variables in `instance_executable_arguments`, then the result is executed with `SC2086` disabled. If config values contain `$()` or backticks, they could be executed.

**Recommendation**: Validate that `instance_executable_arguments` doesn't contain dangerous patterns, or use a whitelist of allowed variable names for `envsubst`.

---

### M6: `tar -xzf "$source" .` — incorrect tar syntax
**File**: `manage.native.tp` (line ~1225)  
**Description**: Passing `.` as an argument to `tar -xzf` is non-standard. The `.` is treated as a member/path filter, not a target directory. While this may work on GNU tar, it's fragile.

**Recommendation**: Remove the trailing `.` (extract to current directory which is already set by the preceding `cd`), or use `tar -xzf "$source" -C "$instance_install_dir"`.

---

## 4. Low-Severity Issues

### L1: UPnP error message inconsistencies
**Files**: Both templates  
**Details**:
- Native says `set 'enable_port_forwarding' to 'false' in $CONFIG_FILE`
- Container says `set 'enable_port_forwarding' to 0 in $0` (one place) and `set 'instance_enable_port_forwarding' to 'false' in $0` (another)
- Container has typo: "these message" → should be "these messages"
- Variable name and target file are inconsistent

### L2: `_cmd_download` version initialization
**File**: `manage.container.tp`  
**Description**: Initializes `local version=0` instead of `local version=""`. The value `0` could theoretically be treated as a valid version.

### L3: `_is_active` uses `__print_info` for output
**Files**: Both templates  
**Description**: The `_is_active` function uses `__print_info "Active"` / `__print_info "Inactive"` for its output, which adds `[INFO]` prefix and source location. This pollutes output when callers need clean status text. Most callers already redirect output to `/dev/null`.

### L4: `_compare_versions` inverted return code semantics
**Files**: Both templates  
**Description**: Returns `1` (shell failure) when versions are equal (no update needed), `0` (shell success) when update is available. While this works, the inverted semantics are confusing.

**Recommendation**: Invert the exit codes, so that exit code `0` (shell success) indicates a new update is available and exit code `1` (shell failure) indicated no update.

### L5: `_cmd_attach` doesn't suppress `_is_active` output
**File**: `manage.container.tp`  
**Description**: Calls `_is_active` without redirecting output, which prints status messages before the attach attempt.

**Recommendation**: Redirect `_is_active` output before attaching.

### L6: `return 0` / `return 1` used in helper functions instead of `$EC_SUCCESS` / `$EC_ERROR`
**Files**: Both templates  
**Description**: Over 50 instances in each file. While functionally correct, reduces consistency.

### L7: Socket file write operators inconsistent (native)
**File**: `manage.native.tp`  
**Description**: Some socket writes use `>` (truncate) and others use `>>` (append). For FIFOs both are equivalent, but the inconsistency suggests unclear intent.

**Recommendation**: Use `>>` (append) for all writes to the FIFO.

---

## 5. Functions Unique to Each Template

### Container-only (3) — All justified:
| Function                      | Purpose                              | Justification                               |
| ----------------------------- | ------------------------------------ | ------------------------------------------- |
| `__sanitize_input_command`    | Input validation/security            | Docker exec requires stricter input control |
| `_get_container_process_info` | Container stats via `docker stats`   | Container-specific monitoring               |
| `_monitor_container_state`    | Container state via `docker inspect` | Container-specific monitoring               |

### Native-only (1) — Justified:
| Function              | Purpose                             | Justification                       |
| --------------------- | ----------------------------------- | ----------------------------------- |
| `_attach_to_instance` | Interactive console via FIFO/screen | Native process attachment mechanism |

---

## 6. Known Technical Debt

### Container `_get_latest_version` is a stub
Returns `"latest"` always. Comment documents intent to add Docker Hub API / registry checking. This means:
- `version --compare` is meaningless for containers
- `status` always shows `updates_available: false`
- This is documented and intentional

---

## 7. Recommendations Summary

| Priority     | Issue                                       | Action                                                           |
| ------------ | ------------------------------------------- | ---------------------------------------------------------------- |
| **Critical** | H1: `_print_logs` interface mismatch        | Fix container's `_print_logs` to check `"true"` not `"--follow"` |
| **Critical** | H2: Invalid `docker compose run --update`   | Remove or replace the invalid command                            |
| **High**     | H3: Inconsistent boolean check (steam auth) | Standardize on string comparison                                 |
| **High**     | M1: Missing input sanitization in native    | Add `__sanitize_input_command` or document why safe              |
| **Medium**   | M2: `_disable_upnp` idempotency             | Add `_is_upnp_enabled` guard to native                           |
| **Medium**   | M3: `_cmd_restart` error handling           | Add stop failure check                                           |
| **Medium**   | M4: `_download` error handling              | Add pull failure check                                           |
| **Medium**   | M5: `envsubst` injection risk               | Validate arguments before expansion                              |
| **Medium**   | M6: tar syntax                              | Remove trailing `.` argument                                     |
| **Low**      | L1-L7                                       | Various consistency improvements                                 |

---

## 8. Overall Verdict

**The refactoring achieved its primary goal**: both templates present an **identical CLI interface** and follow the **same internal structure** (12 sections, `_cmd_*` pattern, help system, exit codes). The differences that exist are either:

1. **Appropriate runtime divergences** (docker compose vs. direct process management)
2. **Bugs to fix** (H1, H2, H3 — actionable items)
3. **Security gaps to evaluate** (M1 — design decision needed)

The templates are production-ready with the caveat that the high-severity bugs (especially H1: broken `logs --follow` in container) should be fixed before deployment.
