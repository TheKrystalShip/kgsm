# Split Container Template — Implementation Decisions

**Date**: 2026-03-06
**Task**: Phase 1b — Split `templates/manage.container.tp` into 14 module files in `templates/manage.container.d/`

## Summary

The monolithic `templates/manage.container.tp` (2016 lines) was split into 14 numbered module
files in `templates/manage.container.d/`. The split follows section comment markers in the
original file (`# ===...===` + section title).

One deliberate deviation from the original ordering was made: `_update()` was moved from the
DOWNLOAD AND DEPLOYMENT section into `12-commands.sh`, immediately before `_cmd_update()`.

---

## Exact Line Ranges Used

| Module           | Description                     | Original Lines | Notes                                         |
|------------------|---------------------------------|---------------|-----------------------------------------------|
| `00-header.sh`   | Shebang, autogen notice, shellcheck disable | 1–15 | Ends with trailing blank line before config section |
| `01-config.sh`   | CONFIGURATION AND INITIALIZATION | 16–138        | Ends with blank line before HELP section      |
| `02-help.sh`     | HELP SYSTEM                      | 139–485       | Ends with blank line before PROCESS section   |
| `03-lifecycle.sh`| PROCESS MANAGEMENT               | 486–773       | Includes `trap _cleanup_on_exit INT TERM` (line 772), ends with trailing blank |
| `04-io.sh`       | SERVER I/O                       | 774–879       | Ends with blank line before VERSION section   |
| `05-version.sh`  | VERSION MANAGEMENT               | 880–917       | Ends with blank line before DOWNLOAD section  |
| `06-download.sh` | DOWNLOAD AND DEPLOYMENT header + `_download()` | 918–938 | Section header shared (no separate DEPLOYMENT section exists in original) |
| `07-deploy.sh`   | `_deploy()` function             | 939–949       | Starts with blank line, ends with trailing blank; `_update()` (950–975) moved out |
| `08-backup.sh`   | BACKUP MANAGEMENT                | 976–1155      | Starts directly with section header           |
| `09-network.sh`  | NETWORK (UPnP)                   | 1156–1216     | Ends with trailing blank                      |
| `10-logging.sh`  | LOGGING                          | 1217–1258     | Ends with trailing blank                      |
| `11-status.sh`   | STATUS                           | 1259–1606     | Ends with trailing blank                      |
| `12-commands.sh` | COMMAND HANDLERS + moved `_update()` | 1607–1862 + 950–975 + 1863–1918 | `_update()` inserted before `_cmd_update()` |
| `13-dispatch.sh` | MAIN DISPATCH                    | 1919–2016     | Includes `command=...` and `case` dispatch to EOF |

**Total lines across all modules**: 2016 (matches original file exactly — no lines dropped)

---

## Deviations from Spec's Approximate Line Numbers

The spec's approximate line ranges matched the actual file exactly:

| Spec Range  | Actual Range | Notes                        |
|-------------|-------------|------------------------------|
| 1–15        | 1–15        | Exact match                  |
| 16–138      | 16–138      | Exact match                  |
| 139–485     | 139–485     | Exact match                  |
| 486–773     | 486–773     | Exact match                  |
| 774–879     | 774–879     | Exact match                  |
| 880–917     | 880–917     | Exact match                  |
| 918–945     | 918–938     | `_download()` ends at 938, not 945 |
| 941–950     | 939–949     | `_deploy()` spans 940–948; 939 is leading blank, 949 is trailing blank |
| 976–1155    | 976–1155    | Exact match                  |
| 1156–1216   | 1156–1216   | Exact match                  |
| 1217–1258   | 1217–1258   | Exact match                  |
| 1259–1606   | 1259–1606   | Exact match                  |
| 1607–1918   | 1607–1918   | Exact match (plus moved `_update()`) |
| 1919–2016   | 1919–2016   | Exact match                  |

---

## Handling of `_update()` Placement

**Original location**: Lines 950–975, inside the DOWNLOAD AND DEPLOYMENT section, after `_deploy()`.

**New location**: `12-commands.sh`, inserted between line 1862 (`}` — end of the function before
`_cmd_update()`) and line 1863 (`function _cmd_update() {`).

**Rationale**: Per spec recommendation, `_update()` is a thin orchestrator that calls `_download()`
and coordinates container recreation. It belongs alongside `_cmd_update()` in the command handlers
layer, not in the download/deploy layer which contains the atomic operations it orchestrates.

**Implementation**: `12-commands.sh` is constructed as three segments:
1. `sed -n '1607,1862p'` — COMMAND HANDLERS section through the end of the function before `_cmd_update()`
2. `sed -n '950,975p'` — `_update()` function from its original location (including trailing blank)
3. `sed -n '1863,1918p'` — `_cmd_update()` through end of COMMAND HANDLERS section

The trailing blank at line 975 (after `_update()`) provides the separation before `_cmd_update()`,
which already has a leading blank at line 1862.

---

## Edge Cases Encountered

### Single Section for Download + Deploy

The spec describes two separate modules (`06-download.sh` and `07-deploy.sh`) with a mapping to
"DOWNLOAD (first half)" and "DEPLOYMENT (second half)". However, the actual template has a single
`# DOWNLOAD AND DEPLOYMENT` section header. Resolution:

- The section header was placed in `06-download.sh` since download is the primary operation
- `07-deploy.sh` starts with the blank line at 939 (separating it from `_download()`), then `_deploy()`
- `_update()` was removed from this section entirely (moved to `12-commands.sh`)

### Top-Level Executable Code in `01-config.sh`

The spec states modules 02–11 should contain "function definitions only — no top-level statements".
`01-config.sh` contains several top-level executable statements as expected (color setup, variable
assignments, docker checks, `self=`, `set -o pipefail`). This is correct per the spec's rule that
`01-config.sh` defines shared constants and makes the config sourcing call.

`03-lifecycle.sh` contains one top-level statement: `trap _cleanup_on_exit INT TERM` at line 772.
This is a module-level setup call for the cleanup trap, which is necessary for process lifecycle
management and is semantically part of the lifecycle module's initialization. It is retained.

### Blank Line at Module Boundaries

Each module was extracted to preserve the blank lines present in the original. This ensures that a
simple `cat 00-header.sh 01-config.sh ... 13-dispatch.sh` reconstructs all section boundaries
correctly without needing inter-file newlines.

---

## Concatenation Verification

```
$ cat templates/manage.container.d/*.sh > /tmp/container_concat.sh
$ wc -l /tmp/container_concat.sh templates/manage.container.tp
2016 /tmp/container_concat.sh
2016 templates/manage.container.tp
```

**Diff against original** (only intentional `_update()` move):

```diff
950,975d949
< function _update() {
<   __print_info "Updating Docker container..."
< ... (26 lines removed from original position)
1860a1835,1860
> }
> 
> function _update() {
>   __print_info "Updating Docker container..."
< ... (26 lines inserted before _cmd_update())
```

The only difference from the original is the relocation of `_update()` from lines 950–975 to
immediately before `function _cmd_update()`. All other content is byte-identical.

**Verification against expected output** (original with `_update()` moved):
```
$ diff /tmp/container_concat.sh /tmp/container_expected.sh
(no output — PERFECT MATCH)
```
