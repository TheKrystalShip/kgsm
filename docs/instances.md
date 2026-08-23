# Instances 101

This document explains what instances are in KGSM, how they work, and provides comprehensive instructions for creating and managing them effectively.

## What is an instance?

An instance is a complete, functional installation of a game server created from a blueprint using KGSM. Think of it as the actual "server" that players will connect to. Each instance:

- Has its own files, configuration, and world data
- Can be started, stopped, updated, and managed independently
- Exists in its own directory inside a library
- Is tracked and managed by KGSM

You can create multiple instances from a single blueprint (for example, several different Minecraft servers with different mods, worlds or purposes), each with its own unique configuration, world data, and player communities.

## Where are instances stored?

Each instance consists of two main components:

1. **Working Directory**: Located inside the library the instance was placed in, at `<library-root>/instances/<blueprint-name>/<instance-name>/`. This contains the game server executables, configuration, world data, and all runtime files. The library root is recorded in the instance config as `library_dir`; see [Libraries](libraries.md).

2. **Instance Reference**: A symbolic link stored inside the `instances/` directory of your KGSM installation, at `instances/<blueprint-name>/<instance-name>/`. This symlink points to the working directory, allowing KGSM to track and access your instances without requiring them to live inside the KGSM directory tree.

### Instance directory structure

Each working directory is laid out as follows:

```
<instance-name>/
├── <instance-name>.config.ini   # Instance configuration (variables, paths, settings)
├── <instance-name>.manage.sh    # Management script (start, stop, update, backup, …)
├── <instance-name>.log          # Live server log output
├── .<instance-name>.pid         # PID of the running server process
├── .<instance-name>.sock        # Named pipe for sending console commands
├── .<instance-name>.version     # Installed version record
├── install/                     # Game server binary and data files
├── backups/                     # Backup archives
├── saves/                       # Game save files and world data
├── temp/                        # Temporary files used during downloads and updates
└── logs/                        # Rotated historical log files
```

> [!NOTE]
> The symbolic link in `instances/` lets KGSM reach all instance files while your game server remains completely self-contained and functional without KGSM.

## Listing instances

Use `instances list` to see your game server instances:

```sh
# List all instances
kgsm.sh instances list

# List only instances created from a specific blueprint
kgsm.sh instances list factorio

# Show detailed configuration for each instance
kgsm.sh instances list --detailed

# Show runtime status for all instances
kgsm.sh instances list --status

# Get JSON output for scripting
kgsm.sh instances list --json

# Combine flags
kgsm.sh instances list factorio --detailed --json
```

Example plain output:

```
minecraft-survival
valheim-community
terraria-hardmode
```

### An instance whose library is offline

An instance placed in a library that is not currently mounted still appears in every listing. It is
not gone, it is unreadable, and the two are reported differently: `--detailed` and `--json` carry
`library_state=offline` and describe the instance with what can be measured without the disk — its
name, blueprint, working directory and library — while every value that lives in its config file is
absent rather than guessed at.

Lifecycle verbs against such an instance refuse up front, naming the library and where it is
expected, and nothing removes the host's record of it. Mounting the library restores everything with
no commands at all. Full behaviour: [Libraries](libraries.md).

## How to create an instance

Creating an instance registers the instance configuration with KGSM and sets up the directory structure. The game server files themselves are downloaded during the separate `install` step.

```sh
# Full install (create + download + deploy) via the top-level command
kgsm.sh install <blueprint> [--library <name>]

# Provide a custom instance name (auto-generated if omitted)
kgsm.sh install minecraft --library ssd --name survival-server

# Create only the instance configuration (no download)
kgsm.sh instances create <blueprint> [--library <name>]
kgsm.sh instances create factorio --library ssd --name factorio-01

# Interactive wizard
kgsm.sh   # Then select "Install" from the menu
```

During a full `kgsm.sh install`, KGSM:

1. Validates the blueprint and the target directory
2. Generates a unique instance name if one is not supplied
3. Creates the working directory structure (`install/`, `backups/`, `saves/`, `temp/`, `logs/`)
4. Writes the instance configuration file (`<instance-name>.config.ini`)
5. Generates the instance management script (`<instance-name>.manage.sh`)
6. Creates the symbolic link in `instances/`
7. Downloads and deploys the game server files
8. Records the installed version

For detailed step-by-step instructions on instance creation, see [Creating a New Game Server Instance](create_new_game_server_instance.md).

## Inspecting instances

### View instance configuration

```sh
# Display the raw configuration file
kgsm.sh instances info <instance>

# Output as JSON for scripting
kgsm.sh instances info factorio-01 --json
```

### Check instance status

```sh
# Show full runtime status (process state, version, resource usage, recent logs)
kgsm.sh instances status <instance>

# Skip version checks for faster response (useful in monitoring loops)
kgsm.sh instances status factorio-01 --fast

# Output as JSON
kgsm.sh instances status factorio-01 --json
kgsm.sh instances status factorio-01 --json --fast
```

### Locate the instance configuration file

```sh
# Print the absolute path to the instance config file
kgsm.sh instances find factorio-01
```

### Generate a unique instance name

