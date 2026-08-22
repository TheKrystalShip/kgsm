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

- **`--force` on a start reaches the watchdog, so it overrides both checks.** `--force` skipped this
  CLI's capacity gate and stopped there, which overrode nothing for a native instance: the daemon
  runs its own check with the memory promised to instances already starting subtracted as well, so it
  refuses everything this gate would and more. The flag now rides the dispatch as
  `POST /start/<name>?force=true` — the URL is all this transport has, since it sends no body and
  reads back a status code — and `restart --force` gets it too, because a restart's start half is an
  ordinary start. The daemon still never overrides itself: its autostart and crash-restart take the
  verdict as final, and only an explicit start carries the flag. The refusal message offers `--force`
  as a remedy now that it is one.

- **A capacity refusal from the watchdog exits `EC_INSUFFICIENT_MEMORY`, like the CLI's own.** The
  daemon runs its own node-capacity check and answers a question this CLI cannot: it knows what the
  instances already starting have been promised, which `MemAvailable` does not yet reflect. So a
  start this CLI's gate passes can still be refused there, and it is the same refusal — the watchdog
  says so with `507` on the control socket and `__watchdog_dispatch_lifecycle` maps it to `51`, so a
  caller needs one rule rather than two. A refusal is not a failure: nothing was attempted and
  nothing is wrong with the instance, so `EC_ERROR` would invite a retry that gets the identical
  answer and read as a fault in the server. `restart` needs no mapping of its own — it is a stop
  followed by a start, and the start half already returns this code, which the command layer reports
  as *stopped but could not be started again, and is now down*. The refusal is said out loud where
  it is dispatched: the transport keeps the daemon's status code and discards its body, and the
  figures behind it are in the daemon's own log. `--force` is deliberately not offered as a remedy —
  it skips **this** CLI's gate, and the daemon has no override to skip.

- **A start is refused when the node has no room for it.** Before a native instance is spawned, the
  memory gate compares what the instance is expected to need against what the node reports available,
  and refuses when going ahead would leave less than `memory_gate_headroom_mb` free (default 1024).
  The requirement is the instance's own `memory_cap_mb` when set — the cgroup ceiling the watchdog
  enforces, so it bounds what the node can actually lose — otherwise the blueprint's advisory
  `metadata.min_ram_mb`. With neither declared the gate cannot answer and the start proceeds; no
  figure is invented to fill the gap. The reading is `MemAvailable`, not `MemFree`, because the
  latter excludes reclaimable page cache and would refuse starts that are perfectly safe.
  The refusal names all three figures and exits `EC_INSUFFICIENT_MEMORY` (51), distinct from a
  failed start so a caller can tell "would not fit" from "tried and failed". `--force` on `start`
  and `restart` skips the check, for the operator who knows a declared figure overstates what a game
  actually uses. New `[resources]` section, config schema v9 with its migration.

- **The test runner accounts for every test function a file declares.** Discovery writes the list
  of `test_*` functions to the test log as a plan before the file is sourced, each function records
  its own result, and the runner reconciles the two afterwards: a declared function with no result
  is a failing subtest named in the TAP failure details, and it fails the file. A test harness that
  runs a subset of the tests it found is the one failure it must never absorb — the suite stays
  green while coverage disappears — so a shortfall is now loud. `pass_test` and `fail_test` record
  one assertion result against the running function and return, like every `assert_*`; `bail_out` is
  the one call that ends a run early. A `--function` naming something the file does not define is a
  typo rather than an empty success, and reports as a function that never ran.

- **`instances status` prints the recent log lines it read.** `recent_logs` is a JSON array of
  lines in every case — one element per line of the tail, an empty array when the instance has
  logged nothing — so the field's type does not depend on whether a log exists. The human-readable
  status renders those lines under *Recent Activity* instead of failing to iterate them, and a JSON
  consumer reads one shape.

- **A backup records why it was taken and whether rotation may take it.** The manifest is
  `schema_version: 2` and carries two deliberately separate fields: `reason` — a fact fixed at
  capture (`manual`, `scheduled`, `pre-update`, `pre-restore`, `incident`), never edited — and
  `retention` (`prunable` | `pinned`) — a policy, and the one part an operator revises. Every
  creation site states its own reason, so the pre-update archive an update takes and the safety
  archive a restore takes are identifiable on disk instead of being inferred from recency.
  `instances create-backup` takes `--reason` and `--retention`; `instances pin-backup` /
  `unpin-backup` change the policy afterwards, emitting `instance_backup_pinned` /
  `instance_backup_unpinned`. `instances prune-backups` skips pinned backups and does not count them
  toward `--keep=N`, so pins cannot erode the rotation; `instance_backups_pruned` gained `Pinned`
  alongside `Deleted` and `Kept`, so a sweep that protected everything is distinguishable from one
  that found nothing to do. A manifest written without the fields reads back as `retention: prunable`
  — its existing behaviour — and `reason: null`, which is unknown and never guessed. `delete-backup`
  removes a pinned backup like any other: pinned means prune will not take it, never that you cannot.

