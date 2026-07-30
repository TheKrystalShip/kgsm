# CLAUDE.md — blueprints/

Blueprints are the templates that declare a game server's identity and
parameters. KGSM creates **instances** from them. Full reference:
`docs/blueprints.md`.

## Format & layout

One **unified YAML** file per game: `<name>.bp.yaml`, in a single **flat**
`blueprints/` directory. There is no `native/` vs `container/` split — the
`runtime` field inside the file (`native` | `container`) decides how the server
runs. Parsing is done with **mikefarah/yq** (Arch package `go-yq`), a **hard
dependency**: a blueprint operation on a host without it fails fast with an
actionable error (`__require_yq` in `core/loader.sh`).

These are the **system** (read-only, shipped) blueprints. User blueprints live
under `~/.local/share/kgsm/blueprints/*.bp.yaml` (respects `$XDG_DATA_HOME`) and
**shadow** a system blueprint of the same name. Never tell users to edit files
here directly — they get overwritten on update; have them copy to the user
directory instead.

## Required fields (both runtimes)

- `schema_version` — currently `1` (future migration hook).
- `name` — lowercase, no spaces. Also the **override-binding key** (see below).
- `runtime` — `native` | `container`.
- `metadata:` — a block of advisory, presentation-oriented fields for catalog /
  control-panel UIs. All keys are **required to be present** but every value
  is **nullable**: `display_name`, `description`, `rawg_slug`, `max_players`,
  `min_ram_mb`, `recommended_ram_mb`, `base_disk_mb`. **`null` means
  unknown/unbounded — never a fabricated `0`** (the project's no-fabricate
  invariant). Nothing in create/install reads metadata, so a blueprint works
  fully with it all null.
  - `rawg_slug` is the game's slug on [RAWG.io](https://rawg.io) — the external
    catalog the Control Panel uses to fetch cover art + description + tags. It is
    a *lookup hint* only (kgsm never calls RAWG; the consumer does), and is the
    same kind of external-catalog id as `native.steam_app_id`. The blueprint
    `name` is **not** assumed to equal the slug (e.g. `gmod` → `garrys-mod`,
    `ark` → `ark-survival-evolved`). Set it **only when verified** (the slug
    resolves to the right game); leave it `null` otherwise — a wrong slug is
    misattribution, which the no-fabricate invariant forbids.

## Native blueprint (`runtime: native`)

Required: `native.executable_file`. Common optional under `native:`: `ports`,
`steam_app_id` (`0` if not Steam), `client_steam_app_id` (`0` if not Steam),
`is_steam_account_required`,
`steamcmd_arguments`, `platform`, `level_name`, `executable_subdirectory`,
`executable_arguments`, `stop_command`, `save_command`, `startup_success_regex`.

Top-level, runtime-agnostic fields (both native and container):
`player_joined_regex`, `player_left_regex`, `rcon_port`, `rcon_password`,
`rcon_poll_interval_seconds`, `rcon_players_command`.

- `ports` is **single-quoted, pipe-separated** UFW format:
  `ports: '1111:2222/tcp|3333/udp'`.
- `executable_arguments` is single-quoted YAML so `$instance_*` variables survive
  to runtime (e.g. `'--start-server $instance_saves_dir/$instance_level_name'`);
  the eval-cat in `__logic_create_base_instance` substitutes them. The full
  variable list is in `docs/blueprints.md` and `templates/blueprint.tp`.

- `rcon_port` (int, nullable) — the game server's RCON port. Null = no RCON
  detection. The watchdog polls this port for connected players when log-based
  leave detection is unavailable.
- `rcon_password` (string) — RCON authentication password. Empty = RCON disabled.
  Stored in plaintext in the instance config; the user must also configure the
  game server's own RCON with matching values.
- `rcon_poll_interval_seconds` (int, nullable) — how often to poll via RCON
  (default 10, minimum 5). Null = default.
- `rcon_players_command` (string) — the RCON command to query connected players
  (default "players"). Game-specific: PZ uses "players", Source engine games
  use "status" or "listplayers".

## Container blueprint (`runtime: container`)

Required: `container.compose` — a YAML **literal block scalar** (`compose: |`)
holding the Docker Compose **verbatim** (comments and `${instance_*}` preserved).
KGSM extracts it to the instance's `docker-compose.yml` at create time and
substitutes `${instance_*}`. Inside the compose: set
`container_name: ${instance_name}`, prefer `network_mode: host`, and bind-mount
KGSM dirs via `${instance_install_dir}`, `${instance_backups_dir}`, etc. Official
images: `ghcr.io/thekrystalship/` (see the kgsm-containers project).

- **UFW ports are derived** from the embedded compose (`__derive_ufw_ports_from_compose`),
  so there is **no** top-level/native `ports` for a container — the compose is the
  single source.

## The critical gotcha: name → override binding

A blueprint binds to an override directory by its **logical `name`, not its
filename**, for **both** runtimes: a blueprint with `name: terraria` uses
`overrides/terraria/` regardless of the file name. (Containers used to bind on
the "first service name under `services:`" — that hack is gone; the explicit
`name` field is now authoritative for every runtime.)

Multiple blueprint variants can share one `name` (and thus one override dir) on
purpose. See `overrides/CLAUDE.md` and `docs/overrides.md`.

## Editing checklist

- Keep `name` lowercase, no spaces.
- Keep native `ports` single-quoted; for containers, declare ports only inside
  the embedded compose (KGSM derives the firewall rules from it).
- Leave any unknown `metadata` value as `null` — never invent a number.
- The file must pass `./kgsm.sh blueprints validate <name>`, which is the
  schema authority — YAML syntax plus every required field for the runtime.
  `--json` lists every problem at once, and a path argument checks a file that
  is not yet under a blueprint name: `blueprints validate /tmp/draft.bp.yaml --json`.
- If you add a blueprint that needs custom install/update logic, it needs a
  matching `overrides/<name>/` directory — the `name` must line up.
