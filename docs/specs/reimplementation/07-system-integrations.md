# 07 — System Integrations

KGSM ships first-class integrations with several host-level systems.
All are optional and gated by config flags. Each integration follows
the same pattern: a template file in `templates/`, plus a
"create"/"remove" pair of operations triggered during instance
install/uninstall.

| Integration       | Config gate                  | Templates                     | Tools required             |
| ----------------- | ---------------------------- | ----------------------------- | -------------------------- |
| systemd           | `enable_systemd`             | `service.tp`, `socket.tp`     | `systemctl`                |
| UFW               | `enable_firewall_management` | `ufw.tp`                      | `ufw`                      |
| UPnP              | `enable_port_forwarding`     | (none — runtime)              | `upnpc` (miniupnpc)        |
| SteamCMD          | (per-blueprint)              | (none — runtime)              | `steamcmd`                 |
| Docker Compose    | (per-blueprint)              | (the blueprint *is* the file) | `docker`, `docker compose` |
| Command shortcuts | `enable_command_shortcuts`   | (none — symlink)              | —                          |

---

## 1. systemd

### 1.1 Service unit (`service.tp`)

```ini
[Unit]
Description=$instance_name Dedicated Server
Requires=$instance_name.socket

[Service]
Type=exec
PIDFile=$instance_pid_file
User=$INSTANCE_USER
WorkingDirectory=$instance_working_dir
ExecStart=$instance_management_file start --detached
ExecStop=$instance_management_file stop
NonBlocking=true

Restart=on-failure
RestartSec=5
StartLimitBurst=1

Sockets=$instance_name.socket
StandardInput=socket

[Install]
WantedBy=multi-user.target
```

The `$variable` placeholders are substituted at file-creation time.
`$INSTANCE_USER` is the user account under which the server should
run; the bash implementation defaults this to the calling user
(`$USER`). A reimplementation MAY accept it as an `--owner` flag on
`kgsm install`.

Filename: `<config_systemd_files_dir>/<instance_name>.service`
(default `/etc/systemd/system/`).

### 1.2 Socket unit (`socket.tp`)

```ini
[Unit]
Description=Socket for $instance_name
PartOf=$instance_name.service

[Socket]
ListenFIFO=$instance_socket_file
RemoveOnStop=true

[Install]
WantedBy=sockets.target
```

The `ListenFIFO=` directive makes systemd own the FIFO at
`$instance_socket_file`. Because the service unit declares
`StandardInput=socket`, systemd connects the FIFO to the server's
stdin. **This is how console input is delivered to the running server
under systemd.**

Filename: `<config_systemd_files_dir>/<instance_name>.socket`.

### 1.3 Operations

- **Create** (during install, if `enable_systemd=true`):
  1. Substitute the templates and write both unit files.
  2. `systemctl daemon-reload`.
  3. `systemctl enable <instance>.socket <instance>.service`.
  4. EMIT `instance-systemd-enabled`.
- **Remove** (during uninstall):
  1. `systemctl stop <instance>.service` (best-effort).
  2. `systemctl disable <instance>.socket <instance>.service`.
  3. Remove both unit files.
  4. `systemctl daemon-reload`.
  5. EMIT `instance-systemd-disabled`.

### 1.4 Per-user vs system-wide

The bash implementation writes to `/etc/systemd/system/` (system-wide,
requires root). A reimplementation MAY add a per-user mode using
`~/.config/systemd/user/` and `systemctl --user`. If so, the choice
MUST be configurable, MUST be reflected in the per-instance config so
later operations target the right scope, and MUST NOT be the silent
default (running as root has different security implications).

---

## 2. UFW (Uncomplicated Firewall)

### 2.1 Application profile (`ufw.tp`)

```ini
[$instance_name]
title=$instance_name
description=$instance_name
ports=$instance_ports
```

Filename: `<config_firewall_rules_dir>/<instance_name>`
(default `/etc/ufw/applications.d/`).

`$instance_ports` is the UFW format string from
[02-data-model.md §2.5](02-data-model.md), which is exactly what
UFW's `applications.d` syntax expects.

### 2.2 Operations

- **Create**:
  1. Write the profile file.
  2. `ufw app update <instance_name>`.
  3. `ufw allow <instance_name>`.
  4. EMIT `instance-ufw-enabled`.
- **Remove**:
  1. `ufw delete allow <instance_name>` (best-effort).
  2. Remove the profile file.
  3. EMIT `instance-ufw-disabled`.

The implementation MUST tolerate UFW being inactive — `ufw allow` will
queue the rule for when UFW is enabled.

---

## 3. UPnP (Universal Plug and Play)

UPnP is **runtime** integration — there are no on-disk files except
the state file `instance_port_forwarding_state_file` which serves as a
boolean "currently enabled" marker.

### 3.1 Operations (in module 09 of the management script)

- `_enable_upnp`:
  1. Build args from `instance_upnp_ports` (a flat array of
     `port proto port proto …`).
  2. `upnpc -e "<instance_name>" -r <port> <proto> [<port> <proto> ...]`.
  3. `touch <instance_port_forwarding_state_file>`.
- `_disable_upnp`:
  1. Skip if the state file is absent.
  2. `upnpc -f <port> <proto> ...`.
  3. Remove the state file.

The state file is necessary because `upnpc` is stateless from KGSM's
perspective — without it we cannot know whether to call `-f` on
shutdown.

### 3.2 Port array generation

`instance_upnp_ports` is computed at instance-creation time by parsing
`instance_ports` (UFW format) into a flat array of `port protocol`
pairs (algorithm in [02-data-model.md §4.2](02-data-model.md)).

