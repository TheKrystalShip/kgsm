# KGSM 3.0 Migration Guide

## Overview

KGSM 3.0 introduces major architectural changes to comply with XDG Base Directory specifications and enable distribution via package managers. This is a **breaking change** with no automatic migration from 2.x.

## What Changed

### Directory Structure

**KGSM 2.x (Old):**
```
~/kgsm/                          # Single directory for everything
├── kgsm.sh
├── installer.sh                 # Self-update (REMOVED)
├── config.ini                   # User config
├── core/
├── commands/
├── blueprints/
│   ├── native/
│   │   ├── default/
│   │   └── custom/              # User blueprints (mixed with code)
│   └── container/
├── overrides/                   # System overrides
├── instances/                   # Deployed servers
└── logs/
```

**KGSM 3.0 (New):**
```
/usr/share/kgsm/                 # System files (read-only)
├── kgsm.sh
├── core/
├── commands/
├── templates/
├── overrides/                   # System overrides
├── migrations/
├── blueprints/
│   ├── native/default/          # System blueprints
│   └── container/default/
└── config.default.ini

/usr/bin/kgsm                    # Symlink to kgsm.sh

~/.config/kgsm/                  # User configuration
└── config.ini

~/.local/share/kgsm/             # User data
├── instances/                   # Deployed servers
├── logs/
├── blueprints/
│   ├── native/                  # User blueprints
│   └── container/
└── overrides/                   # User overrides
```

### Key Changes

1. **No more self-update** - Package manager handles updates
2. **XDG compliance** - Code separated from user data
3. **User blueprints/overrides** - Now in `~/.local/share/kgsm/`
4. **Configuration** - Moved to `~/.config/kgsm/config.ini`
5. **Installation** - Via AUR/package manager instead of git clone

## Migration Steps

### 1. Backup Existing KGSM 2.x Installation

```bash
# Backup your entire KGSM directory
cd ~
tar -czf kgsm-2.x-backup-$(date +%Y%m%d).tar.gz kgsm/

# Verify backup
tar -tzf kgsm-2.x-backup-*.tar.gz | head
```

### 2. Extract Important Files

```bash
cd ~/kgsm

# Backup custom blueprints
mkdir -p ~/kgsm-migration/blueprints/native
mkdir -p ~/kgsm-migration/blueprints/container
cp -r blueprints/native/custom/* ~/kgsm-migration/blueprints/native/ 2>/dev/null || true
cp -r blueprints/container/custom/* ~/kgsm-migration/blueprints/container/ 2>/dev/null || true

# Backup custom overrides (if any)
mkdir -p ~/kgsm-migration/overrides
# User overrides would be custom files in overrides/ - identify and copy manually

# Backup instance data
mkdir -p ~/kgsm-migration/instances
cp -r instances/* ~/kgsm-migration/instances/

# Backup configuration
cp config.ini ~/kgsm-migration/config.ini

# Backup logs (optional)
mkdir -p ~/kgsm-migration/logs
cp -r logs/* ~/kgsm-migration/logs/ 2>/dev/null || true
```

### 3. Install KGSM 3.0

#### Option A: AUR (Arch Linux)

```bash
# Using yay or paru
yay -S kgsm
# or
paru -S kgsm

# Using makepkg
git clone https://aur.archlinux.org/kgsm.git
cd kgsm
makepkg -si
```

#### Option B: Manual Installation (Development/Testing)

```bash
git clone https://github.com/TheKrystalShip/KGSM.git
cd KGSM
git checkout v3.0.0

# For development, set KGSM_ROOT
export KGSM_ROOT=$(pwd)
./kgsm.sh --version
```

### 4. Verify Installation

```bash
# Check version
kgsm --version
# Should output: KGSM, version 3.0.0

# Check directory layout
kgsm --paths
```

### 5. Migrate Configuration

```bash
# KGSM 3.0 will create default config on first run
kgsm --help

# Review default config location
cat ~/.config/kgsm/config.ini

# Merge your old settings
diff ~/kgsm-migration/config.ini ~/.config/kgsm/config.ini

# Edit config with your preferred settings
nano ~/.config/kgsm/config.ini
# or use kgsm config commands:
kgsm config set enable_logging=true
kgsm config set enable_firewall_management=true
```

### 6. Restore Custom Blueprints

```bash
# Copy custom blueprints to new location
cp ~/kgsm-migration/blueprints/native/* ~/.local/share/kgsm/blueprints/native/
cp ~/kgsm-migration/blueprints/container/* ~/.local/share/kgsm/blueprints/container/

# Verify blueprints are discovered
kgsm blueprints list
```

