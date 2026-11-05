# KGSM Reimplementation Specification

This directory contains a **language-agnostic specification** of KGSM
(Krystal Game Server Manager). Its purpose is to enable a faithful
reimplementation of KGSM in another scripting language without having to
read the existing bash source code.

The current implementation is in bash. These documents describe what it
*does*, not how the bash version achieves it. Bash-specific workarounds
are explicitly called out and contrasted with what a higher-level language
should do instead. See [09-reimplementation-notes.md](09-reimplementation-notes.md)
for that catalog.

> **Source of truth.** Where these docs disagree with the bash source, the
> bash source is authoritative for behaviour but these docs reflect the
> *intended* design. If a discrepancy is encountered, treat the bash
> behaviour as the spec and update these docs.

## What KGSM is

A CLI tool that lets a single Linux host install, configure, run, update,
back up, and uninstall an arbitrary number of game-server *instances*
created from reusable *blueprints*. Two runtime kinds are supported:

- **Native** — the server runs as a normal Linux process.
- **Container** — the server runs as a Docker Compose service.

Game-specific behaviour (how to fetch the latest version, how to download
files, how to deploy them) lives in **overrides**, which are plug-in code
modules discovered at runtime by the blueprint's logical name.

KGSM also provides:

- A guided interactive TUI as an alternative to the CLI.
- An **event system** that broadcasts lifecycle events over Unix sockets
  and HTTP webhooks.
- Optional integrations with **systemd**, **UFW**, **UPnP**, and
  **SteamCMD**.
- A **readiness watcher** that detects when a freshly-started server is
  ready to accept players.
- A **configuration management system** with versioned schemas, automatic
  migrations, and rotating backups.

## Mental model in one paragraph

A *blueprint* is a static description of a game server. An *instance* is
a deployed copy of a blueprint. Each instance owns a directory tree
(install, saves, backups, logs, temp), a config file that captures every
resolved variable about it, and a *management script* assembled at
creation time from a stack of numbered modules — some of which can be
replaced per-game by *overrides*. The management script is fully
self-contained; it can be run directly without the parent KGSM tool, and
that is how systemd invokes it. The parent tool exists to *orchestrate*
the high-level flows (install, uninstall, lifecycle commands, listing,
configuration), to dispatch *events* when those flows succeed, and to
manage system-level integrations.

## Documents

Read in this order:

1. [01-system-overview.md](01-system-overview.md) — Top-level architecture,
   module organization, command dispatch, command/handler split,
   error codes, file layout (XDG paths).
2. [02-data-model.md](02-data-model.md) — All persistent data: global
   config, blueprints (native + container), per-instance config,
   directory layout. Includes complete field schemas.
3. [03-management-script-and-overrides.md](03-management-script-and-overrides.md) —
   The per-instance assembled management script: module structure,
   assembly process, override resolution, function contracts.
4. [04-lifecycle-flows.md](04-lifecycle-flows.md) — Step-by-step
   end-to-end flows: install, start/stop/restart, update, backup/restore,
   uninstall.
5. [05-events.md](05-events.md) — Event types, JSON payload shape,
   socket transport, webhook transport, HMAC signing.
6. [06-watchers.md](06-watchers.md) — Readiness detection: log-pattern
   strategy, port-monitoring strategy, selection rules.
7. [07-system-integrations.md](07-system-integrations.md) — systemd,
   UFW, UPnP, SteamCMD, Docker Compose.
8. [08-cli-reference.md](08-cli-reference.md) — Complete CLI surface
   with every command, subcommand, flag, and exit-code contract.
9. [09-reimplementation-notes.md](09-reimplementation-notes.md) —
   Bash-specific patterns to discard, intentional patterns to preserve,
   and design decisions worth re-examining.

## Glossary

| Term                  | Meaning                                                                                                                                                                                                                              |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Blueprint**         | A static template describing a game server (native `.bp` file or container `.docker-compose.yml`).                                                                                                                                   |
| **Instance**          | A deployed game server created from a blueprint. Has its own directory, config, and management script.                                                                                                                               |
| **Blueprint name**    | The logical identity of a game (e.g. `factorio`, `terraria`). For native blueprints it is the `name=` field; for container blueprints it is the first service name in the compose file. Determines which override directory applies. |
| **Instance ID**       | The unique name of one deployed instance (e.g. `factorio-01`, `survival-server`). Auto-generated as `<blueprint>-<NN>` if not supplied.                                                                                              |
| **Override**          | A directory of game-specific module files that replace one or more default management-script modules.                                                                                                                                |
| **Management script** | The per-instance, self-contained executable assembled from numbered modules, capable of running the server without the parent KGSM tool.                                                                                             |
| **Lifecycle manager** | Either `standalone` (the management script manages the process directly) or `systemd` (a systemd unit invokes the management script).                                                                                                |
| **Runtime**           | Either `native` or `container`. Determines which set of management-script modules is used.                                                                                                                                           |
| **Working directory** | The directory under the user's chosen install path that holds the instance's files.                                                                                                                                                  |
| **Symlink layer**     | A directory under `KGSM_INSTANCES_DIR` containing one symlink per instance, pointing at its working directory. Provides a single discovery point regardless of where users install instances.                                        |
| **Watcher**           | A background process that detects when a freshly-started server is ready to accept players.                                                                                                                                          |
| **Event**             | A named lifecycle notification dispatched as JSON over Unix sockets and/or HTTP webhooks.                                                                                                                                            |

## Conventions used in these docs

- Variables exposed to user code (templates, overrides) use the prefixes
  `instance_*` (per-instance values) and `config_*` (global config values).
- "MUST", "SHOULD", "MAY" follow RFC 2119 conventions.
- Directory paths use `/` separators throughout — KGSM is Linux-only.
