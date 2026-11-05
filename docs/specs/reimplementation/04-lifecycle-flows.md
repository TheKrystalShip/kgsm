# 04 — Lifecycle Flows

This document specifies the high-level flows that the parent KGSM tool
orchestrates: install, start, stop, restart, status, update, backup,
restore, and uninstall. Each flow is described as a sequence of steps,
the events it emits, and the failure modes it must surface.

The data model and module APIs referenced here are defined in
[02-data-model.md](02-data-model.md) and
[03-management-script-and-overrides.md](03-management-script-and-overrides.md).
The event names are defined in [05-events.md](05-events.md).

---

## 1. Install (`kgsm install <blueprint> [...]`)

Aliases: `kgsm create <blueprint>`.

### 1.1 Inputs

| Flag                   | Required | Default                            | Meaning                                                                 |
| ---------------------- | -------- | ---------------------------------- | ----------------------------------------------------------------------- |
| `<blueprint>`          | yes      | —                                  | Blueprint name (with or without extension).                             |
| `--library <name>`     | no       | `default_library`, else the sole one | Library the new instance is placed in.                                |
| `--name <id>`          | no       | auto-generated                     | Custom instance identifier.                                             |
| `--version <ver>`      | no       | latest                             | Specific version to install (only meaningful for non-Steam blueprints). |
| `--skip-space-check`   | no       | off                                | Install even when the library has less free room than the blueprint declares the game needs. |

### 1.2 Steps

```
1.  Validate blueprint via find_blueprint + blueprint validation
    (02-data-model.md §2.6, §2.7).
    On failure: EC_BLUEPRINT_NOT_FOUND or EC_INVALID_BLUEPRINT.

2.  Resolve the library: --library, else the configured
    default_library, else the sole registered library.
    With none registered, error naming 'kgsm libraries add <path>'.
    The library must be online — its root present and carrying the
    marker holding its registered id — or EC_LIBRARY_OFFLINE.
    Gate on free space: the blueprint's metadata.base_disk_mb plus
    install_free_space_margin_mb, unless --skip-space-check.

3.  Generate the instance ID:
        if --name was supplied → use it (after uniqueness check)
        else                   → "<blueprint-name>-<NN>", retry until unique
    On exhaustion: EC_ERROR.

4.  Compute working_dir =
        <library-root>/instances/<blueprint-name>/<instance-id>.
    Create it (mkdir -p); on failure EC_FAILED_MKDIR.

5.  Create the discovery symlink:
        <KGSM_INSTANCES_DIR>/<blueprint-name>/<instance-id> → working_dir

6.  Materialise the per-instance config file at
    <working_dir>/<instance-id>.config.ini, populated from the
    blueprint, the global config, and computed paths
    (full schema in 02-data-model.md §3.3).

    EMIT server.install.created.
    EMIT server.install.started.

7.  Create the standard subdirectories:
        install/, saves/, backups/, temp/, logs/

    EMIT server.install.directories_created.

8.  Assemble the management script (see
    03-management-script-and-overrides.md §4) and write it to
    <working_dir>/<instance-id>.manage.sh with mode 0755.

    EMIT instance-management-file-created.
    EMIT server.install.files_created.
    EMIT instance-config-installed.

9.  Create the optional integrations (each gated by a config flag and
    by the corresponding instance_enable_* field):
        - systemd unit and socket files
            EMIT instance-systemd-enabled.
        - UFW application profile + ufw allow
            EMIT instance-ufw-enabled.
        - command shortcut symlink
            EMIT instance-symlink-created.

10. Resolve target version:
        if --version not supplied or = 0 → call management script's
            "version --latest" to fetch from upstream
        else                              → use the supplied string

11. EMIT server.deploy.started.
    Run management script "download <version>".
        On failure: EC_FAILED_DOWNLOAD; EMIT instance-installation-failed; abort.

12. Run management script "deploy".
        On failure: EC_FAILED_DEPLOY; EMIT instance-installation-failed; abort.
    EMIT server.deploy.finished.

13. Run management script "version --save <version>".
        On failure: EC_FAILED_VERSION_SAVE.

    EMIT server.install.finished.

Return EC_SUCCESS.
```

### 1.3 Idempotency notes

- Step 3 MUST guarantee the new instance ID does not collide with any
  existing entry under `KGSM_INSTANCES_DIR`.
- Step 6 fails outright if the target config file already exists; this
  flow does not silently overwrite an existing instance.

---

## 2. Start (`kgsm start <instance>`)

This is a thin wrapper. The actual lifecycle work lives in the
instance's management script (see
[03-management-script-and-overrides.md §5.1](03-management-script-and-overrides.md)).

### 2.1 Steps

