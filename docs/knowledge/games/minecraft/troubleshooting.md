# Minecraft server troubleshooting

Symptoms and what actually causes them on a KGSM-managed Minecraft server.

Derived from the Minecraft Wiki, "Tutorial:Setting up a Java Edition server" (CC BY-NC-SA 3.0) and
behaviour observed on a live KGSM-managed Minecraft server.

The instance log is the primary evidence for everything below:

```bash
kgsm instances info my-minecraft        # shows the log path
```

Minecraft also writes its own logs to `install/logs/`, which survive across restarts and are worth
reading when the instance log has already rolled.

## KGSM says it started, but the server is not running

Starting and staying up are two different things: `kgsm start` reports success once the process is
launched. Confirm the real state, which is measured from the process:

```bash
kgsm instances status my-minecraft
```

If it shows inactive, the cause is at the end of the log — usually one of the next three entries.

## The log shows an UnsupportedClassVersionError

The host's Java is older than the Minecraft release requires. Modern versions want Java 21 or newer.

```bash
java -version
```

Install a newer JRE. The reverse — Java much newer than the server expects — generally works, though
the JVM may print deprecation warnings about garbage-collector flags. Those are warnings, and the
server starts anyway.

## The server exits complaining about the EULA

KGSM writes `eula=true` into `install/eula.txt` when it installs, so a KGSM instance should never hit
this. If it does, the file was replaced or reset — an update that rewrote the install directory is
the usual cause.

```bash
cat <instance>/install/eula.txt        # want eula=true
```

## Failed to bind to port

Two causes, in order of likelihood:

- **Something already holds the port.** Another Minecraft instance is the common one — every
  instance created from the blueprint starts on the same default port, so a second one collides.
  Give it a different `server-port`, and install it with `--port` so the declared ports match.

  ```bash
  kgsm network ports check 25565 tcp
  ```

- **`server-ip` is set.** It should be empty so the server binds every interface. An address that
  does not exist on this host fails to bind.

## Nobody can join

1. **Is it up?** `kgsm instances status my-minecraft`, and the log reached `For help, type "help"`.
2. **Is it listening?** Minecraft listens on **TCP**. Nothing appears on UDP unless `enable-query`
   is on, so a missing UDP listener is normal and proves nothing.
   ```bash
   kgsm network test-port 25565 tcp
   ```
3. **Is the router forwarding?** TCP, to this host.
4. **Is the whitelist on?** With `white-list=true`, anyone not in `whitelist.json` is refused with a
   whitelist message rather than a connection error.
5. **Do the versions match?** A client on a different Minecraft version is refused outright.

Do not open the port by hand. KGSM opens an instance's ports when it starts and closes them when it
stops; a manually added rule sits outside that lifecycle.

## The whitelist has no effect

Adding names to `whitelist.json` does nothing while `white-list=false` in `server.properties`. Turn
it on, and prefer the console command so the file and the running server agree:

```bash
kgsm instances input my-minecraft "/whitelist on"
kgsm instances input my-minecraft "/whitelist add PlayerName"
```

`enforce-whitelist` is what removes players who are already connected; without it, enabling the
whitelist only affects new joins.

## Someone connected as a player they are not

`online-mode` is `false`. The server then accepts any username without checking it against Mojang's
authentication servers, so anyone can claim an operator's name. Set it back to `true` and restart.

## A setting in server.properties has no effect

Two usual causes:

- **The server was not restarted.** The file is read once, at startup. Editing it while the server
  runs is safe — the change sits on disk and takes effect at the next restart — but nothing happens
  until then.
- **The setting only applies at world generation.** `level-seed` and `level-type` do nothing on an
  existing world; change `level-name` as well to generate a new one.

Minecraft rewrites the file when it **starts**, normalising the ordering and comments. That rewrite
preserves your values; it is not a reason to avoid editing.

## The server froze and then exited on its own

Look for a message about a single server tick taking too long. That is Minecraft's own watchdog,
governed by `max-tick-time`, killing a server whose tick has hung — usually a mod, a datapack, or a
chunk-generation stall rather than KGSM.

## The world did not change after restoring a backup

Minecraft keeps its world **inside** the install directory (`install/world`, named by `level-name`),
not in the instance's `saves/`. A KGSM backup captures the install directory for exactly that
reason, so it does include the world — but the archive also carries the jar and libraries and is
large.

Check what a backup actually holds before relying on it:

```bash
kgsm instances backups my-minecraft
```

If `level-name` was changed since the backup, the restored folder is not the world the server now
loads.

## kick says "No player was found"

`kick` only affects someone currently connected. `ban` and `unban` work on an offline player,
because Minecraft keeps the ban list keyed on the account:

```bash
kgsm instances ban my-minecraft "PlayerName"
kgsm instances unban my-minecraft "PlayerName"
```

## An update or backup is refused

Both require a stopped instance:

```bash
kgsm stop my-minecraft
kgsm instances update my-minecraft
kgsm instances create-backup my-minecraft
kgsm start my-minecraft
```
