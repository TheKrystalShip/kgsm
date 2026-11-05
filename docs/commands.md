# Commands

`kgsm <group> <command> [arguments] [options]`. `kgsm --help` and `kgsm <group> --help` list everything; a
command's own `--help` lists its arguments and options.

## Groups

| Group | Commands |
|---|---|
| `instance` | `list`, `show`, `status`, `logs`, `config` (`list`, `get`, `set`), `note` (`set`, `clear`), `console` (`send`, `save`, `announce`, `kick`, `ban`, `unban`), `install`, `uninstall`, `start`, `stop`, `restart`, `move`, `update`, `check-update`, `enable`, `disable`, `repair`, `unlock` |
| `blueprint` | `list`, `show`, `find`, `validate`, `requirements`, `create`, `update`, `delete` |
| `library` | `list`, `add`, `remove`, `rename` |
| `backup` | `list`, `create`, `restore`, `delete`, `prune`, `pin`, `unpin` |
| `port` | `list`, `conflicts`, `listening` |
| `transfer` | `export`, `import` |
| `event` | `emit`, `journal` (`status`, `prune`, `verify`) |
| `engine` | `paths`, `version`, `placeholders`, `config` (`list`, `get`, `set`) |

An `<instance>` is its id, such as `factorio-a1`. Ids are unique across the host.

## Global options

| Option | Meaning |
|---|---|
| `--json`, `--format json` | The result as JSON, through the engine's registered types. Errors go to stderr as a JSON error report with a `code` field and stdout stays empty. |
| `--yes` | Confirm a destructive command. Without a terminal and without `--yes` a destructive command refuses with exit 2. |
| `--actor <provider:name>` | Who acts. Defaults to the local user. |
| `--origin <origin>` | The surface the action came through: `ui`, `assistant`, `discord`, `api`, `notification`, `system`, `reactor`. Defaults to the local user at a terminal. |

Every mutating command journals its events with the actor and origin it was given.

## Lifecycle

- **Native instances** start, stop and restart through the watchdog when it is ready. When it is absent or
  not ready the engine starts the instance through its management script, unsupervised, and the result says
  so. Memory admission is the watchdog's alone: a start it refuses exits 51.
- **Container instances** start through their management script whether or not the watchdog runs.
- **Locks.** A write on one instance takes that instance's lock, so different servers install, back up and
  update at once; a write on shared state (the registry, libraries, blueprints, settings) takes the global
  lock. A held lock fails fast with a busy error.
- **Install rolls back completely** on failure: the registry entry, the working directory and the backups
  directory it created are removed and `server.install.failed` and `server.install.finished` are emitted.
- **Uninstall** stops what runs, whoever runs it, before any file is deleted.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | failure; the error report's `code` field names it |
| 2 | usage error, including a destructive command refused for want of `--yes` |
| 25 | not found |
| 51 | insufficient memory (the watchdog refused a start) |
| 56 | insufficient disk |
| 57 | instance running |
| 59-64 | transfer: locked, version mismatch, requirement missing, port conflict, integrity, import not found |

`blueprint validate`, `blueprint requirements` and the transfer import check print their JSON result even
when they exit non-zero.

## The account gate

Every command but help, version and paths refuses when the event journal directory belongs to another
account, and names the `sudo -u <owner> kgsm ...` line to run instead. On a package node the owner is the
`kgsm` account.
