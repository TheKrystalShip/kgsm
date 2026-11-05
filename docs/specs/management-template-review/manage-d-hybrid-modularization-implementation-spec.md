# manage.d/ Hybrid Modularization — Implementation Specification

> **Status**: Implementation Specification
> **Date**: 2026-03-05
> **Prerequisite**: [manage-d-modularization-analysis.md](manage-d-modularization-analysis.md)
> **Scope**: Split monolithic manage templates into numbered source modules; concatenate them into a single output script during instance creation. Refactor override injection to use module-level replacement instead of sed-based function patching.

---

## 1. Summary

Split `manage.native.tp` and `manage.container.tp` into numbered module files in the KGSM repository. During instance creation, concatenate the modules in order — substituting override modules where they exist — to produce a single, self-contained management script identical in behavior to what exists today. The generated output is still one file; only the KGSM source organization changes.

### Key design decisions

- **No changes to the instance side.** The generated `${instance_name}.manage.sh` remains a single, standalone script. No `manage.d/` directory is created in the instance.
- **Override modules replace default modules by number.** If an override for module `04-download.sh` exists for a blueprint, that entire module file is used instead of the default. Override authors must copy the full default module and modify only what they need — no function removal is permitted. No more sed-based function patching.
- **User hooks are out of scope.** The hook extension point is deferred to a future iteration.
- **Container overrides remain unsupported** for now (matching current behavior).

---

## 2. Proposed Source Layout

### 2.1 Template module directories

```
templates/
├── manage.native.tp                    # REMOVED (replaced by modules below)
├── manage.container.tp                 # REMOVED (replaced by modules below)
├── manage.native.d/
│   ├── 00-header.sh
│   ├── 01-config.sh
│   ├── 02-help.sh
│   ├── 03-lifecycle.sh
│   ├── 04-io.sh
│   ├── 05-version.sh
│   ├── 06-download.sh
│   ├── 07-deploy.sh
│   ├── 08-backup.sh
│   ├── 09-network.sh
│   ├── 10-logging.sh
│   ├── 11-status.sh
│   ├── 12-commands.sh
│   └── 13-dispatch.sh
├── manage.container.d/
│   ├── 00-header.sh
│   ├── 01-config.sh
│   ├── 02-help.sh
│   ├── 03-lifecycle.sh
│   ├── 04-io.sh
│   ├── 05-version.sh
│   ├── 06-download.sh
│   ├── 07-deploy.sh
│   ├── 08-backup.sh
│   ├── 09-network.sh
│   ├── 10-logging.sh
│   ├── 11-status.sh
│   ├── 12-commands.sh
│   └── 13-dispatch.sh
└── ...existing templates unchanged...
```

### 2.2 Override module directories

```
overrides/
├── factorio/
│   ├── 05-version.sh                  # Replaces default 05-version.sh
│   ├── 06-download.sh                 # Replaces default 06-download.sh
│   └── 07-deploy.sh                   # Replaces default 07-deploy.sh
├── minecraft/
│   ├── 05-version.sh
│   ├── 06-download.sh
│   └── 07-deploy.sh
├── terraria/
│   ├── 05-version.sh
│   ├── 06-download.sh
│   └── 07-deploy.sh
├── barotrauma/
│   └── 07-deploy.sh
├── veloren/
│   ├── 05-version.sh
│   └── 06-download.sh
└── ...future overrides follow the same pattern...
```

**Naming convention**: Override files use the **exact same filename** as the default module they replace. The override directory is named after the blueprint's `name=` field (not the blueprint filename).

---

## 3. Module Definitions

Each module maps to one or more sections from the current monolithic template. The content split follows the existing section comment markers (`# =====...=====`).

### Module ↔ current section mapping

