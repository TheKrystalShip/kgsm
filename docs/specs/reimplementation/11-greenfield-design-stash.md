# 11 — Greenfield Design (Stash)

> **Status:** Design proposal. Companion to [10-greenfield-design.md](10-greenfield-design.md).
>
> **Question this document answers:** *"If we throw away the existing
> code AND we throw away the Go choice, can Stash build a tool that's
> at least as good — and possibly better — than the Go design?"*
>
> **Verdict (TL;DR):** Yes, surprisingly comfortably. Stash's standard
> library was designed for exactly this problem class — system
> administration, process orchestration, service management — and it
> shows. The redesign in §3 onwards reuses ~70% of Stash's stdlib
> directly, leaving KGSM as a thin domain layer on top. There are
> real tradeoffs (§13) but they're smaller than I expected before
> reading the spec.

This document is structured as a delta against
[10-greenfield-design.md](10-greenfield-design.md). Where the Go design
holds up, this document references it. Where Stash changes the answer,
this document explains why.

---

## 1. Why Stash makes sense for this problem

Reading the [Stash Language Specification](../../../../stash-lang/docs/Stash%20—%20Language%20Specification.md)
and the [Standard Library Reference](../../../../stash-lang/docs/Stash%20—%20Standard%20Library%20Reference.md),
KGSM's requirements line up almost one-to-one with namespaces Stash
ships out of the box:

| KGSM needs                                                                                      | Stash provides                                                                                                                              | Status                                                                                               |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Spawn / wait / kill / signal a server process; check liveness; daemonise; capture stdout/stderr | `process` namespace — `spawn`, `wait`, `waitTimeout`, `kill`, `signal`, `isAlive`, `daemonize`, `find`, `exists`, `onExit`, `read`, `write` | **Direct fit.** Replaces the entire bash module 03 (lifecycle) and module 04 (input).                |
| Generate + manage systemd units; start/stop/enable/status services; cross-platform fallback     | `scheduler` namespace — `install`, `uninstall`, `start`, `stop`, `restart`, `enable`, `disable`, `status`, `list`, `logs`, `available`      | **Direct fit.** Replaces `service.tp`, `socket.tp`, `files.systemd.sh`, and the systemctl shellouts. |
| Hand-editable on-disk config (TOML)                                                             | `toml` and `config` (format-agnostic) namespaces — `parse`, `stringify`, `read`, `write`                                                    | **Direct fit.** No third-party parser needed.                                                        |
| Templates for unit files, README rendering, etc.                                                | `tpl` namespace — Jinja2-style templating with 19 built-in filters, conditionals, loops, includes                                           | **Direct fit.** Replaces `envsubst` and `sed` template substitution entirely.                        |
| HMAC-SHA256-signed webhook delivery with retry                                                  | `crypto.hmac` + `http.request` + retry blocks (`retry { ... }` language feature)                                                            | **Direct fit.** Removes `wget` and bash retry-loop boilerplate.                                      |
| Unix-socket event sink                                                                          | `net` namespace (TCP/UDP/Unix sockets)                                                                                                      | **Direct fit.** Removes `socat`.                                                                     |
| Structured logging                                                                              | `log` namespace — leveled, structured, JSON or text output                                                                                  | **Direct fit.** Replaces `__print_*` helpers.                                                        |
| Parallel work (e.g. multi-instance status)                                                      | `task` namespace — `run`, `await`, `awaitAll`, `awaitAny`, `timeout`, `race`                                                                | **Direct fit.** No goroutine equivalent in bash; this is pure upgrade.                               |
| Secrets handling (Steam password, webhook secret)                                               | `secret(value)` built-in — auto-redacts in logs and string interpolation                                                                    | **Direct fit + safety upgrade.** Bash leaks secrets into logs all the time.                          |
| CLI argument parsing with subcommands                                                           | Argument parsing in stdlib — spec-driven, auto-generated help                                                                               | **Direct fit.** Replaces the hand-rolled bash case statements.                                       |
| Structured error handling                                                                       | Built-in error types (`IOError`, `ParseError`, `CommandError`, etc.), `try`/`catch`, `defer`, `retry`, `timeout` blocks                     | **Direct fit.** Replaces the 47-code numeric exit-code taxonomy.                                     |
| Testing                                                                                         | TAP infrastructure + `assert` namespace built into the language spec                                                                        | **Direct fit.** Replaces the bespoke bash test framework in `tests/`.                                |

