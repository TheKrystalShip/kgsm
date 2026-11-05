# 01 — System Overview

This document describes the high-level architecture of KGSM: how the
process is organised, how commands are dispatched, where files live on
disk, and the conventions used for error reporting.

---

## 1. File-system layout

KGSM follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/).
There are two completely separate trees:

### 1.1 The installation tree (read-only after install)

Lives wherever KGSM was installed (e.g. `/usr/share/kgsm`, `/opt/kgsm`,
or a git clone). Contains:

```
<install-root>/
├── kgsm                          # Main executable (CLI entry point)
├── core/                         # Core library modules
├── commands/                     # User-facing command modules
│   └── handlers/                 # Pure-logic handlers
├── templates/                    # File-generation templates
│   ├── blueprint                 # Blank-blueprint template
│   ├── instance                  # Per-instance config template
│   ├── overrides                 # Override authoring template
│   ├── service                   # systemd .service template
│   ├── socket                    # systemd .socket template
│   ├── ufw                       # UFW application-profile template
│   ├── manage.native.d/          # Numbered modules for native instances
│   └── manage.container.d/       # Numbered modules for container instances
├── blueprints/
│   ├── native/                   # Bundled native blueprints
│   └── container/                # Bundled container blueprints
├── overrides/                    # Bundled per-game overrides
├── migrations/
│   └── config/                   # Numbered config-schema migrations
├── config.default.ini            # Authoritative default config
└── docs/
```

### 1.2 The user tree (writable, per-user)

Two locations under the XDG roots:

```
${XDG_CONFIG_HOME:-~/.config}/kgsm/
└── config.ini                    # User's effective config
                                  # (plus rotating backups: config.ini.0..9)

${XDG_DATA_HOME:-~/.local/share}/kgsm/
├── instances/                    # Symlink layer (see 1.3)
│   └── <blueprint>/<instance>/   # Symlink → instance working dir
├── logs/                         # KGSM operation logs
├── blueprints/
│   ├── native/                   # User-authored native blueprints
│   └── container/                # User-authored container blueprints
└── overrides/                    # User-authored overrides
    └── <blueprint-name>/         # Per-game override modules
```

**Lookup precedence.** Whenever KGSM resolves a blueprint or override by
name, it MUST search the user tree first and the install tree second.
This lets a user shadow any bundled artifact without modifying the
install tree.

### 1.3 Per-instance working directories

Instances are placed in a **library** — a named root registered with
`kgsm libraries add <path>`. `kgsm install` takes the library from
`--library <name>`, falling back to the `[instance_defaults]
default_library` config key, and then to the sole registered library when
exactly one is registered. The on-disk layout is:

```
<library-root>/instances/<blueprint>/<instance>/
├── <instance>.config.ini         # Instance config (INI)
├── <instance>.manage.sh          # Self-contained management script
├── <instance>.log                # Live server log output
├── .<instance>.pid               # Server process PID
├── .<instance>.tail.pid          # Log-tail process PID
├── .<instance>.sock              # Named pipe (FIFO) for sending console input
├── .<instance>.version           # Installed version string
├── install/                      # Game binaries / data
├── saves/                        # World / save data
├── backups/                      # Backup archives
├── logs/                         # Rotated historical logs
└── temp/                         # Download staging area
```

A **symlink** is created at `<KGSM_DATA>/instances/<blueprint>/<instance>`
that points at this directory. KGSM uses this symlink layer for
discovery. Every per-instance path is stored absolute in the instance's
own config — including `library_dir`, the root of the library it sits in
— so an instance is readable wherever its library root lives, and a
library whose disk is absent leaves the symlink dangling rather than
removing it.

### 1.4 Resolved paths exposed to the rest of the system

Every other module references the following path identifiers (names are
illustrative; an implementation may expose them differently):

