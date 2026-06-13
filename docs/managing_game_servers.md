# Managing Game Servers

This document explains the day-to-day operations of managing game server instances after they've been created. For information about what instances are and how they're created, see [Instances 101](instances.md).

> [!NOTE]
> Throughout this document, `<instance>` refers to the name of your game server instance. Run `./kgsm.sh instances list` to see all created instances.

---

## Lifecycle Management

KGSM provides dedicated commands for controlling the operational state of game server instances through the `lifecycle` module. The most common commands are available as top-level shortcuts directly on `kgsm.sh`.

### Starting a Server

#### Using KGSM (recommended)

```sh
./kgsm.sh start <instance>
```

When a server starts, KGSM automatically launches a readiness watcher (if configured) to monitor when the instance is ready for players.

> [!NOTE]
> `start` only runs the instance now. It does **not** enable the instance for boot auto-start — that is controlled separately by `kgsm autostart enable` (see [Automatic Start on Boot](#automatic-start-on-boot)).

#### Using the instance management script directly

Each instance ships with a self-contained management script in its installation directory:

```sh
./<instance>.manage.sh start            # Attach terminal to the server
./<instance>.manage.sh start --detached # Start as a background process
```

Run `./<instance>.manage.sh --help` to see all available options.

---

### Stopping a Server

#### Using KGSM

```sh
./kgsm.sh stop <instance>
```

> [!NOTE]
> `stop` only stops the instance now. It does **not** disable boot auto-start — if the instance is enabled via `kgsm autostart enable`, it will still come back after a reboot.

#### Using the instance management script directly

```sh
./<instance>.manage.sh stop
./<instance>.manage.sh stop --no-save      # Skip saving before shutdown
./<instance>.manage.sh stop --no-graceful  # Force-terminate the server process
```

---

### Restarting a Server

#### Using KGSM

```sh
./kgsm.sh restart <instance>
```

---

### Checking Instance Status

#### Using KGSM

```sh
./kgsm.sh status <instance>             # Comprehensive runtime status
./kgsm.sh status <instance> --json      # Machine-readable JSON output
./kgsm.sh status <instance> --fast      # Skip update checking for faster response
```

---

### Checking if an Instance is Running

`is-active` returns exit code `0` if the instance is running, or `1` if it is not. This is useful for scripting and health checks.

```sh
./kgsm.sh is-active <instance>
```

---

### Viewing Logs

```sh
./kgsm.sh logs <instance>                     # Show last 10 log lines (default)
./kgsm.sh logs <instance> --follow            # Follow logs in real-time
./kgsm.sh logs <instance> -f                  # Alias for --follow
./kgsm.sh logs <instance> --tail 50           # Show last 50 lines
./kgsm.sh logs <instance> --follow --tail 100 # Follow, starting with last 100 lines
```

Logs are read from the instance's own log file.

The instance management script exposes the same options directly:

```sh
./<instance>.manage.sh --logs
./<instance>.manage.sh --logs --follow
./<instance>.manage.sh --logs --tail 50
```

---

### Automatic Start on Boot

Boot auto-start is controlled with the `autostart` command, which works like
`systemctl enable`/`disable`. It is backed by the **kgsm-watchdog** daemon, which
persists each instance's desired state and brings enabled instances back up after a
reboot. The watchdog daemon must be running for these commands to work.

```sh
./kgsm.sh autostart enable <instance>    # Bring this instance up automatically on boot
./kgsm.sh autostart disable <instance>   # Don't bring it up on boot
./kgsm.sh autostart status <instance>    # Show whether the instance is enabled for boot
./kgsm.sh autostart list                 # List all instances enabled for boot
```

> [!IMPORTANT]
> `autostart` is **independent** of `start`/`stop`, exactly like `systemctl enable`
> is independent of `systemctl start`:
>
> - `enable` does **not** start the instance now; `disable` does **not** stop it.
>   They only change what comes back after a reboot.
> - An instance that is **started but not enabled** will **not** survive a reboot.
> - An instance that is **enabled but stopped** **will** be started on the next boot.

---

## Decommissioning Game Servers

To completely remove a game server instance:

```sh
./kgsm.sh uninstall <instance>
```

This will:

- Stop the instance if it is running.
- Remove all files and directories associated with the instance.
- Delete `ufw` integrations, if applicable.

---

## System Operations

The `system` module provides OS-level information and power management. These commands act on the **host machine**, not on individual game server instances.

### Power Management

> [!WARNING]
> Shutdown and restart commands require `sudo` privileges and affect the entire host system.

```sh
./kgsm.sh system shutdown         # Immediate system shutdown
./kgsm.sh system shutdown 10      # Shutdown in 10 minutes
./kgsm.sh system restart          # Immediate system restart
./kgsm.sh system restart 5        # Restart in 5 minutes
./kgsm.sh system cancel           # Cancel a scheduled shutdown or restart
```

### System Information

```sh
./kgsm.sh system uptime           # Show system uptime
./kgsm.sh system load             # Show CPU load averages
./kgsm.sh system memory           # Show memory usage
./kgsm.sh system disk             # Show disk usage
./kgsm.sh system reboot-required  # Check if a reboot is needed
./kgsm.sh system info             # Show all of the above at once
./kgsm.sh system info --json      # Machine-readable JSON output
```

---

## Network Management

The `network` module provides tools for inspecting and troubleshooting ports and connectivity on the host machine.

### Port Operations

```sh
./kgsm.sh network ports check 27015         # Check if TCP port 27015 is in use
./kgsm.sh network ports check 27015 udp     # Check UDP port 27015
./kgsm.sh network ports list-used           # List all ports currently in use
./kgsm.sh network ports conflicts           # Find port conflicts across KGSM instances
./kgsm.sh network ports kill 27015          # Force-stop the process using port 27015
```

### Connectivity Testing

```sh
./kgsm.sh network test-port 27015           # Test if TCP port 27015 is externally accessible
./kgsm.sh network test-port 27015 udp       # Test UDP port 27015
./kgsm.sh network test-all                  # Test all ports across all KGSM instances
```

### Network Information

```sh
./kgsm.sh network ip                        # Show external and local IP addresses
./kgsm.sh network dns                       # Show DNS server configuration
```

> [!NOTE]
> Port protocol defaults to `tcp` if not specified. Terminating a process using a port may require `sudo` privileges.

---

## Readiness Watchers

The `watcher` module monitors game server instances to detect when they are ready to accept players. It supports two detection strategies:

- **Log pattern matching** (primary): Watches the instance log file for a configured regex pattern (`startup_success_regex`).
- **Port monitoring** (fallback): Polls the instance's configured port(s) until they are active.

Strategy selection is automatic—log pattern matching takes precedence when both are configured.

> [!NOTE]
> Watchers are started automatically by `./kgsm.sh start <instance>` when `enable_watcher=true` is set in `config.ini`. The commands below are for manual control.

### Watcher Commands

```sh
./kgsm.sh watcher start <instance>           # Launch watcher with auto-selected strategy
./kgsm.sh watcher start <instance> --detach  # Run watcher as a background process
./kgsm.sh watcher test <instance>            # Test watcher configuration
./kgsm.sh watcher status <instance>          # Show watcher configuration for all strategies
```

### Component-Level Control

For direct control over individual strategies:

```sh
# Log pattern strategy
./kgsm.sh watcher logs watch <instance>            # Start log watcher
./kgsm.sh watcher logs watch <instance> --detach   # Run in background
./kgsm.sh watcher logs test <instance>             # Test log pattern configuration
./kgsm.sh watcher logs status <instance>           # Show log watcher status

# Port monitoring strategy
./kgsm.sh watcher ports watch <instance>           # Start port watcher
./kgsm.sh watcher ports watch <instance> --detach  # Run in background
./kgsm.sh watcher ports test <instance>            # Test port monitoring configuration
./kgsm.sh watcher ports status <instance>          # Show port watcher status
```

### Configuration

Watcher behaviour is controlled by the `[watchers]` section in `config.ini`:

| Key | Default | Description |
|-----|---------|-------------|
| `enable_watcher` | `false` | Auto-start a watcher when an instance is started |
| `watcher_global_timeout_seconds` | `600` | Maximum time (in seconds) to wait for a ready signal |
| `watcher_ports_check_interval_seconds` | `5` | How often (in seconds) to poll ports |

---

## Advanced Features

### Event System

KGSM emits events when important actions occur—server start, stop, backup creation, instance readiness, and more. These events can be consumed by external systems via webhooks or Unix sockets, enabling custom monitoring and automation workflows.

For details, see [KGSM Event System](events.md).
