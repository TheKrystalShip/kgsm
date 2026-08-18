# =============================================================================
# HELP SYSTEM
# =============================================================================

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "${UNDERLINE}Instance Management - ${instance_name}${END}

Manage this game server instance directly.

${UNDERLINE}Usage:${END}
  $self <command> [arguments] [options]

${BOLD}${UNDERLINE}Lifecycle Commands:${END}
  start [-d, --detached]      Start the server
  stop [--no-save] [--no-graceful]  Stop the server
  restart                     Restart the server (stop + start)
  attach                      Attach to running server console
  kill                        Kill the server process
  is-active                   Check if the server is running

${BOLD}${UNDERLINE}Server Commands:${END}
  save                        Save the current game state
  input <command>             Send a command to the server console
  status [--json] [--fast]    Display comprehensive runtime status
  logs [-f] [--tail N]        View server logs

${BOLD}${UNDERLINE}Player Moderation:${END}
  kick <target>               Disconnect a player
  ban <target>                Disconnect a player and block them
  unban <target>              Lift a block

${BOLD}${UNDERLINE}Version & Update Commands:${END}
  version [--latest|--compare|--save <ver>|--stored-latest]  Version management
  check-update                Check whether a newer version is available
  download [version]          Download game server files
  deploy                      Deploy files from temp directory
  update                      Update to latest version

${BOLD}${UNDERLINE}Backup Commands:${END}
  backups [--json]            List available backups
  create-backup [--reason R]  Create a backup
  restore-backup <id>         Restore the backup with this id
  pin-backup <id>             Keep a backup out of prune-backups' reach
  unpin-backup <id>           Let prune-backups take it again

${BOLD}${UNDERLINE}Other:${END}
  help [command]              Display help information
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  $self start --detached
  $self stop
  $self logs --follow --tail 50
  $self status --json
  $self backup create
  $self version --latest
  $self help start
"
}

function show_usage_start() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Start Command${END}

Start the game server container via docker compose.

${UNDERLINE}Usage:${END}
  $self start [options]

${UNDERLINE}Options:${END}
  -d, --detached              Start container in background (detached) mode
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  $self start
  $self start --detached
"
}

function show_usage_stop() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Stop Command${END}

Gracefully stop the running game server container via docker compose down.

${UNDERLINE}Usage:${END}
  $self stop [options]

${UNDERLINE}Options:${END}
  --no-save                   Do not save game state before stopping
  --no-graceful               Kill immediately without sending stop command
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  $self stop
  $self stop --no-save
  $self stop --no-graceful
"
}

function show_usage_restart() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Restart Command${END}

Stop and then start the game server.

${UNDERLINE}Usage:${END}
  $self restart

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  $self restart
"
}

function show_usage_attach() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Attach Command${END}

Attach to the running container for interactive shell access via docker compose exec.

${UNDERLINE}Usage:${END}
  $self attach

${UNDERLINE}Examples:${END}
  $self attach
"
}

function show_usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Status Command${END}

Display comprehensive runtime status information.

${UNDERLINE}Usage:${END}
  $self status [options]

${UNDERLINE}Options:${END}
  --json                      Output status information as JSON
  --fast                      Skip update checking for faster response
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  $self status
  $self status --json
  $self status --fast
  $self status --json --fast
"
}

function show_usage_logs() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Logs Command${END}

View server log entries via docker compose logs.

${UNDERLINE}Usage:${END}
  $self logs [options]

${UNDERLINE}Options:${END}
  -f, --follow                Continuously follow log output in real-time
  --tail, -n <number>         Display last <number> lines (default: 10)
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  $self logs
  $self logs --follow
  $self logs --tail 50
  $self logs --follow --tail 100
"
}

function show_usage_moderation() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Player Moderation${END}

Disconnect a player, block them, or lift a block.

${UNDERLINE}Usage:${END}
  $self kick <target>
  $self ban <target>
  $self unban <target>

${UNDERLINE}Arguments:${END}
  target                      The player identity this game addresses

${UNDERLINE}Description:${END}
Each action sends this game's own console command with <target> substituted
in. The blueprint declares which identity the game expects by the placeholder
it uses — {ip}, {name} or {id} — and this instance's templates are:

  kick:  ${instance_kick_command:-<unsupported>}
  ban:   ${instance_ban_command:-<unsupported>}
  unban: ${instance_unban_command:-<unsupported>}

