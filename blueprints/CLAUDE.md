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
`rcon_poll_interval_seconds`, `rcon_players_command`, `rcon_players_regex`,
`kick_command`, `ban_command`, `unban_command`.

**Every blueprint declares the RCON family, whether or not the game uses it** —
an empty `rcon_port` leaves it off, and the fields being present is how a reader
sees the capability exists for that game and is simply not wired up yet. Fill
them in only from a server observed answering them, the same rule the presence
patterns follow. RCON presence is polled for **native** instances only; on a
container blueprint the fields are declared but nothing reads them yet.

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
- `rcon_players_regex` (string) — how to read one player out of what that command
  answers, matched **per line**, with optional named groups `id` and `name`. An
  entry carries whichever the server actually states: Project Zomboid prints a
  header and one `-Name` line per player and gives no id anywhere, while a
  columnar roster gives both. Carrying the shape here is what lets a single
  poller read any game's roster without knowing which game it is talking to, so a
  new RCON game is a blueprint edit rather than a change to whatever polls it.
  Empty means the output cannot be read — the poller then skips the instance
  rather than reporting an empty roster, because "nobody is connected" and "I
  could not parse the answer" are different facts.

## Player moderation (`kick_command`, `ban_command`, `unban_command`)

The console commands the game accepts to remove a player, block them, and lift
that block. KGSM sends them down the same channel as `save_command` — the
instance's console — so author them from real server commands.

Each is a **template with exactly one placeholder, and the placeholder names the
identity token the game expects**: `{ip}`, `{name}`, or `{id}`. `kick {ip}`
says both "the verb is `kick`" and "hand it an IP address". That name is the
contract a caller reads to know what to send, which is why the kind lives in the
template and is not duplicated into a separate field where the two could
disagree. Text outside the placeholder is sent verbatim.

Empty/unset means the game has no such command. KGSM then **refuses** the
action — it never substitutes a different one, because a kick standing in for a
ban is a fabricated outcome.

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