```sh
# Preview the name KGSM would auto-generate for a blueprint
kgsm.sh instances generate-id factorio

# Validate a custom name and echo it back if it is available
kgsm.sh instances generate-id factorio --name my-factory
```

## Sending commands to a running instance

```sh
# Trigger an in-game save
kgsm.sh instances save <instance>

# Send an arbitrary console command
kgsm.sh instances input <instance> "<command>"

# Examples
kgsm.sh instances save factorio-01
kgsm.sh instances input factorio-01 "/say Hello players!"
```

These commands write to the instance's named pipe (`.sock` file) so they reach the server's standard input in real time.

## Moving an instance between libraries

```sh
kgsm.sh instances move <instance-name> --library <library-name> [--skip-space-check]
```

Moves an instance's files into another library — the verb that makes emptying a disk before
removing it a single command per instance, and the one `kgsm libraries remove --drain` runs for
every resident of a library at once.

Two things are required before anything happens: the instance must be **stopped**, and both its
current library and the target must be **reachable**. A running server writes to the files the
move copies, so a copy taken under it would be of a world nobody saved; the move refuses rather
than stopping the server, because there are players on the other end of that decision.

The sequence:

1. **A backup** is taken, before a single file is copied. It lands in the shared backups root like
   every other backup, outside the instance, so it survives whichever way the move goes.
2. **The target is gated on free space** — measured from what the instance currently occupies
   (`du`), not from what its blueprint says a fresh install needs, plus the same
   `install_free_space_margin_mb` an install uses. `--skip-space-check` moves anyway and still
   prints the shortfall.
3. **The tree is copied** to `<library-root>/instances/<blueprint>/<instance>`.
4. **Every path the instance holds is rewritten.** The keys are enumerated from the config rather
   than listed, because they all derive from the working directory — and the ones that deliberately
   live outside it (`backups_dir`, `blueprint_file`, `command_shortcut_file`) are left exactly as
   they were. `library_dir` is set to the new root.
5. **The management file is regenerated**, and for a container instance so is its
   `docker-compose.yml`: bind mounts bake the working directory in, and a mount pointing at the tree
   the move removed would never start.
6. **The registry entry is re-pointed** at the new working directory. This is the commit.
7. **The instance is started once and stopped again**, to confirm it runs from where it now lives.
   An instance that has never been started is not started here either — nothing about it says it
   ever ran, so a failure would say nothing about the move — and the move says so.
8. **The old tree is removed.**

A failure at any point up to step 6 leaves the original authoritative: the instance is still
registered where it was, its config is untouched, and re-running the move picks up from the partial
copy at the target. A failure at step 7 puts the registry back the same way. `instance_moved` is
emitted once the move is done, carrying the library it came from and the one it is in.

## Managing instances

Once you've created instances, you'll need to manage them throughout their lifecycle. KGSM provides comprehensive tools for this purpose.

For detailed instructions on day-to-day management of game servers, including:

- Starting and stopping instances
- Checking server status
- Viewing logs
- Configuring boot auto-start with `kgsm autostart`
- Sending console commands
- Managing backups
- Updating instances

Please refer to the [Managing Game Servers](managing_game_servers.md) document.

## Best practices for instance management

- **Meaningful names:** Use descriptive names for your instances (e.g., `minecraft-survival`, `valheim-pvp`) to easily identify them.

- **Regular backups:** Use the `--create-backup` option on the management script before making significant changes, or schedule it via cron.

- **Boot auto-start:** For servers that need to be always online, run `kgsm.sh autostart enable <instance>` so the kgsm-watchdog daemon brings the instance back up automatically after a reboot.

- **Avoid manual edits:** Don't manually modify `<instance-name>.config.ini` or `<instance-name>.manage.sh` unless you know exactly what you're doing. If the management script becomes broken, it can be regenerated.

- **Use `--fast` for monitoring:** When polling status frequently (dashboards, scripts), pass `--fast` to skip remote version checks and reduce latency.

## Removing an instance

### Full uninstall (removes all game data)

```sh
kgsm.sh uninstall <instance-name>
```

This removes the working directory, all game files, saves, backups, the instance configuration, the management script, the symlink in `instances/`, and any system integrations (firewall rules).

> [!WARNING]
> Uninstalling an instance permanently removes all game data, including world saves. Create a backup first if you want to preserve your data.

### Remove only the instance record (keep game files)

```sh
kgsm.sh instances remove <instance-name>
```

This removes only the symbolic link and the instance configuration file from KGSM's tracking. The game server files in the working directory are left intact. This is useful when you want to deregister an instance without deleting the underlying server data.

Both commands refuse when the instance's library is offline: there are no files to uninstall while the disk is away, and the symlink they would remove is the host's last record of the instance. `--force` on either one deregisters the instance without touching a file, which is how an instance that left with its disk is forgotten deliberately.

---

By using these commands, you can efficiently manage your game servers through their entire lifecycle, from creation to operation to eventual removal.

For advanced integrations, KGSM provides an [Event System](events.md) that broadcasts lifecycle events (like server starts, stops, backups, etc.) through Unix Domain Sockets.


