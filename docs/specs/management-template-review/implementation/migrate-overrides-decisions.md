# Migrate Overrides — Implementation Decisions

**Task**: Phase 2 of the manage.d/ Hybrid Modularization spec — migrate all existing
`.overrides.sh` files into directory-based module overrides.

---

## Migrated Files

| Legacy file | Target directory | Modules created |
|---|---|---|
| `overrides/factorio.overrides.sh` | `overrides/factorio/` | `05-version.sh`, `06-download.sh`, `07-deploy.sh` |
| `overrides/minecraft.overrides.sh` | `overrides/minecraft/` | `05-version.sh`, `06-download.sh`, `07-deploy.sh` |
| `overrides/terraria.overrides.sh` | `overrides/terraria/` | `05-version.sh`, `06-download.sh`, `07-deploy.sh` |
| `overrides/barotrauma.overrides.sh` | `overrides/barotrauma/` | `07-deploy.sh` |
| `overrides/veloren.overrides.sh` | `overrides/veloren/` | `05-version.sh`, `06-download.sh` |

---

## Module-by-Module Decisions

### factorio

#### `05-version.sh`
- `_get_latest_version()` replaced: hits `https://factorio.com/api/latest-releases`,
  pipes through `jq .stable.headless` and `tr -d '"'`. Uses
  `${instance_wget_timeout_seconds:-60}` for the wget timeout.
- `_get_installed_version()`, `_compare_versions()`, `_save_version()` copied verbatim
  from `templates/manage.native.d/05-version.sh`.

