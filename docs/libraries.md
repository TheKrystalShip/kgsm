# 💽 Libraries

A **library** is a named root that game server instances are placed in. Registering several of
them lets a host's instances live across several disks, and makes placement an enumerable fact:
what roots exist, how much room is left on each, how many instances each holds, and whether the
disk behind it is there right now.

## The two records

A library is `{name, id, path}`, and it is written down twice.

**The registry** — `$XDG_DATA_HOME/kgsm/libraries.ini` — is what this host knows. One INI section
per library, the section header being the name:

```ini
[ssd]
id=3f2a9c81d4e64b7a
path=/mnt/ssd/kgsm

[archive]
id=b71e04d5a2c8f396
path=/mnt/archive
```

**The marker** — `.kgsm-library` in the library root — is what the disk itself says:

```ini
id=3f2a9c81d4e64b7a
name=ssd
```

Both exist because they answer different questions. The registry is a list of roots this host
has been told about; the marker is proof that the root in front of you is the library the registry
means. An unmounted disk leaves an empty directory behind at its mount point, and without the
marker the engine would take that empty directory for the library and install onto the root
filesystem through it.

- **`name`** is the section header: lowercase letters, digits and dashes, starting with a letter
  or a digit. Host-unique and renameable.
- **`id`** is generated once from the kernel's random source and never changes. It travels with
  the disk, which is what lets a disk that moves between hosts be recognised as the library it
  already is.
- **`path`** is the canonical root, resolved at registration.

The registry is written by the `kgsm libraries` verbs; it is not a file to edit by hand.

## Online and offline

A library is **online** when its root exists *and* carries a marker whose id is the registered
one. Anything else — the path gone, the marker absent, the marker holding another library's id —
is **offline**.

This is measured on every invocation. Nothing is cached: KGSM's CLI re-derives its state on each
run, and a disk's presence is exactly the kind of fact that changes between two of them.

Offline is a **state, not an error**. `kgsm libraries list` reports an offline library and says
nothing about its free space, because nothing measured it. An unplugged disk is a measured
absence, never an uninstall.

## What happens to the instances in an offline library

An instance's registry entry is a symlink in `$KGSM_INSTANCES_DIR/<blueprint>/<instance>`, and an
unmounted library leaves it dangling rather than removing it. So the instance is still there — it
is only unreadable, and every part of the engine treats those as different facts.

- **It still enumerates.** `kgsm instances list` names it, and `--detailed` and `--json` describe
  it with what can be measured without the disk: its name, its blueprint, its working directory,
  its library and where that library is expected. Every other field is absent rather than guessed,
  because all of them live in a config file behind the dangling link.
- **It reports `library_state`.** The field is on every instance, `online`, `offline` or
  `unregistered`, in `instances info --json`, the detailed listing and `instances status --json`.
  An offline instance's `status` is `null`: whether a server whose files cannot be read is running
  is not something that was measured, and `false` would be an invention.
- **Lifecycle verbs fail fast.** `start`, `stop`, `restart`, `status`, `is-active` and `logs` all
  need the instance's own files, so they refuse up front with `EC_LIBRARY_OFFLINE` (55), naming the
  library and the path it is expected at, rather than failing somewhere in the middle on a missing
  file.
- **Nothing removes the record.** `kgsm instances remove`, `kgsm directories unlink-instance` and
  `kgsm uninstall` all refuse while the library is offline. That symlink is the last thing on this
  host that says the instance exists, and the files it points at are intact on a disk that is
  simply elsewhere.

`--force` on any of those three deregisters the instance and touches not one file: the supervisor
stops being told to look after it, the registry entry goes, and the working directory, saves and
backups stay on the disk. It is how an instance is forgotten on purpose. Firewall rules and command
shortcuts the instance recorded in its own config cannot be read, so they are not removed either,
and the uninstall says so.

Putting the disk back is the whole of the recovery. Nothing has to be re-registered, re-linked or
repaired: the next invocation measures the library as online again and every instance in it reads
normally.

## Verbs

```bash
kgsm libraries add <path> [--name <name>]
kgsm libraries remove <name> [--force]
kgsm libraries list [--json]
kgsm libraries rename <old> <new>
```

### `add`

Creates the root when it is not there, resolves it to a canonical path, checks it is writable,
writes the marker, and registers it. The name comes from `--name`, or from the directory's own
name when the directory's name is usable as one.

A root that **already carries a marker is adopted**: it keeps the identity written in it rather
than being made into a new library. That is what makes a disk portable — move it to another host,
`add` it there, and it is the same library with the same id. Pass `--name` when the name it
carries is already taken on this host.

Three things are refused, each naming what is already registered:

- the path is already a library — a path backs exactly one library, or its instances would have
  two answers to "which library am I in";
- the marker's id is registered at another path;
- the name is taken by another library.

### `remove`

Deregisters the library and takes the marker off the root when the root is reachable. **No file
inside the library is touched**, including the instances placed there.

A library that holds instances is refused, and the refusal names them. `--force` deregisters it
anyway and leaves everything on disk where it is.

Removing an **offline** library leaves its marker behind: the identity stays on the disk, so
re-adding it later adopts the library it already holds instead of minting a second one over the
same instances.

### `list`

Reports each library's name, state, free and total bytes, instance count, and root. `--json`
emits the same facts as an array:

```json
[
  {
    "name": "ssd",
    "path": "/mnt/ssd/kgsm",
    "state": "online",
    "free_bytes": 412316860416,
    "total_bytes": 983504482304,
    "instance_count": 3
  }
]
```

An offline library reports `free_bytes` and `total_bytes` as `null` — an unmeasured figure is
null, never a number nothing measured.

### `rename`

Rewrites the name in the registry and in the marker. Instances are unaffected: they record the
library's **path**, and the name lives only in the registry, so a rename costs nothing. An offline
library is renamed in the registry alone; its marker catches up the next time the root is
reachable, and nothing depends on it in the meantime because online is decided by the id.

## Which library an instance is in

An instance belongs to the library whose registered root is the **longest** prefix of its working
directory, so a library nested inside another resolves to the inner one. An instance under no
registered root belongs to no library, and is reported that way rather than assigned to the
nearest one.

The lookup reads the target of the instance's registry symlink rather than following it: a library
that is not mounted leaves a broken symlink behind, and its instances have to stay countable for
the refusals that protect them.

## Configuration

`[instance_defaults] default_library` names this host's default library. Empty is legal; with
exactly one library registered, that one is the default regardless.

`[instance_defaults] install_free_space_margin_mb` (default 1024) is the room an install
requires beyond the blueprint's declared `metadata.base_disk_mb` before it proceeds.

`kgsm install` and `kgsm instances create` take the library an instance is placed in from
`--library <name>`, falling back to `default_library` and then to the sole registered library.
Instances are placed at `<library-root>/instances/<blueprint>/<instance>`. See
[Creating a new game server instance](create_new_game_server_instance.md).

## Events

Registering and deregistering a library are recorded in the event journal as `library_added` and
`library_removed`, each carrying `LibraryName` and `Path`. See [Event System](events.md).
