# Cleanup & Documentation — Implementation Decisions

**Task**: Phase 4 of the manage.d/ Hybrid Modularization spec — remove old monolithic
files and update documentation to reflect the module-based system.

---

## Files Removed

All removals performed with `git rm` so they are tracked in version control.

| File removed | Replaced by |
|---|---|
| `templates/manage.native.tp` | `templates/manage.native.d/` (14 module files) |
| `templates/manage.container.tp` | `templates/manage.container.d/` (14 module files) |
| `overrides/factorio.overrides.sh` | `overrides/factorio/` (3 module files) |
| `overrides/minecraft.overrides.sh` | `overrides/minecraft/` (3 module files) |
| `overrides/terraria.overrides.sh` | `overrides/terraria/` (3 module files) |
| `overrides/barotrauma.overrides.sh` | `overrides/barotrauma/` (1 module file) |
| `overrides/veloren.overrides.sh` | `overrides/veloren/` (2 module files) |

---

## Documentation Changes

### `templates/overrides.tp`

**Before:** A 1766-line bash script with all management functions commented out,
documenting the single-file override pattern (`copy this file, uncomment functions`).

**After:** A 182-line reference file documenting:
- The module-based override structure (`overrides/{blueprint_name}/` directories)
- Which modules can be overridden (03–11)
- The copy-and-modify workflow
- Override search priority (user > system > default)
- A brief annotated example showing how `overrides/factorio/05-version.sh` works
- All `$instance_*` and `$config_*` variable documentation preserved

The function example comments were removed because the authoritative reference for
each function is now its corresponding default module in `templates/manage.native.d/`.

### `docs/overrides.md`

Complete rewrite from 462 lines to 546 lines. Key changes:

- **What are Overrides?** — updated from "custom script files" to "game-specific module
  files that replace numbered default modules during assembly"
- **How Overrides Work** — replaced the `core/overrides.sh` sourcing description with
  the assembly-time `__resolve_module` description; added 3-step assembly flow
- **Override Search Order** — extended to show three tiers: user overrides directory →
  system overrides directory → default template modules
- **New section: Overridable Modules** — table listing modules 03–11 with filenames
  and responsibilities; notes that 00–02 and 12–13 cannot be overridden
- **Available Functions** — grouped by module file instead of by category alone
- **Blueprint-Override Linking** — examples updated to show `→ overrides/factorio/`
  instead of `→ overrides/factorio.overrides.sh`
- **Creating Overrides (Getting Started)** — replaced "copy overrides.tp, uncomment
  functions" workflow with "copy default module, modify functions" workflow
- **Real-World Example: Factorio** — updated to show the three-file module structure
  (`05-version.sh`, `06-download.sh`, `07-deploy.sh`) with actual function bodies
- **New section: Migrating from Legacy Overrides** — step-by-step guide for converting
  old `.overrides.sh` files to the new directory format
- **Best Practices** — added "Copy, then modify" and "Preserve all functions" as
  top-level principles; removed single-file naming advice

### `docs/execution_flows.md`

Two targeted changes to the Instance Creation Flow section:

1. Mermaid diagram node J updated from:
   `files.sh create INSTANCE (management script, config files, integrations)`
   to:
   `files.sh create INSTANCE (assemble management script from modules, config files, integrations)`

2. Prose step 4 updated from:
   > **File generation**: `files.sh create` writes the management script...
   to:
   > **Management script assembly**: `files.sh create` assembles the management script
   > by concatenating numbered modules from `templates/manage.{runtime}.d/`,
   > substituting per-game override modules from `overrides/{blueprint_name}/` for
   > modules 03–11 where they exist.

### `CONTRIBUTING.md`

Added a new **Game Server Overrides** subsection under "Key Areas for Contribution"
explaining the directory-based override structure, the copy-and-modify workflow, and
the constraint that only modules 03–11 may be overridden.

### `docs/blueprints.md`

Line 58: updated the description of the `name` field's role in override lookup from
`overrides/factorio.overrides.sh` to `overrides/factorio/`.

### `docs/templates.md`

- Table of Contents: replaced `manage.native.tp` and `manage.container.tp` anchors
  with `manage.native.d/` and `manage.container.d/`
- `manage.native.tp` section replaced with `manage.native.d/` section: full module
  table (00–13), description of override substitution for modules 03–11
- `manage.container.tp` section replaced with `manage.container.d/` section
- `overrides.tp` description updated to reflect the new reference-file format
- Usage Guidelines: replaced "copy overrides.tp to overrides/your_game.overrides.sh"
  with instructions to create a directory and copy individual default modules

---

## Broken References Found and Fixed

| File | Reference | Fix applied |
|---|---|---|
| `docs/blueprints.md:58` | `overrides/factorio.overrides.sh` | Updated to `overrides/factorio/` |
| `docs/templates.md:11-12` | `manage.native.tp`, `manage.container.tp` TOC links | Replaced with module directory links |
| `docs/templates.md:94,108,110` | `manage.native.tp`, `manage.container.tp` sections | Replaced with module directory sections |
| `docs/templates.md:198` | `overrides/<blueprint_name>.overrides.sh` workflow | Updated to module-copy workflow |
| `docs/templates.md:331,336` | `overrides.tp → overrides/your_game.overrides.sh` | Updated to directory/module workflow |

### References NOT changed (intentional)

| File | Reference | Reason |
|---|---|---|
| `CHANGELOG.md:340` | `factorio.overrides.sh` | Historical changelog entry; must not be altered |
| `docs/specs/*/manage-d-hybrid-modularization-implementation-spec.md` | Various | Spec documents; describe what was planned, not current state |
| `tests/integration/test_xdg_paths_integration.sh` | Creates temporary `.overrides.sh` files | Tests `__find_override` runtime lookup (still valid, not related to assembly) |

---

## Test File Verification

All test files were checked for references to removed filenames:

- `tests/unit/test_files_management_logic.sh` — already updated in Phase 3 to check
  for `templates/manage.native.d` and `templates/manage.container.d` directories
- `tests/unit/test_files_common_logic.sh` — already updated in Phase 3; references
  `$KGSM_SYSTEM_OVERRIDES_DIR/factorio` (directory) and no longer references `.overrides.sh`
- `tests/integration/test_xdg_paths_integration.sh` — creates its own temporary
  `.overrides.sh` files and cleans them up; tests the runtime `__find_override`
  mechanism which is unaffected by this phase

---

## Verification

Post-cleanup grep for removed filenames across all tracked files (excluding `docs/specs/` and `CHANGELOG.md`):

```
grep -rn "manage\.native\.tp|manage\.container\.tp" --include="*.md" --include="*.sh" --include="*.tp" .
→ No results (exit 1)

grep -rn "factorio\.overrides\.sh|terraria\.overrides\.sh|minecraft\.overrides\.sh" --include="*.md" --include="*.sh" --include="*.tp" .
→ Only: CHANGELOG.md:340 (historical entry, intentionally preserved)
```
