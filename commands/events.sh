#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Disabling SC2254:
# Exit code variables are guaranteed to be numeric and safe as case patterns.
# shellcheck disable=SC2254

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load events logic library
logic_library=$(__find_command_handler events.sh)

# shellcheck source=handlers/events.sh
source "$logic_library" || {
  __print_error "Failed to load events logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Event System Management for Krystal Game Server Manager${END}

Manages KGSM's event broadcasting system with support for multiple transport methods.

${UNDERLINE}Usage:${END}
  ${self} <command> [arguments] [options]

${UNDERLINE}Commands:${END}
  status                      Show comprehensive event system status
  journal <command>           Inspect and prune the event journal
  test <transport>            Test event transports (all, webhook)
  webhook <command>           Manage HTTP webhook transport
  emit <event-type> [params]  Emit specific event with parameters
  help [command]              Show help information

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  --debug                     Enable debug output

${UNDERLINE}Examples:${END}
  ${self} status
  ${self} test all
  ${self} webhook configure
  ${self} emit server.install.created myserver factorio
  ${self} emit server.updated myserver 1.0.0 1.1.0
  ${self} help emit

${UNDERLINE}Notes:${END}
  • Events are always appended to the journal; the webhook is an optional copy
  • Use 'status' to verify system health after configuration changes
  • Transport-specific help: ${self} webhook help
  • Event types are dotted names (server.installed, server.started, etc.)
  • All events include timestamp, actor, hostname, and KGSM version metadata
  • Actor (who triggered the event) comes from \$KGSM_EVENT_ACTOR as 'provider:name';
    an event nobody claimed is recorded with no actor
"
}

function usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Show Event System Status${END}

Displays comprehensive status of the KGSM event system including all configured
transports, their current state, and health information.

${UNDERLINE}Usage:${END}
  ${self} status

${UNDERLINE}Description:${END}
The status command aggregates information from all event transports:
  • Webhook transport: Configured URLs, authentication status, connectivity

No configuration changes are made by this command.

${UNDERLINE}Examples:${END}
  ${self} status
"
}

function usage_test() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Test Event Transports${END}

Tests event transport functionality by sending test events and verifying delivery.

${UNDERLINE}Usage:${END}
  ${self} test <transport>

${UNDERLINE}Arguments:${END}
  transport                   Which transport(s) to test
                              Options: all, webhook

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
The test command validates that configured event transports are functional:
  • Webhook: Sends test event to configured URLs, checks responses
  • All: Tests all enabled transports sequentially

Only enabled transports are tested. If no transports are enabled, the command
will report an error.

${UNDERLINE}Examples:${END}
  ${self} test all
  ${self} test webhook
"
}

function usage_emit() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Emit Event${END}

Emits a specific event type with the required parameters to all enabled transports.

${UNDERLINE}Usage:${END}
  ${self} emit <event-type> [parameters...]

${UNDERLINE}Arguments:${END}
  event-type                  The type of event to emit (a dotted name)
  parameters                  Event-specific parameters (varies by type)

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Event Types and Parameters:${END}

Names are grouped by their own first segment, and that hierarchy is what a
reader keys on — a surface picks an icon from the namespace rather than from a
list of every event there is.

${UNDERLINE}Server run state:${END}
  server.started <instance>
  server.ready <instance>
  server.stopped <instance>
  server.restarted <instance>
  server.crashed <instance> <exit_code> <restarts>
  server.crash.exhausted <instance> <exit_code> <restarts>
  server.stop.started <instance>
  server.stop.finished <instance>
  server.restart.started <instance>
  server.restart.stopped <instance>
  server.restart.finished <instance>

  A crash is a run that ended by itself with a restart coming; crash.exhausted
  is the supervisor giving up on it.

${UNDERLINE}Server installation:${END}
  server.installed <instance> <blueprint> <library>
  server.install.started <instance> [blueprint]
  server.install.finished <instance> [blueprint]
  server.install.created <instance> [blueprint]
  server.install.directories_created <instance>
  server.install.files_created <instance>
  server.download.started <instance>
  server.download.finished <instance>
  server.download.completed <instance>
  server.download.failed <instance>
  server.deploy.started <instance>
  server.deploy.finished <instance>
  server.deploy.completed <instance>
  server.deploy.failed <instance>

  <library> is the name of the library the install landed in.

${UNDERLINE}Server updates:${END}
  server.updated <instance> <old_version> <new_version>
  server.update.available <instance> <current_version> <latest_version>
  server.update.started <instance>
  server.update.finished <instance>
  server.update.completed <instance>
  server.update.failed <instance>

  An update run ends without the version moving in two ways — it found nothing
  to do, or it could not do it — so server.update.failed is what separates a
  refusal from a completed run.