| Identifier                             | Meaning                                 |
| -------------------------------------- | --------------------------------------- |
| `KGSM_ROOT`                            | Install tree root                       |
| `KGSM_CORE_DIR`                        | `<install>/core`                        |
| `KGSM_COMMANDS_DIR`                    | `<install>/commands`                    |
| `KGSM_HANDLERS_DIR`                    | `<install>/commands/handlers`           |
| `KGSM_TEMPLATES_DIR`                   | `<install>/templates`                   |
| `KGSM_MIGRATIONS_DIR`                  | `<install>/migrations`                  |
| `KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR`    | `<install>/blueprints/native`           |
| `KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR` | `<install>/blueprints/container`        |
| `KGSM_SYSTEM_OVERRIDES_DIR`            | `<install>/overrides`                   |
| `KGSM_DEFAULT_CONFIG_FILE`             | `<install>/config.default.ini`          |
| `KGSM_CONFIG_DIR`                      | `${XDG_CONFIG_HOME:-~/.config}/kgsm`    |
| `KGSM_CONFIG_FILE`                     | `<config-dir>/config.ini`               |
| `KGSM_DATA_DIR`                        | `${XDG_DATA_HOME:-~/.local/share}/kgsm` |
| `KGSM_INSTANCES_DIR`                   | `<data>/instances`                      |
| `KGSM_LOGS_DIR`                        | `<data>/logs`                           |
| `KGSM_USER_BLUEPRINTS_NATIVE_DIR`      | `<data>/blueprints/native`              |
| `KGSM_USER_BLUEPRINTS_CONTAINER_DIR`   | `<data>/blueprints/container`           |
| `KGSM_USER_OVERRIDES_DIR`              | `<data>/overrides`                      |

The CLI exposes `kgsm --paths` to print all resolved values.

### 1.5 First-run bootstrap

On first run (or whenever a user directory is missing) the tool MUST:

1. Create all eight user directories (with `mkdir -p` semantics).
2. If `<config-dir>/config.ini` is absent, copy `config.default.ini` to it.

These two steps MUST be idempotent.

---

## 2. Module organisation

The codebase has three layers:

```
┌──────────────────────────────────────────────────┐
│  CLI ENTRY (kgsm)                                │
│   Parses first positional, dispatches to module  │
└──────────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────┐
│  COMMAND MODULES (commands/*)                    │
│   - CLI argument parsing                         │
│   - User-facing output (info / warn / error)     │
│   - Calls the matching handler                   │
│   - Emits events on success                      │
│   - Translates handler results into exit codes   │
└──────────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────┐
│  HANDLER MODULES (commands/handlers/*)           │
│   - Pure business logic, no IO                   │
│   - Returns structured result OR exit code       │
└──────────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────┐
│  CORE LIBRARIES (core/*)                         │
│   - Config, paths, logging, validation,          │
│     parser, errors, events, system, overrides    │
└──────────────────────────────────────────────────┘
```

### 2.1 The command/handler split

This split is **intentional and MUST be preserved**. Rationale:

- **Testability.** Handlers are pure: same inputs → same exit code, no
  printing, no event emission, no file IO beyond what is strictly
  necessary. They can be exercised in tests without capturing stdout
  or mocking transports.
- **Reuse.** The same handler can be invoked from the CLI command,
  the interactive TUI, and (in future) a programmatic API.
- **Clear contract.** Commands convert handler results into:
  user-visible output, an event dispatch (when applicable), and a shell
  exit code.

In a higher-level language, "no IO" means handlers do not call
`print` / `log` directly. They MAY return a structured result object
that the command layer renders. Handlers MAY still touch the filesystem
when that *is* their job (e.g. writing an instance config).

### 2.2 Top-level commands

The CLI dispatches the first positional argument to one of these
modules (full reference in [08-cli-reference.md](08-cli-reference.md)):

| Command                | Module        | Purpose                                                           |
| ---------------------- | ------------- | ----------------------------------------------------------------- |
| `install` / `create`   | `install`     | Full install pipeline (create + download + deploy).               |
| `uninstall` / `remove` | `uninstall`   | Full removal pipeline.                                            |
| `interactive`          | `interactive` | Launch TUI menu.                                                  |
| `blueprints`           | `blueprints`  | List / inspect / find / validate blueprints.                      |
| `config`               | `config`      | Get / set / list / validate / merge / rollback / diff / reset.    |
| `directories`          | `directories` | Create / link / unlink / remove instance directories (low-level). |
| `events`               | `events`      | Manage event transports + emit events.                            |
| `files`                | `files`       | Generate / remove instance files (low-level).                     |
| `instances`            | `instances`   | List / info / status / generate-id / create / remove (low-level). |
| `lifecycle`            | `lifecycle`   | start / stop / restart / status / logs / is-active.               |
| `network`              | `network`     | Inspect / test ports, IP, DNS.                                    |
| `system`               | `system`      | Host shutdown / restart / uptime / load / memory / disk / info.   |
| `watcher`              | `watcher`     | Manage readiness watchers.                                        |

