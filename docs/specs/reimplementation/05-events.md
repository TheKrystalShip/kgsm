# 05 — Event System

KGSM emits structured events whenever a noteworthy state change occurs.
Events are delivered over one or both of two transports:

- **Unix Domain Socket** (local IPC) — for same-host consumers.
- **HTTP webhook** (POST request) — for remote consumers.

Both transports are independent and can be enabled simultaneously.
Both deliver the same JSON payload.

> **Important.** Events are emitted only by the parent KGSM tool's
> command layer. Direct invocations of an instance's management script
> bypass the event system entirely. This is intentional — the
> management script is meant to be self-contained and event-emission
> would couple it back to KGSM's transports. Document this in any
> reimplementation.

---

## 1. Configuration

Defined in [02-data-model.md §1.3](02-data-model.md) under `[events]`.
Summary:

```ini
[events]
enable_event_broadcasting=false       # master switch
enable_socket_events=false
event_socket_filenames=kgsm.sock      # comma-separated
enable_webhook_events=false
webhook_urls=                         # comma-separated
webhook_timeout_seconds=10            # 1–300
webhook_retry_count=2                 # 0–5
webhook_secret=                       # if set, requests are HMAC-signed
```

The master switch (`enable_event_broadcasting`) MUST gate everything.
When false, no event is built, no transport is consulted, no syscall
is made.

---

## 2. Naming convention

Each event has two names:

| Surface                  | Style                | Example            |
| ------------------------ | -------------------- | ------------------ |
| CLI / config / log lines | dash-separated       | `server.started` |
| JSON payload `EventType` | underscore-separated | `instance_started` |

These are the same identifier; only the separator differs. A
reimplementation MUST keep both surfaces.

---

## 3. Payload schema

Every event is a JSON object:

```json
{
  "EventType":   "<underscore_name>",
  "Data":        { "InstanceName": "<id>", ... event-specific fields },
  "Timestamp":   "<ISO-8601 UTC>",
  "Hostname":    "<system hostname>",
  "KGSMVersion": "<semver>"
}
```

| Field         | Type   | Notes                                                                                                                                                       |
| ------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EventType`   | string | Underscore-separated.                                                                                                                                       |
| `Data`        | object | Always present. Always contains `InstanceName` (or, for non-instance events like `config_set`, the most-relevant identifier). Field names use `PascalCase`. |
| `Timestamp`   | string | ISO-8601, UTC, with `Z` suffix.                                                                                                                             |
| `Hostname`    | string | `hostname` of the emitting machine.                                                                                                                         |
| `KGSMVersion` | string | The reimplementation's version string.                                                                                                                      |

### 3.1 Data fields per event

| Event (CLI name)                   | `Data` keys                                |
| ---------------------------------- | ------------------------------------------ |
| `server.install.started`    | `InstanceName`, `Blueprint`                |
| `server.install.finished`   | `InstanceName`, `Blueprint`                |
| `server.installed`               | `InstanceName`, `Blueprint`                |
| `server.install.created`                 | `InstanceName`, `Blueprint`                |
| `server.uninstall.removed`                 | `InstanceName`                             |
| `server.install.directories_created`     | `InstanceName`                             |
| `server.uninstall.directories_removed`     | `InstanceName`                             |
| `server.install.files_created`           | `InstanceName`                             |
| `server.uninstall.files_removed`           | `InstanceName`                             |
| `instance-config-installed`        | `InstanceName`                             |
| `instance-config-uninstalled`      | `InstanceName`                             |
| `instance-management-file-created` | `InstanceName`                             |
| `instance-management-file-removed` | `InstanceName`                             |
| `instance-systemd-enabled`         | `InstanceName`                             |
| `instance-systemd-disabled`        | `InstanceName`                             |
| `instance-ufw-enabled`             | `InstanceName`                             |
| `instance-ufw-disabled`            | `InstanceName`                             |
| `instance-symlink-created`         | `InstanceName`                             |
| `instance-symlink-removed`         | `InstanceName`                             |
| `instance-upnp-enabled`            | `InstanceName`                             |
| `instance-upnp-disabled`           | `InstanceName`                             |
| `server.download.started`        | `InstanceName`                             |
| `server.download.finished`       | `InstanceName`                             |
| `server.download.completed`              | `InstanceName`                             |
| `server.deploy.started`          | `InstanceName`                             |
| `server.deploy.finished`         | `InstanceName`                             |
| `server.deploy.completed`                | `InstanceName`                             |
| `server.update.started`          | `InstanceName`                             |
| `server.update.finished`         | `InstanceName`                             |
| `server.update.completed`                 | `InstanceName`                             |
| `server.updated`         | `InstanceName`, `OldVersion`, `NewVersion` |
| `server.started`                 | `InstanceName`, `LifecycleManager`         |
| `server.stopped`                 | `InstanceName`, `LifecycleManager`         |
| `server.restarted`               | `InstanceName`                             |
| `server.ready`                   | `InstanceName`                             |
| `backup.created`          | `InstanceName`, `Source`, `Version`        |
| `backup.restored`         | `InstanceName`, `Source`, `Version`        |
| `server.uninstall.started`       | `InstanceName`                             |
| `server.uninstall.finished`      | `InstanceName`                             |
| `server.uninstalled`             | `InstanceName`                             |
| `blueprint-listed`                 | `Type` (`native` \| `container` \| `all`)  |
| `blueprint-info-retrieved`         | `Blueprint`                                |
| `blueprint-found`                  | `Blueprint`, `Path`                        |
| `blueprint-validated`              | `Blueprint`, `Result`                      |
| `config-set`                       | `Key`, `Value`                             |
| `config-reset`                     | (none required)                            |
| `config-validated`                 | `Result`                                   |
| `config-merged`                    | `SchemaVersion`                            |
| `system-shutdown`                  | (none)                                     |
| `system-restart`                   | (none)                                     |
| `system-info-retrieved`            | (subset of system info)                    |
| `network-port-checked`             | `Port`, `Protocol`, `Status`               |
| `network-port-free`                | `Port`, `Protocol`                         |
| `network-port-in-use`              | `Port`, `Protocol`                         |

> Optional fields MUST be omitted (not set to `null`) when they have
> no meaningful value, except where the JSON consumer benefits from a
> stable shape — in which case use an explicit empty string.

---

## 4. The `events emit` command

A reimplementation MUST expose a manual emission command, structured as:

```
kgsm events emit <event-name> [positional-args...]
```

The positional args map to the `Data` fields in §3.1, in the order
listed there. Examples:

```bash
kgsm events emit server.install.created            myserver factorio
kgsm events emit server.started            myserver systemd
kgsm events emit server.updated    myserver 1.0.0 1.1.0
kgsm events emit backup.created     myserver auto 1.2.3
```

This is the one and only path used internally by the command layer.
Dispatching events is *the* side effect of a successful operation:
the command layer calls `events emit <name> <args>` after the handler
returns success.

---

## 5. Socket transport

### 5.1 Mechanism

KGSM is a **client**, not a server. For each filename listed in
`event_socket_filenames`, the implementation:

1. Resolves the absolute path: `<KGSM_ROOT>/<filename>`.
2. If the path exists, opens a connection (in bash, this is
   `socat - UNIX-CONNECT:<path>`).
3. Writes the JSON payload (one line, no trailing newline required by
   the listener but conventional).
4. Closes the connection.

If the socket file does not exist, the implementation MUST silently
skip that destination — the user-side listener simply has not started
yet. A reimplementation MAY log this at debug level but MUST NOT fail
the calling KGSM operation.

### 5.2 Listener responsibility

The listener (the user's application) is responsible for creating and
binding the socket. KGSM will only ever connect to it. A reference
listener using `socat`:

```
socat UNIX-LISTEN:$KGSM_ROOT/kgsm.sock,fork -
```

### 5.3 Multiple sockets

`event_socket_filenames=kgsm.sock,monitoring.sock` causes each event
to be written to both. Writes happen in parallel; one failing writer
MUST NOT block another.

---

## 6. Webhook transport

### 6.1 Request

For each URL in `webhook_urls`, send an HTTP POST:

```
POST <url> HTTP/1.1
Content-Type: application/json
User-Agent: KGSM/<version>
X-KGSM-Timestamp: <unix-seconds>
X-KGSM-Retry-Count: <n>
X-KGSM-Signature: sha256=<hex>     (only if webhook_secret is set)

