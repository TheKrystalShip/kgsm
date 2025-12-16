# KGSM - Krystal Game Server Manager

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

> A lightweight, powerful tool for managing game servers on Linux with minimal hassle.

KGSM simplifies the process of setting up, managing, and maintaining game servers on Linux. Whether you're hosting a casual Minecraft server for friends or running a dedicated Valheim community, KGSM handles the technical details so you can focus on what matters—playing games and building communities.

## 🎮 Features

- **Simple Management**: Install, update, and manage multiple game servers through an intuitive interface
- **Flexible Deployment**: Support for both native and Docker container-based installations
- **Automation-Ready**: Full command-line support for scripting and automation
- **Low Overhead**: Minimalist design keeps resource usage low
- **Configuration Control**: Easy server customization with override files
- **Integration Options**: Works with systemd and UFW for robust server management

## 🎯 Supported Game Servers

KGSM supports a growing list of game servers through its blueprint system. To see all currently available game servers, run:

```sh
./kgsm.sh blueprints list
```

You can also check the `blueprints/default` directory to browse available blueprints directly.

New blueprints are added regularly, and contributions are enthusiastically welcomed! If you've successfully set up a game server that isn't currently supported, consider contributing your blueprint to the project.

## 💻 Compatibility

KGSM is designed to work on most GNU/Linux distributions as long as the required dependencies are installed. While comprehensive testing on all distributions isn't possible, users have reported successful operation on:

- Ubuntu/Debian-based systems
- Arch Linux and derivatives

## 📋 Prerequisites

### Required Dependencies

The following packages must be installed for KGSM to function properly:

```sh
# Core utilities
grep jq wget unzip tar sed coreutils findutils

# Game server management
steamcmd inotify-tools
```

### Optional Dependencies

These packages enable additional features when configured:

| Package     | Purpose             | Config Setting                    |
| ----------- | ------------------- | --------------------------------- |
| `ufw`       | Firewall management | `enable_firewall_management=true` |
| `socat`     | Event handling      | `enable_event_broadcasting=true`  |
| `miniupnpc` | Port forwarding     | `enable_port_forwarding=true`     |

> [!NOTE]
> If [SteamCMD][1] isn't available through your distribution's package manager, you'll need to [install it manually](https://developer.valvesoftware.com/wiki/SteamCMD#Linux).

### Recommended Setup

For optimal performance and reliability, consider integrating KGSM with:
- `systemd` for service management
- [UFW][2] for simplified firewall configuration

## 🚀 Getting Started

### Installation Options

Choose one of these methods to install KGSM:

#### 1. One-Line Installer (Recommended)
```sh
wget -qO - https://raw.githubusercontent.com/TheKrystalShip/KGSM/main/installer.sh | bash
```

#### 2. Manual Installation
```sh
# Clone the repository
git clone https://github.com/TheKrystalShip/KGSM.git
cd KGSM

# OR download and extract the latest release
wget https://github.com/TheKrystalShip/KGSM/releases/latest/download/kgsm.tar.gz
tar -xzf kgsm.tar.gz
cd kgsm
```

All KGSM files are contained within a single directory, keeping your system organized.

## 🎛️ Usage

### Basic Operation

Launch KGSM with:

```sh
./kgsm.sh
```

On first run, a `config.ini` file will be created with default settings. After configuration, an interactive menu guides you through available operations.

### Command-Line Options

For automation or quick actions, use command-line arguments:

```sh
# Get help information
./kgsm.sh --help

# Interactive help menu
./kgsm.sh --help --interactive

# See available game servers
./kgsm.sh blueprints list

# Create a new game server instance
./kgsm.sh install minecraft --name myserver
```

### Documentation

For detailed information on KGSM's capabilities, check the [project documentation][4].

## 🔄 Maintenance

### Updating KGSM

Keep KGSM up-to-date with:

```sh
./installer.sh --update
```

Your configuration will be automatically merged with new defaults, preserving your customizations while adding new features. See the [Configuration Management Guide](docs/configuration_management.md) for details.

### Configuration Management

KGSM includes powerful configuration management:

```sh
# View all configuration options
./kgsm.sh config list

# Set a configuration value
./kgsm.sh config set enable_logging=true

# Merge config with updated defaults
./kgsm.sh config merge

# Rollback to previous configuration
./kgsm.sh config rollback

# View configuration changes
./kgsm.sh config diff
```

Learn more in the [Configuration Management Guide](docs/configuration_management.md).

### Troubleshooting

If you encounter issues, use the repair option:

```sh
./installer.sh --update --force
```

This reinstalls KGSM while preserving your custom settings and server instances.

## 🤝 Contributing

Contributions to KGSM are always welcome! Here are some ways you can help:

### Game Server Blueprints

The most valuable contributions are new game server blueprints. If you've successfully set up a game server that isn't currently supported by KGSM, consider sharing your work:

1. Create a new blueprint file in `blueprints/custom/native/` or `blueprints/custom/container/` either from an existing blueprint or from the template file: `templates/blueprint.tp`
2. Test it thoroughly to ensure it works properly by running the full installation, lifecycle (start/stop/restart etc), uninstall
3. Submit a pull request to have it included in the main project

### Other Contributions

- Report bugs and suggest features through [GitHub Issues][5]
- Improve documentation
- Add support for more distribution-specific integration options
- Share your success stories and use cases

See [CONTRIBUTING.md](CONTRIBUTING.md) for more detailed contribution guidelines.

## 📄 License

KGSM is licensed under the [GNU General Public License v3.0](LICENSE).

[1]: https://developer.valvesoftware.com/wiki/SteamCMD
[2]: https://en.wikipedia.org/wiki/Uncomplicated_Firewall
[3]: https://github.com/TheKrystalShip/KGSM/releases
[4]: https://github.com/TheKrystalShip/KGSM/tree/main/docs
[5]: https://github.com/TheKrystalShip/KGSM/issues
