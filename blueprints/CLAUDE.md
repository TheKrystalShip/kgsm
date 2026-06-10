# CLAUDE.md — blueprints/

Blueprints are the templates that declare a game server's parameters. KGSM
creates **instances** from them. Full reference: `docs/blueprints.md`.

## Layout

- `native/*.bp` — native (direct Linux process) servers, `key=value` INI format.
- `container/*.docker-compose.yml` — containerized servers, standard Docker
  Compose files.

These are the **system** (read-only, shipped) blueprints. User blueprints live
under `~/.local/share/kgsm/blueprints/{native,container}/` (respects
`$XDG_DATA_HOME`) and **shadow** a system blueprint of the same filename. Never
tell users to edit files here directly — they get overwritten on update; have
them copy to the user directory instead.

## Native blueprint (`.bp`) essentials

Required fields: `name`, `executable_file`, `level_name`. Common optional:
`ports`, `steam_app_id` (`0` if not Steam), `executable_subdirectory`,
`executable_arguments`, `stop_command`, `save_command`, `startup_success_regex`.

- `ports` is **single-quoted, pipe-separated** UFW format:
  `ports='1111:2222/tcp|3333/udp'`.
- `executable_arguments` may reference `$instance_*` variables resolved at
  runtime (e.g. `"--start-server $instance_saves_dir/$instance_level_name"`).
  The full variable list is in `docs/blueprints.md` and `templates/blueprint.tp`.
- Copy `templates/blueprint.tp` (the documented blank template) or an existing
  `.bp` as a starting point.

## Container blueprint essentials

Plain Docker Compose. Set `container_name: ${instance_name}`, prefer
`network_mode: host`, and bind-mount KGSM dirs via `${instance_install_dir}`,
`${instance_backups_dir}`, etc. Official images: `ghcr.io/thekrystalship/`
(see the kgsm-containers project).

## The critical gotcha: name → override binding

A blueprint binds to an override directory by its **logical name, not its
filename**:
- Native: the `name=` field. `terraria-modded.bp` with `name=terraria` →
  `overrides/terraria/`.
- Container: the **first service name** under `services:` →
  `overrides/<service>/`.

Multiple blueprint variants can share one `name` (and thus one override dir) on
purpose. See `overrides/CLAUDE.md` and `docs/overrides.md`.

## Editing checklist

- Keep `name` lowercase, no spaces.
- Keep `ports` single-quoted.
- If you add a blueprint that needs custom install/update logic, it needs a
  matching `overrides/<name>/` directory — the `name` must line up.
