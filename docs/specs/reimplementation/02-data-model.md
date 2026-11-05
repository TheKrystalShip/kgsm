# 02 — Data Model

This document describes every persistent piece of data KGSM reads or
writes: the global config file, blueprints, instances, and the
on-disk layout for each.

---

## 1. Global configuration file

### 1.1 Location and format

|           |                                                 |
| --------- | ----------------------------------------------- |
| User file | `${XDG_CONFIG_HOME:-~/.config}/kgsm/config.ini` |
| Default   | `<KGSM_ROOT>/config.default.ini`                |
| Format    | Sectioned INI, with `#` comments.               |

The schema-version line `config_schema_version=N` MUST appear at the
top, **before** the first section header.

### 1.2 Parsing rules

- Lines starting with `#` or whitespace + `#` are comments.
- Section headers are `[name]`. They group keys for human readability;
  parsers MUST NOT treat the section name as part of the key.
- Each key is `key=value`. Whitespace around `=` is trimmed. Surrounding
  single or double quotes around the value are stripped.
- All keys are exposed to the rest of the system in a **flat, single
  namespace** with the prefix `config_`. Section names are *not* part of
  the exposed identifier — `[network] enable_firewall_management=true`
  becomes `config_enable_firewall_management=true`.
- Booleans are the literal strings `true` or `false`.
- All values are strings; consumers coerce to int/bool as needed.

### 1.3 Sections and keys (current schema, version 1)

#### `[system]`

| Key                    | Type | Default | Meaning                                          |
| ---------------------- | ---- | ------- | ------------------------------------------------ |
| `wget_timeout_seconds` | int  | 60      | Idle timeout for any network operation.          |
| `enable_logging`       | bool | false   | Persist log lines to `<KGSM_LOGS_DIR>/kgsm.log`. |
| `log_max_size_kb`      | int  | 10240   | Rotate the log file when it exceeds this size.   |

#### `[steam]`

| Key              | Type   | Default | Meaning                                         |
| ---------------- | ------ | ------- | ----------------------------------------------- |
| `STEAM_USERNAME` | string | ""      | SteamCMD account name (empty = anonymous-only). |
| `STEAM_PASSWORD` | string | ""      | SteamCMD account password.                      |

> Reimplementations SHOULD allow overriding these via environment
> variables of the same name to keep credentials out of disk files.

#### `[services]`

| Key                 | Type | Default               | Meaning                                                |
| ------------------- | ---- | --------------------- | ------------------------------------------------------ |
| `enable_systemd`    | bool | false                 | Generate `.service`/`.socket` units for new instances. |
| `systemd_files_dir` | path | `/etc/systemd/system` | Where to install generated unit files.                 |

#### `[network]`

| Key                          | Type | Default                   | Meaning                                              |
| ---------------------------- | ---- | ------------------------- | ---------------------------------------------------- |
| `enable_firewall_management` | bool | false                     | Generate UFW application profiles for new instances. |
| `firewall_rules_dir`         | path | `/etc/ufw/applications.d` | Where to install UFW profiles.                       |
| `enable_port_forwarding`     | bool | false                     | Add UPnP rules on instance start, remove on stop.    |

#### `[events]`

| Key                         | Type   | Default     | Meaning                                                             |
| --------------------------- | ------ | ----------- | ------------------------------------------------------------------- |
| `enable_event_broadcasting` | bool   | false       | Master switch. When false, no events are emitted.                   |
| `enable_socket_events`      | bool   | false       | Enable Unix-socket transport.                                       |
| `event_socket_filenames`    | csv    | `kgsm.sock` | Comma-separated filenames; sockets created under `KGSM_ROOT`.       |
| `enable_webhook_events`     | bool   | false       | Enable HTTP webhook transport.                                      |
| `webhook_urls`              | csv    | ""          | Comma-separated endpoint URLs.                                      |
| `webhook_timeout_seconds`   | int    | 10          | Per-request timeout. Range 1–300.                                   |
| `webhook_retry_count`       | int    | 2           | Retry attempts with exponential backoff. Range 0–5.                 |
| `webhook_secret`            | string | ""          | If set, requests carry an `X-KGSM-Signature: sha256=<hmac>` header. |

