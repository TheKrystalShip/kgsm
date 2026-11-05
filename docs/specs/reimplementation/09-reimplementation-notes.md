# 09 — Reimplementation Notes

This document calls out the parts of the bash codebase that are
**workarounds for bash limitations** versus the parts that are
**deliberate design choices**. A reimplementation in another language
(this project's target is Stash) MUST distinguish the two: the first
group should be replaced with idiomatic constructs; the second group
must be reproduced faithfully because users and downstream tooling
depend on them.

---

## 1. Patterns to KEEP

These are not bash workarounds. They are the architecture, and the
reimplementation MUST preserve them.

### 1.1 The self-contained per-instance management script

Every instance has its own `<instance>.manage.sh` which:

- Runs without the parent KGSM tool present.
- Sources its own per-instance config at startup.
- Locates the config relative to its own filesystem path
  (`dirname "$(readlink -f "$0")")`).
- Is what systemd's `ExecStart` points at.

This is intentional. It means an instance survives KGSM uninstallation,
KGSM upgrades never touch already-deployed instances, and power users
can ssh in and run the script directly. **Do not centralise instance
control in the parent tool.** See [03-management-script-and-overrides.md §4.1](03-management-script-and-overrides.md).

### 1.2 File-based per-game overrides

Per-game logic lives in `overrides/<game>/<NN>-<role>.sh`, discovered
at script-assembly time by a directory scan with a 3-tier search order
(user → bundled → default). The directory IS the manifest; no plugin
registration step exists.

Stash does not have a class hierarchy, but this design works in any
language because it is simply file discovery. A reimplementation
**MUST NOT** replace it with class subclassing, plugin registries,
manifest files, or DLL-style dynamic loading. See
[03-management-script-and-overrides.md §3.3](03-management-script-and-overrides.md).

### 1.3 Command / handler split

The two-layer structure inside `commands/` (CLI/IO/event-emit on top,
pure logic underneath) is not a bash convention — it is the testability
discipline. Preserve it. Keep handler functions free of all I/O and
event emission. See [01-system-overview.md §2.1](01-system-overview.md).

### 1.4 INI as the on-disk format

Both the global config and per-instance configs are sectioned/flat INI
files. Users edit them by hand. Tooling parses them with simple regex.
A reimplementation MAY internally use richer types (structs / records
in the host language), but the on-disk file MUST remain INI with the
same key names. See [02-data-model.md §1](02-data-model.md) and §3.

### 1.5 Stable numeric exit codes

The exit codes in [01-system-overview.md §5](01-system-overview.md)
are part of the public API. Downstream scripts and the event system
key off them. **Do not renumber.** New codes MAY be added in unused
ranges; existing codes MUST keep their meanings.

### 1.6 XDG layout

`$XDG_CONFIG_HOME/kgsm/`, `$XDG_DATA_HOME/kgsm/`, with the install
tree separately and read-only. Lookup precedence (user-tree → install-tree)
applies to blueprints and overrides.

### 1.7 Two-name convention for events

CLI / log / config name uses dashes (`server.started`); JSON
`EventType` uses underscores (`instance_started`). Event consumers
already deployed in the wild expect this. See [05-events.md §2](05-events.md).

### 1.8 Auto-selected, not auto-failed watcher strategy

`startup_success_regex` first; ports as fallback. No watcher is also
acceptable. **Do not** make watchers mandatory or make missing-strategy
a fatal install error. See [06-watchers.md §1](06-watchers.md).

---

## 2. Bash workarounds — replace with idiomatic constructs

These exist because bash lacks a feature. The new implementation
language probably has the feature; use it.

### 2.1 Exit codes 200–255 as event triggers

Bash functions cannot return rich values. The codebase fakes this by
returning a "success-event code" in the range 200+ that the command
layer interprets as "succeeded — please dispatch event N".

> Replace with: handlers return a normal success result (or a tagged
> union) and the command layer **explicitly emits the event by name**.
> The `EC_SUCCESS_*` constants can be removed entirely from the new
> codebase. The numeric values themselves are not load-bearing — only
> the event names are.

### 2.2 The `instance_*` variable explosion

Module 01 of the management script reads the per-instance INI and
exports every key as an `instance_<key>` environment variable, then
every other module reads them as global variables. There are 50+ such
variables. This is bash's only viable pattern for "load a record".

> Replace with: a single `Instance` struct (or whichever shape the
> host language uses) loaded once at startup and passed by reference.
> Keep the field names identical to the on-disk keys, so an override
> author switching from a bash override to a host-language override
> writes the same names.

### 2.3 `config_*` variable explosion

Same pattern, for the global config. Same fix: load it into a single
`Config` struct.

### 2.4 `source` instead of imports

Bash uses `source <path>` to load modules. Guard variables
(`KGSM_PARSER_LOADED`) prevent double-loading. Functions are exported
with `export -f` so subprocesses see them.

> Replace with: normal language imports + module singletons. None of
> the guard variables are needed; no `export -f` is needed.

### 2.5 `envsubst` for runtime variable expansion

`instance_executable_arguments` may contain `$instance_*` references
that get expanded with `envsubst` when the management script launches
the server. This is required because the value is stored as plain
text in INI.

> Replace with: a small template renderer (any host-language one) that
> expands `${name}` against the instance struct. Keep the *user-visible
> syntax* identical (`$instance_saves_dir`) so existing blueprints
> work unchanged. Reject `$(...)` and backtick patterns at expansion
> time, exactly as the bash implementation does (
> [03-management-script-and-overrides.md §5.1](03-management-script-and-overrides.md)).

### 2.6 `sed`-based template substitution

Templates (`service.tp`, `socket.tp`, `ufw.tp`, `instance.tp`,
`overrides.tp`) are substituted by passing them through bash variable
expansion (or `envsubst`). This is fragile.

> Replace with: a real template engine. The substitution surface is
> trivially small (only `$identifier`-style references, no
> conditionals or loops in any template), so even a 10-line renderer
> is enough.

### 2.7 Re-bootstrapping in subprocesses

Every script in `commands/` re-runs `core/bootstrap.sh` because each
can also be invoked directly. Guard variables make subsequent
invocations no-ops. This is bash's only pattern for "first invocation
in this process tree, please initialise".

> Replace with: a single `init()` function call at `main()`, invoked
> once per process. There is no need for "is bootstrap loaded?"
> guards once functions are real imports.

### 2.8 The delegator (auto-generated wrapper functions)

`core/delegator.sh` scans `commands/` and generates a bash function
named after each script that invokes that script. This is bash's
hack for "invoke another command without knowing its absolute path".

> Replace with: normal function calls between modules. No code
> generation needed.

### 2.9 PID-file race conditions

Module 03 of the management script has multiple comments about TOCTOU
and atomic-read patterns around `instance_pid_file`. These exist
because bash can't atomically stat-and-read.

> Replace with: a `tryReadPidFile` helper that opens, reads, and
> closes in one go (or uses a process-handle abstraction the host
> language provides). The state machine — "PID file exists and points
> at a live process" — is unchanged.

### 2.10 `pgrep`/`kill` instead of process groups

`_kill_all_processes` (module 03) uses `pgrep -P <pid>` to find direct
children, then sends SIGTERM. This handles only one level of children,
which is good enough for the games KGSM supports today, but a host
language with proper process-group APIs (`setpgid` + signal-process-group)
SHOULD use them for cleanliness.

### 2.11 `socat` for socket emission

The event system shells out to `socat - UNIX-CONNECT:<path>` to write
JSON to a Unix socket. This is bash's only sensible option.

> Replace with: a native Unix-socket client. Removes the `socat`
> dependency entirely.

### 2.12 `wget` for HTTP webhook delivery

Same story. The host language probably has an HTTP client; use it.
This eliminates the `wget` dependency for the event subsystem (it may
still be needed by some game-specific overrides for downloading
non-Steam game files).

### 2.13 `bash -c '...'` inside `timeout`

The watcher strategies wrap their core loop in
`timeout <T>s bash -c '...'`. This is the only way bash gets a
guaranteed-to-fire timeout.

> Replace with: native cancellable async / timeout block / a `select`-style
> deadline. Same observable behaviour, less subprocess overhead.

### 2.14 Exit-code map (`EXIT_CODES` array)

Bash fakes "associate code → message" with an associative array. A
reimplementation has enums / dictionaries natively — no wrapper
needed. The error-message lookup table itself is still useful; just
store it where it makes sense.

### 2.15 `__sanitize_input_command` (module 04)

A blanket reject-list of shell metacharacters in user input destined
for the FIFO. Justified in bash because the FIFO contents may end up
inside a `$()` expansion somewhere. In a host language that does not
shell-evaluate writes to a pipe, the sanitiser MAY be relaxed (still
keeping a length cap and rejecting NUL bytes). Document the relaxation.

### 2.16 `"DEPRECATED:"` comment block in merged config

The config merge writes deprecated keys as commented-out lines at the
end of the file under a "DEPRECATED KEYS" header. This is a UX choice
borne out of the format's limitations.

> Keep this UX. It works in any language. Do not auto-delete deprecated
> keys: users want to see what was removed, often to migrate values
> manually.

---

## 3. Things to verify before launch

Before declaring the reimplementation feature-complete, check each:

- [ ] All 47 standard error codes (0–46) plus 245–249 retain their
  numeric values and meanings.
- [ ] All event names (CLI dash-form + JSON underscore-form) match
  exactly. Run an event consumer like `kgsm-bot` against the new
  implementation and verify it works without code changes.
- [ ] Existing per-instance config files load unchanged.
- [ ] Existing global config files load unchanged (modulo schema
  migrations).
- [ ] Existing blueprints (`.bp` and `.docker-compose.yml`) work
  unchanged.
- [ ] Existing override directories (`overrides/<game>/`) are
  discovered and used.
- [ ] Existing assembled management scripts continue to work — KGSM
  reimplementation does NOT regenerate them automatically.
- [ ] systemd units generated by the bash version continue to work
  with the new tool's `lifecycle stop` (the units' `ExecStop` points
  at the management script which is unchanged).
