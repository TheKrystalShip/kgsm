# 10 — Greenfield Design (Opinionated)

> **Status:** Design proposal. Not a continuation of the
> compatibility-preserving spec series (01–09). This document answers
> the question: *"If we threw away the existing code and the existing
> contracts, what would we build?"*
>
> Where 01–09 are descriptive (here is what KGSM does, faithfully),
> this document is **prescriptive** (here is what a v2 should do, and
> why). It will disagree with 01–09 in many places. That is the point.

The goal remains unchanged: **a stateless command-line tool that
manages game servers on Linux**. Everything else is up for grabs.

---

## 1. Guiding principles

These are non-negotiable. Every later decision flows from them.

1. **Stateless CLI, optional daemon.** Every invocation reads state
   from disk, does its work, exits. A long-running supervisor exists
   *only* if the user opts in for one.
2. **Single static binary.** No runtime dependency tree. The user
   downloads one file and it works. (This rules out Bash, Python,
   Node, and the JVM.)
3. **Declarative-first.** A blueprint *describes a server*. It does
   not contain executable code. Code is reserved for two places:
   well-defined strategy implementations (built into the tool) and
   user-provided hook executables (escape hatch).
4. **Composition over inheritance over replacement.** A game's
   behaviour is built by selecting + configuring strategies, not by
   overriding numbered script files.
5. **The on-disk format is the contract.** Anything KGSM writes to
   disk — registry, configs, blueprints, instance dirs — has a
   versioned schema. Anything KGSM does in-memory is private.
6. **Failure is structured.** No string parsing of `pgrep` output,
   no fragile regex over `steamcmd` text. Every external tool is
   wrapped in a typed adapter that returns a tagged result.
7. **Observable by default.** Structured logs (JSON), structured
   events, structured exit codes. Everything that can be machine-read
   is machine-readable without a flag.
8. **Tested without games.** Every strategy has a fake. CI must run
   without contacting Steam, downloading game binaries, or starting
   real servers.

---

## 2. Language and runtime

### Decision: **Go**

| Candidate         | Verdict      | Why / Why not                                                                                                                                                                                                          |
| ----------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Go**            | ✅ Chosen     | Single static binary; mature stdlib for filesystem, processes, HTTP, sockets, SQL; trivial cross-compile; great test ergonomics; easy concurrency for the watcher and event pipeline.                                  |
| Rust              | Considered   | Ideologically a great fit, but the iteration speed is wrong for a tool that mostly orchestrates other processes. Compile times hurt contributor velocity. Use Rust for the supervisor daemon if perf becomes an issue. |
| Zig               | Rejected     | Too immature; standard library too small for the I/O surface here.                                                                                                                                                     |
| Bash (status quo) | Rejected     | The whole point of this exercise.                                                                                                                                                                                      |
| Stash             | Out of scope | This document is the language-agnostic redesign; a Stash port follows from the strategies in 09 + this document.                                                                                                       |

### Risks of choosing Go

- Generics are still relatively new; some plugin/strategy code may
  feel verbose.
- The `os/exec` API has subtle gotchas around process groups and
  stdin handling — exactly the area we lean on most. Mitigation:
  centralise *all* subprocess handling in `internal/proc` and test
  it exhaustively.

---

## 3. Architecture

### 3.1 Layered, no cyclic dependencies

```
cmd/kgsm/                — Cobra CLI entrypoint, flag parsing
internal/app/            — use-case orchestration (install, start, ...)
internal/blueprint/      — blueprint loading, validation, resolution
internal/instance/       — Instance domain type
internal/registry/       — SQLite-backed instance registry
internal/strategy/       — strategy interfaces + built-ins
  source/                — steamcmd, http_tarball, git, custom_hook
  runtime/               — native, docker_compose, podman_compose
  readiness/             — log_pattern, port_check, tcp_probe, command, none
  version/               — steamcmd_buildid, github_release, file_mtime, none
  console/               — stdin_pipe, rcon, tmux, screen, none
internal/supervisor/     — process supervision adapters
  systemd/               — generate units, control via DBus or systemctl
  foreground/            — direct exec, attach to terminal
  managed/               — KGSM's own supervisor (only if `kgsmd` is running)
internal/events/         — event bus, sink registry
  sink/                  — unix_socket, webhook, file, journald
internal/integration/    — ufw, upnp, steamcmd, docker
internal/proc/           — *the* subprocess wrapper (exec + stdin + stdout + stderr + signals)
internal/io/             — atomic file writes, lockfiles
internal/config/         — TOML config parsing
internal/logging/        — slog setup
```

