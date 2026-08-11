# Valheim server setup on KGSM

Valheim runs as a **native** KGSM instance. The dedicated server is a Steam application that
downloads anonymously, so no Steam account or credentials are involved.

Derived from Iron Gate's "A Guide to Dedicated Servers", rewritten for KGSM and verified against
Valheim dedicated server `l-0.221.12`.

## What these guides cover

Running a **vanilla Valheim** dedicated server on KGSM: installing it, the launch arguments that
configure it, the access-control lists, worlds, backups, updates, and what to check when it
misbehaves.

They do **not** cover:

- **Mods.** BepInEx, Valheim Plus and anything built on them replace the launch script, so a modded
  server is a **separate blueprint** rather than a setting — see [Mods](#mods) below for what that
  means in practice.
- **World transfer** from a single-player game, and editing worlds with external tools.
- **Playing the game** — bosses, biomes, building. These guides are about operating the server.

## Installing a Valheim server

```bash
kgsm install valheim --name my-valheim
```

KGSM fetches the dedicated server through SteamCMD and registers the instance, its firewall rule and
its console shortcut. It is a large download — expect a few minutes.

You do not install SteamCMD, log into Steam, copy a launch script, or edit one. The guides tell you
to make a private copy of `start_server.sh` because Steam overwrites it on update; KGSM does not use
that script at all, so there is nothing to protect. Launch settings live in the instance's
configuration instead.

## Set the password before anyone can reach it

**A Valheim server refuses to start without a password of at least 5 characters.** Because of that
the blueprint ships one — `CHANGE_ME` — purely so a fresh instance boots. It is a placeholder, and
every KGSM install starts with the same one.

Change it before the server is reachable from outside your network:

```bash
kgsm instances config-get my-valheim executable_arguments      # copy what it prints
kgsm instances config-set my-valheim 'executable_arguments=<the same list, with a new -password>'
kgsm restart my-valheim
```

Two rules the server enforces: the password is at least 5 characters, and it must not appear
anywhere inside the server name. A password that breaks either one stops the server at startup.

## The first start generates a world, and takes minutes

A new instance has no world, so the first start creates one. Generating locations alone took ~83
seconds on a quick host, and the server is not joinable until it finishes.

**`kgsm start` reports success as soon as the process is launched, not when the server is ready.**
Readiness is the `Opened Steam server` line, which comes after generation completes and the lobby
registration succeeds — well over a minute later on a first start:

```
Game server connected            ← networking is up; the world is NOT ready
Generating locations
Opened Steam server              ← ready for players
 Done generating locations, duration:82901.026 ms
```

So a fresh instance that KGSM says started will refuse players for a couple of minutes. Watch the
log for that line rather than trusting the start message:

```bash
kgsm start my-valheim
kgsm instances status my-valheim
```

Later starts load the existing world and come up quickly.

## Where everything lives

KGSM points the server at the instance's own `saves/` directory, so a Valheim instance is
self-contained — worlds do **not** go to `~/.config/unity3d/IronGate/Valheim` as they do in a manual
install:

| Path under the instance | Holds |
|---|---|
| `saves/worlds_local/` | The world (`<name>.db` and `<name>.fwl`) and its automatic backups |
| `saves/adminlist.txt` | Players with admin powers |
| `saves/bannedlist.txt` | Blocked players |
| `saves/permittedlist.txt` | Allow-list — **any entry locks out everyone else** |
| `install/` | The downloaded server |
| `<instance>.log` | The live server log |

```bash
kgsm instances info my-valheim
```

## Admins, bans and allow-lists

Valheim has no console, so moderation is these three files plus a restart. Each takes one platform
user ID per line, written `[Platform]_[UserID]` and case-sensitive. The server creates all three on
first start with a comment line explaining the format.

`kgsm instances kick|ban|unban` do not work here, and the blueprint declares no moderation commands,
because there is no command for KGSM to send.

Be careful with `permittedlist.txt`: adding one person converts the server to an allow-list and
refuses everyone else. Leave it empty unless that is what you want.

## Networking

Valheim is **UDP only**. A ready server binds both the configured port and the one above it —
`2456/udp` and `2457/udp` by default. The base port appears late, only once the world is generated,
so a server inspected mid-generation looks as though it uses `2457` alone. KGSM opens the instance's
declared ports when the server starts and closes them when it stops, so you never open one by hand.

Players outside your network still need the port forwarded on the router to this host. The exception
is `-crossplay`, which routes players through Iron Gate's relay servers and needs no forwarding —
see [`configuration.md`](configuration.md).

## Stopping, saving and backups

Valheim reads no console commands, so KGSM stops the server with a signal. The server handles it by
writing the world before exiting — but that write is not instant, and the supervisor allows 30
seconds before killing the process outright:

```
kb-vh2 did not stop gracefully in 30s; cgroup.kill
```

Saving a world that has just been generated for the first time can exceed that, and a killed server
writes nothing. A reload-and-stop of the same world took about 20 seconds and completed.

```bash
kgsm stop my-valheim
```

So: after the very first start, let the server reach `Opened Steam server` and give it a few minutes
before stopping it. Check the world was written:

```bash
ls <instance>/saves/worlds_local/       # want a .db, not just a .fwl
```

Once a `.db` exists, later stops are quick because the world is being updated rather than written
whole.

Back up through KGSM so the backup is registered and restorable:

```bash
kgsm stop my-valheim
kgsm instances create-backup my-valheim
kgsm instances backups my-valheim
kgsm start my-valheim
```

Valheim also keeps its own rolling world backups inside `saves/worlds_local/`, which is a different
thing from a KGSM backup and covers only the world.

## Updates

```bash
kgsm instances check-update my-valheim
kgsm stop my-valheim
kgsm instances update my-valheim
kgsm start my-valheim
```

Clients and the server must be on the same Valheim build, so an update disconnects players until
they update too.

## Mods

The blueprint runs the vanilla server. Mod frameworks such as BepInEx — and Valheim Plus on top of
it — install into the instance and replace the launch script, which means changing `executable_file`.
That field is protected on an existing instance (`config-set` refuses it), so a modded server is a
**separate blueprint** rather than an edit: copy the shipped one into
`~/.local/share/kgsm/blueprints/`, point it at the mod loader's script, and install from that. A
user blueprint shadows the system one of the same name.
