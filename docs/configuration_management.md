# Configuration Management Guide

## Overview

KGSM uses a sophisticated configuration management system that automatically handles updates to default settings while preserving your customizations. When you update KGSM to a newer version, your configuration file is intelligently merged with new defaults—keeping your custom values intact while adding new features.

## Configuration File Structure

KGSM's configuration is stored in `config.ini` at the root of your KGSM installation. The file is organized into sections for easier navigation:

```ini
config_schema_version=1

[system]
update_channel=main
enable_logging=false
...

[network]
enable_firewall_management=false
enable_port_forwarding=false
...

[steam]
STEAM_USERNAME=
STEAM_PASSWORD=
...

[services]
enable_systemd=false
...

[instance_defaults]
instance_suffix_length=3
...

[events]
enable_event_broadcasting=false
...

[watchers]
watcher_timeout_seconds=300
...

[accessibility]
enable_command_shortcuts=false
...
```

### Schema Versioning

The `config_schema_version` field tracks the configuration format version. This allows KGSM to automatically migrate your config when the structure changes between major versions.

## Automatic Configuration Updates

### During KGSM Updates

When you run `./installer.sh --update`, KGSM automatically:

1. **Creates a numbered backup** of your current config (saved as `config.ini.0`)
2. **Runs any pending migrations** to update the config format if needed
3. **Merges your customizations** with the updated default config
4. **Adds new keys** from the updated version
5. **Preserves your custom values** for existing settings
6. **Comments out deprecated keys** with warnings

This happens seamlessly—you don't need to do anything.

### Backup System

KGSM maintains up to **10 numbered generations** of config backups:

```
config.ini       # Current config
config.ini.0     # Most recent backup
config.ini.1     # Previous backup
config.ini.2     # Older backup
...
config.ini.9     # Oldest backup
```

Backups rotate automatically—when a new backup is created, `.0` becomes `.1`, `.1` becomes `.2`, and so on. The oldest backup (`.9`) is deleted.

## Configuration Commands

KGSM provides several commands to manage your configuration:

### Viewing and Editing

```bash
# List all configuration values
./kgsm.sh config list

# Get a specific value
./kgsm.sh config get enable_logging

# Set a configuration value
./kgsm.sh config set enable_logging=true

# Open config in your default editor
./kgsm.sh config edit
```

### Validation

```bash
# Validate current configuration
./kgsm.sh config validate
```

This checks for:
- Missing required keys
- Invalid values
- Structural integrity
- Schema version compatibility

### Manual Merging

```bash
# Manually merge with updated defaults
./kgsm.sh config merge
```

Use this if:
- You skipped automatic merge during an update
- You manually edited `config.default.ini`
- You want to refresh your config with new defaults

### Viewing Changes

```bash
# Show differences between current config and most recent backup
./kgsm.sh config diff

# Compare with older backup (0-9)
./kgsm.sh config diff 2
```

This displays a color-coded diff showing:
- Lines removed (in red, prefixed with `-`)
- Lines added (in green, prefixed with `+`)
- Unchanged context lines

### Rolling Back Changes

```bash
# Rollback to most recent backup
./kgsm.sh config rollback

# Rollback to specific generation (0-9)
./kgsm.sh config rollback 2
```

**Important:** Rollback creates a safety backup of your current config before restoring. This ensures you can undo a rollback if needed.

### Resetting to Defaults

```bash
# Reset all settings to defaults
./kgsm.sh config reset
```

⚠️ **Warning:** This replaces your entire config with defaults. Use with caution.

## Configuration Migrations

### What Are Migrations?

Migrations are automated scripts that update your configuration format when KGSM's structure changes between major versions. For example, KGSM 3.0 introduced sectioned INI format, requiring a migration from the flat format used in 2.x.

### How Migrations Work

Migrations are:

1. **Automatic** - Run during updates when needed
2. **Sequential** - Execute in order (001, 002, 003...)
3. **Idempotent** - Safe to run multiple times
4. **Backup-creating** - Always create a `.pre-migration-vX.bak` file

### Migration Files

Migration scripts are stored in `migrations/config/`:

```
migrations/config/
├── 001_v0_to_v1_flat_to_sectioned.sh    # Flat → Sectioned
├── 002_future_migration.sh              # Future changes
└── ...
```

Each migration:
- Checks if it needs to run (via `config_schema_version`)
- Creates a backup before making changes
- Updates the schema version upon completion
- Preserves all user customizations

### Migration Example

When updating from KGSM 2.x to 3.0:

**Before (flat format):**
```ini
update_channel=main
enable_logging=true
STEAM_USERNAME=myuser
```

**After (sectioned format):**
```ini
config_schema_version=1

[system]
update_channel=main
enable_logging=true

[steam]
STEAM_USERNAME=myuser
```

Your custom values (`update_channel=main`, `enable_logging=true`) are preserved while the structure is modernized.

## Deprecated Keys

When KGSM removes or renames configuration keys, they're automatically handled during merge:

```ini
# ============================================================================
# DEPRECATED KEYS
# ============================================================================
# The following keys are no longer used by KGSM and have been preserved
# here for reference. They will be ignored by KGSM.
# ============================================================================

# DEPRECATED: old_setting_name=value
# DEPRECATED: another_removed_key=123
```

You'll see warnings in the merge output:
```
[WARNING] Deprecated configuration key found: old_setting_name
[INFO] Review commented-out deprecated keys in config.ini
```

**Action Required:** Review deprecated keys and remove them when ready. They don't affect KGSM's operation but keep your config file organized.

## Common Workflows

### After Updating KGSM

```bash
# 1. Update KGSM (merge happens automatically)
./installer.sh --update

# 2. Review what changed
./kgsm.sh config diff 0

# 3. If needed, check for deprecated keys
grep "DEPRECATED" config.ini

# 4. Validate the new config
./kgsm.sh config validate
```

### Experimenting with Settings

```bash
# 1. Make changes
./kgsm.sh config set enable_logging=true
./kgsm.sh config set log_max_size_kb=20480

# 2. Test the changes
# ... run your game servers ...

# 3. If something breaks, rollback
./kgsm.sh config rollback 0
```

### Checking Backup History

```bash
# List all available backups with timestamps
for i in {0..9}; do
  [ -f "config.ini.$i" ] && stat -c "%y config.ini.$i" "config.ini.$i"
done
```

### Recovering from Bad Changes

```bash
# 1. View what changed
./kgsm.sh config diff 0

# 2. Restore previous version
./kgsm.sh config rollback 0

# 3. Verify restoration
./kgsm.sh config validate
```

## Troubleshooting

### "Config merge failed" Error

**Symptoms:** After update, you see:
```
[WARNING] Config merge failed. Run './kgsm.sh config merge' manually.
```

**Solution:**
```bash
# Run merge manually
./kgsm.sh config merge

# Check for errors
./kgsm.sh config validate
```

### Missing Configuration Keys

**Symptoms:** KGSM complains about missing settings.

**Solution:**
```bash
# Merge with defaults to add new keys
./kgsm.sh config merge

# Or reset to defaults (nuclear option)
./kgsm.sh config reset
```

### Migration Stuck or Failed

**Symptoms:** Update hangs or fails during migration.

**Solution:**
```bash
# 1. Check migration logs
tail -n 50 logs/latest.log

# 2. Restore pre-migration backup
cp config.ini.pre-migration-v1.bak config.ini

# 3. Try merge instead
./kgsm.sh config merge
```

### Accidentally Deleted config.ini

**Solution:**
```bash
# Restore from most recent backup
cp config.ini.0 config.ini

# Or recreate from defaults
cp config.default.ini config.ini
```

### Want to Start Fresh

```bash
# Option 1: Reset to defaults (keeps backups)
./kgsm.sh config reset

# Option 2: Complete clean slate
rm config.ini config.ini.*
cp config.default.ini config.ini
```

## Best Practices

### ✅ Do

- **Review diffs after updates** - Know what changed
- **Keep backups** - Don't delete `.bak` files manually
- **Use config commands** - Safer than manual editing
- **Validate after changes** - Catch errors early
- **Document custom values** - Comment why you changed defaults

### ❌ Don't

- **Edit during updates** - Let the merge complete first
- **Delete config.default.ini** - Used as merge source
- **Manually edit schema version** - Let migrations handle it
- **Ignore deprecation warnings** - Clean them up eventually
- **Skip validation** - Catches problems before runtime

## Advanced: Manual Migrations

If you need to migrate manually (rare):

```bash
# Check current schema version
grep config_schema_version config.ini

# Run specific migration
bash migrations/config/001_v0_to_v1_flat_to_sectioned.sh

# Verify migration succeeded
grep config_schema_version config.ini  # Should be incremented
```

## Configuration Reference

For a complete list of all configuration keys and their meanings, see:
- `config.default.ini` - Contains all settings with inline documentation
- Each section in the file explains the purpose and valid values

Common sections:
- **[system]** - Core KGSM behavior (logging, updates)
- **[network]** - Firewall, port forwarding
- **[steam]** - Steam integration credentials
- **[services]** - systemd, UFW integration
- **[instance_defaults]** - Default settings for new game servers
- **[events]** - Webhook notifications
- **[watchers]** - Server readiness detection
- **[accessibility]** - Command shortcuts, UI features

## Related Documentation

- **[config_management_specification.md](config_management_specification.md)** - Technical specification for developers
- **[create_new_game_server_instance.md](create_new_game_server_instance.md)** - Using instance-level config
- **[managing_game_servers.md](managing_game_servers.md)** - Server lifecycle management

## Need Help?

If you encounter issues with configuration:

1. Check this guide's [Troubleshooting](#troubleshooting) section
2. Run `./kgsm.sh config validate` for specific errors
3. Review backup files if available
4. Open an issue on GitHub with:
   - Output of `./kgsm.sh config validate`
   - Relevant log entries
   - Steps to reproduce

---

**Last Updated:** December 16, 2025  
**KGSM Version:** 3.0+  
**Schema Version:** 1
