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

An event type is a **dotted lowercase name** and that name is its only identity — the same spelling on the wire, on the CLI and in a filter. The dots are load-bearing: the hierarchy in the name is what a reader groups and picks an icon from, so `network.upnp.opened` places itself under `network` with nothing downstream holding a list.

### 🛠️ Installation Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `server.install.started` | Installation process initiated | `InstanceName`, `Blueprint` |
| `server.install.created` | Instance record and files created | `InstanceName`, `Blueprint` |
| `server.install.directories_created` | Directory structure created | `InstanceName` |
| `server.install.files_created` | Configuration files generated | `InstanceName` |
| `server.download.started` | Download of server files initiated | `InstanceName` |
| `server.download.finished` | Download of server files completed | `InstanceName` |
| `server.download.completed` | All required files downloaded | `InstanceName` |
| `server.deploy.started` | Deployment of server files initiated | `InstanceName` |
| `server.deploy.finished` | Deployment of server files completed | `InstanceName` |
| `server.deploy.completed` | Server files fully deployed | `InstanceName` |
| `server.install.finished` | Installation process completed | `InstanceName`, `Blueprint` |
| `server.installed` | Server fully installed and ready | `InstanceName`, `Blueprint`, `Library` |

`server.installed` is the one installation event that also says **where** the files landed:
`Library` is the name of the library the install was placed in. The placement is resolved before a
single directory is created, so it is always known, and on a host with several disks it is what an
audit row needs most.

### 📦 Placement Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `server.moved` | An instance's files now live in a different library | `InstanceName`, `FromLibrary`, `ToLibrary` |

Both library names are carried because a reader that learns only the destination cannot say which
disk just got its space back — and emptying a disk before it is unplugged is the whole reason
`kgsm instances move` and `kgsm libraries remove --drain` exist. An instance the registry places in
no library reports `unregistered`, which is a measurement rather than an absence.

### 🔄 Update Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `server.update.started` | Server update initiated | `InstanceName` |
| `server.update.finished` | The update run ended, whatever its outcome | `InstanceName` |
| `server.update.failed` | An update run ended without the version moving, for a reason — a refusal, a failed download or deploy. What tells that outcome apart from finding nothing to do | `InstanceName` |
| `server.updated` | An installed server moved from one build to another | `InstanceName`, `OldVersion`, `NewVersion` |
| `server.update.completed` | Server fully updated | `InstanceName` |
| `server.update.available` | A newer build exists upstream and this server is not on it | `InstanceName`, `CurrentVersion`, `LatestVersion` |

`server.updated` reports a move between two builds, so it needs a
build to move from: an update that finds the instance already current emits
nothing, and an install emits nothing either — the version a fresh instance
lands on is part of the instance the installation events announce. `OldVersion`
is therefore always a real previous version.

### 🚀 Lifecycle Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `server.started` | Server process started | `InstanceName` |
| `server.stop.started` | Shutdown initiated — the supervisor has asked the game to stop and is waiting for it to drain | `InstanceName` |
| `server.stop.finished` | The shutdown run ended, whatever its outcome | `InstanceName` |
| `server.stopped` | Server process stopped | `InstanceName` |
| `server.restart.started` | Restart initiated — the instance is going down and coming back | `InstanceName` |
| `server.restart.stopped` | The restart's old run is down — the process no longer exists, the new one has not been spawned yet | `InstanceName` |
| `server.restart.finished` | The restart run ended, whatever its outcome | `InstanceName` |
| `server.restarted` | Server restarted and is back up | `InstanceName` |
| `server.ready` | Server is accepting connections | `InstanceName` |
| `backup.started` | A backup run has begun — archiving is under way | `InstanceName` |
| `backup.finished` | The backup run ended, whatever its outcome | `InstanceName` |
| `backup.restore.started` | A restore run has begun — safety archive, verification, then the data is replaced | `InstanceName` |
| `backup.restore.finished` | The restore run ended, whatever its outcome | `InstanceName` |
| `backup.created` | Backup created | `InstanceName`, `Source`, `Version` |
| `backup.restored` | Backup restored | `InstanceName`, `Source`, `Version` |
| `backup.deleted` | One named backup removed | `InstanceName`, `Source` |
| `backup.pinned` | A backup put out of retention's reach | `InstanceName`, `Source` |
| `backup.unpinned` | A backup handed back to retention | `InstanceName`, `Source` |
| `backup.pruned` | Retention swept old backups | `InstanceName`, `Deleted`, `Kept`, `Pinned` |

`Source` is the backup id on every single-backup event. A delete, a pin and an
unpin each name one backup; a prune reports the whole sweep, so it carries counts
instead: `Deleted` is how many were actually removed, `Kept` the retention window
it ran with, and `Pinned` how many it skipped because they were pinned. All three
are JSON numbers. A prune that removed nothing emits nothing.

