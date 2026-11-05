# 03 — Management Script and Overrides

Each instance carries a self-contained **management script**
(`<instance>.manage.sh`) inside its working directory. This script is
the only thing systemd invokes, and it is the only thing a power user
needs to run when the parent KGSM tool is unavailable.

This document defines:

1. How the management script is **assembled** at instance creation.
2. The **module list** and what each module owns.
3. The **override system** — directory layout, search order, and the
   exact contract every overridable function must honour.

---

## 1. Two runtimes, one shape

KGSM supports two server runtimes:

- **Native** — the server is a binary (or shell launcher) running on
  the host. Modules live in `<KGSM_TEMPLATES_DIR>/manage.native.d/`.
- **Container** — the server runs in a Docker container managed via
  Docker Compose. Modules live in `<KGSM_TEMPLATES_DIR>/manage.container.d/`.

Both runtimes use **the same set of 14 module slots and the same
function names** at every layer. The implementation differs (native
spawns a process; container calls `docker compose`) but the surface
contract is identical, so callers do not need to know which runtime
they are talking to.

---

## 2. Module layout

The 14 slots, in order:

| #   | File              | Role                                                                                                                                        | Overridable? |
| --- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| 00  | `00-header.sh`    | Shebang + file banner                                                                                                                       | No           |
| 01  | `01-config.sh`    | Source the per-instance INI; export `instance_*` vars; set up logging colours                                                               | No           |
| 02  | `02-help.sh`      | `show_usage*` functions                                                                                                                     | No           |
| 03  | `03-lifecycle.sh` | Process lifecycle: `_is_active`, `_start`, `_start_background`, `_attach_to_instance`, `_stop_server`, `_timed_stop`, `_kill_all_processes` | **Yes**      |
| 04  | `04-io.sh`        | Console pipe: `_send_input`, `_send_save_command`, plus `__sanitize_input_command`                                                          | **Yes**      |
| 05  | `05-version.sh`   | Version: `_get_installed_version`, `_get_latest_version`, `_compare_versions`, `_save_version`                                              | **Yes**      |
| 06  | `06-download.sh`  | `_download`                                                                                                                                 | **Yes**      |
| 07  | `07-deploy.sh`    | `_deploy`                                                                                                                                   | **Yes**      |
| 08  | `08-backup.sh`    | `_create_backup`, `_list_backups`, `_restore_backup`                                                                                        | **Yes**      |
| 09  | `09-network.sh`   | `_enable_upnp`, `_disable_upnp`, `_is_upnp_enabled`                                                                                         | **Yes**      |
| 10  | `10-logging.sh`   | `_print_logs`, `_rotate_log_file`                                                                                                           | **Yes**      |
| 11  | `11-status.sh`    | `_get_status` (text + JSON modes)                                                                                                           | **Yes**      |
| 12  | `12-commands.sh`  | `_cmd_*` argument parsers (one per CLI verb)                                                                                                | No           |
| 13  | `13-dispatch.sh`  | `case` over `$1` that routes to `_cmd_*`                                                                                                    | No           |

### 2.1 What "overridable" means

The four fixed modules (00, 01, 02, 12, 13) define the script's overall
shape and the CLI surface. They are never replaced — overriding them
would let a per-game override redefine the management script's CLI,
which would be a maintenance nightmare.

The nine middle modules contain functions whose semantics are
inherently game-specific (especially `_download`, `_get_latest_version`,
`_deploy`). These MAY be replaced wholesale by an override (see §3).

The bash implementation requires that an override module be a **full
copy** of the default module — every function the default defines must
be present in the override, even if the override only meaningfully
changes one of them. A reimplementation is free to relax this (it could
allow per-function overrides) but the current behaviour is the
documented contract that override authors rely on.

---

## 3. The override system

### 3.1 Directory layout

```
<override-root>/
└── <blueprint-logical-name>/
    ├── 03-lifecycle.sh
    ├── 04-io.sh
    ├── 05-version.sh
    ├── 06-download.sh
    ├── 07-deploy.sh
    ├── 08-backup.sh
    ├── 09-network.sh
    ├── 10-logging.sh
    └── 11-status.sh   (any subset; missing files use the default)
```

