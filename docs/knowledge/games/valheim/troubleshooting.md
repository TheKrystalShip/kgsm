# Valheim server troubleshooting

Symptoms and what actually causes them on a KGSM-managed Valheim server.

Derived from Iron Gate's "A Guide to Dedicated Servers" and behaviour observed on Valheim dedicated
server `l-0.221.12` under KGSM.

The instance log is the primary evidence for everything below:

```bash
kgsm instances info my-valheim        # shows the log path
```

## The server exits immediately and the log mentions the password

```
Error bad password:The password is too short
```

Valheim refuses to run without a password of at least 5 characters, and refuses one that appears
inside the server name. Both are startup failures, not warnings.

```bash
kgsm instances config-get my-valheim executable_arguments
```

Check that `-password` is present, is 5 characters or more, and that its text does not occur in
`-name`. Since `-name` defaults to the instance's `level_name`, naming an instance after its
password breaks it.

## KGSM says it started, but players cannot join yet

Starting and being ready are two different things here, and the gap is large. `kgsm start` reports
success once the process is launched; a new instance then generates a world before it accepts
anyone — generating locations alone took ~83 seconds on a quick host. The log shows the phases:

```
Game server connected            ← networking is up; the world is NOT ready
Generating locations
Opened Steam server              ← ready for players
 Done generating locations, duration:82901.026 ms
```

`Game server connected` appearing early is not readiness — wait for `Opened Steam server`. Later
starts load the existing world and come up quickly.

## The world regenerates every start, and there is no `.db` file

The world was never written. Valheim writes `<world>.db` on its autosave schedule and while shutting
down; until one exists there is only `<world>.fwl`, which carries the seed — so the next start
generates the same world from scratch again.

```bash
ls <instance>/saves/worlds_local/       # a .fwl with no .db is this
```

Two ways to end up here, both on a **new** instance:

- **Stopped while it was still generating.** Nothing had been written yet.
- **Stopped just after generating.** Writing a freshly generated world takes longer than the 30
  seconds the supervisor waits before killing the process, so the save is cut off. The watchdog
  journal records it plainly:

  ```
  <instance> did not stop gracefully in 30s; cgroup.kill
  ```

  ```bash
  journalctl -u kgsm-watchdog | grep <instance>
  ```

Let a new instance reach `Opened Steam server` and run for a few minutes before stopping it, then
confirm a `.db` appeared. Once it exists, stopping updates that file instead of writing it whole —
a reload-and-stop measured about 20 seconds — and the problem does not recur.

Note the watchdog restarts an instance that exits unexpectedly, so a server killed this way comes
back on its own, having lost whatever was not saved.

## Worlds ended up outside the instance

If `saves/worlds_local/` is empty but the server clearly has a world, look in
`~/.config/unity3d/IronGate/Valheim/worlds_local/`. That is Valheim's default location, used when
`-savedir` is missing from the launch arguments.

```bash
kgsm instances config-get my-valheim executable_arguments
```

It must contain `-savedir $instance_saves_dir`. Without it the instance's backups capture nothing,
and every Valheim server on the host shares one directory. Note that directory is shared with any
server you have ever run by hand, so worlds there may predate the instance.

## Nobody can join

1. **Is it ready?** `kgsm instances status my-valheim`, and the log reached `Opened Steam server` —
   not merely `Game server connected`.
2. **Is it listening?** Valheim is **UDP only**, and a ready server binds both `2456/udp` and
   `2457/udp`. A TCP check proves nothing. The base port is opened only once the world is
   generated, so seeing just `2457` means it is still generating, not that it is broken.
3. **Is the host port reachable?** `kgsm network test-port 2457 udp`.
4. **Is the router forwarding?** UDP, to this host. Or use `-crossplay`, which relays through Iron
   Gate's servers and needs no forwarding.
5. **Is the password right?** Players are refused with a password error, not a connection failure.

Do not open the port by hand. KGSM opens an instance's ports when it starts and closes them when it
stops; a manually added rule sits outside that lifecycle.

## Everyone is suddenly locked out, including people who were playing

`permittedlist.txt` has an entry. It is an allow-list, not a VIP list: the moment it is non-empty,
every player not named in it is refused.

```bash
cat <instance>/saves/permittedlist.txt
```

Empty it to go back to "anyone with the password", or add the rest of your players.

## The server does not appear in the community browser

Check `-public 1` is in the launch arguments and the server was restarted afterwards. A server with
`-public 0` runs normally and is joined by address instead.

Note the log line `Registering lobby` — if the server reached `Opened Steam server`, the listing
side succeeded and the problem is more likely the players' search than the server.

## Console commands and `kgsm instances kick` do nothing

Valheim's dedicated server reads no console input, so there is nothing for `kgsm instances input` to
talk to, and the blueprint declares no moderation commands — `kgsm instances kick|ban|unban` answer
that the instance does not support them.

Moderation is the list files in `saves/`, applied by restarting:

```bash
# add the platform user ID to bannedlist.txt, then
kgsm restart my-valheim
```

## Settings changes have no effect

Valheim has no configuration file — everything is a launch argument. Editing `start_server.sh` in the
install directory changes nothing, because KGSM does not run that script: the shipped one hardcodes
its own name, world and password and forwards nothing, which is why the blueprint runs the server
binary directly.

Change `executable_arguments` on the instance instead, then restart:

```bash
kgsm instances config-set my-valheim 'executable_arguments=…'
kgsm restart my-valheim
```

## An update or backup is refused

Both require a stopped instance:

```bash
kgsm stop my-valheim
kgsm instances update my-valheim
kgsm instances create-backup my-valheim
kgsm start my-valheim
```
