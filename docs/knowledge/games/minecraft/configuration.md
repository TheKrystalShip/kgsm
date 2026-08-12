# Minecraft server.properties reference

`server.properties` is Minecraft's configuration file. It lives in the instance's `install/`
directory, is generated on first start with defaults, and holds around 65 settings. It is a plain
`key=value` file; lines starting `#` are comments.

Derived from the Minecraft Wiki, "Tutorial:Setting up a Java Edition server" (CC BY-NC-SA 3.0).

## World

| Setting | Meaning |
|---|---|
| `level-name` | The world folder, inside the install directory. Renaming it starts a **new** world; the old folder is left untouched |
| `level-seed` | Seed used when the world is generated. Ignored once it exists |
| `level-type` | World generator, e.g. `minecraft:normal`, `minecraft:flat` |
| `hardcore` | Death is permanent and the player is put in spectator |
| `gamemode` | Default mode for new players: `survival`, `creative`, `adventure`, `spectator` |
| `force-gamemode` | Put returning players back into the default mode on join |
| `difficulty` | `peaceful`, `easy`, `normal`, `hard` |
| `spawn-protection` | Radius around spawn only operators may build in. `0` disables it |

`level-seed` and `level-type` apply at generation. On an existing world they do nothing — to use a
new seed, change `level-name` as well so a fresh world is created.

## Players and access

| Setting | Meaning |
|---|---|
| `max-players` | Connection limit |
| `online-mode` | Verify every player against Mojang's authentication servers |
| `white-list` | Refuse anyone not in `whitelist.json` |
| `enforce-whitelist` | Kick players already online who are not whitelisted |
| `pvp` | Allow players to damage each other |
| `motd` | The line shown under the server name in the client's list |
| `player-idle-timeout` | Minutes before an idle player is kicked. `0` never kicks |

**Leave `online-mode=true` unless you know exactly why not.** With it off, the server accepts any
username without checking it against Mojang, so anyone may connect claiming to be an operator you
have already opped. It exists for isolated networks, not for public servers.

## Networking

| Setting | Meaning |
|---|---|
| `server-port` | The listening port |
| `server-ip` | Which interface to bind. **Leave it empty** so the server binds all of them |
| `enable-rcon` / `rcon.port` / `rcon.password` | Remote console |
| `enable-query` / `query.port` | The GS4 query listener, used by server-list sites |
| `enable-status` | Answer client pings at all; off hides the server from the multiplayer list |
| `network-compression-threshold` | Packet size above which traffic is compressed |

Change `server-port` only in step with the instance's declared ports: KGSM opens and closes what the
blueprint declares around the instance's lifecycle, so a port set only here produces a server nobody
can reach.

`enable-query` turns on a **UDP** listener on the query port. The instance already opens both
protocols on its port, so enabling query needs no firewall change.

Setting `server-ip` to a specific address is a common way to make a server unreachable — an empty
value is almost always what you want.

## Performance

| Setting | Meaning |
|---|---|
| `view-distance` | Chunks sent to each player. The single biggest lever on memory and bandwidth |
| `simulation-distance` | Chunks where entities and blocks actually tick |
| `max-tick-time` | Milliseconds a tick may take before the watchdog kills the server. `-1` disables it |
| `sync-chunk-writes` | Write chunks synchronously; safer, slower |
| `max-world-size` | World border limit, in blocks |

Lower `view-distance` before adding heap. A busy server is far more often short of chunk budget than
of memory, and the heap size is a launch argument rather than a setting here — see
[`setup.md`](setup.md).

`max-tick-time` is why a server that freezes sometimes exits by itself, reporting that a single tick
took too long.

## Applying a change

The file is read **once, at startup**, and rewritten at startup with the ordering and comments
normalised — that rewrite keeps your values, so editing it while the server runs is safe and takes
effect at the next restart:

```bash
kgsm restart my-minecraft
kgsm instances status my-minecraft
```

Some settings can also be changed live from the console, and those changes are written back:

```bash
kgsm instances input my-minecraft "/difficulty hard"
kgsm instances input my-minecraft "/whitelist on"
```

## The JSON files beside it

These are managed by the server, and each has a console command that edits it — preferring the
command avoids hand-editing JSON while the server holds it open.

| File | Console command |
|---|---|
| `ops.json` | `/op <name>`, `/deop <name>` |
| `whitelist.json` | `/whitelist add\|remove <name>`, `/whitelist reload` |
| `banned-players.json` | `/ban <name>`, `/pardon <name>` — or KGSM's own `kgsm instances ban\|unban` |

An operator level in `ops.json` runs 1–4, where 4 is full access including `/stop`.

`whitelist.json` only takes effect when `white-list=true`; adding names to it while that is `false`
changes nothing, which is the usual reason a whitelist "does not work".
