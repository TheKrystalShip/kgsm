# CLAUDE.md — overrides/

Overrides are game-specific module files that **replace** individual default
management-script modules during assembly. They externalize per-game logic
(custom version checks, non-Steam downloads, special deploy steps) so the core
stays generic. Full reference: `docs/overrides.md`; API reference:
`templates/overrides.tp`.

## Structure (module-based)

Each game gets a directory named after the blueprint's **logical name**:

```
overrides/<name>/05-version.sh
overrides/<name>/06-download.sh
...
```

An override module is a **complete copy** of the corresponding default module
from `templates/manage.{native,container}.d/`, with only the functions that need
game-specific behavior changed. Bundled examples: `factorio/`, `terraria/`,
`minecraft/`, `veloren/`, `barotrauma/`, `projectzomboid/` (each overrides only
the modules it needs, typically 05/06/07).

## How binding works (the critical gotcha)

The override directory name comes from the blueprint's logical name, **not** its
filename: the `name:` field in the blueprint (`<file>.bp.yaml`), for **both**
runtimes.

So `terraria-modded.bp.yaml` with `name: terraria` resolves to
`overrides/terraria/`, and several blueprint variants can deliberately share one
override dir. If the name doesn't line up, KGSM silently falls back to the
default module.

## Resolution order

For each overridable module, first match wins:
1. User: `~/.local/share/kgsm/overrides/<name>/<module>.sh` (respects `$XDG_DATA_HOME`)
2. System: `<KGSM_ROOT>/overrides/<name>/<module>.sh` (this directory)
3. Default: `templates/manage.{runtime}.d/<module>.sh`

Prefer the user dir for customization; system files here ship with KGSM.

## What may be overridden

Only modules **03–08, 10, 11** (the modules in the table below). `00–02` and
`12–13` are structural and cannot be overridden.

| Module | Key functions |
|--------|---------------|
| `03-lifecycle.sh` | `_start`, `_start_background`, `_stop_server` |
| `04-io.sh` | `_send_save_command`, `_send_input`, `_is_active` |
| `05-version.sh` | `_get_latest_version`, `_get_installed_version`, `_compare_versions`, `_save_version` |
| `06-download.sh` | `_download` |
| `07-deploy.sh` | `_deploy`, `_update` |
| `08-backup.sh` | `_create_backup`, `_list_backups`, `_restore_backup`, `_set_backup_retention`, `_clean_old_backups` |
| `10-logging.sh` | `_print_logs`, `_rotate_logs` |
| `11-status.sh` | status reporting |

Function signatures and return-code contracts are in `docs/overrides.md` and
`templates/overrides.tp` (e.g. `_get_latest_version` echoes a version or
`exit 1`; `_download`/`_deploy` return 0/1).

## Authoring rules

- **Copy the default module, then modify** — start from
  `templates/manage.{native,container}.d/<module>.sh`.
- **Keep every function** from the default present; the assembled script must be
  complete. Don't ship a partial module with only the changed function.
- Override functions run with all `$instance_*` and `$config_*` variables
  available; operate on those (`$instance_temp_dir`, `$instance_install_dir`,
  `$instance_saves_dir`, …).
- Use `__print_error` / `__print_warning` / `__print_info` for output and the
  `EC_*` codes (`return $EC_SUCCESS` / `return $EC_ERROR`), not magic numbers.
- Private helpers use the `__override_` prefix. Verify with `bash -n` and
  `shellcheck`; files must be readable (`chmod 644`).
- Behavioral certainty: a given code path must always have one defined outcome —
  don't make a check conditional on incidental state.