- **`instances config-list` reports every key with whether it can be set.** The settable flag comes
  from `__is_protected_instance_config_key` — the same function `config-set` itself calls — so what a
  reader is told it may change is exactly what the setter will accept, and the two cannot drift.
  `--settable` narrows the listing to those keys; `--json` emits them as an array.

- **`network ports list-used` names the ports it found.** Every row is
  `<port>/<protocol>`, with the process holding it when the socket can be attributed, and both
  `ports list-used` and `ports conflicts` take `--json`. The scan's own progress reporting stays on
  the human path only, so a machine reading the conflict list sees an array of findings and nothing
  else — an empty one when there are none.

- **The release build lints the engine and can fail on it.** `shellcheck` is the only gate the
  bash half of KGSM has, and it now excludes exactly the categories a per-file lint cannot answer
  here — unquoted exit codes in expansions and in `case` patterns, `config_*`/`instance_*` names
  parsed out of `.config.ini` at runtime, the sourced-not-executed `manage.*.d/` fragments,
  dispatcher-reached handlers, and variables a sourcing script consumes. Everything else fails the
  build, and the findings that were left are fixed: the newest rotated log is found with `find`
  rather than by parsing `ls`, an event's parameter spec is split with `read -ra` so a name can
  never glob, and a keypress is read with `-r`.

- **Journal retention ages a segment by its name, not its mtime.** `events journal prune` used
  `find -mtime`, which measures when a file was last *written to* — a restore, a copy or a backup
  tool moves that without any event having moved, so a recovered journal was pruned by when it was
  recovered. The segment's name is its date whatever the filesystem thinks. Every other producer's
  writer applies this same rule (`TheKrystalShip.KGSM.Journal` 1.4.0), so a merged page now ages
  uniformly instead of the engine's half of it ageing on a different clock.

  A segment dated exactly on the boundary is **kept** — the window is "this many days of history",
  and rounding it inward returns one day less than the number an operator configured. A file in the
  journal directory whose name is not a date is left alone rather than guessed at.

- **An instance config value survives a double quote.** The config is written as `key="value"` and
  read back two ways — the management script sources it, everything else parses the text — and
  neither write path escaped the value. A quote inside it closed the assignment early and left the
  rest of the line to be parsed as code, so the file stopped sourcing at all; `config-set` and the
  install-time template both did it. Values are now escaped on write (`\`, `"`, and `` ` ``; `$` stays
  live, because `executable_arguments` carries `$instance_level_name` into the config precisely so it
  expands on source), and the three text readers — `__get_instance_config_value`,
  `__source_with_prefix`, and `instances info --json` — undo it, so a parsed value and a sourced one
  are the same bytes. Without the unescape a regex arrived with every backslash doubled, which
  compiles and then matches nothing.
- **Necesse detects player joins and leaves.** Authored from real server output. The two sides carry
  disjoint identity — the connect line has the SteamID64 and the endpoint, the disconnect line has the
  SteamID64, the character name and the reason — so `key` pins the session key to the id, the only
  field on both. This is the first blueprint whose pattern needs a literal double quote, which is what
  surfaced the escaping bug above.

- **A lifecycle verb reports a state change only when the state changed.** The verbs are idempotent —
  the supervisor answers a stop for an already-stopped instance, or a start for an already-running
  one, with success, and it is right to — but the command layer turned that success into an event. So
  `instance_stopped` was recorded for a server that had been down for hours, most visibly on every
  uninstall (the Control Panel stops before removing, so uninstalling a stopped instance wrote a stop
  into the audit trail that never happened), and `instance_started` would have told every surface a
  healthy server had just begun booting.

  The run-state is now sampled before the verb runs and the fact is emitted on a real transition:
  `instance_started` only when a run began, `instance_stopped` only when one ended, and a restart's
  `instance_restart_stopped` only when there was an old run to bring down. The verbs themselves are
  unchanged and still succeed — an idempotent command is not an error, it just is not news.
  ⚠ `unknown` counts as a transition: suppressing on ignorance would lose a real one, while emitting
  on ignorance at worst repeats what the consumer already knows.