### 3.2 Dependency rule

`cmd → app → strategy + registry + supervisor → integration → proc/io`.

Nothing in `internal/strategy` imports `internal/registry`. Strategies
are pure: given a struct of inputs, do work, return a struct of
outputs. The registry knows about strategies (by name); strategies
do not know about the registry.

### 3.3 Testability

Every strategy interface has:

- A real implementation (e.g. `SteamCMDSource`).
- A fake implementation in `*_fake.go` that records calls and returns
  configurable outcomes.
- Table-driven tests against the real one, gated on a build tag
  (`//go:build integration`) so default `go test ./...` runs in
  seconds without external tools.

---

## 4. Blueprint format

### 4.1 TOML, declarative, no embedded code

```toml
schema = 1
name = "factorio"
display_name = "Factorio"
runtime = "native"

[source]
kind = "steamcmd"
app_id = 427520
platform = "linux"
extra_args = ["+beta", "experimental"]

[server]
executable = "bin/x64/factorio"
args = [
  "--start-server-load-latest",
  "--server-settings=server-settings.json",
  "--port", "{{ .Ports.game }}",
]
working_dir = "."
env = { LANG = "en_US.UTF-8" }

[[network.ports]]
name = "game"
port = 34197
protocol = "udp"

[lifecycle]
stop = { strategy = "signal", signal = "SIGTERM", timeout = "30s", fallback = "SIGKILL" }
save = { strategy = "command", command = "/save\n" }   # written to console

[readiness]
kind = "log_pattern"
pattern = "(?i)Hosting game at"
timeout = "60s"

[console]
kind = "stdin"

[version]
kind = "steamcmd_buildid"

[backup]
include = ["saves/", "mods/", "server-settings.json"]
exclude = ["*.tmp"]
```

### 4.2 Why TOML and not YAML / JSON / INI

| Format           | Verdict                                                                                                                                                                     |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **TOML**         | ✅ Hand-editable, comments allowed, unambiguous, has tables/arrays/typed values without indentation games.                                                                   |
| YAML             | Rejected — significant whitespace causes too many user errors; the Norway Problem; multiple parsers disagree.                                                               |
| JSON             | Rejected — no comments, no trailing commas, hostile to hand-editing.                                                                                                        |
| INI (status quo) | Rejected — no nesting, no arrays, no types. The current KGSM blueprint syntax (`ports='1111:2222/tcp\|3333/udp'`) exists *because* INI cannot express a list of structures. |

### 4.3 Templates

Server `args`, `env`, and `executable` may contain Go-template
references to a fixed context: `{{ .Ports.<name> }}`, `{{ .Paths.saves }}`,
`{{ .Paths.install }}`, `{{ .Instance.Name }}`, `{{ .Server.Owner }}`.

No arbitrary expressions, no shell-out, no `$(...)`. Anything more
complex requires a hook (§4.4).

### 4.4 Hooks: the escape hatch

Some games need real logic (Minecraft EULA acceptance, Terraria's
`tModLoader` indirection, the dozen quirks `factorio.overrides.sh`
covers today). Hooks are how we handle them.

```toml
[hooks]
post_install = "scripts/accept-eula.sh"
pre_start    = "scripts/sync-mods.sh"
```

Contract:

- Hook is invoked as a normal subprocess (any executable).
- KGSM passes a structured environment (`KGSM_INSTANCE_DIR`,
  `KGSM_PORTS_GAME`, ...) and a JSON object on stdin describing the
  full instance state.
- Hook prints a JSON object on stdout describing any state changes
  it wants reflected (new env vars, new files registered for backup,
  updated version string, ...).
- Non-zero exit fails the parent operation; stderr is captured into
  the structured log.

Hooks are **not** sourced into the parent process. They run sandboxed.
This eliminates the entire class of bugs caused by bash override
files mutating parent-process state in surprising ways.

### 4.5 Resolution

A user blueprint at `$XDG_DATA_HOME/kgsm/blueprints/factorio.toml`
**fully replaces** the bundled one — no field-level merging.
Variants live as separate blueprints (`factorio.toml`,
`factorio-modded.toml`) with their own `name` field.

---

## 5. Instance registry

### 5.1 Decision: SQLite, single file

`$XDG_STATE_HOME/kgsm/registry.db`.

