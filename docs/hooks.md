# Hooks

A game whose version check, download or deploy is not the generic Steam one supplies a hook file:
`overrides/<name>/hooks.sh`, where `<name>` is the blueprint's `name` field. The engine inlines the file
into the instance's generated management script.

## Where hook files live

- **System:** `/opt/kgsm/overrides/<name>/hooks.sh`, shipped with the package.
- **User:** `<data home>/kgsm/overrides/<name>/hooks.sh`. A user file replaces the system file whole and
  never merges with it.

## The functions

A hook file defines functions from this list, and helpers prefixed `_hook_`. Any other function name is
refused.

| Function | Arguments | What it does |
|---|---|---|
| `kgsm_hook_latest_version` | none | prints the newest upstream version |
| `kgsm_hook_download` | `<version> <dest_dir>` | downloads and unpacks that version into the directory |
| `kgsm_hook_deploy` | `<temp_dir> <install_dir>` | moves the downloaded files into the install directory |
| `kgsm_hook_post_deploy` | `<install_dir>` | runs after a deploy: creates a missing save, writes an EULA, sets a mode |

A hook that is absent uses the script's own behaviour: a Steam game's version comes from steamcmd and its
files from steamcmd's download.

## Rules

- Hooks read the instance's values as `instance_<snake_case>` variables (`instance_saves_dir`,
  `instance_launch_dir`, `instance_level_name`, `instance_download_timeout_seconds`, and the rest of the
  instance config's keys), write diagnostics to stderr and fail with a non-zero exit.
- Each hook runs in a subshell under `set -e`.
- A hook file must be valid bash; `kgsm instance install` and `kgsm instance repair` refuse one that is not.
- The script records the digest of the hook file it was built from. Changing a hook file makes the
  instance's script stale; `kgsm instance repair <instance>` regenerates it.
- Downloads honour `instance_download_timeout_seconds` (setting `Downloads:TimeoutSeconds`).
- Tools a hook needs beyond the package's dependencies (`curl` is one) are the hook author's to declare in
  the blueprint's requirements.

The shipped files, `overrides/factorio/hooks.sh` and the others beside it, are the reference.
