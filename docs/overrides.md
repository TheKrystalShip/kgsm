# Overrides 101

This document explains what overrides are, how they work in KGSM, and how to create and use them effectively to customize game server management.

## Table of Contents

- [What are Overrides?](#what-are-overrides)
  - [Common Use Cases](#common-use-cases)
- [How Overrides Work](#how-overrides-work)
  - [Override Search Order](#override-search-order)
- [Override System Components](#override-system-components)
  - [Overridable Modules](#overridable-modules)
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
- [Migrating from Legacy Overrides](#migrating-from-legacy-overrides)
- [Best Practices and Guidelines](#best-practices-and-guidelines)
  - [Core Principles](#core-principles)
  - [File Permissions](#file-permissions)

## What are Overrides?

Overrides are game-specific module files that replace one or more numbered default modules during management script assembly. They serve several important purposes:

- **Enable support for diverse game servers**: Particularly useful for non-Steam games that require custom installation, update, or runtime handling
- **Keep KGSM's core modular**: By externalizing game-specific code, the main codebase remains clean and maintainable
- **Provide flexibility**: Replace only the modules that need to differ, leaving everything else as the default

### Common Use Cases

Overrides are typically used for:
- Creating custom version-checking for games with unique versioning systems
- Implementing specialized download procedures for games not available through Steam
- Adding unique startup/shutdown sequences for games with special requirements
- Developing custom backup and restoration logic for complex game data structures

## How Overrides Work

When KGSM assembles a management script for a new instance, it concatenates numbered module files in order. For each overridable module (03–11) it checks the override search directories first. If a matching module exists there, it is used instead of the default.

The assembly process for a native instance:

1. KGSM reads the `name=` field from the instance's blueprint file.
2. For each numbered module (00–13), KGSM calls `__resolve_module`:
   - For modules 00–02 and 12–13: always use the default template module.
   - For modules 03–11: search override directories for `{name}/{module}.sh`; if found, use the override; otherwise fall back to the default template module.
3. The resolved modules are concatenated in order into a single self-contained management script.

This means override modules are **complete module files** — copies of the default module with only the specific functions changed. All functions from the default module must be present.

### Override Search Order

KGSM searches for override modules in the following order, using the **first match found**:

1. **User overrides directory** (XDG-compliant, writable):
   `${XDG_DATA_HOME:-$HOME/.local/share}/kgsm/overrides/{blueprint_name}/`
2. **System overrides directory** (shipped with KGSM):
   `${KGSM_ROOT}/overrides/{blueprint_name}/`
3. **Default template modules** (fallback):
   `${KGSM_ROOT}/templates/manage.{runtime}.d/`

User-defined overrides always take precedence over system overrides. To customize a bundled game (such as Factorio or Terraria) without modifying system files, place your override directory under the user overrides path.

## Override System Components

### Overridable Modules

Only modules 03–11 may be overridden. The module filenames and their responsibilities are:

| Module | Filename | Responsibility |
|--------|----------|----------------|
| 03 | `03-lifecycle.sh` | Server start/stop/restart logic |
| 04 | `04-io.sh` | Input/output helpers (send input, send save command) |
| 05 | `05-version.sh` | Version retrieval and comparison |
| 06 | `06-download.sh` | File download from remote sources |
| 07 | `07-deploy.sh` | File deployment from temp dir to install dir |
| 08 | `08-backup.sh` | Backup creation, listing, and restoration |
| 09 | `09-network.sh` | UPnP port management |
| 10 | `10-logging.sh` | Log printing and rotation |
| 11 | `11-status.sh` | Server status reporting |

Modules 00–02 (`00-header.sh`, `01-config.sh`, `02-help.sh`) and 12–13 (`12-commands.sh`, `13-dispatch.sh`) are structural and cannot be overridden.

### Available Functions

The following functions are defined across the overridable modules. Override the module that contains the functions you need to customize:

**Version Management** (module `05-version.sh`)

| Function | Signature | Purpose |
|---|---|---|
| `_get_latest_version` | `() → echo "$version"` | Query remote source for the latest available version |
| `_get_installed_version` | `() → echo "$version"` | Read the currently installed version from `$instance_version_file` |
| `_compare_versions` | `($1: v1, $2: v2) → return 0/1/2/3` | Compare two version strings; returns 0=equal, 1=v1 newer, 2=v2 newer, 3=error |
| `_save_version` | `($1: version) → return 0/1` | Write the version string to `$instance_version_file` |

**Download and Deployment** (modules `06-download.sh`, `07-deploy.sh`)

| Function | Signature | Purpose |
|---|---|---|
| `_download` | `($1: version, $2: dest=instance_temp_dir) → return 0/1` | Download and extract server files into the temp directory |
| `_deploy` | `() → return 0/1` | Move files from the temp directory to the installation directory |
| `_update` | `() → return 0/1` | Orchestrate the full version-check → download → deploy → save-version cycle |

**Server Control** (module `03-lifecycle.sh`)

| Function | Signature | Purpose |
|---|---|---|
| `_start` | `() → (exec, no return)` | Start the server in the foreground (current terminal) |
| `_start_background` | `() → return 0/1` | Start the server as a detached background process |
| `_stop_server` | `() → return 0/1` | Gracefully stop the server, falling back to force-kill |

**I/O** (module `04-io.sh`)

| Function | Signature | Purpose |
|---|---|---|
| `_send_save_command` | `() → return 0/1` | Send the in-game save command via `$instance_save_command` |
| `_send_input` | `($1: input) → return 0/1` | Send arbitrary input to the server's stdin socket |
| `_is_active` | `() → return 0/1` | Check whether the server process is currently running |

**Port Management** (module `09-network.sh`)

| Function | Signature | Purpose |
|---|---|---|
| `_enable_upnp` | `() → return 0/1` | Register UPnP port mappings for `$instance_upnp_ports` |
| `_disable_upnp` | `() → return 0/1` | Remove UPnP port mappings |

**Log Management** (module `10-logging.sh`)

| Function | Signature | Purpose |
|---|---|---|
| `_print_logs` | `() → return 0/1` | Print recent server log output |
| `_rotate_logs` | `() → return 0/1` | Rotate log files to prevent unbounded growth |

**Backup Management** (module `08-backup.sh`)

| Function | Signature | Purpose |
|---|---|---|
| `_create_backup` | `() → return 0/1` | Create a timestamped backup of the saves directory |
| `_list_backups` | `() → return 0/1` | List available backups for this instance |
| `_restore_backup` | `($1: backup_name) → return 0/1` | Restore a named backup to the saves directory |
| `_clean_old_backups` | `() → return 0/1` | Delete backups beyond the configured retention limit |

> [!TIP]
> The default implementations of every function above live in `templates/manage.native.d/` (or `manage.container.d/` for container runtimes). Use those files as your starting point when creating overrides.

### Available Variables

Override functions have access to all instance and global configuration variables. These are set before the management script runs.

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
| `$config_enable_firewall_management` | Whether firewall management is enabled globally (`true`/`false`) |
| `$config_enable_port_forwarding` | Whether UPnP port forwarding is enabled globally (`true`/`false`) |
| `$config_enable_backup_compression` | Whether backup compression is enabled globally (`true`/`false`) |

### Blueprint-Override Linking

Overrides are linked to blueprints through the **`name` field of the blueprint**, not the blueprint filename. This holds for **both** runtimes — the unified `.bp.yaml` format gives every blueprint, container included, an explicit `name`. For a complete explanation of blueprints, see [Blueprints 101](blueprints.md).

KGSM reads the top-level `name` field (via yq) regardless of runtime:

```yaml
# blueprints/factorio-experimental.bp.yaml
name: factorio
runtime: native
```

→ override directory consulted: `overrides/factorio/`

```yaml
# blueprints/valheim.bp.yaml
name: valheim
runtime: container
container:
  compose: |
    services:
      valheim:
        image: ...
```

→ override directory consulted: `overrides/valheim/`

> [!IMPORTANT]
> The override directory name is derived from the blueprint's `name` field, **not** the blueprint filename and **not** (for containers) the first service name in the compose — that older container heuristic is gone. If the naming convention is not followed, KGSM will not find the override modules.

#### Example: Multiple Blueprint Variants

Multiple blueprint files for the same game can all share one override directory by using the same `name` value:

```
blueprints/terraria-vanilla.bp.yaml    (name: terraria) → overrides/terraria/
blueprints/terraria-modded.bp.yaml     (name: terraria) → overrides/terraria/
blueprints/terraria-hardcore.bp.yaml   (name: terraria) → overrides/terraria/
```

All three blueprint variants use the same `terraria/` override directory, ensuring consistent installation and update logic across configurations.

## Design Decision: Name-Based Matching

KGSM uses name-based matching (matching override directories to the blueprint's `name` variable) rather than file-based matching (matching overrides to the blueprint filename). This design decision was made after careful consideration of both approaches.

### Why Name-Based Matching Was Chosen

The name-based approach was selected because it better supports KGSM's goal of providing a flexible, maintainable system for managing diverse game server configurations. Here's why:

1. **Real-World Usage**: Most users will have multiple variants of the same game (vanilla, modded, hardcore, etc.) that share the same core logic
2. **Maintenance Efficiency**: Critical bug fixes and improvements only need to be made once
3. **Logical Grouping**: The `name` field represents the core game identity, which is what the override logic should be based on
4. **Future-Proof**: Supports complex scenarios that will become more common as KGSM grows

### Comparison: Name-Based vs File-Based Matching

#### Name-Based Matching (Current Approach)
**How it works:** `terraria-vanilla.bp.yaml` (name: terraria) → `overrides/terraria/`

**Pros:**
- **DRY principle**: Single override directory serves multiple blueprint variants
- **Easier maintenance**: One place to update logic for all variants
- **Consistent behavior**: All variants guaranteed to use the same override logic
- **Flexible naming**: Blueprint files can have descriptive names without affecting override matching

**Cons:**
- Less obvious relationship between blueprint files and overrides
- Potential confusion for users expecting file-based matching

#### File-Based Matching (Alternative Approach)
**How it would work:** `terraria-vanilla.bp.yaml` → `overrides/terraria-vanilla/`

**Pros:**
- Simple and intuitive 1:1 mapping
- No ambiguity about which override belongs to which blueprint

**Cons:**
- Code duplication across multiple similar blueprints
- Maintenance overhead — changes must be replicated across multiple files

### Best Practices for Name-Based Matching

- **Use descriptive blueprint filenames**: `terraria-vanilla.bp.yaml`, `terraria-modded.bp.yaml`, `terraria-hardcore.bp.yaml`
- **Keep blueprint names consistent**: All variants should use the same `name: terraria` value
- **Document override dependencies**: Add comments in override modules explaining which blueprint variants use them
- **Test all variants**: When modifying an override, test all blueprint variants that use it

## Creating Overrides

### Getting Started

To create a new override for a game:

1. Identify which module(s) you need to override (see [Overridable Modules](#overridable-modules)).

2. Create the override directory (prefer the user directory so updates do not overwrite it):
   ```bash
   mkdir -p ~/.local/share/kgsm/overrides/{blueprint_name}/
   ```
   Where `{blueprint_name}` is the value of the `name=` field in your blueprint.

3. Copy the default module you want to customize:
   ```bash
   # For native servers:
   cp "$KGSM_ROOT/templates/manage.native.d/05-version.sh" \
      ~/.local/share/kgsm/overrides/{blueprint_name}/05-version.sh

   # For container servers:
   cp "$KGSM_ROOT/templates/manage.container.d/05-version.sh" \
      ~/.local/share/kgsm/overrides/{blueprint_name}/05-version.sh
   ```

4. Edit the copied module and modify **only** the functions that need game-specific logic. Keep all other functions exactly as they are in the default module.

5. Verify the file parses cleanly:
   ```bash
   bash -n ~/.local/share/kgsm/overrides/{blueprint_name}/05-version.sh
   ```

6. Create a new instance from your blueprint to test the override.

> [!TIP]
> The default module files in `templates/manage.native.d/` contain the complete, working implementations of every function. Use them as your authoritative reference when implementing custom logic.

> [!NOTE]
> Override modules must contain **all** functions from the default module, not just the ones being changed. This ensures the assembled management script is always complete.

### Real-World Example: Factorio

The bundled `overrides/factorio/` directory demonstrates how three modules are customized for a non-Steam game.

#### `overrides/factorio/05-version.sh`

Only `_get_latest_version` differs from the default — it queries the Factorio REST API instead of using SteamCMD:

```bash
function _get_latest_version() {
  local timeout="${instance_wget_timeout_seconds:-60}"
  wget --timeout="$timeout" -qO - 'https://factorio.com/api/latest-releases' |
    jq .stable.headless |
    tr -d '"'
}
```

All other functions (`_get_installed_version`, `_compare_versions`, `_save_version`) are kept verbatim from `templates/manage.native.d/05-version.sh`.

#### `overrides/factorio/06-download.sh`

Only `_download` differs — it fetches a versioned `.tar.xz` archive from Factorio's CDN:

```bash
function _download() {
  # shellcheck disable=SC2034
  local version=$1
  local dest=${2:-$instance_temp_dir}

  local download_url="https://factorio.com/get-download/${version}/headless/linux64"
  local dest_file="$dest/factorio_headless.tar.xz"
  local timeout="${instance_wget_timeout_seconds:-60}"

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

#### `overrides/factorio/07-deploy.sh`

Only `_deploy` differs — after copying files it creates a Factorio save file if one does not already exist:

```bash
function _deploy() {
  local source=$instance_temp_dir
  local dest=$instance_install_dir

  if [[ -z "$(ls -A "$source")" ]]; then
    __print_error "$source is empty, nothing to deploy."
    return $EC_ERROR
  fi

  if ! cp -r "$source"/* "$dest"; then
    __print_error "Failed to copy contents from $source into $dest"
    return $EC_ERROR
  fi

  if ! rm -rf "${source:?}"/*; then
    __print_warning "Failed to clear $source, continuing..."
  fi

  # Factorio requires a save file to exist at startup
  if [[ ! -f "$instance_saves_dir/$instance_level_name" ]]; then
    cd "$instance_install_dir/bin/x64" || return 1
    if ! "$instance_executable_file" --create \
         "$instance_saves_dir/$instance_level_name" &>/dev/null; then
      __print_error "Failed to create savefile $instance_level_name"
      return $EC_ERROR
    fi
  fi

  return $EC_SUCCESS
}
```

### Error Handling

Override functions should follow KGSM's error handling conventions:

- **Return codes**: Use `return $EC_SUCCESS` (0) for success and `return $EC_ERROR` for failure
- **Error messages**: Use `__print_error` for errors, `__print_warning` for non-fatal issues, and `__print_info` for informational output
- **Validation**: Always validate inputs and check for required files/directories before proceeding
- **Cleanup**: If your function fails partway through, clean up any partial changes (e.g., partially extracted archives in `$instance_temp_dir`)

## Migrating from Legacy Overrides

Prior to the module-based system, overrides were single files named `{blueprint_name}.overrides.sh`. These legacy files are no longer supported for management script assembly.

To migrate a legacy override file:

1. **Identify which functions were overridden** in the legacy `.overrides.sh` file.
2. **Determine which module(s)** contain those functions (see [Overridable Modules](#overridable-modules)).
3. **Copy the default module** for each affected module.
4. **Port the function bodies** from the legacy file into the corresponding module files, keeping all other functions from the defaults.
5. **Verify** each module parses cleanly with `bash -n`.

Example: if your legacy `mygame.overrides.sh` only overrode `_get_latest_version` and `_download`:

```bash
mkdir -p ~/.local/share/kgsm/overrides/mygame/

# Module 05 for _get_latest_version
cp "$KGSM_ROOT/templates/manage.native.d/05-version.sh" \
   ~/.local/share/kgsm/overrides/mygame/05-version.sh
# Edit 05-version.sh: replace _get_latest_version body with your custom logic

# Module 06 for _download
cp "$KGSM_ROOT/templates/manage.native.d/06-download.sh" \
   ~/.local/share/kgsm/overrides/mygame/06-download.sh
# Edit 06-download.sh: replace _download body with your custom logic
```

## Best Practices and Guidelines

### Core Principles

- **Copy, then modify**: Start from a copy of the default module, change only what is necessary.
- **Preserve all functions**: Every function from the default module must exist in your override module.
- **Keep it Simple**: Override only the modules that absolutely require game-specific logic.
- **Test Thoroughly**: Verify both the module parses (`bash -n`) and the resulting instance works end-to-end.
- **Document Changes**: Add comments explaining what was changed and why.
- **Follow Naming Conventions**: Private helper functions should use the `__override_` prefix.
- **Validate Inputs**: Always check that required parameters and files exist before proceeding.
- **Handle Errors Gracefully**: Use proper error handling and cleanup in case of failures.
- **Use KGSM Functions**: Use `__print_info`, `__print_error`, `__print_warning`, and `__print_success` for consistent messaging.
- **Prefer user overrides**: Place custom overrides in `~/.local/share/kgsm/overrides/` rather than editing files under `$KGSM_ROOT/overrides/`, so they are not overwritten by system updates.

### File Permissions

Override module files must be readable by the user running KGSM:

```bash
chmod 644 ~/.local/share/kgsm/overrides/mygame/05-version.sh
```

---

By using module-based overrides effectively, you can extend KGSM's functionality to support a wide variety of game servers while maintaining the integrity of its core scripts.