The one big external tool KGSM still needs (SteamCMD) is genuinely a
subprocess — Stash's `$(...)` and `process.spawn` handle it cleanly,
with `CommandError` for typed failure handling.

In short: where the Go design (§10) had to *build* most of these layers
from third-party packages, the Stash design *uses* what's already
there. The KGSM-specific code shrinks dramatically.

---

## 2. Guiding principles (deltas vs §10)

The §10 principles still hold, with two amendments:

1. **"Single static binary"** is dropped as a principle. Stash is
   interpreted; the user installs Stash, then installs KGSM as a
   collection of `.stash` files. This is the biggest tradeoff
   (discussed in §13.1).
2. **"Use the platform's idioms"** is added. When Stash provides a
   stdlib namespace for something we'd otherwise build ourselves,
   we use it. The KGSM codebase should look like idiomatic Stash —
   not a Stash translation of a Go program.

Everything else carries over: declarative-first blueprints; strategies
+ hooks; SQLite for the registry (with caveats — see §6); systemd as
the default supervisor; structured events; `--json` everywhere.

---

## 3. Project shape

```
kgsm/
  bin/
    kgsm                          (#!/usr/bin/env stash entry point)
  src/
    main.stash                    (CLI dispatch)
    cli/
      install.stash
      uninstall.stash
      instance.stash
      blueprint.stash
      config.stash
      event.stash
      system.stash
    domain/
      blueprint.stash             (struct definitions, validation)
      instance.stash              (struct, registry helpers)
      ports.stash                 (port spec parsing)
    strategy/
      source/
        steamcmd.stash
        http_tarball.stash
        custom_hook.stash
      runtime/
        native.stash
        compose.stash
      readiness/
        log_pattern.stash
        port_check.stash
        tcp_probe.stash
        http.stash
        command.stash
        none.stash
      version/
        steamcmd_buildid.stash
        github_release.stash
        none.stash
      console/
        stdin.stash
        rcon.stash
        none.stash
    supervisor/
      systemd.stash               (uses scheduler namespace)
      foreground.stash            (uses process namespace)
      managed.stash               (talks to optional kgsmd)
    integration/
      ufw.stash
      upnp.stash
      steamcmd.stash              (typed adapter around the steamcmd binary)
      compose.stash
    events/
      bus.stash
      sink/
        unix_socket.stash
        webhook.stash
        file.stash
        journald.stash
    registry/
      sqlite.stash                (if a sqlite binding is available)
      file.stash                  (fallback: per-instance TOML + index)
    util/
      atomic_write.stash
      lockfile.stash
  blueprints/                     (bundled blueprints, shipped with KGSM)
  hooks/                          (bundled reference hooks)
  templates/                      (Jinja2 templates for units, READMEs, etc.)
  tests/                          (TAP-based, using stash's assert namespace)
```