- **Every long operation now reports its outcome and its steps.** From an audit of all 56 events, the
  gaps were all the same shape as the restart's: a bracket says a run is happening, and nothing says
  what it did.

  - **`instance_update_failed`.** An update that ends without the version moving had two meanings and
    one appearance — it found nothing to do, or it could not do it. Since a consumer settles a run on
    its bracket, an update kgsm REFUSED reported itself everywhere as a completed one.
  - **An uninstall says it stopped the server.** Deregistering from the watchdog kills a running game;
    nothing emitted `instance_stopped`, so run-state read Online for the whole file removal and the
    audit trail never recorded that players had been dropped. Emitted only when the instance was
    measurably up.
  - **The backups an update and a restore take are announced.** Both capture the state they are about
    to overwrite from inside the management script, which cannot emit — so the rollback point for the
    riskiest operation there is existed with nothing to announce it. The command layer records the
    backup ids before the run and emits `instance-backup-created` for whatever appeared, each carrying
    the version from its OWN manifest.
  - **`instance_backup_started`/`_finished` and `instance_restore_started`/`_finished`** bracket the
    two long backup verbs, like every other long verb.
  - **An update reports its download and deploy**, with the same events an install emits for the same
    work, through an `--emit-cmd` the caller hands the management script. Silent when not given one,
    so the script still runs standalone. ⚠ Existing instances pick this up on
    `kgsm files management create <instance>`.
  - **`*_finished` is emitted after the fact it brackets**, in install, uninstall and update — stop
    and restart already did, and the reason is theirs: a consumer that re-reads on "the run ended"
    must find the outcome recorded, not the state from before it.
  - **A failed step no longer skips the rest of an uninstall's cleanup.** `files.sh remove` returned at
    the first failure while the uninstall carried on deleting directories, leaving a firewall rule or a
    symlink behind for a server that no longer exists.

- **Events emitted from a delegated module are recorded again.** `EVENT_CONFIGS` is an associative
  array and bash cannot export one; the "events module loaded" flag beside it *is* exported. So any
  child process — every module reached through the delegator (`files.sh remove`, `directories.sh
  remove`), and anything a management script shells out to — inherited the claim without the table,
  skipped loading it on that claim, and had every event it emitted rejected as an invalid type. In
  silence, because `__emit_event` warned only when the journal write failed.

  The table's presence is now what says the module is loaded, in both guards. `instance_files_removed`
  and `instance_directories_removed` had not been emitted since 2026-07-29; they are emitted again.
  **`__emit_event` now warns on every failure**, not just a journal write — a reporting path that
  fails quietly is indistinguishable from one nobody wired up, which is how this lasted.

- **A restart reports its middle.** `restart` runs the stop and the start through the pure logic
  rather than the stop and start commands, so nothing was emitted between
  `instance_restart_started` and `instance_restarted` at the very end. For the whole shutdown —
  seconds to a minute, and the full drain of a game that saves its world on the way out — the
  process did not exist and every consumer still read the instance as running, because the bracket
  says only that a restart is in progress and the state it can fall back on is the one from before.

  `instance_restart_stopped` is that middle: the old run is down, the new one has not been spawned
  yet. It is a step inside one operation, deliberately not `instance_stopped` — that one is the fact
  that somebody stopped a server, and a restart is not that (kgsm-lib classifies the new event
  `Phase`, so it moves state without adding an audit row or a notification to every restart).

  The sequencing stays in `__logic_instance_restart`, which now takes an optional function to call
  once the stop half is down; the command layer passes the emitter, so the logic layer keeps emitting
  nothing itself.

- **`files firewall disable` no longer records the close.** The kgsm-firewall authority writes the
  rule and sees the backend accept it, so it is the one component that can honestly say a port
  closed, and it records the edge in its own journal. Emitting `instance-ports-closed` here as well
  put a single change in the record twice under two different authors — and the ports listed came
  from this caller's config read rather than the authority's measurement. It was the last firewall
  emit left in the engine after the rest of that machinery was removed.
- **The event envelope is v1** — every emitted event carries `V: 1`, a millisecond-precision
  `Timestamp`, and `ProducerVersion` in place of `KGSMVersion`. The envelope is a cross-producer
  contract now (authority: `../event-journal-federation-plan.md` §2): each component that writes an
  event journal writes this same shape, so one reader merges them all.
  - Milliseconds are load-bearing rather than cosmetic. A single appender takes its ordering from the
    file it writes, but events read across several journals at second granularity order arbitrarily
    inside each second — exactly where causally adjacent events sit, a start and the port opening
    that follows it landing within one second routinely. `%3N` is GNU `date`, which this Linux-only
    engine already depends on.
  - `ProducerVersion` names whoever emitted an event rather than KGSM specifically, so one field
    answers "which build produced this line" whatever produced it. It is separate from `V` because
    one says how to read the line and the other says which build wrote it.
  - `OpId`, `RunId` and `During` are reserved in the envelope for correlating events belonging to one
    operation. KGSM writes none of them.
