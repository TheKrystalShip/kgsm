# Instances

An instance is one installed game server: a registry entry, a working directory inside a library, a config
file and a generated management script.

## Identity

An id is `<blueprint>-<suffix>` with a random suffix of `Instances:IdSuffixLength` characters, or whatever
`--id` names: a letter or digit, then letters, digits, dots, underscores and hyphens, up to 64 characters.
Ids are unique across the host. The registry is `instances.json` in the data home, written under the
global lock: id, blueprint, library, working directory. An instance in an offline library stays listed and
keeps its id.

## Files

Under `<library>/instances/<blueprint>/<id>`:

| Path | What it is |
|---|---|
| `install/`, `saves/`, `logs/`, `temp/`, `events/` | the game's files, its saves, its output, scratch, and (containers) the directory bind-mounted at `/run/kgsm` |
| `<id>.config.json` | the instance's config; carries `schemaVersion` |
| `<id>.manage.sh` | the generated management script |
| `<id>.docker-compose.yml` | the rendered compose file (containers) |
| `<id>.log`, `.<id>.pid`, `.<id>.sock` | the instance's log, pid file and console input pipe |
| `.<id>.version`, `.<id>.latest` | the installed version and the last upstream version an update check found |

Every path inside the working directory is derived from the registry; none is stored, so a move or an
import rewrites no path. Only the backups directory, outside the tree, is stored in the config.

## Config

`kgsm instance config list|get|set <instance>` reads and changes the instance's config keys, which are spelled
in camelCase as the config file spells them; most are settable (commands, timeouts, port forwarding, backup
compression). `kgsm instance note set|clear` keeps a plain-text note with its
author and time.

## The management script

The script does what changes an instance and must work with the binary absent: start and stop without the
watchdog, console input, download, deploy, update, backup creation and restore. Each action has one
implementation, the script's; the binary decides, brackets and journals.

A script records the template version and the digest of the hooks it was built from. A read never
regenerates a script and no read writes anything. `kgsm instance repair <instance>` regenerates one, and
`kgsm instance repair --all` regenerates only the stale ones; the package runs the latter after every
upgrade.

## Backups

`kgsm backup create|list|restore|delete|prune|pin|unpin`. A backup is a tar archive with a manifest, in the
instance's backups directory. A restore takes a safety backup of what is there first. `prune` keeps the
newest few; pinned backups and the newest pre-update backup are never pruned.

## Update

`kgsm instance check-update` asks whether a newer version exists (steamcmd for Steam games, or the game's
`kgsm_hook_latest_version`). `kgsm instance update` backs the instance up, stops it if it runs, downloads,
deploys and restarts it.

## Moving between nodes

`kgsm transfer export|import` move a stopped instance to another node. kgsm-api drives the pair; an
instance in transit holds a transfer lock that `kgsm instance unlock` releases.