<payload-json>
```

### 6.2 Headers

| Header               | Value                                                                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `Content-Type`       | `application/json`                                                                                                                          |
| `User-Agent`         | `KGSM/<version>`                                                                                                                            |
| `X-KGSM-Timestamp`   | Unix epoch seconds at the moment of the *current attempt*.                                                                                  |
| `X-KGSM-Retry-Count` | `0` for the first attempt, incremented by 1 for each retry.                                                                                 |
| `X-KGSM-Signature`   | `sha256=` + lowercase-hex HMAC-SHA256 of the body using `webhook_secret` as the key. Omit the header entirely when no secret is configured. |

### 6.3 Retry policy

- Per-request timeout: `webhook_timeout_seconds` (1–300).
- Retries on failure: up to `webhook_retry_count` (0–5).
- Backoff: exponential. Bash uses `sleep 2^retry` (1s, 2s, 4s, 8s, ...).
  A reimplementation MAY add jitter.
- A request is a failure if: (a) the connection times out, (b) the TCP
  connection is refused, (c) the HTTP response status is ≥ 400.
- Retries MUST update `X-KGSM-Timestamp` and `X-KGSM-Retry-Count`.
  The signature MUST be recomputed iff any signed bytes change (which
  in this scheme is "every retry", because the headers are not in the
  signed body — only the body itself is signed; recomputation is still
  required if the implementation regenerates the JSON each attempt).

### 6.4 Parallelism

When multiple webhook URLs are configured, requests are dispatched in
parallel. One slow or failing target MUST NOT delay the others. The
emit operation as a whole returns when all target attempts have either
succeeded or exhausted their retries; it does **not** propagate a
failure to the caller (events are best-effort).

---

## 7. Failure handling

The event subsystem is **fire-and-forget** from the operation's point
of view:

- A failed emit MUST NOT change the operation's exit code.
- A failed emit MAY be logged (at warning level for transport errors,
  at error level for malformed-payload errors).
- Per-transport-failure exit codes (`EC_EVENT_TYPE_INVALID=37`,
  `EC_EVENT_PARAMS_INVALID=38`, `EC_EVENT_TRANSPORT_FAILED=39`,
  `EC_EVENT_JSON_FAILED=40`) are exposed only when the user explicitly
  invokes `kgsm events emit ...` from the CLI.

---

## 8. Test commands

The `events test` subcommand SHOULD send a synthetic payload over each
configured transport and report success/failure per transport. This is
the recommended way for users to verify configuration:

```
kgsm events test all
kgsm events test socket
kgsm events test webhook
```

The synthetic event MAY use a special `EventType` such as `_test`, or
any real event with placeholder data. The exact form is implementation
choice; consistent test output is the only requirement.

---

## 9. Status command

`kgsm events status` MUST print a single block summarising:

- Master switch state.
- Per-transport: enabled / disabled, target list, dependency presence
  (`socat` / `wget` / equivalents), and any obvious misconfiguration
  (e.g. `enable_webhook_events=true` but `webhook_urls` is empty).

This is a read-only diagnostic; no events are emitted.