Stash modules use lexical scoping and explicit `import` / `export`
(per the language spec's module system in §9b). No `source` chains,
no guard variables, no `export -f`. A module imported twice executes
once.

---

## 4. Blueprints

Same TOML-based, declarative shape as in §10, parsed natively:

```stash
import toml
import config

fn loadBlueprint(path) {
    let raw = config.read(path)        // format-agnostic; TOML, YAML, or JSON
    return validateBlueprint(raw)
}
```

Blueprint validation uses Stash structs and the built-in `is`
operator for type checks. Where the Go design specified
`Blueprint` as a Go struct, the Stash design specifies it as a Stash
struct:

```stash
struct Blueprint {
    schema: int,
    name: string,
    display_name: string,
    runtime: string,                   // "native" | "container"
    source: SourceSpec,
    server: ServerSpec,
    network: NetworkSpec,
    lifecycle: LifecycleSpec,
    readiness: ReadinessSpec,
    console: ConsoleSpec,
    version: VersionSpec,
    backup: BackupSpec,
    hooks: dict                        // hook name → script path
}

struct ServerSpec {
    executable: string,
    args: array,
    working_dir: string,
    env: dict
}

// ... etc
```

Per the user-memory note, **structs over dicts** for everything
structured. Raw `dict` is reserved for genuinely open-ended data
(e.g. environment variables, hook outputs).

### Templates

`server.args` may contain template references. Stash's `tpl`
namespace handles this directly:

```stash
import tpl

fn renderArgs(spec, ctx) {
    let out = []
    for arg in spec.args {
        out.append(tpl.render(arg, ctx))
    }
    return out
}
```

`ctx` is a single `Instance` struct. Same surface as the Go design
(`{{ .Ports.game }}`), same restriction (no shell-out from inside
templates).

---

## 5. The CLI

Stash's stdlib has a spec-driven argument parser. The whole CLI
becomes a single spec object:

```stash
import argparse

const CLI_SPEC = {
    name: "kgsm",
    description: "Game server orchestrator",
    subcommands: {
        instance: {
            subcommands: {
                install: {
                    positional: ["blueprint"],
                    options: {
                        "name":         { type: "string" },
                        "install-dir":  { type: "string" }
                    }
                },
                start:   { positional: ["id"], flags: ["detached"] },
                stop:    { positional: ["id"], flags: ["no-save"] },
                status:  { positional: ["id"], flags: ["json", "watch"] },
                logs:    { positional: ["id"], flags: ["follow"], options: { "tail": { type: "int", default: 50 } } },
                console: { positional: ["id"] },
                send:    { positional: ["id", "command"] },
                // ...
            }
        },
        blueprint: { /* ... */ },
        config:    { /* ... */ },
        event:     { /* ... */ },
        system:    { /* ... */ }
    }
}

fn main(argv) {
    let args = argparse.parse(CLI_SPEC, argv)
    // dispatch on args.subcommand chain
}
```

Help text, completion, and validation are auto-generated. The exit
code contract from §10 (0 / 1 / 2 + structured JSON error body) is
preserved, implemented via Stash's typed error catches:

```stash
fn dispatch(args) {
    try {
        runCommand(args)
        return 0
    } catch (ValueError e) {
        io.eprintln($"Usage error: {e.message}")
        return 1
    } catch (CommandError e) {
        log.error("Subcommand failed", { command: e.command, exitCode: e.exitCode, stderr: e.stderr })
        return 2
    } catch (IOError e) {
        log.error("I/O error", { message: e.message })
        return 2
    }
}
```

`CommandError` is built-in and includes `exitCode`, `stderr`, `stdout`,
and `command`. This is exactly what we need to surface external-tool
failures (SteamCMD, UFW, `upnpc`) with structure instead of regex.

---

## 6. Process supervision

### 6.1 systemd via the `scheduler` namespace

The `scheduler` namespace exists for this exact purpose:

```stash
import scheduler

fn installAsService(inst) {
    let def = scheduler.ServiceDef {
        name:               inst.id,
        scriptPath:         inst.startScript,
        description:        $"KGSM-managed: {inst.blueprint}",
        workingDir:         inst.installDir,
        env:                inst.runtimeEnv,
        user:               inst.owner,
        autoStart:          true,
        restartOnFailure:   true,
        maxRestarts:        3,
        restartDelaySec:    5,
        system:             inst.systemScope
    }
    scheduler.install(def)
}
```

Stash generates the unit (or launchd plist, or Task Scheduler entry)
under the hood. KGSM does not own the unit-template strings.

**This is a major win.** All of `service.tp`, `socket.tp`, the
`systemctl daemon-reload` dance, the enable/disable orchestration,
and the cross-platform abstraction layer collapse into ~10 lines.

### 6.2 The console-input problem

`scheduler` does not (today, per its spec) expose `ListenFIFO` /
`StandardInput=socket`. So console input has two paths:

- **For `foreground` and `managed` supervisors:** `process.spawn` +
  `process.write(proc, "/save\n")`. Direct stdin write.
- **For the `systemd` supervisor:** KGSM still needs to provision
  the FIFO socket separately. Two options, in order of preference:
  1. **Push the FIFO support upstream into Stash's `scheduler`
     namespace** (e.g. as `scheduler.ServiceDef.stdin = "fifo://..."`).
     This is the right long-term answer.
  2. **Side-channel:** KGSM writes a small companion `<inst>.socket`
     unit alongside the scheduler-generated `.service` unit. This
     reproduces today's bash behaviour and is a viable interim.

Until upstream support lands, ship option 2; document that it's a
patch on top of `scheduler`.

### 6.3 Foreground supervisor

```stash
import process

fn runForeground(inst) {
    let proc = process.spawn(inst.command)
    log.info("Server started", { instance: inst.id, pid: proc.pid })

    // Forward stdin to the child while it runs
    process.onExit(proc, (result) => {
        events.emit("instance.exited", { instance: inst.id, exitCode: result.exitCode })
    })

    let result = process.wait(proc)
    return result.exitCode
}
```

Note `defer` and `try` integrate naturally — a crash in the supervisor
body still cleans up the child:

```stash
fn runForeground(inst) {
    let proc = process.spawn(inst.command)
    defer {
        if process.isAlive(proc) {
            process.kill(proc)
            process.waitTimeout(proc, 5000) ?? process.signal(proc, process.SIGKILL)
        }
    }
    return process.wait(proc).exitCode
}
```

This is much cleaner than the bash equivalent in
[manage.native.d/03](../../../templates/manage.native.d/) and
removes the entire class of TOCTOU bugs around PID files.

---

## 7. Events and webhooks

The whole event subsystem fits in three small modules.

### 7.1 Bus

```stash
import log
import time
import json

fn emit(name, data) {
    let evt = {
        schema:        1,
        id:            crypto.uuid(),
        name:          name,
        ts:            time.nowIso(),
        host:          sys.hostname(),
        kgsm_version:  KGSM_VERSION,
        data:          data
    }

    // Persist to outbox (registry table or append to JSONL fallback)
    outbox.append(evt)

    // Also log structured so journald sinks pick it up
    log.info("event", evt)
}
```

### 7.2 Webhook sink

```stash
import http
import crypto
import log

fn deliver(evt, conf) {
    let body = json.stringify(evt)
    let sig  = crypto.hmac("sha256", reveal(conf.secret), body)

    retry(times: 3, delay: 1000, backoff: "exponential") {
        let r = http.request({
            method:  "POST",
            url:     conf.url,
            headers: {
                "Content-Type":      "application/json",
                "X-KGSM-Signature":  $"sha256={sig}"
            },
            body:    body,
            timeout: conf.timeout
        })
        if r.status >= 500 {
            throw IOError { message: $"HTTP {r.status}" }
        }
        return r
    }
}
```

`retry` is a **language-level construct** (per language spec §7d),
not a third-party library. `secret(conf.secret)` ensures the value
never accidentally appears in a log message. `crypto.hmac` is stdlib.
`http.request` is stdlib. The handler is ~20 lines and there is no
external dependency.

### 7.3 Unix socket sink

```stash
import net

let sock = net.unix.connect(conf.path)
sock.write(json.stringify(evt) + "\n")
```

Replaces the entire `events.socket.sh` module and the `socat`
dependency.

---

## 8. Watchers

Stash has `task.timeout`, `task.race`, and `fs.watch`. The bash
implementation's `timeout <T>s bash -c '...'` becomes a clean
expression:

```stash
import fs
import task

fn waitForLogPattern(logFile, pattern, timeoutMs) {
    return task.timeout(timeoutMs, () => {
        for line in fs.tail(logFile, follow: true) {
            if str.matches(line, pattern) {
                return true
            }
        }
    }) ?? throw TimeoutError { message: "log pattern not seen" }
}

fn waitForPort(port, proto, timeoutMs) {
    return task.timeout(timeoutMs, () => {
        while true {
            if net.portInUse(port, proto) { return true }
            time.sleepMs(500)
        }
    }) ?? throw TimeoutError { message: $"port {port} not active" }
}
```

Each readiness strategy is a function with the same signature
(`fn(spec, ctx) -> bool, throws TimeoutError`). The dispatcher just
looks up the function by `readiness.kind`.

---

## 9. Configuration

```stash
import config
import toml

const CONFIG_PATH = path.join(env.xdgConfigHome(), "kgsm/config.toml")

struct Config {
    schema:   int,
    defaults: Defaults,
    steam:    SteamConfig,
    network:  NetworkConfig,
    events:   EventsConfig
}

struct SteamConfig {
    username:    string,
    secret_file: string
}

fn loadConfig() {
    let raw = config.read(CONFIG_PATH)
    let cfg = parseConfig(raw)
    if cfg.steam.secret_file != "" {
        cfg.steam.password = secret(fs.readFile(cfg.steam.secret_file).trim())
    }
    return cfg
}
```

Schema migrations: same idea as §10, implemented as a small dispatcher
over numbered `migrations/00X_*.stash` files. Each migration imports a
fresh copy of the TOML, transforms it, writes back. Stash's `defer`
makes the "always restore from backup on failure" pattern trivial:

```stash
fn migrate(path, fromV, toV) {
    let backup = path + ".pre-migration-v" + str(fromV) + ".bak"
    fs.copy(path, backup)
    defer {
        if lastError() != null {
            fs.copy(backup, path)
            log.warn("Migration rolled back", { from: fromV, to: toV })
        }
    }
    runMigrations(path, fromV, toV)
}
```

---

## 10. Registry: SQLite or filesystem?

**The honest answer:** SQLite is not in the Stash standard library
(per the table of contents — there's `csv`, `json`, `toml`, `yaml`,
`ini`, but no `sqlite`). Two paths:

### 10.1 If a Stash SQLite binding exists or can be added

Use it. Same design as §10.5: registry is the fast path,
`<install_dir>/.kgsm/instance.toml` is the recovery path.

### 10.2 If not (today's reality)

Use the filesystem itself, mitigated by an index file. Layout:

```
$XDG_STATE_HOME/kgsm/
  index.toml                       (instance_id → install_dir, blueprint, supervisor)
  instances.lock                   (file lock for concurrent CLI safety)
```

Each instance's authoritative metadata still lives at
`<install_dir>/.kgsm/instance.toml`. The index is a **rebuildable
cache** — `kgsm system rebuild-index` walks installed instances and
recreates it.

Concurrency: wrap every index mutation in a flock. Stash exposes
file locking via `fs` (or via `process.spawn("flock", ...)` as a
worst-case fallback).

This is genuinely worse than SQLite in three ways:

- No transactional multi-row updates.
- "List all systemd-supervised instances installed in the last 30
  days" requires scanning, not querying.
- Lock contention scales poorly past a few dozen concurrent CLI
  invocations.

For KGSM's actual scale (a single host, dozens of instances at most,
one or two simultaneous CLI calls), this is acceptable. **If KGSM
ever needs richer queries, fund the SQLite binding** — the Stash
ecosystem benefits too.

