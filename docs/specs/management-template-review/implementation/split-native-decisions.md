# Phase 1a: Split `manage.native.tp` — Implementation Decisions

**Date**: 2025-03  
**Status**: Complete  
**Task**: Split `templates/manage.native.tp` into 14 module files under `templates/manage.native.d/`

---

## Exact Line Ranges Used

The original file is 1993 lines. Section boundaries were identified using the `# =============================================================================` markers in the file.

| Module            | Lines from original     | Lines in module | Notes |
| ----------------- | ----------------------- | --------------- | ----- |
| `00-header.sh`    | 1–18                    | 18              | Shebang, autogen notice, shellcheck disable directives, trailing blank line |
| `01-config.sh`    | 19–137                  | 119             | CONFIGURATION AND INITIALIZATION section |
| `02-help.sh`      | 138–484                 | 347             | HELP SYSTEM section |
| `03-lifecycle.sh` | 485–829                 | 345             | PROCESS MANAGEMENT section |
| `04-io.sh`        | 830–900                 | 71              | SERVER I/O section |
| `05-version.sh`   | 901–981                 | 81              | VERSION MANAGEMENT section |
| `06-download.sh`  | 982–1038                | 57              | DOWNLOAD AND DEPLOYMENT header + `_download()` + trailing blank |
| `07-deploy.sh`    | 1039–1065               | 27              | `_deploy()` function + trailing blank |
| `08-backup.sh`    | 1117–1296               | 180             | BACKUP MANAGEMENT section |
| `09-network.sh`   | 1297–1357               | 61              | NETWORK (UPnP) section |
| `10-logging.sh`   | 1358–1402               | 45              | LOGGING section |
| `11-status.sh`    | 1403–1601               | 199             | STATUS section |
| `12-commands.sh`  | 1602–1839 + 1066–1116 + 1840–1895 | 345 | COMMAND HANDLERS section + relocated `_update()` |
| `13-dispatch.sh`  | 1896–1993               | 98              | MAIN DISPATCH section |

**Total module lines: 1993** (same as original, no content is lost)

---

## Deviations from Spec's Approximate Line Numbers

The spec provided approximate line numbers. The actual boundaries matched very closely, with the following notes:

- **`06-download.sh` ends at 1038, not 1037**: Line 1038 is the blank line between `_download()` and `_deploy()`. This blank line is included in `06-download.sh` so that `07-deploy.sh` opens cleanly with `function _deploy()` at line 1.
- **`07-deploy.sh` ends at 1065, not 1064**: Line 1065 is the blank line after `_deploy()`. Included in `07-deploy.sh` to preserve the trailing blank separator.
- **`07-deploy.sh` does NOT include lines 1065–1116**: The spec approximate range `1039–1064` for `07-deploy.sh` excluded `_update()`. Lines 1066–1116 contain `_update()` which is moved to `12-commands.sh` (see below).
- **`08-backup.sh` starts at 1117, not 1065**: Because `_update()` was moved out, `08-backup.sh` starts directly at the `# === BACKUP MANAGEMENT` section marker.

---

## `_update()` Placement

**Original location**: Lines 1066–1116 (after `_deploy()`, inside the DOWNLOAD AND DEPLOYMENT section).

**Decision**: Moved to `12-commands.sh`, inserted between `_cmd_deploy()` (ends at line 1838 original / position 238 in 12-commands.sh) and `_cmd_update()` (starts at line 1840 original).

**Rationale** (per spec): `_update()` is a thin orchestrator — it calls `_get_latest_version()`, `_download()`, `_deploy()`, and `_save_version()` in sequence, then delegates to `_cmd_update()` which is a one-liner (`_update`). Placing `_update()` immediately before `_cmd_update()` in `12-commands.sh` groups the "update workflow" logic together with its command handler. The `_download()` and `_deploy()` primitives remain in their own modules.

**12-commands.sh construction**:
```
original lines 1602–1839   (COMMAND HANDLERS section header + _cmd_start through _cmd_deploy)
original lines 1066–1116   (_update() function, relocated here)
original lines 1840–1895   (_cmd_update through _cmd_upnp)
```

---

## Edge Cases and Notes

### Section Header Ownership
Each section's `# =============================================================================` / section name / `# =============================================================================` block is included at the **start of its owning module**:
- `01-config.sh` opens with the `# CONFIGURATION AND INITIALIZATION` header
- `02-help.sh` opens with the `# HELP SYSTEM` header
- etc.

The `00-header.sh` module contains only the shebang, autogen comment, and `shellcheck disable` directives — it has no section header of its own.

### DOWNLOAD AND DEPLOYMENT Section Split
The original file has a single `# DOWNLOAD AND DEPLOYMENT` section header at line 982. Per the spec, this section is split across two modules (`06-download.sh` and `07-deploy.sh`). The section header is retained in `06-download.sh`, which is the first module of the section. `07-deploy.sh` has no section header (it begins directly with `function _deploy()`).

### Trailing Blank Lines at Boundaries
Each module file ends with the blank line that precedes the next section's `# ===` header (or ends naturally at EOF for `13-dispatch.sh`). This ensures that direct concatenation with `cat` reproduces the content without needing explicit newline separators between modules.

### `trap` Statement in `03-lifecycle.sh`
The `trap _cleanup_on_exit INT TERM` statement at line 828 is top-level executable code. Per the spec, modules 02–11 should define functions only. However, this `trap` is part of the PROCESS MANAGEMENT section's setup and is functionally required alongside `_cleanup_on_exit()`. It is kept in `03-lifecycle.sh` for Phase 1a (preserving grouping), with a note that Phase 1b may consider whether it should move to `13-dispatch.sh` or `01-config.sh`.

---

## Concatenation Verification

Running:
```bash
cat templates/manage.native.d/{00-header.sh,01-config.sh,02-help.sh,03-lifecycle.sh,\
04-io.sh,05-version.sh,06-download.sh,07-deploy.sh,08-backup.sh,09-network.sh,\
10-logging.sh,11-status.sh,12-commands.sh,13-dispatch.sh} > /tmp/concat.sh

diff templates/manage.native.tp /tmp/concat.sh
```

**Result**: The diff shows **exactly one structural change**:

```diff
1066,1116d1065
< function _update() {
< ...51 lines of _update() body...
< }
<
1837a1787,1837
> }
>
> function _update() {
> ...51 lines of _update() body (identical content)...
```

The `_update()` function (51 lines) is the **only** difference — it has been relocated from the DOWNLOAD AND DEPLOYMENT section to the COMMAND HANDLERS section, placed between `_cmd_deploy()` and `_cmd_update()`. All 1993 lines of content are preserved; nothing is added or removed.

This single structural change is the intentional deviation mandated by the spec. All other content is byte-identical.
