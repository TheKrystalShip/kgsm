# cgroup Supervision — Implementation Plan

**Status:** Living · **Created:** 2026-06-12 · **Owner:** KGSM

Tracking doc for giving KGSM **native cgroup-v2 process supervision** as the
single spawn mechanism for game-server instances, removing the dependency on
systemd for crash protection and process-tree handling. This is the foundation
for a future **kgsm-watchdog** (a desired-state reconciler).

## Problem

Standalone (non-systemd) instances have **no crash/restart protection**, and
KGSM's native lifecycle tracks a single PID (`kill -0`) and kills only direct
`pgrep -P` children — so detached/double-forked children escape both liveness
detection and teardown. systemd handles this correctly only because it supervises
a **cgroup**, not a PID. Decision: give KGSM that primitive natively.

## End-state model — every instance is cgroup-scoped; owner differs by kind

| Kind | cgroup owner | Notes |
|---|---|---|
| Native (standalone **and** systemd) | **KGSM** | The new work |
| Container | Docker | KGSM/monitor only read it; unchanged |

systemd is demoted to a **boot launcher** — no longer the supervisor.

## Locked decisions (2026-06-12)

- **Purist end-state, staged.** Ship standalone-native cgroup support first
  (greenfield), then demote systemd as a fast-follow.
- **Delegated `kgsm.slice` via one-time privileged setup** (`kgsm system
  setup-cgroups`): create + `chown` the subtree and enable controllers once;
  spawns run unprivileged afterward. Honest cost: partially reintroduces a
  privilege requirement (different from systemd, not free).

## Invariants & gotchas

- Native identity flips from `.pid` → **cgroup path** (`.pid` demoted to display).
- Spawn pattern: `( echo $BASHPID > cgroup.procs; exec game <fifo &>log )` — exec
  **into** the cgroup, no attach-after race.
- The keepalive `tail -f /dev/null --pid=…` and the FIFO writer MUST stay
  **outside** the cgroup, or `cgroup.events:populated` never clears and liveness
  is stuck "alive."
- Liveness = `cgroup.events:populated`; teardown = `cgroup.kill` (kernel ≥5.14 —
  a stated system requirement) after graceful stop-command + bounded wait.
- Tests run real KGSM, no mocks, as the invoking user → cgroup-required lifecycle
  needs a delegated cgroup in test setup (capability-gate when unavailable).

---

## Increment 0 — cgroup foundation + delegation bootstrap  ◀ DONE (2026-06-12)

The dependency root; independently testable given a delegated cgroup.

- [x] `core/cgroup.sh` — primitives + capability detection
      (`__cgroup_supported`, `__cgroup_base`, `__cgroup_path`,
      `__cgroup_enable_string`, `__cgroup_enable_controllers`,
      `__cgroup_kernel_has_kill`, `__cgroup_create`, `__cgroup_attach`,
      `__cgroup_is_populated`, `__cgroup_kill`, `__cgroup_remove`). Lazy-load
      guard + `export -f`; registered in `core/common.sh`.
- [x] `core/errors.sh` — added `EC_CGROUP=47`, `EC_CGROUP_UNSUPPORTED=48`
      (+ EXIT_CODES entries).
- [x] `kgsm system setup-cgroups` — privileged, idempotent: enables controllers
      at the mount root + base `cgroup.subtree_control`, creates the base,
      `chown`s the subtree to the target user. (`commands/system.sh` +
      `commands/handlers/system.sh::__logic_setup_cgroups`.) Verified: non-root
      → `EC_PERMISSION` with guidance; bogus arg → `EC_INVALID_ARG`.
- [x] `[cgroup]` config section in `config.default.ini` (enable_cgroups,
      cgroup_mount_point, cgroup_base_name, cgroup_controllers).
- [x] Migration `migrations/config/002_v1_to_v2_add_cgroup_section.sh` + bumped
      `config_schema_version` to 2 + 3 `test_config_migrations.sh` cases.
- [x] `tests/unit/test_cgroup.sh` — 9 deterministic + 1 capability-gated live
      round-trip (skips without a delegated base). All green.
- [x] `shellcheck` clean on new files; pre-existing warnings (SC2034 EXIT_CODES /
      TEST_NAME, SC2254 case-label style) left untouched, matching the codebase.

Test status: `test_cgroup` 10/10, `test_config_migrations` 11/11. Full unit
suite 41/44 — the 3 reds (`test_directories_commands`, `test_files_upnp_commands`,
`test_instances_logic`) are **pre-existing**, confirmed failing on the clean tree
with these changes stashed.

## Finding from live verification (2026-06-12) — the entry-bootstrap constraint

The live round-trip (run after `setup-cgroups` succeeded) surfaced a real Linux
constraint, not a bug: **`chown`ing `kgsm.slice` to the user grants *management*
rights (create/remove child cgroups, set `subtree_control`) but NOT the right to
*move a process into* it.** cgroup-v2 delegation containment requires write access
to the `cgroup.procs` of the **common ancestor** of the source and destination
cgroups. A process living in `system.slice/sshd.service` (an SSH login) moving
into `kgsm.slice` has the **root cgroup** as common ancestor — which the user
doesn't own → `EACCES`. Verified directly.

