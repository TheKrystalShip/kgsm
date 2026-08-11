# Terraria serverconfig.txt reference

`serverconfig.txt` sets a Terraria server's world, player limit, password, message of the day and
Journey-mode permissions. A KGSM Terraria instance does **not** use one unless you create it and
point the instance at it with `-config` — see [`setup.md`](setup.md).

It is a plain `key=value` file, one setting per line, with `#` starting a comment. Unset keys take
the game's default.

Derived from the Terraria Wiki, "Server" (CC BY-NC-SA 4.0), verified against Terraria Server 1.4.5.6.

## World

| Setting | Meaning |
|---|---|
| `world` | Absolute path of the world file to load |
| `worldname` | Name given to a world the server creates |
| `worldpath` | Directory holding worlds, when `world` is not an absolute path |
| `autocreate` | Generate the world if it is missing: `1` small, `2` medium, `3` large |
| `seed` | World seed used when generating |
| `difficulty` | `0` classic, `1` expert, `2` master, `3` journey |

KGSM passes the world arguments on the command line so the server uses the instance's own `saves/`
directory. Setting `world` or `worldpath` here as well gives two answers to the same question —
leave them to the launch arguments and keep this file for the rest.

`autocreate` only matters when the world file is absent. Once a world exists it is loaded as-is, and
`difficulty` and `seed` no longer do anything, because both are fixed at generation.

## Players and access

| Setting | Meaning |
|---|---|
| `maxplayers` | Connection limit, 1–255 |
| `password` | Password players must enter to join. Empty means anyone may join |
| `motd` | Message shown to a player on joining |
| `banlist` | Path to the ban list file |
| `secure` | `1` enables cheat protection |
| `language` | Server language, e.g. `en-US`, `de-DE`, `fr-FR`, `es-ES` |

## Network

| Setting | Meaning |
|---|---|
| `port` | Listening port |
| `upnp` | `1` asks the router to forward the port over UPnP |

Leave `port` to the blueprint and the instance: KGSM opens and closes the instance's declared ports
around its lifecycle, and a port set here that disagrees with what KGSM opened produces a server
nobody can reach.

Leave `upnp` off. Forwarding is owned by the host — a server that opens its own router mapping does
it outside KGSM's lifecycle, so the mapping outlives the server that asked for it.

## Performance

| Setting | Meaning |
|---|---|
| `npcstream` | How aggressively NPC updates are skipped; higher trades accuracy for CPU |
| `priority` | Process priority, `0` highest to `5` lowest |

Leave `priority` alone. KGSM's watchdog places each instance in its own cgroup, and the instance's
`cpu_priority` is the knob that expresses this — one set here fights it.

## Journey mode

Journey worlds accept a family of `journeypermission_*` settings — time, weather, spawn rate,
godmode and the rest — each taking `0` (nobody), `1` (host only) or `2` (everyone). They apply only
to a world generated with `difficulty=3`.

## Applying a change

The file is read **once, at startup**. Editing it while the server runs changes nothing until a
restart:

```bash
kgsm restart my-terraria
kgsm instances status my-terraria
```

Check status afterwards rather than trusting the restart message, and confirm a setting actually
took effect by asking the server:

```bash
kgsm instances input my-terraria "maxplayers"
kgsm instances input my-terraria "motd"
```

## Command-line switches

Terraria accepts the same settings as launch switches — `-port`, `-maxplayers`, `-password`,
`-world`, `-worldname`, `-autocreate`, `-seed`, `-secure`, `-noupnp`. KGSM already uses the world
switches, and mixing the two forms for one setting makes which value wins depend on argument order.
Keep the world on the command line and everything else in the config file.
