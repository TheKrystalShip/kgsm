# 📡 KGSM Event System

KGSM records every game-server lifecycle event in an append-only **journal** on disk. External applications (like [kgsm-bot](https://github.com/TheKrystalShip/kgsm-bot)) tail that journal to build monitoring dashboards, automated responses, or custom integrations without modifying KGSM's core.

## 🔌 How It Works

When a KGSM operation completes (starting a server, creating a backup, installing an update, etc.), `core/events.sh` maps the operation's result code to a specific event type and emits it in-process: the payload is built and appended to the journal without leaving the running KGSM process.

**KGSM appends; it does not deliver.** The engine holds no list of consumers and no delivery configuration. Each consumer tails the journal at its own pace, holding its own cursor, so adding or removing a consumer needs no change to KGSM.

### The journal

| Property | Value |
|----------|-------|
| Location | `event_journal_dir` (default `/var/lib/kgsm/events`) |
| Format | Newline-delimited JSON — one event per line |
| Segments | `YYYY-MM-DD.ndjson`, sorting lexically in chronological order |
| Retention | `event_journal_retention_days` (default 90), pruned by `events journal prune` |

One event per line is the contract every consumer's cursor depends on, so payloads are always written compact and never span lines.

**Emission is unconditional.** There is deliberately no switch that disables it: the journal is KGSM's audit record, and an audit trail that can be silently switched off is worse than none at all.

**The journal is the record, and it answers for itself.** Reading history is a query over these files, not a lookup in something built from them — from C#, `kgsm-lib`'s `IEventJournalHistory` does it in-process. That is deliberate: a derived copy is a thing that can disagree with the record, fall behind it, or need rebuilding, and a consumer holding one makes every other consumer depend on that consumer being installed.

A consumer *may* still keep its own store — for its own rows, or as a cache. Two rules then apply. Its retention must never exceed `event_journal_retention_days`, or rebuilding it returns less than it already held. And it must key events idempotently (delivery is at-least-once, below), so replaying a segment corrects it instead of duplicating it.

### The optional transport

One additional transport can be switched on. It is **additive** — it delivers a copy and is not load-bearing:

| Transport | Protocol | Dependency | Use Case |
|-----------|----------|------------|----------|
| HTTP Webhook | HTTP POST | `wget` | Remote services, cloud integrations |

A local consumer needs none of this: it tails the journal directly.

### ⚠️ Important Note on Event Emission

Events are **only** emitted when operations are performed through `kgsm.sh` or through one of the modules in the `commands/` directory. Invoking an instance management script directly (e.g., `factorio.manage.sh`) bypasses the event system. Always use `kgsm.sh` when event broadcasting is required.

## 📝 Available Events

Event types use **underscore-separated** names in JSON payloads and **dash-separated** names on the CLI (e.g., `instance_started` in JSON, `instance-started` on the command line).

### 🛠️ Installation Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `instance_installation_started` | Installation process initiated | `InstanceName`, `Blueprint` |
| `instance_created` | Instance record and files created | `InstanceName`, `Blueprint` |
| `instance_directories_created` | Directory structure created | `InstanceName` |
| `instance_files_created` | Configuration files generated | `InstanceName` |
| `instance_download_started` | Download of server files initiated | `InstanceName` |
| `instance_download_finished` | Download of server files completed | `InstanceName` |
| `instance_downloaded` | All required files downloaded | `InstanceName` |
| `instance_deploy_started` | Deployment of server files initiated | `InstanceName` |
| `instance_deploy_finished` | Deployment of server files completed | `InstanceName` |
| `instance_deployed` | Server files fully deployed | `InstanceName` |
| `instance_installation_finished` | Installation process completed | `InstanceName`, `Blueprint` |
| `instance_installed` | Server fully installed and ready | `InstanceName`, `Blueprint` |

### 🔄 Update Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `instance_update_started` | Server update initiated | `InstanceName` |
| `instance_update_finished` | The update run ended, whatever its outcome | `InstanceName` |
| `instance_update_failed` | An update run ended without the version moving, for a reason — a refusal, a failed download or deploy. What tells that outcome apart from finding nothing to do | `InstanceName` |
| `instance_version_updated` | An installed server moved from one build to another | `InstanceName`, `OldVersion`, `NewVersion` |
| `instance_updated` | Server fully updated | `InstanceName` |
| `instance_update_available` | A newer build exists upstream and this server is not on it | `InstanceName`, `CurrentVersion`, `LatestVersion` |

`instance_version_updated` reports a move between two builds, so it needs a
build to move from: an update that finds the instance already current emits
nothing, and an install emits nothing either — the version a fresh instance
lands on is part of the instance the installation events announce. `OldVersion`
is therefore always a real previous version.

### 🚀 Lifecycle Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `instance_started` | Server process started | `InstanceName` |
| `instance_stop_started` | Shutdown initiated — the supervisor has asked the game to stop and is waiting for it to drain | `InstanceName` |
| `instance_stop_finished` | The shutdown run ended, whatever its outcome | `InstanceName` |
| `instance_stopped` | Server process stopped | `InstanceName` |
| `instance_restart_started` | Restart initiated — the instance is going down and coming back | `InstanceName` |
| `instance_restart_stopped` | The restart's old run is down — the process no longer exists, the new one has not been spawned yet | `InstanceName` |
| `instance_restart_finished` | The restart run ended, whatever its outcome | `InstanceName` |
| `instance_restarted` | Server restarted and is back up | `InstanceName` |
| `instance_ready` | Server is accepting connections | `InstanceName` |
| `instance_backup_started` | A backup run has begun — archiving is under way | `InstanceName` |
| `instance_backup_finished` | The backup run ended, whatever its outcome | `InstanceName` |
| `instance_restore_started` | A restore run has begun — safety archive, verification, then the data is replaced | `InstanceName` |
| `instance_restore_finished` | The restore run ended, whatever its outcome | `InstanceName` |
| `instance_backup_created` | Backup created | `InstanceName`, `Source`, `Version` |
| `instance_backup_restored` | Backup restored | `InstanceName`, `Source`, `Version` |
| `instance_backup_deleted` | One named backup removed | `InstanceName`, `Source` |
| `instance_backups_pruned` | Retention swept old backups | `InstanceName`, `Deleted`, `Kept` |

`Source` is the backup id on all three of the single-backup events. A delete
names one backup; a prune reports the whole sweep, so it carries counts instead:
`Deleted` is how many were actually removed and `Kept` the retention window it
ran with. Both are JSON numbers. A prune that removed nothing emits nothing.

### 🗑️ Removal Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `instance_uninstall_started` | Uninstallation process initiated | `InstanceName` |
| `instance_files_removed` | Server files removed | `InstanceName` |
| `instance_directories_removed` | Server directories removed | `InstanceName` |
| `instance_removed` | Instance record removed | `InstanceName` |
| `instance_uninstall_finished` | Uninstallation process completed | `InstanceName` |
| `instance_uninstalled` | Server fully uninstalled | `InstanceName` |

### 👤 Player Moderation Events

Emitted when an operator removes a player from a running server, blocks them, or lifts that block, and only once the command has been delivered.

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `instance_player_kicked` | A player was disconnected | `InstanceName`, `Target`, `Command` |
| `instance_player_banned` | A player was disconnected and blocked | `InstanceName`, `Target`, `Command` |
| `instance_player_unbanned` | A block was lifted | `InstanceName`, `Target`, `Command` |

| Field | Type | Meaning |
|-------|------|---------|
| `Target` | string | The player identity the operator supplied — whichever kind the blueprint's template declared (`{ip}`, `{name}` or `{id}`). Carried verbatim; KGSM does not classify it, since the blueprint is where that meaning is declared |
| `Command` | string | The resolved console command that was delivered, so the trail records the literal effect beside its subject |

These are their own event types rather than a console-input record because the subject is a **player**, not a command: a consumer asking "who was banned on this server" filters on the type instead of pattern-matching command text — text a hand-typed `instances input` could produce with no moderation intent behind it.

### 📘 Blueprint Events

These are the only events whose subject is **not an instance**. They fire when a blueprint file in the catalog is written or deleted, so that no consumer serves a stale blueprint and the change lands in event history.

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `blueprint_created` | A blueprint file appeared where none existed | `BlueprintName`, `Tier`, `OverridesSystem`, `Runtime` |
| `blueprint_updated` | An existing blueprint file was overwritten | `BlueprintName`, `Tier`, `OverridesSystem`, `Runtime` |
| `blueprint_removed` | A blueprint file was deleted | `BlueprintName`, `Tier`, `RevertedToSystem` |

| Field | Type | Meaning |
|-------|------|---------|
| `BlueprintName` | string | The blueprint's logical name — the subject, in place of `InstanceName` |
| `Tier` | string | Where the file lives. Always `user`: the shipped system directory is read-only |
| `OverridesSystem` | boolean\|null | `true` when the blueprint now shadows a shipped blueprint of the same name, `false` when it is entirely new |
| `RevertedToSystem` | boolean\|null | `true` when deleting the user file uncovers a shipped blueprint that takes over again, `false` when the blueprint leaves the host entirely |
| `Runtime` | string\|null | `native` or `container`, or `null` when the emitter could not determine it |

The file **contents are never carried**. A blueprint can hold credentials (SteamCMD arguments, passwords inside an embedded compose) and an event payload fans out to every enabled transport, so the record is "blueprint X changed" and nothing more. A consumer that needs the content reads the file.

## 🔄 Event Payload Structure

Every event is a JSON object with the following top-level fields:

```json
{
    "V": 1,
    "EventType": "<event_name>",
    "Data": {
        "InstanceName": "<instance_name>",
        ...event-specific fields
    },
    "Timestamp": "2026-01-15T12:34:56.789Z",
    "Actor": "discord:someone",
    "Origin": "ui",
    "Hostname": "my-server",
    "ProducerVersion": "1.2.3"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `V` | int | Envelope schema version. A reader treats an absent `V` as version 0 — the spelling used before the field existed, which retention keeps on disk for up to `event_journal_retention_days` |
| `EventType` | string | Underscore-separated event type name |
| `Data` | object | Event-specific payload. Instance events key it on `InstanceName`; the blueprint events key it on `BlueprintName` |
| `Timestamp` | string | ISO 8601 UTC timestamp, millisecond precision |
| `Actor` | string | Who triggered it, `provider:name`. From `$KGSM_EVENT_ACTOR`, else the OS user |
| `Origin` | string\|null | The surface that drove it. From `$KGSM_EVENT_ORIGIN`; `null` when none was declared — never fabricated |
| `Hostname` | string | System hostname where the event originated |
| `ProducerVersion` | string | The version of the component that emitted the event — here, KGSM's |

**Absent means null.** A field that carries nothing may be omitted rather than written as an
explicit null, and a reader treats the two identically.

**The timestamp carries milliseconds** because the journal is read alongside every other
producer's. A single appender gets its ordering free from the file it writes, but events merged
across journals at second granularity order arbitrarily inside each second — which is exactly
where causally adjacent events sit, a start and the port opening that follows it landing within one
second routinely.

**`ProducerVersion` names whoever emitted the event, not KGSM specifically.** Every component that
writes a journal stamps its own build there, so one field answers "which code produced this line"
whatever produced it. It is deliberately separate from `V`: one says how to read the line, the
other says which build wrote it, and a single field serving as both cannot answer either reliably.

Three further envelope fields — `OpId`, `RunId` and `During` — are **reserved** for correlating
events that belong to one operation. KGSM writes none of them, and a reader sees them absent.

### Example: Instance Started

```json
{
    "V": 1,
    "EventType": "instance_started",
    "Data": {
        "InstanceName": "minecraft_survival"
    },
    "Timestamp": "2026-01-15T12:34:56.789Z",
    "Actor": "discord:someone",
    "Origin": "ui",
    "Hostname": "my-server",
    "ProducerVersion": "1.2.3"
}
```

## 🖥️ CLI Reference

The event system is managed via `events.sh` (or through `kgsm.sh events`).

### Top-level commands

```
events.sh <command> [arguments] [options]

Commands:
  status                      Show comprehensive event system status
  journal <command>           Inspect and prune the event journal
  test <transport>            Test event transports (all, webhook)
  webhook <command>           Manage HTTP webhook transport
  emit <event-type> [params]  Emit a specific event with parameters
  help [command]              Show help information

Options:
  -h, --help                  Display this help information
  --debug                     Enable debug output
```

### `events.sh journal` — the event journal

```
events.sh journal <command>

Commands:
  status                      Show journal location, segments, event count and size
  prune                       Delete segments past the retention window
  verify                      Check every segment is well-formed NDJSON
```

`verify` matters more than it looks: a consumer's cursor is a byte offset into a
segment, so one malformed line desynchronizes every reader past that point.

`prune` is time-based only and never consults a consumer — KGSM holds no knowledge
of who reads the journal. A consumer absent longer than the retention window
detects the gap and cold-starts. `deploy/setup.sh` installs a user systemd timer
that runs `prune` daily.

### `events.sh webhook` — HTTP Webhook transport

```
events.sh webhook <command>

Commands:
  enable      Enable HTTP webhook event transport
  disable     Disable HTTP webhook event transport
  configure   Interactive webhook configuration wizard
  test        Test webhook functionality
  status      Show webhook transport status
```

### `events.sh emit` — Emit an event manually

Events are specified using **dash-separated** names on the CLI:

```
events.sh emit <event-type> [parameters...]
```

**Event types and their required parameters:**

| CLI Event Name | Parameters |
|----------------|------------|
| `instance-created` | `<instance>` `[blueprint]` |
| `instance-started` | `<instance>` |
| `instance-stopped` | `<instance>` |
| `instance-ready` | `<instance>` |
| `instance-removed` | `<instance>` |
| `instance-directories-created` | `<instance>` |
| `instance-files-created` | `<instance>` |
| `instance-download-started` | `<instance>` |
| `instance-download-finished` | `<instance>` |
| `instance-downloaded` | `<instance>` |
| `instance-deploy-started` | `<instance>` |
| `instance-deploy-finished` | `<instance>` |
| `instance-deployed` | `<instance>` |
| `instance-installation-started` | `<instance>` `[blueprint]` |
| `instance-installation-finished` | `<instance>` `[blueprint]` |
| `instance-installed` | `<instance>` `[blueprint]` |
| `instance-update-started` | `<instance>` |
| `instance-update-finished` | `<instance>` |
| `instance-updated` | `<instance>` |
| `instance-version-updated` | `<instance>` `<old_version>` `<new_version>` |
| `instance-backup-created` | `<instance>` `<source>` `<version>` |
| `instance-backup-restored` | `<instance>` `<source>` `<version>` |
| `instance-backup-deleted` | `<instance>` `<source>` |
| `instance-backups-pruned` | `<instance>` `<deleted>` `<kept>` |
| `instance-files-removed` | `<instance>` |
| `instance-directories-removed` | `<instance>` |
| `instance-uninstall-started` | `<instance>` |
| `instance-uninstall-finished` | `<instance>` |
| `instance-uninstalled` | `<instance>` |
| `blueprint-created` | `<blueprint>` `<tier>` `<overrides_system>` `[runtime]` |
| `blueprint-updated` | `<blueprint>` `<tier>` `<overrides_system>` `[runtime]` |
| `blueprint-removed` | `<blueprint>` `<tier>` `<reverted_to_system>` |

**Examples:**

```bash
events.sh emit instance-created myserver factorio
events.sh emit instance-started myserver
events.sh emit instance-version-updated myserver 1.0.0 1.1.0
events.sh emit instance-backup-created myserver auto 1.2.3
events.sh emit instance-stopped myserver
events.sh emit blueprint-updated terraria user true native
events.sh emit blueprint-removed terraria user true
```

## ⚙️ Configuration

All event settings live in the `[events]` section of `config.ini`.

### Journal

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `event_journal_dir` | string | `/var/lib/kgsm/events` | Where segments are appended. `~` expands to `$HOME` |
| `event_journal_retention_days` | int | `90` | Days of segments to keep. Must be **≥** the retention of any index built from the journal |

There is no key that disables emission.

### HTTP Webhook Transport

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enable_webhook_events` | bool | `false` | Enable HTTP webhook delivery |
| `webhook_urls` | string | _(empty)_ | Comma-separated list of HTTP/HTTPS endpoint URLs |
| `webhook_timeout_seconds` | int | `10` | Per-request timeout in seconds (1–300) |
| `webhook_retry_count` | int | `2` | Retry attempts on failure with exponential backoff (0–5) |
| `webhook_secret` | string | _(empty)_ | Optional HMAC-SHA256 signing secret. When set, requests include an `X-KGSM-Signature: sha256=<sig>` header |

### Quick-start examples

**Enable webhook transport (interactive wizard):**

```bash
events.sh webhook configure
events.sh webhook enable
```

**Verify everything is working:**

```bash
events.sh status
events.sh test all
```

## 📖 Journal — Integration Guide

A consumer tails the journal and remembers where it stopped. Nothing needs to be
registered with KGSM, and any number of readers can tail the same segments
concurrently — a file has no exclusive binding, so readers need no coordination.

### The cursor

A cursor is `(segment filename, byte offset)`. Persist it wherever the consumer
already keeps state; if that is a database, keep the cursor **inside** it, so the
position and whatever was built from it cannot end up in different places.

**Delivery is at-least-once.** The cursor advances only past events already
handled, so a crash costs a re-read and never a loss — which means a consumer
that persists what it reads **must be idempotent**. Key each row by something
derived from the event's own content and let a repeat insert be a no-op. Storing
the cursor in the same transaction as the row does not buy exactly-once; it only
narrows the window, and idempotence closes it completely.

### Reading

1. Open the segment named by the cursor and `seek()` to its offset.
2. Read whole lines; each is one complete JSON event. Update the offset only
   after the event is durably handled.
3. At EOF, if a lexically-greater segment exists, move to it — then re-check the
   previous segment once, to catch a write that landed just after midnight.

### Cold start and gaps

A consumer with **no** cursor picks a start position deliberately:

| Intent | Start at | Why |
|--------|----------|-----|
| Build an index of history | the oldest segment | it must replay to be complete |
| React to what happens next | the end of the newest segment | replaying would re-fire stale reactions |

If a saved cursor names a segment retention has already deleted, that is a real
**gap**. Report it — never resume silently, and never present the resulting
history as complete — then cold-start on the policy above.

### Sample tailer (Python)

```python
import json, os, time

JOURNAL = "/var/lib/kgsm/events"

def segments():
    return sorted(f for f in os.listdir(JOURNAL) if f.endswith(".ndjson"))

def tail(segment, offset, handle):
    path = os.path.join(JOURNAL, segment)
    with open(path) as fh:
        fh.seek(offset)
        for line in fh:
            if not line.endswith("\n"):
                break          # a partial trailing write; re-read it next pass
            handle(json.loads(line))
            offset = fh.tell()
    return offset

def run(segment=None, offset=0):
    while True:
        available = segments()
        if not available:
            time.sleep(1)
            continue
        if segment is None or segment not in available:
            segment, offset = available[-1], 0   # cold start at the tail
        offset = tail(segment, offset, print)
        later = [s for s in available if s > segment]
        if later:
            offset = tail(segment, offset, print)  # re-check before advancing
            segment, offset = later[0], 0
        else:
            time.sleep(1)
```

## 🌐 Webhook Transport — Integration Guide

When webhook delivery is enabled, KGSM sends an HTTP POST request with a `Content-Type: application/json` body to each configured URL. Requests are sent in parallel. Failed requests are retried with exponential backoff up to `webhook_retry_count` times.

### Request Headers

| Header | Value |
|--------|-------|
| `Content-Type` | `application/json` |
| `User-Agent` | `KGSM/<version>` |
| `X-KGSM-Timestamp` | Unix timestamp of the request |
| `X-KGSM-Retry-Count` | Current retry attempt (0 = first attempt) |
| `X-KGSM-Signature` | `sha256=<hmac>` _(only when `webhook_secret` is set)_ |

### Verifying Signatures (Python example)

```python
import hmac
import hashlib

def verify_signature(payload: bytes, secret: str, signature_header: str) -> bool:
    expected = "sha256=" + hmac.new(
        secret.encode(), payload, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature_header)
```

## 🔍 Debugging

**Check the overall system status:**

```bash
events.sh status
```

**Run transport-specific tests:**

```bash
events.sh test all
events.sh test webhook
```

**Common issues:**

| Symptom | Check |
|---------|-------|
| No events in the journal | Check `kgsm events journal status` — an unwritable `event_journal_dir` is reported there |
| A consumer sees no events | Confirm the journal is growing (`events.sh journal status`); the consumer's cursor is its own business |
| Webhook events missing | Confirm `enable_webhook_events=true`, `webhook_urls` is set, and `wget` is installed |
| Webhook authentication errors | Confirm `webhook_secret` matches on both sides |

## 💡 Best Practices

1. **Idempotent handling** — Delivery is at-least-once, so key anything you persist by the event's own content and let a repeat be a no-op.
2. **Selective handling** — Process only the event types relevant to your integration.
3. **Payload validation** — Always validate the JSON structure before accessing fields.
4. **Atomic handlers** — Avoid creating complex dependencies between event handlers.
5. **Logging** — Record received events to aid troubleshooting.
6. **No registration** — A file has no exclusive binding, so any number of consumers tail the same segments concurrently. Nothing needs to be added to KGSM's config to add a reader.

---

By leveraging KGSM's event system, you can build custom notifications, automated workflows, monitoring systems, and more—without modifying the core KGSM codebase.