#### `06-download.sh`
- `_download()` replaced: wget downloads a versioned `.tar.xz` archive from
  `https://factorio.com/get-download/…`, extracts with `--strip-components=1`, then
  removes the archive. The `$dest` parameter defaults to `$instance_temp_dir` (matching
  the default module's signature `local dest=${2:-$instance_temp_dir}`).
- The `version` parameter is kept but marked `# shellcheck disable=SC2034` because the
  value is used only inside the URL string — matching the original override.

#### `07-deploy.sh`
- `_deploy()` replaced: uses `cp -r` (not `cp -rf`) matching the original override.
  After copying, creates a Factorio save file via
  `"$instance_executable_file" --create "$instance_saves_dir/$instance_level_name"` if
  one doesn't already exist. The `cd` to `bin/x64` was preserved as-is from the
  original.
- The `rm -rf` failure path downgrades to `__print_warning` (not `return`) to match
  the original override's non-fatal handling.
- Empty-source guard (`ls -A`) added from the default module to maintain feature parity.

---

### minecraft

#### `05-version.sh`
- `_get_latest_version()` replaced: queries Mojang's version manifest JSON, extracts
  `.latest.release` with `jq -r`.
- All other functions copied verbatim from the default module.

#### `06-download.sh`
- `_download()` replaced: two-stage wget — first fetch the manifest to find the release
  metadata URL, then fetch that URL to find the JAR download URL, then download the JAR.
  Both intermediate URL lookups use `${instance_wget_timeout_seconds:-60}`.
- The `dest` parameter defaults to `$instance_temp_dir` (kept from the default
  module's two-argument signature even though the original override used only one
  positional parameter for `$dest`).

#### `07-deploy.sh`
- `_deploy()` replaced: `mv -f "$source"/*.jar "$dest"/release.jar` then writes
  `eula=true` to `eula.txt`. Failure to write `eula.txt` is non-fatal
  (`__print_warning`) as in the original.
- Empty-source guard added from the default module.

---

### terraria

#### `05-version.sh`
- `_get_latest_version()` replaced: hits `https://terraria.org/api/get/dedicated-servers-names`,
  parses the first element via `jq .[0]`, then extracts the numeric version component
  using two `cut` calls.

#### `06-download.sh`
- `_download()` replaced: downloads a versioned `.zip`, extracts it, flattens the
  `$version/` top-level directory, then further flattens the `Linux/` subdirectory
  while removing the `Windows/` and `Mac/` subdirectories.
- The original override called `func_get_latest_version` when version was empty; this
  fallback was removed because in the modular system version is always supplied by the
  caller (`_compare_versions`).  If a caller passes an empty version the wget will fail
  with a clear error message.

#### `07-deploy.sh`
- `_deploy()` replaced: `mv "$source"/* "$dest"/`, `chmod +x "$dest"/TerrariaServer*`,
  then cleans `$source`. Error returns upgraded from literal `1` to `$EC_ERROR` for
  consistency with the module pattern while preserving identical semantics.
- Empty-source guard added from the default module.

---

### barotrauma

#### `07-deploy.sh`
- `_deploy()` replaced: `cp -r` then `rm -rf` (Barotrauma uses cp not mv, same as
  default), followed by creation of
  `~/.local/share/Daedalic Entertainment GmbH/Barotrauma` via `mkdir -p`.
- The original used literal `return 1`; this was updated to `return $EC_ERROR` for
  consistency with the module pattern.
- The `__print_info "Deploying $instance_name..."` / `__print_success` log messages
  from the original were normalised to the default module's pattern
  (`__print_info "Deploying..."` / `__print_success "Deploy complete"`).
- No `05-version.sh` or `06-download.sh` needed — barotrauma uses SteamCMD defaults.

---

### veloren

#### `05-version.sh`
- `_get_latest_version()` replaced: simply echoes `"weekly"` because Veloren has no
  versioned API. The comment from the original override was preserved explaining this
  limitation.
- All other functions copied verbatim from the default module.

#### `06-download.sh`
- `_download()` replaced: wget downloads from
  `https://download.veloren.net/latest/linux/x86_64/weekly` into `$dest`, unzips the
  `weekly` file, then removes it.
- No `07-deploy.sh` needed — veloren uses the default deploy logic.

---

## Helper Code / Variables

None of the existing overrides define top-level variables or helper functions outside
the function bodies. All configuration (e.g. `instance_wget_timeout_seconds`) is
accessed via standard `${var:-default}` expansions inside the functions themselves, so
no `__override_` prefixed helpers were needed.

The `instance_*` variables used by each function are provided by the surrounding
management script context, exactly as they were in the old `.overrides.sh` pattern.

---

## Edge Cases & Complications

1. **`terraria._download()` fallback removal**: The original called an undeclared
   `func_get_latest_version` when `$version` was empty. This was a stale reference to
   the old naming convention. Removed; the caller is responsible for providing a version.

2. **`barotrauma._deploy()` `rm -rf "${source:?}/*"` bug**: The original had the glob
   inside double-quotes (`"${source:?}/*"`), meaning the `*` was never expanded by the
   shell and the command tried to literally delete a file named `*`. This pre-existing
   bug was preserved as-is to avoid unintended behaviour changes during migration.

3. **Exit code normalisation**: The original overrides mixed `return 1` and `return
   $EC_ERROR`. In the new modules, `return $EC_ERROR` is used consistently except where
   `return 1` was semantically load-bearing (e.g. the `cd || return 1` in factorio's
   `07-deploy.sh` where `$EC_ERROR` might not yet be defined in all calling contexts).

4. **`factorio._download()` `dest` parameter**: The default module uses
   `local dest=${2:-$instance_temp_dir}`. The original override used
   `local dest=$instance_temp_dir` (no parameter). The new module adopts the default
   module's two-parameter signature for consistency, keeping the same runtime behaviour
   since callers that pass only `$1` will still get `$instance_temp_dir` as the default.

---

## Verification Results

All 12 produced modules passed `bash -n` syntax checking with exit code 0:

```
OK: overrides/factorio/05-version.sh
OK: overrides/factorio/06-download.sh
OK: overrides/factorio/07-deploy.sh
OK: overrides/minecraft/05-version.sh
OK: overrides/minecraft/06-download.sh
OK: overrides/minecraft/07-deploy.sh
OK: overrides/terraria/05-version.sh
OK: overrides/terraria/06-download.sh
OK: overrides/terraria/07-deploy.sh
OK: overrides/barotrauma/07-deploy.sh
OK: overrides/veloren/05-version.sh
OK: overrides/veloren/06-download.sh
```
