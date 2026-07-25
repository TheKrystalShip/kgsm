# Game reference: real launch shapes from the catalog

Annotated examples from shipped blueprints, grouped by the pattern each one illustrates. The blueprint
file (`blueprints/<game>.bp.yaml`) is the live source of truth; this catalog explains *why* each is
shaped the way it is. See [`native-server-launch.md`](native-server-launch.md) and
[`steam-downloads.md`](steam-downloads.md) for the patterns themselves.

## Wrapper launch scripts

The game ships a script that sets up the runtime and execs the binary; the script is the executable.

- **Core Keeper** — `executable_file: _launch.sh`, no arguments (the script reads its own config).
  Server app id `1963720` (client `1621690`). Ready line: `Game ID`. Illustrates a wrapper that needs
  empty arguments — the raw `CoreKeeperServer.x86_64` beside it is the wrong choice.
- **Valheim** — `executable_file: start_server_bepinex.sh`,
  `executable_arguments: -nographics -batchmode -name $instance_level_name -port 2456 -public 1`.
  Server app id `896660` (client `892970`). Ready line: `Opened Steam server`. Ports span a range,
  `2456:2458/tcp|2456:2458/udp`. The script sets `LD_LIBRARY_PATH`; the raw `valheim_server.x86_64`
  does not run without it.
- **Palworld** — `executable_file: PalServer.sh`,
  `executable_arguments: -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS -publicport=8211 -players=32`.
  Server app id `2394010`. Ready line: `Bringing World /Pal/Maps/MainWorld up for play`.
- **Project Zomboid** — `executable_file: start-server.sh`,
  `executable_arguments: -servername $instance_level_name -cachedir=$instance_saves_dir`. Ready line:
  `SERVER STARTED`. Parameterises both the server name and the cache dir with `$instance_*` variables.
- **Necesse** — `executable_file: StartServer-nogui.sh`,
  `executable_arguments: -world $instance_level_name -localdir`. Server app id `1169370` (client
  `1169040`). Ready line: `Started server using port`.

## Interpreter-run servers

The server runs through an interpreter; the interpreter is the executable and the artifact is an
argument.

- **Minecraft** — `executable_file: java`, arguments are the JVM flags followed by
  `-jar release.jar nogui`. Not a Steam game (`steam_app_id: 0`). Ready line: `For help, type "help"`.
  Stopped with `/stop`.
- **Romestead** — `executable_file: dotnet`, `executable_arguments: Server.dll`. Server app id
  `4763510` is distinct from the client `1805320`, so it downloads anonymously
  (`is_steam_account_required: false`). Ready line: `Server started on port`.

## Raw binary in a subdirectory

The binary runs directly but lives in a subfolder; subfolder and filename are separate fields.

- **Factorio** — `executable_subdirectory: bin/x64`, `executable_file: factorio`,
  `executable_arguments: --start-server $instance_saves_dir/$instance_level_name`. Not a SteamCMD
  install (`steam_app_id: 0`; downloads from the vendor). Ready line: `Hosting game at IP ADDR`.
- **7 Days to Die** — `executable_subdirectory: /bin/x86_64`,
  `executable_file: 7DaysToDieServer.x86_64`, arguments run it headless and point `-configfile=` at
  `$instance_install_dir/serverconfig.xml`. Server app id `294420` (client `251570`). Ports span
  `26900:26903`. Ready line: `INF StartGame done`.
- **Starbound** — `executable_subdirectory: linux`, `executable_file: starbound_server`, no arguments.
  See below — it is also the ownership-required example.

## Raw binary at the install root

- **Terraria** — `executable_file: TerrariaServer.bin.x86_64`,
  `executable_arguments: -world $instance_saves_dir/$instance_level_name -autocreate 3 -worldname $instance_level_name`.
  Not a SteamCMD install (`steam_app_id: 0`; downloaded via override). Ports `7777/tcp|7777/udp`.
  Ready line: `Server started`. Without the `-world`/`-autocreate`/`-worldname` arguments the server
  stalls at an interactive world-selection prompt and never listens.
- **Barotrauma** — `executable_file: DedicatedServer`, no arguments. Server app id `1026340` (client
  `602960`). Ports `27015/udp|27016/udp`. Ready line: `Server started`.

## Ownership required

- **Starbound** — `steam_app_id: 211820` equals `client_steam_app_id: 211820`: the server ships inside
  the paid game with no separate free server app, so `is_steam_account_required: true`. Its files
  download only through an account that owns the game; an anonymous install cannot fetch them. This is
  the one case in the catalog where server and client app ids match — everywhere else they differ and
  ownership is not required.
