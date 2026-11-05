# Phase 3b: Test Updates — Decision Document

**Phase**: 3b — Test Updates  
**Date**: 2025  
**Status**: Complete

## Summary

Updated three existing test files to work with the new module-based management file assembly
system introduced in Phase 3a. The old monolithic templates (`manage.native.tp`,
`manage.container.tp`) and old `*.overrides.sh` override injection have been replaced by:

- `templates/manage.native.d/` and `templates/manage.container.d/` — 14-module directories
- `overrides/{game_name}/` — per-game module override directories
- `__logic_assemble_management_file()` — new assembly function
- `__resolve_module()` — new per-module override resolution function
- `__logic_inject_overrides()` — retained as a **no-op** for backward compatibility

---

## Test Files Modified

### 1. `tests/unit/test_files_management_logic.sh`

#### What changed and why

**`setup_test`** — Changed two `assert_file_exists` assertions to `assert_dir_exists`:
```
BEFORE: assert_file_exists "templates/manage.native.tp"
BEFORE: assert_file_exists "templates/manage.container.tp"
AFTER:  assert_dir_exists  "templates/manage.native.d"
AFTER:  assert_dir_exists  "templates/manage.container.d"
```
The old monolithic `.tp` template files were removed; the new `.d/` module directories are
the correct targets.

**`test_create_management_file_invalid_runtime`** — Completely rewritten:
- **Removed**: Used non-existent `create_mock_instance_config` helper (was causing accidental
  pass because the function call returned empty, making the test pass by coincidence with
  `EC_INVALID_ARG` from empty argument, not from invalid runtime validation).
- **Added**: Inline config creation using `cat > file << EOF`.
- **Updated expected exit code**: Changed from `EC_INVALID_ARG` to `EC_FAILED_TEMPLATE`.
  In the new implementation, an invalid runtime causes `__find_manage_module_dir` to fail
  with `EC_FILE_NOT_FOUND`, which `__logic_assemble_management_file` propagates, and
  `__logic_create_management_file` wraps as `EC_FAILED_TEMPLATE`.
- **Fixed blueprint path**: Changed `blueprints/native/default/factorio.bp` to use
  `$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/factorio.bp` (the actual path in the repo).

**`test_create_management_file_replaces_existing`** — Replaced a single monolithic function
containing 4 concatenated sub-tests (an existing bug in the file) with 5 separate functions:

| New function | Purpose |
|---|---|
| `test_create_management_file_replaces_existing` | Verifies truncation before assembly |
| `test_create_management_file_native_success` | Basic native creation (necesse, no overrides) |
| `test_create_management_file_native_with_module_overrides` | Factorio with module overrides applied |
| `test_create_management_file_container_compose_failure` | Container missing blueprint_file |
| `test_create_management_file_assembles_all_modules` | Verifies key functions from all modules |

All new functions use inline config creation and `$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR` for
blueprint paths, replacing the non-existent `create_mock_instance_config` helper.

**Previous failures fixed**: 4/29 assertions failed → 0/50 assertions failed.  
**New test count**: 17 → 28 functions.

---

### 2. `tests/unit/test_files_common_logic.sh`

#### What changed and why

**`setup_test`** — Updated assertions:
- Added `__logic_assemble_management_file` and `__resolve_module` to function existence checks
  (both are new exports from `files.common.sh`).
- Replaced `assert_file_exists` for `factorio.overrides.sh` / `terraria.overrides.sh` with
  `assert_dir_exists` for `factorio/` / `terraria/` override directories (new structure).
- Replaced `assert_file_not_exists` for `necesse.overrides.sh` with `assert_dir_not_exists`
  for `necesse/` (no module overrides for necesse).

**Removed helper functions** — `__create_minimal_test_instance` and
`__remove_minimal_test_instance` were no longer needed since the rewritten inject_overrides
tests don't create instances.

**`test_inject_overrides_*` tests (10 functions)** — All adapted to reflect that
`__logic_inject_overrides` is now a **no-op** returning `0` unconditionally:

| Test | Before (expected) | After (expected) | Rationale |
|---|---|---|---|
| `test_inject_overrides_empty_instance_name` | `EC_INVALID_ARG` | `0` | No-op |
| `test_inject_overrides_empty_management_file` | `EC_INVALID_ARG` | `0` | No-op |
| `test_inject_overrides_management_file_not_found` | `EC_FILE_NOT_FOUND` | `0` | No-op |
| `test_inject_overrides_instance_not_found` | `EC_INVALID_INSTANCE` | `0` | No-op |
| `test_inject_overrides_missing_blueprint_file_config` | `EC_INVALID_CONFIG` | `0` | No-op; removed instance setup |
| `test_inject_overrides_missing_blueprint_name` | `EC_INVALID_CONFIG` | `0` | No-op; removed instance setup |
| `test_inject_overrides_container_blueprint_skips` | `0` + file unchanged | `0` + file unchanged | Same outcome |
| `test_inject_overrides_no_override_file_exists` | `0` + file unchanged | `0` + file unchanged | Same outcome; removed instance setup |
| `test_inject_overrides_success_with_overrides` | `0` + file modified | `0` + file **unchanged** | No-op never modifies file |
| `test_inject_overrides_corrupt_override_file` | `EC_FAILED_SOURCE` | `0` | No-op |