- [ ] `--json` output of `instances list`, `instances info`, `status`,
  `blueprints list`, `config list`, `system info`, `events status`
  matches the bash version's shape.
- [ ] CLI exit codes match for all documented success and failure
  paths.

---

## 4. Things the bash implementation does NOT do (and probably never should)

Listed here so a reimplementation does not accidentally add them
thinking they were oversights:

- **No central daemon.** KGSM is a one-shot CLI tool. Each invocation
  bootstraps, does its thing, exits. A daemon would change the
  security and operational model significantly. Resist the temptation.
- **No remote control / API server.** Events go OUT (socket, webhook);
  nothing comes IN. If remote control is needed, it should be a
  separate companion project.
- **No automatic instance migration on KGSM upgrade.** Upgrades touch
  the install tree only. Existing instance directories are untouched.
  This is the contract that lets users hand-edit assembled management
  scripts.
- **No automatic update scheduling.** `instance_auto_update_before_start`
  runs the update only as part of `start`. There is no cron-equivalent.
  Users who want one wire systemd timers themselves.
- **No Windows or macOS support.** Linux-only. The design accommodates
  cross-platform in principle (overrides and integrations are
  pluggable) but no first-class support is shipped.
- **No multi-user instance ownership.** An instance is owned by the
  user who created it. No ACLs, no group ownership, no role-based
  control. Users who need this run multiple users' KGSMs.

---

## 5. Open questions left for the implementer

These are points where the bash version makes a choice but a
reimplementation might reasonably make a different one:

1. **Atomic config file writes.** The bash merger writes to a temp
   file and then `mv`s. The new implementation MAY use a host-native
   atomic-write helper.
2. **Concurrency.** The bash implementation makes no concurrency
   guarantees; running two `kgsm install` calls simultaneously may
   corrupt `KGSM_INSTANCES_DIR`. The new implementation MAY add file
   locking. Document whatever choice is made.
3. **JSON output buffering.** The bash version emits JSON with
   trailing newlines; the spec does not require either with or
   without. Pick one and document.
4. **Webhook signing version.** Currently HMAC-SHA256 with the secret
   as the raw key. If a more standard scheme is needed (e.g. JWS), it
   should be opt-in via a new config key, never the default.
5. **`--json` for currently text-only commands.** Adding `--json` to
   `network ports`, `system uptime`, etc., is a pure addition and
   does not break anything; treat as a low-priority polish task.