In addition, six **lifecycle shortcuts** are routed directly to the
`lifecycle` module so users can write `kgsm start <instance>` instead
of `kgsm lifecycle start <instance>`:

```
start  stop  restart  status  logs  is-active
```

Three meta commands are handled inside the entry point itself:

```
-h | --help | help          Print full usage.
-v | --version              Print KGSM version + license header.
--paths                     Print resolved path layout.
```

### 2.3 Global flags

| Flag      | Effect                                                                                                                                                                                                                                                                               |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--debug` | Enable verbose tracing for the whole process tree. Sets `KGSM_DEBUG=true` in the environment so child processes (the management script, watchers) inherit it. The flag MUST be stripped from the argument list before dispatching to a module so it does not interfere with parsing. |

### 2.4 The `interactive` module

A guided TUI menu that mirrors the CLI surface. Implementation is free,
but it MUST not have capabilities the CLI lacks — the TUI is purely a
front-end that calls the same commands. Users who automate KGSM rely
on every operation being CLI-accessible.

---

## 3. Initialization sequence

Every entry point (the main `kgsm` binary and any directly-invoked
sub-tool) MUST perform the following before doing anything else. In bash
this is the work of `core/bootstrap.sh`; in another language it should
be a single `init()` call at the top of `main`.

1. Inspect the argument list for `--debug`. If present, enable verbose
   tracing, set `KGSM_DEBUG=true`, and remove the flag from `argv`.
2. Resolve `KGSM_ROOT` (from the executable's location, falling back to
   the `KGSM_ROOT` environment variable).
3. Resolve all path identifiers in §1.4.
4. Create any missing user directories from §1.2.
5. If the user config file is absent, copy `config.default.ini` to it.
6. Load and parse the user config; expose every key as `config_<key>`
   (a flat, case-preserved namespace). See [02-data-model.md §1](02-data-model.md).
7. Initialise logging (timestamps, colour, optional file output).

Steps 1–7 MUST be idempotent and re-entrant — a sub-process that
re-runs them must short-circuit when it detects that initialisation
has already happened in the current process tree.

---

## 4. Logging

KGSM uses five log levels:

| Level     | Colour (when TTY supports it) | Stream                              |
| --------- | ----------------------------- | ----------------------------------- |
| `success` | green                         | stdout                              |
| `info`    | blue                          | stdout                              |
| `warning` | yellow                        | stdout                              |
| `error`   | red                           | stderr                              |
| `debug`   | magenta                       | suppressed unless `KGSM_DEBUG=true` |

Each emitted line MUST include:

- An ISO-8601 timestamp (`YYYY-MM-DD HH:MM:SS`).
- The log level.
- The caller's source location (file + line). In bash this comes from
  `BASH_SOURCE`/`BASH_LINENO`; in another language, use the equivalent
  stack-introspection facility.
- The message text.

When `enable_logging=true` in the global config, every line MUST also
be written (uncoloured) to `<KGSM_LOGS_DIR>/kgsm.log`. The log file
MUST be rotated when it exceeds `log_max_size_kb` kilobytes; the
rotated file's name MUST include a timestamp suffix.

Colour MUST be auto-disabled when stdout is not a TTY, when the
terminal advertises ≤8 colours, or when `KGSM_NO_COLOR` is set.

---

## 5. Error codes

KGSM uses a fixed numeric exit-code system. Codes are split into two
ranges:

### 5.1 Standard codes (0 – 99)

These are returned by handlers and propagated as the process exit code.
Reimplementations MUST keep these numeric values stable; downstream
scripts and the event system depend on them.

| Code | Constant                       | Meaning                                 |
| ---- | ------------------------------ | --------------------------------------- |
| 0    | `EC_SUCCESS`                   | Operation succeeded                     |
| 1    | `EC_ERROR`                     | Generic / unspecified error             |
| 2    | `EC_KGSM_ROOT`                 | `KGSM_ROOT` could not be resolved       |
| 3    | `EC_FAILED_CONFIG`             | Config file could not be loaded         |
| 4    | `EC_INVALID_CONFIG`            | Config file is malformed                |
| 5    | `EC_FILE_NOT_FOUND`            | A required file could not be found      |
| 6    | `EC_FAILED_SOURCE`             | Failed to load (source) a script/module |
| 7    | `EC_MISSING_ARG`               | A required argument was not supplied    |
| 8    | `EC_INVALID_ARG`               | An argument value was rejected          |
| 9    | `EC_FAILED_CD`                 | `cd` to a directory failed              |
| 10   | `EC_FAILED_CP`                 | File copy failed                        |
| 11   | `EC_FAILED_RM`                 | File removal failed                     |
| 12   | `EC_FAILED_TEMPLATE`           | Template expansion failed               |
| 13   | `EC_FAILED_DOWNLOAD`           | Download step failed                    |
| 14   | `EC_FAILED_DEPLOY`             | Deploy step failed                      |
| 15   | `EC_FAILED_MKDIR`              | Directory creation failed               |
| 16   | `EC_PERMISSION`                | Permission denied                       |
| 17   | `EC_FAILED_SED`                | Text-substitution step failed           |
| 18   | `EC_SYSTEMD`                   | `systemctl` invocation failed           |
| 19   | `EC_UFW`                       | `ufw` invocation failed                 |
| 20   | `EC_MALFORMED_INSTANCE`        | Instance config file is malformed       |
| 21   | `EC_MISSING_DEPENDENCY`        | Required external tool missing          |
| 22   | `EC_FAILED_LN`                 | Symlink creation failed                 |
| 23   | `EC_FAILED_UPDATE_CONFIG`      | Config write/update failed              |
| 24   | `EC_KEY_NOT_FOUND`             | Config key not found                    |
| 25   | `EC_NOT_FOUND`                 | Generic "item not found"                |
| 26   | `EC_FAILED_VERSION_SAVE`       | Saving installed version failed         |
| 27   | `EC_BLUEPRINT_NOT_FOUND`       | Blueprint resolution failed             |
| 28   | `EC_INVALID_BLUEPRINT`         | Blueprint failed validation             |
| 29   | `EC_INVALID_INSTANCE`          | Instance failed validation              |
| 30   | `EC_FAILED_MV`                 | File move failed                        |
| 32   | `EC_FAILED_TOUCH`              | File creation failed                    |
| 33   | `EC_FAILURE`                   | Generic failure (alternate to 1)        |
| 34   | `EC_MISSING_ARGS`              | Multiple required arguments missing     |
| 35   | `EC_SKIP`                      | Operation skipped (not an error)        |
| 36   | `EC_TIMEOUT`                   | Test or wait timed out                  |
| 37   | `EC_EVENT_TYPE_INVALID`        | Unknown event type                      |
| 38   | `EC_EVENT_PARAMS_INVALID`      | Wrong event parameters                  |
| 39   | `EC_EVENT_TRANSPORT_FAILED`    | Event delivery failed                   |
| 40   | `EC_EVENT_JSON_FAILED`         | Failed to build event JSON              |
| 41   | `EC_WATCHER_TIMEOUT`           | Watcher timed out                       |
| 42   | `EC_WATCHER_NO_STRATEGY`       | No watcher strategy applies             |
| 43   | `EC_WATCHER_PATTERN_NOT_FOUND` | Log pattern not found before timeout    |
| 44   | `EC_WATCHER_PORT_NOT_ACTIVE`   | Port did not become active              |
| 45   | `EC_WATCHER_LOG_FILE_MISSING`  | Log file does not exist                 |
| 46   | `EC_DIRECTORY_NOT_FOUND`       | Directory does not exist                |
| 245  | `EC_MIGRATION_FAILED`          | Config migration failed                 |
| 246  | `EC_MIGRATION_NOT_FOUND`       | Required migration script missing       |
| 247  | `EC_MISSING_CONFIG_KEY`        | Required config key missing             |
| 248  | `EC_INVALID_CONFIG_VALUE`      | Config value failed validation          |
| 249  | `EC_FAILED_BACKUP`             | Backup operation failed                 |

### 5.2 Success-event codes (200 – 255)

> **Note.** In the bash implementation these codes are returned from
> handlers to tell the command layer "succeeded — please emit *this*
> event". This is a workaround for bash's lack of a richer return type
> and SHOULD NOT be reproduced in another language. Instead, handlers
> should return a normal success result and explicitly emit events from
> the command layer. The event names below are still authoritative.

| Code | Event name                         |
| ---- | ---------------------------------- |
| 200  | `server.install.directories_created`     |
| 201  | `server.uninstall.directories_removed`     |
| 202  | `server.install.files_created`           |
| 203  | `server.uninstall.files_removed`           |
| 204  | `instance-config-installed`        |
| 205  | `instance-config-uninstalled`      |
| 206  | `instance-management-file-created` |
| 207  | `instance-management-file-removed` |
| 208  | `instance-systemd-enabled`         |
| 209  | `instance-systemd-disabled`        |
| 210  | `server.install.created`                 |
| 211  | `server.started`                 |
| 212  | `server.stopped`                 |
| 213  | `server.restarted`               |
| 214  | `server.uninstall.removed`                 |
| 215  | `instance-ufw-enabled`             |
| 216  | `instance-ufw-disabled`            |
| 217  | `instance-symlink-created`         |
| 218  | `instance-symlink-removed`         |
| 219  | `instance-upnp-enabled`            |
| 220  | `server.deploy.started`          |
| 221  | `server.deploy.finished`         |
| 222  | `server.ready`                   |
| 223  | `blueprint-listed`                 |
| 224  | `blueprint-info-retrieved`         |
| 225  | `blueprint-found`                  |
| 226  | `blueprint-validated`              |
| 230  | `backup.created`          |
| 231  | `backup.restored`         |
| 240  | `config-set`                       |
| 241  | `config-reset`                     |
| 242  | `config-validated`                 |
| 243  | `config-merged`                    |
| 250  | `system-shutdown`                  |
| 251  | `system-restart`                   |
| 252  | `system-info-retrieved`            |
| 253  | `network-port-checked`             |
| 254  | `network-port-free`                |
| 255  | `network-port-in-use`              |

The event payload format is in [05-events.md](05-events.md).

### 5.3 Error-message map

The implementation MUST expose a lookup from numeric code to a short
human-readable message (the bash version uses an associative array
named `EXIT_CODES`). The CLI uses this when reporting failures.

---

## 6. Module discovery and loading

In bash, every script begins by `source`-ing `core/bootstrap.sh`,
which then loads every other core module. A higher-level language can
replace this with normal imports.

The two patterns that DO need preserving regardless of language:

1. **Lookup priority**. When resolving a blueprint or override by name,
   user-tree paths MUST be searched before install-tree paths. See the
   `find_blueprint` / `find_override` algorithms in
   [02-data-model.md §2.4](02-data-model.md) and
   [03-management-script-and-overrides.md §3](03-management-script-and-overrides.md).
2. **Sub-process invocation of the same tool**. Several flows
   (notably the readiness watcher) need to invoke another KGSM command
   from inside a running command. The implementation MUST allow this
   without re-doing first-run bootstrap (i.e. avoid repeated `mkdir`s
   and config copies on every invocation). A guard that detects "init
   already ran in this process tree" is sufficient.

---

## 7. Runtime dependencies

The implementation language is free to choose its own dependencies, but
KGSM relies on these external tools at runtime, called via subprocess:

**Required:**

- `wget` — Downloads (game files, version-check API calls, webhooks).
- `jq` — JSON parsing in some overrides.
- `tar`, `unzip` — Archive extraction during downloads.
- `sed`, `grep`, `coreutils`, `findutils` — General text/file work.
- `steamcmd` — Default download mechanism for Steam-based games.
- `inotify-tools` — Used by some watcher implementations.

**Optional (controlled by config flags):**

- `ufw` — Firewall integration (`enable_firewall_management`).
- `socat` — Unix-socket event transport (`enable_socket_events`).
- `miniupnpc` (`upnpc`) — UPnP port forwarding (`enable_port_forwarding`).
- `systemd` (`systemctl`) — systemd integration (`enable_systemd`).
- `docker` + `docker compose` — Required for any container instance.
- `ss`, `tail` — Used by watchers.

A reimplementation MAY use native libraries instead of subprocess
invocations where appropriate (e.g. an HTTP client instead of `wget`),
but MUST NOT lose feature parity for game-specific overrides that rely
on these tools being available — overrides are user code and they
shell out directly.
