# Project Zomboid server troubleshooting

Symptoms and what actually causes them on a KGSM-managed Project Zomboid server.

Two sources of evidence, and the second is usually better:

```bash
kgsm instances info my-pz        # shows the live log path
```

- `<instance>.log` — the live console output, one undifferentiated stream.
- `saves/Logs/` — the game's own logs, split by kind and by session, and they survive restarts.
  `*_user.txt` for connects and disconnects, `*_DebugLog-server.txt` for everything.

## The server started but never becomes joinable

Almost always the **admin-password prompt**. On an instance with no admin account, the server stops
and waits for one to be typed:

```
User 'admin' not found, creating it
Command line admin password: null
Enter new administrator password:
```

Nothing is attached to answer it, so it waits indefinitely. `kgsm start` reported success and
`kgsm instances status` reports **Active**, both correctly — the process is running, it is just never
going to finish starting. The giveaway is that the log ends on that line and stops moving.

Answer it through the console channel, twice — the second time for the confirmation:

```bash
kgsm instances input my-pz "yourpassword"
# wait for "Confirm the password:" to appear in the log
kgsm instances input my-pz "yourpassword"
```

Better, set it in the launch arguments so the prompt never happens — see
[`setup.md`](setup.md#the-first-start-blocks-on-an-admin-password).

## The server is killed a few seconds in, over and over

Look for this in the log:

```
start-server.sh: line 18: 617868 Killed  LD_PRELOAD="${LD_PRELOAD}:${JSIG}" ./ProjectZomboid64 "$@"
```

`Killed` is SIGKILL, and on a host that is short of memory it is the kernel's OOM killer. Confirm it,
because nothing in the game's own log will say so:

```bash
journalctl -k --since "20 min ago" | grep -i "out of memory"
```

A real record from this host, killed while loading the world:

```
Out of memory: Killed process 617868 (ProjectZomboid6) total-vm:137575456kB,
anon-rss:1098132kB, shmem-rss:6979504kB
```

Note `constraint=CONSTRAINT_NONE ... global_oom` in the companion line: that is the **host** running
out of memory, not this instance hitting a cap. The instance's own `memory_cap_mb` was `0`
(uncapped), so nothing local limited it — Project Zomboid was simply the biggest thing the kernel
could reclaim. Ignore `total-vm`, which is address space rather than memory; the two figures that
matter are `anon-rss` and `shmem-rss`.

What to do, in order:

1. **Free memory on the host**, or run fewer servers at once. This is a host-capacity problem before
   it is a Project Zomboid problem.
2. **Lower the Java heap.** The shipped `install/ProjectZomboid64.json` asks for `-Xmx8g`. Editing
   that file changes what the JVM claims — but note it caps the *heap* only, and in the record above
   the heap (`anon-rss`, ~1.1 GB) was the small half. Most of the footprint was shared memory.
3. **Cap the instance** so it is killed alone instead of taking the host down with it:

   ```bash
   kgsm instances config-set my-pz 'memory_cap_mb=8192'
   ```

   The watchdog applies this as the cgroup's `memory.max`. Verified: with a cap set, the kernel
   records `constraint=CONSTRAINT_MEMCG` against that one instance's cgroup instead of the
   `global_oom` it records without one — the difference between losing this server and losing
   whatever else the host happens to be running.

   Set it above what the server actually needs. A 6 GiB cap killed a **vanilla** server during asset
   loading, holding ~1.1 GB `anon-rss` and ~5.1 GB `shmem-rss` at the moment it died, which is why
   the blueprint advises 8 GiB as a minimum and 16 GiB as comfortable. A modded server wants more
   again.

## An older instance reports a crash as a clean exit

Project Zomboid's **shipped** `start-server.sh` launches the JVM and then ends with an unconditional
`exit 0`, so whatever happens to the server, the script succeeds. A killed JVM reaches the watchdog
as `exited cleanly (exit 0); restart #1`, and an OOM crash loop reads as a run of clean exits — the
watchdog is not inventing a status, the wrapper is discarding one.

KGSM replaces that script on every install and update with one that `exec`s the server, so the
process the watchdog supervises **is** the server and its exit code is the server's by construction.
A killed server now reports `137`.

An instance created before that change keeps the shipped script until its next deploy:

```bash
kgsm stop my-pz
kgsm instances update my-pz          # rewrites the launcher
kgsm start my-pz
```

Until then, treat "exited cleanly" on this game as no evidence at all: read the log for a `Killed`
line or a stack trace. Either way, expect a crash loop to back off between attempts (1s, 2s, 4s, 8s)
until the watchdog gives up at `crash_max_restarts`.

The launcher is rewritten from the override on every deploy, so editing it in place does not last —
and it is deliberately identical to the shipped one otherwise, including the `libjsig.so` preload
that fails and is ignored.

## Nobody can join

1. **Is it up?** `kgsm instances status my-pz`, and the log reached `*** SERVER STARTED ****`.
2. **Is it listening?** Project Zomboid is **UDP only** and binds **two** ports — `DefaultPort` and
   `UDPPort`. Both must be present:

   ```bash
   ss -lun | grep -E '16261|16262'
   ```

   Nothing ever appears on TCP. A missing TCP listener is normal and proves nothing.
3. **Is the router forwarding?** UDP, both ports, to this host.
4. **Do the ports still match the blueprint?** Changing `DefaultPort` or `UDPPort` in the `.ini`
   without reinstalling leaves KGSM opening a range the server no longer uses.
5. **Is `Open=false`?** Then the server is a whitelist and only accounts an admin created with
   `adduser` may connect.
6. **Is there a `Password`?** Players need it, and it is separate from the admin password.

Do not open the port by hand. KGSM opens an instance's ports when it starts and closes them when it
stops; a manually added rule sits outside that lifecycle.

## The port forward disappears while the server is running

Two systems are fighting over the same router mapping. Project Zomboid's `.ini` ships with
`UPnP=true`, and KGSM's watchdog does its own UPnP forwarding when the instance has
`enable_port_forwarding=true`. Both create the mapping, and either can remove it.

Pick one. On a KGSM host, turn the game's off:

```ini
UPnP=false
```

## A setting in the .ini has no effect

- **The server was not restarted.** The file is read at startup. `reloadoptions` re-reads it live and
  pushes to clients, and `changeoption` alters a single value on the running server — but anything
  consumed once at startup, ports included, still needs a restart.
- **It only applies at world creation.** `Seed` is the clearest case; its own comment says to delete
  `map_worldgen.bin` from the save directory to make a new one take effect. Most of
  `<servername>_SandboxVars.lua` is the same.
- **You edited the wrong file.** The `.ini` is named after the instance's `level_name`, not its name.
  An instance called `my-pz` with the default `level_name` reads `saves/Server/default.ini`.

## A mod downloaded but does nothing

`WorkshopItems` and `Mods` take **different identifiers** and both are required. `WorkshopItems`
holds Workshop item IDs (the number in the Steam page URL) and controls the download; `Mods` holds
mod loading IDs (the `id=` line in the mod's `info.txt`) and controls whether it is switched on. A
mod listed only in `WorkshopItems` is downloaded and ignored.

Check it arrived:

```bash
ls <instance>/install/steamapps/workshop/content/108600/
```

## The log is full of "template not found" and mesh errors

```
ERROR: template "DAMN85chevyImpalaPD" not found B.
WARN : no such mesh "vehicles/..." for Base.92jeepYJSportRollbarWI
```

These come from inside mods, not from KGSM or the server, and a healthy modded server produces
hundreds of them. They are not the reason something else is broken. On a vanilla server they do not
appear at all, which makes them a quick way to tell whether mods actually loaded.

## Errors on every start that are not errors

Two appear on every single start, vanilla or modded, and mean nothing:

```
ERROR: ld.so: object 'libjsig.so' from LD_PRELOAD cannot be preloaded ... ignored.
```
The shipped `start-server.sh` preloads a JVM signal-handling library that is not in the image.

```
java.nio.file... DebugFileWatcher.registerDir> Exception thrown
```
The file watcher failing to register directories.

Neither stops the server, and the run continues to `*** SERVER STARTED ****`.

## Player presence is empty or wrong

Presence for this game comes from **RCON polling only**, and RCON is off until it has a password. Set
`RCONPassword` in the server `.ini` and the matching `rcon_password` on the instance — they must
agree, and leaving either empty leaves the server with no presence at all.

The console log is deliberately not used as a presence source: it announces a join as a bare Steam ID
with no name, and prints no leave line at all, while RCON's `players` answers with names and no IDs.
The two cannot be correlated, so only the RCON half is read.

Also check the RCON port is actually free. `27015` is the Steam default and several other games claim
it — on this host a Palworld server holds it, which silently leaves Project Zomboid's RCON unbound.

```bash
ss -lun | grep 27015
```

## Restoring a backup did not restore the world

Project Zomboid keeps **its own** backups in `saves/backups/`, taken on start and on version change
and pruned on its own schedule. Those are not KGSM backups, and `kgsm instances backups` does not
list them. Check which set you are looking at before restoring.

```bash
kgsm instances backups my-pz          # KGSM's
ls <instance>/saves/backups/          # the game's
```

## An update or backup is refused

Both require a stopped instance:

```bash
kgsm stop my-pz
kgsm instances update my-pz
kgsm instances create-backup my-pz
kgsm start my-pz
```

The instance also ships with `auto_update=true`, so an update can arrive at the next start without
being asked for. If players are suddenly locked out on a version mismatch nobody triggered, that is
where to look.