${UNDERLINE}Server placement and identity:${END}
  server.moved <instance> <from_library> <to_library>
  server.renamed <instance> <old_display_name> <new_display_name>

  A rename carries both labels, because a label exists to be shown; the
  instance id is unchanged by it and is what a consumer keys on.

${UNDERLINE}Server removal:${END}
  server.uninstalled <instance>
  server.uninstall.started <instance>
  server.uninstall.finished <instance>
  server.uninstall.failed <instance>
  server.uninstall.files_removed <instance>
  server.uninstall.directories_removed <instance>
  server.uninstall.removed <instance>

${UNDERLINE}Backups:${END}
  backup.created <instance> <source> <version>
  backup.restored <instance> <source> <version>
  backup.deleted <instance> <source>
  backup.pinned <instance> <source>
  backup.unpinned <instance> <source>
  backup.pruned <instance> <deleted> <kept> <pinned>
  backup.started <instance>
  backup.finished <instance>
  backup.restore.started <instance>
  backup.restore.finished <instance>

  <source> is the backup id. A delete, a pin and an unpin each name one backup;
  a prune reports the whole sweep as counts — <deleted> is what was removed,
  <kept> the retention window it ran with, <pinned> how many it skipped because
  they were pinned.

${UNDERLINE}Networking:${END}
  network.ports.opened <instance> <ports>
  network.ports.closed <instance> <ports>
  network.upnp.opened <instance> <ports>
  network.upnp.closed <instance> <ports>
  network.upnp.reasserted <instance> <ports>

  <ports> is the instance's UFW-format spec and is carried as the canonical
  structured array. A host firewall rule and a router NAT forward are separate
  facts about separate machines, which is why they are separate names.

${UNDERLINE}Players:${END}
  player.joined <instance> [player_id] [player_name] [player_addr] [session_key]
  player.left <instance> [player_id] [player_name] [player_addr] [session_key] [reason]
  player.kicked <instance> <target> <command>
  player.banned <instance> <target> <command>
  player.unbanned <instance> <target> <command>

  <target> is the identity token the operator supplied, carried verbatim —
  which kind of token it is was declared by the game's blueprint.

${UNDERLINE}Operator actions:${END}
  config.changed <instance> <key>
  console.input.sent <instance> <command>
  announcement.sent <instance> <message> <command>

  A config change carries the key alone — never the value, which may be a
  secret. Console input carries the command in full on purpose: the trail's
  value is recording exactly what was run. An announcement carries what a
  person wrote alongside the console command that delivered it.

${UNDERLINE}Blueprints:${END}
  blueprint.created <blueprint> <tier> <overrides_system> [runtime]
  blueprint.updated <blueprint> <tier> <overrides_system> [runtime]
  blueprint.removed <blueprint> <tier> <reverted_to_system>

  These take a blueprint name, not an instance name, and carry it as
  Data.BlueprintName. The file contents are never carried.

${UNDERLINE}Libraries:${END}
  library.added <name> <path>
  library.removed <name> <path>

  A library is a placement root — a named disk instances live on. No instance
  is involved.

${UNDERLINE}Description:${END}
Events are broadcast to all enabled transports in parallel. The JSON payload
includes the event type, event-specific data, timestamp, actor, hostname, and
KGSM version.

It also carries how much the event matters ('info', 'warn' or 'danger'), how it
went ('success', 'failure' or 'neutral') and one line of prose saying what
happened. Those three are what lets a surface render an event it has never
heard of; a phase bracket has no prose to give and carries none rather than an
empty line.

The actor (who triggered the event) is taken from the \$KGSM_EVENT_ACTOR
environment variable, which the caller (bot/assistant/watchdog/API) sets to the
principal it is acting for, written 'provider:name'. An invocation that sets
nothing has no actor and the event records without one: KGSM never fabricates an
identity, and the OS user it runs as owns the process rather than asking for the
action. A value that is not 'provider:name' is refused the same way, with a
warning, because no reader could resolve it.

Optional parameters (shown in brackets) can be omitted or left as empty strings.

${UNDERLINE}Examples:${END}
  ${self} emit server.install.created myserver factorio
  ${self} emit server.installed myserver factorio ssd
  ${self} emit server.moved myserver ssd archive
  ${self} emit server.started myserver
  ${self} emit server.updated myserver 1.0.0 1.1.1
  ${self} emit backup.created myserver auto 1.2.3
  ${self} emit backup.deleted myserver myserver-20260731T142233Z-a3f9c1
  ${self} emit backup.pruned myserver 3 5 1
  ${self} emit backup.pinned myserver myserver-20260731T142233Z-a3f9c1
  ${self} emit server.stopped myserver manual
  ${self} emit network.ports.opened myserver '34197/udp|27015:27020/tcp'
  ${self} emit network.ports.closed myserver '34197/udp|27015:27020/tcp'
  ${self} emit player.joined myserver 76561198000000000 Alice
  ${self} emit player.left myserver '' Bob
  ${self} emit config.changed myserver rcon_password
  ${self} emit server.renamed myserver myserver 'Weekend Server'
  ${self} emit blueprint.created mygame user false native
  ${self} emit blueprint.updated terraria user true native
  ${self} emit blueprint.removed terraria user true