#### `[watchers]`

| Key                                    | Type | Default | Meaning                                   |
| -------------------------------------- | ---- | ------- | ----------------------------------------- |
| `enable_watcher`                       | bool | false   | Auto-launch a watcher on `kgsm start`.    |
| `watcher_global_timeout_seconds`       | int  | 600     | Max wait time for readiness.              |
| `watcher_ports_check_interval_seconds` | int  | 5       | Poll period for port-monitoring strategy. |

#### `[instance_defaults]`

These act as defaults for newly-created instances; each may be overridden
in the per-instance config.

| Key                                     | Type | Default | Meaning                                                      |
| --------------------------------------- | ---- | ------- | ------------------------------------------------------------ |
| `default_library`                       | name | ""      | The host's default library — a root registered with `kgsm libraries add`. |
| `instance_suffix_length`                | int  | 2       | Number of digits in auto-generated instance IDs. Range 1–10. |
| `enable_backup_compression`             | bool | false   | `tar` + gzip backups instead of plain copies.                |
| `instance_save_command_timeout_seconds` | int  | 5       | Wait period after sending the save command.                  |
| `instance_stop_command_timeout_seconds` | int  | 30      | Grace period before SIGKILL on stop.                         |
| `instance_auto_update_before_start`     | bool | false   | Run the update flow before each start.                       |

#### `[accessibility]`

| Key                           | Type | Default          | Meaning                                                                                          |
| ----------------------------- | ---- | ---------------- | ------------------------------------------------------------------------------------------------ |
| `enable_command_shortcuts`    | bool | false            | On instance creation, place a symlink in `command_shortcuts_directory` named after the instance. |
| `command_shortcuts_directory` | path | `/usr/local/bin` | Where to install the shortcut symlink.                                                           |

### 1.4 Schema version, migrations, backups

- A top-level `config_schema_version=N` declares the format version.
  The bundled default file declares the *current* version.
- On every "merge" operation (see §1.5), if the user file's version is
  lower than the default's, KGSM MUST run all numbered migration scripts
  in `<KGSM_ROOT>/migrations/config/` whose target version is greater
  than the user's current version, in ascending order.
- Migration scripts MUST be idempotent (re-running them on
  already-migrated data is a no-op).
- Each migration MUST create a `config.ini.pre-migration-vN.bak` snapshot
  before mutating the file.
- The "merge" operation MUST also create a numbered rotating backup
  (`config.ini.0` is the latest, `config.ini.9` is the oldest;
  `.0 → .1 → … → .9` rotation, oldest deleted).

### 1.5 Merge algorithm

Triggered automatically after a KGSM update, and manually via
`kgsm config merge`. Inputs: the user file and the default file.

1. Create a numbered backup of the user file.
2. If the user's `config_schema_version` is lower than the default's,
   run all pending migrations.
3. Parse both files into key→value maps.
4. Walk the **structure** of the default file line by line. For each
   line:
   - Section header / comment / blank → copy as-is to the merged file.
   - `key=value` → if the user file has this key, write the user's
     value; otherwise write the default's value.
5. Find any keys that appear in the user file but not the default file.
   Append them under a "DEPRECATED KEYS" comment block at the end of
   the merged file, each line commented out with a `DEPRECATED:` prefix.
6. Atomically replace the user file with the merged file.

The result: every user customisation is preserved, every new default
key is added, every removed key is preserved (as a comment) so the
user can still see what was there.

### 1.6 Rollback / diff / reset / validate

These are invoked from `kgsm config <verb>`:

- `rollback [N]` — Restore `config.ini.N` (default 0) over the current
  file, after first creating a safety backup of the current state.
- `diff [N]` — Print a colour-coded diff between the current file and
  `config.ini.N`.
