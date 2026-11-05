# KGSM - Krystal Game Server Manager

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

The engine of the KGSM ecosystem: one Native-AOT binary, `kgsm`, that installs, runs, backs up, updates
and removes game servers on a Linux host, as native processes or as containers, from declarative
blueprints.

- **One binary, one writer.** Every change to engine state goes through `kgsm`; components read the same
  state in-process through the `TheKrystalShip.KGSM.Engine` package and write by running the binary through
  the typed invocation in `TheKrystalShip.KGSM.Engine.Contracts`.
- **Scriptable.** Every command prints text, or JSON with `--json`; errors go to stderr as a JSON error
  report in that mode; exit codes are few and documented.
- **Native or container.** A blueprint's `runtime` decides which.
- **Low overhead.** No resident process: the watchdog is the resident half and supervises native instances.

## Installation

KGSM is published as a signed pacman package in the KGSM repository. Point pacman at the repository and its
signing key once (the block is in [`kgsm-meta`](https://github.com/TheKrystalShip/kgsm-meta#installing-a-node)),
then:

```sh
pacman -S kgsm
```

The package installs the binary, the system blueprints and the system hook files under `/opt/kgsm`, links
it onto `PATH` as `/usr/bin/kgsm`, and pulls in the tools the generated management scripts run (`bash`,
`jq`, `curl`, `tar`, procps, coreutils, findutils). Upgrades are `pacman -Syu`; each upgrade regenerates
the instances' management scripts that went stale (`kgsm instance repair --all`).

Optional: `kgsm-watchdog` (supervision, autostart, crash restart), `kgsm-firewall` (host firewall ports),
`steamcmd` (Steam-distributed servers), `docker` and `docker-compose` (container instances).

## Quick start

```sh
kgsm blueprint list                     # what can be installed
kgsm instance install factorio --start  # install, then start
kgsm instance list                      # every registered instance
kgsm instance status factorio-a1        # run state, version, ports, backups, recent output
kgsm backup create factorio-a1
kgsm instance stop factorio-a1
```

Every command: `kgsm --help`, and [docs/commands.md](docs/commands.md).

## Building from source

```sh
dotnet build kgsm.slnx
dotnet test tests/Engine.Tests
dotnet publish src/Cli/Cli.csproj -c Release -r linux-x64     # the Native-AOT binary
```

`scripts/pkg-local.sh kgsm` in the workspace builds the package the release workflow builds, from this
checkout.

## Documentation

[docs/README.md](docs/README.md) indexes the guides. The engine's place among the other components, its
contracts and its rules are documented in the `kgsm-docs` repository.

## Contributing

A new game is a blueprint in `blueprints/` and, when its install or update is not the generic Steam one, a
hook file in `overrides/<name>/hooks.sh`. See [docs/blueprints.md](docs/blueprints.md) and
[docs/hooks.md](docs/hooks.md). Code changes follow `CLAUDE.md`.

## License

GPL-3.0. See [LICENSE](LICENSE).
