# Terraria server setup on KGSM

Terraria runs as a **native** KGSM instance. KGSM downloads the official dedicated-server build
directly from terraria.org — Terraria's server is not distributed through Steam, so no Steam account
or credentials are involved.

Derived from the Terraria Wiki, "Server" (CC BY-NC-SA 4.0), rewritten for KGSM and verified against
Terraria Server 1.4.5.6.

## What these guides cover

Running a **vanilla Terraria** dedicated server on KGSM: installing it, the `serverconfig.txt`
settings, worlds, moderation, backups, updates, and what to check when it misbehaves.

They do **not** cover:

- **tModLoader and modded servers.** tModLoader is a different server program from a different
  source, so it is a **separate blueprint** rather than a setting on this one — not something you
  switch on for an existing instance.
- **Journey-mode research and power settings** beyond noting that a Journey world is chosen at
  creation.
- **World editing** with external tools such as TEdit.
- **Playing the game** — bosses, progression, building. These guides are about operating the server.

## Installing a Terraria server

```bash
kgsm install terraria --name my-terraria
```

That one command does everything the standalone guides describe by hand:

- resolves the current server build from terraria.org's release API
- downloads and unpacks the archive
- flattens the versioned folder and keeps only the Linux payload, discarding the Windows and Mac
  copies the archive also ships
- makes the server binary executable

You do not install `unzip`, `wget` or `tmux`, unpack anything, or `chmod` a binary. Nor do you need
a terminal multiplexer: KGSM supervises the process and gives you a console channel, so the guides'
`tmux` sections describe a problem KGSM has already solved.

Start it, then confirm it came up:

```bash
kgsm start my-terraria
kgsm instances status my-terraria
```

## The first start generates a world, and takes minutes

A new instance has no world, so the first start creates one before it will accept players. The log
fills with generation progress ("Desertification — 52.8%") and the server is not listening yet.
This is normal, and it is the single most common reason a first start looks hung.

A large world takes over a minute on a quick host. The server is ready when the log reaches:

```
Listening on port 7777
: Server started
```

Ask KGSM rather than reading the log directly:

```bash
kgsm instances status my-terraria
```

## Where the world lives

KGSM points the server at the instance's own `saves/` directory, so worlds do **not** go in
`~/.local/share/Terraria/Worlds/` as they do in a manual install. The active world is the file named
by the instance's `level_name`, and it has no file extension.

```bash
kgsm instances info my-terraria       # shows the instance's directories
```

The instance keeps everything under one directory: `install/` for the game files, `saves/` for
worlds, `logs/`, the live `<instance>.log`, and `<instance>.config.ini` for KGSM's own settings.

## Configuring the server

A fresh instance runs with Terraria's built-in defaults: no message of the day, no password, and the
default player limit. Terraria reads those from a `serverconfig.txt`, which KGSM does not create or
pass, so wire one up if you want them.

1. Write a `serverconfig.txt` in the instance directory. Comment lines start with `#`:

   ```
   maxplayers=12
   motd=Welcome
   password=changeme
   ```

2. Tell the instance to launch with it, keeping the world arguments intact:

   ```bash
   kgsm instances config-set my-terraria \
     'executable_arguments=-config /path/to/serverconfig.txt -world $instance_saves_dir/$instance_level_name -autocreate 3 -worldname $instance_level_name'
   ```

   The `$instance_*` variables are what point the server at this instance's own world — keep them.
   Use an absolute path for the config file.

3. Restart, then **confirm the server is actually up**:

   ```bash
   kgsm restart my-terraria
   kgsm instances status my-terraria
   ```

[`configuration.md`](configuration.md) covers what each setting does.

## Networking

Terraria listens on **TCP**. KGSM opens the instance's ports when the server starts and closes them
when it stops, so you never open or forward a port by hand for a KGSM instance.

For players outside your network the port still has to be forwarded on the router to this host.

## Console commands

Send commands through KGSM rather than to a terminal:

```bash
kgsm instances input my-terraria "playing"     # who is connected
kgsm instances input my-terraria "say hello"   # broadcast to the server
kgsm instances input my-terraria "time"
```

`help` lists everything the server accepts. Useful ones: `playing`, `say`, `time`, `dawn`/`noon`/
`dusk`/`midnight`, `settle` (settle liquids), `motd`, `password`, `maxplayers`, `version`.

Do **not** use the `exit` console command to stop the server — that bypasses KGSM's lifecycle. Use:

```bash
kgsm stop my-terraria
```

## Saving and backups

Terraria saves periodically and on a clean shutdown. Force one without stopping:

```bash
kgsm instances save my-terraria
```

Back up through KGSM so the backup is registered and restorable:

```bash
kgsm stop my-terraria
kgsm instances create-backup my-terraria
kgsm instances backups my-terraria
kgsm start my-terraria
```

## Moderation

Terraria's server moderates from its own console, so send the commands through the console channel:

```bash
kgsm instances input my-terraria "kick PlayerName"
kgsm instances input my-terraria "ban PlayerName"
```

Banned players are recorded in `banlist.txt`, and removing someone from that file is what un-bans
them — the server offers no un-ban command.

KGSM's own moderation verbs (`kgsm instances kick|ban|unban`) do **not** work here: they require the
blueprint to declare the game's moderation commands, and Terraria's declares none. Asking for one
answers *"does not support 'kick'"* rather than doing anything.

## Mods and tModLoader

These guides do not cover modded Terraria, and the shipped blueprint cannot run it. It installs the
**vanilla** dedicated server from terraria.org.

tModLoader is a different server program, distributed separately, so running it means a **separate
blueprint** rather than a setting on this one: copy the shipped blueprint into
`~/.local/share/kgsm/blueprints/`, point it at tModLoader with an override that downloads it, and
install from that. A user blueprint shadows the system one of the same name.

As with vanilla, every client must run the same version as the server — and with mods, the same mod
set too.

## Version and updates

The server version comes from terraria.org's release API:

```bash
kgsm instances check-update my-terraria
kgsm stop my-terraria
kgsm instances update my-terraria
kgsm start my-terraria
```

Clients and the server must be on the same Terraria version; players on an older build are refused.