| Module            | Current section                  | Native lines | Container lines | Functions                                                                                                                                                                                                                                 |
| ----------------- | -------------------------------- | ------------ | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `00-header.sh`    | Shebang, autogen notice          | 1–18         | 1–15            | —                                                                                                                                                                                                                                         |
| `01-config.sh`    | CONFIGURATION AND INITIALIZATION | 19–137       | 16–138          | `__validate_config_key`, `__source_instance_config`, `__print_*` (4), exit code constants                                                                                                                                                 |
| `02-help.sh`      | HELP SYSTEM                      | 138–484      | 139–485         | `show_usage` (1 main + 10 per-command), `_cmd_help`                                                                                                                                                                                       |
| `03-lifecycle.sh` | PROCESS MANAGEMENT               | 485–829      | 486–773         | `_is_active`, `_start`, `_start_background`, `_attach_to_instance`, `_stop_server`, `_timed_stop`, `_kill_all_processes`, `_cleanup_on_exit`                                                                                              |
| `04-io.sh`        | SERVER I/O                       | 830–900      | 774–879         | `_send_input`, `_send_save_command` (+ `__sanitize_input_command` for container)                                                                                                                                                          |
| `05-version.sh`   | VERSION MANAGEMENT               | 901–981      | 880–917         | `_get_installed_version`, `_get_latest_version`, `_compare_versions`, `_save_version`                                                                                                                                                     |
| `06-download.sh`  | DOWNLOAD (first half)            | 982–1037     | 918–945         | `_download`                                                                                                                                                                                                                               |
| `07-deploy.sh`    | DEPLOYMENT (second half)         | 1039–1064    | 941–950         | `_deploy`                                                                                                                                                                                                                                 |
| `08-backup.sh`    | BACKUP MANAGEMENT                | 1117–1296    | 976–1155        | `_create_backup`, `_restore_backup`, `_list_backups`                                                                                                                                                                                      |
| `09-network.sh`   | NETWORK (UPnP)                   | 1297–1357    | 1156–1216       | `_enable_upnp`, `_disable_upnp`, `_is_upnp_enabled`                                                                                                                                                                                       |
| `10-logging.sh`   | LOGGING                          | 1358–1402    | 1217–1258       | `_rotate_log_file`, `_print_logs`                                                                                                                                                                                                         |
| `11-status.sh`    | STATUS                           | 1403–1601    | 1259–1606       | `_get_status` (+ `_get_container_process_info`, `_monitor_container_state` for container)                                                                                                                                                 |
| `12-commands.sh`  | COMMAND HANDLERS                 | 1602–1895    | 1607–1918       | `_cmd_start`, `_cmd_stop`, `_cmd_restart`, `_cmd_attach`, `_cmd_kill`, `_cmd_save`, `_cmd_input`, `_cmd_is_active`, `_cmd_status`, `_cmd_logs`, `_cmd_version`, `_cmd_download`, `_cmd_deploy`, `_cmd_update`, `_cmd_backup`, `_cmd_upnp` |
| `13-dispatch.sh`  | MAIN DISPATCH                    | 1896–1993    | 1919–2016       | Main `case` statement, argument parsing                                                                                                                                                                                                   |

### Module boundary rules

1. `00-header.sh` contains **only** the shebang (`#!/usr/bin/env bash`), the autogenerated notice comment block, and the global shellcheck disable directives. No executable code.
2. `01-config.sh` defines all shared constants, utility functions, and the config sourcing call. Every subsequent module depends on it.
3. Modules `02` through `11` define functions only. They do **not** execute code at source time (no top-level statements besides function definitions).
4. `12-commands.sh` defines the `_cmd_*` handler functions. No top-level execution.
5. `13-dispatch.sh` contains the only top-level executable code: the CLI argument parser and `case` dispatch.

### Separate `_update` from `_download`/`_deploy`

The current `_update()` function orchestrates `_download` + `_deploy`. It should stay in a module that is **not** overridable by default (`06-download.sh` or `07-deploy.sh`). `_update()` belongs in `12-commands.sh` as part of `_cmd_update`, or in its own non-overridden module. This ensures overriding download or deploy does not silently break the update pipeline.

**Recommendation**: Move `_update()` into `12-commands.sh` alongside `_cmd_update`, since it is a thin orchestrator that calls `_download` and `_deploy`. Alternatively, keep it in `06-download.sh` and document that override authors must not redefine `_update()` unless they explicitly intend to.

