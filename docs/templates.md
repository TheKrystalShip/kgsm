# Templates in KGSM

Templates in KGSM are standardized files that provide consistent structure for generating and managing game server configuration and runtime artifacts. They act as the blueprints that KGSM uses to produce instance configuration files, management scripts, and firewall rules — each tailored to the specific parameters of a deployed game server.

## Table of Contents

- [How Templates Work](#how-templates-work)
- [Template Reference](#template-reference)
  - [blueprint.tp](#blueprinttp)
  - [instance.tp](#instancetp)
  - [manage.native.d/](#managenativedd)
  - [manage.container.d/](#managecontainerd)
  - [overrides.tp](#overridestown)
- [Template Variables Reference](#template-variables-reference)
- [Usage Guidelines](#usage-guidelines)

## How Templates Work

All template files use the `.tp` extension and live in the `templates/` directory. KGSM expands templates using bash variable substitution: the template content is evaluated in a subshell that has all relevant `$instance_*` and `$config_*` variables exported into it. This means any shell variable reference (`$instance_name`, `${instance_ports}`, etc.) in a template is replaced with its value at expansion time.

The template engine lives in `commands/handlers/templates.sh` and exposes these functions for internal use:

| Function | Purpose |
|---|---|
| `__logic_find_template` | Locate a `.tp` file by name |
| `__logic_expand_template` | Expand a template using current environment variables |
| `__logic_expand_template_with_vars` | Expand a template with an explicit variable map |
| `__logic_validate_template_vars` | Confirm that required variables are present in a template |
| `__logic_list_templates` | List all available templates by name |

The low-level file discovery is handled by `__find_template` in `core/loader.sh`.

> [!NOTE]
> Template files in `templates/` should never be modified directly. They are internal KGSM artifacts. To customize behavior, use the appropriate directories: `~/.local/share/kgsm/blueprints/` for blueprint variants, or `overrides/` for game-specific function implementations.

## Template Reference

### blueprint.tp

**Purpose:** A human-readable starting point for creating a new blueprint. It documents every supported field with inline comments, examples (both `native:` and `container:`), the `metadata:` block, and the full list of `$instance_*` variables available for use in `executable_arguments`.

**Used by:** Not expanded programmatically. Referenced in `commands/blueprints.sh` documentation and in the KGSM user guide as the canonical example for authoring blueprints.

**Format:** Unified YAML (`<name>.bp.yaml`), parsed with mikefarah/yq.

**Key fields defined:** Top-level `schema_version`, `name`, `runtime`, and a nullable `metadata:` block are shared by both runtimes. The fields below live under the `native:` block; only `executable_file` is required.

| Field | Required | Description |
|---|---|---|
| `executable_file` | Yes | Server binary name |
| `ports` | No | Network ports in UFW format, e.g. `'27015/tcp\|27015/udp'` |
| `steam_app_id` | No | Steam App ID; `0` if not applicable |
| `client_steam_app_id` | No | Client Steam App ID for launch/connect; `0` if not Steam |
| `is_steam_account_required` | No | `true` if a Steam account is needed |
| `platform` | No | Target OS: `linux` (default), `windows`, `macos` |
| `level_name` | No | Default world/map name (defaults to `default`) |
| `executable_subdirectory` | No | Relative subdirectory containing the binary |
| `executable_arguments` | No | CLI arguments passed to the server binary |
| `stop_command` | No | Command sent to the input socket to stop the server |
| `save_command` | No | Command sent to the input socket to save the game |
| `startup_success_regex` | No | Regex matched against server log to detect successful startup |

For a container blueprint (`runtime: container`), the body is instead a `container.compose` literal block scalar holding the Docker Compose verbatim; firewall ports are derived from it.

---

### instance.tp

**Purpose:** Template for the per-instance configuration file (`.ini`-style). When a new instance is created, KGSM expands this template with all resolved `$instance_*` values and writes the result to the instance's working directory. This file is the authoritative runtime configuration for the instance.

**Used by:** `commands/handlers/instances.sh` during instance creation.

**Format:** Sectioned INI-style, with inline comments grouping fields into logical sections.

**Sections:**

| Section | Fields |
|---|---|
| Basic Instance Information | `name`, `blueprint_file`, `install_datetime` |
| Directory and File Paths | `working_dir`, `backups_dir`, `install_dir`, `saves_dir`, `temp_dir`, `logs_dir`, `launch_dir`, `executable_subdirectory`, `executable_file`, `management_file`, `compose_file` |
| Process Management Files | `version_file`, `pid_file`, `socket_file`, `log_file` |
| Runtime Configuration | `runtime`, `platform`, `auto_update`, `startup_success_regex` |
| Game Server Executable Configuration | `level_name`, `executable_arguments` |
| Steam Integration | `steam_app_id`, `steamcmd_arguments`, `is_steam_account_required` |
| Network Configuration | `ports`, `enable_firewall_management`, `firewall_rule_file`, `wget_timeout_seconds` |
| Server Control Commands | `stop_command`, `save_command`, `save_command_timeout_seconds`, `stop_command_timeout_seconds` |
| Backup Configuration | `compress_backups` |
| Management Features | `enable_command_shortcuts`, `command_shortcut_file` |

---

### manage.native.d/

**Purpose:** Directory of numbered module files that are concatenated during instance creation to produce the per-instance management script for **native** (non-containerized) game servers. Each module handles one concern (lifecycle, I/O, version management, download, deploy, backup, network, logging, status).

**Modules:**

| File | Responsibility |
|------|----------------|
| `00-header.sh` | Shebang, global flags, bootstrap |
| `01-config.sh` | Instance config loading (`__source_instance_config`) |
| `02-help.sh` | `--help` output |
| `03-lifecycle.sh` | Start / stop / restart logic |
| `04-io.sh` | Input / output helpers |
| `05-version.sh` | Version retrieval and comparison |
| `06-download.sh` | File download |
| `07-deploy.sh` | File deployment |
| `08-backup.sh` | Backup management |
| `09-network.sh` | ~~UPnP port management~~ (removed — watchdog owns UPnP lifecycle) |
| `10-logging.sh` | Log printing and rotation |
| `11-status.sh` | Server status reporting |
| `12-commands.sh` | CLI argument dispatch |
| `13-dispatch.sh` | Main entry point / argument parsing |

**Used by:** `commands/handlers/files.management.sh` (`__logic_create_management_file`) when `instance_runtime=native`. Modules 03–08 and 10–11 may be replaced by per-game override modules from `overrides/{blueprint_name}/`. Can be manually regenerated with:

```bash
./kgsm.sh files management create <instance_name>
```

**Format:** Each module is a self-contained bash fragment. They are concatenated in numerical order into a single `#!/usr/bin/env bash` script.

---

### manage.container.d/

**Purpose:** Equivalent to `manage.native.d/` for **containerized** game servers. All lifecycle operations (`--start`, `--stop`, `--restart`, `--update`) are implemented via `docker compose` rather than direct process management.

**Used by:** `commands/handlers/files.management.sh` when `instance_runtime=container`. Can be manually regenerated with:

```bash
./kgsm.sh files management create <instance_name>
```

**Format:** Same numbered module structure as `manage.native.d/`. Reads `$instance_compose_file` and delegates container operations to Docker Compose.

---

### overrides.tp

**Purpose:** A reference file documenting the module-based override system and available variables. Documents which modules can be overridden (03–11), the copy-and-modify workflow, helper function naming conventions, and the full list of `$instance_*` and `$config_*` variables available to override modules.

**Used by:** Not expanded programmatically. Serves as a starting point and API reference for authors writing override modules.

**Format:** Bash script with inline documentation comments. Describes the override directory structure and workflow.

For a detailed explanation of overrides and the override system, see [Overrides 101](overrides.md).

---

## Template Variables Reference

The following `$instance_*` variables are available in templates that are expanded during instance creation or file generation. They are resolved from the instance configuration file at the time of expansion.

### Basic Instance Information

| Variable | Description |
|---|---|
| `$instance_name` | Unique instance identifier |
| `$instance_blueprint_file` | Absolute path to the blueprint file |
| `$instance_install_datetime` | Timestamp of when the instance was installed |

### Directory and File Paths

| Variable | Description |
|---|---|
| `$instance_working_dir` | Root working directory for all instance files |
| `$instance_install_dir` | Directory where server binaries are installed |
| `$instance_backups_dir` | Directory holding this instance's backups (outside `working_dir`) |
| `$instance_saves_dir` | Directory for save files |
| `$instance_temp_dir` | Temporary directory for downloads and processing |
| `$instance_logs_dir` | Directory for server log output |
| `$instance_launch_dir` | Directory from which the server binary is launched |
| `$instance_executable_subdirectory` | Subdirectory within `install_dir` containing the binary |
| `$instance_management_file` | Absolute path to the generated management script |
| `$instance_compose_file` | Absolute path to the docker-compose file (container only) |

### Process Management Files

| Variable | Description |
|---|---|
| `$instance_version_file` | Path to the file storing the installed version |
| `$instance_pid_file` | Path to the PID file for the running process |
| `$instance_tail_pid_file` | Path to the tail PID file |
| `$instance_socket_file` | Path to the named pipe for sending commands to the server |
| `$instance_log_file` | Path to the active server log file |

### Runtime Configuration

| Variable | Description |
|---|---|
| `$instance_runtime` | Runtime type: `native` or `container` |
| `$instance_platform` | Target platform: `linux`, `windows`, or `macos` |
| `$instance_auto_update` | `true` if the server auto-updates before starting |
| `$instance_startup_success_regex` | Regex matched against log output to detect successful startup |

### Game Server Executable Configuration

| Variable | Description |
|---|---|
| `$instance_level_name` | Default world/level name |
| `$instance_executable_file` | Server binary filename |
| `$instance_executable_arguments` | CLI arguments passed to the server binary |

### Steam Integration

| Variable | Description |
|---|---|
| `$instance_steam_app_id` | Steam App ID; `0` if not Steam-based |
| `$instance_client_steam_app_id` | Client Steam App ID for launch/connect; `0` if not Steam |
| `$instance_steamcmd_arguments` | Additional arguments passed to SteamCMD |
| `$instance_is_steam_account_required` | `true` if a Steam account is required for download |

### Network Configuration

| Variable | Description |
|---|---|
| `$instance_ports` | Ports in UFW format, e.g. `27015/udp\|27015/tcp` |
| `$instance_enable_firewall_management` | `true` if UFW firewall management is enabled |
| `$instance_firewall_rule_file` | Path to the generated UFW profile file |

### Server Control

| Variable | Description |
|---|---|
| `$instance_stop_command` | Command sent to the socket to gracefully stop the server |
| `$instance_save_command` | Command sent to the socket to save game state |
| `$instance_save_command_timeout_seconds` | Seconds to wait after sending the save command |
| `$instance_stop_command_timeout_seconds` | Seconds to wait for graceful shutdown |

### Backup Configuration

| Variable | Description |
|---|---|
| `$instance_compress_backups` | `true` if backups are compressed |

### Management Features

| Variable | Description |
|---|---|
| `$instance_enable_command_shortcuts` | `true` if command shortcut symlinks are created |
| `$instance_command_shortcut_file` | Path to the command shortcut symlink |

### Global Configuration Variables

These `$config_*` variables reflect KGSM-wide settings and are also available in templates:

| Variable | Description |
|---|---|
| `$config_wget_timeout_seconds` | Timeout in seconds for `wget` operations (default: `60`) |
| `$config_enable_logging` | `true` if file logging is enabled |
| `$config_enable_firewall_management` | Global UFW management toggle |
| `$config_enable_backup_compression` | Global backup compression toggle |

---

## Usage Guidelines

- **Never modify files in `templates/`**. These are internal KGSM files and may be overwritten during updates.
- To create a new blueprint, copy `templates/blueprint.tp` to `~/.local/share/kgsm/blueprints/your_game.bp.yaml` and fill in the fields.
- To add game-specific logic, create a directory `overrides/{blueprint_name}/`, copy the relevant default modules from `templates/manage.native.d/`, and modify only the functions you need. See `docs/overrides.md` for details.
- If a management script becomes corrupted or needs to be regenerated, use:
  ```bash
  ./kgsm.sh files management create <instance_name>
  ```
- The management script is assembled from numbered modules in `templates/manage.{runtime}.d/`, with per-game overrides from `overrides/{blueprint_name}/` substituted for modules 03–11 where they exist.