### 🗑️ Removal Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `server.uninstall.started` | Uninstallation process initiated | `InstanceName` |
| `server.uninstall.files_removed` | Server files removed | `InstanceName` |
| `server.uninstall.directories_removed` | Server directories removed | `InstanceName` |
| `server.uninstall.removed` | Instance record removed | `InstanceName` |
| `server.uninstall.finished` | Uninstallation process completed | `InstanceName` |
| `server.uninstalled` | Server fully uninstalled | `InstanceName` |

### 👤 Player Moderation Events

Emitted when an operator removes a player from a running server, blocks them, or lifts that block, and only once the command has been delivered.

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `player.kicked` | A player was disconnected | `InstanceName`, `Target`, `Command` |
| `player.banned` | A player was disconnected and blocked | `InstanceName`, `Target`, `Command` |
| `player.unbanned` | A block was lifted | `InstanceName`, `Target`, `Command` |

| Field | Type | Meaning |
|-------|------|---------|
| `Target` | string | The player identity the operator supplied — whichever kind the blueprint's template declared (`{ip}`, `{name}` or `{id}`). Carried verbatim; KGSM does not classify it, since the blueprint is where that meaning is declared |
| `Command` | string | The resolved console command that was delivered, so the trail records the literal effect beside its subject |

These are their own event types rather than a console-input record because the subject is a **player**, not a command: a consumer asking "who was banned on this server" filters on the type instead of pattern-matching command text — text a hand-typed `instances input` could produce with no moderation intent behind it.

### ⚙️ Configuration Events

Emitted by the command layer when an instance's `.config.ini` is written through `instances config-set` or `instances rename`.

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `config.changed` | A key in the instance config was set | `InstanceName`, `Key` |
| `server.renamed` | The instance's display name was changed | `InstanceName`, `OldDisplayName`, `NewDisplayName` |

`config.changed` carries the **key only, never the value**. Instance config holds secrets — RCON and admin passwords, tokens — and an event payload fans out to every enabled transport, so the record is "key X changed on instance Y" and nothing more.

A display-name change is the one exception, and it is not one: both labels are carried in full because a display name is the value in that file which exists to be shown. Withholding it would leave the event unable to say what it is about, and every surface reading it would have to go back to the engine for the label it was just told had changed. Both events fire on a display-name change — the generic record, and the specific one a surface re-renders off.

`InstanceName` is the **id**, which a rename does not touch. The id is what every consumer keys on; the label beside it is decoration.

### 📘 Blueprint Events

These are the only events whose subject is **not an instance**. They fire when a blueprint file in the catalog is written or deleted, so that no consumer serves a stale blueprint and the change lands in event history.

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `blueprint.created` | A blueprint file appeared where none existed | `BlueprintName`, `Tier`, `OverridesSystem`, `Runtime` |
| `blueprint.updated` | An existing blueprint file was overwritten | `BlueprintName`, `Tier`, `OverridesSystem`, `Runtime` |
| `blueprint.removed` | A blueprint file was deleted | `BlueprintName`, `Tier`, `RevertedToSystem` |

| Field | Type | Meaning |
|-------|------|---------|
| `BlueprintName` | string | The blueprint's logical name — the subject, in place of `InstanceName` |
| `Tier` | string | Where the file lives. Always `user`: the shipped system directory is read-only |
| `OverridesSystem` | boolean\|null | `true` when the blueprint now shadows a shipped blueprint of the same name, `false` when it is entirely new |
| `RevertedToSystem` | boolean\|null | `true` when deleting the user file uncovers a shipped blueprint that takes over again, `false` when the blueprint leaves the host entirely |
| `Runtime` | string\|null | `native` or `container`, or `null` when the emitter could not determine it |

The file **contents are never carried**. A blueprint can hold credentials (SteamCMD arguments, passwords inside an embedded compose) and an event payload fans out to every enabled transport, so the record is "blueprint X changed" and nothing more. A consumer that needs the content reads the file.

### 💽 Library Events

The other events whose subject is **not an instance**. A library is a named root that instances are placed in, and these fire when one is registered or deregistered — so a surface can keep its picture of where this host can place instances without polling the registry.

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `library.added` | A library was registered | `LibraryName`, `Path` |
| `library.removed` | A library was deregistered | `LibraryName`, `Path` |

| Field | Type | Meaning |
|-------|------|---------|
| `LibraryName` | string | The library's name — the subject, in place of `InstanceName` |
| `Path` | string | The canonical root that was registered |

The path rides along because the name alone is not enough to act on: a removal takes the name out of the registry, and a reader that only learns the name cannot say which disk left. No capacity or online figure is carried — both are measurements that are only true at the moment they are taken, and `kgsm libraries list` is where they are taken.