---

## 4. Override Resolution Algorithm

The current sed-based override injection (`__logic_inject_overrides` in `files.common.sh`) is replaced with module-level file substitution during concatenation.

### 4.1 Current flow (to be replaced)

```
1. cp manage.native.tp → instance.manage.sh
2. source overrides/{blueprint_name}.overrides.sh
3. for each function in overrides file:
     sed -i replace function block in instance.manage.sh
```

### 4.2 New flow

```
1. Determine runtime (native/container) from instance config
2. Determine blueprint_name from blueprint file's name= field
3. For each module NN-name.sh in templates/manage.{runtime}.d/ (sorted):
     a. Check: does overrides/{blueprint_name}/NN-name.sh exist?
     b. If YES → use the override module
     c. If NO  → use the default module from templates/manage.{runtime}.d/
4. Concatenate all resolved modules (in order) into one output file
5. chmod +x the output file
```

### 4.3 Override search order

For a given module `NN-name.sh` and blueprint name `factorio`:

1. `${KGSM_USER_OVERRIDES_DIR}/factorio/NN-name.sh` (user customizations, highest priority)
2. `${KGSM_SYSTEM_OVERRIDES_DIR}/factorio/NN-name.sh` (KGSM-shipped overrides)
3. `${KGSM_TEMPLATES_DIR}/manage.{runtime}.d/NN-name.sh` (default)

First match wins. This preserves the existing user > system override priority from `__find_override()` in `core/loader.sh`.

### 4.4 Override scope constraints

- An override module **must** be a copy of the default module with modifications applied. All functions from the default module must be preserved; the override author may modify function implementations but must not remove any functions. It is the user's responsibility to maintain module integrity.
- An override module **may** add helper functions used only within that module, prefixed with `__override_` to avoid collisions.
- Only modules `03` through `11` may be overridden. Modules `00` (header), `01` (config), `02` (help), `12` (commands), and `13` (dispatch) are KGSM infrastructure and not overridable.

---

## 5. Required Code Changes

### 5.1 New files to create

| File                                                                 | Purpose                                                                        |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `templates/manage.native.d/00-header.sh` through `13-dispatch.sh`    | 14 module files, split from `manage.native.tp`                                 |
| `templates/manage.container.d/00-header.sh` through `13-dispatch.sh` | 14 module files, split from `manage.container.tp`                              |
| `overrides/factorio/05-version.sh`                                   | Factorio version override (from `factorio.overrides.sh` `_get_latest_version`) |
| `overrides/factorio/06-download.sh`                                  | Factorio download override (from `factorio.overrides.sh` `_download`)          |
| `overrides/factorio/07-deploy.sh`                                    | Factorio deploy override (from `factorio.overrides.sh` `_deploy`)              |
| `overrides/minecraft/05-version.sh`                                  | Minecraft version override                                                     |
| `overrides/minecraft/06-download.sh`                                 | Minecraft download override                                                    |
| `overrides/minecraft/07-deploy.sh`                                   | Minecraft deploy override                                                      |
| `overrides/terraria/05-version.sh`                                   | Terraria version override                                                      |
| `overrides/terraria/06-download.sh`                                  | Terraria download override                                                     |
| `overrides/terraria/07-deploy.sh`                                    | Terraria deploy override                                                       |
| `overrides/barotrauma/07-deploy.sh`                                  | Barotrauma deploy override                                                     |
| `overrides/veloren/05-version.sh`                                    | Veloren version override                                                       |
| `overrides/veloren/06-download.sh`                                   | Veloren download override                                                      |

### 5.2 Files to modify

| File                                    | Change                                                                                                     |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `commands/handlers/files.management.sh` | Replace `cp` of monolithic template with module concatenation logic                                        |
| `commands/handlers/files.common.sh`     | Replace `__logic_inject_overrides()` with new module-resolution function                                   |
| `core/loader.sh`                        | Add `__find_manage_module_dir()` function; update `__find_override()` to support directory-based overrides |
| `templates/overrides.tp`                | Update to reflect new override structure (module files instead of single file)                             |

