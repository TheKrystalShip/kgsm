# 📡 KGSM Event System

KGSM features a robust event broadcasting system that notifies external applications of game server lifecycle events in real-time. The system supports two independent transport mechanisms—**Unix Domain Sockets** and **HTTP Webhooks**—which can be enabled simultaneously. External applications (like [kgsm-bot](https://github.com/TheKrystalShip/kgsm-bot)) can consume these events to build monitoring dashboards, automated responses, or custom integrations without modifying KGSM's core.

## 🔌 How It Works

When a KGSM operation completes (starting a server, creating a backup, installing an update, etc.), `core/events.sh` maps the operation's result code to a specific event type and calls `events.sh emit`. The emit command builds a JSON payload and dispatches it in parallel to every enabled transport.

### Transports at a Glance

| Transport | Protocol | Dependency | Use Case |
|-----------|----------|------------|----------|
| Unix Domain Socket | Local IPC | `socat` | Same-host daemons and bots |
| HTTP Webhook | HTTP POST | `wget` | Remote services, cloud integrations |

Both transports are independent. Enabling one does not affect the other.

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
| `instance_update_finished` | Server update completed | `InstanceName` |
| `instance_version_updated` | Server version changed | `InstanceName`, `OldVersion`, `NewVersion` |
| `instance_updated` | Server fully updated | `InstanceName` |

### 🚀 Lifecycle Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `instance_started` | Server process started | `InstanceName` |
| `instance_stopped` | Server process stopped | `InstanceName` |
| `instance_ready` | Server is accepting connections | `InstanceName` |
| `instance_backup_created` | Backup created | `InstanceName`, `Source`, `Version` |
| `instance_backup_restored` | Backup restored | `InstanceName`, `Source`, `Version` |

### 🗑️ Removal Events

| Event Name | Description | Data Fields |
|------------|-------------|-------------|
| `instance_uninstall_started` | Uninstallation process initiated | `InstanceName` |
| `instance_files_removed` | Server files removed | `InstanceName` |
| `instance_directories_removed` | Server directories removed | `InstanceName` |
| `instance_removed` | Instance record removed | `InstanceName` |
| `instance_uninstall_finished` | Uninstallation process completed | `InstanceName` |
| `instance_uninstalled` | Server fully uninstalled | `InstanceName` |

## 🔄 Event Payload Structure

Every event is a JSON object with the following top-level fields:

```json
{
    "EventType": "<event_name>",
    "Data": {
        "InstanceName": "<instance_name>",
        ...event-specific fields
    },
    "Timestamp": "2024-01-15T12:34:56Z",
    "Hostname": "my-server",
    "KGSMVersion": "1.2.3"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `EventType` | string | Underscore-separated event type name |
| `Data` | object | Event-specific payload (always contains `InstanceName`) |
| `Timestamp` | string | ISO 8601 UTC timestamp |
| `Hostname` | string | System hostname where the event originated |
| `KGSMVersion` | string | Running KGSM version |

### Example: Instance Started

```json
{
    "EventType": "instance_started",
    "Data": {
        "InstanceName": "minecraft_survival"
    },
    "Timestamp": "2024-01-15T12:34:56Z",
    "Hostname": "my-server",
    "KGSMVersion": "1.2.3"
}
```

## 🖥️ CLI Reference

The event system is managed via `events.sh` (or through `kgsm.sh events`).

### Top-level commands

```
events.sh <command> [arguments] [options]

Commands:
  status                      Show comprehensive event system status
  test <transport>            Test event transports (all, socket, webhook)
  socket <command>            Manage Unix Domain Socket transport
  webhook <command>           Manage HTTP webhook transport
  emit <event-type> [params]  Emit a specific event with parameters
  help [command]              Show help information

Options:
  -h, --help                  Display this help information
  --debug                     Enable debug output
```

### `events.sh socket` — Unix Domain Socket transport

```
events.sh socket <command>

Commands:
  enable      Enable Unix Domain Socket event transport
  disable     Disable Unix Domain Socket event transport
  test        Test socket functionality
  status      Show socket transport status
```

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
| `instance-files-removed` | `<instance>` |
| `instance-directories-removed` | `<instance>` |
| `instance-uninstall-started` | `<instance>` |
| `instance-uninstall-finished` | `<instance>` |
| `instance-uninstalled` | `<instance>` |

**Examples:**

```bash
events.sh emit instance-created myserver factorio
events.sh emit instance-started myserver
events.sh emit instance-version-updated myserver 1.0.0 1.1.0
events.sh emit instance-backup-created myserver auto 1.2.3
events.sh emit instance-stopped myserver
```

## ⚙️ Configuration

All event settings live in the `[events]` section of `config.ini`.

### Master Switch

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enable_event_broadcasting` | bool | `false` | Master switch — must be `true` for any events to be emitted |

### Unix Domain Socket Transport

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enable_socket_events` | bool | `false` | Enable Unix Domain Socket delivery |
| `event_socket_filenames` | string | `kgsm.sock` | Comma-separated list of socket filenames created under `$KGSM_ROOT` |

Multiple socket files are useful when multiple applications (e.g., a bot and a monitoring daemon) each own their own socket:

```ini
event_socket_filenames=kgsm.sock,monitoring.sock
```

### HTTP Webhook Transport

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enable_webhook_events` | bool | `false` | Enable HTTP webhook delivery |
| `webhook_urls` | string | _(empty)_ | Comma-separated list of HTTP/HTTPS endpoint URLs |
| `webhook_timeout_seconds` | int | `10` | Per-request timeout in seconds (1–300) |
| `webhook_retry_count` | int | `2` | Retry attempts on failure with exponential backoff (0–5) |
| `webhook_secret` | string | _(empty)_ | Optional HMAC-SHA256 signing secret. When set, requests include an `X-KGSM-Signature: sha256=<sig>` header |

### Quick-start examples

**Enable socket transport:**

```bash
events.sh socket enable
```

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

## 🔌 Socket Transport — Integration Guide

The socket transport uses `socat` to connect to a pre-existing Unix Domain Socket and write the JSON payload. **Your application creates and owns the socket**; KGSM connects to it as a client.

### Listening with socat

```bash
socat UNIX-LISTEN:$KGSM_ROOT/kgsm.sock,fork -
```

### Sample Client (Python)

```python
import socket
import json
import os

SOCKET_PATH = "/path/to/kgsm.sock"

def listen_for_events():
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(SOCKET_PATH)
    sock.listen(1)

    print(f"Listening on {SOCKET_PATH}")

    while True:
        connection, _ = sock.accept()
        try:
            data = connection.recv(4096)
            if data:
                event = json.loads(data.decode("utf-8"))
                process_event(event)
        finally:
            connection.close()

def process_event(event):
    event_type = event["EventType"]
    instance_name = event["Data"]["InstanceName"]

    if event_type == "instance_started":
        print(f"Server {instance_name} has started!")
    elif event_type == "instance_stopped":
        print(f"Server {instance_name} has stopped!")
```

**Reliability tips:**
- Recreate and re-bind the socket if it is deleted while your application is running.
- Filter for only the event types your application cares about.
- Always validate the JSON structure before accessing fields.

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
events.sh test socket
events.sh test webhook
```

**Common issues:**

| Symptom | Check |
|---------|-------|
| No events received | Verify `enable_event_broadcasting=true` in `config.ini` |
| Socket events missing | Confirm `enable_socket_events=true` and `socat` is installed |
| Socket file not found | Your listener application must create the socket file first |
| Webhook events missing | Confirm `enable_webhook_events=true`, `webhook_urls` is set, and `wget` is installed |
| Webhook authentication errors | Confirm `webhook_secret` matches on both sides |

## 💡 Best Practices

1. **Reconnection logic** — Socket client applications should recreate the socket and re-listen if the file is removed.
2. **Selective handling** — Process only the event types relevant to your integration.
3. **Payload validation** — Always validate the JSON structure before accessing fields.
4. **Atomic handlers** — Avoid creating complex dependencies between event handlers.
5. **Logging** — Record received events to aid troubleshooting.
6. **Multiple sockets** — Use `event_socket_filenames` with a comma-separated list when multiple consumers need isolated sockets.

---

By leveraging KGSM's event system, you can build custom notifications, automated workflows, monitoring systems, and more—without modifying the core KGSM codebase.