- Events system refactoring to command-based architecture

## [Unreleased] - 3.0.0 (Major Version)

### Added — an Arch package, built from the tested binaries

`packaging/PKGBUILD` builds this project into a pacman package. It compiles nothing: CI publishes
first and the recipe places that output, so the packaged bytes are the tested bytes. `pkgver()`
reads `deploy/version.sh`, so the package never restates a version.

The install prefix stays `/opt/<project>` — the same path `deploy.sh` uses — which is what lets the
committed systemd unit ship verbatim instead of being rewritten at packaging time.

Config files are listed in `backup=()`, so an upgrade writes `.pacnew` beside a file you edited
rather than over it. The unit, the sysusers fragment and the leaf descriptor are packaged files, so
the descriptor can never lag the binary it describes. Nothing is enabled by a scriptlet: pacman's
own hooks handle the service account, the state directories and the daemon reload, and enabling a
unit is the administrator's decision.

`deploy/tree-excludes.txt` now holds the list of checkout-only files, read by both `deploy.sh` and
the package, so the deployed tree and the packaged one are the same set. It excludes the bundled
VS Code debugger extension, which had been shipping to `/opt/kgsm`.

### Changed — the engine's entry point is `/usr/bin/kgsm`

`/usr/local` belongs to the local administrator and no package may write there. Settings files and
leaf descriptors already defaulted to `/usr/bin/kgsm`; units and `setup.sh` now agree with them.

### Added — one machine-readable version, read rather than restated

`deploy/version.sh` prints this project's version from the single file that declares it, and
`--pkgver` prints the form pacman accepts (a `pkgver` may not contain a hyphen; ordering survives it,
since `vercmp` puts `3.16.0rc3` before `3.16.0`). Packaging asks for a version instead of carrying a
copy that can fall behind the binary.

### Added — the host requirements are declared, not described

`deploy/kgsm.requires.json` states every command the engine needs, each with its Arch package name
and a probe. It supersedes the README's dependency list, which demanded `inotify-tools` the engine
never uses, marked the optional `steamcmd` as required, and omitted `yq` — which blueprint parsing
cannot run without.

`yq` is recorded as `go-yq` specifically: Debian's `yq` is an unrelated Python tool with
incompatible syntax, so a name-only check passes and `.bp.yaml` parsing then fails as though the
YAML were corrupt.

`deploy/sysusers.d/kgsm.conf` declares the `kgsm` service account.

### Changed

- **kgsm no longer records firewall edges.** `__emit_firewall_edges`, the
  `KGSM_FIREWALL_APPLIED_EDGES` drain and both `__firewall_edges_record` call sites are gone.
  kgsm-firewall performs the change and records it in its own journal; kgsm shelled that
  authority's CLI and then wrote the line, which named the wrong author.
  Two guards went with them, and they existed only to stop one edge being recorded twice: the
  `__watchdog_available` probe on the start path, and the `_watchdog_owns_teardown` probe on the
  stop path — the latter asked *before* the stop specifically because the supervisor forgets an
  instance the moment it goes down. With a single author there is nothing to deduplicate.
  Provenance still reaches the record: the authority's CLI reads `KGSM_EVENT_ACTOR` /
  `KGSM_EVENT_ORIGIN`, the same variables kgsm's own emitter reads, so the two paths cannot name
  different actors for one action.

### Fixed

- **Installing a server no longer reports a version update.** `install` emitted
  `instance-version-updated` with `OldVersion` `0` after saving the version it had just
  installed, so every install produced an update event beside its install events — and every
  consumer that treats that event as "this server moved to a new build" acted on it: the API
  wrote a `server.update` audit row for each `server.install` (16 of each in this host's audit
  log), the Discord bot announced *"was updated to"* for a server that had just appeared, and
  the assistant's history carried both. `0` was never a version anything ran; it was a
  placeholder for "there was nothing here". The install path emits no version event at all now
  — the version a new instance lands on is part of the instance that
  `instance_installation_finished` / `instance_installed` announce, and it is read from the
  instance. `OldVersion` is therefore always a build that actually ran, which is what makes the
  event comparable. The update path is unchanged and still emits only when the version really
  moved.