The directory name is the **logical blueprint name** as defined in
[02-data-model.md §2.2](02-data-model.md), NOT the blueprint's
filename. Blueprints `terraria-vanilla.bp` and `terraria-modded.bp`
both with `name=terraria` share `overrides/terraria/`.

For container blueprints, the directory name is the first service key
in the compose file (also defined in §2.2).

### 3.2 Search order

When assembling module N for an instance whose blueprint has logical
name `<bp>`, search for the override module file in this order and
use the first match:

```
1. <KGSM_USER_OVERRIDES_DIR>/<bp>/<N>-<role>.sh   (per-user override)
2. <KGSM_SYSTEM_OVERRIDES_DIR>/<bp>/<N>-<role>.sh (bundled override)
3. <KGSM_TEMPLATES_DIR>/manage.<runtime>.d/<N>-<role>.sh (default)
```

If none of the user/system override files exist for slot N, the default
template is used. Each slot is resolved independently.

### 3.3 Why file-based, not class-based

KGSM is bash. The implementation language for a port (Stash, in this
project) does not have a class hierarchy either. The chosen mechanism
— per-game directories of replacement modules discovered by name at
runtime — fits both languages, is trivial to inspect with `ls`, and
lets users author overrides in any text editor without learning a
plugin API. **Reimplementations MUST keep this discovery model.**
Specifically: do NOT replace it with a class-based plugin system that
loads game-specific subclasses; do NOT require overrides to register
themselves in a manifest. The directory IS the manifest.

---

## 4. Assembly process

Triggered by `kgsm files --instance <name> --create --manage`, and
implicitly by every `install` and every blueprint-driven recreation.

Inputs: a fully-materialised per-instance config file.

Algorithm:

```
output = ""
for slot in [00, 01, 02, ..., 13]:
    role = name of slot's role (from §2 table)
    src  = resolve(slot, role, runtime, blueprint_logical_name)
            # search order from §3.2
    output += read(src)
    output += "\n"
write(output, "<working_dir>/<instance>.manage.sh", mode=0755)
```

The output is a single executable file. There is no template
substitution at assembly time on the bash side because the default
modules read everything they need from the per-instance config at
runtime (module 01 sources the config). A reimplementation MAY choose
to substitute statically (folding `instance_*` values into the script
text) provided the result remains self-contained.

### 4.1 Self-containment requirement

The assembled script:

- MUST run when invoked directly (`/path/to/<instance>.manage.sh start`)
  with no environment from the parent KGSM tool — only standard system
  PATH and the variables systemd injects.
- MUST source its own per-instance config file at startup (module 01).
- MUST NOT depend on `KGSM_ROOT` being set at runtime — it is
  intentionally portable to a system where KGSM has been removed.
- MUST locate the config file using `dirname "$(readlink -f "$0")"` —
  this allows the instance directory to be moved.

Module 01's prologue performs all of this. Reimplementations MUST
preserve self-containment.

### 4.2 The instance is not regenerated automatically

Once written, the management script is not rewritten by KGSM unless the
user explicitly runs `kgsm files --instance <name> --create --manage`.
A KGSM upgrade does not touch existing instances. Rationale: an instance
is a deployed artifact; users may have hand-edited its management
script (the file header even tells them so). Auto-overwriting on every
KGSM action would surprise users. This is intentional behaviour.

---

## 5. Function contracts

The following are the contracts every overridable function MUST honour.
"Returns N" means "exits the function with status N, which propagates
up to the management script's exit code through the dispatcher".

All of these are part of the override API: they are called either by
the dispatcher in module 13 or by sibling functions in other modules,
so authors of an override can rely on the contract.

### 5.1 Module 03 — lifecycle

