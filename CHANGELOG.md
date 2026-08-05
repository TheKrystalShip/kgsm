# Changelog

- [Changelog](#changelog)
  - [Ideas for the future](#ideas-for-the-future)
  - [Work in progress](#work-in-progress)
  - [2.1.0](#210)
  - [2.0.1](#201)
  - [2.0](#20)
  - [1.7.3](#173)
  - [1.7.2](#172)
  - [1.7.1](#171)
  - [1.7.0 - Maintenance Update](#170---maintenance-update)
  - [1.6.1](#161)
  - [1.6.0 - Events](#160---events)
  - [1.5.2](#152)
  - [1.5.1](#151)
  - [1.5.0](#150)
  - [1.4.2](#142)
  - [1.4.1](#141)
  - [1.4.0](#140)
  - [1.3.2](#132)
  - [1.3.1](#131)
  - [1.3.0](#130)
  - [1.2.7](#127)
  - [1.2.6](#126)
  - [1.2.5](#125)
  - [1.2.4](#124)
  - [1.2.3](#123)
  - [1.2.1](#121)
  - [1.2.0](#120)
  - [1.1.1](#111)
  - [1.1.0](#110)
  - [1.0.4](#104)
  - [1.0.3](#103)
  - [1.0.2](#102)
  - [1.0.1](#101)
  - [1.0.0](#100)

## Ideas for the future

Features that I'd like to consider implementing in order to make KGSM more versatile.

- Support for other firewalls other than UFW
- Allow instances to start automatically on system boot without going through systemd
- Podman as an alternative for Docker
- More game servers

## Work in progress

- Events system refactoring to command-based architecture

## [Unreleased] - 3.0.0 (Major Version)

### Added

- **`instances update` brackets its run with events.** `instance_update_started` is emitted before
  the management file runs and `instance_update_finished` after it returns, on every outcome — so a
  consumer can tell that an instance is busy updating for the whole minutes-long download-and-deploy,
  instead of learning about it only when `instance_version_updated` lands at the end. Finished states
  that the run ended, not that it succeeded; the version event remains the one that says the version
  moved. Both event types were already declared and carry the instance name.

- **Palworld and Project Zomboid declare their moderation commands.** Palworld addresses a player
  by account id (`/KickPlayer {id}`, `/BanPlayer {id}`, `/UnBanPlayer {id}`) — the bare number its
  join line carries, so the presence capture and the moderation target are the same token. Project
  Zomboid addresses one by user name (`kick {name}`, `banuser {name}`, `unbanuser {name}`).

- **Project Zomboid detects presence and polls RCON.** Its `player_joined_regex`, `player_left_regex`
  and the four `rcon_*` fields sit at the blueprint's top level, where the loader reads them, so the
  watchdog gets both the join pattern and the RCON connection it needs. The console log names a
  player only by Steam id, so the RCON `players` poll is what supplies the user name a moderation
  command addresses — which makes `rcon_password` (set on the instance and in the game's own server
  config) the switch that turns Project Zomboid moderation from declared into usable.

- **Player moderation: `kgsm instances kick|ban|unban <instance> <target>`.** Three optional
  top-level blueprint fields — `kick_command`, `ban_command`, `unban_command` — declare the console
  commands a game accepts to remove a player, block them, and lift that block. Each is a template
  carrying exactly one placeholder, and the placeholder *names* the identity token the game expects:
  `{ip}`, `{name}`, or `{id}`. So `kick {ip}` says both "the verb is `kick`" and "hand it an IP
  address", and a caller reads the token to know what to send.

  The kind lives in the template rather than in a second field beside it, because two fields can
  disagree — one of them would then be describing a substitution that does not happen. The
  templates flow blueprint → instance config → management script (`kick`/`ban`/`unban` verbs), and
  `blueprints info --json` reports all three as `KickCommand`/`BanCommand`/`UnbanCommand`.

  An undeclared action is **refused**, never approximated with a different command — a kick
  standing in for a ban is a fabricated outcome. A target containing a line break is rejected: the
  console reads one command per line, so it would deliver a second command nobody issued. For a
  native instance the run state is resolved through the watchdog before sending, because the FIFO
  outlives the process that read it and a write into a stopped instance is accepted by the kernel
  and delivered to nobody.

- **Player-moderation audit events: `instance_player_kicked`, `instance_player_banned`,
  `instance_player_unbanned`**, carrying `InstanceName`, `Target` (the identity the operator
  supplied, verbatim — KGSM does not classify it, the blueprint is where that meaning is declared)
  and `Command` (the resolved console command that was delivered). Their own types rather than a
  console-input record because the subject is a player, not a command: a consumer asking "who was
  banned on this server" filters on the type instead of pattern-matching command text — text a
  hand-typed `instances input` could produce with no moderation intent behind it.

### Removed

- **The Unix Domain Socket event transport is gone** — `commands/events.socket.sh`, the
  `events socket` verb, `events test socket`, and both config keys (`enable_socket_events`,
  `event_socket_filenames`). Config schema 7 (migration `007_v6_to_v7_drop_socket_transport.sh`)
  removes the keys rather than commenting them out, so a dead switch cannot invite an operator to
  set it and expect delivery somewhere.

  Socket binding is exclusive, which is the whole reason the engine had to be configured with a
  list of consumer paths at all: one socket, one reader, so every new consumer meant a new path in
  KGSM's config. A journal segment is a plain file — any number of readers, no registration, no
  coordination — so the fan-out has nothing left to buy. Measured on a live host with five
  configured consumer sockets, none of which had a reader: an emit fell from **111ms to 76ms**.

  The webhook transport is untouched. It delivers to remote endpoints a local consumer cannot tail,
  and it never carried the consumer-registry problem.

### Changed

- **Events are recorded in an append-only journal, and always emitted.** KGSM appends one JSON
  line per event to a date-named segment under `event_journal_dir` (default `/var/lib/kgsm/events`)
  and holds no list of consumers: each one tails the journal at its own pace with its own cursor,
  so adding or removing a consumer needs no engine configuration. `enable_event_broadcasting` is
  removed — the journal is KGSM's audit record, and an audit trail that can be silently switched
  off is worse than none. The webhook transport stays, as a purely additive copy.
  `events journal status|prune|verify` inspects and maintains it; `event_journal_retention_days`
  (default 90) bounds it, pruned by a user systemd timer that `deploy/setup.sh` installs.
  Config schema 6 (migration `006_v5_to_v6_event_journal.sh`).

- **Emitting an event no longer re-executes `events.sh`.** The payload is built and written from
  inside the running KGSM process, so an emission costs one in-process append rather than a full
  bash bootstrap per event: 110ms → 59ms, and 13ms once the journal was the only transport. Payloads are written compact, since one event per line is the contract every consumer's
  cursor depends on.

- **Scheduled backups have their own cadence.** New instance config keys `backup_schedule`
  (off | daily | weekly | 6h), `backup_time` and `backup_day` drive a backup schedule that is
  independent of `scheduled_restart`; `auto_backup_on_restart` is removed. A backup is taken
  against the instance as it is, running or not, so it no longer needs a restart window to happen
  in. `timezone` now serves both schedules. Enforced by the kgsm-scheduler leaf; inert without it.

- **A backup records the state it was captured in.** `manifest.consistency` is measured per
  backup instead of being written as the constant `"cold"` it always was: `cold` when the
  instance was stopped, `flushed` when it was running and the game wrote its world out first,
  `hot` when it was running with no usable save command, and `null` when the run state could
  not be determined. A native instance is spawned by the watchdog, which owns the process and
  writes no pid file, so the management file cannot see it — the command layer resolves the
  state and passes it in with `create-backup --run-state`.

  **A management file generated before this keeps writing the constant `"cold"`.** Run
  `kgsm files management create <instance>` on each instance to pick the measurement up.

- **An update backs the instance up before it applies.** `update` archives what it is about to
  overwrite and abandons the update if that archive cannot be made, so a new version is never
  laid over an unprotected world. An instance already on the latest version is a no-op and takes
  no backup, and a plain restart — which cannot lose data — takes none either. This is not tied
  to `backup_schedule`: it happens whenever an update applies, including the one `auto_update`
  triggers on start.

- **A restore's safety backup records the state it was taken against.** `restore-backup` accepts
  `--run-state` and carries it into the archive it takes before overwriting, so that archive is
  subject to the same measurement rule as any other instead of falling back to a probe the
  management file cannot answer.

- **A running instance can be backed up.** The refusal that required a stopped instance is
  gone. It had stopped working on its own — it probed a pid file the watchdog no longer
  writes, so it silently passed for every supervised instance — and what it protected against
  is now recorded in `manifest.consistency` instead of forbidden.

- **A backup of a running instance captures `saves/` alone when it has content.** `install/`
  is the bulk of a game and is re-downloadable, so skipping it is what keeps a frequent backup
  cadence affordable — a running Project Zomboid backup drops from 11.9GB to 2.75GB. When
  `saves/` is empty the whole tree is captured instead, because several games keep their world
  inside `install/` and capturing `saves/` alone would back up nothing of value.

- **A backup flushes the game to disk first when it can.** A running instance whose blueprint
  declares a save command is told to write its world out before the archive is taken. A save
  command identical to the instance's stop command is not a usable save command — some
  blueprints declare both as `exit`, and issuing it would shut the server down to back it up.

- **Writing to an instance's command FIFO cannot hang.** The FIFO is opened read-write rather
  than appended to; a plain append blocks until something opens the read end, so a server that
  died leaving its socket behind would hang the caller forever. This covers both the save
  flush and console input.

### Fixed

- **An update of a running native instance is refused.** The refusal probed the pid file the
  watchdog does not write, so it never fired for a supervised instance: the update ran, downloaded,
  and failed partway through deploy with `cp: … Text file busy`, leaving `install/` half-replaced.
  It now consults the run state the command layer resolves, and fails before downloading anything.
  `kgsm-api` already rejected an update on a running server on the grounds that the engine does
  this — that is now true.

- **A backup with nothing to capture fails instead of reporting success.** It returned success
  having created no backup, so a scheduled run would record protection that does not exist.

- **Instance config lookup resolves the path instead of searching for it.** The layout
  `$KGSM_INSTANCES_DIR/<blueprint>/<instance>/<instance>.config.ini` is deterministic, so a
  single-level glob finds the file directly. The previous recursive `find -L` followed the
  instance symlink into the game's working directory and walked the whole installation —
  over 300,000 files on a host with Project Zomboid installed — to locate a file whose path
  was already known, making the cost of every instance-scoped command scale with the size of
  the installed games. Instances outside the standard layout still resolve by search.
  `kgsm instances backups <instance> --json` drops from ~456ms to ~143ms.

- **The two management-file capability gates share one `--help` probe.** `backups` and the
  other gated ops commands executed the 60KB+ generated management script twice per
  invocation to read the same help text; the probe is now run once and both gates read the
  memoized result.

- **Backups capture `saves/` as well as `install/`.** For many games the world lives in
  `saves/` (terraria, factorio, projectzomboid and every blueprint that mounts
  `${instance_saves_dir}`), while `install/` holds only re-downloadable game files. A
  backup now archives both subtrees, rooted at their own names, and its manifest records
  exactly which ones it captured.

- **A backup is a directory identified by an opaque id**, holding a `manifest.json` plus
  `data.tar.gz` (or a `data/` tree when `compress_backups=false`). The manifest carries the
  creation time, captured version, size, file count, sources and sha256 — nothing parses the
  id. Backups are built in the instance's temp directory and moved into place only when
  complete, and only manifest-bearing directories are listed, so an interrupted build can
  never be offered for restore. Restore verifies the recorded checksum before touching the
  instance. **The previous `<instance>-<version>-<datetime>.backup[.tar.gz]` artifacts are
  not readable by this version.**

- **Backups live outside the instance's working directory**, in a per-instance subdirectory
  of `$XDG_DATA_HOME/kgsm/backups` (override with the new `backups_directory` config key).
  Removing an instance deletes its working directory wholesale, which used to destroy the
  backups along with it; `uninstall` now keeps them and reports where they are. Pass
  `--purge-backups` to delete them too. An instance created before this change is repointed
  at the canonical path on the first backup command that touches it.

### Added

- **`instances backups <instance> --json`** emits every backup's full manifest as a JSON
  array, newest first — the machine-readable form of the id listing that consumers such as
  kgsm-api read to report a backup's size, age and captured version.

- **Config schema v5** adds `backups_directory` to `[instance_defaults]`
  (`migrations/config/005_v4_to_v5_backups_directory.sh`). Empty means the XDG default.

### Changed

- **`event_socket_filenames` ships the assistant's socket** — `/run/kgsm-assistant/events.sock`
  joins the four other ecosystem consumer sockets in the default list. The assistant caches the
  blueprint catalog, so a blueprint written through the Control Panel needs to reach it for the
  next answer to use the new values. As with every entry, a socket that does not exist is skipped,
  so listing it costs nothing on a host with no assistant installed. An existing host keeps its own
  `event_socket_filenames`; add the path there to deliver.

- **Deployment split into `deploy/setup.sh` (once per host) + `deploy/deploy.sh` (every time)**,
  the ecosystem-wide contract (`tks/scripts/deploy-template/README.md`). `setup.sh` asks for sudo
  and creates `/opt/kgsm` owned by the deploying user plus the `/usr/local/bin/kgsm` symlink;
  `deploy.sh` then `rsync`s the checkout with **no sudo and no prompts**, and refuses up-front with
  "run `deploy/setup.sh`" when the host is not provisioned. It replaces the root-level `deploy.sh`,
  whose interactive "Overwrite? [y/N]" prompt and `rm -rf` of the target are gone — the sync prunes
  instead, so a deleted command or override never lingers on the deployed engine.

### Added

- **RCON blueprint fields**: `rcon_port`, `rcon_password`, `rcon_poll_interval_seconds`,
  `rcon_players_command` — new top-level, runtime-agnostic blueprint fields that materialize
  into the instance config. The kgsm-watchdog reads these to poll game servers via Source RCON
  for connected players, detecting disconnects when the game server does not log them. The
  password is stored in plaintext; the user must also configure the game server's own RCON with
  matching values. Project Zomboid blueprint now ships with `rcon_port: 27015` and
  `player_joined_regex` for log-based join detection.

### Added

- **`blueprints validate <blueprint|path> [--json]`** exposes the blueprint schema check as a
  command. The check itself (YAML syntax, required `name` and `runtime`, `native.executable_file`
  for native, a `container.compose` with at least one service all on `network_mode: host` for
  container) was previously reachable only as an internal function, so the only way to find out
  whether a blueprint was acceptable was to write it and then ask KGSM to read it back. An
  argument naming an existing file is checked as a path rather than a blueprint name, which
  allows a file to be checked *before* it is committed under a blueprint's real name. Nothing is
  written and no event is emitted. `--json` returns `{Valid, Path, Errors}` listing every problem
  found rather than stopping at the first, so a caller rejecting a file can report all of them at
  once instead of one per round-trip.

- **`blueprints find <blueprint> --all|--json`** reports every path a blueprint name could
  resolve to, in precedence order, with whether each exists. Because a user blueprint shadows a
  same-named system one, the single resolved path that plain `find` returns cannot distinguish a
  purely custom blueprint from a user copy overriding a shipped one — both candidates existing
  means an override is in effect, and only the user candidate existing means there is no original
  to fall back to. Unlike plain `find`, these modes report on existence alone and skip the format
  check: locating a file is not the same as approving it, and a malformed blueprint has to stay
  findable in order to be repaired.

- **Blueprint file events: `blueprint-created`, `blueprint-updated`, `blueprint-removed`.** A
  blueprint write was invisible to the rest of the system, so every consumer holding a blueprint
  catalog kept serving the pre-edit version until its own refresh timer happened to fire, and the
  change never reached event history at all. These are the first events whose subject is not an
  instance: their `Data` carries `BlueprintName` where every other event carries `InstanceName`,
  alongside `Tier` (where the file lives — only ever `user`, since the shipped system directory is
  an rsync target a write would lose on the next deploy) and a boolean saying whether the file
  shadows a shipped blueprint of the same name (`OverridesSystem`) or, on removal, whether
  deleting it uncovers one that takes over again (`RevertedToSystem`). `Runtime` is nullable — a
  blueprint can be saved in a state no runtime can be read out of, and an unknown runtime is
  reported as `null` rather than defaulted. The file **contents are never carried**: a blueprint
  can hold credentials (SteamCMD arguments, a password inside an embedded compose) and a payload
  fans out to every enabled transport, so the record is that the blueprint changed and nothing
  more.

### Fixed

- **KGSM no longer reports its version as `unknown`.** Three call sites still shelled
  `installer.sh --version`, a script deleted when versioning moved to the package manager. The
  failure was silent — each swallowed the missing-file error and fell back to a literal
  `"unknown"` — so *every* event payload carried `"KGSMVersion": "unknown"`, every webhook went
  out as `User-Agent: KGSM/unknown`, and the interactive system overview showed `Unknown`. The
  version now comes from `KGSM_VERSION`, which moves from `kgsm.sh` to `core/bootstrap.sh`:
  KGSM is a multi-entrypoint CLI, and a module under `commands/` invoked directly would otherwise
  report a different version than the same code reached through `kgsm.sh`. Bootstrap is the one
  file every entrypoint sources, so the version resolves identically no matter how the code was
  reached. The event payload's `KGSMVersion` is now asserted in the integration suite — nothing
  covered it before, which is why the regression went unnoticed.

- **Palworld player-presence detection now matches crossplay accounts, not just Steam.** The
  `player_joined_regex`/`player_left_regex` in `palworld.bp.yaml` required a literal `steam_`
  prefix on the `User id:` field, so a player connecting from Xbox / Game Pass (`gdk_<XUID>`)
  matched neither pattern. Palworld is crossplay, so those sessions were invisible to the entire
  presence pipeline, and invisible *silently*: the watchdog's native matcher treats a line that
  matches no pattern as an ordinary non-presence line and ignores it without a warning, so no
  join/leave event was emitted and the player never reached a roster, with nothing anywhere to
  indicate a player had been dropped. Both patterns now accept `(?:steam|gdk)_`. The platform
  prefix stays **outside** the `id` capture group — the bare account number remains the roster
  identity, so existing Steam roster rows keep theirs, and the two number spaces (17-digit
  SteamID64, 16-digit XUID) do not collide. Detection is tail-based: this applies from the next
  join onward and does not backfill sessions already missed.

- **`uninstall` now deregisters the instance from the kgsm-watchdog daemon.** Removing a native
  instance left the watchdog supervising it: the daemon kept a `desired=running` record and
  restart-looped a server whose install directory no longer existed, and because that record stayed
  in its instance list, downstream consumers (the Control Panel API's alert feed) reported a crash
  condition for a server that could never be started, stopped, or resolved. `uninstall` now calls the
  daemon's `DELETE /instance/<name>` (kgsm-watchdog 1.9.0) before removing any files — the daemon
  stops the instance as part of deregistering, and a graceful stop needs the FIFO and management
  script to still exist. An unreachable daemon is best-effort (a host without one still uninstalls,
  with a warning), but an explicit refusal **aborts** the uninstall: a refusal means the daemon could
  not stop the instance, and deleting a running server's files corrupts its saves and strands the
  process. Because deregistering performs a full graceful stop, uninstalling a running instance now
  takes as long as stopping it does.

### Documentation

- Added a knowledge base under `docs/knowledge/` documenting how native Linux dedicated
  servers are launched (wrapper scripts vs raw binaries vs interpreter-run servers, the
  executable subdirectory, headless arguments, readiness detection), how SteamCMD app ids
  and account ownership work (dedicated-server vs client app id, anonymous vs owned
  downloads), and annotated real examples from the catalog grouped by pattern. Cross-linked
  from `docs/README.md` and `docs/blueprints.md`.

### Breaking Changes

#### Systemd Removed as an Instance Lifecycle Manager
systemd is no longer used to supervise or boot game server instances. All native
instances are now supervised by the resident **kgsm-watchdog** daemon (cgroup-v2
spawn + crash-restart), and `runtime` (`native` | `container`) is the sole instance
runtime discriminator.

**Removed:**
- The `lifecycle_manager` instance field (every native instance was `standalone`;
  the field is gone) and the `enable_systemd`, `systemd_service_file`, and
  `systemd_socket_file` instance fields.
- The `[services]` config section (`enable_systemd`, `systemd_files_dir`).
- The `service.tp` and `socket.tp` templates.
- The `kgsm files systemd` command and the `files.systemd.sh` handler.
- The `LifecycleManager` field from the `instance-started`/`instance-stopped` event
  payloads (and the corresponding `[lifecycle_manager]` emit parameter); the event
  `Data` is now just `{"InstanceName": ...}`.

**Config schema bumped to v3:** migration
`003_v2_to_v3_remove_services_section.sh` removes the `[services]` section from
existing configs automatically.

**Migration Required:**
Boot auto-start was previously achieved with `sudo systemctl enable <instance>`.
Replace it with the new `kgsm autostart` command (see below). Existing systemd unit
files for KGSM instances are no longer used and may be removed.

#### Events System Refactoring
Complete refactor of the events system from legacy dash-argument style to modern command-based architecture with separated I/O and logic layers.

**Old Command Format:**
```bash
events.sh --emit --instance-created myserver factorio
events.socket.sh --enable
events.webhook.sh --configure
```

**New Command Format:**
```bash
events.sh emit instance-created myserver factorio
events.socket.sh enable
events.webhook.sh configure
```

**Module Changes:**
- `commands/events.sh`: Refactored to command-based (`status`, `test`, `socket`, `webhook`, `emit`, `help`)
- `commands/events.socket.sh`: Refactored to command-based (`enable`, `disable`, `test`, `status`, `emit`, `help`)
- `commands/events.webhook.sh`: Refactored to command-based (`enable`, `disable`, `configure`, `test`, `status`, `emit`, `help`)

**Architecture Changes:**
- Created `commands/handlers/events.sh` with pure validation logic
- Moved event constants and parameter specifications to logic layer
- Event emission now validates event types and parameters
- Updated `core/events.sh` dispatcher to use new command format

**Event Name Format:**
- Event names now use dash-separated format: `instance-created`, `instance-started`, `instance-version-updated`
- Internally converted to underscore format for constant matching

**New Exit Codes:**
- `EC_EVENT_TYPE_INVALID` (37): Invalid or unknown event type
- `EC_EVENT_PARAMS_INVALID` (38): Invalid parameters for event type
- `EC_EVENT_TRANSPORT_FAILED` (39): All event transports failed
- `EC_EVENT_JSON_FAILED` (40): Failed to generate JSON event payload
- `EC_SUCCESS_BLUEPRINT_LISTED` (256): Blueprint listing succeeded
- `EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED` (257): Blueprint info retrieved
- `EC_SUCCESS_BLUEPRINT_FOUND` (258): Blueprint found
- `EC_SUCCESS_BLUEPRINT_VALIDATED` (259): Blueprint validated

**Migration Required:**
All event emission calls throughout the codebase have been updated to the new format. External scripts or integrations calling KGSM events will need to update their command syntax.

**Example Migrations:**
```bash
# Old → New
events.sh --status → events.sh status
events.sh --test-all → events.sh test all
events.sh --emit --instance-started myserver → events.sh emit instance-started myserver
events.socket.sh --enable → events.socket.sh enable
events.webhook.sh --test → events.webhook.sh test
```

### Added
- `kgsm --paths --json` emits the XDG directory layout as machine-readable JSON
  (grouped `system`/`user` objects), alongside the existing human-readable
  `--paths`. Lets consumers query engine paths (e.g. the user blueprints
  directory) without parsing free-form text.
- New `kgsm autostart enable|disable|status|list <instance>` command for boot
  auto-start, backed by the kgsm-watchdog daemon's persisted desired-state. It works
  like `systemctl enable`/`disable`: it is **independent** of `start`/`stop` —
  `enable` does not start the instance now and `disable` does not stop it; they only
  change what comes back after a reboot. A started-but-not-enabled instance will not
  survive a reboot, while an enabled-but-stopped one will be started on the next
  boot. Requires the watchdog daemon to be running.
- Comprehensive event validation in `commands/handlers/events.sh`
- Command-specific help for all event commands
- Unit tests for event logic library (`tests/unit/test_events_logic.sh`)
- Integration tests for event modules (`tests/integration/test_events_module.sh`)
- player presence v1 — player_addr/session_key/reason event params + join/left
  detection regexes for stationeers/romestead/valheim/corekeeper; kick/ban +
  concurrent-join deferred to a future version.
- Palworld native blueprint (`blueprints/palworld.bp.yaml`) — SteamCMD dedicated
  server (app `2394010`, anonymous), `PalServer.sh` on `8211/udp` + `27015/udp`
  query.
- Palworld player-presence detection — `player_joined_regex`/`player_left_regex`
  authored from real server output, correlating on the SteamID64 (`id`). Join
  edge is the "joined the server" world-load line, not the earlier "connected"
  handshake; leave resolves the same identity via the session map.
- Blueprint validation now requires every container service to declare
  `network_mode: host`. KGSM containers are host-networked so the host firewall
  (ufw / kgsm-firewall) governs them through the `INPUT` chain exactly like
  native instances, and the compose `ports:` block stays the declarative source
  for firewall/UPnP. A bridge-networked service would DNAT-publish those ports
  into Docker's `FORWARD`/`DOCKER-USER` path, bypassing the host firewall; such a
  blueprint is now rejected before it can produce an instance.

### Fixed
- **Container `instance_stopping` lifecycle event now fires reliably, emitted
  host-side.** `templates/manage.container.d/03-lifecycle.sh`'s `_stop_server`
  now appends `{"type":"instance_stopping","ts":"<ISO-8601-UTC>"}` to
  `${instance_events_dir}/lifecycle.ndjson` immediately before running
  `docker compose ... down`. Previously this event was only emitted by an
  in-container `INT`/`TERM` trap (see kgsm-containers'
  `templates/container.manage.sh` `_emit_lifecycle`), which is unreachable
  for the vast majority of stops: once `_start`'s final `exec` replaces that
  bash process with the game binary, no in-container bash remains to catch
  the signal a `docker stop`/`compose down` sends. kgsm-watchdog tails
  `lifecycle.ndjson` to drive UPnP port-close on `instance_stopping` — this
  fix makes that reliable for containers instead of depending on a narrow
  pre-exec signal-timing window. Best-effort/guarded: a write failure never
  fails the stop, and a guard failure is skipped silently rather than
  emitting bad data. The in-container trap is left in place as a harmless
  redundant emit (UPnP-close is idempotent).
- **Host→container console input actually works now.** `_send_input`/
  `_send_save_command` in `templates/manage.container.d/04-io.sh` previously
  shelled out via `docker exec -i <container> "$MANAGEMENT_FILE" --input`,
  which appended the command to `$instance_socket_file` inside the
  container — a FIFO that only the in-container `_start_background()` ever
  creates. Container instances always launch through the foreground
  `_start()` (compose runs them in the foreground), so that FIFO never
  existed and every console-input send silently failed. Fixed by writing
  directly to a new, independent `${instance_events_dir}/command.fifo` on
  the existing `/run/kgsm` bind mount (mirrors how
  `manage.native.d/04-io.sh` writes straight to its own host-visible FIFO).
  The in-container half (creating the FIFO, keeping it open, and wiring it
  to the game's stdin) lives in kgsm-containers.

### Changed
- Event system now uses command-based CLI instead of flag-based
- All event emission calls updated across all modules
- Event dispatcher in `core/events.sh` uses new command format
- Improved error messages for invalid events and parameters
- `kgsm start` no longer auto-launches the `watcher.sh` readiness watcher on a
  successful start. The resident **kgsm-watchdog** daemon is now the canonical
  detector of `instance_ready` for native instances (it matches the blueprint's
  `startup_success_regex` against the game log itself), which made kgsm's own
  bash log/port watcher redundant on that path — and it was already broken
  under the watchdog spawn path, since it blocked waiting for a
  management-script PID file the watchdog's cgroup spawn never writes. kgsm
  itself performs no readiness detection any more. `watcher.sh` /
  `watcher.logs.sh` / `watcher.ports.sh` remain available as manual CLI
  commands (`kgsm watcher start|status|test <instance>`), they are simply no
  longer invoked automatically.

### Technical Details
- All 28 event types supported with full parameter validation
- Transport delegation maintained (socket and webhook run in parallel)
- JSON payload generation remains in module layer (jq dependency)
- Event constants exported globally for external script consumption
- Complete I/O/logic separation following KGSM architecture standards

## 2.1.0

**Changes**
- Instance config file have been moved to the instance working directory for easy access and even more instance independence from KGSM.
- Named arguments for `--install` and `--uninstall` have been moved to a more semantic `--create` and `--remove` across modules. Old argument kept to avoid breaking changes, they act as aliases for the new ones.
- Added missing `--input` functionality to container management scripts.
- Instance config file is now generated based on the `templates/instance.tp` file.
- The `--info` command now outputs raw instance configuration file contents instead of computed values. Use `--info --json` for structured JSON configuration data ideal for automation and scripting.
- Enhanced `--status` command with unified behavior across all instance types (systemd, standalone, container) and added `--status --json` support for web interfaces and APIs.
- Added flexible log line control to instance management scripts with `--tail <number>` option, including Unix standard aliases `--lines <number>` and `-n <number>`. Works for both static log viewing and live log following.
- Complete rework of interactive mode (`commands/interactive.sh`) with improved user experience, enhanced visual design using color-coded interface, hierarchical menu navigation, context-aware system overview, and comprehensive help system.

**Bug fixes**
- Removed duplicate debug tracking in the management templates
- Fixed but where instance config variables were not loaded correctly across modules
- Fixed interactive mode not checking correctly for which instance integrations were already set up or not. (`Modify` option)
- Fixed `kgsm -i <instance> --status` not displaying correctly if the instance was active or not.
- Fixed the `kgsm --blueprints --json` having two different structures for native and container based blueprints, now they have the same structure but with missing field values for the container blueprints.
- Fixed test_instances_module_comprehensive to use consistent command syntax with --instance flag for info, status, and remove functionalities.

## 2.0.1

**Bug fixes**
- Fixed erroneous output from `instances.sh` module when listing instances in json format.
- Fixed instance installation datetime format.
- Fixed `instance_name` not being set before emitting the "instance_installation_started" event.
- Fixed `instances.sh` module displaying `--follow` as an invalid argument, after exiting.
- Fixed `blueprints.sh --list --detailed --json` output containing mixed object formats for container and native blueprint, now both have the same structure.
- Added new `BlueprintType: [Container | Native]` field in the json output of `blueprints.sh --list --detailed --json`

## 2.0

This is a major version release and is not compatible with previous versions of KGSM.

> It is highly recommended to use a fresh start with KGSM 2.0 to avoid compatibility issues.

A migration module has been introduced to help transition existing instances from v1.* to v2.0:

```sh
./kgsm.sh --migrate
```

> [!WARNING]
> This will convert all instance configuration files to the new format and regenerate all `<instance>.manage.sh` files to make them standalone.
> This is necessary as KGSM now delegates actions to each instance's management file.
>
> **Back up your important files/servers before migration.**

Version 2.0 represents a comprehensive core rewrite to support the following new features:

**Standalone Instances**

- Each instance receives its own self-sufficient `<instance>.manage.sh` script
- Instances function independently, handling server operations, backups, updates, and management
- Optional symbolic links in system `$PATH` enable global access
- KGSM is only needed for initial setup, not ongoing operations

**Container-based Blueprints**

- Full support for container-based instances alongside native deployments
- Curated images available in the [KGSM-Containers](https://github.com/TheKrystalShip/KGSM-Containers) repository
- Feature parity with native instances
- Requires `docker` and `docker-compose`

**UPnP Support**

- Automatic port forwarding configuration, configurable per instance

**Breaking Changes**

- New instance configuration file format (requires migration)
- Blueprints reorganized into subdirectories (`custom/default` and `container/native`)
- New blueprint format (custom blueprints require manual migration)
- Command syntax changed: `--install/--id` replaced with `--create/--name`
- Updated config.ini format
- Renamed override functions (see overrides.tp for new names)
- Log command behavior changed: `--logs` shows last 10 lines; `--logs --follow` for continuous output

## 1.7.3

**Bug fixes**
- `installer.sh` failed to store the new version after updating KGSM.

## 1.7.2

**Bug fixes**
- Removed warning messages from `installer.sh` as they were interfering with the `--version` argument output.

## 1.7.1
- `version.txt` has been added back to repository to allow previous versions of KGSM to update correctly since they are reliant on that file. However, past `1.7.0`, the file is not needed or used for anything and will be automatically handled by `installer.sh` whenever it's called.

**Bug fixes**
- Incorrect function call in `kgsm.sh` for the `--update-config` flag.

## 1.7.0 - Maintenance Update

This release focuses on improving internal code quality and enhancing debugging capabilities to make troubleshooting easier. The introduction of standardized exit codes across all scripts allows for better error identification, while the newly implemented logging system enables persistent tracking of operations.

- **Descriptive exit codes**: Implemented across all modules to provide clear information about errors and their causes.
- **Logging**: KGSM and its modules can now write operation logs to a file if enabled in `config.ini`.
- **Update checker**: Added the `./kgsm.sh --check-update` command to verify if a new version is available.
- **Contributor guide**: A `CONTRIBUTING.md` file has been added to the repository to assist contributors.
- **Force kill game server**: `[instance].manage.sh` includes a new `--kill` argument to terminate unresponsive game servers. This is used internally by the `[instance].manage.sh` file in conjunction with a timeout mechanism during the normal `--stop` procedure.
- **Instance activity check**: `[instance].manage.sh` now includes a `--is-active` flag to verify if a game server is running. This is called internally by `commands/instances.sh` for more accurate status reporting.
- **Template update**: The `manage.tp` template has been updated to include the `--kill` flag for newly created instances.

To apply the new `[instance].manage.sh` changes to existing instances, run:
```sh
./commands/files.sh -i [instance] --create --manage
```

- **Environment simplification**: Modules no longer require `KGSM_ROOT` to be set before execution.
- **Installer consolidation**: The `installer.sh` script now handles installation, version control, and updates. Update-related tasks can be accessed through `kgsm.sh`, eliminating the need to call `installer.sh` directly.
- **Codebase refactoring**: `commands/include/common.sh` has been split into sub-modules to improve code organization and responsibility separation.
- **Versioning improvements**:
  - The `version.txt` file has been replaced with `.kgsm.version`.
  - KGSM versions now align with GitHub Releases instead of relying on a repository file.

**Bug fixes**
- **.editorconfig corrections**: Fixed incorrect `indent_style` settings for some file types.

## 1.6.1
- New `--update-config` parameter for `kgsm.sh` to merge new options added to `config.default.ini` to user defined `config.ini`.
- `config.default.ini` options are now a bit better organized

**Bug fixes**
- `commands/instances.sh` now reflects the correct default value for `INSTANCE_RANDOM_CHAR_COUNT` for the instance ID generation.

## 1.6.0 - Events

Events provide a mechanism for KGSM to communicate with other processes while remaining completely standalone and lightweight. By using a Unix Domain Socket for inter-process communication (IPC), KGSM can emit events for various actions happening under the hood. This enables other processes, like [KGSM-Bot](https://github.com/TheKrystalShip/KGSM-Bot), to listen, interpret, and react to these events.

Leveraging KGSM as the source of truth allows dependent processes to operate with minimal configuration, focusing solely on reacting to the incoming data.


- Unix Domain Socket support for IPC.
- New configurable option in `config.default.ini` to enable/disable events and set the socket path. Make sure to add the new configuration to your own `config.ini` file to enable events.
- New module: `commands/include/events.sh`.
- Event emissions for all major stages and actions, from instance creation to removal, formatted as JSON using the existing jq dependency.
- Optional `--json` argument for `commands/instances.sh` and `commands/blueprints.sh` to display information in JSON format. Documented in the `--help` command for both modules and the `kgsm.sh --help` documentation.
- Optional `KGSM_BRANCH=` option in `config.default.ini` allowing you to update KGSM from either the `main` development branch or the `dev` testing branch.

**Bug fixes**
- Corrected missing colored output in several modules.

## 1.5.2

**Bug fixes**
- Instances with systemd as a lifecycle manager were not getting logs followed.

## 1.5.1

**Bug fixes**
- Wrong argument order in `commands/instances.sh` for `--logs`.

## 1.5.0
**Breaking changes**
- `kgsm.sh --instances` now prints a list of instances without the .ini extension
- `kgsm.sh -i X --logs` will now follow rotating logs automatically, however the `--follow` flag has been removed and it will now always follow logs.


- Colored output! Commands will now display a message [SUCCESS / INFO / WARNING / ERROR] in color if the output supports it.
- Changelog: `kgsm.sh --update` will (going forward) show a list of commits and their messages between whatever version you have locally and whichever is the newest available after updating.
- Unturned dedicated server blueprint
- Silenced Factorio output on deployment
- Optimized internal `find` calls slightly

## 1.4.2

**Bug fixes**
- - `commands/instances.sh` was not properly accounting for `systemd` as a lifecycle manager, meaning the `--input` argument was sent to systemd which errored out.

## 1.4.1

**Bug fixes**
- Added missing internal `--debug` flag to a few module calls.

## 1.4.0
- New named argument: `./kgsm.sh --instance <instance> --save`, issues the save command to the instance if the instance has an interactive console and the $INSTANCE_SAVE_COMMAND is set.
- New named argument: `./kgsm.sh --instance <instance> --input <command>`, allows issuing ad-hoc commands to the instance if the instance has an interactive console.

These new features are currently **not** available for the interactive mode, they will be added at a later point.

## 1.3.2
- `kgsm.sh` now exposes an additional named argument for listing available backups for an instance. This was available in interactive mode but didn't have parity with the named arguments, now it does.

```sh
./kgsm.sh -i <instance> --backups
```
## 1.3.1

**Bug fixes**
- `commands/deploy.sh` now recursively copies and force overwrites the content of `$INSTANCE_INSTALL_DIR` with the contents of `$INSTANCE_TEMP_DIR`. The lack of force overwrite was causing the update process to fail for some game servers.

## 1.3.0

**Breaking** - Changed commands/instances.sh to use the `--id` argument as the full name of the instance instead of appending it to a predefined name.
Useful when you want to run a single instance and don't want to have the random numbers in the instance name.
> This also works through `kgsm.sh` Ex: `kgsm.sh --install factorio --id factorio`

Non `--id` generation hasn't been changed

**Bug fixes**
- Fixed `commands/instances.sh` now properly checks for duplicates when generating instance IDs.

## 1.2.7

Added new default blueprint for [Don't Starve Together](https://store.steampowered.com/app/322330/Dont_Starve_Together/)

**Bug fixes**
- Fixed return and error checking conditions in factorio.overrides.sh

## 1.2.6
Added default blueprint for [Necesse Dedicated Server](https://store.steampowered.com/app/1169040/Necesse/)

## 1.2.5

Added possibility to use `kgsm.sh` from the `$PATH`.


Example:
Create symlink
```sh
sudo ln -s /path/to/kgsm.sh /usr/local/bin/kgsm
```

Call `kgsm` from anywhere:
```sh
kgsm --version
```

## 1.2.4
Added new `[-f | --follow]` argument when fetching logs to read in real-time.
Usage:
```sh
./kgsm.sh --instance <instance> --logs [-f | --follow]
```

**Bug fixes**
- Fixed bug in instances.sh modules when fetching instance logs.

## 1.2.3

**Bug fixes**
- Fixed `commands/deploy.sh` bug that expected the instance's install directory to be empty. That's no longer the case since version `1.2.0`.

## 1.2.1

**Bug fixes**
- Fixed bug in `commands/backup.sh` restore it didn't read the version number.

## 1.2.0

- Added new `config.default.ini` option COMPRESS_BACKUPS that if enabled will use tar to reduce the size of the backups. This option is disabled by default and it has to be manually enabled in your `config.ini` file.

**Bug fixes**
- Fixed issue with exit codes in various modules and kgsm.sh.

## 1.1.1

**Bug fixes**

- Fixed Factorio override not using the `--version` passed to it when downloading, defaulting to latest.

## 1.1.0

**Breaking change**: Moved `--uninstall <instance>` arg to top level instead of having it nested.
Previous: `./kgsm.sh --instance <instance> --uninstall`
New: `./kgsm.sh --uninstall <instance>`

Added feature: ability to add/remove systemd and ufw integration from already created instances.
From the interactive mode menu, select the `Modify` option, then follow the prompts.
Named arguments:

```sh
./kgsm.sh --instance <instance> --modify [--add | --remove] [systemd | ufw]
```

Both the interactive mode `Help` option and `./kgsm.sh --help` will display these new options.

**Full Changelog**: https://github.com/TheKrystalShip/KGSM/compare/1.0.4...1.1.0

## 1.0.4

**Bug fixes**

- Fixed `commands/update.sh` not taking into account the instance lifecycle manager when stopping/starting an instance.

## 1.0.3

- Added new module, blueprint, instance, template common loading functions.
- Changed internal module vars naming convention to lowercase.

**Bug fixes**

- Fixed wrong argument bug when restoring backup using interactive mode.
- Fixed `commands/update.sh` not asking for root password when issuing systemctl commands.
- Fixed some inconsistencies between `--help` functions on different modules.

- Known issue:
  - `commands/update.sh` doesn't take into account the INSTANCE_LIFECYCLE_MANAGER and defaults to using systemctl to manage instances

## 1.0.2

- Changed `commands/instances.sh --print-info` to `commands/instances.sh --info`.
- Added shorthand `kgsm.sh [-i, --instance]` argument option to match the modules.
- Added `kgsm.sh --instance <instance> --info` argument to print out instance information.

**Bug fixes**

- Fixed systemd file permission and ownership.

## 1.0.1

**Bug fixes**

- Fixed UFW rule formatting in various blueprints to a more explicit definition
- Fixed UFW rule file permissions bug where the file didn't belong to root.
- Fixed port definitions across blueprints to correctly reflect the defaults recommended by official documentation.

## 1.0.0

Initial Release