### 7. Restore Custom Overrides (If Any)

```bash
# If you have custom override files
cp ~/kgsm-migration/overrides/custom-game.overrides.sh ~/.local/share/kgsm/overrides/

# User overrides now take precedence over system overrides
```

### 8. Recreate Instances

**IMPORTANT:** Instance directories must be recreated. You cannot simply copy them due to path changes.

```bash
# List your backed-up instances
ls ~/kgsm-migration/instances/

# For each instance, note the blueprint and install directory
# Example: vrising instance
cat ~/kgsm-migration/instances/vrising/vrising.ini

# Recreate the instance
kgsm install vrising --name vrising --install-dir /opt/servers/vrising

# The server files will be re-downloaded
# You can then restore your world saves/configs
```

### 9. Restore Server Saves/Configs

```bash
# After recreating instance, restore saves and configurations
# Example for vrising:

# Find the new instance directory
NEW_INSTANCE_DIR=$(kgsm directories instance vrising)

# Restore saves
cp -r ~/kgsm-migration/instances/vrising/saves/* "$NEW_INSTANCE_DIR/saves/"

# Restore server configs (carefully - paths may have changed)
# Review differences first
diff ~/kgsm-migration/instances/vrising/*.ini "$NEW_INSTANCE_DIR/"
diff ~/kgsm-migration/instances/vrising/*.json "$NEW_INSTANCE_DIR/"

# Copy config files selectively
cp ~/kgsm-migration/instances/vrising/ServerHostSettings.json "$NEW_INSTANCE_DIR/"
```

### 10. Verify Instances

```bash
# List instances
kgsm instances list

# Start instance
kgsm start vrising

# Check status
kgsm status vrising

# View logs
kgsm logs vrising --follow
```

### 11. Cleanup Old Installation

```bash
# Only after verifying everything works!

# Remove old KGSM directory
rm -rf ~/kgsm

# Keep backup for a while
# Delete later: rm ~/kgsm-2.x-backup-*.tar.gz
```

## Common Issues

### Config File Not Found

KGSM 3.0 creates config at `~/.config/kgsm/config.ini` on first run. If you get an error:

```bash
# Check if config exists
ls -la ~/.config/kgsm/config.ini

# If missing, run any command to trigger creation
kgsm --version

# Verify config was created
cat ~/.config/kgsm/config.ini
```

### Blueprints Not Found

Custom blueprints must be in `~/.local/share/kgsm/blueprints/`:

```bash
# List discovered blueprints
kgsm blueprints list

# Check blueprint directories
ls ~/.local/share/kgsm/blueprints/native/
ls /usr/share/kgsm/blueprints/native/default/
```

### Permissions Issues

User directories are automatically created with correct permissions:

```bash
# Verify user directories exist
ls -la ~/.config/kgsm/
ls -la ~/.local/share/kgsm/

# If missing, manually create
mkdir -p ~/.config/kgsm
mkdir -p ~/.local/share/kgsm/{instances,logs,blueprints/{native,container},overrides}
```

### System Files Not Found

If running a non-packaged installation:

```bash
# System install (package manager)
KGSM_ROOT=/usr/share/kgsm

# Development install (git clone)
export KGSM_ROOT=/path/to/KGSM/repo
./kgsm.sh --paths
```

## Feature Changes

### Self-Update Removed

```bash
# KGSM 2.x
./kgsm.sh --update

# KGSM 3.0 - Use package manager
yay -Syu kgsm           # AUR
sudo pacman -Syu kgsm   # After package is published
```

### Version Tracking

```bash
# KGSM 2.x - Version in .kgsm.version file
# KGSM 3.0 - Version hardcoded in kgsm.sh and tracked by package manager

kgsm --version
```

### New --paths Command

```bash
# Display XDG directory layout
kgsm --paths
```

## Getting Help

- Documentation: `/usr/share/doc/kgsm/` (package install) or `docs/` (git)
- Issues: https://github.com/TheKrystalShip/KGSM/issues
- Wiki: https://github.com/TheKrystalShip/KGSM/wiki

## Rollback to KGSM 2.x

If you need to rollback:

```bash
# Uninstall KGSM 3.0
yay -R kgsm  # or sudo pacman -R kgsm

# Restore from backup
cd ~
tar -xzf kgsm-2.x-backup-*.tar.gz

# Verify 2.x works
cd ~/kgsm
./kgsm.sh --version
```

Note: Instances created/modified in 3.0 will need to be manually adjusted for 2.x paths.
