# Libraries

A library is a named storage root that instances are placed in. An instance's working directory is
`<library root>/instances/<blueprint>/<id>`.

```sh
kgsm library list                       # state, free and total bytes, instance count
kgsm library add games /mnt/games
kgsm library rename games big
kgsm library remove big                 # deregisters; its files are never deleted
```

## Rules

- A name is lowercase letters, digits and hyphens, starting with a letter or digit.
- A root is absolute and is marked by a `.kgsm-library` file the engine writes.
- A root never overlaps the directory that holds the engine's registries: game data and engine state do not
  share a tree.
- An instance belongs to the registered library whose root is the longest prefix of its working directory,
  so a library nested in another resolves to the inner one.
- `Libraries:DefaultLibrary` names the library an install uses when `--library` is absent; with one library
  registered that library is used.
- An install needs the blueprint's `base_disk_mb` plus `Libraries:InstallFreeSpaceMarginMb` free in the
  library; `--skip-space-check` installs anyway. A shortage exits 56.
- A library on an unmounted disk is offline: its instances stay listed and keep their ids.
- `kgsm instance move <instance> <library>` moves a stopped instance between libraries.

The registry is `libraries.json` in the data home.
