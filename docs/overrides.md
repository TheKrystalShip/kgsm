# Overrides 101

This document explains what overrides are, how they work in KGSM, and how to create and use them effectively to customize game server management.

## Table of Contents

- [What are Overrides?](#what-are-overrides)
  - [Common Use Cases](#common-use-cases)
- [How Overrides Work](#how-overrides-work)
  - [Override Search Order](#override-search-order)
- [Override System Components](#override-system-components)
  - [Available Functions](#available-functions)
  - [Available Variables](#available-variables)
  - [Blueprint-Override Linking](#blueprint-override-linking)
    - [Native Blueprints](#native-blueprints)
    - [Container Blueprints](#container-blueprints)
    - [Example: Multiple Blueprint Variants](#example-multiple-blueprint-variants)
- [Design Decision: Name-Based Matching](#design-decision-name-based-matching)
  - [Why Name-Based Matching Was Chosen](#why-name-based-matching-was-chosen)
  - [Comparison: Name-Based vs File-Based Matching](#comparison-name-based-vs-file-based-matching)
  - [Best Practices for Name-Based Matching](#best-practices-for-name-based-matching)
- [Creating Overrides](#creating-overrides)
  - [Getting Started](#getting-started)
  - [Real-World Example: Factorio](#real-world-example-factorio)
  - [Error Handling](#error-handling)
- [Best Practices and Guidelines](#best-practices-and-guidelines)
  - [Core Principles](#core-principles)
  - [File Permissions](#file-permissions)

## What are Overrides?

Overrides are custom script files that allow you to replace specific functions in a game server's management script with your own implementations. They serve several important purposes:

- **Enable support for diverse game servers**: Particularly useful for non-Steam games that require custom installation, update, or runtime handling
- **Keep KGSM's core modular**: By externalizing game-specific code, the main codebase remains clean and maintainable
- **Provide flexibility**: Allow any management function to be customized without modifying KGSM's core scripts

### Common Use Cases

Overrides are typically used for:
- Creating custom version-checking for games with unique versioning systems
- Implementing specialized download procedures for games not available through Steam
- Adding unique startup/shutdown sequences for games with special requirements
- Developing custom backup and restoration logic for complex game data structures

## How Overrides Work

When KGSM manages a game server instance, it loads overrides through `core/overrides.sh`:

1. The module receives the **instance name** as its argument
2. It reads the instance's config file to locate the associated blueprint file
3. For **native blueprints** (`.bp` files), it reads the `name=` field from the blueprint
4. For **container blueprints** (`.docker-compose.yml` files), it reads the first service name listed under `services:`
5. It searches for a file named `{blueprint_name}.overrides.sh` in the [override search directories](#override-search-order)
6. If found, the file is sourced using bash's `source` command, making any defined functions available
7. Those functions then **replace** the default implementations in the management script
8. Functions not defined in the override continue to use their default implementations
9. If no override file is found, all functions use their default implementations

This selective replacement system means you only need to implement the specific functions that require customization for your game server.

### Override Search Order

KGSM searches for override files in the following order, using the **first match found**:

1. **User overrides directory** (XDG-compliant, writable):
   `${XDG_DATA_HOME:-$HOME/.local/share}/kgsm/overrides/`
2. **System overrides directory** (shipped with KGSM):
   `${KGSM_ROOT}/overrides/`

This means user-defined overrides always take precedence over the bundled system overrides. To customize the behavior of a bundled game (such as Factorio or Terraria) without modifying the system files, place your override file in the user overrides directory with the same filename.

## Override System Components

### Available Functions

Any of the following functions from `templates/overrides.tp` can be overridden. Implement only the ones you need:

**Version Management**

| Function | Signature | Purpose |
|---|---|---|
| `_get_latest_version` | `() → echo "$version"` | Query remote source for the latest available version |
| `_get_installed_version` | `() → echo "$version"` | Read the currently installed version from `$instance_version_file` |
| `_compare_versions` | `($1: v1, $2: v2) → return 0/1/2/3` | Compare two version strings; returns 0=equal, 1=v1 newer, 2=v2 newer, 3=error |
| `_save_version` | `($1: version) → return 0/1` | Write the version string to `$instance_version_file` |

**Download and Deployment**

| Function | Signature | Purpose |
|---|---|---|
| `_download` | `($1: version, $2: dest=instance_temp_dir, $3: variant) → return 0/1` | Download and extract server files into the temp directory |
| `_deploy` | `($1: source=instance_temp_dir, $2: dest=instance_install_dir) → return 0/1` | Move files from the temp directory to the installation directory |
| `_update` | `() → return 0/1` | Orchestrate the full version-check → download → deploy → save-version cycle |

**Server Control**

| Function | Signature | Purpose |
|---|---|---|
| `_start` | `() → (exec, no return)` | Start the server in the foreground (current terminal) |
| `_start_background` | `() → return 0/1` | Start the server as a detached background process |
| `_kill_all_processes` | `() → return 0/1` | Force-kill all server processes |
| `_stop_server` | `() → return 0/1` | Gracefully stop the server, falling back to force-kill |
| `_send_save_command` | `() → return 0/1` | Send the in-game save command via `$instance_save_command` |
| `_send_input` | `($1: input) → return 0/1` | Send arbitrary input to the server's stdin socket |
| `_is_active` | `() → return 0/1` | Check whether the server process is currently running |

**Port Management**

| Function | Signature | Purpose |
|---|---|---|
| `_enable_upnp` | `() → return 0/1` | Register UPnP port mappings for `$instance_upnp_ports` |
| `_disable_upnp` | `() → return 0/1` | Remove UPnP port mappings |

**Log Management**

| Function | Signature | Purpose |
|---|---|---|
| `_print_logs` | `() → return 0/1` | Print recent server log output |
| `_rotate_logs` | `() → return 0/1` | Rotate log files to prevent unbounded growth |

**Backup Management**

| Function | Signature | Purpose |
|---|---|---|
| `_create_backup` | `() → return 0/1` | Create a timestamped backup of the saves directory |
| `_list_backups` | `() → return 0/1` | List available backups for this instance |
| `_restore_backup` | `($1: backup_name) → return 0/1` | Restore a named backup to the saves directory |
| `_clean_old_backups` | `() → return 0/1` | Delete backups beyond the configured retention limit |

> [!TIP]
> Every function above is fully documented with usage examples in `templates/overrides.tp`. Use it as your primary implementation reference.

### Available Variables

Override functions have access to all instance and global configuration variables. These are set before the override is sourced.

**Basic Instance Information**

| Variable | Description |
|---|---|
| `$instance_name` | Name of the instance |
| `$instance_blueprint_file` | Path to the blueprint file |
| `$instance_install_datetime` | Timestamp of when the instance was installed |

**Directory and File Paths**

| Variable | Description |
|---|---|
| `$instance_working_dir` | Working directory for the instance |
| `$instance_install_dir` | Directory where the server binary is installed |
| `$instance_saves_dir` | Directory for save files |
| `$instance_temp_dir` | Temporary directory for downloads and processing |
| `$instance_backups_dir` | Directory for backups |
| `$instance_logs_dir` | Directory for server logs |
| `$instance_launch_dir` | Directory from which to launch the server (may differ from install dir) |
| `$instance_executable_subdirectory` | Subdirectory within install dir containing the executable |
| `$instance_management_file` | Path to the generated management script |
| `$instance_compose_file` | Path to the docker-compose file (container instances only) |

**Process Management Files**

| Variable | Description |
|---|---|
| `$instance_version_file` | Path to the file storing the installed version |
| `$instance_pid_file` | Path to the PID file tracking the server process |
| `$instance_tail_pid_file` | Path to the PID file for the log-tail process |
| `$instance_socket_file` | Path to the socket file used for sending commands |

**Runtime Configuration**

| Variable | Description |
|---|---|
| `$instance_lifecycle_manager` | How the instance is managed: `standalone` or `systemd` |
| `$instance_runtime` | Runtime type: `native` or `container` |
| `$instance_platform` | SteamCMD platform string (default: `linux`) |
| `$instance_auto_update` | Whether to auto-update before starting (`true`/`false`) |
| `$instance_logs_redirect` | Log redirection pattern |

**Game Server Configuration**

| Variable | Description |
|---|---|
| `$instance_level_name` | Name of the level or world |
| `$instance_executable_file` | Path to the server executable |
| `$instance_executable_arguments` | Command-line arguments passed to the executable |

**Steam Integration**

| Variable | Description |
|---|---|
| `$instance_steam_app_id` | Steam App ID (Steam-based games only) |
| `$instance_is_steam_account_required` | Whether a Steam account is required (`true`/`false`) |

**Network Configuration**

| Variable | Description |
|---|---|
| `$instance_ports` | Network ports in UFW format |
| `$instance_enable_port_forwarding` | Whether UPnP port forwarding is enabled (`true`/`false`) |
| `$instance_upnp_ports` | Array of ports to register with UPnP |
| `$instance_enable_firewall_management` | Whether firewall (UFW) management is enabled (`true`/`false`) |
| `$instance_firewall_rule_file` | Path to the UFW rule file |

**Server Control**

| Variable | Description |
|---|---|
| `$instance_stop_command` | In-game command to gracefully stop the server |
| `$instance_save_command` | In-game command to trigger a game save |
| `$instance_save_command_timeout_seconds` | Seconds to wait after sending the save command |
| `$instance_stop_command_timeout_seconds` | Seconds to wait for graceful shutdown before force-killing |

**Backup Configuration**

| Variable | Description |
|---|---|
| `$instance_compress_backups` | Whether to compress backup archives (`true`/`false`) |

**System Integration**

| Variable | Description |
|---|---|
| `$instance_enable_systemd` | Whether systemd integration is enabled for this instance (`true`/`false`) |
| `$instance_systemd_service_file` | Path to the systemd service file |
| `$instance_systemd_socket_file` | Path to the systemd socket file |
| `$instance_enable_command_shortcuts` | Whether command shortcuts are enabled (`true`/`false`) |
| `$instance_command_shortcut_file` | Path to the command shortcut file |

**Global Configuration Variables**

These come from the KGSM config file and apply across all instances:

| Variable | Description |
|---|---|
| `$config_wget_timeout_seconds` | Timeout for `wget` operations (default: `60`) |
| `$config_webhook_timeout_seconds` | Timeout for webhook HTTP requests (default: `10`) |
| `$config_save_command_timeout_seconds` | Default timeout for save commands (default: `5`) |
| `$config_stop_command_timeout_seconds` | Default timeout for stop commands (default: `30`) |
| `$config_enable_logging` | Whether file logging is enabled (`true`/`false`) |
| `$config_enable_systemd` | Whether systemd is enabled globally (`true`/`false`) |
| `$config_enable_firewall_management` | Whether firewall management is enabled globally (`true`/`false`) |
| `$config_enable_port_forwarding` | Whether UPnP port forwarding is enabled globally (`true`/`false`) |
| `$config_enable_backup_compression` | Whether backup compression is enabled globally (`true`/`false`) |

### Blueprint-Override Linking

Overrides are linked to blueprints through the **`name` field extracted from the blueprint**, not the blueprint filename. For a complete explanation of blueprints, see [Blueprints 101](blueprints.md).

#### Native Blueprints

For `.bp` files, KGSM reads the `name=` variable directly:

```ini
# blueprints/native/custom/factorio-experimental.bp
name=factorio
```

→ loads `overrides/factorio.overrides.sh`

#### Container Blueprints

For `.docker-compose.yml` files, there is no `name=` field. Instead, KGSM uses the **first service name** listed under the `services:` key:

```yaml
# blueprints/container/custom/valheim.docker-compose.yml
services:
  valheim:   # ← this name is used
    image: ...
```

→ loads `overrides/valheim.overrides.sh`

> [!IMPORTANT]
> The override file name is derived from the blueprint's logical name (the `name=` field for native blueprints, the first service name for container blueprints), **not** the blueprint filename. If the naming convention is not followed, KGSM will not find the override script.

#### Example: Multiple Blueprint Variants

Multiple blueprint files for the same game can all share one override file by using the same `name` value:

```
blueprints/native/custom/terraria-vanilla.bp    (name=terraria) → overrides/terraria.overrides.sh
blueprints/native/custom/terraria-modded.bp     (name=terraria) → overrides/terraria.overrides.sh
blueprints/native/custom/terraria-hardcore.bp   (name=terraria) → overrides/terraria.overrides.sh
```

All three blueprint variants use the same `terraria.overrides.sh`, ensuring consistent installation and update logic across configurations.

## Design Decision: Name-Based Matching

KGSM uses name-based matching (matching overrides to the blueprint's `name` variable) rather than file-based matching (matching overrides to the blueprint filename). This design decision was made after careful consideration of both approaches.

### Why Name-Based Matching Was Chosen

The name-based approach was selected because it better supports KGSM's goal of providing a flexible, maintainable system for managing diverse game server configurations. Here's why:

1. **Real-World Usage**: Most users will have multiple variants of the same game (vanilla, modded, hardcore, etc.) that share the same core logic
2. **Maintenance Efficiency**: Critical bug fixes and improvements only need to be made once
3. **Logical Grouping**: The `name` field represents the core game identity, which is what the override logic should be based on
4. **Future-Proof**: Supports complex scenarios that will become more common as KGSM grows

### Comparison: Name-Based vs File-Based Matching

#### Name-Based Matching (Current Approach)
**How it works:** `terraria-vanilla.bp` (name=terraria) → `terraria.overrides.sh`

**Pros:**
- **DRY principle**: Single override file serves multiple blueprint variants
- **Easier maintenance**: One place to update logic for all variants
- **Consistent behavior**: All variants guaranteed to use the same override logic
- **Flexible naming**: Blueprint files can have descriptive names without affecting override matching
- **Better scalability**: Supports complex scenarios like modded variants, different game modes, etc.

**Cons:**
- Less obvious relationship between blueprint files and overrides
- Potential confusion for users expecting file-based matching
- Hidden dependencies where override changes affect multiple blueprints
- Slightly more complex debugging (need to check blueprint's `name` field)

#### File-Based Matching (Alternative Approach)
**How it would work:** `terraria-vanilla.bp` → `terraria-vanilla.overrides.sh`

**Pros:**
- Simple and intuitive 1:1 mapping
- Clear file organization
- No ambiguity about which override belongs to which blueprint
- Easy debugging and troubleshooting

**Cons:**
- Code duplication across multiple similar blueprints
- Maintenance overhead - changes must be replicated across multiple files
- Risk of inconsistent behavior as override files diverge over time
- Storage inefficiency with redundant files

### Best Practices for Name-Based Matching

- **Use descriptive blueprint filenames**: `terraria-vanilla.bp`, `terraria-modded.bp`, `terraria-hardcore.bp`
- **Keep blueprint names consistent**: All variants should use the same `name=terraria` value
- **Document override dependencies**: Add comments in override files explaining which blueprint variants use them
- **Test all variants**: When modifying an override, test all blueprint variants that use it

## Creating Overrides

### Getting Started

To create a new override script:

1. Copy `templates/overrides.tp` to a new file in the user overrides directory:
   ```
   ~/.local/share/kgsm/overrides/{blueprint_name}.overrides.sh
   ```
   Where `{blueprint_name}` is the value of the `name=` field in your blueprint.
2. Review the template to understand all available functions and their purposes.
3. Uncomment and implement only the functions you need to customize — any function not defined in your override will use the default implementation.

> [!TIP]
> The `templates/overrides.tp` file contains comprehensive documentation for each function, including detailed input/output specifications, implementation examples, and best practices. Use it as your primary reference when implementing override functions.

### Real-World Example: Factorio

The bundled `overrides/factorio.overrides.sh` demonstrates the three most commonly overridden functions for a non-Steam game:

**`_get_latest_version`** — queries the Factorio REST API and returns the stable headless version:

```bash
function _get_latest_version() {
  local timeout="${config_wget_timeout_seconds:-60}"
  wget --timeout="$timeout" -qO - 'https://factorio.com/api/latest-releases' |
    jq .stable.headless |
    tr -d '"'
}
```

**`_download`** — downloads and extracts the tarball into `$instance_temp_dir`:

```bash
function _download() {
  local version=$1
  local dest=$instance_temp_dir

  local download_url="https://factorio.com/get-download/${version}/headless/linux64"
  local dest_file="$dest/factorio_headless.tar.xz"
  local timeout="${config_wget_timeout_seconds:-60}"

  if ! wget --timeout="$timeout" -qO "$dest_file" "$download_url"; then
    __print_error "wget --timeout=$timeout -qO $dest_file $download_url"
    return 1
  fi

  if ! tar -xf "$dest_file" --strip-components=1 -C "$dest" >/dev/null 2>&1; then
    __print_error "tar -xf $dest_file --strip-components=1 -C $dest"
    return 1
  fi

  rm "$dest_file"
  return 0
}
```

**`_deploy`** — copies extracted files to `$instance_install_dir` and creates a required initial save file:

```bash
function _deploy() {
  local source=$instance_temp_dir
  local dest=$instance_install_dir

  if ! cp -r "$source"/* "$dest"; then
    __print_error "Failed copy contents from $source into $dest"
    return 1
  fi

  rm -rf "${source:?}"/*

  # Factorio requires a save file to exist at startup
  if [[ ! -f "$instance_saves_dir/$instance_level_name" ]]; then
    cd "$instance_install_dir/bin/x64" || return 1
    if ! "$instance_executable_file" --create "$instance_saves_dir/$instance_level_name" &>/dev/null; then
      __print_error "Failed to create savefile $instance_level_name"
      return 1
    fi
  fi

  return 0
}
```

### Error Handling

Override functions should follow KGSM's error handling conventions:

- **Return codes**: Use `return 0` for success and `return 1` for failure
- **Error messages**: Use `__print_error` for error messages, `__print_warning` for non-fatal issues, and `__print_info` for informational output
- **Validation**: Always validate inputs and check for required files/directories before proceeding
- **Cleanup**: If your function fails partway through, clean up any partial changes (e.g., partially extracted archives in `$instance_temp_dir`)

> [!TIP]
> For detailed error handling examples and best practices, see the "IMPORTANT GUIDELINES" section in `templates/overrides.tp`. The template provides extensive guidance on writing robust, production-ready override functions.

## Best Practices and Guidelines

### Core Principles

- **Keep it Simple:** Only implement the necessary functions for the game server's unique requirements.
- **Test Thoroughly:** Ensure the override functions work as intended by testing installation, updates, and deployments.
- **Document Changes:** Add comments in the override file to explain any custom behavior for future reference.
- **Follow Naming Conventions:** Always use the underscore prefix (`_`) for override function names.
- **Validate Inputs:** Always check that required parameters and files exist before proceeding.
- **Handle Errors Gracefully:** Use proper error handling and cleanup in case of failures.
- **Use KGSM Functions:** Leverage KGSM's built-in functions like `__print_info`, `__print_error`, `__print_warning`, and `__print_success` for consistent messaging.
- **Prefer user overrides:** Place custom overrides in `~/.local/share/kgsm/overrides/` rather than editing files under `$KGSM_ROOT/overrides/`, so they are not overwritten by system updates.

### File Permissions

Override files are sourced by KGSM and do not require execution permissions. Ensure the file has read permissions:

```bash
chmod 644 ~/.local/share/kgsm/overrides/mygame.overrides.sh
```

---

By using overrides effectively, you can extend KGSM's functionality to support a wide variety of game servers while maintaining the integrity of its core scripts.
