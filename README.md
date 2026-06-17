# KGSM - Krystal Game Server Manager

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

A lightweight, powerful tool for managing game servers on Linux with minimal hassle.

## What is KGSM?

KGSM simplifies setting up and managing game servers on Linux. Whether you're hosting a casual Minecraft server for friends or running a dedicated Valheim community, KGSM handles the technical details so you can focus on playing games.

**Key Features:**
- **Simple Management** - Install, update, and manage servers through an intuitive interface
- **Flexible Deployment** - Native Linux or Docker container support
- **Automation-Ready** - Full CLI for scripting
- **Low Overhead** - Minimalist design keeps resource usage low

## Installation

### Arch Linux (AUR)

```sh
yay -S kgsm
```

### From Source

```sh
git clone https://github.com/TheKrystalShip/KGSM.git
cd KGSM
./kgsm.sh --help
```

### Dependencies

**Required:**
```sh
grep jq wget unzip tar sed coreutils findutils steamcmd inotify-tools
```

**Optional:**
| Package     | Purpose             | Config Setting                    |
| ----------- | ------------------- | --------------------------------- |
| `ufw`   | Firewall management | `enable_firewall_management=true` |
| `socat` | Event handling      | `enable_event_broadcasting=true`  |

> **Note:** If SteamCMD isn't in your package manager, [install manually](https://developer.valvesoftware.com/wiki/SteamCMD#Linux).

## Directory Structure

KGSM follows [XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/latest/) conventions:

| Location                          | Purpose                                    |
| --------------------------------- | ------------------------------------------ |
| `~/.config/kgsm/config.ini`       | Global settings (logging, firewall, ports) |
| `~/.local/share/kgsm/instances/`  | Your deployed game servers live here       |
| `~/.local/share/kgsm/blueprints/` | Custom server blueprints you create        |
| `~/.local/share/kgsm/overrides/`  | Custom install/update logic per game       |
| `~/.local/share/kgsm/logs/`       | Operation logs (when logging enabled)      |

**Instance directory structure:**
```
instances/
└── my-minecraft-server/
    ├── server/          # Game server files
    ├── saves/           # World data and saves
    ├── backups/         # Automatic backups
    └── logs/            # Server-specific logs
```

## Usage

```sh
kgsm --help              # Show all commands
kgsm blueprints list     # List available game servers
kgsm install <game>      # Install a game server
kgsm start <instance>    # Start a server
kgsm stop <instance>     # Stop a server
```

### Example: Setting up a Minecraft server

```sh
# See what's available
kgsm blueprints list

# Install Minecraft with a custom name
kgsm install minecraft --name survival

# Start it
kgsm start survival

# Check status
kgsm status survival
```

### Configuration

```sh
kgsm config list         # Show current settings
kgsm config set key=val  # Change a setting
```

## Documentation

For detailed guides on configuration, blueprints, overrides, and more, see the [docs](docs/) directory.

---

## Contributing

We welcome contributions of all kinds:

- **New game server blueprints** - The most valuable contribution
- **Bug fixes and compatibility improvements** - KGSM is tested on limited distributions, so fixes that improve compatibility with other Linux systems are highly appreciated
- **New features** - Enhancements that benefit the community
- **Documentation improvements** - Clearer docs help everyone

### Adding a New Game Server

1. Create a blueprint in `~/.local/share/kgsm/blueprints/native/` using the template at `templates/blueprint.tp`
2. Test the full lifecycle: install, start, stop, restart, uninstall
3. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

[GNU General Public License v3.0](LICENSE)