- `reset` — Replace the user file with `config.default.ini`, after
  creating a timestamped `config.ini.<YYYYMMDD_HHMMSS>.bak` snapshot.
- `validate` — Walk the user file, ensure every required key is
  present, every value parses to its declared type, every numeric value
  is in its declared range. Returns `EC_INVALID_CONFIG_VALUE` /
  `EC_MISSING_CONFIG_KEY` on failure.

---

## 2. Blueprints

A blueprint is a static description of a game server. Two kinds exist
side-by-side, distinguished by file extension.

### 2.1 Storage

| Tree                | Native                               | Container                                               |
| ------------------- | ------------------------------------ | ------------------------------------------------------- |
| Bundled (read-only) | `<KGSM_ROOT>/blueprints/native/*.bp` | `<KGSM_ROOT>/blueprints/container/*.docker-compose.yml` |
| User (writable)     | `<KGSM_DATA>/blueprints/native/*.bp` | `<KGSM_DATA>/blueprints/container/*.docker-compose.yml` |

The user tree shadows the bundled tree (a user file with the same
filename takes precedence).

### 2.2 The blueprint *name*

Two distinct identifiers are involved:

- **Filename** (e.g. `terraria-modded.bp`) — chosen by the user, may
  be anything sensible.
- **Logical name** (e.g. `terraria`) — the value that determines which
  *override* directory (if any) applies.

Resolution of the logical name:

| Blueprint type                    | Where to read from                    |
| --------------------------------- | ------------------------------------- |
| Native (`.bp`)                    | The value of `name=` inside the file. |
| Container (`.docker-compose.yml`) | The first key under `services:`.      |

This means **multiple blueprint variants may share the same logical
name** and therefore the same override. `terraria-vanilla.bp`,
`terraria-modded.bp`, and `terraria-hardcore.bp` may all set
`name=terraria` and reuse `overrides/terraria/`. This is intentional;
preserve it.

### 2.3 Native blueprint schema (`.bp`)

INI-style `key=value`, no sections. Same parsing rules as the global
config (§1.2).

