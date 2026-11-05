# 08 — CLI Reference

This is the complete user-facing CLI surface of the parent KGSM tool.
Subordinate command modules each have their own `--help` / `help`
subcommand; this document is the contract those help texts must
satisfy.

Conventions:

- `<required>` — positional argument.
- `[optional]` — optional positional or flag.
- `<a> | <b>` — mutually exclusive choices.
- All commands accept `-h`, `--help`, or `help` and print
  command-specific usage.
- All commands accept the global `--debug` flag, which is stripped
  before dispatch.

The exit code of every command is one of the values in
[01-system-overview.md §5.1](01-system-overview.md#51-standard-codes-0--99).
The success-event codes (200 – 255) MUST be translated to `0` before
being returned to the user's shell.

---

## 1. Top-level

```
kgsm <command> [args] [options]
```

| Command                                                             | Purpose                                                                               |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `-h` \| `--help` \| `help`                                          | Print global usage.                                                                   |
| `-v` \| `--version`                                                 | Print version + license header.                                                       |
| `--paths`                                                           | Print resolved path layout (see [01-system-overview.md §1.4](01-system-overview.md)). |
| `install` \| `create`                                               | Install a new instance. (§2)                                                          |
| `uninstall` \| `remove`                                             | Uninstall an instance. (§3)                                                           |
| `interactive`                                                       | Launch the menu-driven UI.                                                            |
| `blueprints`                                                        | Inspect and validate blueprints. (§4)                                                 |
| `config`                                                            | Manage the global config file. (§5)                                                   |
| `directories`                                                       | Low-level: create / remove instance directories.                                      |
| `files`                                                             | Low-level: create / remove instance files.                                            |
| `libraries`                                                         | Register / list / rename / deregister instance libraries.                             |
| `instances`                                                         | List / inspect / generate-id / create / move / remove instances. (§6)                 |
| `lifecycle`                                                         | start / stop / restart / status / logs / is-active. (§7)                              |
| `events`                                                            | Manage and emit events. (§8)                                                          |
| `network`                                                           | Network diagnostics. (§9)                                                             |
| `system`                                                            | Host system commands. (§10)                                                           |
| `watcher`                                                           | Manage readiness watchers. (§11)                                                      |
| `start` \| `stop` \| `restart` \| `status` \| `logs` \| `is-active` | Shortcuts for `lifecycle <verb>`.                                                     |

---

## 2. `install`

```
kgsm install <blueprint> [--library <name>] [--name <id>] [--version <ver>]
                         [--skip-space-check]
```

| Argument               | Meaning                                                  |
| ---------------------- | -------------------------------------------------------- |
| `<blueprint>`          | Logical name (with or without extension).                |
| `--library <name>`     | Library the instance is placed in. Default: the configured `default_library`, else the sole registered library. |
| `--name <id>`          | Custom instance ID. Default: auto-generated `<bp>-<NN>`. |
| `--version <ver>`      | Specific version. Default `0` / `latest`.                |
| `--skip-space-check`   | Install even when the library has less free room than the blueprint declares the game needs. |

The instance lands at `<library-root>/instances/<blueprint>/<instance>`.

Exit codes: `EC_SUCCESS`, `EC_BLUEPRINT_NOT_FOUND`,
`EC_INVALID_BLUEPRINT`, `EC_MISSING_ARG`, `EC_LIBRARY_OFFLINE`,
`EC_FAILED_DOWNLOAD`, `EC_FAILED_DEPLOY`, `EC_FAILED_MKDIR`,
`EC_PERMISSION`.

Aliases: `create`.

---

## 3. `uninstall`

```
kgsm uninstall <instance>
```

| Argument     | Meaning                                       |
| ------------ | --------------------------------------------- |
| `<instance>` | Instance ID (the `name` field of its config). |

Aliases: `remove`. Destructive — see [04-lifecycle-flows.md §10](04-lifecycle-flows.md).

Exit codes: `EC_SUCCESS`, `EC_FILE_NOT_FOUND`, `EC_ERROR`.

---

## 4. `blueprints`

```
kgsm blueprints <subcommand> [args]
```

| Subcommand      | Args                               | Purpose                                                 |
| --------------- | ---------------------------------- | ------------------------------------------------------- |
| `list`          | `[--native\|--container] [--json]` | List available blueprints (logical names).              |
| `info <bp>`     |                                    | Print the blueprint file's contents (or a parsed view). |
| `find <bp>`     |                                    | Print the absolute path of the resolved blueprint file. |
| `validate <bp>` |                                    | Validate per [02-data-model.md §2.7](02-data-model.md). |

JSON output of `list --json`:

```json
[
  { "name": "factorio", "type": "native", "path": "/abs/.../factorio.bp" },
  { "name": "vrising",  "type": "container", "path": "/abs/.../vrising.docker-compose.yml" }
]
```

---

## 5. `config`

```
kgsm config <subcommand> [args]
```

| Subcommand          | Args                     | Purpose                                                     |
| ------------------- | ------------------------ | ----------------------------------------------------------- |
| `list`              | `[--json]`               | Print every key=value with sections.                        |
| `get <key>`         |                          | Print the value of a single key.                            |
| `set <key>=<value>` |                          | Update one key (writes through merge logic).                |
| `validate`          |                          | Verify all required keys present; values in range.          |
| `merge`             |                          | Run the merge algorithm against `config.default.ini`.       |
| `rollback [N]`      | `N` ∈ `0..9` (default 0) | Restore `config.ini.N`.                                     |
| `diff [N]`          |                          | Diff current file vs `config.ini.N`.                        |
| `reset`             |                          | Replace user file with `config.default.ini` (after backup). |

Exit codes: `EC_SUCCESS`, `EC_SUCCESS_CONFIG_MERGED` → `0`,
`EC_INVALID_CONFIG`, `EC_INVALID_CONFIG_VALUE`, `EC_MISSING_CONFIG_KEY`,
`EC_FAILED_BACKUP`, `EC_MIGRATION_FAILED`.

---

## 6. `instances`

```
kgsm instances <subcommand> [args]
```

| Subcommand          | Args                                             | Purpose                                                  |
| ------------------- | ------------------------------------------------ | -------------------------------------------------------- |
| `list`              | `[<blueprint>] [--detailed] [--status] [--json]` | Enumerate instances (optionally filtered by blueprint).  |
| `info <instance>`   | `[--json]`                                       | Print full instance details.                             |
| `status <instance>` | `[--json] [--fast]`                              | Same as `lifecycle status`.                              |
| `generate-id <bp>`  | `[--name <name>]`                                | Compute a fresh unique instance ID and print it.         |
| `create <bp>`       | `[--library <name>] [--name <id>]`               | Write only the per-instance config (no download/deploy). |
| `move <instance>`   | `--library <name> [--skip-space-check]`          | Move a stopped instance's files into another library.    |
| `remove <instance>` |                                                  | Remove only the per-instance config (no files/dirs).     |

`list --json` shape:

```json
[
  {
    "name": "factorio-01",
    "blueprint": "factorio",
    "runtime": "native",
    "lifecycle_manager": "systemd",
    "directory": "/opt/servers/factorio/factorio-01",
    "install_datetime": "2024-09-15T18:22:11Z",
    "status": "running"     // only when --status is passed
  }
]
```

---

## 7. `lifecycle`

```
kgsm lifecycle <verb> <instance> [verb-args]
```

Or, via shortcut: `kgsm <verb> <instance> [verb-args]`.

| Verb        | Args                                     | Purpose                                                                           |
| ----------- | ---------------------------------------- | --------------------------------------------------------------------------------- |
| `start`     | `[--detached]`                           | Start the instance. `--detached` skips the attach loop.                           |
| `stop`      | `[--no-save] [--no-graceful]`            | Stop. `--no-save` skips the save command; `--no-graceful` skips the stop command. |
| `restart`   |                                          | Stop then start.                                                                  |
| `status`    | `[--json] [--fast]`                      | Print rich status. `--fast` skips the upstream version check.                     |
| `logs`      | `[-f \| --follow] [--tail <N>] [-n <N>]` | Tail the instance log.                                                            |
| `is-active` |                                          | Returns `0` if running, non-zero otherwise.                                       |

`status --json` shape (matches what the management script's
`_get_status --json` returns):

```json
{
  "instance_name": "factorio-01",
  "status": true,
  "process": { "pid": 12345, "status": "S", "start_time": "Mon Sep 15 18:00:00 2024" },
  "version": { "current": "1.1.94", "latest": "1.1.94", "updates_available": false },
  "configuration": {
    "blueprint": "factorio.bp",
    "runtime": "native",
    "lifecycle_manager": "systemd",
    "directory": "/opt/servers/factorio/factorio-01",
    "ports": "34197/udp"
  },
  "resources": { "disk_usage": "412M" },
  "backups": [ "factorio-01-1.1.93-2024-09-10T12:00:00.backup" ],
  "recent_logs": [ "...", "...", "..." ]
}
```

---

## 8. `events`

```
kgsm events <subcommand> [args]
```

| Subcommand          | Args                                                 | Purpose                                     |
| ------------------- | ---------------------------------------------------- | ------------------------------------------- |
| `status`            |                                                      | Print master switch + per-transport status. |
| `test <which>`      | `which ∈ {all, socket, webhook}`                     | Send a test event and report.               |
| `socket <verb>`     | `verb ∈ {enable, disable, status, test}`             | Manage socket transport.                    |
| `webhook <verb>`    | `verb ∈ {enable, disable, configure, status, test}`  | Manage webhook transport.                   |
| `emit <event-name>` | `[positional args matching the event's Data fields]` | Emit an event manually.                     |

See [05-events.md](05-events.md) for the full event-name list and
parameter ordering.

---

## 9. `network`

```
kgsm network <subcommand>
```

| Subcommand                    | Args | Purpose                                  |
| ----------------------------- | ---- | ---------------------------------------- |
| `ip`                          |      | Print primary IP.                        |
| `dns <hostname>`              |      | Resolve a hostname.                      |
| `port-check <port>[/<proto>]` |      | Test if a single port is in use locally. |
| `ports`                       |      | List all listening sockets.              |

---

## 10. `system`

```
kgsm system <subcommand>
```

| Subcommand | Args       | Purpose                                           |
| ---------- | ---------- | ------------------------------------------------- |
| `info`     | `[--json]` | Aggregate hostname / OS / kernel / uptime / load. |
| `uptime`   |            | Print uptime.                                     |
| `load`     |            | Print load averages.                              |
| `memory`   |            | Print memory stats.                               |
| `disk`     |            | Print disk usage per filesystem.                  |
| `shutdown` |            | Halt the host (requires confirmation).            |
| `restart`  |            | Reboot the host (requires confirmation).          |

---

## 11. `watcher`

```
kgsm watcher <subcommand> <instance> [args]
```

| Subcommand | Args         | Purpose                                                            |
| ---------- | ------------ | ------------------------------------------------------------------ |
| `start`    | `[--detach]` | Launch the appropriate watcher strategy.                           |
| `stop`     |              | Kill any running watcher for the instance.                         |
| `status`   |              | Print which strategy applies and its current state.                |
| `test`     |              | Dry-run: verify a strategy can be selected and is wired correctly. |

Exit codes specific to watchers: `EC_WATCHER_TIMEOUT`,
`EC_WATCHER_NO_STRATEGY`, `EC_WATCHER_PATTERN_NOT_FOUND`,
`EC_WATCHER_PORT_NOT_ACTIVE`, `EC_WATCHER_LOG_FILE_MISSING`.

---

## 12. `directories` / `files` (low-level)

These exist for advanced users who need to recreate or remove single
artifacts of an instance. The full list:

```
kgsm directories <verb> <instance> [args]
    create | remove | link-instance | unlink-instance | ensure-created

kgsm files <verb> <instance> [args]
    create     [--manage|--systemd|--ufw|--symlink|--all]
    remove     [--manage|--systemd|--ufw|--symlink|--all]
    list
```

These are exposed for orchestration scripts and for the install /
uninstall flows themselves to call. Reimplementations MUST keep them
available because `kgsm files --instance <inst> --create --manage` is
the documented escape hatch users have for "regenerate my management
script after an edit broke it".

---

## 13. Output stability contract

Whatever a command prints when invoked with `--json` is part of the
public API and changes in a backward-incompatible way only at major
version bumps. Plain-text output is **not** part of the contract;
external tooling SHOULD use `--json` exclusively.

| Command                                            | Has `--json`? |
| -------------------------------------------------- | ------------- |
| `blueprints list`                                  | Yes           |
| `blueprints info`                                  | Yes           |
| `instances list`                                   | Yes           |
| `instances info`                                   | Yes           |
| `instances status` / `lifecycle status` / `status` | Yes           |
| `config list`                                      | Yes           |
| `system info`                                      | Yes           |
| `events status`                                    | Yes           |

Any command not in this table is plain-text only today; reimplementations
MAY add `--json` to additional commands as long as the existing
plain-text output is preserved.