A reimplementation MAY use a real UPnP library (e.g. miniupnpc as a
linked library, or any platform-native equivalent) instead of shelling
out to `upnpc`, provided the same enable/disable lifecycle is observed.

---

## 4. SteamCMD

SteamCMD is the default download mechanism for any blueprint with a
non-zero `steam_app_id`. It is invoked from the management script's
`_download` and `_get_latest_version` functions
([03-management-script-and-overrides.md §5.3, §5.4](03-management-script-and-overrides.md)).

### 4.1 Anonymous vs account login

```
if instance_is_steam_account_required == "true":
    login_args = "$STEAM_USERNAME $STEAM_PASSWORD"
    (both must be non-empty; otherwise abort with EC_ERROR)
else:
    login_args = "anonymous"
```

`STEAM_USERNAME` and `STEAM_PASSWORD` come from the `[steam]` section
of the global config (or environment variables of the same name in a
reimplementation that supports env-var override).

### 4.2 Download

```
steamcmd \
  +@sSteamCmdForcePlatformType <instance_platform>   # default: linux
  +force_install_dir <dest>                           # default: instance_temp_dir
  +login <login_args> \
  +app_update <app_id> <instance_steamcmd_arguments> validate \
  +quit
```

`<instance_steamcmd_arguments>` is the per-blueprint extra-args field
(e.g. `+beta experimental`) — passed through unmodified.

### 4.3 Version detection

```
steamcmd \
  +login <login_args> \
  +app_info_update 1 \
  +app_info_print <app_id> \
  +quit \
  | tr '\n' ' ' \
  | grep -Po '"branches"\s*{\s*"public"\s*{\s*"buildid"\s*"\K(\d*)'
```

The buildid string (e.g. `"15921892"`) is the version. Reimplementations
that need a more reliable parse SHOULD wrap a real KeyValues parser
around the SteamCMD output; the regex is fragile but matches what the
default bash override does today.

---

## 5. Docker Compose

Container blueprints *are* compose files. The management script for a
container instance (modules under `manage.container.d/`) shells out to
`docker compose` for every operation:

| Operation | Command                                               |
| --------- | ----------------------------------------------------- |
| Start     | `docker compose -f <compose_file> up -d`              |
| Stop      | `docker compose -f <compose_file> stop`               |
| Restart   | `docker compose -f <compose_file> restart`            |
| Status    | `docker compose -f <compose_file> ps`                 |
| Logs      | `docker compose -f <compose_file> logs [-f] --tail=N` |
| Kill      | `docker compose -f <compose_file> kill`               |

The compose file is **bind-mounted** into KGSM-managed directories
(`instance_install_dir`, `instance_backups_dir`, `instance_saves_dir`,
`instance_logs_dir`) using `${instance_*}` interpolation that Docker
Compose itself resolves. KGSM exports those values into the
environment before invoking compose.

`container_name: ${instance_name}` is the convention; this lets KGSM
target a specific container with `docker exec` when sending console
input.

---

## 6. Command shortcuts

When `enable_command_shortcuts=true`, instance creation places a
symlink at `<config_command_shortcuts_directory>/<instance_name>`
(default `/usr/local/bin/<instance>`) pointing at the management
script. A user can then run e.g. `myserver start` from anywhere on
their PATH.

Operations:

- **Create**: `ln -s <management_file> <shortcut_path>`. EMIT
  `instance-symlink-created`.
- **Remove**: `unlink <shortcut_path>`. EMIT `instance-symlink-removed`.

The shortcut directory MUST be writable by the user invoking
`kgsm install`. The bash implementation does not check this
ahead-of-time — failure surfaces as `EC_FAILED_LN`. A reimplementation
SHOULD validate up front and warn if the directory is not on `PATH`.

---

## 7. Network and host system commands

These are exposed by `kgsm network` and `kgsm system` for diagnostic
convenience. They do not interact with instances.

### 7.1 `kgsm network`

| Subcommand                    | Purpose                                         |
| ----------------------------- | ----------------------------------------------- |
| `ip`                          | Print the host's primary IP.                    |
| `dns <hostname>`              | Resolve a hostname.                             |
| `port-check <port>[/<proto>]` | Test whether the port is in use locally.        |
| `ports`                       | List all listening sockets (delegates to `ss`). |

### 7.2 `kgsm system`

| Subcommand | Purpose                                           |
| ---------- | ------------------------------------------------- |
| `info`     | Aggregate hostname / OS / kernel / uptime / load. |
| `uptime`   | Print uptime.                                     |
| `load`     | Print load averages.                              |
| `memory`   | Print free/used memory.                           |
| `disk`     | Print disk usage.                                 |
| `shutdown` | `shutdown -h now` (with a confirmation prompt).   |
| `restart`  | `shutdown -r now` (with a confirmation prompt).   |

These commands are deliberately thin wrappers; the implementation MAY
delegate to platform-native APIs rather than parsing `uptime` or `df`
output. The output shape (text vs JSON when `--json` is passed) MUST
remain stable.

---

## 8. Cross-platform note

KGSM is **Linux-only** today. Several integrations have no equivalent
on macOS or Windows (systemd, UFW, `upnpc`'s pair with `iptables`).

A future port to another OS SHOULD:

- Make every integration a pluggable backend (already the design
  shape, since each is gated independently).
- Skip integrations gracefully when the required tool is absent rather
  than failing instance creation. The bash implementation aborts on
  missing dependencies that are explicitly enabled — keep this strict
  behaviour, but ensure the error message names the missing tool.