### 5.3 Files to remove (after migration)

| File                                | Reason                                        |
| ----------------------------------- | --------------------------------------------- |
| `templates/manage.native.tp`        | Replaced by `templates/manage.native.d/`      |
| `templates/manage.container.tp`     | Replaced by `templates/manage.container.d/`   |
| `overrides/factorio.overrides.sh`   | Replaced by `overrides/factorio/` directory   |
| `overrides/minecraft.overrides.sh`  | Replaced by `overrides/minecraft/` directory  |
| `overrides/terraria.overrides.sh`   | Replaced by `overrides/terraria/` directory   |
| `overrides/barotrauma.overrides.sh` | Replaced by `overrides/barotrauma/` directory |
| `overrides/veloren.overrides.sh`    | Replaced by `overrides/veloren/` directory    |

---

## 6. Implementation Details

### 6.1 Module concatenation function

Replaces the current `cp` + `__logic_inject_overrides()` in `__logic_create_management_file()`.

**Pseudocode**:

```bash
# New function: Assemble management script from modules
# Args: $1 = runtime (native|container), $2 = blueprint_name, $3 = output_file
function __logic_assemble_management_file() {
  local runtime="$1"
  local blueprint_name="$2"
  local output_file="$3"

  local module_dir="${KGSM_TEMPLATES_DIR}/manage.${runtime}.d"

  if [[ ! -d "$module_dir" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Truncate output file
  : > "$output_file"

  # Iterate modules in numeric order
  local module_file resolved_file
  for module_file in "$module_dir"/*.sh; do
    local module_basename
    module_basename=$(basename "$module_file")

    # Resolve: check for override, fall back to default
    resolved_file=$(__resolve_module "$blueprint_name" "$runtime" "$module_basename")

    # Append module content to output
    cat "$resolved_file" >> "$output_file"
    printf '\n' >> "$output_file"
  done

  return 0
}

# Resolve a single module: override > default
# Args: $1 = blueprint_name, $2 = runtime, $3 = module_basename
function __resolve_module() {
  local blueprint_name="$1"
  local runtime="$2"
  local module_basename="$3"

  # Extract module number prefix
  local module_number="${module_basename%%-*}"

  # Non-overridable modules: 00, 01, 02, 12, 13
  case "$module_number" in
    00|01|02|12|13)
      echo "${KGSM_TEMPLATES_DIR}/manage.${runtime}.d/${module_basename}"
      return 0
      ;;
  esac

  # Check user overrides first, then system overrides
  local user_override="${KGSM_USER_OVERRIDES_DIR}/${blueprint_name}/${module_basename}"
  if [[ -f "$user_override" ]]; then
    echo "$user_override"
    return 0
  fi

  local system_override="${KGSM_SYSTEM_OVERRIDES_DIR}/${blueprint_name}/${module_basename}"
  if [[ -f "$system_override" ]]; then
    echo "$system_override"
    return 0
  fi

  # Fall back to default
  echo "${KGSM_TEMPLATES_DIR}/manage.${runtime}.d/${module_basename}"
  return 0
}
```

### 6.2 Changes to `__logic_create_management_file()`

**Current** (`commands/handlers/files.management.sh` lines 76–143):
```bash
# Current: copy monolithic template, then inject overrides
cp -f "$manage_template_file" "$_instance_management_file"
# ...
__logic_inject_overrides "$_instance_name" "$_instance_management_file"
```

**New**:
```bash
# New: assemble from modules with override resolution
local blueprint_name
blueprint_name=$(__get_config_value "$instance_config_file" "blueprint_name" 2>/dev/null)
# (Extract from blueprint file if not in instance config)

__logic_assemble_management_file "$_instance_runtime" "$blueprint_name" "$_instance_management_file"
```

The `__logic_inject_overrides()` call is **removed entirely** — override resolution is now part of assembly.

### 6.3 Changes to `__logic_inject_overrides()`

This function is **removed** or reduced to a no-op. Its responsibility (override injection) is absorbed by `__logic_assemble_management_file()` and `__resolve_module()`.

