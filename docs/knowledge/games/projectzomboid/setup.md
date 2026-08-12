# Project Zomboid server setup on KGSM

Project Zomboid runs as a **native** KGSM instance. The dedicated server is a Java program shipped
with its own bundled JRE, downloaded anonymously through SteamCMD — no Steam account or credentials
are involved, and the host does not need its own Java.

## What these guides cover

Running a Project Zomboid dedicated server on KGSM: installing it, the admin account, the
`.ini` server settings, accounts and moderation, Workshop mods, backups, updates, and what to check
when it misbehaves.

They do **not** cover:

- **Individual sandbox and difficulty values** — zombie population, loot rarity, day length, and the
  rest of `<servername>_SandboxVars.lua`. The guides say where that file lives and when it is read,
  because that is what decides whether an edit does anything; they do not go through its settings
  one by one.
- **Choosing or debugging individual mods.** Mod *installation* is covered — it is a first-class
  server feature here — but which mods to run, mod load order, and errors thrown from inside a mod
  are the mod author's territory.
- **Custom maps and map load order** beyond noting which setting selects them.
- **Playing the game** — survival, crafting, base building. These guides are about operating the
  server.

## Installing a Project Zomboid server

```bash
kgsm install projectzomboid --name my-pz
```

KGSM fetches the dedicated server through SteamCMD and registers the instance, its firewall rule and
its console shortcut. Expect a **large** download: a vanilla install measures **6.9 GB** and takes
several minutes. You do not install SteamCMD, install a JRE, log into Steam, or edit `start-server.sh`.

**This server is memory-hungry — plan for 8 GB and prefer 16 GB.** A vanilla server was killed by a
6 GiB cgroup cap while still loading assets, holding ~1.1 GB of heap and ~5.1 GB of shared memory;
mods add to both. On a host that cannot spare that, cap the instance so a shortfall kills this server
alone rather than the host:

```bash
kgsm instances config-set my-pz 'memory_cap_mb=8192'
```

The Java heap is separate and lives in `install/ProjectZomboid64.json` (`-Xmx`), and it is the
smaller half — lowering it does not make the server fit in much less.

## Change the admin password before anyone can reach the server

A server with no admin account **prompts for one on stdin** and waits there indefinitely. A KGSM
instance has no terminal attached, so nothing answers; `kgsm start` reports success and
`kgsm instances status` reports **Active**, both truthfully, because the process really is running.
It is simply never going to finish starting.

The blueprint avoids that by creating the account non-interactively, with
`-adminusername admin -adminpassword CHANGE_ME_ON_FIRST_START` in the launch arguments. The log
reads `Administrator account 'admin' created.` and startup continues.

**That password is a placeholder and it is the same on every KGSM install.** A Project Zomboid admin
can do anything in-game — teleport, spawn, ban, change any setting — so change it before the server
is reachable by anyone you do not trust:

```bash
kgsm instances config-get my-pz executable_arguments      # copy what it prints
kgsm instances config-set my-pz \
  'executable_arguments=-servername $instance_level_name -cachedir=$instance_saves_dir -adminusername admin -adminpassword yourpassword'
kgsm restart my-pz
```

Keep `-servername $instance_level_name` and `-cachedir=$instance_saves_dir` exactly as they are —
those variables are what tie the server to this instance's own files.

Two things worth knowing about how this works:

- **The argument only creates the account; it does not change one that exists.** Once
  `saves/db/<servername>.db` holds an `admin` row, editing `-adminpassword` does nothing. Change it
  from the console instead, which works on a running server:

  ```bash
  kgsm instances input my-pz "setpassword \"admin\" \"yourpassword\""
  ```

- **The password is visible** in the instance config and in the process list to anyone with an
  account on this host.

If you have an instance that predates this and is sitting on the prompt, answer it through the
console channel. Send the password, wait for `Confirm the password:` in the log, then send it again:

```bash
kgsm instances input my-pz "yourpassword"
# wait for "Confirm the password:" in the log
kgsm instances input my-pz "yourpassword"
```

## Confirming it actually came up

```bash
kgsm start my-pz
kgsm instances status my-pz
```

The server is ready when the log reaches:

```
*** SERVER STARTED ****
```

A first start generates the world before it will accept anyone: about 30 seconds on a quick host for
a vanilla server, and considerably longer with mods, which are downloaded during startup. Everything
before that line is normal progress, including a long wall of asset loading.

Two log lines that look alarming on every single start and mean nothing:

- `ERROR: ld.so: object 'libjsig.so' from LD_PRELOAD cannot be preloaded ... ignored.` — the shipped
  `start-server.sh` preloads a JVM signal library that is not in the image. The server runs fine.
- A `java.nio.file` stack trace from `DebugFileWatcher.registerDir` — the file watcher failing to
  register directories. Also harmless.

## Where everything lives

KGSM passes `-cachedir=$instance_saves_dir`, so the folder Project Zomboid guides call `~/Zomboid`
is the instance's own `saves/` directory. The instance is self-contained and nothing is written to
your home directory.

