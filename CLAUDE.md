# CLAUDE.md

KGSM (Krystal Game Server Manager) is a bash game-server manager for Linux: native processes and
containers, installed and run from declarative blueprints through one CLI. It is the engine's stateless
half; `kgsm-watchdog` is the resident half. Role, contracts and peers: `../kgsm-docs/components/kgsm.md`.
The engine model: `../kgsm-docs/systems/engine/`.

## Commands

```bash
./kgsm.sh --help
./kgsm.sh --debug <command>          # trace output; also: export KGSM_DEBUG=true

shellcheck path/to/script.sh         # must pass clean; SC2086 is disabled globally for unquoted exit codes

./tests/run.sh                                   # all (unit + integration + e2e)
./tests/run.sh unit                              # one type (unit | integration | e2e)
./tests/run.sh --pattern 'test_config_*.sh'      # filename glob (or a fragment: 'config')
./tests/run.sh --pattern 'test_config_merge_logic.sh' --function 'test_merge_preserves_user_values'
./tests/run.sh --debug-run tests/unit/test_x.sh  # inline run of one file, full trace
```

`tests/run.sh` emits TAP v14 (the VS Code Test Adapter entry point).

## Code map

- `kgsm.sh` dispatches the first argument to a command module in `commands/`. Every module sources
  `core/bootstrap.sh` first, which exports `KGSM_ROOT` and loads `core/common.sh` and the library.
- Locate files with `__find_command()`, `__find_core_module()`, `__find_or_fail()`; never hardcode paths.
  Modules lazy-load behind guards (`if [[ ! $KGSM_COMMON_LOADED ]]`).
- **A function called from a subshell must be exported with `export -f`**, or it does not exist in the
  child. This is the most common silent breakage. `--debug` / `KGSM_DEBUG=true` propagates to sub-shells.
- `commands/*.sh` are the I/O layer (argument parsing, `__print_*` messages). Logic lives in
  `commands/handlers/*.sh` as pure functions returning exit codes, paired by name
  (`commands/instances.sh` and `commands/handlers/instances.sh`). Keep `commands/` thin.
- Exit codes are `EC_*` constants in `core/errors.sh`, written unquoted (`return $EC_GENERAL`); return
  those, never magic numbers.
- Config is sectioned INI (`core/config.sh`, `config.default.ini`), flattened to `config_*` variables at
  runtime. A schema change is a sequential idempotent migration in `migrations/config/`, a bumped
  `config_schema_version` in `config.default.ini`, and a case in `tests/unit/test_config_migrations.sh`.
  Paths follow XDG (`core/paths.sh`).
- Blueprints (`blueprints/*.bp.yaml`, parsed with mikefarah/yq, a hard dependency) and overrides
  (`overrides/<name>/NN-*.sh`) are governed by `blueprints/CLAUDE.md` and `overrides/CLAUDE.md`. A blueprint
  binds to an override directory by its `name` field, not its filename, for both runtimes. Blueprint
  metadata is nullable: `null` is unknown, never a fabricated `0`. Only override modules `03`-`08`, `10`
  and `11` exist to be overridden; `templates/overrides.tp` is the API reference.
- Native lifecycle routes to the watchdog (`commands/handlers/watchdog.sh`); `autostart` controls boot
  start through the watchdog's desired-state.
- Events are always appended to the on-disk journal (`commands/events.journal.sh`); `docs/events.md`
  holds the engine's event reference.

## Conventions

- Google Shell Style Guide, 2-space indent, lines at most 80 characters (never over 120),
  `#!/usr/bin/env bash`, the `function` keyword, `[[` over `[`, every expansion quoted (exit codes excepted).
- Private functions `_name()`, internal library helpers `__name()`. Prefixes: `config_*`, `instance_*`,
  `_var` for locals.
- Avoid `eval`; sanitize user input that reaches a command.
- Every code path has one defined, testable outcome. A check either always runs or never runs; it is
  never conditional on incidental state.

## Testing

Tests run against full sandboxed copies of KGSM under `/tmp/kgsm-test-sandbox-*/` with no mocking; the
sandbox isolates XDG paths from the real `~/.config` and `~/.local/share`. Before writing or modifying
anything under `tests/`, read `docs/specs/testing-framework/testing_specification.md` and
`tests/templates/test.template.sh`, and model a new test on an existing file of the same type.
`.github/agents/testing.agent.md` and `.github/skills/create-test/` describe the workflow.

## Deployment

`/opt/kgsm` is a byte-identical copy of this checkout, published by `./deploy/deploy.sh` (rsync, no sudo,
no prompts, prunes deleted files; instances, config and logs under XDG are untouched). `./deploy/setup.sh`
runs once per host: it creates `/opt/kgsm` owned by you, the `kgsm` symlink on `PATH`, and the
`kgsm-journal-prune` timer, so no polkit grant is needed. Run `deploy.sh` after changing engine code.
`deploy/deploy-common.sh` holds the shared paths; the scripts are self-contained.

`deploy/kgsm.actions.json` is the engine's action manifest, written by hand. kgsm-lib's `KgsmActions`
mirrors it and a kgsm-lib test fails when the two disagree, so an action added here is added there in the
same change. Format: `../kgsm-docs/reference/action-manifest.md`.

## Version tracking

- The version is `KGSM_VERSION` in `core/bootstrap.sh`; `./deploy/version.sh` prints it (`--pkgver` for the
  pacman form) and packaging asks for it.
- Bump it for every user-facing change: patch for fixes, minor for features, major for breaking changes.
- Add a `CHANGELOG.md` entry under `## [Unreleased]` for every meaningful change.
- Tag the bump commit `git tag -a v<version> -m "kgsm v<version>"`.

## Read before changing

- `templates/overrides.tp`: the override API.
- `docs/`: `execution_flows.md`, `blueprints.md`, `overrides.md`, `instances.md`, `libraries.md`,
  `configuration_management.md`, `events.md`.
- `../kgsm-docs/reference/event-envelope.md`, `event-journal.md`, `event-vocabulary.md`: the journal
  line the engine writes.
- `../kgsm-docs/reference/maintenance-windows.md` and `../kgsm-docs/systems/operations/`: windows and
  announcements.

Docs and comments describe the system as it is now: present tense, no history, no emoji, no volatile
numbers (workspace `../CLAUDE.md`).