| Function              | Args                              | stdout                 | Returns                   | Side effects                                                                                                                                                                                                                                                                                                                                                                                                               |
| --------------------- | --------------------------------- | ---------------------- | ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_is_active`          | —                                 | "Active" \| "Inactive" | 0 if running, 1 otherwise | Stale PID files MAY be removed.                                                                                                                                                                                                                                                                                                                                                                                            |
| `_start`              | —                                 | progress               | 0 on success              | Calls `_start_background` then `_attach_to_instance`.                                                                                                                                                                                                                                                                                                                                                                      |
| `_start_background`   | —                                 | progress               | 0 on success              | Rotates current log; creates input FIFO at `instance_socket_file`; spawns the server with stdin from FIFO and stdout/stderr to `instance_log_file`; writes the PID to `instance_pid_file`; if `instance_enable_port_forwarding=true`, calls `_enable_upnp`; if `instance_auto_update=true`, calls `_update`; expands variables inside `instance_executable_arguments` (rejecting `$(...)` and backticks before expansion). |
| `_attach_to_instance` | —                                 | interactive            | 0 on detach/stop          | Tails the log; presents a prompt; sends user input through `_send_input`. The literal string `.detach` exits the loop without stopping the server.                                                                                                                                                                                                                                                                         |
| `_stop_server`        | `[--no-save] [--no-graceful]`     | progress               | 0                         | If save command is set and not `--no-save`, calls `_send_save_command`. If stop command is set and not `--no-graceful`, writes it into the FIFO. Then `_kill_all_processes`. Removes PID + FIFO. If port forwarding was active, calls `_disable_upnp`.                                                                                                                                                                     |
| `_timed_stop`         | `<no_save_int> <no_graceful_int>` | progress               | 0                         | Wraps `_stop_server` in `timeout instance_stop_command_timeout_seconds`; on timeout, force-kills.                                                                                                                                                                                                                                                                                                                          |
| `_kill_all_processes` | —                                 | progress               | 0                         | Reads PID file, finds direct children with `pgrep -P`, sends SIGTERM to children then to main PID.                                                                                                                                                                                                                                                                                                                         |

### 5.2 Module 04 — I/O

| Function             | Args               | Returns        | Side effects                                                                            |
| -------------------- | ------------------ | -------------- | --------------------------------------------------------------------------------------- |
| `_send_input`        | `<command-string>` | 0 if delivered | Sanitises (rejects shell metacharacters; max length 1000), writes to FIFO.              |
| `_send_save_command` | —                  | 0 if delivered | Writes `instance_save_command` to FIFO; sleeps `instance_save_command_timeout_seconds`. |

### 5.3 Module 05 — version

| Function                 | Args        | stdout                               | Returns                                                |
| ------------------------ | ----------- | ------------------------------------ | ------------------------------------------------------ |
| `_get_installed_version` | —           | version string ("unknown" if absent) | 0                                                      |
| `_get_latest_version`    | —           | version string                       | 0 on success, non-zero on failure                      |
| `_compare_versions`      | —           | latest version (only if updateable)  | 0 if update available; non-zero if up-to-date or error |
| `_save_version`          | `<version>` | progress                             | 0 on success                                           | (Side effect: write to `instance_version_file`.) |

The default `_get_latest_version` queries SteamCMD's
`+app_info_print <id>` and extracts `branches.public.buildid`. The
default `_get_installed_version` reads `instance_version_file`. Both
are routinely overridden — Factorio queries
`https://factorio.com/api/latest-releases`, Minecraft queries
Mojang's manifest, etc.

### 5.4 Module 06 — download

| Function    | Args                                                                      | Returns      | Side effects                              |
| ----------- | ------------------------------------------------------------------------- | ------------ | ----------------------------------------- |
| `_download` | `[<version>] [<dest=instance_temp_dir>] [<app_id=instance_steam_app_id>]` | 0 on success | Populates `<dest>` with downloaded files. |

The default uses SteamCMD with `+force_install_dir <dest>`, anonymous
or account login per `instance_is_steam_account_required`,
`+app_update <app_id> <steamcmd_arguments> validate`. Overrides for
non-Steam games (Factorio, Minecraft, Veloren) replace this with
`wget` + extract.

### 5.5 Module 07 — deploy

| Function  | Args | Returns      | Side effects                                                                                              |
| --------- | ---- | ------------ | --------------------------------------------------------------------------------------------------------- |
| `_deploy` | —    | 0 on success | Moves contents of `instance_temp_dir` into `instance_install_dir`; clears `instance_temp_dir` afterwards. |

### 5.6 Module 08 — backup