| Key                         | Required | Type   | Default | Meaning                                                                                            |
| --------------------------- | -------- | ------ | ------- | -------------------------------------------------------------------------------------------------- |
| `name`                      | yes      | string | —       | Logical name (lowercase, no spaces).                                                               |
| `executable_file`           | yes      | string | —       | Filename of the server binary.                                                                     |
| `level_name`                | yes      | string | —       | Default world / map / save name.                                                                   |
| `ports`                     | no       | string | ""      | Network ports in UFW format (see §2.5). Single-quoted in the file.                                 |
| `steam_app_id`              | no       | int    | 0       | Steam App ID. `0` means non-Steam.                                                                 |
| `steamcmd_arguments`        | no       | string | ""      | Extra arguments passed to `steamcmd` (e.g. `+beta experimental`).                                  |
| `is_steam_account_required` | no       | bool   | false   | If true, SteamCMD logs in with `STEAM_USERNAME`/`STEAM_PASSWORD`.                                  |
| `platform`                  | no       | enum   | `linux` | `linux` / `windows` / `macos` (passed to SteamCMD's `+@sSteamCmdForcePlatformType`).               |
| `executable_subdirectory`   | no       | path   | ""      | Relative path inside `install_dir` containing the executable.                                      |
| `executable_arguments`      | no       | string | ""      | Argument string for the server binary. May reference `$instance_*` variables; expanded at startup. |
| `stop_command`              | no       | string | ""      | Console command sent to the input socket to gracefully stop the server.                            |
| `save_command`              | no       | string | ""      | Console command sent to the input socket to save state.                                            |
| `startup_success_regex`     | no       | regex  | ""      | Pattern matched against new log lines by the readiness watcher.                                    |

#### `executable_arguments` variable substitution

When the management script launches the server, it expands `$instance_*`
references inside `executable_arguments` against the per-instance config
(§3.3). This means a blueprint can write things like:

```
executable_arguments=--start-server $instance_saves_dir/$instance_level_name --port 34197
```

Reimplementations MUST support this expansion. The full set of available
variable names is the union of every key listed in §3.3 plus the global
`config_*` keys from §1.

### 2.4 Container blueprint schema (`.docker-compose.yml`)

A standard Docker Compose v3 file with two conventions:

1. There MUST be at least one service. The first service's name becomes
   the blueprint's logical name (§2.2).
2. The compose file SHOULD use `${instance_*}` variable references
   (Docker Compose's native interpolation syntax) to bind mount the
   KGSM-managed directories into the container. Typical pattern:

   ```yaml
   services:
     vrising:
       image: ghcr.io/thekrystalship/vrising:latest
       container_name: ${instance_name}
       network_mode: host
       ports:
         - 9876:9876/udp
         - 9877:9877/udp
       volumes:
         - type: bind
           source: ${instance_install_dir}
           target: /opt/vrising/install
         - type: bind
           source: ${instance_backups_dir}
           target: /opt/vrising/backups
       restart: unless-stopped
   ```

3. Port declarations under `ports:` are parsed by KGSM (see §2.5) to
   build UFW rules.

### 2.5 Port format

KGSM uses a single string format for ports, called the **UFW format**:

```
'<spec>|<spec>|...'
```

Each spec matches one of:

| Pattern           | Meaning                                     |
| ----------------- | ------------------------------------------- |
| `<n>`             | Port `n`, both TCP and UDP.                 |
| `<n>/<proto>`     | Port `n`, single protocol (`tcp` or `udp`). |
| `<a>:<b>`         | Range `a..b`, both TCP and UDP.             |
| `<a>:<b>/<proto>` | Range `a..b`, single protocol.              |

Examples: `'34197'`, `'25565/udp'`, `'7777/tcp\|7777/udp'`,
`'27000:27050/udp'`.

For native blueprints, the user writes this string directly as the
`ports` field. For container blueprints, it is *derived* by reading
the `ports:` lines in the compose file (matching `<host>:<container>/<proto>`)
and joining them with `|`. Reimplementations MUST implement both the
parser and the deriver.

### 2.6 Blueprint discovery (`find_blueprint(name)`)

Input: a name (with or without extension).

```
strip extension if present
for dir in [
    KGSM_USER_BLUEPRINTS_NATIVE_DIR,       # search 1
    KGSM_USER_BLUEPRINTS_CONTAINER_DIR,    # search 2
    KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR,     # search 3
    KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR,  # search 4
]:
    for ext in [".bp", ".docker-compose.yml"]:
        if file <dir>/<name><ext> exists:
            return absolute path
return EC_BLUEPRINT_NOT_FOUND
```

The search order is significant and MUST be preserved.

### 2.7 Blueprint validation

Performed by `kgsm blueprints validate <name>` and by every operation
that consumes a blueprint. Checks (in order):

1. Blueprint can be located via `find_blueprint`.
2. File is readable.
3. **Native:** `name`, `executable_file`, `level_name` are present and
   non-empty.
4. **Container:** valid YAML; at least one entry under `services:`.

Failure returns `EC_INVALID_BLUEPRINT` (or `EC_BLUEPRINT_NOT_FOUND` if
step 1 fails).

---

## 3. Instances

An *instance* is a deployed game server created from a blueprint.

### 3.1 Identity

| Identifier     | Source                                            | Example                        |
| -------------- | ------------------------------------------------- | ------------------------------ |
| Blueprint name | The blueprint the instance was created from       | `factorio`                     |
| Instance ID    | Either user-supplied (`--name`) or auto-generated | `factorio-prod`, `factorio-07` |

**Auto-generation rule:** if the user does not supply a name,
generate `<blueprint>-<NN>` where `NN` is a zero-padded random
decimal of length `instance_suffix_length` (default 2). The result
MUST be unique within `KGSM_INSTANCES_DIR` — retry until uniqueness
is achieved or fail after a sensible attempt count.

### 3.2 On-disk layout

See [01-system-overview.md §1.3](01-system-overview.md). Repeated
here for reference:

```
<install-dir>/<blueprint>/<instance>/    (working directory)
├── <instance>.config.ini                (this is the source of truth)
├── <instance>.manage.sh                 (assembled, executable)
├── <instance>.log                       (live log)
├── .<instance>.pid
├── .<instance>.tail.pid
├── .<instance>.sock                     (FIFO for console input)
├── .<instance>.version
├── install/    saves/    backups/    logs/    temp/

<KGSM_INSTANCES_DIR>/<blueprint>/<instance>  →  symlink to working dir
```

The symlink under `KGSM_INSTANCES_DIR` is the **canonical discovery
point**: `kgsm instances list` enumerates these symlinks (following
them with `-L` so the actual config files are read through them).

### 3.3 Per-instance config schema

The per-instance config file is INI without sections, written from
`templates/instance.tp` at instance creation. **All values are strings;
arrays are space-separated bash arrays.** A reimplementation in another
language MUST keep the same key names (downstream tooling, including
user overrides, references them) but MAY choose any concrete file
format that round-trips faithfully.

Filename: `<instance>.config.ini` inside the working directory.

| Key                                                               | Type         | Source                          | Notes                                                 |
| ----------------------------------------------------------------- | ------------ | ------------------------------- | ----------------------------------------------------- |
| **Identity**                                                      |              |                                 |                                                       |
| `name`                                                            | string       | `--name` or auto-generated      | The instance ID.                                      |
| `blueprint_file`                                                  | path         | computed                        | Absolute path to the blueprint file.                  |
| `install_datetime`                                                | ISO-8601     | computed                        | Set on creation.                                      |
| **Paths**                                                         |              |                                 |                                                       |
| `working_dir`                                                     | path         | computed                        | Root of the instance directory tree.                  |
| `backups_dir`, `install_dir`, `saves_dir`, `temp_dir`, `logs_dir` | path         | computed                        | Subdirectories of `working_dir`.                      |
| `launch_dir`                                                      | path         | computed                        | Native: `install_dir` + `executable_subdirectory`.    |
| `executable_subdirectory`                                         | path         | blueprint                       | Copied from blueprint.                                |
| `executable_file`                                                 | string       | blueprint                       | Copied from blueprint.                                |
| `management_file`                                                 | path         | computed                        | `<working_dir>/<instance>.manage.sh`.                 |
| `compose_file`                                                    | path         | computed                        | Container: copy of the blueprint. Native: empty.      |
| **Process control files**                                         |              |                                 |                                                       |
| `version_file`                                                    | path         | computed                        | `<working_dir>/.<instance>.version`.                  |
| `pid_file`                                                        | path         | computed                        | `<working_dir>/.<instance>.pid`.                      |
| `socket_file`                                                     | path         | computed                        | `<working_dir>/.<instance>.sock`.                     |
| `log_file`                                                        | path         | computed                        | `<working_dir>/<instance>.log`.                       |
| `port_forwarding_state_file`                                      | path         | computed                        | UPnP state cache.                                     |
| **Runtime**                                                       |              |                                 |                                                       |
| `lifecycle_manager`                                               | enum         | `standalone` \| `systemd`       | Set at creation based on global `enable_systemd`.     |
| `runtime`                                                         | enum         | `native` \| `container`         | Inferred from blueprint extension.                    |
| `platform`                                                        | enum         | `linux` \| `windows` \| `macos` | From blueprint.                                       |
| `auto_update`                                                     | bool         | global default                  | Whether to update before start.                       |
| `startup_success_regex`                                           | regex        | blueprint                       | Empty if not set.                                     |
| **Game settings**                                                 |              |                                 |                                                       |
| `level_name`                                                      | string       | blueprint                       | Defaults to `default`.                                |
| `executable_arguments`                                            | string       | blueprint                       | Pre-substitution form (variables expanded at launch). |
| **Steam**                                                         |              |                                 |                                                       |
| `steam_app_id`                                                    | int          | blueprint                       | `0` if non-Steam.                                     |
| `steamcmd_arguments`                                              | string       | blueprint                       |                                                       |
| `is_steam_account_required`                                       | bool         | blueprint                       |                                                       |
| **Network**                                                       |              |                                 |                                                       |
| `ports`                                                           | string       | blueprint or derived            | UFW format (§2.5).                                    |
| `enable_port_forwarding`                                          | bool         | global config                   | Per-instance override.                                |
| `upnp_ports`                                                      | string array | parsed from `ports`             | Pairs of `port protocol port protocol …`.             |
| `enable_firewall_management`                                      | bool         | global config                   |                                                       |
| `firewall_rule_file`                                              | path         | computed                        | UFW profile path.                                     |
| `wget_timeout_seconds`                                            | int          | global config                   |                                                       |
| **Server control**                                                |              |                                 |                                                       |
| `stop_command`                                                    | string       | blueprint                       |                                                       |
| `save_command`                                                    | string       | blueprint                       |                                                       |
| `save_command_timeout_seconds`                                    | int          | global default                  |                                                       |
| `stop_command_timeout_seconds`                                    | int          | global default                  |                                                       |
| **Backup**                                                        |              |                                 |                                                       |
| `compress_backups`                                                | bool         | global default                  |                                                       |
| **System integration**                                            |              |                                 |                                                       |
| `enable_systemd`                                                  | bool         | global config                   |                                                       |
| `systemd_service_file`                                            | path         | computed                        | Empty if `enable_systemd=false`.                      |
| `systemd_socket_file`                                             | path         | computed                        |                                                       |
| **Shortcuts**                                                     |              |                                 |                                                       |
| `enable_command_shortcuts`                                        | bool         | global config                   |                                                       |
| `command_shortcut_file`                                           | path         | computed                        |                                                       |

When loaded, every key MUST be exposed to downstream code (overrides,
templates, the management script) under the prefix `instance_`. So
the on-disk key `working_dir` becomes `instance_working_dir`. This
prefix convention is part of the API surface and MUST be preserved.

### 3.4 Instance discovery

`kgsm instances list` walks `<KGSM_INSTANCES_DIR>` two levels deep
(blueprint subdir → instance symlink), following symlinks, and reads
each `<instance>.config.ini` to extract the `name` field. An optional
positional argument restricts the listing to a single blueprint
subdirectory.

Filter flags:

| Flag         | Effect                                                            |
| ------------ | ----------------------------------------------------------------- |
| `--detailed` | Include per-instance metadata (blueprint, runtime, install date). |
| `--status`   | Include runtime status (running / stopped / unknown).             |
| `--json`     | Emit a JSON array instead of plain text.                          |

### 3.5 Instance config file is the source of truth

After creation, **the per-instance config file is authoritative** for
that instance. The blueprint may be modified or removed without
breaking the instance, because every value the instance needs has been
materialised into its own config. This decoupling is intentional —
upgrading KGSM and pulling new bundled blueprints MUST NOT change
existing instances.

---

## 4. Cross-cutting parsing helpers

### 4.1 `extract_blueprint_name(input)`

Strip directory parts and known extensions to produce the logical
name. Recognised extensions to strip:
`.bp`, `.docker-compose.yml`, `.docker-compose.yaml`, `.yml`, `.yaml`.

### 4.2 `parse_ufw_to_upnp(ports_string)`

Parses the UFW format of §2.5 and returns a flat sequence of
`port protocol` pairs. Single ports without a protocol expand to
**both** `tcp` and `udp` pairs. Port ranges expand to one entry per
port.

### 4.3 `parse_compose_to_ufw(compose_path)`

Read the compose file line by line, match lines under any
`ports:` block of the form `- "<host>:<container>/<proto>"`, and
return the joined UFW string `'host1/proto1|host2/proto2|...'`.
A regex sufficient for this is:

```
^\s*-\s*"?(\d+):(\d+)/(tcp|udp)"?
```

Implementations MAY use a real YAML parser instead, but MUST produce
the same UFW string.
