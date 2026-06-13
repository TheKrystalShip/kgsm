# KGSM VS Code Extension

This document explains the KGSM VS Code extension—its purpose, architecture, internal structure, and critical implementation details. It is aimed at developers (and AI models) working on or extending the extension.

---

## Table of Contents

- [Overview](#overview)
- [File Structure](#file-structure)
- [Architecture Overview](#architecture-overview)
- [Extension Lifecycle](#extension-lifecycle)
- [Module: KgsmClient](#module-kgsmclient)
- [Module: BlueprintsProvider](#module-blueprintsprovider)
- [Module: InstancesProvider](#module-instancesprovider)
- [Commands Reference](#commands-reference)
- [Configuration Settings](#configuration-settings)
- [contextValue Conventions](#contextvalue-conventions)
- [Critical Considerations](#critical-considerations)

---

## Overview

The extension lives at `.vscode/kgsm-extension/` and is a **plain JavaScript VS Code extension** with no build step, no bundler, and no npm dependencies beyond the VS Code API and Node.js built-ins. It provides a sidebar panel with two tree views:

- **Blueprints** — browses and creates KGSM blueprint files.
- **Instances** — monitors and controls deployed game server instances.

All communication with KGSM is done by shelling out to the `kgsm.sh` script (or, in limited cases, to scripts in the `commands/` directory) via Node's `child_process.execFile`.

---

## File Structure

```
.vscode/kgsm-extension/
├── package.json           # Extension manifest (contributions, settings)
├── extension.js           # Entry point: activate() / deactivate()
├── kgsmClient.js          # CLI wrapper — all kgsm.sh invocations
├── blueprintsProvider.js  # TreeDataProvider for the Blueprints view
└── instancesProvider.js   # TreeDataProvider for the Instances view
```

There is no `node_modules/`, no `tsconfig.json`, and no compilation step. The extension runs directly as CommonJS modules.

---

## Architecture Overview

```
VS Code UI
    │
    ├─ Blueprints View ──► BlueprintsProvider ──► KgsmClient ──► kgsm.sh / commands/*.sh
    │
    └─ Instances View  ──► InstancesProvider  ──► KgsmClient ──► kgsm.sh
```

`extension.js` is the wiring layer. It:
1. Instantiates `KgsmClient`, `BlueprintsProvider`, and `InstancesProvider`.
2. Registers tree data providers with VS Code.
3. Registers all commands, each of which calls `KgsmClient` methods and then refreshes the relevant provider.
4. Starts a polling timer that calls `instancesProvider.refresh()` every `N` seconds.

`KgsmClient` is the single point of contact with the shell. No other module spawns processes.

---

## Extension Lifecycle

### `activate(context)`

Called by VS Code when the extension is first used.

1. Reads `kgsm.scriptPath` from settings to build a `KgsmClient`.
2. Instantiates both tree providers and registers them.
3. Registers all commands (see [Commands Reference](#commands-reference)).
4. Reads `kgsm.pollInterval` (default `30` seconds) and starts a `setInterval` that calls `instancesProvider.refresh()`.

The `pollTimer` is stored as a **module-level variable** (`let pollTimer`), not on `context.subscriptions`. This means it is not auto-disposed by VS Code — `deactivate()` must clear it manually.

### `deactivate()`

Clears `pollTimer` to prevent callbacks from firing after unload.

---

## Module: KgsmClient

**File:** `kgsmClient.js`

The client wraps all CLI interactions. It is constructed with a single argument: the absolute path to `kgsm.sh`.

```js
const client = new KgsmClient("/usr/local/bin/kgsm");
```

### `this.cwd`

`path.dirname(kgsmPath)` — the KGSM root directory. This is used as the working directory for all `execFile` calls and for resolving sibling paths (e.g., `templates/blueprint.tp`).

**Critical:** If `kgsmPath` is a symlink to `kgsm.sh` in a different directory (e.g., `/usr/local/bin/kgsm` → `/opt/kgsm/kgsm.sh`), `this.cwd` will be `/usr/local/bin`, not `/opt/kgsm`. Blueprint template reading and sub-script resolution in `addBlueprint` will fail unless the path points directly to the script's real location.

### `exec(args)`

The core method. Calls `execFile(this.kgsmPath, args, { cwd: this.cwd })` and resolves with `{ stdout, stderr, exitCode }`. It **never rejects** — errors are encoded in `exitCode`.

### Methods

| Method                                         | CLI invocation                                                    | Returns                                                                        |
| ---------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `getBlueprints(filter?)`                       | `kgsm.sh blueprints list [filter] --json`                         | `string[]`                                                                     |
| `getBlueprintsDetailed()`                      | `kgsm.sh blueprints list detailed --json`                         | `Record<string, object>` (name → info, incl. `BlueprintType`)                  |
| `getBlueprintDirs()`                           | `kgsm.sh --paths`                                                 | `{ default, custom }` or `null`                                                |
| `getBlueprintFilePath(name)`                   | `kgsm.sh blueprints find <name>`                                  | `string` or `null` (stdout trimmed)                                            |
| `getInstances(blueprint?)`                     | `kgsm.sh instances list [blueprint] --json`                       | `string[]`                                                                     |
| `getInstanceStatus(name)`                      | `kgsm.sh instances status <name> --json --fast`                   | `object` or `null`                                                             |
| `getInstanceInfo(name)`                        | `kgsm.sh instances info <name> --json`                            | `object` or `null`                                                             |
| `getInstanceConfigPath(name)`                  | `kgsm.sh instances find <name>`                                   | `string` or `null` (stdout trimmed)                                            |
| `isActive(name)`                               | `kgsm.sh is-active <name>`                                        | `boolean` (exit code 0 = true)                                                 |
| `startInstance(name)`                          | `kgsm.sh start <name>`                                            | `{ stdout, stderr, exitCode }`                                                 |
| `stopInstance(name)`                           | `kgsm.sh stop <name>`                                             | `{ stdout, stderr, exitCode }`                                                 |
| `restartInstance(name)`                        | `kgsm.sh restart <name>`                                          | `{ stdout, stderr, exitCode }`                                                 |
| `createInstance(blueprint, installDir, name?)` | `kgsm.sh install <blueprint> --install-dir <dir> [--name <name>]` | `{ stdout, stderr, exitCode }`                                                 |

### Runtime is a per-blueprint field, not a file family

With the unified `<name>.bp.yaml` format, every method goes through `kgsm.sh` (no
direct `commands/*.sh` invocation). There is no longer a native-vs-container script
split. A blueprint's runtime lives in its `runtime` field, surfaced on the wire as
`BlueprintType` (`Native`/`Container`). `getBlueprintsDetailed()` returns the full
info object for every blueprint keyed by name, which the tree uses to pick a
per-item icon and tooltip.

### `getBlueprintDirs()` — `--paths` Parsing

This method calls `kgsm.sh --paths` and parses the output with regex matching for the
two flat blueprint directories (one per source — no native/container subdirs):

```
KGSM_SYSTEM_BLUEPRINTS_DIR: /path/to/blueprints
KGSM_USER_BLUEPRINTS_DIR:   /path/to/.local/share/kgsm/blueprints
```

If the output format of `--paths` ever changes (key names, spacing, or ordering), this parsing will silently return `null` values.

---

## Module: BlueprintsProvider

**File:** `blueprintsProvider.js`

Implements `vscode.TreeDataProvider`. The tree has two levels, split by source
(default vs. custom). Runtime is shown per-item (icon + tooltip), not as a category:

```
Default                 (BlueprintCategory, filter="default")
  ├─ factorio           (BlueprintItem, native)
  └─ valheim            (BlueprintItem, native)
Custom                  (BlueprintCategory, filter="custom")
  └─ vrising            (BlueprintItem, container)
```

### `BlueprintCategory`

A `vscode.TreeItem` subclass representing a collapsible folder node. Its `contextValue` is:

```
blueprintCategory-{filter}
```

Examples: `blueprintCategory-default`, `blueprintCategory-custom`.

The `addBlueprint` command menu item uses the when-clause `viewItem =~ /^blueprintCategory/` to match all category nodes.

### `BlueprintItem`

A `vscode.TreeItem` subclass representing a single blueprint. Its `contextValue` is `"blueprint"` and it carries `item.runtime` (`"native"`/`"container"`/`""`) for its icon and tooltip. Clicking it fires `kgsm.openBlueprint` with itself as the argument, providing `item.blueprintName` to the command handler.

### Data Flow

When a category is expanded, `getChildren(element)` fetches the source's names via
`client.getBlueprints(element.filter)` and a name→info map via
`client.getBlueprintsDetailed()` (both in parallel), then maps each name to a
`BlueprintItem`, reading the runtime from the detail map's `BlueprintType`.

---

## Module: InstancesProvider

**File:** `instancesProvider.js`

Implements `vscode.TreeDataProvider`. The tree has two levels:

```
factorio                (BlueprintGroup, 2 instances)
  ├─ factorio-01        (InstanceItem, running, v2.0.28)
  └─ factorio-02        (InstanceItem, stopped, v2.0.15)
minecraft               (BlueprintGroup, 1 instance)
  └─ minecraft-01       (InstanceItem, running, 1.21.4)
```

### Blueprint Grouping

At the root level, all instances are fetched, then `getInstanceInfo(name)` is called for each (in parallel via `Promise.all`). The `blueprint_file` field of the returned info object is parsed to extract the blueprint name:

```js
// e.g. info.blueprint_file = "/opt/kgsm/blueprints/factorio.bp.yaml"
// → filename = "factorio.bp.yaml" → name = "factorio"
```

The regex `replace(/\.bp\.yaml$/, "")` strips the unified extension. If `blueprint_file` is absent or null, the fallback strips a trailing `-{digits}` suffix from the instance name.

### Instance Status

Status is determined by `client.isActive(name)`, which checks the exit code of `kgsm.sh is-active <name>` (exit 0 = running, non-zero = stopped). The `getInstanceStatus` method (which calls `kgsm.sh instances status --fast`) is **defined on the client but not currently used** by the provider.

### Version Display

The installed version is read from the file path stored in `info.version_file` using **synchronous** `fs.readFileSync`. This is called inside an async function, but the I/O is blocking. If the file is large or on a slow filesystem, it will block the extension host's event loop.

### Instance Cache (`_instanceCache`)

A `Map<string, object>` is maintained on the provider instance. It is populated during `_getBlueprintGroups()` and consulted as a fast path in `_getInstanceItems()` before falling back to `getInstanceInfo()`. The cache is **never evicted** — entries persist as long as the provider object lives. Instances that are removed from KGSM will linger in the cache until VS Code is reloaded.

### `BlueprintGroup`

A `vscode.TreeItem` that starts expanded (`TreeItemCollapsibleState.Expanded`). Its `contextValue` is `"blueprintGroup"`.

### `InstanceItem`

A `vscode.TreeItem` whose appearance and available commands depend on the running state:

| State   | Icon color                   | `contextValue`      |
| ------- | ---------------------------- | ------------------- |
| Running | `testing.iconPassed` (green) | `"instancerunning"` |
| Stopped | `testing.iconFailed` (red)   | `"instancestopped"` |

The `item.instanceName` and `item.instanceInfo` properties are used by command handlers.

---

## Commands Reference

All commands are registered in `extension.js`. Each wraps one or more `KgsmClient` calls and calls `provider.refresh()` after mutations.

| Command ID                  | Trigger                                   | What it does                                                                                                                  |
| --------------------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `kgsm.openSettings`         | Gear icon in view title                   | Opens VS Code settings filtered to this extension                                                                             |
| `kgsm.refreshBlueprints`    | Refresh icon on Blueprints panel          | Fires `blueprintsProvider.refresh()`                                                                                          |
| `kgsm.openBlueprint`        | Click or inline icon on `BlueprintItem`   | Calls `getBlueprintFilePath(name)`, opens file in editor                                                                      |
| `kgsm.addBlueprint`         | `+` inline on `BlueprintCategory`         | Prompts name + runtime, resolves target dir via `getBlueprintDirs()`, writes `<name>.bp.yaml` from the unified template, opens editor |
| `kgsm.refreshInstances`     | Refresh icon on Instances panel           | Fires `instancesProvider.refresh()`                                                                                           |
| `kgsm.createInstance`       | `+` icon on Instances panel title         | Prompts blueprint (QuickPick), install dir (folder dialog), optional name, runs `kgsm.sh install`                             |
| `kgsm.startInstance`        | Inline play button on stopped instance    | Calls `client.startInstance(name)`                                                                                            |
| `kgsm.stopInstance`         | Inline stop button on running instance    | Calls `client.stopInstance(name)`                                                                                             |
| `kgsm.restartInstance`      | Inline restart button on running instance | Calls `client.restartInstance(name)`                                                                                          |
| `kgsm.updateInstance`       | Context menu on any instance              | Executes `info.management_file --update` directly via `child_process.execFile`                                                |
| `kgsm.openInstanceLog`      | Context menu on any instance              | Opens a new terminal and sends `kgsm logs <name> --follow`                                                                    |
| `kgsm.openInstanceConfig`   | Context menu on any instance              | Calls `getInstanceConfigPath(name)`, opens file in editor                                                                     |
| `kgsm.openManagementScript` | Context menu on any instance              | Reads `management_file` from cached info or fresh `getInstanceInfo()`, opens file in editor                                   |

### `kgsm.addBlueprint` — Template Resolution

For native blueprints, the command reads `templates/blueprint.tp` relative to `client.cwd`. If that file is not found, it falls back to a hardcoded minimal template. For container blueprints, the template is always hardcoded inline (no file read).

### `kgsm.updateInstance` — Direct `management_file` Execution

This command does **not** go through `KgsmClient` or `kgsm.sh`. It calls `execFile(info.management_file, ["--update"], ...)` directly. This means:
- The `management_file` must be executable.
- Errors from the management script are surfaced as `stderr` in the error message.
- There is no unified error code interpretation.

### `kgsm.openInstanceLog` — Terminal Mode

Unlike all other instance commands, this one does not show a progress notification and does not call any `KgsmClient` method. It creates a new VS Code terminal and sends the command as text. The terminal persists after the command ends.

---

## Configuration Settings

Declared in `package.json` under `contributes.configuration`:

| Setting             | Type     | Default               | Description                                                                                                  |
| ------------------- | -------- | --------------------- | ------------------------------------------------------------------------------------------------------------ |
| `kgsm.scriptPath`   | `string` | `/usr/local/bin/kgsm` | Absolute path to the `kgsm.sh` script. This is the **only** parameter that `KgsmClient` is constructed with. |
| `kgsm.pollInterval` | `number` | `30`                  | Seconds between automatic instance status refreshes. Minimum value `5`.                                      |

The `pollInterval` is read **once** during `activate()` and used to start `setInterval`. If the user changes it in settings, the change does **not** take effect until VS Code is reloaded. There is no `onDidChangeConfiguration` listener.

Similarly, `scriptPath` is read once at activation. Changes require a reload.

---

## `contextValue` Conventions

`contextValue` strings control which menu items and inline buttons appear on tree nodes. The `package.json` `when` clauses rely on exact string matching or regex patterns.

### Blueprint nodes

| Node type           | `contextValue`                         | Pattern used in menus              |
| ------------------- | -------------------------------------- | ---------------------------------- |
| `BlueprintCategory` | `blueprintCategory-{filter}-{runtime}` | `viewItem =~ /^blueprintCategory/` |
| `BlueprintItem`     | `"blueprint"`                          | `viewItem == blueprint`            |

### Instance nodes

| Node state | `contextValue`      | Pattern used in menus                              |
| ---------- | ------------------- | -------------------------------------------------- |
| Running    | `"instancerunning"` | `viewItem =~ /^instance/ && viewItem =~ /running/` |
| Stopped    | `"instancestopped"` | `viewItem =~ /^instance/ && viewItem =~ /stopped/` |

**Important:** The instance `contextValue` strings use no separator — they are `"instancerunning"` and `"instancestopped"` (not `"instance-running"`). Both match `^instance` and then their respective state word. When adding new instance states or node types, maintain this `instance{state}` camelCase pattern or update all when-clauses in `package.json` accordingly.

---

## Critical Considerations

### 1. `kgsmPath` Must Be the Real Script Location

`this.cwd = path.dirname(kgsmPath)` underpins template resolution. If `kgsmPath` points to a symlink (e.g., `/usr/local/bin/kgsm` → `/opt/kgsm/kgsm.sh`), then `cwd` will be `/usr/local/bin` — and reading `templates/blueprint.tp` (for `addBlueprint`) will fail. Users must set `kgsm.scriptPath` to the actual script path, not a symlink wrapper.

### 2. No `--json` Flag Consistency

Most list/info commands request `--json` output which the client `JSON.parse`s. However, `getBlueprintFilePath` and `getInstanceConfigPath` expect **raw path strings** on stdout (not JSON). If KGSM ever adds `--json` support to `blueprints find` or `instances find`, the client must be updated.

### 3. `getInstanceStatus` Is Unused

`KgsmClient.getInstanceStatus()` is defined (calls `instances status --fast --json`) but never called by `InstancesProvider`. Status is determined solely by `isActive()` (exit code). The richer status data (e.g., uptime, pid) is available but not surfaced in the UI.

### 4. Synchronous File I/O in Async Context

`InstancesProvider._readVersion()` uses `fs.readFileSync` inside an `async` function called within `Promise.all`. This blocks the Node.js event loop for the duration of the file read. For users with many instances or version files on slow mounts, this can cause the extension host to stall.

### 5. Instance Cache Has No Eviction

`_instanceCache` grows monotonically. Deleted instances remain in the map. Stale cache entries do not cause visible bugs (the provider will re-fetch if the cached entry is used and info is null), but memory is never freed during a session.

### 6. Poll Timer Is Not on `context.subscriptions`

`pollTimer = setInterval(...)` is a module-level variable. It is only cleared in `deactivate()`. If `deactivate()` is somehow not called (edge case), the timer leaks. This is a minor risk but worth noting when refactoring the activation lifecycle.

### 7. `kgsm.pollInterval` and `kgsm.scriptPath` Require Reload

Neither setting is watched for changes. `setInterval` is set once with the value read at activation. To change either value, the extension host must be reloaded.

### 8. `kgsm.updateInstance` Bypasses `KgsmClient`

This is the only command that directly executes a file path (`info.management_file`) without going through `KgsmClient.exec()`. It uses an inline `require("child_process")` call. Any changes to how updates are triggered should be unified through the client.

### 9. No Input Sanitization for Shell Arguments

`KgsmClient.exec()` uses `execFile` (not `exec`), so arguments are passed as an array and are not subject to shell injection. This is the correct and safe approach and must be preserved in any refactoring.

### 10. Blueprint Name Validation Is UI-Only

The `kgsm.addBlueprint` command validates the name input (lowercase, alphanumeric + hyphens) in the UI. The same validation does not exist for `kgsm.createInstance` — the custom name input there validates format but the blueprint selection is a free QuickPick with no further checks before invoking `kgsm.sh install`.

### 11. `BlueprintGroup` Grouping Can Produce "unknown"

If `info.blueprint_file` is null or absent and `info.name` is also null, `_extractBlueprintName()` returns `"unknown"`. Multiple such instances will be grouped under a single `"unknown"` node.
