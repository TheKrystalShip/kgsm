# Factorio server troubleshooting

Symptoms and what actually causes them on a KGSM-managed Factorio server.

Derived from the Factorio Wiki, "Multiplayer" (CC BY-NC-SA 3.0) and behaviour observed on Factorio
headless 2.0.77 under KGSM.

The instance log is the primary evidence for everything below:

```bash
kgsm instances info my-factorio        # shows the log path
```

## KGSM says the server started, but it is not running

Starting and staying up are two different things. `kgsm start` and `kgsm restart` report success
once the process has been **launched**; a server that exits a second later still produced that
message.

Confirm the real state, which is measured from the process:

```bash
kgsm instances status my-factorio
```

If that shows the instance inactive, the cause is at the end of the log. The most common one is a
malformed `server-settings.json`, which Factorio rejects at startup:

```
Error CommandLineMultiplayer.cpp:355: Hosting multiplayer game failed:
Unexpected end of file at .../server-settings.json:1
```

Fix the JSON — a missing brace, a trailing comma, a truncated file — and start again. Validating it
first saves a cycle:

```bash
python3 -m json.tool server-settings.json > /dev/null
```

## The server will not start and the log mentions a missing save

Factorio cannot host without a save file. KGSM creates one during install, so this usually means the
save was deleted or renamed, or the instance's `level_name` no longer matches any file in `saves/`.

Check what the instance expects against what exists:

```bash
kgsm instances config-get my-factorio level_name
```

A log line such as `saves/default not found; using saves/default.zip` is **not** this problem — that
is Factorio resolving a name to the `.zip`, and is normal.

## Nobody outside my network can join

Work through it in this order:

1. **Is the server up?** `kgsm instances status my-factorio`.
2. **Is it listening?** A running Factorio holds a **UDP** socket on its game port. It never listens
   on TCP, so a TCP check always looks closed and proves nothing.
3. **Is the host port reachable?** `kgsm network test-port <port> udp`.
4. **Is the router forwarding?** The forward must be UDP, to this host.
5. **Does the router randomise source ports?** Factorio's own documentation calls this out: if the
   router rewrites the source port of packets leaving the game port, clients fail to connect even
   with a correct forward. That is a router setting, not something the server or KGSM can work
   around.

Do not open the port by hand. KGSM opens an instance's ports when it starts and closes them when it
stops; a manually added rule sits outside that lifecycle and will be wrong as soon as the server
stops.

## The server does not appear in the public server browser

Public listing needs more than `visibility.public`. In `server-settings.json`, check that:

- `visibility.public` is `true`
- `username` is set, together with either `token` or `password` — these are **factorio.com account**
  credentials, and public visibility is refused without them
- the server was restarted after the edit; the file is only read at startup

The log records the outcome of contacting the auth server at startup — a healthy server reports
obtaining a `serverPadlock` from `auth.factorio.com`. If that step failed, the credentials or
outbound connectivity are the problem, not the listing.

Players can still join an unlisted server by entering the address directly.

## Players get a version or mod mismatch

Every client must run **exactly** the same game version and the same mods as the server. There is no
compatibility range.

```bash
kgsm instances version my-factorio
kgsm instances check-update my-factorio
```

Updating the server disconnects everyone until each player updates too, so it is a coordinated
action rather than routine maintenance.

## The server looks frozen with nobody online

Expected, when `auto_pause` is on: with no players connected there is nothing to simulate, so the
game pauses, and it resumes when someone joins. Set `auto_pause` to `false` only if the factory
needs to keep running unattended — it costs CPU continuously.

## Console commands do nothing

Send commands through KGSM rather than to the terminal that started the server:

```bash
kgsm instances input my-factorio "/players"
```

If a command is rejected in-game, `allow_commands` in `server-settings.json` is likely
`admins-only` (the default) and the player is not in `server-adminlist.json`.

## Changes to server settings have no effect

`server-settings.json` is read once, at startup. Restart, then verify the instance is still up — an
edit that broke the JSON takes the server down at the next restart rather than at the moment it was
saved.

## An update or backup is refused

Both require a stopped instance:

```bash
kgsm stop my-factorio
kgsm instances update my-factorio
kgsm instances create-backup my-factorio
kgsm start my-factorio
```