Tables:

```sql
instances(
  id              TEXT PRIMARY KEY,        -- user-facing slug
  blueprint_name  TEXT NOT NULL,
  blueprint_hash  TEXT NOT NULL,           -- snapshot of the blueprint at install time
  install_dir     TEXT NOT NULL,
  install_time    INTEGER NOT NULL,
  owner_uid       INTEGER NOT NULL,
  runtime         TEXT NOT NULL,
  supervisor      TEXT NOT NULL,           -- 'systemd' | 'foreground' | 'managed'
  state_json      TEXT NOT NULL,           -- mutable struct: ports, version, last_started, etc.
  schema          INTEGER NOT NULL
);

events_outbox(
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  instance_id     TEXT,
  event_name      TEXT NOT NULL,
  payload_json    TEXT NOT NULL,
  ts              INTEGER NOT NULL,
  delivered       INTEGER NOT NULL DEFAULT 0
);

config_history(
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  ts              INTEGER NOT NULL,
  user            TEXT NOT NULL,
  diff_text       TEXT NOT NULL
);
```

### 5.2 Why SQLite, not the filesystem-as-database

The current approach (each instance is a directory; "list" = `ls`)
has real costs:

- No atomic multi-instance updates.
- "List all systemd-supervised instances installed in the last
  30 days" requires walking every directory and parsing every config.
- Concurrent CLI invocations can race (e.g. ID generation).

SQLite gives us atomicity, queries, and indexed lookups for the cost
of one extra file. It is still a **single static file** — no server,
no network, embedded in the binary.

The instance directories on disk remain authoritative for *file
content* (saves, backups, logs). The registry is authoritative for
*metadata*. A `kgsm registry rebuild` command reconciles the registry
from the on-disk dirs in case of corruption.

### 5.3 Per-instance config: keep it on disk too

In addition to the DB row, each instance has
`<install_dir>/.kgsm/instance.toml` containing the same data. Reasons:

- Survives total registry loss (rebuild reads them).
- Lets a user `scp` an instance directory to another machine and
  re-register it.
- Hand-editable for the rare case the user knows what they're doing.

The DB is the fast path; the file is the recovery path. They must
agree, and `kgsm doctor` flags drift.

---

## 6. Process supervision

### 6.1 Three modes, user picks per instance

| Mode                | Use case                                      | What KGSM emits                                                                    |
| ------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------- |
| `systemd` (default) | Production servers; reboot persistence        | `<inst>.service` + `<inst>.socket` units, system-level by default, `--user` opt-in |
| `foreground`        | Development; one-off; running in tmux/screen  | Nothing on disk; KGSM exec's the server in the calling terminal                    |
| `managed`           | Users who refuse systemd but want supervision | Hands the instance to `kgsmd` (a separate optional daemon)                         |

### 6.2 Why keep systemd

It's the right answer on Linux. Process trees, restart policy, log
forwarding, socket activation, cgroup isolation — all solved.
Replacing it would be folly. KGSM's job is to **generate good units**,
not to reinvent supervision.

### 6.3 Why offer `managed` at all

Some users genuinely cannot use systemd (containerised hosts without
an init, BSD users in the future, NixOS users with strong opinions).
A small Go daemon (`kgsmd`) running under whatever they have
satisfies them without polluting the main tool.

### 6.4 The console problem

How do we send `/save\n` to a running server?

| Mode         | Mechanism                                                    |
| ------------ | ------------------------------------------------------------ |
| `systemd`    | `ListenFIFO` socket + `StandardInput=socket` (same as today) |
| `foreground` | KGSM is the parent process; write directly to child stdin    |
| `managed`    | `kgsmd` owns the FIFO and forwards                           |

This is the one place where the reimplementation closely mirrors the
current design — because the current design here is correct.

---

## 7. Configuration

### 7.1 Single file, TOML

`$XDG_CONFIG_HOME/kgsm/config.toml`. Sectioned, typed, hand-editable.

```toml
schema = 1

[defaults]
install_dir = "~/games"
supervisor  = "systemd"
runtime     = "native"

[steam]
username = ""              # empty = anonymous
# password is read from secret_file or KGSM_STEAM_PASSWORD env var
secret_file = "~/.config/kgsm/steam.secret"

[network.firewall]
backend = "ufw"            # 'ufw' | 'firewalld' | 'none'
auto_open = true

[network.upnp]
enabled = false

[events]
enabled = true
sinks = ["unix_socket", "webhook"]

[events.sink.unix_socket]
path = "/run/user/1000/kgsm.sock"

[events.sink.webhook]
url = "https://hooks.example.com/kgsm"
secret_file = "~/.config/kgsm/webhook.secret"
hmac = "sha256"
timeout = "5s"
retries = 3
```

