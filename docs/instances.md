# Instances 101

This document explains what instances are in KGSM, how they work, and provides comprehensive instructions for creating and managing them effectively.

## What is an instance?

An instance is a complete, functional installation of a game server created from a blueprint using KGSM. Think of it as the actual "server" that players will connect to. Each instance:

- Has its own files, configuration, and world data
- Can be started, stopped, updated, and managed independently
- Exists in its own installation directory
- Is tracked and managed by KGSM

You can create multiple instances from a single blueprint (for example, several different Minecraft servers with different mods, worlds or purposes), each with its own unique configuration, world data, and player communities.

## Where are instances stored?

Each instance consists of two main components:

1. **Game Server Files**: Located in the installation directory you specified during instance creation. This contains the actual game server executables, configuration files, world data, etc.

2. **Instance Reference**: Stored in the `instances` directory within your KGSM installation. This is a symbolic link to your game server installation directory, allowing KGSM to track and access your instances. The symlink structure is organized by blueprint type for easy navigation.

### Listing instances

To list all your game server instances, run:

```sh
# List all instances
kgsm.sh instances

# List instances with detailed information
kgsm.sh instances --detailed

# List only instances of a specific game
kgsm.sh instances minecraft

# Get JSON output for scripting
kgsm.sh instances --json
```

For example, the output might look like this:

```
minecraft-survival
valheim-community
terraria-hardmode
```

## How to create an instance

Creating an instance involves using a blueprint to set up a new game server. You can do this in several ways:

```sh
# Basic usage
kgsm.sh install <blueprint> --name <instance-name> --install-dir <directory>

# Example
kgsm.sh install minecraft --name survival-server --install-dir /opt/servers

# Interactive mode
kgsm.sh   # Then select "Install" from the menu
```

During the creation process, KGSM:

1. Sets up the game server files in the specified installation directory
2. Creates a **symbolic link** in the `instances` directory that points to your installation, allowing KGSM to track the instance
3. Creates the necessary directory structure for logs, backups, saves, etc.
4. Downloads and installs the game server files

> [!NOTE]
> The symbolic link allows KGSM to access all instance files (configuration, logs, saves, etc.) while keeping your game server completely standalone and functional without KGSM.

For detailed step-by-step instructions on instance creation, see [Creating a New Game Server Instance](create_new_game_server_instance.md).

## Managing instances

Once you've created instances, you'll need to manage them throughout their lifecycle. KGSM provides comprehensive tools for this purpose.

For detailed instructions on day-to-day management of game servers, including:

- Starting and stopping instances
- Checking server status
- Viewing logs
- Using systemd integration
- Sending console commands
- Managing backups
- Updating instances

Please refer to the [Managing Game Servers](managing_game_servers.md) document.

## Best practices for instance management

- **Meaningful names:** Use descriptive names for your instances (e.g., `minecraft-survival`, `valheim-pvp`) to easily identify them.

- **Regular backups:** Use the `create-backup` command before making significant changes or regularly via cron jobs.

- **Systemd integration:** For servers that need to be always online, add systemd integration for automatic startup on system boot.

- **Avoid manual edits:** Don't manually modify the instance configuration files unless you know exactly what you're doing.

## Removing an instance

To completely remove an instance, use the uninstall command:

```sh
kgsm.sh uninstall <instance-name>
```

This ensures that:
1. All game server files are properly removed
2. The instance configuration is cleaned up
3. Any system integrations (systemd, ufw) are properly disabled

> [!WARNING]
> Uninstalling an instance permanently removes all game data, including world saves. Create a manual backup first if you want to preserve your data!

---

By using these commands, you can efficiently manage your game servers through their entire lifecycle, from creation to operation to eventual removal.

For advanced integrations, KGSM provides an [Event System](events.md) that broadcasts lifecycle events (like server starts, stops, backups, etc.) through Unix Domain Sockets.


