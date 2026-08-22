# CLAUDE.md — commands/

Top-level command modules dispatched from `kgsm.sh`. This is where most feature
work happens. Derived from the code here; there is no `docs/` page for this
layer.

## The two-layer split (enforced, not optional)

- `commands/*.sh` — **I/O layer**. Argument parsing, `show_usage*` help text,
  user-facing messages via `__print_error` / `__print_warning` / `__print_info`
  / `__print_success`, JSON output. Keep these **thin**.
- `commands/handlers/*.sh` — **pure logic layer**. Functions that take inputs
  and communicate *only* via exit codes, with **no user-facing I/O**. Business
  logic lives here so it stays testable and reusable.

The two are paired by name: `commands/instances.sh` ↔
`commands/handlers/instances.sh`. When adding logic, put it in the handler and
call it from the command; don't grow the command file.

## File families

Related commands cluster by prefix — keep new files in the existing family:
- `blueprints.sh` (one unified module — the former `blueprints.native.sh` /
  `blueprints.container.sh` split is gone, since runtime is now a blueprint field)
- `files.sh`, `files.management.sh`, `files.firewall.sh`,
  `files.symlink.sh` (+ paired handlers)
- `events.sh`, `events.journal.sh`, `events.webhook.sh`
- `watcher.sh`, `watcher.logs.sh`, `watcher.ports.sh`
- lifecycle: `install.sh`, `uninstall.sh`, `lifecycle.sh`, `instances.sh`,
  `autostart.sh` (boot auto-start enable/disable via the watchdog)
- `config.sh`, `system.sh`, `network.sh`, `directories.sh`, `libraries.sh`
  (instance placement roots), `interactive.sh`

Handlers without a 1:1 command pair exist for shared logic
(`handlers/files.common.sh`, `handlers/menus.sh`, `handlers/wizards.sh`,
`handlers/templates.sh`).

## Conventions specific to this layer

- **Every file sources bootstrap first:**
  `source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"` — never
  hardcode other paths; locate things via `__find_command`,
  `__find_command_handler`, `__find_core_module`, `__find_or_fail`.
- **Handler functions are `__logic_*`** (internal helpers `__name`), and
  **any function used in a subshell MUST be `export -f`'d** right after its
  definition (used 31× across this tree — forgetting it is the most common
  silent breakage). See `handlers/instances.sh` for the pattern.
- **Lazy-load guard** at the top of handlers:
  `if [[ -n "${KGSM_LOGIC_X_LOADED}" ]]; then return 0; fi` … set it at the end.
- **Exit-code contract** (from `handlers/instances.sh`):
  - `0` — success, no event
  - `200`–`255` — **success *with* event emission** (the command layer reacts by
    broadcasting an event). Going past 255 overflows back to 1 since bash uses a
    single byte for the exit code.
  - named `EC_*` codes (`core/errors.sh`) — errors. Never magic numbers.
  Return codes are written unquoted (SC2086 disabled globally), e.g.
  `return $EC_BLUEPRINT_NOT_FOUND`.

## Style

Google Shell Style, 2-space indent, ≤80 cols, `function` keyword, `[[` over `[`,
quote all expansions (exit codes excepted). `shellcheck` must pass clean.