### 7.2 Migrations

Schema-versioned. `kgsm config migrate` applies migrations idempotently.
Backups taken automatically (10 generations, same as today — the
current behaviour here is good).

### 7.3 Secrets

Never inline. Always `secret_file = "..."` with mode-checked
permissions (`0600` enforced; tool refuses to start if looser). Or
environment-variable override (`KGSM_STEAM_PASSWORD`, etc.).

### 7.4 What's gone

- The 50+ `config_*` flat-namespace keys. Replaced by nested tables.
- The deprecated-keys-as-comments mechanism (we have schema migrations
  now).
- The `[accessibility]` colour config section — let the terminal /
  `NO_COLOR` decide.

---

## 8. CLI surface

### 8.1 Verb-noun, with a small set of nouns

```
kgsm <noun> <verb> [args]    — full form
kgsm <verb> <id>             — shortcuts for common lifecycle verbs
```

Nouns: `instance`, `blueprint`, `library`, `config`, `event`, `hook`,
`system`.

```
kgsm instance install <blueprint> [--name id] [--library name]
kgsm instance list [--blueprint X] [--status] [--json]
kgsm instance show <id> [--json]
kgsm instance start <id> [--detached]
kgsm instance stop <id> [--no-save]
kgsm instance restart <id>
kgsm instance status <id> [--json] [--watch]
kgsm instance logs <id> [-f] [-n N]
kgsm instance backup <id> [--name X]
kgsm instance restore <id> <backup>
kgsm instance update <id> [--version V]
kgsm instance console <id>           — interactive console session
kgsm instance send <id> <command>    — one-shot console input
kgsm instance uninstall <id> [--keep-saves]
kgsm instance move <id> --library <name>

kgsm library add <path> [--name X]
kgsm library list [--json]
kgsm library rename <old> <new>
kgsm library remove <name> [--drain target]

kgsm blueprint list [--json]
kgsm blueprint show <name> [--json]
kgsm blueprint validate <path>
kgsm blueprint init <name>           — scaffold a new blueprint

kgsm config show [--json]
kgsm config set <key> <value>
kgsm config edit                     — opens $EDITOR on the file with validation
kgsm config validate
kgsm config migrate

kgsm event tail [--filter NAME]      — watch the event stream live
kgsm event emit <name> [k=v ...]
kgsm event sinks                     — list configured sinks and their health

kgsm system info [--json]
kgsm system doctor                   — check deps, perms, registry consistency
kgsm system completion <shell>       — emit shell completions
```

Shortcuts: `kgsm start <id>` ≡ `kgsm instance start <id>` (same for
stop, restart, status, logs).

### 8.2 What's gone

- The `directories` and `files` low-level commands. They're an
  artefact of bash's poor abstraction — in the new tool you should
  never need to manually re-emit a single template file.
- `interactive` mode. A TUI is a separate project (`kgsm-tui`)
  that consumes the same JSON API. Bundling it bloats the binary
  and conflates concerns.
- `network` and `watcher` as top-level nouns. `network` is fluff
  (use `ss`, `ip`); the watcher is an implementation detail of
  `instance start`, not a user-facing object.

### 8.3 JSON-everywhere

Every command supports `--json` and emits a stable schema. Plain-text
output is for humans only and may change between minor versions.

### 8.4 Exit codes

Three buckets:

- `0` — success.
- `1` — user error (bad args, missing instance, validation failure).
- `2` — environmental error (missing dependency, permission denied,
  network failure, integration failure).

Detailed reason is in stderr text + the `error.code` field in
`--json` output. **No more 47 numeric error codes.** Scripts that
need fine-grained dispatch read JSON.

### 8.5 The 200–255 success-event hack

Gone. Events are emitted explicitly by handlers via the event bus.

---

## 9. Events

### 9.1 Single bus, multiple sinks

In-process: a typed event bus. Out-of-process: pluggable sinks read
from the `events_outbox` table and deliver in the background.

Sinks shipped:

- **unix_socket** — line-delimited JSON to a configurable path.
- **webhook** — POST JSON, HMAC-SHA256 signature in header, retry
  with exponential backoff, dead-letter on the outbox after N tries.