```
1. Resolve instance via __find_instance_config.
   On failure: EC_FILE_NOT_FOUND.
   Source the per-instance config so instance_* are bound.

2. If instance_lifecycle_manager == "systemd" and systemctl is available:
       run: systemctl --user start <instance>.service
   Else (or if systemctl invocation fails and "standalone" fallback is
   permitted by config):
       run: <management_file> start --detached    # _start_background
   Capture exit code.

3. If exit code is success:
       EMIT server.started.
       Optionally launch a watcher in the background:
           watcher <instance> --detach           # see 06-watchers.md
           (Failure of the watcher launch is logged but does NOT fail
           the start.)
       Return EC_SUCCESS.
   Else:
       Return the captured exit code (typically EC_ERROR).
```

### 2.2 Standalone vs systemd

The lifecycle manager is decided at *instance creation time* and stored
in the per-instance config (`lifecycle_manager`). It cannot change
mid-life without recreating the management files.

- `standalone` — KGSM directly invokes the management script. The
  server runs as a child of whatever process invoked KGSM; if that
  parent dies, the server keeps running because module 03 launches it
  with `&` and the FIFO keeps stdin open via a `tail` keepalive.
- `systemd` — KGSM defers to `systemctl`. The unit file's `ExecStart`
  points at the same management script with the same `start` argument
  set. systemd takes over process supervision.

Both modes use the same FIFO mechanism for console input: the systemd
unit file declares a matching `.socket` unit with `ListenFIFO=` so
input can be pushed into the running server through a stable path.

---

## 3. Stop (`kgsm stop <instance> [--no-save] [--no-graceful]`)

### 3.1 Steps

```
1. Resolve instance, source config.

2. If instance_lifecycle_manager == "systemd":
       run: systemctl --user stop <instance>.service
   Else:
       run: <management_file> stop [--no-save] [--no-graceful]

3. The management script's _timed_stop performs:
       a. _send_save_command    (skipped if --no-save)
       b. write instance_stop_command into the FIFO  (skipped if --no-graceful)
       c. wait up to instance_stop_command_timeout_seconds
       d. on timeout: _kill_all_processes (SIGTERM children, then main)
       e. clean up: rm PID file, rm FIFO
       f. _disable_upnp if it was enabled

4. EMIT server.stopped on success.
```

The two flag pairs map to the management script's command-line interface
without translation.

---

## 4. Restart (`kgsm restart <instance>`)

```
stop with default flags    (steps 1–3 of §3)
sleep briefly to let kernel release ports/PIDs
start                      (step 2 of §2)
EMIT server.restarted on success.
```

The KGSM-level restart is *not* a single atomic operation: each phase
emits its own subordinate event. Consumers should subscribe to
`server.restarted` rather than to the inner `server.stopped` /
`server.started` if they want one notification per restart.

---

## 5. Status (`kgsm status <instance> [--json] [--fast]`)

Status is a pure read operation; no events are emitted.

```
1. Resolve instance, source config.
2. Run: <management_file> status [--json] [--fast]
3. The management script's _get_status (module 11) prints either
   a human-readable block or a JSON object (schema in 08-cli-reference.md).
4. --fast skips the upstream version check.
```

`is-active` is the same flow but for a one-line answer:
`<management_file> is-active` returns 0 iff the instance is running.

---

## 6. Logs (`kgsm logs <instance> [-f] [--tail N]`)

```
1. Resolve instance, source config.
2. exec: <management_file> logs [-f] [--tail N]
3. The management script's _print_logs execs `tail` against
   instance_log_file, with --pid=$$ so the tail dies when the
   caller dies.
```

This is an `exec`, not a fork — KGSM hands its terminal directly to
`tail` so the user's `^C` is delivered correctly.

---

## 7. Update flow

There is no top-level `kgsm update` command in the current bash
implementation. Updates are triggered:

- Manually: `<management_file> update` (which the user can invoke
  directly, since the script is self-contained).
- Automatically: when `instance_auto_update=true` is set and the user
  runs `kgsm start`, the management script's `_start_background`
  function calls `_update` before launching the server.

### 7.1 The `_update` flow inside the management script

```
1. Refuse if the server is currently running (use _is_active).
2. version_to_install = _compare_versions
       returns the latest version if updateable, fails (non-zero)
       if up-to-date or on error.
       On "up-to-date": return success without doing anything.

3. EMIT server.deploy.started.
4. _download <version_to_install>          → on failure, EMIT server.deploy.failed
5. _deploy                                  → on failure, EMIT server.deploy.failed
6. _save_version <version_to_install>
7. EMIT server.deploy.finished.
```

A reimplementation MAY add a top-level `kgsm update <instance>` command
that is just a friendly wrapper around step 2 onward. This is purely a
CLI surface decision; the underlying mechanism is unchanged.

---

## 8. Backup (`<management-script> backup --create`)

Backups are also driven from the instance's management script. The
parent KGSM tool exposes them through `kgsm files` / interactive menus
but does not implement them itself.