**Added: `test_resolve_module_*` tests (6 new functions)**:
- `test_resolve_module_non_overridable_always_default` — Verifies modules 00, 01, 02, 12, 13
  always use the default template even when user/system overrides exist.
- `test_resolve_module_overridable_uses_default_when_no_override` — necesse has no overrides,
  default is used.
- `test_resolve_module_system_override` — factorio system override for `05-version.sh`.
- `test_resolve_module_user_override_priority` — User override takes priority over system.
- `test_resolve_module_empty_blueprint_uses_default` — Empty blueprint name → default.
- `test_resolve_module_invalid_module_not_found` — Non-existent module → `EC_FILE_NOT_FOUND`.

**Added: `test_assemble_management_file_*` tests (7 new functions)**:
- `test_assemble_management_file_empty_runtime` — `EC_INVALID_ARG`.
- `test_assemble_management_file_empty_output_file` — `EC_INVALID_ARG`.
- `test_assemble_management_file_invalid_runtime` — `EC_FILE_NOT_FOUND`.
- `test_assemble_management_file_native_success` — Success + shebang present.
- `test_assemble_management_file_container_success` — Container assembly succeeds.
- `test_assemble_management_file_applies_module_overrides` — factorio's `factorio.com` appears.
- `test_assemble_management_file_non_overridable_modules_immutable` — Non-overridable module
  override is silently ignored; real header is used.

**Previous failures fixed**: 7/41 assertions failed → 0/75 assertions failed.  
**New test count**: 15 → 28 functions.

---

### 3. `tests/integration/test_xdg_paths_integration.sh`

#### What changed and why

**`setup_test`** — Two changes:
1. Added sourcing of `files.common.sh` (via `__find_command_handler`) to make `__resolve_module`
   available for new integration tests.
2. Added assertion: `assert_function_exists "__resolve_module"`.
3. Removed the directory-based override creation for `test-modgame` from `setup_test` — moved
   into individual test functions to avoid test interference (shared user XDG path means tests
   running in parallel could see each other's state).

**`test_user_override_precedence`** — Kept unchanged. This test already correctly tests
`__find_override` with legacy `.overrides.sh` file priority (user > system), which still works.

**Added: `test_resolve_module_system_override_directory`** — Tests that `__resolve_module`
returns the system override path when only a system override exists.

**Added: `test_resolve_module_user_override_directory_priority`** — Tests that the user override
directory takes priority over the system override directory when both exist.

**Added: `test_resolve_module_non_overridable_ignores_override_dirs`** — Tests that creating
override files for non-overridable modules (e.g., `00-header.sh`) has no effect.

**Added: `test_override_directories_exist_for_known_games`** — Structural test verifying that
`overrides/factorio/` and `overrides/terraria/` directories exist in the system overrides dir.

**Key design decision**: Each `test_resolve_module_*` test creates and cleans up its own
override files independently. This is critical because `KGSM_USER_OVERRIDES_DIR` points to the
real user's XDG directory (not sandboxed), so tests must not rely on setup_test state.

**Previous state**: All 11 tests passed.  
**New test count**: 11 → 15 functions (41 assertions).

---

## Tests Removed vs Adapted vs Added

| Category | Count | Details |
|---|---|---|
| **Removed** | 1 function body | Old `test_create_management_file_replaces_existing` monolith (contained 4 sub-tests inline; was bugged) |
| **Adapted** | 13 functions | All `test_inject_overrides_*` updated for no-op behavior; `setup_test` assertions updated in all 3 files; `test_create_management_file_invalid_runtime` rewritten |
| **Added** | 20 functions | 5 management logic, 13 common logic (6 resolve_module + 7 assemble), 4 xdg_paths |

---

## Test Execution Results

### Before changes (pre-existing failures)
```
not ok - test_files_management_logic [unit]  # 4/29 assertions failed
not ok - test_files_common_logic [unit]      # 7/41 assertions failed
ok     - test_xdg_paths_integration          # 31/31 assertions passed
```

### After changes
```
ok - test_files_management_logic [unit]   # 50/50 assertions passed (28 tests)
ok - test_files_common_logic [unit]       # 75/75 assertions passed (28 tests)
ok - test_xdg_paths_integration           # 41/41 assertions passed (15 tests)
```

### Pre-existing failures (unrelated to this phase)
`test_directories_commands`, `test_directories_logic`, and `test_instances_logic` fail both
before and after these changes when run in the full parallel unit suite. They pass in isolation.
These are pre-existing race conditions in the test framework related to shared XDG paths.