- **file** — append to a JSONL file (great for testing, archival).
- **journald** — structured log to systemd-journald, no separate
  consumer needed.

### 9.2 Event names

Single naming convention: `snake_case_dotted`.

```
instance.installed
instance.started
instance.stopped
instance.crashed
instance.update.available
instance.update.completed
instance.backup.created
instance.backup.restored
config.changed
```

The current dual dash/underscore convention is dropped.

### 9.3 Schema

```json
{
  "schema": 1,
  "id": "01HXYZ...",          // ULID per event
  "name": "instance.started",
  "ts": "2026-04-29T10:15:30Z",
  "host": "myhost",
  "kgsm_version": "2.0.0",
  "instance": { "id": "factorio-01", "blueprint": "factorio" },
  "data": { ... event-specific ... }
}
```

Outbox + delivery confirmation gives at-least-once semantics. A
consumer that needs exactly-once dedupes on `id`.

---

## 10. Readiness watchers

Strategies, selected per blueprint, not auto-detected:

| Strategy      | When to use                                                  |
| ------------- | ------------------------------------------------------------ |
| `none`        | Server backgrounds itself / exits start. Default for legacy. |
| `log_pattern` | Server logs a known string when ready. Most common.          |
| `port_check`  | Server opens a known port when ready.                        |
| `tcp_probe`   | KGSM connects TCP/UDP and gets a response.                   |
| `command`     | KGSM runs a shell command; ready when it exits 0.            |
| `http`        | Server has an HTTP endpoint; ready on 2xx.                   |

The **auto-selection** the current bash version does is removed.
Auto-selection looks helpful but obscures what's happening when it
goes wrong; making the blueprint declare its readiness strategy
explicitly is one extra line of TOML per game.

---

## 11. Storage layout

```
$XDG_CONFIG_HOME/kgsm/
  config.toml
  config.toml.bak.[0-9]
  steam.secret               (mode 0600)
  webhook.secret             (mode 0600)

$XDG_STATE_HOME/kgsm/
  registry.db
  registry.db.bak.[0-9]

$XDG_DATA_HOME/kgsm/
  blueprints/                (user blueprints)
  hooks/                     (user-supplied hook scripts)

$XDG_CACHE_HOME/kgsm/
  downloads/                 (steamcmd staging, http tarballs)
  steamcmd/                  (steamcmd's own state)

<install_dir>/<instance_id>/
  .kgsm/
    instance.toml            (mirror of registry row)
    state/                   (PID file, FIFO, lockfiles)
  game/                      (the actual game install)
  saves/   logs/   backups/  (bind-mountable, configurable per-blueprint)
```

Bundled blueprints ship inside the binary (Go `embed.FS`). No need
for a separate install tree.

---

## 12. Integrations

### 12.1 systemd

Use `go-systemd` (DBus) when available; fall back to invoking
`systemctl` as a subprocess when the DBus connection fails (e.g. in
a container). Generate units from typed structs, not text templates.

### 12.2 Firewall

Pluggable: `ufw`, `firewalld`, `iptables`, `none`. The blueprint
doesn't care; the integration adapter translates port specs to the
backend's syntax.

### 12.3 UPnP

Use a real UPnP library (e.g. `huin/goupnp`) instead of shelling
out to `upnpc`. Removes a runtime dependency.

### 12.4 SteamCMD

Still a subprocess (it has no library form), but wrapped by an
adapter that:

- Parses output into typed events (`AppUpdateProgress`, `LoginFailed`,
  ...).
- Has a real KeyValues parser for `app_info_print`, replacing the
  current `grep -Po` pipeline.
- Has a fake for tests.

### 12.5 Docker / Podman

A `runtime = "container"` blueprint references a compose file inline
or by path. KGSM uses the Docker SDK directly (not `docker compose`
shell-out) for start/stop/logs; falls back to compose for build /
pull. Container vs native is a runtime choice in the blueprint, not
a separate blueprint format.

---

## 13. What's gone (summary)

Things from the current KGSM that this design **deliberately drops**:

| Dropped                                           | Replaced by                                  |
| ------------------------------------------------- | -------------------------------------------- |
| Bash override files in numbered slots             | TOML strategies + sandboxed hook executables |
| Self-contained per-instance management script     | Stateless CLI + supervisor adapters          |
| Templates substituted by `envsubst` / `sed`       | Typed unit/config generation in Go           |
| INI for both global and per-instance config       | TOML, schema-versioned                       |
| Dual event-name convention (dash + underscore)    | Single `snake_case`                          |
| 200–255 success-event exit codes                  | Direct event emission                        |
| ~50 numeric error codes                           | 0/1/2 + structured error JSON                |
| `socat` / `wget` / `envsubst` / `pgrep` shellouts | Native Go libraries                          |
| Filesystem-as-database for instance discovery     | SQLite registry (with FS as backup)          |
| `directories` / `files` low-level CLI commands    | Internal — never user-facing                 |
| Built-in interactive TUI                          | Separate `kgsm-tui` consuming the JSON API   |
| Auto-selected watcher strategy                    | Declared explicitly in blueprints            |
| Variable-explosion (`instance_*`, `config_*`)     | Nested structs                               |
| `source` + `export -f` module loading             | Normal Go imports                            |

---

## 14. What's kept (summary)

The current KGSM gets a lot of things right. This design preserves
them, just in different clothing:

- **The blueprint/instance/per-game-logic three-tier model** — sound.
  Reorganised but unchanged in spirit.
- **systemd as the default supervisor** — correct.
- **Event-driven observability** — correct, just consolidated.
- **XDG layout** — correct.
- **Hand-editable on-disk format** — correct, switched from INI to TOML.
- **First-run bootstrap that creates user dirs** — correct.
- **Schema migrations + automatic backups** — correct.
- **Variants of a game share logic via `name=`** — preserved as
  blueprints with the same `name` field selecting the same hooks /
  strategies.
- **`status --json` shape** — kept conceptually (a structured
  introspection command), even though specific field names change.
- **Container-vs-native parity** — strengthened: same blueprint type,
  one field selects the runtime.

---

## 15. Build, distribution, install

- **Single binary, releases via GitHub Releases.** Static `linux/amd64`,
  `linux/arm64`, `linux/armv7`.
- **System install** via package: `apt`, `rpm`, `pacman`, `nix`, plus
  a `tar.gz` for everyone else. The package's only job: drop the
  binary at `/usr/local/bin/kgsm` and install a shell completion
  file.
- **First-run UX**: `kgsm system doctor` runs automatically on first
  invocation. Reports missing deps (`steamcmd`, `ufw`, `docker`),
  permissions issues, and what's needed for full functionality.
  Doesn't fail — the tool degrades gracefully.

---

## 16. Risks and tradeoffs of this design

Honest accounting. Every design choice has a cost.

1. **Losing the self-contained management script means losing offline
   power-user editability.** Today, an advanced user can `vim` an
   instance's `manage.sh` on a server with no KGSM installed and
   change behaviour. New design: that user runs `kgsm` itself, which
   must be present. Mitigation: the binary is small and static; it's
   reasonable to require it.

2. **SQLite adds a hidden state file users may not expect.** Users
   used to "everything is in `~/.config/kgsm/instances/`" will be
   surprised. Mitigation: heavy documentation; `kgsm registry rebuild`
   recovers from FS dirs alone.

3. **Hooks are less powerful than bash overrides.** A hook is a
   subprocess; an override is sourced into the parent. Some games
   *might* genuinely need to mutate parent-process state. We bet
   that's never actually necessary (the current overrides don't
   really need it either — they exploit it because bash makes it
   trivial). If we're wrong, we add a richer hook protocol later.

4. **Go is not trivially scriptable.** Adding a new game today means
   writing bash. Adding a new game in the new design means writing
   TOML (easy) plus, occasionally, a hook script (in any language).
   For 90% of games this is *easier*; for the 10% that need exotic
   logic it's harder than just dropping a `.sh` in `overrides/`.
   Mitigation: hooks are language-agnostic, so contributors can use
   whatever they're comfortable with.

5. **No backwards compatibility means a hard cutover.** Existing KGSM
   users cannot upgrade in place. Mitigation: ship a one-shot
   `kgsm-import` tool that reads an old install tree and creates new
   blueprints + registry entries. Best-effort; some edge cases will
   require manual fixup.

6. **TOML is less universal than YAML in DevOps culture.** Some users
   will grumble. We choose correctness over familiarity.

7. **A single static binary means a larger download than a shell
   script.** ~15 MB vs ~500 KB. Acceptable in 2026.

---

## 17. Implementation order

If someone were to actually build this, the order matters:

1. **Skeleton + CLI scaffolding + config loader.** No game support yet;
   `kgsm config show` works, `kgsm system doctor` works.
2. **Registry + blueprint loader + `instance install` for one trivial
   blueprint** (e.g. a static binary game with no Steam, no readiness
   watcher).
3. **Native runtime + foreground supervisor.** `kgsm start/stop/status`
   work for the trivial blueprint.
4. **Strategies: `steamcmd` source, `log_pattern` readiness,
   `signal` stop.** Now Factorio / Minecraft / 80% of the catalog
   work.
5. **systemd supervisor adapter.** Now they can be production servers.
6. **Event bus + unix_socket + webhook sinks.**
7. **Container runtime + Docker SDK adapter.**
8. **Firewall + UPnP integrations.**
9. **Hook protocol + reference hook scripts for the games that need
   them.**
10. **`kgsm-import` for migration from old KGSM.**
11. **TUI as a separate companion project.**

Each phase ends with a usable tool — never a long branch where
nothing works.

---

## 18. Out of scope (for v2 of the rebuild itself)

These are deliberate omissions. They might be future work; they are
not part of what would replace today's KGSM.

- **Cluster / multi-host orchestration.** Use Nomad / Kubernetes /
  Pelican if you need this. KGSM stays single-host.
- **A web UI bundled with the tool.** Separate project; consumes the
  same JSON.
- **Authentication / multi-tenant access control.** Filesystem
  permissions are sufficient for the target audience.
- **A scripting language / DSL for blueprints.** Hooks are the
  scripting language. Adding more risks reinventing bash overrides.
- **Cross-platform support beyond Linux.** macOS / Windows are
  fundamentally different (no systemd, different process model). A
  port is feasible but is a separate project, not a goal of v2.

---

## 19. Decision log

Capturing the non-obvious decisions for future reference:

| #   | Decision                                              | Rejected alternatives                                         | Why                                                                          |
| --- | ----------------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| 1   | Go as the implementation language                     | Rust, Zig, Stash                                              | Static binary + iteration speed + ecosystem maturity for our problem domain  |
| 2   | TOML for all on-disk format                           | YAML, JSON, INI                                               | Comments + types + nesting + low parsing-ambiguity surface                   |
| 3   | SQLite for instance registry                          | Filesystem-only, BoltDB, JSON file                            | Atomic, queryable, single-file, mature                                       |
| 4   | Strategies + hooks instead of bash overrides          | Lua plugins, WASM, native shared libs                         | TOML covers 80%; subprocess hooks cover 100%; no embedded runtimes           |
| 5   | Drop the per-instance self-contained script           | Keep it for offline power users                               | Maintenance cost too high; the JSON-everywhere CLI replaces the use case     |
| 6   | Three exit codes (0/1/2) instead of 47                | Keep numeric taxonomy, expand it, GRPC-style codes            | Detailed reason belongs in JSON; shell `if` only needs success/usage/runtime |
| 7   | snake_case event names (single convention)            | Keep dash CLI / underscore JSON split                         | Two names for one thing was always a mistake                                 |
| 8   | Drop interactive TUI from main binary                 | Bundle a Bubble Tea TUI                                       | Concern separation; binary size; testing surface                             |
| 9   | Auto-readiness-detection removed; declared explicitly | Keep the current "regex first, ports fallback" auto-selection | Implicit behaviour is hostile when debugging                                 |
| 10  | systemd remains the default supervisor                | Build our own daemon                                          | Linux already solved this; we should not reinvent it                         |
| 11  | No cluster/multi-host support                         | Add a control-plane mode                                      | Stay focused; cluster orchestration is its own product                       |
| 12  | Hooks are subprocesses, not sourced                   | In-process plugins (Go plugins, Lua)                          | Sandboxing, language freedom, no parent-state mutation surprises             |

---

## 20. TL;DR

> A single static Go binary. TOML blueprints describe servers
> declaratively; a small set of strategy implementations handles
> downloads, runtime, readiness, and console; hooks (any executable)
> cover edge cases. SQLite holds the instance registry; systemd
> supervises by default. Events flow over a structured outbox to
> sockets / webhooks / journald. The CLI is verb-noun, JSON-everywhere,
> three exit codes. No bash, no overrides, no per-instance script,
> no two-name event convention, no 47 error codes, no auto-detect
> magic. Same job as today's KGSM — done with about 80% less
> ceremony.
