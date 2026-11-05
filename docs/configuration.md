# Configuration

## Settings

The engine's settings are a sectioned JSON file, `kgsm.settings.json`. Three sources apply, lowest
precedence first:

1. the file beside the binary, `/opt/kgsm/kgsm.settings.json`, which declares the whole surface;
2. the person's file, `<config home>/kgsm/kgsm.settings.json` (`~/.config/kgsm/`), holding only the
   overrides;
3. environment variables, `Section__Key` (`Libraries__DefaultLibrary`).

```sh
kgsm engine config list            # every setting, its value and the source that set it
kgsm engine config get Backups:Compress
kgsm engine config set Journal:RetentionDays 30
```

`set` writes the person's file, typed and validated against the settings' floors before anything is written.
A change applies the next time `kgsm` runs; nothing restarts.

| Section | Settings |
|---|---|
| `Libraries` | `DefaultLibrary`, `InstallFreeSpaceMarginMb` |
| `Instances` | `IdSuffixLength` and the defaults copied into a new instance: `SaveCommandTimeoutSeconds`, `StopCommandTimeoutSeconds`, `AutoUpdateBeforeStart`, `MaintenanceWindows`, `AnnounceLeadMinutes`, `AnnounceMaintenanceMessage`, `AnnounceMaintenanceCancelledMessage`, `EnableFirewallManagement`, `EnablePortForwarding` |
| `Backups` | `Directory` (empty is the data home's `backups/`), `Compress` |
| `Journal` | `Directory` (`/var/lib/kgsm/events`), `RetentionDays` |
| `Cgroup` | `MountPoint`, `BaseName` |
| `Watchdog` | `Socket`, `Enabled` |
| `Firewall` | `Client`, `Socket` |
| `Downloads` | `TimeoutSeconds`, exposed to hooks |
| `Logging` | `File:MaxSizeKb`, `File:MaxFiles`, `LogLevel:Default` |

The settings class (`src/Engine/Settings/EngineSettings.cs`) is the authority; the config descriptor the
panel edits is generated from it.

## Files

`kgsm engine paths` prints every directory and file the engine resolves: the XDG config, data and state
homes, the install root, both settings files, the registries, the user and system blueprint and hook
directories, the log and the locks directory.

## Steam credentials

`/etc/kgsm/kgsm.env` holds `STEAM_USERNAME` and `STEAM_PASSWORD`, readable by the engine's account only.
The binary and the generated scripts read it themselves, since neither runs as a unit; the environment wins
over the file.

## The engine's log

`kgsm.log` in the state home's `kgsm/logs/`, in the console formatter's line format, rotated by size
(`Logging:File:MaxSizeKb`) and keeping `Logging:File:MaxFiles` rotated files. The level is
`Logging:LogLevel:Default`.

## The event journal

Facts the engine establishes are appended to `<Journal:Directory>/YYYY-MM-DD.ndjson`. `kgsm event journal
prune` deletes segments past `Journal:RetentionDays`; the `kgsm-journal-prune` timer runs it daily.
`kgsm event emit` writes one of the engine's own events; the vocabulary is in `kgsm-docs`.
