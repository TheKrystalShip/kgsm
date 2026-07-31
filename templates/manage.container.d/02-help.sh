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

${BOLD}${UNDERLINE}Version & Update Commands:${END}
  version [--latest|--compare|--save <ver>]  Version management
  check-update                Check whether a newer version is available
  download [version]          Download game server files
  deploy                      Deploy files from temp directory
  update                      Update to latest version

${BOLD}${UNDERLINE}Backup Commands:${END}
  backups [--json]            List available backups
  create-backup               Create a backup
  restore-backup <id>         Restore the backup with this id

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
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  $self version
  $self version --latest
  $self version --compare
  $self version --save 1.2.3
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

${UNDERLINE}Usage:${END}
  $self backups [--json]
  $self create-backup
  $self restore-backup <id>

${UNDERLINE}Commands:${END}
  backups [--json]            List backup ids, newest first (--json: full manifests)
  create-backup               Create a backup of the current server files
  restore-backup <id>         Restore from the backup with this id

${UNDERLINE}Examples:${END}
  $self create-backup
  $self backups
  $self backups --json
  $self restore-backup factorio-01-20260731T142233Z-a3f9c1
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
  backup | backups | create-backup | restore-backup)
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

