# KGSM Installation Stage Tracking Specification

**Version**: 1.0  
**Date**: February 7, 2026  
**Status**: Draft  
**Target Release**: KGSM v3.x

---

## Table of Contents

1. [Overview](#overview)
2. [Design Goals](#design-goals)
3. [Current State Analysis](#current-state-analysis)
4. [Installation Stages](#installation-stages)
5. [State File Specification](#state-file-specification)
6. [Handler Module API](#handler-module-api)
7. [Command-Line Interface](#command-line-interface)
8. [Error Codes](#error-codes)
9. [Integration with Existing Modules](#integration-with-existing-modules)
10. [User Experience Flow](#user-experience-flow)
11. [Testing Requirements](#testing-requirements)
12. [Implementation Phases](#implementation-phases)
13. [Files to Create/Modify](#files-to-createmodify)

---

## Overview

This specification defines an installation stage tracking system (checkpoint system) for KGSM game server instance installations. The system tracks progress through discrete installation stages, enabling recovery from failures without requiring full reinstallation.

### Problem Statement

Current KGSM installation process has significant issues:
- **No progress tracking**: Installation failures leave partial state with no record of progress
- **No recovery path**: Users must manually delete orphaned files or run full uninstall
- **Wasted resources**: Large downloads (often GBs) are discarded on later-stage failures
- **Poor developer experience**: Testing installation changes requires repeated full reinstalls
- **Ambiguous state**: No way to distinguish partial installations from complete ones

### Solution

Implement a **checkpoint-based installation tracking system** with:
- State file tracking completed installation stages
- `--resume` flag to continue failed installations
- Clear error messages indicating failure stage and recovery commands
- Blueprint hash validation to detect configuration changes
- Integration with existing command/handler architecture

---

## Design Goals

1. **Resumable Installations**: Failed installations can continue from last successful stage
2. **Explicit Recovery**: Users must explicitly opt-in via `--resume` flag (no silent auto-resume)
3. **Clear Diagnostics**: Error messages show exact failure stage and recovery commands
4. **Preserve Standalone Modules**: Checkpoint system is additive; manual module calls still work
5. **Follow Existing Patterns**: Use handler module pattern, state file conventions (`.version`, `.pid`)
6. **Clean Success State**: Completed installations leave no checkpoint artifacts
7. **Configuration Validation**: Detect blueprint changes between partial install and resume attempt

---

## Current State Analysis

### Existing Installation Flow

The installation process in `commands/install.sh` executes these steps sequentially:

| Step | Module                             | Description                             | Artifacts Created                                              |
| ---- | ---------------------------------- | --------------------------------------- | -------------------------------------------------------------- |
| 1    | `directories.sh ensure-created`    | Ensure install directory exists         | Base install directory                                         |
| 2    | `instances.sh create`              | Create instance config file             | `<instance>.config.ini`                                        |
| 3    | `directories.sh create`            | Create directory structure              | `working/`, `install/`, `saves/`, `temp/`, `backups/`, `logs/` |
| 4    | `files.sh create`                  | Create management script + integrations | `<instance>.manage.sh`, systemd/ufw files                      |
| 5    | `management_file --download`       | Download game files                     | Files in `temp/`                                               |
| 6    | `management_file --deploy`         | Deploy to install directory             | Files in `install/`                                            |
| 7    | `management_file --version --save` | Save installed version                  | `.version` file                                                |

### Current Error Handling

- **Fail-fast pattern**: Immediate return on error with exit code
- **No cleanup**: Created artifacts remain on failure
- **No rollback**: No mechanism to undo partial work
- **Events emitted**: `server.download.failed`, `server.deploy.failed` etc. (informational only)

### Existing State File Patterns

KGSM already uses state files in instance working directories:
- `.<instance>.version` - Tracks installed version
- `.<instance>.pid` - Tracks running process PID
- `.<instance>.sock` - Named pipe for runtime commands
- `.<instance>.upnp_enabled` - UPnP port forwarding state

The installation state file follows this established convention.

---

## Installation Stages

### Stage Definitions

```bash
INSTALL_STAGE_INIT="INIT"           # Ensure install directory exists
INSTALL_STAGE_CONFIG="CONFIG"       # Create instance configuration
INSTALL_STAGE_DIRECTORIES="DIRECTORIES"  # Create directory structure
INSTALL_STAGE_FILES="FILES"         # Create management script and integrations
INSTALL_STAGE_DOWNLOAD="DOWNLOAD"   # Download game files to temp
INSTALL_STAGE_DEPLOY="DEPLOY"       # Deploy from temp to install
INSTALL_STAGE_VERSION="VERSION"     # Save version information
INSTALL_STAGE_COMPLETE="COMPLETE"   # Installation finished (triggers cleanup)
```

### Stage Order

Stages execute in strict linear order. Each stage depends on all previous stages completing successfully.

```
INIT → CONFIG → DIRECTORIES → FILES → DOWNLOAD → DEPLOY → VERSION → COMPLETE
```

### Stage Validation

Before marking a stage complete, validate its artifacts exist:

| Stage       | Validation                                                                               |
| ----------- | ---------------------------------------------------------------------------------------- |
| INIT        | Install directory exists and is writable                                                 |
| CONFIG      | Instance config file exists                                                              |
| DIRECTORIES | All 6 directories exist (`working/`, `install/`, `saves/`, `temp/`, `backups/`, `logs/`) |
| FILES       | Management script exists and is executable                                               |
| DOWNLOAD    | Files present in `temp/` directory                                                       |
| DEPLOY      | Files present in `install/` directory                                                    |
| VERSION     | `.version` file exists with valid content                                                |
| COMPLETE    | All above validations pass                                                               |

---

## State File Specification

### Location

```
<working_dir>/.<instance_name>.install_state
```

Example:
`/mnt/ssd/kgsm/instances/factorio/factorio-abc123/.factorio-abc123.install_state`

### Format

INI-style format matching KGSM conventions:

```ini
# KGSM Installation State
# Do not edit manually
schema_version=1
instance_name=factorio-abc123
blueprint_file=/home/user/kgsm/blueprints/native/default/factorio.bp
blueprint_hash=a3f2b1c4d5e6f7a8
library_dir=/mnt/ssd/kgsm
version_requested=0
started_at=2026-02-07T14:23:00
last_updated=2026-02-07T14:25:30
current_stage=DOWNLOAD
stages_completed=INIT,CONFIG,DIRECTORIES,FILES
last_error=Connection timeout during download
```

### Field Definitions

| Field               | Type       | Description                                    |
| ------------------- | ---------- | ---------------------------------------------- |
| `schema_version`    | Integer    | State file format version (currently 1)        |
| `instance_name`     | String     | Instance identifier                            |
| `blueprint_file`    | Path       | Absolute path to blueprint used                |
| `blueprint_hash`    | Hex string | MD5 hash of blueprint file contents            |
| `library_dir`       | Path       | Root of the library the instance is placed in  |
| `version_requested` | String     | Version requested (0 = latest)                 |
| `started_at`        | ISO 8601   | Timestamp when installation started            |
| `last_updated`      | ISO 8601   | Timestamp of last state change                 |
| `current_stage`     | Stage      | Stage that was executing when failure occurred |
| `stages_completed`  | CSV        | Comma-separated list of completed stages       |
| `last_error`        | String     | Error message from last failure (optional)     |

### Atomic Writes

State file updates use atomic write pattern:
1. Write to `.<instance>.install_state.tmp`
2. `mv` temp file to final location
3. `sync` to ensure durability

### Lifecycle

1. **Created**: At INIT stage start (before any work)
2. **Updated**: After each stage completes
3. **Removed**: On successful COMPLETE stage (clean install leaves no state file)
4. **Preserved**: On failure (for resume capability)

---

## Handler Module API

### Module Location

`commands/handlers/install.sh`

### Stage Constants

```bash
declare -g -r INSTALL_STAGE_INIT="INIT"
declare -g -r INSTALL_STAGE_CONFIG="CONFIG"
declare -g -r INSTALL_STAGE_DIRECTORIES="DIRECTORIES"
declare -g -r INSTALL_STAGE_FILES="FILES"
declare -g -r INSTALL_STAGE_DOWNLOAD="DOWNLOAD"
declare -g -r INSTALL_STAGE_DEPLOY="DEPLOY"
declare -g -r INSTALL_STAGE_VERSION="VERSION"
declare -g -r INSTALL_STAGE_COMPLETE="COMPLETE"

# Stage order array for iteration
declare -g -r -a INSTALL_STAGES=(
  "$INSTALL_STAGE_INIT"
  "$INSTALL_STAGE_CONFIG"
  "$INSTALL_STAGE_DIRECTORIES"
  "$INSTALL_STAGE_FILES"
  "$INSTALL_STAGE_DOWNLOAD"
  "$INSTALL_STAGE_DEPLOY"
  "$INSTALL_STAGE_VERSION"
  "$INSTALL_STAGE_COMPLETE"
)
```

### Function Reference

#### `__logic_install_state_init`

Create new installation state file.

```bash
# Arguments:
#   $1 - state_file: Path to state file
#   $2 - instance_name: Instance identifier
#   $3 - blueprint_file: Path to blueprint
#   $4 - library_dir: Root of the library the instance is placed in
#   $5 - version_requested: Version to install (0 = latest)
# Returns:
#   EC_SUCCESS on success
#   EC_FAILED_TEMPLATE on write failure
__logic_install_state_init "$state_file" "$instance" "$blueprint" "$library_dir" "$version"
```

#### `__logic_install_state_complete_stage`

Mark a stage as completed.

```bash
# Arguments:
#   $1 - state_file: Path to state file
#   $2 - stage: Stage constant to mark complete
# Returns:
#   EC_SUCCESS on success
#   EC_FILE_NOT_FOUND if state file missing
__logic_install_state_complete_stage "$state_file" "$INSTALL_STAGE_DIRECTORIES"
```

#### `__logic_install_state_get_current`

Get the current/failed stage.

```bash
# Arguments:
#   $1 - state_file: Path to state file
# Output:
#   Echoes stage name (e.g., "DOWNLOAD")
# Returns:
#   EC_SUCCESS on success
#   EC_FILE_NOT_FOUND if state file missing
current=$(__logic_install_state_get_current "$state_file")
```

#### `__logic_install_state_exists`

Check if a partial installation exists.

```bash
# Arguments:
#   $1 - working_dir: Instance working directory
#   $2 - instance_name: Instance identifier
# Returns:
#   EC_SUCCESS (0) if state file exists
#   EC_FILE_NOT_FOUND if no state file
__logic_install_state_exists "$working_dir" "$instance"
```

#### `__logic_install_state_remove`

Remove state file (called on successful completion).

```bash
# Arguments:
#   $1 - state_file: Path to state file
# Returns:
#   EC_SUCCESS on success or if file doesn't exist
__logic_install_state_remove "$state_file"
```

#### `__logic_install_state_validate`

Validate state file integrity and blueprint hash.

```bash
# Arguments:
#   $1 - state_file: Path to state file
#   $2 - blueprint_file: Current blueprint path
# Returns:
#   EC_SUCCESS if valid and hash matches
#   EC_INSTALL_STATE_INVALID if corrupted
#   EC_INSTALL_CONFIG_MISMATCH if blueprint changed
__logic_install_state_validate "$state_file" "$blueprint"
```

#### `__logic_install_state_set_error`

Record error message in state file.

```bash
# Arguments:
#   $1 - state_file: Path to state file
#   $2 - error_message: Error description
# Returns:
#   EC_SUCCESS on success
__logic_install_state_set_error "$state_file" "Connection timeout"
```

#### `__logic_install_should_run_stage`

Determine if a stage should execute (not already completed).

```bash
# Arguments:
#   $1 - state_file: Path to state file
#   $2 - stage: Stage to check
# Returns:
#   EC_SUCCESS (0) if stage should run
#   EC_ERROR (1) if stage already completed
if __logic_install_should_run_stage "$state_file" "$INSTALL_STAGE_DOWNLOAD"; then
  # Run download
fi
```

#### `__logic_install_get_next_stage`

Get the next stage to execute after current completed stages.

```bash
# Arguments:
#   $1 - state_file: Path to state file
# Output:
#   Echoes next stage name
# Returns:
#   EC_SUCCESS on success
next=$(__logic_install_get_next_stage "$state_file")
```

#### `__logic_install_compute_blueprint_hash`

Compute MD5 hash of blueprint file.

```bash
# Arguments:
#   $1 - blueprint_file: Path to blueprint
# Output:
#   Echoes 32-character hex hash
# Returns:
#   EC_SUCCESS on success
#   EC_FILE_NOT_FOUND if blueprint missing
hash=$(__logic_install_compute_blueprint_hash "$blueprint")
```

---

## Command-Line Interface

### Modified `install.sh` Command

```
Usage:
  install.sh <blueprint> [options]

Arguments:
  <blueprint>                 Blueprint name to install from

Options:
  --library <name>            Library to place the instance in (default: the
                              configured default_library, or the sole
                              registered library)
  --version <version>         Specific version to install (default: latest)
  --name <name>               Custom instance name (default: auto-generated)
  --resume                    Resume a partially completed installation
  --force                     Force fresh install (removes any partial state)
  -h, --help                  Display this help information

Examples:
  install.sh factorio
  install.sh factorio --library ssd
  install.sh factorio --resume
  install.sh factorio --force
```

### Behavior Matrix

| State File Exists? | Flag                       | Behavior                                                          |
| ------------------ | -------------------------- | ----------------------------------------------------------------- |
| No                 | (none)                     | Normal fresh install                                              |
| No                 | `--resume`                 | Error: "No partial installation found for blueprint 'X'"          |
| Yes                | (none)                     | Error: "Partial installation detected. Use --resume or uninstall" |
| Yes                | `--resume`                 | Validate state, resume from next incomplete stage                 |
| Yes                | `--resume` (hash mismatch) | Error: "Blueprint changed. Use --force to start fresh"            |
| Yes                | `--force`                  | Remove working directory and state, start fresh install           |

---

## Error Codes

### New Error Codes

Add to `core/errors.sh`:

```bash
# Installation state tracking errors (50-59 range)
declare -g -r EC_PARTIAL_INSTALL=50
export EC_PARTIAL_INSTALL

declare -g -r EC_INSTALL_STATE_INVALID=51
export EC_INSTALL_STATE_INVALID

declare -g -r EC_INSTALL_CONFIG_MISMATCH=52
export EC_INSTALL_CONFIG_MISMATCH

declare -g -r EC_INSTALL_RESUME_FAILED=53
export EC_INSTALL_RESUME_FAILED

declare -g -r EC_NO_PARTIAL_INSTALL=54
export EC_NO_PARTIAL_INSTALL
```

### Error Code Usage

| Code | Constant                     | When Used                                         |
| ---- | ---------------------------- | ------------------------------------------------- |
| 50   | `EC_PARTIAL_INSTALL`         | Partial installation exists, `--resume` required  |
| 51   | `EC_INSTALL_STATE_INVALID`   | State file corrupted or wrong schema version      |
| 52   | `EC_INSTALL_CONFIG_MISMATCH` | Blueprint hash doesn't match state file           |
| 53   | `EC_INSTALL_RESUME_FAILED`   | Resume attempted but required artifacts missing   |
| 54   | `EC_NO_PARTIAL_INSTALL`      | `--resume` used but no partial installation found |

---

## Integration with Existing Modules

### instances.sh

**List command enhancement**:

```bash
$ ./kgsm.sh instances list
factorio-abc123 [PARTIAL: DOWNLOAD]
minecraft-server
valheim-prod
```

Partial installations shown with `[PARTIAL: <stage>]` marker.

**Info command enhancement**:

```bash
$ ./kgsm.sh instances info factorio-abc123
Instance: factorio-abc123
Status: PARTIAL INSTALLATION
Blueprint: factorio
Completed stages: INIT, CONFIG, DIRECTORIES, FILES
Failed at: DOWNLOAD
Started: 2026-02-07T14:23:00
Last error: Connection timeout during download

To resume installation:
  ./kgsm.sh install factorio --resume

To remove and start fresh:
  ./kgsm.sh uninstall factorio-abc123
```

### uninstall.sh

- Include `.install_state` file in cleanup
- Handle partial installations (may have fewer artifacts to clean)
- Consider explicit messaging: "Removing partial installation..."

### Standalone Module Philosophy

**Important**: The checkpoint system does NOT replace standalone module capability.

| Use Case                           | Approach                                                |
| ---------------------------------- | ------------------------------------------------------- |
| Resume failed installation         | `./kgsm.sh install <blueprint> --resume`                |
| Regenerate management file only    | `./kgsm.sh files management create <instance>` (manual) |
| Recreate systemd service           | `./kgsm.sh files systemd enable <instance>` (manual)    |
| Re-download without full reinstall | `<instance>.manage.sh --download <version>` (manual)    |

Standalone modules remain useful for:
- Selective regeneration of specific files
- Advanced troubleshooting
- Custom workflows
- Development/testing of individual components

---

## User Experience Flow

### Scenario: Fresh Installation Success

```
$ ./kgsm.sh install factorio --library ssd

Creating a new instance of factorio in library 'ssd' (/mnt/ssd/kgsm)...
[INIT] Ensuring installation directory exists... done
[CONFIG] Creating instance configuration... done
[DIRECTORIES] Creating directory structure... done
[FILES] Creating management files... done
[DOWNLOAD] Downloading factorio v1.1.100... done
[DEPLOY] Deploying to installation directory... done
[VERSION] Saving version information... done

Instance 'factorio-abc123', version '1.1.100', has been created in '/mnt/ssd/kgsm/instances/factorio/factorio-abc123'
```

No `.install_state` file remains after success.

### Scenario: Installation Failure

```
$ ./kgsm.sh install factorio --library ssd

Creating a new instance of factorio in library 'ssd' (/mnt/ssd/kgsm)...
[INIT] Ensuring installation directory exists... done
[CONFIG] Creating instance configuration... done
[DIRECTORIES] Creating directory structure... done
[FILES] Creating management files... done
[DOWNLOAD] Downloading factorio v1.1.100... failed

Error: Installation failed at stage 'DOWNLOAD'
  Instance: factorio-abc123
  Working directory: /mnt/ssd/kgsm/instances/factorio/factorio-abc123
  Error: Connection timeout during download

To resume installation from this stage:
  ./kgsm.sh install factorio --resume

To remove the partial installation and start fresh:
  ./kgsm.sh uninstall factorio-abc123
```

### Scenario: Resume Installation

```
$ ./kgsm.sh install factorio --resume

Resuming installation of factorio-abc123...
Completed stages: INIT, CONFIG, DIRECTORIES, FILES
Resuming from: DOWNLOAD

[DOWNLOAD] Downloading factorio v1.1.100... done
[DEPLOY] Deploying to installation directory... done
[VERSION] Saving version information... done

Instance 'factorio-abc123', version '1.1.100', has been created in '/mnt/ssd/kgsm/instances/factorio/factorio-abc123'
```

### Scenario: Resume Without Partial Install

```
$ ./kgsm.sh install factorio --resume

Error: No partial installation found for blueprint 'factorio'
To start a fresh installation, run:
  ./kgsm.sh install factorio
```

### Scenario: Blueprint Changed Since Partial Install

```
$ ./kgsm.sh install factorio --resume

Error: Blueprint 'factorio' has changed since partial installation started.
The installation was started with a different blueprint configuration.

To continue with the original configuration:
  This is not supported. You must start fresh.

To start a fresh installation:
  ./kgsm.sh install factorio --force
```

---

## Testing Requirements

### Unit Tests

File: `tests/unit/test_install_handler.sh`

| Test                                        | Description                            |
| ------------------------------------------- | -------------------------------------- |
| `test_state_init_creates_file`              | State file created with correct fields |
| `test_state_init_computes_hash`             | Blueprint hash correctly computed      |
| `test_state_complete_stage_updates_file`    | Stage completion recorded              |
| `test_state_complete_stage_preserves_order` | Stages recorded in execution order     |
| `test_state_get_current_returns_stage`      | Current stage correctly retrieved      |
| `test_state_exists_returns_true`            | Exists check works when file present   |
| `test_state_exists_returns_false`           | Exists check works when file absent    |
| `test_state_remove_deletes_file`            | Removal works correctly                |
| `test_state_validate_accepts_valid`         | Valid state passes validation          |
| `test_state_validate_rejects_corrupted`     | Corrupted state detected               |
| `test_state_validate_detects_hash_mismatch` | Changed blueprint detected             |
| `test_should_run_stage_true_for_incomplete` | Incomplete stages return true          |
| `test_should_run_stage_false_for_complete`  | Completed stages return false          |
| `test_get_next_stage_returns_correct`       | Next stage calculation works           |
| `test_atomic_write_survives_interrupt`      | Atomic write pattern works             |

### Integration Tests

File: `tests/integration/test_install_resume.sh`

| Test                                 | Description                              |
| ------------------------------------ | ---------------------------------------- |
| `test_fresh_install_no_state_file`   | Successful install leaves no state file  |
| `test_failure_at_each_stage`         | Each stage failure leaves correct state  |
| `test_resume_skips_completed_stages` | Resume starts at correct stage           |
| `test_resume_without_state_errors`   | `--resume` without partial install fails |
| `test_force_removes_partial`         | `--force` cleans up and restarts         |
| `test_config_mismatch_detected`      | Changed blueprint blocks resume          |
| `test_instances_list_shows_partial`  | Partial installs marked in list          |
| `test_uninstall_cleans_state_file`   | Uninstall removes state file             |
| `test_resume_after_download_failure` | Download resume works                    |
| `test_resume_after_deploy_failure`   | Deploy resume works                      |

### E2E Tests

File: `tests/e2e/test_install_resume_e2e.sh`

| Test                                | Description                                |
| ----------------------------------- | ------------------------------------------ |
| `test_real_factorio_install_resume` | Full resume flow with real Factorio server |

---

## Implementation Phases

### Phase 1: Core Infrastructure

1. Add error codes to `core/errors.sh`
2. Create `commands/handlers/install.sh` with state file functions
3. Write unit tests for handler functions

### Phase 2: Install Command Integration

1. Modify `commands/install.sh` to track stages
2. Add `--resume` and `--force` flags
3. Implement stage-aware installation flow
4. Write integration tests for resume flow

### Phase 3: Module Integration

1. Update `commands/instances.sh` to show partial install status
2. Update `commands/uninstall.sh` to handle state files
3. Add enhanced error messages with recovery commands

### Phase 4: Testing & Documentation

1. Run full test suite
2. Manual testing of failure scenarios
3. Update user documentation
4. Update developer documentation

---

## Files to Create/Modify

| File                                       | Action     | Description                                        |
| ------------------------------------------ | ---------- | -------------------------------------------------- |
| `commands/handlers/install.sh`             | **Create** | State tracking logic handler                       |
| `commands/install.sh`                      | **Modify** | Add `--resume`/`--force`, integrate state tracking |
| `core/errors.sh`                           | **Modify** | Add 5 new error codes (50-54)                      |
| `commands/uninstall.sh`                    | **Modify** | Clean up state file                                |
| `commands/instances.sh`                    | **Modify** | Show partial install status                        |
| `commands/handlers/instances.sh`           | **Modify** | Logic for partial install detection                |
| `tests/unit/test_install_handler.sh`       | **Create** | Unit tests for handler                             |
| `tests/integration/test_install_resume.sh` | **Create** | Integration tests                                  |
| `tests/e2e/test_install_resume_e2e.sh`     | **Create** | E2E tests                                          |
| `docs/create_new_game_server_instance.md`  | **Modify** | Document `--resume` flag                           |

---

## Open Questions

1. **Multiple partial installs**: Should `--resume` support specifying which partial install to resume if multiple exist for same blueprint?
   - Proposed: Yes, use `--resume --name <instance>` to specify

2. **State file permissions**: Should state file have restricted permissions?
   - Proposed: Match instance config file permissions

3. **Cleanup on `--force`**: Should `--force` also remove downloaded files in temp?
   - Proposed: Yes, full cleanup to ensure clean slate

4. **Event emissions**: Should resume emit different events than fresh install?
   - Proposed: Yes, `instance-installation-resumed` event

---

## Appendix: State File Example

Complete example of state file after DOWNLOAD failure:

```ini
# KGSM Installation State
# Do not edit manually
schema_version=1
instance_name=factorio-abc123
blueprint_file=/home/user/kgsm/blueprints/native/default/factorio.bp
blueprint_hash=a3f2b1c4d5e6f7a8b9c0d1e2f3a4b5c6
library_dir=/mnt/ssd/kgsm
version_requested=0
started_at=2026-02-07T14:23:00
last_updated=2026-02-07T14:25:30
current_stage=DOWNLOAD
stages_completed=INIT,CONFIG,DIRECTORIES,FILES
last_error=Connection timeout: Failed to connect to download server after 30 seconds
```