If backward compatibility is needed during a transition period, the function can be kept as a no-op:
```bash
function __logic_inject_overrides() {
  # Override injection is now handled during module assembly.
  # This function is retained for backward compatibility and is a no-op.
  return 0
}
```

### 6.4 Changes to `core/loader.sh`

Add a function to locate the manage module directory:

```bash
function __find_manage_module_dir() {
  local runtime="$1"
  local module_dir="${KGSM_TEMPLATES_DIR}/manage.${runtime}.d"
  if [[ -d "$module_dir" ]]; then
    echo "$module_dir"
    return 0
  fi
  return $EC_FILE_NOT_FOUND
}
export -f __find_manage_module_dir
```

Update or deprecate `__find_override()` — its callers should migrate to the module resolution path. If other parts of KGSM still use it (check all callers), it can be kept for those use cases.

### 6.5 Override migration: single file → module directory

Each existing `{blueprint_name}.overrides.sh` is split into individual module files. The migration is mechanical:

**Example: `factorio.overrides.sh` → `overrides/factorio/`**

| Source function         | Target module    | Rationale                 |
| ----------------------- | ---------------- | ------------------------- |
| `_get_latest_version()` | `05-version.sh`  | Version management module |
| `_download()`           | `06-download.sh` | Download module           |
| `_deploy()`             | `07-deploy.sh`   | Deploy module             |

Each override module file must be a **copy of the corresponding default module** with only the necessary modifications applied. Override authors must:
1. **Copy** the full default module from `templates/manage.{runtime}.d/NN-name.sh`.
2. **Modify** only the functions or logic they need to customize.
3. **Not remove** any existing functions or code from the copied module.

The override module replaces the entire default module during concatenation — there is no merging. It is the **user's responsibility** to maintain the integrity of the module by preserving all default functions they do not intend to change.

**Example**: If the default `05-version.sh` defines 4 functions (`_get_installed_version`, `_get_latest_version`, `_compare_versions`, `_save_version`) and an override only needs to change `_get_latest_version`, the override's `05-version.sh` must be a copy of the default with only `_get_latest_version` modified. The other 3 functions remain as-is from the default.

---

## 7. Override Strategy: Module-Level Replacement

Overrides operate at the **module level** (one module per section, as defined in Section 2). When a user needs to customize behavior for a specific module, they must:

1. **Copy** the entire default module from `templates/manage.{runtime}.d/`.
2. **Modify** only the functions or logic they need to change.
3. **Preserve** all existing functions and code they do not intend to change.

This approach keeps the module layout simple (14 modules matching the existing section structure) and avoids the complexity of per-function file splitting. The trade-off is that override modules carry the full default code alongside customizations, but this is an acceptable cost because:

- **Clarity**: Override authors can see all related functions in context, making it easier to understand the module they are customizing.
- **Simplicity**: The assembly loop, file layout, and override resolution remain straightforward with no additional file proliferation.
- **User responsibility**: Override authors are expected to maintain their overrides. If a KGSM update changes a default function in a module the user has overridden, it is the user's responsibility to incorporate those changes. KGSM will document default module changes in release notes to assist with this.
- **Consistency**: The module boundaries match the existing section structure of the monolithic template, making the initial split mechanical and verifiable.

---

## 8. Validation & Testing Requirements

### 8.1 Output equivalence test

The most critical test: the concatenated output from the new module system must produce a **byte-identical** (or functionally identical) management script compared to the current monolithic template + sed override injection.

```bash
# Generate management file using current monolith approach
./kgsm.sh create factorio --name test-old ...
# Capture: test-old.manage.sh

# Generate management file using new module approach
./kgsm.sh create factorio --name test-new ...
# Capture: test-new.manage.sh

# Compare (ignoring instance-specific values like paths/names)
diff <(sed 's/test-old/INSTANCE/g' test-old.manage.sh) \
     <(sed 's/test-new/INSTANCE/g' test-new.manage.sh)
```

### 8.2 Unit tests