---

## 11. Testing

Stash ships TAP infrastructure and an `assert` namespace. KGSM tests
become first-class:

```stash
// tests/strategy/source/steamcmd.test.stash

import test
import strategy.source.steamcmd as src

test.declare("steamcmd source", () => {
    test.it("anonymous login when no credentials configured", () => {
        let cmd = src.buildDownloadCommand({ appId: 12345, credentials: null }, "/tmp/dest")
        assert.contains(cmd, "+login anonymous")
    })

    test.it("authenticated login with credentials", () => {
        let cmd = src.buildDownloadCommand({
            appId: 12345,
            credentials: { username: "u", password: secret("p") }
        }, "/tmp/dest")
        assert.contains(cmd, "+login u p")
    })
})
```

No sandboxing rituals. No `tests/framework/sandbox.sh`. No fake
KGSM_ROOT trees. Strategies are pure functions of their inputs;
fakes for external tools are written as Stash modules with the same
exported surface.

The **integration tests** (real SteamCMD, real systemd) still need
the existing sandbox mechanism, but it shrinks dramatically because
Stash modules don't need bootstrapping.

---

## 12. Comparison: Stash vs Go for KGSM

| Concern                              | Go (§10)                                   | Stash (this doc)                                        | Winner                |
| ------------------------------------ | ------------------------------------------ | ------------------------------------------------------- | --------------------- |
| Process management                   | `os/exec` (low-level, footgun-prone)       | `process` namespace (high-level, designed for this)     | **Stash**             |
| systemd integration                  | `go-systemd` DBus + manual unit generation | `scheduler.install()` — one call                        | **Stash**             |
| Templates                            | `text/template` or `pongo2` (third-party)  | `tpl` namespace (built-in Jinja2)                       | **Stash**             |
| TOML                                 | `pelletier/go-toml` (third-party)          | `toml`/`config` namespaces (built-in)                   | **Stash**             |
| Crypto / HMAC                        | `crypto/hmac` (built-in)                   | `crypto.hmac` (built-in)                                | Even                  |
| HTTP client                          | `net/http` (built-in, verbose)             | `http.request` (built-in, terse)                        | **Stash**             |
| Argument parsing                     | `cobra` (third-party, large)               | `argparse` (built-in, spec-driven)                      | **Stash**             |
| Structured logging                   | `slog` (built-in, recent)                  | `log` namespace (built-in)                              | Even                  |
| Concurrency                          | goroutines + channels (powerful)           | `task` namespace (futures, delays, races)               | **Go** (deeper model) |
| Static type safety                   | Yes — catches mistakes at compile time     | No — runtime type errors                                | **Go**                |
| SQLite                               | First-class library                        | Not yet in stdlib                                       | **Go**                |
| Compilation / startup                | Compiled, ~5ms startup                     | AOT-compiled native binary, single-digit ms startup     | Even                  |
| Distribution                         | Single static binary                       | User must install Stash first                           | **Go**                |
| Cross-compile                        | Trivial (`GOOS/GOARCH`)                    | Runs on Windows, Linux, macOS — .NET targets all three  | Even                  |
| LSP / DAP for the language itself    | Mature                                     | Fully implemented — 28 LSP handlers, DAP with 129 tests | Even                  |
| Test ergonomics                      | `testing` + table-driven                   | TAP + `assert` (fits scripting style)                   | Even                  |
| Lines of KGSM code we'd write        | ~8–12 KLOC estimated                       | ~3–5 KLOC estimated                                     | **Stash**             |
| Idiomatic fit for the problem domain | Good                                       | **Excellent**                                           | **Stash**             |