| Path under the instance | Holds |
|---|---|
| `saves/Server/<servername>.ini` | The server settings |
| `saves/Server/<servername>_SandboxVars.lua` | World and difficulty settings |
| `saves/Server/<servername>_spawnpoints.lua`, `_spawnregions.lua` | Where players spawn |
| `saves/Saves/Multiplayer/<servername>/` | The world |
| `saves/db/<servername>.db` | The account database — users, roles, bans |
| `saves/Logs/` | The game's own dated logs, split by kind |
| `saves/backups/` | Project Zomboid's own automatic backups |
| `install/` | The downloaded server, its bundled JRE, and Workshop mods |
| `<instance>.log` | The live console output KGSM captures |

```bash
kgsm instances info my-pz
```

**`<servername>` is the instance's `level_name`, not its name.** KGSM launches with
`-servername $instance_level_name`, so an instance called `my-pz` whose `level_name` is `default`
keeps its files under `default.ini`, `default.db` and so on. Two instances can therefore both use
`default` without colliding, because each has its own `saves/` directory.

## The game keeps its own logs, and they are better than the console

The console log is one undifferentiated stream. `saves/Logs/` splits the same events into files by
kind and by server session, and they survive restarts:

| File | Holds |
|---|---|
| `*_user.txt` | Connects and disconnects, with the Steam ID **and** the player name |
| `*_admin.txt` | Admin actions |
| `*_chat.txt` | Chat |
| `*_cmd.txt` | Commands players ran |
| `*_pvp.txt` | PVP incidents |
| `*_DebugLog-server.txt` | The full engine log |

`*_user.txt` is the one to reach for when asking who was on and when.

## Console commands

Send commands through KGSM rather than to a terminal:

```bash
kgsm instances input my-pz "players"                  # who is connected
kgsm instances input my-pz "servermsg \"back in 5\""  # broadcast
kgsm instances input my-pz "showoptions"              # dump current settings
kgsm instances input my-pz "help"                     # the authoritative command list
```

`help` prints every command the running server accepts, with usage. That list is the truth for your
build; [`configuration.md`](configuration.md) covers the ones that change settings.

Answers come back **in the instance log, not to your shell** — `kgsm instances input` sends the
command and returns. Read the log for the result.

Do **not** use the `quit` console command to shut the server down; that stops it underneath KGSM
rather than through it. Use `kgsm stop my-pz`, which sends the same command as part of the lifecycle.
A clean stop takes about 12 seconds and ends with `Shutdown handling finished`.

## Accounts and moderation

Project Zomboid addresses players by their in-game **user name**, and KGSM's moderation verbs work
directly:

```bash
kgsm instances kick my-pz "PlayerName"
kgsm instances ban my-pz "PlayerName"
kgsm instances unban my-pz "PlayerName"
```

An unknown name is reported in the log as `User PlayerName doesn't exist.` rather than as an error
from KGSM.

Accounts live in `saves/db/<servername>.db` and carry a **role**: `banned`, `user`, `priority`,
`observer`, `gm`, `moderator`, `admin`. A new player is created as `user`. Promote from the console:

```bash
kgsm instances input my-pz "setaccesslevel \"PlayerName\" \"moderator\""
```

See [`configuration.md`](configuration.md) for the whitelist and for banning by Steam ID or IP, which
are separate lists from the account roles.

## Mods

Unlike most games, the Project Zomboid server **downloads its own Workshop mods** — no separate
blueprint and no manual file copying. Two settings in the server `.ini` do it, and both are needed:

- `WorkshopItems` — the semicolon-separated Workshop **item IDs** to download
- `Mods` — the semicolon-separated **mod loading IDs** to actually enable

They are different identifiers, and listing an item in one but not the other is the usual reason a
mod downloads and then does nothing. Details and where to find each ID are in
[`configuration.md`](configuration.md).

Mods are downloaded at startup into `install/steamapps/workshop/content/108600/<id>/`, which is why a
modded server takes noticeably longer to start than a vanilla one. Every client must have the same
mods as the server.

A modded server logs a great deal of noise it did not log before — hundreds of lines like
`ERROR: template "SomeCarPart" not found` and `WARN: no such mesh ...`. Those come from inside mods,
not from KGSM or the server, and a running server with a wall of them is normal.

## Saving, backups and updates

```bash
kgsm instances save my-pz            # force a save without stopping

kgsm stop my-pz
kgsm instances create-backup my-pz
kgsm instances backups my-pz
kgsm start my-pz

kgsm instances check-update my-pz
kgsm instances update my-pz          # instance must be stopped
```

Project Zomboid **also** keeps its own backups in `saves/backups/`, taken on start and on version
change. Those are a different thing from a KGSM backup: they cover the save only, they are pruned on
the game's own schedule, and KGSM does not know about them.

Clients must be on the same build as the server, so an update locks out players until they switch
too. Note that the instance ships with `auto_update=true`, which means an update can arrive at the
next start without you asking for one.
