# Terraria server troubleshooting

Symptoms and what actually causes them on a KGSM-managed Terraria server.

Derived from the Terraria Wiki, "Server" (CC BY-NC-SA 4.0) and behaviour observed on a live
KGSM-managed Terraria server.

The instance log is the primary evidence for everything below:

```bash
kgsm instances info my-terraria        # shows the log path
```

## The first start seems to hang

Almost always world generation, not a hang. A new instance has no world, so the first start creates
one before listening, and a large world takes over a minute. The log fills with progress lines:

```
26.1% - Desertification - 52.8%
```

Let it finish. It is ready at:

```
Listening on port 7777
: Server started
```

If you want a faster first start, generate a smaller world by lowering `autocreate` from `3` (large)
to `1` (small) before the first launch. After a world exists the setting does nothing.

## KGSM says the server started, but it is not running

Starting and staying up are two different things. `kgsm start` and `kgsm restart` report success once
the process has been **launched**; a server that exits a second later still produced that message.

Confirm the real state, which is measured from the process:

```bash
kgsm instances status my-terraria
```

If that shows the instance inactive, the cause is at the end of the log.

## The log shows a crash about a missing world file

The server was told to load a world that does not exist, with no `autocreate` to generate one, so it
crashes on startup:

```
Server crash: ...
System.IO.FileNotFoundException: .../saves/doesnotexist
  at Terraria.IO.WorldFileData.SetAsActive ()
```

A `Gtk-WARNING ... Failed to open display` line usually follows — the crash handler tries to raise a
graphical dialog and cannot on a headless host. That warning is a consequence of the crash, not its
cause; the exception above it is what matters.

Check the world the instance expects against what exists:

```bash
kgsm instances config-get my-terraria level_name
kgsm instances config-get my-terraria executable_arguments
```

The launch arguments must point at the instance's own saves directory, via
`-world $instance_saves_dir/$instance_level_name`. A hand-edited absolute path that no longer
matches the instance is the usual way this breaks.

## Nobody outside my network can join

Work through it in this order:

1. **Is the server up?** `kgsm instances status my-terraria`, and the log reached `Server started`.
2. **Is it listening?** A running Terraria holds a **TCP** socket on its game port.
3. **Is the host port reachable?** `kgsm network test-port <port> tcp`.
4. **Is the router forwarding?** The forward must reach this host.

Do not open the port by hand. KGSM opens an instance's ports when it starts and closes them when it
stops; a manually added rule sits outside that lifecycle and will be wrong as soon as the server
stops.

## Players are refused with a version mismatch

Clients and the server must run the same Terraria version:

```bash
kgsm instances version my-terraria
kgsm instances check-update my-terraria
```

Updating disconnects everyone until each player is on the same build.

## A setting in serverconfig.txt has no effect

Three usual causes:

- **The file is not being read.** KGSM does not pass one unless the instance's launch arguments
  include `-config`. Check with `kgsm instances config-get my-terraria executable_arguments`.
- **The server was not restarted.** The file is read once, at startup.
- **The setting is fixed at world generation.** `difficulty` and `seed` apply only when a world is
  created; on an existing world they do nothing.

Confirm what the server actually believes:

```bash
kgsm instances input my-terraria "maxplayers"
kgsm instances input my-terraria "motd"
```

## The server stopped when I typed `exit`

`exit` is Terraria's own shutdown command, so it stops the server underneath KGSM rather than
through it. Use `kgsm stop my-terraria`, which saves and shuts down as part of the instance
lifecycle.

## A player needs removing, and `kgsm instances kick` refuses

KGSM answers *"does not support 'kick'"* / *"No kick_command is declared for this instance"*. Its
moderation verbs require the blueprint to declare the game's moderation commands, and Terraria's
declares none — so the verb is unavailable even though the server itself can kick and ban.

Use the server's own console:

```bash
kgsm instances input my-terraria "kick PlayerName"
kgsm instances input my-terraria "ban PlayerName"
```

Bans are recorded in `banlist.txt`, and a player stays banned until removed from that file — the
server has no un-ban command.

## An update or backup is refused

Both require a stopped instance:

```bash
kgsm stop my-terraria
kgsm instances update my-terraria
kgsm instances create-backup my-terraria
kgsm start my-terraria
```
