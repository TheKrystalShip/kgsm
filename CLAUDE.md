# CLAUDE.md

KGSM (Krystal Game Server Manager) is the engine of the KGSM ecosystem: one Native-AOT binary, `kgsm`,
that installs, runs and manages game-server instances (native processes and containers) from declarative
blueprints. It is the engine's stateless half; `kgsm-watchdog` is the resident half. Role, contracts and
peers: `../kgsm-docs/components/kgsm.md`. The engine model: `../kgsm-docs/systems/engine/`.

## Commands

```bash
dotnet build kgsm.slnx
dotnet test tests/Engine.Tests
dotnet publish src/Cli/Cli.csproj -c Release -r linux-x64     # must show no IL2xxx, IL3xxx or ILC warning
../scripts/pkg-local.sh kgsm [--test] [--no-install]         # the release workflow's build, as a package
```

`pkg-local.sh` runs the workflow's own Test and Publish steps, `makepkg`s into `../.packages/kgsm/` and
installs with `sudo pacman -U`; `--no-install` stops after the package. That is how a change reaches a host:
nothing is copied onto a host by hand, and there is no checkout deploy.

## Code map

- `src/Engine.Contracts` (shapes, event vocabulary, maintenance-window grammar) and `src/Engine` (the
  core) are the two packages; `src/Cli` is the binary. `Directory.Build.props` carries the one version,
  which `./deploy/version.sh` prints (`--pkgver` for the pacman form).
- `src/Cli` is the command line: a command returns an `Outcome` (a result DTO with its text, or a failure) and
  never writes; `Output/` is the one stage that renders it, as text or as JSON through the registered
  context, errors on stderr with stdout empty. A command goes in `Commands/`, its DTO in `Engine.Contracts`
  and `EngineJsonContext`, and its test runs the command line in-process through `CliSession` in
  `tests/Engine.Tests/Cli/`. Every command but help, version and paths runs behind the registry-account gate.
- Components reach the engine through two classes: `EngineReader` (`src/Engine/Reading/`, every read, in-process,
  built on the same modules as the read commands) and `EngineCli` (`src/Engine.Contracts/Invocation/`, every
  write, the typed invocation of the binary). A new command that components call gets its method on
  `EngineCli`; a new read gets its method on `EngineReader` and, when the binary prints it too, a shared
  builder both use.
- The write operations are `src/Engine/Operations/`, one service per concern (install, uninstall, lifecycle,
  move, update, config, console, backup, blueprint, library, journal maintenance), all standing on an
  `OperationHost`. Transfer is `src/Engine/Transfers/`: the export service (manifest, locked parts, commit),
  the import service (check, begin, part, finish, abort, list), the tree part's archive and the sealed image
  stream. Its doors to the outside are interfaces (`IProcessRunner` for the instance's script and
  the firewall client, `IWatchdogControl`, `IContainerRuntime`, `IImageStore`, `IFirewallClient`), so a test runs an
  operation against fakes: `tests/Engine.Tests/Operations/OpsFixture.cs` holds a `ScriptEmulator` that
  leaves what the real script leaves. Whatever changes an instance runs in its script; a service decides,
  brackets, journals and checks results. A new write needs its refusals decided before it touches a file,
  its events bracketed with `*.finished` always last, and a test for each.
- JSON goes through the registered contexts (`EngineJsonContext` camelCase, `EngineEventJsonContext`
  PascalCase for journal payloads) and YAML through `BlueprintYamlContext`; no JSON DOM.
- A file the engine writes carries `schemaVersion`, and a reader refuses a version it does not know.
- The management script is one template, `src/Engine/Scripts/management-script.tpl`, rendered per runtime by
  `ScriptGenerator`. A change to its text bumps `ScriptTemplate.Version` and records the new hash in
  `tests/Engine.Tests/Scripts/ScriptTemplateTests.cs`, which is what makes `instance repair --all` rewrite
  the scripts built from the old text. A script test builds a `ScriptWorld` (a generated script in a
  sandbox with fakes for every external tool, `Scripts/FakeTools.cs`) and runs it with bash; none touches a
  real host. A game's hooks are `overrides/<name>/hooks.sh`.
- The config descriptor `src/Cli/kgsm.leaf.json` is generated from the settings class on every build.
  Edit `src/Engine/Settings/EngineSettings.cs` and `src/Cli/kgsm.settings.json`, never the JSON.
- A transfer test builds a `TransferWorld` (tests/Engine.Tests/Transfers/): two nodes, each an `OpsFixture`
  with a runtime of its own, and the command lines that carry an instance from one to the other through the
  parts' standard streams. An image the fake runtime saves is `reference|chain|size`, loaded under an id of
  the loading runtime's own.
- A test builds its world in a `Sandbox` (its own XDG homes, install root and journal directory under the
  run's temporary root). No test touches `/var/lib/kgsm/events` or any live path.

## Conventions

- Code follows `.editorconfig` and the workspace rules: registered JSON types only, no JSON DOM, no
  fabricated values (`null` is unknown), logging per `../kgsm-docs/reference/logging-convention.md`.
- Every code path has one defined, testable outcome. A check either always runs or never runs; it is never
  conditional on incidental state.
- The generated management script is bash; the hook files under `overrides/` are bash too.

## Packaging and release

- `packaging/PKGBUILD` places the published stage: the binary and `kgsm.settings.json` under `/opt/kgsm`,
  the system blueprints (`blueprints/*.bp.yaml`), the hook files (`overrides/<name>/hooks.sh`), the
  descriptor and the two generated manifests under `/var/lib/kgsm/leaves`, and the journal-prune units from
  `deploy/`. `/usr/bin/kgsm` links to the binary; its real directory is the install root.
- `packaging/kgsm.install` presets the prune timer and runs `kgsm instance repair --all` as the `kgsm`
  account after an upgrade.
- `.github/workflows/release.yml` is generated by `../scripts/ci-template/vendor-ci.sh`; edit the template.
- A pushed `v*` tag fires the release into the public pacman repository.

## Version tracking

- The version is `<Version>` in `Directory.Build.props`; `./deploy/version.sh` prints it and packaging asks
  for it. Both packages, `Engine` and `Engine.Contracts`, publish at it.
- Bump it for every user-facing change: patch for fixes, minor for features, major for breaking changes.
- Add a `CHANGELOG.md` entry for every meaningful change.
- Tag the bump commit `git tag -a v<version> -m "kgsm v<version>"`.

## Read before changing

- `blueprints/CLAUDE.md` and `overrides/CLAUDE.md`: the system blueprints and hook files.
- `docs/`: the guides for the binary.
- `../kgsm-docs/reference/event-envelope.md`, `event-journal.md`, `event-vocabulary.md`: the journal
  line the engine writes.
- `../kgsm-docs/reference/maintenance-windows.md` and `../kgsm-docs/systems/operations/`: windows and
  announcements.

Docs and comments describe the system as it is now: present tense, no history, no emoji, no volatile
numbers (workspace `../CLAUDE.md`).