| Function          | Args         | stdout                    | Returns      | Side effects                                                                                                                                                                                                     |
| ----------------- | ------------ | ------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_create_backup`  | —            | progress                  | 0 / non-zero | Refuses if instance is running. Creates a timestamped folder (or `.tar.gz` if `instance_compress_backups=true`) in `instance_backups_dir` named `<instance>-<version>-<ISO-timestamp>.backup[.tar.gz]`.          |
| `_list_backups`   | —            | space-separated filenames | 0            | None.                                                                                                                                                                                                            |
| `_restore_backup` | `<filename>` | progress                  | 0 / non-zero | First creates a safety backup of the current install. Then clears `instance_install_dir` and unpacks the chosen backup into it. Updates `instance_version_file` from the version segment of the backup filename. |

### 5.7 Module 09 — network (UPnP)

| Function           | Args | Returns                | Side effects                                                                                                                              |
| ------------------ | ---- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `_enable_upnp`     | —    | 0 on success           | Calls `upnpc -e <name> -r <port> <proto> [<port> <proto> ...]` over `instance_upnp_ports`; touches `instance_port_forwarding_state_file`. |
| `_disable_upnp`    | —    | 0 on success           | Calls `upnpc -f <port> <proto> ...`; removes the state file.                                                                              |
| `_is_upnp_enabled` | —    | 0 if state file exists | None.                                                                                                                                     |

### 5.8 Module 10 — logging

| Function           | Args                                 | Returns | Side effects                                                                             |
| ------------------ | ------------------------------------ | ------- | ---------------------------------------------------------------------------------------- |
| `_rotate_log_file` | `<log_file>`                         | 0       | If file is non-empty, moves it to `<instance_logs_dir>/<instance>.<ISO-timestamp>.log`.  |
| `_print_logs`      | `[<follow=false>] [<line_count=10>]` | 0       | Execs `tail` (with `--pid=$$` so it dies with its caller). When `follow=true` adds `-F`. |

### 5.9 Module 11 — status

| Function      | Args                            | stdout       | Returns |
| ------------- | ------------------------------- | ------------ | ------- |
| `_get_status` | `[<json_format>] [<fast_mode>]` | text or JSON | 0       |

The JSON shape is defined in [08-cli-reference.md](08-cli-reference.md)
under `kgsm status --json`.

---

## 6. Variables available to override functions

When an override function runs, the following are guaranteed to be
defined and bound in the function's environment:

- Every key in the per-instance config file (§3.3 of
  [02-data-model.md](02-data-model.md)), as `instance_<key>`.
- `STEAM_USERNAME`, `STEAM_PASSWORD` from the global config (or the
  process environment, if the implementation prefers env-var overrides).
- The selected subset of global config keys that the default modules
  reference (`config_wget_timeout_seconds`, etc. — see the list at the
  bottom of `templates/overrides.tp`).
- `self` — basename of the management script (used for self-referential
  log lines).
- The exit-code constants `EC_SUCCESS`, `EC_ERROR`, `EC_MISSING_ARG`,
  `EC_INVALID_ARG` (module 01 redeclares these locally so the script
  is self-contained — see [01-system-overview.md §5](01-system-overview.md)).
- The four logging helpers `__print_success`, `__print_info`,
  `__print_warning`, `__print_error` (also defined locally in module 01).

A reimplementation that uses imports/modules instead of `source` MUST
expose the same identifier names at the same scope so existing override
authors can write code with no surprises.

---

## 7. Container variant differences

The container module set is the same shape but the implementations
delegate to Docker:

- `_is_active` → `docker compose -f <compose_file> ps -q <service>`
  returns non-empty iff active.
- `_start_background` → `docker compose -f <compose_file> up -d` (after
  optional `_update`).
- `_stop_server` → `docker compose -f <compose_file> stop`.
- `_kill_all_processes` → `docker compose -f <compose_file> kill`.
- `_send_input` → `docker exec -i <container> sh -c 'echo "<cmd>" >> /shared/console'`
  (or whatever input mechanism the container exposes — game-dependent;
  many container blueprints simply do not implement input).
- `_print_logs` → `docker compose -f <compose_file> logs [-f] --tail=N`.
- `_create_backup` / `_restore_backup` → operate on the host-side
  `instance_install_dir` (which is bind-mounted into the container),
  with the container stopped.
- `_download` / `_deploy` are typically **no-ops** for container
  servers: the image already contains the binaries and the data is
  pulled by the container itself on first launch.
- `_enable_upnp` / `_disable_upnp` are unchanged.

The exact contracts (return codes, argument order) are identical to
the native versions so callers (modules 12, 13, and the parent KGSM
tool) do not need to special-case runtime.