## 🔄 Event Payload Structure

Every event is a JSON object with the following top-level fields:

```json
{
    "V": 2,
    "EventType": "<event_type>",
    "Severity": "info",
    "Outcome": "neutral",
    "Summary": "started minecraft_survival",
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
| `EventType` | string | The dotted event type — the event's whole identity |
| `Severity` | string\|null | How much this matters: `info`, `warn` or `danger` |
| `Outcome` | string\|null | How it went: `success`, `failure` or `neutral` |
| `Summary` | string\|null | One line of prose, written when the event happened. `null` on a phase bracket, which no feed renders as a row |
| `Data` | object | Event-specific payload. Instance events key it on `InstanceName`; the blueprint events key it on `BlueprintName` |
| `Timestamp` | string | ISO 8601 UTC timestamp, millisecond precision |
| `Actor` | string\|null | Who triggered it, `provider:name`. From `$KGSM_EVENT_ACTOR`; `null` when none was supplied, and when the supplied value is not `provider:name` — never a borrowed OS username |
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

**Every event describes itself.** `Severity`, `Outcome` and `Summary` are the engine's own
judgement about what it just did, stamped at emit time, so a reader needs no table of its own. That
is what lets a surface render an event it has never heard of: nothing downstream is keyed on an
event's name, because a map keyed by identity has a missing arm for every event nobody has added to
it yet.

`Severity` is `info`, `warn` or `danger` — how much the event matters. `Outcome` is `success`,
`failure` or `neutral` — how it went. They are separate axes: a backup created and a config key set
are both routine and differ only in how they went, while an uninstall that succeeded is still the
loudest line on the feed.

**The summary is prose, and prose is content.** It is one line, written when the event happened,
naming things as they were called at the time — the instance id the emitter passed, never a label
looked up later, so a rename leaves every earlier line saying what the server was called then. A
phase bracket carries `null` rather than an empty string: absent means "nothing to say", and an
empty string is a third state no reader handles.

### Example: Instance Started

```json
{
    "V": 2,
    "EventType": "server.started",
    "Severity": "info",
    "Outcome": "neutral",
    "Summary": "started minecraft_survival",
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

An event is named by its dotted type:

```
events.sh emit <event-type> [parameters...]
```

**Event types and their required parameters:**

| Event Type | Parameters |
|----------------|------------|
| `server.install.created` | `<instance>` `[blueprint]` |
| `server.started` | `<instance>` |
| `server.stopped` | `<instance>` |
| `server.ready` | `<instance>` |
| `server.uninstall.removed` | `<instance>` |
| `server.install.directories_created` | `<instance>` |
| `server.install.files_created` | `<instance>` |
| `server.download.started` | `<instance>` |
| `server.download.finished` | `<instance>` |
| `server.download.completed` | `<instance>` |
| `server.deploy.started` | `<instance>` |
| `server.deploy.finished` | `<instance>` |
| `server.deploy.completed` | `<instance>` |
| `server.install.started` | `<instance>` `[blueprint]` |
| `server.install.finished` | `<instance>` `[blueprint]` |
| `server.installed` | `<instance>` `[blueprint]` |
| `server.update.started` | `<instance>` |
| `server.update.finished` | `<instance>` |
| `server.update.completed` | `<instance>` |
| `server.updated` | `<instance>` `<old_version>` `<new_version>` |
| `backup.created` | `<instance>` `<source>` `<version>` |
| `backup.restored` | `<instance>` `<source>` `<version>` |
| `backup.deleted` | `<instance>` `<source>` |
| `backup.pruned` | `<instance>` `<deleted>` `<kept>` |
| `server.uninstall.files_removed` | `<instance>` |
| `server.uninstall.directories_removed` | `<instance>` |
| `server.uninstall.started` | `<instance>` |
| `server.uninstall.finished` | `<instance>` |
| `server.uninstalled` | `<instance>` |
| `blueprint.created` | `<blueprint>` `<tier>` `<overrides_system>` `[runtime]` |
| `blueprint.updated` | `<blueprint>` `<tier>` `<overrides_system>` `[runtime]` |
| `blueprint.removed` | `<blueprint>` `<tier>` `<reverted_to_system>` |
| `library.added` | `<name>` `<path>` |
| `library.removed` | `<name>` `<path>` |

**Examples:**

```bash
events.sh emit server.install.created myserver factorio
events.sh emit server.started myserver
events.sh emit server.updated myserver 1.0.0 1.1.0
events.sh emit backup.created myserver auto 1.2.3
events.sh emit server.stopped myserver
events.sh emit blueprint.updated terraria user true native
events.sh emit blueprint.removed terraria user true
events.sh emit library.added ssd /mnt/ssd/kgsm
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