- **A Project Zomboid server that dies reports that it died.** The shipped `start-server.sh` launches
  the JVM and then ends in an unconditional `exit 0`, so whatever happened to the server, the script
  succeeds: a JVM the kernel's OOM killer removed reaches kgsm-watchdog as *"exited cleanly (exit
  0)"*, and a crash loop reads as a run of clean exits. That is the one thing a supervisor must not
  be told, because a clean exit is precisely what distinguishes a server that stopped from a server
  that died. A new `overrides/projectzomboid/07-deploy.sh` replaces the launcher after every deploy
  and update with one that `exec`s the server, so the supervised process **is** the server and its
  exit code is the server's by construction rather than by remembering to propagate it. Measured
  against a stub: the shipped script reports `0` for a SIGKILLed server, the replacement reports
  `137`.

  Deliberately identical to the shipped script otherwise, including `jre64/lib/amd64` on
  `LD_LIBRARY_PATH` — a directory the current payload does not contain, so the `libjsig.so` preload
  fails and is ignored exactly as before. Correcting that would switch on JVM signal chaining, which
  changes how the server handles the SIGTERM that stops it; repairing an exit code is not the place
  for it.

  The launcher is rewritten in place rather than added beside the shipped one because
  `executable_file` is a protected instance key — an existing instance could not be pointed at a new
  file. Existing instances pick the fix up on their next `instances update`.

- **A Project Zomboid instance starts unattended.** With no admin account the server prompts for a
  password on stdin and waits there indefinitely; a KGSM instance has nothing attached to answer it,
  so it hangs while `kgsm start` reports success and status reports Active — both true, since the
  process really is running. The blueprint now passes `-adminusername admin -adminpassword
  CHANGE_ME_ON_FIRST_START`, which creates the account outright and skips the prompt.

  ⚠ **That password is a placeholder, identical on every KGSM install, and a Project Zomboid admin
  can do anything in-game.** Change it before the server is reachable by anyone untrusted. The
  argument only ever *creates* the account, so once one exists it is changed from the console with
  `setpassword`, not by editing the argument.

- **Project Zomboid's advisory memory metadata reflects what it uses.** `min_ram_mb` 2048 → 8192 and
  `recommended_ram_mb` 4096 → 16384; `base_disk_mb` 5120 → 7168, measured from a vanilla install.
  At the moment the kernel killed a loading server it held ~1.1 GB `anon-rss` and ~7.0 GB
  `shmem-rss`, so the old advisory numbers were low enough to invite exactly that.

- **A rotated log is named for when the run ended.** `_rotate_log_file` (both the native and the
  container management-script modules) stamps the filename from the log file's last write — the last
  line the server printed — rather than the clock at the moment of rotation. Rotation happens at the
  next start, so the two quantities differ by however long the instance stayed stopped: an instance
  stopped on the 1st and started on the 5th named a run that ended on the 1st for the 5th. The
  timestamp is UTC, matching kgsm-watchdog's rotator, so both sort together in one `logs/` directory.
  Two runs ending inside the same second (a crash loop restarts after about a second) now fall back
  to a nanosecond-suffixed name instead of `mv` silently overwriting the earlier run.

  Existing instances carry a generated management script and keep the old naming until it is
  regenerated: `kgsm files management create <instance>`.

- **Valheim's blueprint runs the vanilla dedicated server.** It named `start_server_bepinex.sh`, a
  script only a mod loader installs, so `kgsm install valheim` produced an instance that could not
  start at all. It now runs `valheim_server.x86_64`, which takes the arguments and needs no
  `LD_LIBRARY_PATH` — the shipped `start_server.sh` cannot be used because it hardcodes its own
  name, world and password and forwards nothing, making every instance identical. With that:
  `-savedir $instance_saves_dir` keeps worlds and the access lists inside the instance instead of a
  shared directory in `$HOME`, a `-password` is shipped because the server refuses to start without
  one of at least 5 characters, `ports` drops its TCP half (the server opens no TCP socket), and
  `stop_command` is empty because Valheim reads no console input.