"
}

# Show comprehensive event system status
function _cmd_status() {
  local BOLD="\e[1m"
  local END="\e[0m"

  echo -e "${BOLD}KGSM Event System Status${END}"
  echo "=========================="
  echo ""

  # Delegate to transport modules
  events.webhook.sh status

  return $EC_SUCCESS
}

# Test event transports
function _cmd_test() {
  local transport="$1"

  if [[ -z "$transport" ]]; then
    __print_error "Transport argument required: all or webhook"
    usage_test
    return $EC_MISSING_ARG
  fi

  case "$transport" in
    -h | --help | help)
      usage_test
      return $EC_SUCCESS
      ;;
    all)
      # shellcheck disable=SC2154
      local webhook_enabled="$config_enable_webhook_events"
      local overall_result=0

      __print_info "Testing all configured event transports..."
      echo ""

      if [[ "$webhook_enabled" == "true" ]]; then
        if events.webhook.sh test; then
          __print_success "Webhook transport: PASSED"
        else
          __print_error "Webhook transport: FAILED"
          overall_result=1
        fi
        echo ""
      fi

      if [[ "$webhook_enabled" != "true" ]]; then
        __print_error "No optional event transports are enabled"
        __print_info "Enable one with: ${self} webhook enable"
        __print_info "The journal is always written; inspect it with: ${self} journal status"
        return $EC_ERROR
      fi

      if [[ $overall_result -eq 0 ]]; then
        __print_success "All active transports passed testing"
      else
        __print_error "One or more transport tests failed"
      fi

      return $overall_result
      ;;
    webhook)
      events.webhook.sh test
      return $?
      ;;
    *)
      __print_error "Unknown transport: $transport"
      __print_info "Valid options: all, webhook"
      return $EC_INVALID_ARG
      ;;
  esac
}

# Delegate to webhook transport module
function _cmd_webhook() {
  events.webhook.sh "$@"
  return $?
}

# Delegate to the journal module
function _cmd_journal() {
  events.journal.sh "$@"
  return $?
}

# Emit event
#
# The I/O half of emission: help, then the diagnostics for whichever stage
# __logic_emit_event reports as failed. The emission itself — validation,
# payload, journal append, optional transports — lives in the handler so this
# path and core/events.sh's exit-code dispatch share one implementation.
function _cmd_emit() {
  local event_type="$1"
  shift
  local params=("$@")

  if [[ -z "$event_type" ]]; then
    __print_error "Event type is required"
    usage_emit
    return $EC_MISSING_ARG
  fi

  if [[ "$event_type" == "-h" || "$event_type" == "--help" || "$event_type" == "help" ]]; then
    usage_emit
    return $EC_SUCCESS
  fi

  local _result=$EC_SUCCESS
  __logic_emit_event "$event_type" "${params[@]}" || _result=$?

  case $_result in
    $EC_SUCCESS)
      return $EC_SUCCESS
      ;;
    $EC_EVENT_TYPE_INVALID)
      __print_error "Invalid event type: $event_type"
      __print_info "Use '${self} help emit' to see all available event types"
      ;;
    $EC_EVENT_PARAMS_INVALID)
      local param_spec
      param_spec=$(__logic_get_event_param_spec "$event_type")
      __print_error "Invalid parameters for event '$event_type'"
      __print_info "Required parameters: $param_spec"
      ;;
    $EC_EVENT_JSON_FAILED)
      __print_error "Failed to generate event payload"
      ;;
    $EC_EVENT_JOURNAL_FAILED)
      __print_error "Failed to append the event to the journal at $(__logic_journal_dir)"
      ;;
    *)
      __print_error "Failed to emit event '$event_type'"
      ;;
  esac

  return $_result
}

# Help command
function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return $EC_SUCCESS
  fi

  case "$command" in
    status)
      usage_status
      ;;
    test)
      usage_test
      ;;
    emit)
      usage_emit
      ;;
    webhook)
      events.webhook.sh help
      ;;
    *)
      __print_error "Unknown command: $command"
      show_usage
      return $EC_INVALID_ARG
      ;;
  esac

  return $EC_SUCCESS
}

# Parse command
command="${1:-}"
shift 2> /dev/null || true

# Route to command handlers
case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  -h | --help | help)
    _cmd_help "$@"
    exit $?
    ;;
  status)
    _cmd_status "$@"
    exit $?
    ;;
  test)
    _cmd_test "$@"
    exit $?
    ;;
  webhook)
    _cmd_webhook "$@"
    exit $?
    ;;
  journal)
    _cmd_journal "$@"
    exit $?
    ;;
  emit)
    _cmd_emit "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
