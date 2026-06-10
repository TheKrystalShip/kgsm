# CLAUDE.md — templates/

Templates are the source artifacts KGSM expands to generate per-instance config,
management scripts, systemd units, and firewall rules. Full reference:
`docs/templates.md`.

> **Never modify these files to customize a single game or instance.** They are
> internal KGSM artifacts and may be overwritten on update. To customize: author
> a blueprint (user `blueprints/` dir) or an override (`overrides/<name>/`).

## How expansion works

`.tp` files are expanded by bash variable substitution: the template is
evaluated in a subshell with all relevant `$instance_*` and `$config_*`
variables exported, so any `$instance_name` / `${instance_ports}` reference is
replaced with its value. The engine is `commands/handlers/templates.sh`
(`__logic_expand_template*`, `__logic_validate_template_vars`, …); file
discovery is `__find_template` in `core/loader.sh`.

## Files

| File | Expanded? | Purpose |
|------|-----------|---------|
| `blueprint.tp` | No | Documented blank native blueprint; the canonical authoring reference. |
| `instance.tp` | Yes | Per-instance config (`.ini`); written at instance creation. Authoritative runtime config. |
| `manage.native.d/` | Yes (concatenated) | Numbered modules assembled into the management script for **native** instances. |
| `manage.container.d/` | Yes (concatenated) | Same, for **container** instances (lifecycle via `docker compose`). |
| `service.tp` | Yes | systemd `.service` unit. |
| `socket.tp` | Yes | systemd `.socket` unit (command FIFO). |
| `ufw.tp` | Yes | UFW application profile. |
| `overrides.tp` | No | API reference for authoring override modules. |

## Management-script modules (`manage.{native,container}.d/`)

Modules `00`–`13` are concatenated in numeric order into one
`#!/usr/bin/env bash` script. Each handles one concern:

- `00-header` `01-config` `02-help` — structural, **never overridden**.
- `03-lifecycle` `04-io` `05-version` `06-download` `07-deploy` `08-backup`
  `09-network` `10-logging` `11-status` — the **overridable** range (03–11);
  per-game modules in `overrides/<name>/` replace these by filename when present.
- `12-commands` `13-dispatch` — structural, **never overridden**.

Regenerate an instance's management script with:
`./kgsm.sh files --instance <name> --create --manage`.

## Editing rules

- `.tp` files use the same variables documented in `docs/templates.md`
  (Template Variables Reference). When you add a variable reference to a
  template, make sure the corresponding `$instance_*`/`$config_*` value is
  actually exported into the expansion subshell.
- These files are the **default implementations** override authors copy from —
  keep every function complete and self-contained, since an override module must
  contain *all* functions from the default, not just the changed one.
- Follow the repo style (Google Shell Style, 2-space indent, `function`
  keyword, quote expansions). Run `shellcheck` on module `.sh` files.