- **Terraria declares its moderation commands and only the protocol it listens on.** `kick {name}`
  and `ban {name}` come from the command list the server's own `help` prints, so `kgsm instances
  kick|ban` work on a Terraria instance instead of answering "does not support 'kick'".
  `unban_command` stays empty because the server has no such command — a ban is lifted by editing
  `banlist.txt` — and KGSM refuses the action rather than substituting one that would not lift
  anything. `ports` is `7777/tcp`: a running server holds a TCP listener and opens no UDP socket, so
  the previous `7777/tcp|7777/udp` opened a port nothing listens on.

### Added

- **Per-game operator guides under `docs/knowledge/games/<game>/`** — how to install, configure and
  troubleshoot one game's server once its blueprint exists, as `setup.md`, `configuration.md` and
  `troubleshooting.md`. This is the operator half of `docs/knowledge/`, whose existing documents
  cover authoring a blueprint. The guides describe KGSM's workflow rather than the manual install
  the public guides open with, and they do not restate ports, app ids or launch arguments, which the
  blueprint owns — a second copy of a value drifts and then outranks the engine in a reader's mind.
  Headings are phrased as the questions people ask, since each is indexed with its heading
  breadcrumb and retrieved by it. Each game's `setup.md` also states what the guides do **not**
  cover, with the excluded topic given its own heading — similarity cannot tell "this document
  answers the question" from "this document is about the same game", so an uncovered question
  retrieves the guide anyway, and a named section is what turns that into an honest answer instead
  of unrelated install steps. The build each guide was verified against lives in the game's
  `SOURCES.txt`, never in a `.md`: a version number sitting in indexed prose is retrieved by
  someone asking what the latest version of a game is and answered as though it were the current
  release. Measured — "what's the latest version of Terraria?" returned *"the current stable
  version of Terraria is 1.4.5.6"* on every rep, that being the build the guide was written
  against, and a local hit of that confidence also suppresses the web lookup that would have been
  right. The indexer walks `*.md` only, so a plain-text sibling keeps the information for a reader
  and out of the assistant's reach; attribution and licence stay in the document. Factorio,
  Terraria, Valheim, Minecraft and Project Zomboid are written; other games follow as each is
  measured.

  Project Zomboid's set leads with the one thing that stops a new server dead: with no admin account
  the server prompts for a password on stdin, and a KGSM instance has nothing attached to answer it,
  so it waits forever while `kgsm start` reports success and status reports Active — both truthfully,
  since the process is running. `-adminusername` and `-adminpassword` in the launch arguments skip
  the prompt entirely. The guides also record that this game's shipped `start-server.sh` ends in an
  unconditional `exit 0`, so a JVM killed underneath it is reported to the watchdog as a clean exit
  — for this game "exited cleanly" is not evidence that it did — and that Workshop mods are a
  first-class server feature here rather than a separate blueprint, needing an entry in both
  `WorkshopItems` (download) and `Mods` (enable), which are different identifiers.

- **`rcon_players_regex`** — a blueprint field naming how to read one player out of
  `rcon_players_command`'s output, applied per line with optional named groups `id` and `name`.
  Games word their rosters differently: Project Zomboid prints a header and one `-Name` line per
  player and states no id anywhere, while a columnar roster gives an id and a name. That difference
  is data about a game, so it belongs beside the command that produces it — a consumer polling RCON
  applies the pattern without knowing which game it is talking to, and a new RCON game is a
  blueprint, not a change to whatever does the polling. Empty means the output cannot be read, which
  turns RCON presence off for the game rather than inventing a roster out of the server's own prose.
  Materialized into the instance config and served on `instances info --json` like the other
  presence fields.

- **Every blueprint declares the RCON family** — `rcon_port`, `rcon_password`,
  `rcon_poll_interval_seconds`, `rcon_players_command`, `rcon_players_regex` — whether or not the
  game uses it, with empty values where it does not. A field that only appears on the one game
  already using it reads as a property of that game; the family being present on all thirty is what
  shows the capability belongs to every blueprint and is simply unwired for most. Nothing is guessed
  to fill them: an empty `rcon_port` leaves polling off, and values are authored only from a server
  observed answering them, the same rule the presence patterns follow. `templates/blueprint.tp`
  documents the family for new blueprints. Presence polling covers native instances, so a container
  blueprint declares the fields but nothing reads them yet.

### Changed

- **Project Zomboid's presence comes from RCON alone**; its `player_joined_regex` is now empty. The
  console announces a join as a Steam id with no name, RCON answers `players` with a name and no id,
  and nothing correlates the two — so running both produced two sessions for one player, one of
  which no leave could ever retire, because the console prints no leave line at all. The name is the
  half worth keeping: moderation addresses players by name, and a roster entry reading as a bare
  Steam id names nobody.

- **`instances delete-backup <instance> <id>`** — remove one backup by id. Only an id the engine
  itself lists is accepted, so a directory in the backups store carrying no manifest — a foreign
  directory, or a backup still being staged — cannot be deleted by naming it.

- **`instance_backup_deleted` and `instance_backups_pruned`** — the two backup-removal audit
  events. They are separate types because they answer different questions: a delete is an operator
  naming one snapshot, a prune is retention policy sweeping whatever fell outside the keep window.
  A reader asking who threw away a backup should not have to infer intent from a count, and one
  auditing retention should not have to filter out hand-deletes. The delete carries the backup id;
  the prune carries `Deleted`/`Kept` counts as JSON numbers, and a sweep that removed nothing emits
  nothing. Scheduled retention pruning was previously the one backup operation that destroyed data
  without leaving a record.

- **`instance_update_available`** — a newer build exists upstream and this server is not on it,
  carrying `CurrentVersion` and `LatestVersion`. The engine emits it, so every consumer gets the
  fact from the journal; nothing has to poll for it. `instance_version_updated` is what clears it.

- **`instances check-update <instance> --emit`** records what the check found beside the instance
  and emits the event when the upstream version has not been reported before. The recorded version
  is what makes a repeated sweep silent: only `--emit` writes it, so a check run by hand never
  consumes an announcement, and a sweep that finds the same version again says nothing. An instance
  whose own version cannot be read records the check but reports no update — "newer than unknown"
  is not a fact.

- **`instances list --status --json --fast` answers the update question from that record**, with a
  `checked_at` saying when the upstream was really fetched. Fast mode did no update check at all and
  reported `checked: false`; it now reports a genuine reading and how old it is, with no network on
  the read path. A `checked_at` is only ever written by a real fetch — never stamped onto a value
  read back off disk.

- **`version --stored-latest`, `--stored-checked-at` and `--save-latest`** on the generated
  management script. They live in the structural `01-config.sh` rather than the overridable
  `05-version.sh`, so the four games that override version handling keep working unchanged.
  An instance whose config predates `latest_version_file` derives the path, so nothing needs
  migrating.

### Fixed

- **A container instance's version is the digest of its images, not the tag it was pulled by.**
  `_get_latest_version` returned the literal string `latest` for every container, and the status
  surface compared that against the recorded version and reported it as a *checked* answer — so
  every container instance claimed an update was available, permanently, and `update` wrote the same
  placeholder back. The version is now the image digest the registry serves, read per image from the
  instance's own compose file; a multi-image instance fingerprints the sorted set, so its version
  changes when any one image does. An instance with nothing recorded reports `Unknown`, which is
  what makes the status surface report it as unchecked rather than compare against a placeholder.

- **An update check that could not run is no longer reported as "up to date".** Both status modules
  decided from `_compare_versions`, which returns the same error for *already current* as for *the
  remote did not answer* — so a steamcmd failure or an unreachable registry produced
  `updates_available: false, checked: true`. They now read the latest version directly and report
  `checked: false` when nothing came back. `_compare_versions` keeps its documented override-API
  contract and is untouched; nothing that has to tell the two apart calls it any more.

- **An install whose latest version could not be determined fails instead of recording an empty
  one.** An instance with no recorded version can never be compared against anything afterwards.

### Changed

- **Backups are compressed by default** (`enable_backup_compression=true`, config schema v8). A
  compressed backup is a single `data.tar.gz` with an sha256 digest in its manifest, and that digest
  is what `restore-backup` verifies before it touches the instance; an uncompressed backup is a
  `data/` tree with no single digest, so a restore has nothing to check it against. Backups already
  on disk are untouched and stay restorable — each manifest records its own `compressed` flag and
  restore reads that, not the config. An existing instance keeps the value baked into its own
  `.config.ini` until it is flipped with `instances config-set <instance> compress_backups=true`.

- **`instance_upnp_reasserted`** — a router forward that went missing while its instance kept
  running, put back by the watchdog's periodic sweep. Its own event type rather than a second
  `instance_upnp_opened` because the two answer different questions: an open accompanies a
  bring-up, whereas this one says the mapping disappeared with nothing on this host asking for it.
  It is the only evidence a reader gets that a router discards mappings it accepted — a router can
  report a lease as infinite and drop it anyway — and how often. Carries the same structured
  `Ports` payload as the rest of the network events, holding the subset that was missing rather
  than the instance's whole set.

- **An instance's ports are open exactly while it is running.** They open on every bring-up and are
  released on a deliberate stop, so a server that is not running holds nothing open on the host —
  the same lifetime its UPnP mapping already had, and for the same reason. `files firewall enable`
  opens nothing now: it marks the instance as one whose ports KGSM manages, which is what every
  consumer already read it as, and the rule is written by the start that follows. Because nothing is
  opened at install, enabling no longer depends on the authority being up, so a firewall-enabled
  install can no longer be blocked by it.

  A crash is deliberately not a close — the restart that follows still needs the ports, and a
  process dying is not a reason to tear down host state. `kgsm-watchdog` drives both edges for the
  native instances it supervises, including the boot auto-starts and crash-respawns the CLI never
  sees; this path is what covers a container instance and a host with no watchdog. Both are
  idempotent. An instance whose operator turned firewall management off is left alone, and an
  authority that is down is reported but never keeps a game server off the air.

  Both edges are audited, so a port opening is recorded the way a router forward already was.
  `instance_ports_opened` / `instance_ports_closed` carry the instance's ports as the canonical
  structured array, and are emitted by whichever component performed the transition, exactly once:
  the watchdog for the instances it supervises, KGSM for the bring-ups and teardowns it performs
  itself. Which one owns a teardown is settled BEFORE the stop — the daemon forgets an instance the
  moment it goes down, so asking afterwards reads "not supervised" for the very stop it just
  performed, and the close would be recorded twice. Nothing is emitted for an instance that opted
  out, declares no ports, or whose authority could not confirm the change.

- **Minecraft detects presence and declares its moderation commands.** `player_joined_regex` and
  `player_left_regex` match the connection pair (`logged in with entity id` / `lost connection:`)
  rather than the "joined/left the game" chat broadcasts: those are core server logging a mod does
  not reword, and they carry the player's address and the disconnect reason. The account UUID is
  logged on its own line, which a per-line matcher cannot correlate, so the username is the identity
  and `key` pins the session key to it on both sides — the address appears on the join line alone.
  The username is matched as Minecraft's legal charset anchored to the start of the message, so a
  pre-login `GameProfile@…` disconnect by someone who never joined raises no phantom leave. The
  game addresses a player by that same username, so moderation is `/kick {name}`, `/ban {name}`,
  `/pardon {name}`.

- **`restart` brackets its run with events.** `instance_restart_started` before and
  `instance_restart_finished` after, on every outcome. A restart is a stop and a start back to back —
  the longest of the lifecycle verbs — and it runs through the pure logic functions rather than the
  stop and start commands, so none of their events fire along the way: `instance_restarted` at the end
  was the only thing a consumer ever saw, and until it arrived the instance still looked like it was
  running normally. Finished says the run ENDED; `instance_restarted` still says the instance came
  back. With this, every long lifecycle verb — update, stop, restart — is bracketed the same way.

- **`stop` brackets its run with events.** `instance_stop_started` is emitted before the shutdown and
  `instance_stop_finished` after it returns, on every outcome — so a consumer can show an instance as
  stopping for as long as the supervisor waits for the game to drain and save, which is seconds to a
  minute for most games and the whole stop timeout for one that ignores its stop command. Finished
  says the run ENDED; `instance_stopped` still says the instance is down, and is still emitted on
  success only. This gives `stop` the same shape `update` has, so a surface learns about either from
  the journal alone, no matter which entrypoint drove it.

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

- **The `[steam]` config credentials are read.** `STEAM_USERNAME` and `STEAM_PASSWORD` are resolved
  from the process environment first and from the KGSM config file second, so a Steam-account game
  installs and updates without a shell environment. The management script is standalone and never
  loaded the engine's config, so the two keys the config file documents reached nothing and only an
  exported variable worked — which ruled out every non-interactive caller, since a systemd unit and
  the watchdog carry no login environment. The error text now names both places the value can go.

- **A validation failure is returned to the caller instead of being reported as success.** Three
  sites took a failure code with `return $?` from inside an `if ! cmd` branch, where `$?` is the
  negated status and therefore always `0`. The validation ran and correctly rejected the input; the
  code that carried the rejection was thrown away one line later. `directories.sh remove` accepted a
  nonexistent instance and an instance whose working directory does not resolve, and
  `__logic_create_instance` reported a created instance when the base configuration had not been
  written. All three take the code with `|| return $?`, which the rest of the tree already uses.

- **`STEAM_PASSWORD` is optional, and a stored refresh token is preferred over it.** SteamCMD keeps
  a refresh token after a login that satisfies Steam Guard, and a username-only login spends that
  token — which is the only way a download runs unattended on an account with Steam Guard enabled.
  Requiring a password forced the password path on every call even when a token was stored, and
  that path replaces the token, so the engine destroyed the credential that made it work headless:
  two logins per install, each one spending the account's password rather than the token it had
  just been given. A host that has logged in once should leave `STEAM_PASSWORD` empty and store no
  Steam password at all.

- **A download that fetched nothing is reported as a failure.** `_download` confirms game files
  reached the destination instead of trusting SteamCMD's report. SteamCMD claims a success it did
  not achieve — a login left unconfirmed at a Steam Guard prompt, or an account-gated app fetched
  anonymously, exits 0, prints `Success! App fully installed`, and writes a manifest claiming
  `StateFlags 4` over an empty depot list. `_download` reported success on the strength of that,
  deploy copied the lone manifest into the instance, and the install failed several steps later
  complaining about a missing version argument — nowhere near the thing that actually went wrong.

- **Minecraft's blueprint opens the port the game actually listens on.** It declared `25565/udp`,
  but the Java server serves the game over TCP; UDP on that number is only the optional GS4 query
  listener. An instance came up with its game port shut and needed a hand-written ufw rule to be
  reachable at all. The protocol is now left off the spec, which opens both — the way ufw reads a
  bare port — so enabling query later needs no firewall change.

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
