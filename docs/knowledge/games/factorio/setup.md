# Factorio server setup on KGSM

Factorio runs as a **native** KGSM instance. KGSM downloads the official headless build directly
from factorio.com — Factorio is not installed through Steam, so no Steam account or credentials are
involved.

Derived from the Factorio Wiki, "Multiplayer" (CC BY-NC-SA 3.0), rewritten for KGSM and verified
against Factorio headless 2.0.77.

## What these guides cover

Running a **vanilla Factorio headless** server on KGSM: installing it, the `server-settings.json`
options, admins, saves, backups, updates, and what to check when it misbehaves.

They do **not** cover:

- **Mods.** Factorio mods live in the server's `mods/` directory and must match on every client.
  Nothing here describes installing, updating or syncing them.
- **Scenarios and custom maps** beyond the world the server creates for itself, and map-generation
  settings (`map-gen-settings.json`, `map-settings.json`) beyond noting that they shape a world only
  at creation.
- **The Space Age expansion** and other DLC-specific settings.
- **Playing the game** — building, circuits, ratios. These guides are about operating the server.

## Installing a Factorio server

```bash
kgsm install factorio --name my-factorio
```

That one command does everything the standalone guides describe by hand:

- downloads the current stable headless build from factorio.com
- unpacks it into the instance's install directory
- **creates the initial save automatically** — a Factorio server refuses to start without one, so
  KGSM generates it during deploy
- registers the instance, its firewall rule, and its console shortcut

You do not create a user, unpack a tarball, write a service unit, or run `--create` yourself. Those
steps in the public guides describe a manual install and do not apply here.

Start it, then confirm it came up:

```bash
kgsm start my-factorio
kgsm instances status my-factorio
```

## What the instance looks like

Everything for one instance lives under a single directory:

| Path | Holds |
|---|---|
| `install/` | The unpacked Factorio headless build |
| `saves/` | Save files; the active one is named by the instance's `level_name` |
| `logs/` | Rotated logs |
| `<instance>.log` | The live server log — the first place to look when something is wrong |
| `<instance>.config.ini` | The instance's KGSM configuration |

Ask KGSM rather than memorising paths:

```bash
kgsm instances info my-factorio
```

## Naming the server, setting a password, going public

A fresh KGSM Factorio instance starts with **Factorio's built-in defaults**: no server name, no
description, no password, and no admins. KGSM does not create or pass a `server-settings.json`, so
wire one up if you want any of that.

1. Copy the example that ships with the game, from the instance's install directory:

   ```bash
   cp install/data/server-settings.example.json server-settings.json
   ```

2. Edit it — [`configuration.md`](configuration.md) explains every field.

3. Tell the instance to launch with it:

   ```bash
   kgsm instances config-set my-factorio \
     'executable_arguments=--start-server $instance_saves_dir/$instance_level_name --server-settings /path/to/server-settings.json'
   ```

   Keep the `--start-server $instance_saves_dir/$instance_level_name` portion exactly as it is —
   those variables are what point Factorio at this instance's own save. Use an absolute path for the
   settings file.

4. Restart, then **confirm the server is actually up**:

   ```bash
   kgsm restart my-factorio
   kgsm instances status my-factorio
   ```

   A syntax error in `server-settings.json` stops the server a second after launch while KGSM still
   reports the restart as successful. Check status, not the restart message.

## Networking

Factorio listens on **UDP only**; it never opens a TCP socket. KGSM opens the instance's ports when
the server starts and closes them when it stops, so you never open or forward a port by hand for a
KGSM instance.

For players outside your network the port still has to be forwarded on the router to this host.
Factorio's own guidance is that the router must **not randomise the source port** of packets leaving
the game port, or clients fail to connect even with a correct forward.

## Admins

Create `server-adminlist.json` beside the server log, listing the Factorio usernames that should
have console access:

```json
["playerone", "playertwo"]
```

Players promoted in-game through the console are written into this file automatically.

## Saves and worlds

The running world is the save named by the instance's `level_name`, inside `saves/`. Factorio
accepts that name with or without the `.zip` extension; the log notes when it falls back to the
`.zip`, which is normal and not an error.

Trigger a save without stopping the server:

```bash
kgsm instances save my-factorio
```

Back up through KGSM rather than copying files, so the backup is registered and restorable:

```bash
kgsm stop my-factorio
kgsm instances create-backup my-factorio
kgsm instances backups my-factorio
kgsm start my-factorio
```

## Mods

These guides do not cover installing or managing Factorio mods, and KGSM does nothing with them: the
blueprint installs the vanilla headless server and no more.

What is worth knowing as an operator is the constraint mods impose. Factorio requires **every client
to run exactly the same version and the same mod set as the server** — there is no partial match, so
adding, removing or updating a single mod locks out every player until they match it. Mods live in a
`mods/` directory inside the instance's install directory, and a KGSM update replaces the server
build without reconciling them.

## Version and updates

Factorio's version comes from factorio.com's release API, not Steam:

```bash
kgsm instances check-update my-factorio
kgsm stop my-factorio
kgsm instances update my-factorio
kgsm start my-factorio
```

Every client must run **exactly the same version and mods** as the server, so an update disconnects
players until they update too.
