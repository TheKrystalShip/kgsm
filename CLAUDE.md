# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

KGSM (Krystal Game Server Manager) is a bash-based game server orchestration system for Linux. It deploys and manages diverse game servers — both native Linux processes and Docker containers — through a single CLI, using a blueprint-driven architecture.

## Commands

```bash
# Run KGSM
./kgsm.sh --help
./kgsm.sh --debug <command>          # trace output; also: export KGSM_DEBUG=true

# Lint (must pass clean; SC2086 is globally disabled for unquoted exit codes)
shellcheck path/to/script.sh

# Tests
./tests/run.sh                                   # all (unit + integration + e2e)
./tests/run.sh unit                              # one type (unit | integration | e2e)
./tests/run.sh --pattern 'test_config_*.sh'      # filename glob
./tests/run.sh --pattern 'test_config_merge_logic.sh' --function 'test_merge_preserves_user_values'
./tests/run.sh --debug-run tests/unit/test_x.sh  # inline run of one file, full trace, for debugging
```

`tests/run.sh` emits TAP v14 (it's the VS Code Test Adapter entry point), but the CLI invocations above are the supported way to run tests by hand.

## Architecture

### Entry point and dispatch
`kgsm.sh` parses the first argument and passes through to a top-level command module in `commands/` (e.g. `install`/`create` → `install.sh`, `config` → `config.sh`, `blueprints` → `blueprints.sh`). Every module sources `core/bootstrap.sh` first, which detects and exports `KGSM_ROOT`, then loads `core/common.sh` and the rest of the library.

### Module loading (`core/bootstrap.sh`, `core/loader.sh`, `core/delegator.sh`)
- Files are located dynamically via `__find_command()`, `__find_core_module()`, `__find_or_fail()` — don't hardcode paths.
- Modules are lazy-loaded behind guards (`if [[ ! $KGSM_COMMON_LOADED ]]`).
- Any function called from a subshell **must** be exported with `export -f function_name`, or it won't exist in the child process. This is the most common silent breakage.
- `--debug` / `KGSM_DEBUG=true` propagates into all sub-shells.

### Command / Handler split
`commands/*.sh` are the I/O layer: argument parsing, user-facing messages, calling `__print_error`/`__print_warning`/`__print_info`. The actual business logic lives in `commands/handlers/*.sh` as pure functions that take inputs and return exit codes with no I/O. Put logic in handlers so it stays testable and reusable; keep `commands/` thin. The two layers are paired by name (`commands/instances.sh` ↔ `commands/handlers/instances.sh`).

### Blueprint → Instance → Override (the core data model)
- **Blueprints** (`blueprints/*.bp.yaml`) are **unified YAML** templates — one file per game in a single flat directory — that are a game server's complete identity: `schema_version`, `name`, `runtime` (`native`|`container`), a nullable `metadata:` block (display name + resource requirements, for UIs), and a runtime-tagged body (`native:` fields or `container.compose`). The `runtime` **field** replaces the old file-extension/directory type split. Parsed with **mikefarah/yq** (Arch `go-yq`), a **hard dependency**. Native `ports` is single-quoted, pipe-separated (`'1111:2222/tcp|3333/udp'`); container ports are **derived** from the embedded compose. Metadata values are nullable — `null` means unknown, **never a fabricated `0`**. These are the system (read-only) blueprints; user blueprints live under `~/.local/share/kgsm/blueprints/*.bp.yaml` and shadow same-named system ones. See `blueprints/CLAUDE.md`.
- **Instances** are deployed servers created from a blueprint, each with isolated `server/ saves/ backups/ logs/` directories and a generated management script.
- **Overrides** (`overrides/<name>/NN-*.sh`) supply game-specific install/update/lifecycle logic as module-based files. See `overrides/CLAUDE.md`.

**Critical gotcha:** a blueprint binds to an override directory by its logical *name*, *not* its filename — the `name` field, for **both** runtimes (containers no longer bind on the first `services:` entry). `terraria-modded.bp.yaml` with `name: terraria` uses `overrides/terraria/`. This lets multiple blueprint variants share one override directory.

The override system is **module-based**: a game's override directory (`overrides/<name>/`) holds complete copies of the default management-script modules from `templates/manage.{native,container}.d/`, with only the game-specific functions changed. Only modules `03`–`11` may be overridden. The older single-file `<name>.overrides.sh` form is legacy and no longer used for script assembly. Override functions follow fixed signatures documented in `templates/overrides.tp` (the authoritative API reference) — e.g. `_get_latest_version()` echoes a version or `exit 1`; `_download()`/`_deploy()` return 0/1. They operate on `instance_*` variables (`instance_install_dir`, `instance_temp_dir`, `instance_working_dir`, etc.). Read `templates/overrides.tp` before writing an override; copy `overrides/factorio/` or `overrides/terraria/` as a working example.

### Error codes (`core/errors.sh`)
All exit codes are named `EC_*` constants (`EC_OKAY=0`, `EC_BLUEPRINT_NOT_FOUND=27`, `EC_MIGRATION_FAILED=245`, …). Return these, not magic numbers. Exit codes are written unquoted (`return $EC_GENERAL`) — this is why SC2086 is disabled globally in `.shellcheckrc`.

### Configuration (`core/config.sh`, `config.default.ini`, `migrations/config/`)
Sectioned INI (`[system]`, `[network]`, `[steam]`, `[services]`, `[instance_defaults]`, `[events]`, `[watchers]`, `[accessibility]`) with a `config_schema_version`. At runtime keys are flattened to `config_*` exported variables. User config lives at `~/.config/kgsm/config.ini` and is merged with `config.default.ini` on update — the merge preserves user values, adds new keys, comments out deprecated ones, and keeps 10 numbered backups.

Schema changes go through sequential idempotent migrations in `migrations/config/` (`001_*`, `002_*`, …) that run automatically when the schema version bumps. To change config schema: add the migration script, bump `config_schema_version` in `config.default.ini`, and add a case to `tests/unit/test_config_migrations.sh`. User-facing config CLI: `config merge | rollback [0-9] | diff [0-9] | validate`.

Paths follow the XDG base directory spec (`~/.local/share/kgsm/` for instances/blueprints/overrides/logs). See `core/paths.sh`.

## Conventions

- **Style:** Google Shell Style Guide, 2-space indent, lines ≤80 chars (never >120), `#!/usr/bin/env bash` shebang, always use the `function` keyword, prefer `[[` over `[`, quote all variable expansions (exit codes excepted, per above).
- **Naming:** private functions `_name()`, internal library helpers `__name()`, public command logic plain. Variable prefixes: `config_*` for config, `instance_*` for instance state, `_var` for locals/internal.
- **Avoid `eval`**; sanitize any user input that reaches a command.
- **Behavioral certainty:** every code path must have a single defined, testable outcome — no "may succeed or fail depending on implementation." A check either always runs or never runs; don't make it conditional on incidental state. (E.g. ID generation either always validates the blueprint or never does — never "sometimes.")

## Testing

Tests run against full sandboxed copies of KGSM under `/tmp/kgsm-test-sandbox-*/` with **no mocking** — they exercise real KGSM code. Sandboxing also isolates XDG paths so tests don't touch the real `~/.config` / `~/.local/share`.

The testing framework has its own substantial conventions (per-test setup/teardown hooks, the assertion library, the test template, TAP output, discovery). Before writing or modifying anything under `tests/`, read `docs/specs/testing-framework/testing_specification.md` and `tests/templates/test.template.sh`, and model new tests on an existing file of the same type. This area is treated as its own specialized domain — `.github/agents/testing.agent.md` and `.github/skills/create-test/` describe the workflow the project uses for test work; the key transferable rule is to follow the documented spec rather than improvising test structure.

## Integration points (all opt-in via config flags)

UFW firewall rules (`enable_firewall_management`) and a webhook/socket event system (`commands/events.*.sh`, `enable_event_broadcasting`). Log/port watchers live in `commands/watcher.*.sh`.

Native instances are supervised by the resident **kgsm-watchdog** daemon (cgroup-v2 spawn + crash-restart). `kgsm start/stop` route to it when present (`commands/handlers/watchdog.sh`), and `kgsm autostart enable|disable|status|list` controls boot auto-start via its persisted desired-state — the in-house replacement for systemd's `enable`/`WantedBy=`. systemd is no longer an instance lifecycle manager.

## Key references

- `templates/overrides.tp` — complete override API
- `docs/` — `execution_flows.md`, `blueprints.md`, `overrides.md`, `instances.md`, `configuration_management.md`
- `docs/specs/testing-framework/testing_specification.md` — required before touching tests
- Examples: `blueprints/factorio.bp.yaml` (native), `blueprints/vrising.bp.yaml` (container), `overrides/factorio/`, `migrations/config/001_v0_to_v1_flat_to_sectioned.sh`