```
1. Refuse if the server is running (use _is_active).
2. Compute output filename:
       <backups_dir>/<instance>-<installed_version>-<ISO-timestamp>.backup
   (append .tar.gz if instance_compress_backups=true).
3. Either tar -czf the install dir, or recursively cp it into the
   output folder.
4. EMIT backup.created.
```

## 9. Restore (`<management-script> backup --restore <name>`)

```
1. Resolve the source archive in instance_backups_dir.
2. If instance_install_dir is non-empty, FIRST create a new backup
   of the current state (calling _create_backup). Refuse to proceed
   unless the safety backup succeeded.
3. Clear instance_install_dir.
4. tar -xzf or cp -r the chosen backup into instance_install_dir.
5. Parse the version segment out of the backup filename and
   _save_version it.
6. EMIT backup.restored.
```

The version-extraction regex matches:
`^[^-]+-([^-]+)-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.backup`

Falling back to "the third dash-delimited segment" and finally to "any
`x.y[.z]` substring", with a final fallback of `unknown`. This
laundry-list of fallbacks exists because user-renamed backups are
common; preserve all three branches.

---

## 10. Uninstall (`kgsm uninstall <instance>`)

```
1. Resolve instance via __find_instance_config.
   On failure: EC_FILE_NOT_FOUND.
   EMIT instance-uninstallation-started.

2. If the instance is currently running, refuse.
   (The bash implementation does not auto-stop; reimplementations
   MAY choose to, but MUST require an explicit --force flag if so.)

3. Remove generated files:
       management script
       systemd unit + socket    (if enabled)        EMIT instance-systemd-disabled.
       UFW profile + ufw delete (if enabled)        EMIT instance-ufw-disabled.
       UPnP port forwards       (if enabled)        EMIT instance-upnp-disabled.
       command shortcut symlink (if enabled)        EMIT instance-symlink-removed.

   EMIT server.uninstall.files_removed.

4. Remove standard subdirectories: install/, saves/, backups/, temp/, logs/.
   EMIT server.uninstall.directories_removed.

5. Remove the discovery symlink under KGSM_INSTANCES_DIR. If the
   parent <blueprint-name>/ directory becomes empty, remove it too.
   EMIT instance-symlink-removed (if not already emitted in step 3).

6. Remove the per-instance config file.
   EMIT instance-config-uninstalled.
   EMIT server.uninstall.removed.

7. EMIT instance-uninstallation-finished.
```

Uninstall is destructive and irreversible — saves and backups are
wiped along with everything else. The CLI MUST print a clear warning
before performing it (or require `--force` for non-interactive use).

---

## 11. Event emission summary

The full event-name list is in [05-events.md](05-events.md). Two
concerns matter for the flows above:

1. **Pairs.** Every `*-started` event MUST have either a corresponding
   `*-finished` or `*-failed` later in the same flow. Consumers rely on
   this for state machines.
2. **Order.** Events are emitted as soon as the underlying state change
   succeeds. Within a single flow, ordering is the in-document order;
   events are NOT emitted speculatively.

If the implementation's transport is asynchronous (webhook with retry,
queued socket writes), the **emit order** is what matters; the actual
delivery order may differ.

---

## 12. Failure-mode summary

| Phase                | Typical failure                                    | Exit code                                                                                         | Recoverable?                                                                           |
| -------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Blueprint resolution | typo, missing file                                 | `EC_BLUEPRINT_NOT_FOUND`                                                                          | Yes — user retries with correct name.                                                  |
| Install (download)   | network outage, Steam outage, wrong app id         | `EC_FAILED_DOWNLOAD`                                                                              | Yes — re-run `install`; existing partial files are cleaned by `_deploy` clearing temp. |
| Install (deploy)     | disk full, permissions                             | `EC_FAILED_DEPLOY`                                                                                | Often yes — fix the host issue and re-run.                                             |
| Start                | another instance owns the port; missing dependency | `EC_ERROR`                                                                                        | Yes — fix root cause.                                                                  |
| Stop (timeout)       | server ignored stop command                        | `EC_TIMEOUT` (handler-internal) → falls back to SIGKILL                                           | Yes — server is force-killed, which may corrupt unsaved state.                         |
| Update (no change)   | already at latest version                          | `EC_ERROR` from `_compare_versions` (a misnomer — it is intentional sentinel for "no work to do") | N/A                                                                                    |
| Backup               | instance is running                                | `EC_ERROR`                                                                                        | Yes — stop first.                                                                      |
| Restore              | safety backup failed                               | `EC_ERROR`                                                                                        | Yes — frees disk and retries.                                                          |
| Uninstall            | instance is running                                | `EC_ERROR`                                                                                        | Yes — stop first (or implement `--force`).                                             |

A reimplementation MAY introduce more granular codes for the cases
currently lumped under `EC_ERROR`, but MUST NOT change the existing
codes' meanings.
