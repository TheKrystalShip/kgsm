# 06 — Readiness Watchers

A *watcher* observes a freshly-started instance and emits the
`server.ready` event the moment the server is actually serving
players. This is distinct from `server.started`, which only confirms
that the process was spawned.

Watchers are optional and disabled by default
(`enable_watcher=false`). When enabled, `kgsm start` launches one in
the background; the user may also start one manually with
`kgsm watcher start <instance>`.

---

## 1. Strategy auto-selection

Two strategies exist. Exactly one is picked per invocation, by reading
the instance's config file:

| Priority | Strategy            | Trigger                                        |
| -------- | ------------------- | ---------------------------------------------- |
| 1        | **Log pattern**     | `instance_startup_success_regex` is non-empty. |
| 2        | **Port monitoring** | (fallback) `instance_ports` is non-empty.      |
| —        | None                | Both empty → `EC_WATCHER_NO_STRATEGY`.         |

The selection function is called `__logic_determine_strategy(config_path)` →
echoes either `logs` or `ports`. A reimplementation MUST keep this
priority order: log-pattern is more reliable because it observes a
game-author-defined ready signal; port-monitoring only proves the
process opened a socket.

---

## 2. Inputs and configuration

Defined in [02-data-model.md §1.3](02-data-model.md) under `[watchers]`:

| Key                                    | Default | Meaning                                        |
| -------------------------------------- | ------- | ---------------------------------------------- |
| `enable_watcher`                       | false   | Master switch for auto-launch on `kgsm start`. |
| `watcher_global_timeout_seconds`       | 600     | Maximum total time to wait for readiness.      |
| `watcher_ports_check_interval_seconds` | 5       | Poll interval for the port strategy.           |

From the instance:

- `instance_startup_success_regex` — selects log-strategy and is the
  pattern matched against new log lines.
- `instance_ports` — selects port-strategy; the *first* port in the
  UFW string is the one polled.
- `instance_log_file` — path to the live log (log strategy only).
- `instance_pid_file` — used to abort early if the server process dies.
- `instance_runtime` — `native` (use `kill -0 <pid>`) vs `container`
  (use `docker inspect <id> --format='{{.State.Status}}'` and check
  for `running`).

A per-instance watcher log file (e.g. `<instance_logs_dir>/<instance>.watcher.log`)
SHOULD be written so users can audit watcher decisions after the fact.

---

## 3. Strategy 1 — log pattern

```
inputs:  instance, server_pid, ready_pattern, log_file, timeout_seconds, watcher_log_file
returns: EC_SUCCESS_INSTANCE_READY (222) on match
         EC_WATCHER_TIMEOUT       (41)  on timeout
         EC_ERROR                       if the server process dies during the watch
```

Algorithm: tail the log file (with `--pid=<server_pid>` so the tail
exits if the server dies), grep new lines for `ready_pattern`, exit on
the first match. The whole operation is wrapped in
`timeout <timeout_seconds>s ...`.

The bash implementation is essentially:

```
timeout "${T}s" bash -c '
  tail -n 50 -f --pid="$1" "$2" | grep --line-buffered -q -m 1 -e "$3"
' -- "$server_pid" "$log_file" "$ready_pattern"
```

The `tail -n 50` includes recent lines so a pattern that already
appeared (e.g. the watcher started slightly late) is still caught.

A reimplementation that has native log-tailing capability MAY use it
directly instead of subprocess `tail`/`grep`, but MUST preserve:

- The "process dies → abort" behaviour.
- The timeout.
- The "match anywhere in the recent + future tail" behaviour.

---

## 4. Strategy 2 — port monitoring

```
inputs:  instance, server_pid_or_container_id, port_to_check,
         timeout_seconds, watcher_log_file, check_interval
returns: same exit codes as the log strategy
```

Algorithm: every `check_interval` seconds, do two checks:

1. **Server still alive?**
   - Native (numeric PID): `kill -0 <pid>`. If it fails, abort with
     `EC_ERROR`.
   - Container (non-numeric ID): `docker inspect <id> --format='{{.State.Status}}'`
     must be `running`. If not, abort.
2. **Port active?** Check whether *any* process on the host is
   listening on `port_to_check` (TCP or UDP). The bash implementation
   uses `ss -lntu | grep ":<port>\b"`. A reimplementation MAY use a
   socket-existence syscall instead.

Wrap the loop in `timeout <timeout_seconds>s`.

### 4.1 Port selection

The watched port is the **first** one extracted from the UFW format
string (`__logic_extract_first_port`):

```
input    → output
'34197'              → 34197
'34197/udp'          → 34197
'25565:25575/tcp'    → 25565       (start of range)
'7777|27015/udp'     → 7777        (first spec only)
```

This is a deliberate simplification — KGSM does not try to validate
that the server is listening on every declared port, only that *some*
port is active. Reimplementations MAY broaden this if desired.

---

## 5. Lifecycle integration

When `enable_watcher=true`:

1. `kgsm start <instance>` succeeds.
2. The command layer launches `kgsm watcher start <instance>` in the
   background (detached process). Failure to launch the watcher is
   logged at warning level but does NOT fail the start.
3. The watcher selects a strategy, runs it, and on success emits
   `server.ready`.
4. If the watcher times out or sees the process die, it emits no
   ready event (and exits with the corresponding `EC_WATCHER_*` code).

A reimplementation MAY emit `instance-ready-failed` or similar on
timeout, but the bash implementation does not — only the success path
emits an event. Stay consistent with whichever choice is made.

---

## 6. Manual commands

```
kgsm watcher start  <instance> [--detach]   Launch the watcher.
kgsm watcher stop   <instance>              Kill any running watcher.
kgsm watcher status <instance>              Print which strategy applies and current state.
kgsm watcher test   <instance>              Dry-run: verify a strategy can be selected.
```

The status command MUST report:

- Selected strategy (`logs` / `ports` / `none`).
- For logs: the regex, the log path, whether the log file exists,
  whether the regex has already matched in current contents.
- For ports: the port count from `instance_ports`, how many of those
  are currently active.

This is a diagnostic for users investigating why they never see
`server.ready` events.
