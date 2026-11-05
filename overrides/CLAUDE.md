# CLAUDE.md — overrides/

One directory per game: `overrides/<name>/hooks.sh`, where `<name>` is a blueprint's `name:` field. The
file holds the game's own version check, download, deploy and post-deploy steps as `kgsm_hook_*` functions
the engine inlines into the instance's generated management script. Reference: `docs/hooks.md`.

## Binding

The directory name is the blueprint's logical `name`, not its filename: `terraria-modded.bp.yaml` with
`name: terraria` uses `overrides/terraria/hooks.sh`, and several blueprint variants may deliberately share
one directory. A name that does not line up leaves the game on the script's defaults, silently.

## Resolution

A user file, `<data home>/kgsm/overrides/<name>/hooks.sh`, replaces the system file whole. These system
files ship in the package and are never edited on a host.

## Writing one

- Define only `kgsm_hook_latest_version`, `kgsm_hook_download`, `kgsm_hook_deploy`, `kgsm_hook_post_deploy`
  and helpers prefixed `_hook_`; any other function name is refused.
- Read the instance's values as `instance_<snake_case>` variables, write diagnostics to stderr and fail
  with a non-zero exit. Each hook runs in a subshell under `set -e`.
- A hook that does what the default does is not written: an absent hook is the default.
- A change to a hook file changes its digest, which makes every instance script built from it stale until
  `kgsm instance repair` regenerates it.