The pattern: Go wins on **engineering rigour** (types, perf, deployment).
Stash wins on **fit for purpose** (the stdlib was designed for this
exact kind of script). Which matters more depends on KGSM's user
base and operational reality.

---

## 13. Honest tradeoffs of choosing Stash

These are the things that would worry me if I were the maintainer
making this decision.

### 13.1 No single static binary

Users must install Stash first, then install KGSM (a directory of
`.stash` files). This is a real regression from the Go design.

**Mitigations:**
- Ship a `kgsm-bundle.tar.gz` that includes a pinned Stash interpreter
  alongside the KGSM scripts. Single download, slightly larger (Stash
  interpreter is C# / .NET — probably ~30 MB).
- Distribution packages (`apt`, `pacman`, `nix`) declare `stash` as
  a dependency. Most users install through a package manager anyway.
- The user-facing UX (one command to install, then `kgsm ...`) is
  unchanged. The "two installs" reality is invisible if packaged
  correctly.

### 13.2 Dynamically typed

The §10 design leans on Go's type system to catch shape mismatches
at compile time. In Stash, those become runtime errors.

**Mitigations:**
- Stash has `is`, typed catches, and structs with named fields;
  most type errors surface immediately on the first call rather than
  after a long-running operation.
- Aggressive validation at boundaries — `loadBlueprint`, `loadConfig`,
  hook output parsing all validate fully before returning structs.
- LSP coverage (per the language spec) catches a lot statically even
  without a full type checker.

### 13.3 SQLite not in stdlib

Discussed in §10. Acceptable workaround exists for KGSM's scale.

### 13.4 Performance

Stash compiles to a **register-based VM** (not stack-based) with
constant folding, dead branch elimination, peephole optimisation,
superinstructions, inline caching, and integer-specialised loop
opcodes. The CLI binary is distributed as a .NET Native AOT
self-contained executable, which eliminates JIT warm-up entirely.

Actual benchmark results (median of 3 runs, same workload and
algorithms as Python / Node / Ruby / Bash):

| Benchmark                            |  Stash | Python | Node.js |   Ruby |      Bash |
| ------------------------------------ | -----: | -----: | ------: | -----: | --------: |
| Algorithms (recursion, sort, struct) | 101 ms |  73 ms |    6 ms |  52 ms | 10,589 ms |
| Function calls (600k)                |  68 ms |  79 ms |    3 ms |  17 ms |  3,645 ms |
| Expression throughput                | 156 ms | 180 ms |   15 ms | 189 ms |  4,928 ms |
| Built-in functions (2.6M calls)      | 180 ms | 295 ms |   30 ms | 351 ms | 23,220 ms |
| Scope lookup                         |  95 ms | 101 ms |    8 ms | 136 ms |  3,185 ms |

Stash is consistently faster than Python and Ruby at typical sysadmin
workloads and roughly 30–50× faster than Bash. Node.js is faster
(V8's JIT is a decade of investment), but Node is not a realistic
alternative for this problem. The comparison that matters is
**Stash vs Python** — and Stash wins that across all five benchmarks.

Startup latency via AOT will be in the same ballpark as a compiled
Go binary — single-digit milliseconds — and is not a practical
concern for a CLI tool that immediately spends time on disk I/O or
SteamCMD.

**Mitigations (residual concerns):**
- KGSM's hot path is *not* CLI startup — it's downloading multi-GB
  game files. Startup is in the noise regardless of the language.
- The lifecycle scripts run **inside** systemd as ExecStart; they
  start once per server boot.
- For shell-completion specifically, ship pre-rendered completion
  files as a belt-and-suspenders precaution.

### 13.5 Younger language, smaller community

Stash is at v0.1 (per its own spec header). Bugs in the interpreter
or stdlib will block KGSM. Go's interpreter and stdlib are 15+ years
mature.

**Mitigation:** This is a real risk and the reason this design is
proposed alongside the Go one rather than replacing it. KGSM's
adoption of Stash is also a contribution to Stash; expect to file
bugs and possibly upstream patches (e.g. the FIFO support discussed
in §6.2, the SQLite binding in §10).

### 13.6 No language-level concurrency primitives

The language spec explicitly lists "Concurrency primitives" as a
non-goal for v1. The `task` namespace covers async/await-style
parallelism, but there are no goroutines, channels, or mutexes.

**For KGSM this is fine.** The only concurrency needs are:
- Parallel status checks across instances → `task.awaitAll`. Done.
- Background event delivery → spawn a worker via `process.spawn` or
  use a tiny in-process loop. Done.
- Concurrent CLI invocations on the same registry → flock. Done.

If KGSM ever gains a long-running daemon mode (`kgsmd`), that's
where the lack of concurrency primitives might bite. By that point
Stash will likely have grown some.

---

## 14. Implementation order (Stash-flavoured)

Same shape as §10.17, with adjustments for what Stash gives us free:

1. **Skeleton + CLI scaffolding + config loader.** ~1 day. The
   `argparse` + `config` + `log` stdlib means this is mostly typing.
2. **Blueprint loader + struct definitions + validator.** ~2 days.
3. **Registry (filesystem variant) + `instance install` for a trivial
   blueprint.** ~3 days.
4. **Native runtime + foreground supervisor** using `process`. ~2 days.
5. **`steamcmd` source strategy + `log_pattern` readiness.** ~3 days.
6. **`systemd` supervisor via `scheduler` namespace** + the FIFO
   side-channel for console input. ~3 days.
7. **Event bus + webhook + unix-socket + journald sinks.** ~2 days.
8. **Container runtime via `compose` integration.** ~3 days.
9. **UFW + UPnP integrations.** ~2 days.
10. **Hook protocol + reference hooks.** ~2 days.
11. **`kgsm-import` from old KGSM.** ~3 days.

Estimated end-to-end: ~25 person-days for parity with current KGSM.
The Go equivalent in §10 would land closer to ~50.

This is the primary practical argument for Stash: **time-to-parity
is much shorter when the stdlib already covers your problem.**

---

## 15. Decision log additions

Appending to the §10 decision log; same numbering scheme:

| #   | Decision                                                                              | Rejected alternatives                                         | Why                                                                                                 |
| --- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| 13  | Stash as the implementation language                                                  | Go (§10), Rust, Bash                                          | Stdlib aligns ~70% with KGSM's needs; estimated 50% less code; idiomatic fit for sysadmin scripting |
| 14  | Use `scheduler` namespace for systemd                                                 | Generate units manually + shell to `systemctl`                | Works on macOS/Windows transparently; collapses ~200 lines to ~10                                   |
| 15  | Use `tpl` namespace for all templating                                                | Hand-rolled string substitution, third-party engines          | Built-in, Jinja2-compatible, expression access to full language                                     |
| 16  | Use `secret()` for all credentials                                                    | Plain strings + manual log scrubbing                          | First-class redaction; no accidental log leaks                                                      |
| 17  | Use `retry`/`timeout`/`defer` blocks instead of helper funcs                          | Hand-written retry loops, channel-based timeouts              | Language-level constructs; clearer code; built-in error propagation                                 |
| 18  | Filesystem registry with index, not SQLite (until binding exists)                     | Block on SQLite binding, ship without registry                | Acceptable at KGSM's scale; index is rebuildable; SQLite remains the right answer if/when available |
| 19  | Bundle Stash with KGSM in the user-facing package                                     | Make users install Stash separately                           | Preserves the "one download" UX; users don't need to learn about Stash                              |
| 20  | TAP-based tests using `assert` namespace                                              | Reuse existing bash test framework                            | Stash's testing infra was designed for this; tests become readable                                  |
| 21  | Side-channel `.socket` unit alongside scheduler-generated `.service` for FIFO console | Wait for `scheduler` to grow FIFO support; no console support | Pragmatic interim that matches today's behaviour; upstream the proper fix later                     |

---

## 16. TL;DR (Stash edition)

> The Stash standard library was designed for a problem class that
> includes KGSM. `process`, `scheduler`, `tpl`, `crypto`, `http`,
> `task`, `secret()`, `retry`, `defer`, `argparse`, and the structured
> error system collectively replace ~70% of what we'd otherwise write
> by hand in Go (or 90% in Bash). The KGSM-specific code becomes
> small enough to fit in a developer's head: ~3–5 KLOC of Stash vs
> ~8–12 KLOC of Go vs ~10 KLOC of Bash today.
>
> The cost is real: no single static binary, dynamic typing, missing
> SQLite binding, a young language with a small community. None of
> those are fatal for KGSM's scope, and several can be improved by
> upstream contributions that benefit Stash too.
>
> If the question is *"which choice produces the best engineered
> system?"*, Go (§10) wins narrowly on rigour. If the question is
> *"which choice produces a working, maintainable KGSM in the
> shortest time?"*, **Stash wins decisively.** For a single-maintainer
> project orchestrating game servers on Linux, that's the question
> that matters.
