# Minecraft server setup on KGSM

Minecraft Java Edition runs as a **native** KGSM instance. The server is a Java program, so the host
needs a JRE; the server itself comes straight from Mojang's version manifest, with no Steam or
account involved.

Derived from the Minecraft Wiki, "Tutorial:Setting up a Java Edition server" (CC BY-NC-SA 3.0),
rewritten for KGSM and verified against Minecraft server 26.2 on OpenJDK 26.

## What these guides cover

Running a **vanilla Minecraft Java Edition** server on KGSM: installing it, the `server.properties`
settings, moderation, backups, updates, and what to check when it misbehaves.

They do **not** cover:

- **Modpacks and modded servers** — Forge, NeoForge, Fabric, Quilt. A modded server replaces the
  server jar and is downloaded from somewhere other than Mojang's manifest, so it is a **separate
  blueprint**, not a setting on this one. Copy the shipped blueprint into
  `~/.local/share/kgsm/blueprints/`, point it at the loader's jar with a matching override for the
  download, and install from that.
- **Server platforms** — Paper, Spigot, Purpur, Bukkit — and their plugins. Same reasoning: a
  different jar from a different source, so a different blueprint.
- **Proxies** — BungeeCord, Velocity, and multi-server networks.
- **Bedrock Edition.** This is Java Edition only; Bedrock is a different server entirely.
- **Datapacks, resource packs, and in-game commands** beyond the handful used for administration.

Nothing here is a judgement about those — they are simply outside what the shipped blueprint runs,
and a guide that guessed at them would be worse than silence.

## Installing a Minecraft server

```bash
kgsm install minecraft --name my-minecraft
```

KGSM resolves the current release from Mojang's manifest, downloads the server jar, and registers
the instance, its firewall rule and its console shortcut.

**Installing accepts Mojang's EULA on your behalf.** The public guides describe running the server
once, watching it exit, editing `eula.txt` from `false` to `true`, and running it again — KGSM
writes `eula=true` during deploy, so a fresh instance starts first time. By installing you are
agreeing to Mojang's terms exactly as if you had edited that file yourself.

You also do not write a `start.sh`, pick JVM flags, or `chmod` anything.

Start it, then confirm it came up:

```bash
kgsm start my-minecraft
kgsm instances status my-minecraft
```

A healthy server logs `Done (0.330s)! For help, type "help"`. First start is quick — Minecraft
generates only the spawn area, not a whole world, so it is ready in seconds rather than minutes.

## Java version

The server needs a JRE new enough for the Minecraft release: modern versions want Java 21 or newer,
and older Minecraft releases run fine on newer Java. Check what the host has:

```bash
java -version
```

A too-old JRE fails at startup with an `UnsupportedClassVersionError`. A very new JRE is generally
fine, but it may print deprecation warnings for GC flags the instance launches with — those are
warnings from the JVM, not errors, and the server starts normally.

## Where the world lives

Minecraft keeps its world **inside the install directory**, in a folder named by `level-name` in
`server.properties` (`world` by default). It does not use the instance's `saves/` directory, and the
instance's own `level_name` setting has no effect on a Minecraft server.

| Path under the instance | Holds |
|---|---|
| `install/world/` | The world — region data, player data, `level.dat` |
| `install/server.properties` | Server settings |
| `install/ops.json` | Operators |
| `install/whitelist.json` | Allow-list, used when `white-list=true` |
| `install/banned-players.json` | Bans |
| `install/logs/` | Minecraft's own rotated logs |
| `<instance>.log` | The live console output KGSM captures |

```bash
kgsm instances info my-minecraft
```

Because the world sits inside `install/`, a KGSM backup captures it as part of that directory — the
archive therefore also carries the jar and libraries and is correspondingly large.

## Configuring the server

`server.properties` is generated on first start and holds around 65 settings. It is read once, at
startup, so a change needs a restart. See [`configuration.md`](configuration.md) for the settings
that matter.

```bash
kgsm restart my-minecraft
kgsm instances status my-minecraft
```

## Memory

The instance launches with a fixed Java heap and a tuned set of G1 garbage-collector flags. If the
host cannot spare that much, or the server needs more, change the heap in the instance's launch
arguments:

```bash
kgsm instances config-get my-minecraft executable_arguments      # copy what it prints
kgsm instances config-set my-minecraft 'executable_arguments=<the same list, with new -Xmx/-Xms>'
kgsm restart my-minecraft
```

`-Xmx` is the ceiling and `-Xms` the amount claimed at startup. Setting `-Xmx` above what the host
can actually give is worse than setting it low: the JVM will accept the flag and then be killed by
the kernel when it tries to use the memory.

## Console commands

Send commands through KGSM rather than to a terminal:

```bash
kgsm instances input my-minecraft "/list"           # who is connected
kgsm instances input my-minecraft "/say hello"      # broadcast
kgsm instances input my-minecraft "/op PlayerName"  # grant operator
kgsm instances input my-minecraft "/whitelist add PlayerName"
```

Do not use the `/stop` console command to shut the server down — that stops it underneath KGSM
rather than through it. Use `kgsm stop`, which sends the same command as part of the instance
lifecycle and returns in about a second with all chunks saved.

## Moderation

Minecraft addresses players by username, and KGSM's moderation verbs work directly:

```bash
kgsm instances kick my-minecraft "PlayerName"
kgsm instances ban my-minecraft "PlayerName"
kgsm instances unban my-minecraft "PlayerName"
```

`ban` and `unban` work on a player who is not connected — Minecraft keeps the ban list keyed on the
account. `kick` only affects someone currently online, and reports `No player was found` otherwise.

## Networking

Minecraft listens on **TCP**. The optional GS4 query listener uses UDP on the same port number and
is off by default, which is why nothing appears on UDP on a stock server.

KGSM opens the instance's declared ports when the server starts and closes them when it stops, so
you never open one by hand. Players outside your network still need the port forwarded on the router
to this host.

## Modpacks, plugins and modded servers

These guides do not cover installing modpacks, mods or plugins, and the shipped blueprint cannot run
them. It launches the **vanilla** server jar downloaded from Mojang's version manifest.

Every modded or alternative server — Forge, NeoForge, Fabric, Quilt, and the Paper/Spigot/Purpur
family — is a different jar obtained from somewhere other than Mojang. Because the jar and where it
comes from are properties of the blueprint rather than settings on an instance, running one means a
**separate blueprint**: copy the shipped one into `~/.local/share/kgsm/blueprints/`, give it an
override that downloads the loader's jar, and install from that. A user blueprint shadows the system
one of the same name.

The same applies to proxies such as BungeeCord and Velocity, and to Bedrock Edition, which is a
different server program entirely.

## Saving, backups and updates

```bash
kgsm instances save my-minecraft            # force a save without stopping

kgsm stop my-minecraft
kgsm instances create-backup my-minecraft
kgsm instances backups my-minecraft
kgsm start my-minecraft

kgsm instances check-update my-minecraft
kgsm instances update my-minecraft          # instance must be stopped
```

Updating replaces the server jar. Clients must be on the same Minecraft version as the server, so an
update locks out players until they switch versions too.
