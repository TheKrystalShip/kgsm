# Assembly Logic Implementation Decisions

**Phase 3 — Module Assembly & Override Resolution**
**Files modified:** `core/loader.sh`, `commands/handlers/files.common.sh`, `commands/handlers/files.management.sh`

---

## How `blueprint_name` Is Extracted in the New Flow

`__logic_create_management_file()` now reads `blueprint_file` from the instance config, then calls `__get_config_value "$_instance_blueprint_file" "name"` to obtain the `name=` field from the blueprint file itself.

This matches the documented invariant: the `name=` field — not the filename — determines which override directory is consulted. A blueprint file named `terraria-modded.bp` with `name=terraria` correctly resolves to `overrides/terraria/`.

`blueprint_name` is allowed to be empty (e.g. for container blueprints or synthetic instances). When empty, `__resolve_module` skips the override lookup and falls through to the default template module.

---

## How the Assembly Function Handles Edge Cases

| Situation | Behaviour |
|---|---|
| Module directory missing | `__find_manage_module_dir` returns `EC_FILE_NOT_FOUND`; assembly returns `EC_FILE_NOT_FOUND`. |
| Empty `blueprint_name` | `__resolve_module` skips both override paths and returns the default module. |
| Default module file missing | `__resolve_module` returns `EC_FILE_NOT_FOUND`; assembly propagates it. |
| Override file exists but default also exists | Override wins (first-match-wins, user > system > default). |
| Non-overridable module prefix (00,01,02,12,13) | `__resolve_module` always echoes the default path, ignoring any override files on disk. |

The output file is truncated (`: >"$output_file"`) before concatenation begins, so a partial previous file is never left in place on re-run.

---

## Backward Compatibility

### `__logic_inject_overrides`
Converted to a no-op returning `0`. The signature (`instance_name`, `management_file`) is preserved so any existing callers continue to compile and run without error. The function remains exported.

The call site inside `__logic_create_management_file` has been removed because assembly already incorporates per-module overrides. The no-op body of `__logic_inject_overrides` ensures the function is safe if called from external scripts or tests that have not yet been updated.

### `__find_override` in `core/loader.sh`
Left untouched. Its only caller outside tests is `core/overrides.sh`, which sources the monolithic `.overrides.sh` file for runtime function injection. That path is unrelated to management file assembly and must continue to work.

### Old template files (`manage.native.tp`, `manage.container.tp`)
Still present on disk. `__logic_create_management_file` no longer calls `__find_template("manage.${runtime}")`, so the old templates are bypassed but not deleted — safe for any external callers that reference them directly.

---

## Callers of `__find_override` That Were Checked

| File | Usage | Impact |
|---|---|---|
| `core/overrides.sh:36` | Sources monolithic `.overrides.sh` at runtime | Unchanged; no management file assembly involvement |
| `core/loader.sh:221` | Definition | Retained as-is |

No callers inside `commands/` or `tests/` were found that would be affected by the management-file assembly change.

---

## Verification Results

```
bash -n core/loader.sh                            → OK
bash -n commands/handlers/files.common.sh         → OK
bash -n commands/handlers/files.management.sh     → OK
shellcheck core/loader.sh                         → clean (exit 0)
shellcheck commands/handlers/files.common.sh      → clean (exit 0)
shellcheck commands/handlers/files.management.sh  → clean (exit 0)
```
