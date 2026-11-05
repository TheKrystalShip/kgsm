# Blueprints

A blueprint is the file that declares a game server's identity and parameters. An instance is installed
from one. A blueprint is one unified YAML file, `<name>.bp.yaml`, and its `runtime` field (`native` or
`container`) decides how the server runs.

## Where blueprints live

- **System blueprints** are shipped with the package, in `/opt/kgsm/blueprints/`, one flat directory.
  They are read-only.
- **User blueprints** are in `<data home>/kgsm/blueprints/` (`~/.local/share/kgsm/blueprints/`, honouring
  `XDG_DATA_HOME`). A user blueprint shadows a system blueprint of the same name.

`kgsm blueprint list` shows every file, `kgsm blueprint find <name>` where a name resolves with every
candidate path, and `kgsm engine paths` the two directories.

A blueprint's `name` field, not its filename, binds it to a hook file: `name: terraria` uses
`overrides/terraria/hooks.sh`, and several blueprint variants may share one name and one hook file
([hooks.md](hooks.md)).

## Managing blueprints

```sh
kgsm blueprint show factorio              # the content
kgsm blueprint validate my-game           # every rule; the verdict prints whether or not it passes
kgsm blueprint validate /tmp/draft.bp.yaml --json
kgsm blueprint requirements factorio      # what the host must provide, and whether each is present
kgsm blueprint create my-game --file my-game.bp.yaml    # or on standard input
kgsm blueprint update my-game --file my-game.bp.yaml
kgsm blueprint delete my-game             # a system blueprint it shadowed shows again
```

`kgsm blueprint validate` is the schema authority: YAML syntax and every required field for the runtime,
all problems at once with `--json`. `kgsm instance install` refuses a blueprint that does not validate.

## Fields, both runtimes

| Field | Meaning |
|---|---|
| `schema_version` | `1` |
| `name` | lowercase, no spaces; also the hook-file key |
| `runtime` | `native` or `container` |
| `metadata` | advisory presentation fields: `display_name`, `description`, `rawg_slug`, `max_players`, `min_ram_mb`, `recommended_ram_mb`, `base_disk_mb`. Every key is present and every value nullable: `null` is unknown, never a fabricated `0`. `rawg_slug` is a lookup hint for catalogs and is set only when verified. |
| `player_joined_regex`, `player_left_regex` | log patterns for player presence; named groups `id` and `name` |
| `rcon_port`, `rcon_password`, `rcon_poll_interval_seconds`, `rcon_players_command`, `rcon_players_regex` | the RCON presence source, native instances only; an empty `rcon_port` leaves it off. Fill them only from a server observed answering them. |
| `kick_command`, `ban_command`, `unban_command` | console commands that remove, block and unblock a player. Each is a template with exactly one placeholder naming the identity the game expects: `{ip}`, `{name}` or `{id}`. Empty means the game has no such command and the engine refuses the action rather than substitute another. |
| `broadcast_command` | the console command that messages everyone; one `{message}` placeholder |

Every blueprint declares the RCON and moderation families whether or not the game uses them, so a reader
sees which capabilities the game offers.

## Native fields (`runtime: native`)

Required: `native.executable_file`. Under `native:`:

| Field | Meaning |
|---|---|
| `ports` | single-quoted, pipe-separated: `'27015:27020/tcp\|27015/udp'` |
| `steam_app_id`, `client_steam_app_id` | `0` when not a Steam game |
| `is_steam_account_required` | the game's files need a Steam login; credentials come from `/etc/kgsm/kgsm.env` |
| `steamcmd_arguments` | extra arguments for the steamcmd install and update |
| `platform`, `level_name` | passed to the instance config |
| `executable_subdirectory`, `executable_file` | where the binary is launched from, and its name |
| `executable_arguments` | the launch arguments; see below |
| `stop_command`, `save_command` | console commands |
| `startup_success_regex` | the log line that means the server is ready |

### Launch arguments

`executable_arguments` is single-quoted YAML naming instance values as `$instance_<name>` or
`${instance_<name>}`, for example `'--start-server $instance_saves_dir/$instance_level_name'`. The
engine rewrites each reference into the `{camelCase}` template the instance config stores and resolves
that template into an argument list when the server starts: the template is split on whitespace first
and the values substituted inside each argument, so a value with spaces stays one argument and nothing in
a value is shell syntax. `kgsm engine placeholders` lists the values a reference may name. A reference to
any other name fails the install.

## Container fields (`runtime: container`)

Required: `container.compose`, a YAML literal block scalar holding a Docker Compose file verbatim. The
engine writes it to the instance's `<id>.docker-compose.yml`, substituting only `${instance_<key>}` and
`$instance_<key>` against the instance config (an unknown key fails the install); every other `$` is left
for compose. Inside the compose, name the container `${instance_name}`, prefer `network_mode: host`, and
bind-mount the instance's directories through `${instance_install_dir}`, `${instance_backups_dir}`,
`${instance_logs_dir}` and the other path values. The ports to open on the firewall are derived from the
compose; a container blueprint has no top-level `ports`. Official images are under
`ghcr.io/thekrystalship/` (the `kgsm-containers` project).

## Adding a game

1. Write `<name>.bp.yaml`; copy a shipped blueprint of the same runtime.
2. `kgsm blueprint validate <name>` until it passes.
3. Add `overrides/<name>/hooks.sh` only when the game's version check, download or deploy is not the
   generic Steam one ([hooks.md](hooks.md)).
4. Install it, start it, stop it, back it up and update it on a throwaway instance.