An action with no declared command is refused; KGSM never substitutes a
different one.

${UNDERLINE}Examples:${END}
  $self kick 192.168.1.42
  $self ban 192.168.1.42
  $self unban 192.168.1.42
"
}

function show_usage_version() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Version Command${END}

Manage version information for this instance.

${UNDERLINE}Usage:${END}
  $self version [options]

${UNDERLINE}Options:${END}
  --latest                    Print the latest available version
  --compare                   Compare installed vs latest version
  --save <version>            Save a version string to file
  --stored-latest             Print the last upstream version a check recorded
  --stored-checked-at         Print when that version was fetched
  --save-latest <version>     Record an upstream version as checked just now
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  $self version
  $self version --latest
  $self version --compare
  $self version --save 1.2.3
  $self version --stored-latest
"
}

function show_usage_backup() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Backup Commands${END}

Manage game server backups.

A backup captures the instance's install and saves directories. Each one is
identified by an opaque id; its details (size, creation time, captured version)
live in the backup's manifest and are reported by 'backups --json'.

A manifest also records WHY the backup was taken and WHETHER rotation may take
it. The reason is a fact fixed at capture (manual, scheduled, pre-update,
pre-restore, incident) and is never edited; the retention is a policy, and
pin-backup/unpin-backup are how it changes. A pinned backup is skipped by
prune-backups and does not count toward its --keep window; deleting one by name
still works.

${UNDERLINE}Usage:${END}
  $self backups [--json]
  $self create-backup [--reason <reason>] [--retention <policy>]
  $self restore-backup <id>
  $self pin-backup <id>
  $self unpin-backup <id>

${UNDERLINE}Commands:${END}
  backups [--json]            List backup ids, newest first (--json: full manifests)
  create-backup               Create a backup of the current server files
  restore-backup <id>         Restore from the backup with this id
  pin-backup <id>             Keep a backup out of prune-backups' reach
  unpin-backup <id>           Let prune-backups take it again

${UNDERLINE}Options:${END}
  --reason <reason>           manual | scheduled | pre-update | pre-restore | incident
                              (default: manual)
  --retention <policy>        prunable | pinned (default: prunable)

${UNDERLINE}Examples:${END}
  $self create-backup
  $self create-backup --reason incident --retention pinned
  $self backups
  $self backups --json
  $self restore-backup factorio-01-20260731T142233Z-a3f9c1
  $self pin-backup factorio-01-20260731T142233Z-a3f9c1
"
}

function show_usage_check_update() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Check-Update Command${END}

Check whether a newer version is available without applying it. Prints the
latest version to stdout when an update is available; prints nothing when the
instance is already current.

${UNDERLINE}Usage:${END}
  $self check-update

${UNDERLINE}Examples:${END}
  $self check-update
"
}

function show_usage_download() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Download Command${END}

Download game server files (pulls docker images if applicable).

${UNDERLINE}Usage:${END}
  $self download [version]

${UNDERLINE}Arguments:${END}
  version                     Specific version to download (optional)

${UNDERLINE}Examples:${END}
  $self download
  $self download 1.2.3
"
}

function show_usage_update() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Update Command${END}

Update the game server to the latest version (pulls updated docker images).

${UNDERLINE}Usage:${END}
  $self update

${UNDERLINE}Examples:${END}
  $self update
"
}

function _cmd_help() {
  if [[ -z "${1:-}" ]]; then
    show_usage
    return $EC_SUCCESS
  fi

  case "$1" in
  start)
    show_usage_start
    ;;
  stop)
    show_usage_stop
    ;;
  restart)
    show_usage_restart
    ;;
  attach)
    show_usage_attach
    ;;
  status)
    show_usage_status
    ;;
  logs)
    show_usage_logs
    ;;
  version)
    show_usage_version
    ;;
  backup | backups | create-backup | restore-backup | pin-backup | unpin-backup)
    show_usage_backup
    ;;
  check-update)
    show_usage_check_update
    ;;
  download)
    show_usage_download
    ;;
  deploy)
    show_usage_download
    ;;
  update)
    show_usage_update
    ;;
  kick | ban | unban)
    show_usage_moderation
    ;;
  kill | save | input | is-active)
    show_usage
    ;;
  *)
    __print_error "Unknown command: $1"
    __print_error "Use '$self help' for available commands"
    return $EC_INVALID_ARG
    ;;
  esac
  return $EC_SUCCESS
}