| Test                                   | What it verifies                                                       |
| -------------------------------------- | ---------------------------------------------------------------------- |
| `test_module_assembly_default`         | All 14 modules concatenate correctly without overrides                 |
| `test_module_assembly_with_override`   | Override module is substituted at correct position                     |
| `test_module_resolution_priority`      | User override > system override > default                              |
| `test_non_overridable_modules`         | Modules 00, 01, 02, 12, 13 cannot be overridden                        |
| `test_all_existing_overrides_migrated` | Every function in old `.overrides.sh` files has a corresponding module |
| `test_override_module_completeness`    | Override modules preserve all functions defined in the default module they replace |

### 8.3 Integration tests

| Test                                         | What it verifies                                                                  |
| -------------------------------------------- | --------------------------------------------------------------------------------- |
| `test_instance_create_native_no_overrides`   | Instance creation works for blueprints without overrides                          |
| `test_instance_create_native_with_overrides` | Instance creation works for blueprints with overrides (factorio, minecraft, etc.) |
| `test_instance_create_container`             | Container instances still work (no overrides applied)                             |
| `test_generated_script_executable`           | Generated management script runs and responds to `--help`                         |

### 8.4 Existing test impact

Review and update any tests that:
- Reference `manage.native.tp` or `manage.container.tp` by path.
- Test `__logic_inject_overrides()` directly.
- Test `__find_override()` behavior.
- Create instances and inspect the generated management file.

---

## 9. Migration Path

### Phase 1: Create module directories (non-breaking)

1. Create `templates/manage.native.d/` and `templates/manage.container.d/`.
2. Split existing monolithic templates into numbered modules.
3. Verify: concatenating all modules reproduces the original template exactly.
4. **Do not modify any runtime code yet.** The monolithic templates remain the active source.

### Phase 2: Create override module directories (non-breaking)

1. Create `overrides/{blueprint_name}/` directories.
2. Split existing `.overrides.sh` files into numbered module files.
3. **Do not remove old override files yet.**

### Phase 3: Implement new assembly logic

1. Add `__logic_assemble_management_file()` and `__resolve_module()` to `files.common.sh` (or a new `files.assembly.sh`).
2. Update `__logic_create_management_file()` to use assembly instead of copy + inject.
3. Run output equivalence tests.
4. Run full test suite.

### Phase 4: Cleanup

1. Remove `templates/manage.native.tp` and `templates/manage.container.tp`.
2. Remove old `overrides/*.overrides.sh` files.
3. Update `templates/overrides.tp` to document new module structure.
4. Update documentation (`docs/overrides.md`, `CONTRIBUTING.md`, etc.).

---

## 10. Files Requiring Documentation Updates

| File                                             | Change needed                                                            |
| ------------------------------------------------ | ------------------------------------------------------------------------ |
| `docs/overrides.md`                              | Document new module-based override structure                             |
| `templates/overrides.tp`                         | Update override template to document copy-and-modify workflow for module overrides |
| `CONTRIBUTING.md`                                | Update instructions for adding new game server overrides                 |
| `docs/specs/manage-d-modularization-analysis.md` | Link to this spec as the chosen implementation                           |
| `docs/execution_flows.md`                        | Update instance creation flow to reflect module assembly                 |

---

## 11. Risks and Mitigations

| Risk                                                                              | Impact                                                   | Mitigation                                                                                          |
| --------------------------------------------------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Module concatenation introduces blank lines or whitespace differences             | Low — cosmetic only, but could affect diff-based testing | Normalize whitespace in output equivalence tests                                                    |
| Override module removes or omits a required function                              | High — runtime errors in generated script                | Document that overrides must be copies of the default module; add an optional validation step that warns if expected functions are missing |
| Existing tests break due to path changes                                          | Medium — test failures                                   | Update test references in Phase 3, run full suite before merging                                    |
| `__find_override()` is called from other code paths not identified                | Medium — broken override resolution elsewhere            | `grep -r __find_override` to find all callers before modifying                                      |
| Template variable expansion (`eval "cat <<EOF"`) interacts with module boundaries | Low — currently templates are copied, not expanded       | Verify no modules contain `$variable` references that would be affected if expansion is later added |
