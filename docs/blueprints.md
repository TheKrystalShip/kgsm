# Blueprints 101

This document explains what blueprints are, how they work in KGSM, and how to create or customize them.

## Table of Contents
- [What are Blueprints?](#what-are-blueprints)
- [Blueprint Storage](#blueprint-storage)
- [Required Fields](#required-fields)
- [Metadata](#metadata)
- [Managing Blueprints](#managing-blueprints)
  - [Listing Available Blueprints](#listing-available-blueprints)
  - [Inspecting a Blueprint](#inspecting-a-blueprint)
  - [Validating a Blueprint](#validating-a-blueprint)
  - [Creating New Blueprints](#creating-new-blueprints)
  - [Customizing Existing Blueprints](#customizing-existing-blueprints)
- [Using Blueprints](#using-blueprints)
- [Native Blueprint Reference](#native-blueprint-reference)
  - [Example Template](#native-blueprint-example-template)
  - [Key Parameters](#native-blueprint-key-parameters)
  - [Available Instance Variables](#available-instance-variables)
- [Container Blueprint Reference](#container-blueprint-reference)
  - [Example Template](#container-blueprint-example-template)
  - [Key Components](#container-blueprint-components)
  - [Container Images](#container-images)
- [Contributing](#contributing)
  - [Contributing Blueprints](#contributing-blueprints)
  - [Contributing Container Images](#contributing-container-images)

## What are Blueprints?

Blueprints in KGSM are configuration files that define the parameters needed to create a game server. These parameters typically include server settings such as port numbers, game world names, maximum player counts, and other initialization values required to start and configure the server properly. Think of them like an architect's blueprint: a detailed plan to build something specific.

A blueprint is **one YAML file per game**, named `<name>.bp.yaml`, that holds a
game server's *entire identity* in a single place: presentation metadata plus
everything needed to install, configure, and run it. The `runtime` field —
`native` or `container` — decides how the server runs:

1. **Native** servers run directly on your system as a Linux process; their
   parameters live under a `native:` block.
2. **Container** servers run as a Docker Compose stack embedded under
   `container.compose`.

There is no separate file format or directory per type — a single unified file
covers both. Blueprints are parsed with [**mikefarah/yq**](https://github.com/mikefarah/yq)
(Arch package `go-yq`), which is a **hard dependency**: blueprint operations on a
host without it fail immediately with a clear message.

KGSM comes with a growing collection of pre-configured blueprints for popular game servers, making it easy to get started quickly without having to create custom configurations from scratch.

## Blueprint Storage

KGSM follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/) to separate read-only system blueprints from user-managed ones. Each is a single **flat** directory of `*.bp.yaml` files (no `native/` vs `container/` subdirectories):

- **System Blueprints** (read-only, provided by KGSM, updated with the package):
  - `blueprints/` — all shipped blueprints, e.g. `blueprints/factorio.bp.yaml`

- **User Blueprints** (writable, managed by you):
  - `~/.local/share/kgsm/blueprints/` — your custom blueprints

  > The base path respects `$XDG_DATA_HOME` if that environment variable is set.

When KGSM resolves a blueprint by name, **user blueprints take precedence over system blueprints**. A user blueprint with the same filename as a system blueprint will shadow it, allowing you to override defaults without modifying the originals.

> [!IMPORTANT]
> Never modify files in the system `blueprints/` directory directly. Those files may be overwritten during KGSM updates. Always create your customized copies in the user blueprint directory.

### Blueprint to Override Relationship

The `name` field in a blueprint connects it to a corresponding override directory, for **both** runtimes. For example, a blueprint with `name: factorio` makes KGSM look for override modules in `overrides/factorio/` during management script assembly. Multiple blueprint variants can share the same `name`, allowing them to reuse the same override logic (e.g., `terraria-modded.bp.yaml` with `name: terraria` uses `overrides/terraria/`). The binding is always the `name` field — never the file name, and (unlike older KGSM) never the first service name in a container's compose.

For details about overrides and how they provide custom functionality for specific game servers, see [Overrides 101](overrides.md).

## Required Fields

Every blueprint, regardless of runtime, must declare:

| Field | Description |
|-------|-------------|
| `schema_version` | Format version. Currently `1` (a future-migration hook). |
| `name` | Unique, lowercase, no spaces. Also the override-binding key. |
| `runtime` | `native` or `container`. |
| `metadata:` | A block of advisory presentation fields (see below). The keys must be present; the values may be `null`. |

Then, depending on `runtime`:

- **native** requires `native.executable_file` (everything else under `native:` is optional with sensible defaults).
- **container** requires `container.compose` with at least one service.

## Metadata

The `metadata:` block carries advisory, presentation-oriented information for
catalogs and UIs (such as the control panel) — it does **not** affect how a
server installs or runs, so a blueprint is fully functional with every metadata
value left `null`.

```yaml
metadata:
  display_name: "Factorio"          # human-friendly name ("7 Days to Die", not "7dtd")
  description: "Automation/factory-building dedicated server."
  rawg_slug: "factorio"             # RAWG.io slug for cover art/metadata; null if unverified
  max_players: 65535                # null if unbounded/configurable/unknown
  min_ram_mb: 2048                  # advisory minimum RAM
  recommended_ram_mb: 4096          # advisory recommended RAM
  base_disk_mb: 3000                # base install footprint (grows with saves/mods)
```

> [!NOTE]
> `rawg_slug` is the game's slug on [RAWG.io](https://rawg.io), the external
> catalog the control panel uses to fetch cover art, descriptions, and tags. It
> is a *lookup hint* only — KGSM never calls RAWG; the consumer (kgsm-api) does,
> and caches the result. It is the same kind of external-catalog identifier as
> `native.steam_app_id`. The blueprint `name` is **not** assumed to equal the
> slug (`gmod` → `garrys-mod`, `ark` → `ark-survival-evolved`). Set it **only
> when verified**; leave it `null` otherwise — a wrong slug is misattribution.

> [!IMPORTANT]
> Every metadata value is **nullable**, and `null` means *unknown or unbounded*
> — it is **never** a substitute for a real `0`. These figures are
> vendor-declared estimates, not measured guarantees. Honoring KGSM's
> "never fabricate a metric" rule, leave anything you are unsure of as `null`
> rather than guessing a number. (On the wire, `kgsm blueprints info --json`
> emits these under a nested `Metadata` object, with unknown numerics as JSON
> `null`.)

## Managing Blueprints

### Listing Available Blueprints

To list all available blueprints, run:

```sh
./kgsm.sh blueprints list
```

Filter to show only system (default) or user (custom) blueprints:

```sh
./kgsm.sh blueprints list default
./kgsm.sh blueprints list custom
```

Show detailed metadata for each blueprint:

```sh
./kgsm.sh blueprints list detailed
```

Output any of the above in JSON format for scripting:

```sh
./kgsm.sh blueprints list --json
./kgsm.sh blueprints list default --json
./kgsm.sh blueprints list detailed --json
```

### Inspecting a Blueprint

Display the full contents of a blueprint:

```sh
./kgsm.sh blueprints info factorio
./kgsm.sh blueprints info factorio --json
```

Find the absolute path to a blueprint file:

```sh
./kgsm.sh blueprints find factorio
```

Because a user blueprint shadows a same-named system one, the path a name
resolves to does not by itself say whether a shipped blueprint is being
overridden. `--all` reports every candidate path in precedence order along with
whether it exists, and `--json` returns the same set as an object:

```sh
./kgsm.sh blueprints find factorio --all
./kgsm.sh blueprints find factorio --json
```

Both candidates existing means a user copy is shadowing a shipped blueprint;
only the user candidate existing means the blueprint is purely custom, with no
original to fall back to. These modes report on existence alone and skip the
format check, so a malformed blueprint can still be located and repaired.

### Validating a Blueprint

Check a blueprint's YAML syntax and required fields:

```sh
./kgsm.sh blueprints validate factorio
./kgsm.sh blueprints validate factorio --json
```

An argument naming an existing file is checked as a path rather than a
blueprint name, so a file can be validated before it is committed under a
blueprint's real name:

```sh
./kgsm.sh blueprints validate /tmp/mygame.bp.yaml --json
```

Nothing is written and no event is emitted. `--json` reports every problem
found rather than stopping at the first:

```json
{
  "Valid": false,
  "Path": "/tmp/mygame.bp.yaml",
  "Errors": [
    "Blueprint missing required field 'name': /tmp/mygame.bp.yaml",
    "Native blueprint missing required field 'native.executable_file': /tmp/mygame.bp.yaml"
  ]
}
```

### Creating New Blueprints

To create a blueprint for a game server that KGSM does not include:

1. Copy the blank template to the user blueprint directory as `<name>.bp.yaml`:

   ```sh
   cp templates/blueprint.tp ~/.local/share/kgsm/blueprints/mygame.bp.yaml
   ```

2. Open the file in your editor, set `name` and `runtime`, and fill in the
   matching block (`native:` or `container:`) plus any metadata you know. The
   template documents every field inline.

3. Save the file. The blueprint is immediately available to KGSM. Verify it:

   ```sh
   ./kgsm.sh blueprints info mygame
   ```

> [!TIP]
> You can use an existing blueprint as a starting point. For example:
> ```sh
> cp blueprints/minecraft.bp.yaml ~/.local/share/kgsm/blueprints/my-custom-game.bp.yaml
> ```

### Customizing Existing Blueprints

To adjust a system blueprint without modifying the original:

1. Copy it from the system directory to the user directory (same file name):

   ```sh
   cp blueprints/minecraft.bp.yaml ~/.local/share/kgsm/blueprints/minecraft.bp.yaml
   ```

2. Edit your copy. KGSM will automatically prefer the user copy over the system original.

## Using Blueprints

Once you have a blueprint, create a new game server instance with:

```sh
./kgsm.sh install <blueprint> [--install-dir <path>] [--name <instance-name>]
```

`create` is an accepted alias for `install`.

KGSM reads the blueprint's `runtime` field to decide whether to install it as a native process or a container stack, and handles it accordingly.

### Native Server Example

```sh
./kgsm.sh install minecraft --install-dir /opt/servers --name survival-server
```

### Container Server Example

```sh
./kgsm.sh install enshrouded --install-dir /opt/servers --name enshrouded-server
```

> [!NOTE]
> Using container-based game servers requires Docker and Docker Compose to be installed on your system. KGSM will check for these dependencies when creating container-based server instances.

## Native Blueprint Reference

> For the *reasoning* behind these fields — how to choose the executable (wrapper script vs raw
> binary vs interpreter), how SteamCMD app ids and account ownership work, and annotated real
> examples grouped by pattern — see the [knowledge base](knowledge/README.md).

### Native Blueprint Example Template

Below is a representative native blueprint (Factorio). The `native:` block holds
the runtime-specific fields; the top-level `schema_version`/`name`/`runtime`/
`metadata` are shared by every blueprint:

```yaml
schema_version: 1
name: factorio
runtime: native
metadata:
  display_name: "Factorio"
  description: "Automation/factory-building dedicated server."
  rawg_slug: "factorio"      # RAWG.io slug; null if unverified
  max_players: null          # null = unknown/unbounded, NEVER 0
  min_ram_mb: null
  recommended_ram_mb: null
  base_disk_mb: null
native:
  # Port(s), in UFW format. Single-quoted, pipe-separated.
  # Example: '1111:2222/tcp|1111:2222/udp'
  ports: '34197'

  # Steam App ID. 0 if not applicable, a valid Steam app id otherwise.
  steam_app_id: 0

  # Client Steam App ID — the game players launch to connect. 0 if not Steam.
  client_steam_app_id: 0

  # (Optional) Additional steamcmd arguments, e.g. "+beta <branch>".
  steamcmd_arguments: ""

  # Only applicable if steam_app_id != 0. false = anonymous, true = account required.
  is_steam_account_required: false

  # (Optional) Target platform if not Linux. windows / linux / macos.
  platform: linux

  # Savefile / world / level name, whichever applies.
  level_name: default

  # (Optional) Subdirectory containing the executable, relative to install dir.
  executable_subdirectory: bin/x64

  # Name of the executable that starts the server. (Required for native.)
  executable_file: factorio

  # (Optional) Arguments passed to the executable. Single-quote so $instance_*
  # variables (see "Available Instance Variables") survive to runtime.
  executable_arguments: '--start-server $instance_saves_dir/$instance_level_name'

  # (Optional) Stop / save commands sent to the input socket.
  stop_command: /quit
  save_command: /save

  # (Optional) Regex matching the startup-success log line. If unset, KGSM waits
  # for the server to listen on the declared ports.
  startup_success_regex: "Hosting game at IP ADDR"
```

### Native Blueprint Key Parameters

All of these live under the `native:` block. Only `executable_file` is required;
the rest are optional with the noted defaults.

| Parameter | Description | Required | Example |
|-----------|-------------|:--------:|---------|
| `executable_file` | Name of the server executable | Yes | `factorio` |
| `ports` | Network ports in UFW format (single-quoted) | No | `'25565/tcp'` |
| `steam_app_id` | Steam App ID (`0` if not applicable) | No | `294420` |
| `client_steam_app_id` | Client Steam App ID for launch/connect (`0` if not Steam) | No | `251570` |
| `steamcmd_arguments` | Extra arguments passed to steamcmd | No | `"+beta public"` |
| `is_steam_account_required` | Whether a Steam account is required (`false`/`true`) | No | `false` |
| `platform` | Target platform (`linux`, `windows`, `macos`) | No | `linux` |
| `level_name` | World/map/save name (defaults to `default`) | No | `default` |
| `executable_subdirectory` | Subdirectory containing the executable | No | `bin/x64` |
| `executable_arguments` | Command-line arguments for the server | No | `--dedicated` |
| `stop_command` | Command sent to socket to stop the server | No | `/quit` |
| `save_command` | Command sent to socket to save the game | No | `/save` |
| `startup_success_regex` | Regex matching the server-ready log line | No | `"Server started"` |

### Available Instance Variables

The following variables can be used inside `executable_arguments` and are resolved at runtime:

**Basic Instance Information**

| Variable | Description |
|----------|-------------|
| `$instance_name` | The instance identifier |
| `$instance_blueprint_file` | Absolute path to the blueprint file |
| `$instance_install_datetime` | Timestamp when the instance was installed |

**Directory and File Paths**

| Variable | Description |
|----------|-------------|
| `$instance_working_dir` | Absolute path to the working directory |
| `$instance_install_dir` | Absolute path to the installation directory |
| `$instance_saves_dir` | Absolute path to the saves directory |
| `$instance_backups_dir` | Absolute path to the backups directory (outside `working_dir`) |
| `$instance_temp_dir` | Absolute path to the temp directory |
| `$instance_logs_dir` | Absolute path to the logs directory |
| `$instance_launch_dir` | Directory from which the binary is launched |
| `$instance_executable_subdirectory` | Subdirectory containing the executable |
| `$instance_management_file` | Path to the management script |
| `$instance_compose_file` | Path to the docker-compose file (container only) |

**Process Management Files**

| Variable | Description |
|----------|-------------|
| `$instance_version_file` | Path to the version file |
| `$instance_pid_file` | Path to the PID file |
| `$instance_tail_pid_file` | Path to the tail PID file |
| `$instance_socket_file` | Path to the input socket file |

**Runtime Configuration**

| Variable | Description |
|----------|-------------|
| `$instance_runtime` | Runtime type (`native`, `container`) |
| `$instance_platform` | Target platform (`linux`, `windows`, `macos`) |
| `$instance_auto_update` | Whether to auto-update before starting |
| `$instance_logs_redirect` | Log redirection pattern |

**Game Server Configuration**

| Variable | Description |
|----------|-------------|
| `$instance_level_name` | Default level/world name |
| `$instance_executable_file` | The executable filename |
| `$instance_executable_arguments` | The command-line arguments |

**Steam Integration**

| Variable | Description |
|----------|-------------|
| `$instance_steam_app_id` | Steam App ID for downloads |
| `$instance_client_steam_app_id` | Client Steam App ID for launch/connect deeplinks |
| `$instance_is_steam_account_required` | Whether a Steam account is required |

**Network Configuration**

| Variable | Description |
|----------|-------------|
| `$instance_ports` | Network ports in UFW format |
| `$instance_enable_firewall_management` | Whether firewall management is enabled |
| `$instance_firewall_rule_file` | Path to the firewall rule file |

**Server Control**

| Variable | Description |
|----------|-------------|
| `$instance_stop_command` | Command to gracefully stop the server |
| `$instance_save_command` | Command to save the game state |
| `$instance_save_command_timeout_seconds` | Timeout for the save command |
| `$instance_stop_command_timeout_seconds` | Timeout for the stop command |

**Backup Configuration**

| Variable | Description |
|----------|-------------|
| `$instance_compress_backups` | Whether to compress backups |

**Management Features**

| Variable | Description |
|----------|-------------|
| `$instance_enable_command_shortcuts` | Whether command shortcuts are enabled |
| `$instance_command_shortcut_file` | Path to the command shortcut file |

## Container Blueprint Reference

### Container Blueprint Example Template

A container blueprint embeds its Docker Compose **verbatim** under
`container.compose` as a YAML *literal block scalar* (`compose: |`). The compose
text is opaque to KGSM — comments and `${instance_*}` placeholders are preserved
exactly — and is extracted to the instance's `docker-compose.yml` (with
`${instance_*}` substituted) at create time. Below is a representative example
(V Rising):

```yaml
schema_version: 1
name: vrising
runtime: container
metadata:
  display_name: "V Rising"
  description: "Survival vampire dedicated server (official image)."
  rawg_slug: "v-rising"      # RAWG.io slug; null if unverified
  max_players: null          # null = unknown/unbounded, NEVER 0
  min_ram_mb: null
  recommended_ram_mb: null
  base_disk_mb: null
container:
  compose: |
    services:
      vrising:

        # Official image for V Rising
        image: ghcr.io/thekrystalship/vrising:latest

        # Dynamic container name set by KGSM at deploy time
        container_name: ${instance_name}

        # Use the host's network stack directly
        network_mode: host

        # Ports the server uses (KGSM derives firewall rules from these)
        ports:
          - 9876:9876/udp
          - 9877:9877/udp
          - 27015:27015/udp
          - 27016:27016/udp

        # Bind mount volumes for persistent storage
        volumes:
          - type: bind
            source: ${instance_backups_dir}
            target: /opt/vrising/backups
          - type: bind
            source: ${instance_install_dir}
            target: /opt/vrising/install

        # Restart policy to keep the container running
        restart: unless-stopped
```

> [!NOTE]
> A container blueprint has **no** top-level `ports` field — KGSM **derives** the
> firewall ports from the `ports:` entries inside the embedded compose, so the
> compose is the single source of truth for ports.

> [!IMPORTANT]
> Every service **must** set `network_mode: host` — KGSM validates this and
> rejects a container blueprint without it. Host networking makes the container
> listen directly on the host network stack, so the host firewall (ufw /
> kgsm-firewall) governs it through the `INPUT` chain exactly like a native
> instance. Under host networking Docker **ignores** the `ports:` block; KGSM
> reads it as the declarative source for the firewall rule and router UPnP
> mappings. A bridge-networked service would instead DNAT-publish those ports
> into Docker's `FORWARD`/`DOCKER-USER` path, bypassing the host firewall — which
> is why it is not allowed.

> [!IMPORTANT]
> KGSM uses official container images from the [KGSM-Containers](https://github.com/TheKrystalShip/kgsm-containers) project. These images are specifically tested and configured to work with the KGSM ecosystem. While you can use other container images, the official ones ensure compatibility and proper integration.

### Container Blueprint Components

#### 1. Docker Image

Specify the Docker image for the game server. The official KGSM images are hosted at `ghcr.io/thekrystalship/`:

```yml
image: ghcr.io/thekrystalship/vrising:latest
```

#### 2. Container Name

Set the container name to the KGSM instance name so KGSM can manage it:

```yml
container_name: ${instance_name}
```

#### 3. Network Configuration

Most game servers benefit from host networking for optimal performance:

```yml
network_mode: host
```

#### 4. Port Mapping

Explicitly declaring ports documents which ports the server uses and allows KGSM to configure firewall rules:

```yml
ports:
  - 27015:27015/udp
  - 27016:27016/tcp
```

#### 5. Volume Mounts

Use `$instance_*` path variables to bind-mount the correct KGSM-managed directories into the container:

```yml
volumes:
  - type: bind
    source: ${instance_install_dir}
    target: /app/install
  - type: bind
    source: ${instance_backups_dir}
    target: /app/backups
```

#### 6. Environment Variables

Pass any required configuration as environment variables:

```yml
environment:
  SERVER_NAME: "My Server"
  MAX_PLAYERS: "16"
```

#### 7. Restart Policy

Include a restart policy for production stability:

```yml
restart: unless-stopped
```

### Container Images

The container images used by KGSM are maintained in a dedicated repository: [kgsm-containers](https://github.com/TheKrystalShip/kgsm-containers). These images are specifically designed to work well with the KGSM ecosystem and have been thoroughly tested.

## Contributing

### Contributing Blueprints

The list of supported game servers in KGSM is constantly growing! If you create a blueprint that works well, consider contributing it back to the project to help other users.

To submit your blueprint:
1. Ensure it is well-tested and properly configured
2. Create a pull request on GitHub with your blueprint file
3. Alternatively, [submit a feature request](https://github.com/TheKrystalShip/kgsm/issues/new?template=add_game_server.md) with your blueprint attached

Community contributions are what make KGSM better for everyone!

### Contributing Container Images

If you want to contribute a new container image for a game server:

1. Visit the [kgsm-containers](https://github.com/TheKrystalShip/kgsm-containers) repository
2. Follow the contribution guidelines specific to that project
3. Submit your container image via a Pull Request

Once your container image is accepted and published to the official repository, you can then create a corresponding `<name>.bp.yaml` blueprint (`runtime: container`) whose embedded `container.compose` uses your image.
