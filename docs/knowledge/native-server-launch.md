# Launching a native Linux dedicated server

The `native:` block of a blueprint tells KGSM what to run and how to know it started. Getting
`executable_file` and `executable_arguments` right is the difference between a server that boots and
listens and one that exits immediately or hangs. The conventions below are what real game servers
follow.

## The executable is what you run, which is not always the binary

`executable_file` names the thing KGSM executes from the install directory. There are three shapes,
and choosing the wrong one is the most common reason a server fails to boot.

### 1. A wrapper launch script (preferred whenever the game ships one)

Many games ship a small shell script that sets up the runtime environment and then execs the real
binary — it exports `LD_LIBRARY_PATH` so the binary finds its bundled shared libraries, changes into
the install directory, and sometimes starts a virtual framebuffer (`xvfb`) the engine needs. When a
game ships such a script, **the script is the executable**, not the binary it wraps. Running the raw
binary directly skips that setup and it fails to load its own libraries.

Shipped examples: Core Keeper's `_launch.sh`, Valheim's `start_server_bepinex.sh`, Palworld's
`PalServer.sh`, Necesse's `StartServer-nogui.sh`, Project Zomboid's `start-server.sh`. Each sits
beside a raw binary (`CoreKeeperServer.x86_64`, `valheim_server.x86_64`, …) that is *not* the right
`executable_file`.

### 2. An interpreter, with the server artifact as an argument

Some servers are not native binaries at all — they run *through* an interpreter. The interpreter is
the executable and the server file is an argument:

- A Java server: `executable_file: java`, and the jar goes in the arguments as `-jar release.jar`
  (Minecraft ships this way — `java … -jar release.jar nogui`).
- A .NET server: `executable_file: dotnet`, and the dll goes in the arguments as `Server.dll`
  (Romestead ships this way).

The `.jar` / `.dll` is never the `executable_file` — it is not directly executable.

### 3. A raw binary, sometimes in a subdirectory

When a game genuinely runs a binary directly, `executable_file` is that binary
(`TerrariaServer.bin.x86_64`, `DedicatedServer`). If the binary lives in a subfolder of the install
directory rather than at its root, that subfolder goes in `executable_subdirectory` and *only the
filename* goes in `executable_file` — the two are separate fields, not one path:

- Factorio: `executable_subdirectory: bin/x64`, `executable_file: factorio`.
- 7 Days to Die: `executable_subdirectory: /bin/x86_64`, `executable_file: 7DaysToDieServer.x86_64`.
- Starbound: `executable_subdirectory: linux`, `executable_file: starbound_server`.

Cramming the path into the filename (`bin/x64/factorio` as `executable_file`) is wrong.

### Docker entrypoints are not native launchers

A container entrypoint (`entry.sh`, `docker-entrypoint.sh`, or a start script defined inside a
`Dockerfile`) is a containerisation wrapper, not the game's native launch script. KGSM installs the
game's official native server directly on the host, so the Docker entrypoint is never the
`executable_file` — look past it to the launch script or binary the game itself ships. (This is the
opposite of the wrapper-script rule above: the game's *own* launcher is preferred; a *container's*
launcher is excluded.)

## Arguments must launch it headless, and stay portable

`executable_arguments` are the flags that start the server **non-interactively** — it boots and
listens without waiting for keyboard input. A server started without its headless flags stalls at an
interactive prompt (choosing a world, for example) and never binds its port.

Two rules keep arguments correct across installs:

- **Use `$instance_*` variables for names and paths the player fills in**, not literals or absolute
  paths. A documented `-world <SaveName>` becomes `-world $instance_level_name`; a save path becomes
  `$instance_saves_dir/$instance_level_name`. Terraria, Factorio, 7 Days to Die, Necesse and Project
  Zomboid all parameterise their arguments this way.
- **Never hard-code an absolute host path** (`/opt/<game>/server-settings.json`) — it will not exist
  on a fresh install. Use a `$instance_*` path or omit the optional flag.

Keep the argument list minimal: only the flags needed to launch and listen. Some wrapper scripts read
their own config file and need *no* arguments at all (Core Keeper, Barotrauma ship with empty
`executable_arguments`).

## Readiness: how KGSM knows the server started

KGSM confirms a server is up in one of two ways, and `startup_success_regex` is the more reliable:

- **`startup_success_regex`** — a regex matched against the server's log output, authored from the
  *real* line the server prints when it is ready. Examples from the catalog: Terraria and Barotrauma
  print `Server started`; Factorio prints `Hosting game at IP ADDR…`; Valheim prints `Opened Steam
  server`; Starbound prints `UniverseServer: listening for incoming TCP connections`. Author this only
  from observed output — a guessed phrase that never appears means the server is treated as never
  ready.
- **Port reachability** — if no readiness regex is set, KGSM waits for the server to listen on its
  configured port instead. This needs `ports` to be correct.

When both are absent, there is no positive signal that the server came up, and it can only be treated
as failed.

## Ports

`ports` is a single string in UFW format, pipe-separated, listing every port the server binds. It is
not the Docker `host:container` shape. Real forms:

- A single port and protocol: `34197` (Factorio) — a bare number defaults across protocols; or an
  explicit `27015/udp`.
- Both protocols on one port: `7777/tcp|7777/udp` (Terraria).
- A contiguous range: `2456:2458/tcp|2456:2458/udp` (Valheim), `26900:26903/tcp|26900:26903/udp`
  (7 Days to Die).
- Several distinct ports: `8211/udp|27015/udp` (Palworld).

## Stopping the server

`stop_command` is the input a server reads on its console to shut down gracefully — `exit`, `/stop`,
`/quit`, `quit`, or `stop`, depending on the game. It is left empty when the server has no console
stop command and is stopped by signal instead.
