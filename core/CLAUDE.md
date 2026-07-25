# CLAUDE.md — core/

The foundational library every command and handler depends on. Subtle, load-
bearing machinery — change with care. Derived from the code here; there is no
`docs/` page for this layer.

## Load chain

Every entry point sources `bootstrap.sh` first. Bootstrap, in order:
1. Handles the `--debug` flag (strips it from `$@`, exports `KGSM_DEBUG=true`,
   enables `set -x` with a colorized `PS4` — this propagates into all subshells).
2. Resolves and exports **`KGSM_ROOT`** from its own location (`core/`'s parent)
   if not already set — this is what makes the library path-independent.
3. Sources `paths.sh`, runs `__init_user_directories`, then sources
   `common.sh`, which pulls in the rest of the library.

After bootstrap, modules are reached via the `__find_*` locators in `loader.sh`
(`__find_core_module`, `__find_command`, `__find_command_handler`,
`__find_blueprint`, `__find_template`, `__find_override`, `__find_or_fail`).
**Never hardcode module paths.**

## The two universal patterns

- **Lazy-load guard** — every module is loaded behind a guard so re-sourcing is
  a no-op: `if [[ -n "${KGSM_X_LOADED:-}" ]]; then return 0; fi` … set the flag
  (and `export` it) at the end. Bootstrap uses `KGSM_BOOTSTRAP_LOADED`.
- **`export -f` for subshell functions** — any function that must exist in a
  child process has to be exported. Missing exports are the most common silent
  breakage in the codebase.

## Module ownership

| Module | Owns |
|--------|------|
| `bootstrap.sh` | Debug flag, `KGSM_ROOT`, initial load sequence |
| `loader.sh` | All dynamic file discovery (`__find_*`), blueprint/instance sourcing |
| `delegator.sh` | Shortcut accessors so modules can call into each other |
| `common.sh` | Aggregates/loads the common library surface |
| `paths.sh` | XDG path resolution (`~/.local/share/kgsm`, `~/.config/kgsm`); user-dir init |
| `errors.sh` | All `EC_*` exit-code constants (`EC_SUCCESS=0`, …) |
| `config.sh` | INI load/flatten to `config_*` vars; merge logic |
| `overrides.sh` | Resolving `overrides/<name>/` modules during management-script assembly |
| `validation.sh` | Input/blueprint/instance validation helpers |
| `parser.sh` | Argument / value parsing |
| `events.sh` | Event broadcasting (webhook/socket) |
| `logging.sh` | `__print_*` output + file logging |
| `ui.sh` | Interactive UI / menu primitives |
| `system.sh` | System-level tasks for other modules |

## Conventions

- Public-ish library helpers are `__name()`; constants are `UPPER_CASE`.
- Return `EC_*` codes unquoted (SC2086 disabled globally), never magic numbers.
- Google Shell Style, 2-space indent, ≤80 cols, `function` keyword, `[[` over
  `[`, quote all expansions (exit codes excepted). `shellcheck` must pass clean.
- `--debug` / `KGSM_DEBUG=true` must keep working through any new subshell you
  spawn — don't swallow the environment.