Consequences:
- **`__cgroup_attach` of an externally-started process can't work rootless.** This
  *validates* the exec-into-cgroup choice — but even exec-into-cgroup self-move
  fails the same way if the parent isn't already inside `kgsm.slice`.
- The "no internal processes" rule also means a process can't sit in `kgsm.slice`
  directly once controllers are enabled there.
- **Working runtime topology:** `kgsm.slice/{supervisor, <inst1>, <inst2>, …}`.
  One privileged act places the long-lived KGSM **supervisor** into
  `kgsm.slice/supervisor` (root, or a systemd scope under the slice). The
  supervisor then forks each game (born inside `kgsm.slice/supervisor`) and moves
  it into `kgsm.slice/<inst>` — an **intra-`kgsm.slice`** move whose common
  ancestor the user owns → allowed. Everything after the one bootstrap entry is
  rootless.
- So "unprivileged after one-time setup" holds for *management*, but the
  **supervisor's initial entry** needs root or systemd — which is exactly the
  Increment 2 systemd-boot-launcher decision, now concretely grounded.

Increment 0's primitives and the delegated base are correct and unchanged; this
finding constrains **who spawns** in Increment 1.

## Architecture decision (2026-06-12) — resident supervisor = `kgsm-watchdog`

The headless requirement (KGSM must spawn into cgroups with **zero per-operation
privilege escalation**, callable by automated processes like the Discord bot)
collapses the design space: an arbitrary client process can't enter `kgsm.slice`
without root or a spawner already inside it. The chosen answer is a **resident
KGSM supervisor daemon** placed in `kgsm.slice/supervisor` once at boot; CLI /
kgsm-lib / bot become **thin clients** that delegate lifecycle ops to it over a
unix socket. **This deliberately breaks KGSM's "stateless / no warm process"
invariant** (root CLAUDE.md, keystone §4) — accepted, eyes-open, because the
daemon *is* the watchdog the project already wanted, so it earns its keep.

The supervisor **is** `kgsm-watchdog`: it owns `kgsm.slice`, forks game processes
into per-instance cgroups, AND does crash-restart. The two hard supervision
problems are both solved by this one component — **detection** via per-instance
`cgroup.events` (it's the parent + reads the kernel signal, race-free), and
**intent** via the desired-state it holds (it received the start command, so it
knows what *should* run and whether a stop was requested).

> **Doc follow-up:** keystone §4 + root CLAUDE.md assert statelessness; both need
> amending to record this break. Not yet done.

## Increment 1 — supervisor daemon (`kgsm-watchdog`): minimal spawn path

- [ ] Resident daemon: self-places into `kgsm.slice/supervisor`, drops to the
      kgsm user, stays in-cgroup.
- [ ] Control socket (model on the events socket / monitor `/run` socket).
- [ ] `start <inst>`: fork game → born in `kgsm.slice/supervisor` → move to
      `kgsm.slice/<inst>` (intra-slice, allowed). Reuse the native I/O model
      (FIFO-stdin, logfile-stdout); keepalive/FIFO writer stay OUTSIDE the cgroup.
- [ ] `stop <inst>`: graceful stop-command → bounded drain → `cgroup.kill` →
      `cgroup.remove`.

**Open design questions to settle first:** (a) **stack** — bash long-lived daemon
vs .NET-AOT like kgsm-monitor; (b) **spawn-logic ownership** — daemon reimplements
FIFO/exec vs drives the existing `manage.native.d` script; (c) **control
protocol** shape; (d) **bootstrap-entry** mechanism (how it lands in the slice).

## Increment 2 — watchdog behavior: crash detection + restart

- [ ] Per-instance `cgroup.events` watch (`poll()`), desired-state table.
- [ ] Crash = populated→0 with no stop requested → restart.
- [ ] Exponential backoff + flap rate-limit + give-up/"failed" state.

## Increment 3 — make CLI / kgsm-lib / bot clients + boot integration

- [ ] `kgsm.sh start/stop` + kgsm-lib route to the supervisor socket when present.
- [ ] Native direct-spawn path superseded; systemd `Restart=` dropped (no dueling
      supervisors); `Delegate=yes` where systemd hosts the daemon.
- [ ] Boot variants: non-systemd init script (root → enter slice → drop privs) /
      systemd unit (`Slice=kgsm.slice` + `User=`) / rootless user + `enable-linger`.

## Increment 4 — cross-repo (additive)

- [ ] kgsm-lib: supervisor socket client + `Instance.CgroupPath` (register in
      `KgsmJsonContext`).
- [ ] kgsm-monitor: fold native into the cgroup kinds (fixes CPU/mem accuracy +
      PID-reuse fragility; `io.stat` still controller-gated; per-server net still
      uncovered).
- [ ] Keystone: add the supervisor to the topology, amend §4 statelessness, fix
      the §6 ledger + the native anchor of the inventory/cgroup-path contract
      (`kgsm-monitor/PLAN.md §6`).
