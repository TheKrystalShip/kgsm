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
  ${self} emit instance-created myserver factorio
  ${self} emit instance-version-updated myserver 1.0.0 1.1.0
  ${self} help emit

${UNDERLINE}Notes:${END}
  • Events are always appended to the journal; the webhook is an optional copy
  • Use 'status' to verify system health after configuration changes
  • Transport-specific help: ${self} webhook help
  • Event types use dash-separated names (instance-created, instance-started, etc.)
  • All events include timestamp, actor, hostname, and KGSM version metadata
  • Actor (who triggered the event) comes from \$KGSM_EVENT_ACTOR, else the OS user
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
  event-type                  The type of event to emit (dash-separated)
  parameters                  Event-specific parameters (varies by type)

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Event Types and Parameters:${END}

${UNDERLINE}Instance Lifecycle:${END}
  instance-created <instance> [blueprint]
  instance-started <instance>
  instance-stopped <instance>
  instance-removed <instance>
  instance-ready <instance>

${UNDERLINE}Instance Configuration:${END}
  instance-config-changed <instance> <key>
  instance-display-name-changed <instance> <old_display_name> <new_display_name>

  A config change carries the key alone — never the value, which may be a
  secret. A display-name change carries both labels, because a label exists to
  be shown.

${UNDERLINE}Instance Creation Process:${END}
  instance-directories-created <instance>
  instance-files-created <instance>
  instance-download-started <instance>
  instance-download-finished <instance>
  instance-downloaded <instance>
  instance-deploy-started <instance>
  instance-deploy-finished <instance>
  instance-deployed <instance>

${UNDERLINE}Instance Installation:${END}
  instance-installation-started <instance> [blueprint]
  instance-installation-finished <instance> [blueprint]
  instance-installed <instance> <blueprint> <library>

  <library> is the name of the library the install landed in.

${UNDERLINE}Instance Placement:${END}
  instance-moved <instance> <from_library> <to_library>

${UNDERLINE}Instance Updates:${END}
  instance-update-started <instance>
  instance-update-finished <instance>
  instance-updated <instance>
  instance-version-updated <instance> <old_version> <new_version>

${UNDERLINE}Instance Backups:${END}
  instance-backup-created <instance> <source> <version>
  instance-backup-restored <instance> <source> <version>
  instance-backup-deleted <instance> <source>
  instance-backup-pinned <instance> <source>
  instance-backup-unpinned <instance> <source>
  instance-backups-pruned <instance> <deleted> <kept> <pinned>

  <source> is the backup id. A delete, a pin and an unpin each name one backup;
  a prune reports the whole sweep as counts — <deleted> is what was removed,
  <kept> the retention window it ran with, <pinned> how many it skipped because
  they were pinned.

${UNDERLINE}Player Presence:${END}
  instance-player-joined <instance> [player_id] [player_name]
  instance-player-left <instance> [player_id] [player_name]

${UNDERLINE}Instance Removal:${END}
  instance-files-removed <instance>
  instance-directories-removed <instance>
  instance-uninstall-started <instance>
  instance-uninstall-finished <instance>
  instance-uninstalled <instance>

${UNDERLINE}Blueprints:${END}
  blueprint-created <blueprint> <tier> <overrides_system> [runtime]
  blueprint-updated <blueprint> <tier> <overrides_system> [runtime]
  blueprint-removed <blueprint> <tier> <reverted_to_system>

  These take a blueprint name, not an instance name, and carry it as
  Data.BlueprintName. The file contents are never carried.

${UNDERLINE}Description:${END}
Events are broadcast to all enabled transports in parallel. The JSON payload
includes the event type, event-specific data, timestamp, actor, hostname, and
KGSM version.

The actor (who triggered the event) is taken from the \$KGSM_EVENT_ACTOR
environment variable when set — the caller (bot/assistant/watchdog) supplies the
principal — otherwise it falls back to the invoking OS user. KGSM never fabricates
an identity.

Optional parameters (shown in brackets) can be omitted or left as empty strings.

${UNDERLINE}Examples:${END}
  ${self} emit instance-created myserver factorio
  ${self} emit instance-installed myserver factorio ssd
  ${self} emit instance-moved myserver ssd archive
  ${self} emit instance-started myserver
  ${self} emit instance-version-updated myserver 1.0.0 1.1.1
  ${self} emit instance-backup-created myserver auto 1.2.3
  ${self} emit instance-backup-deleted myserver myserver-20260731T142233Z-a3f9c1
  ${self} emit instance-backups-pruned myserver 3 5 1
  ${self} emit instance-backup-pinned myserver myserver-20260731T142233Z-a3f9c1
  ${self} emit instance-stopped myserver manual
  ${self} emit instance-ports-opened myserver '34197/udp|27015:27020/tcp'
  ${self} emit instance-ports-closed myserver '34197/udp|27015:27020/tcp'
  ${self} emit instance-player-joined myserver 76561198000000000 Alice
  ${self} emit instance-player-left myserver '' Bob
  ${self} emit instance-config-changed myserver rcon_password
  ${self} emit instance-display-name-changed myserver myserver 'Weekend Server'
  ${self} emit blueprint-created mygame user false native
  ${self} emit blueprint-updated terraria user true native
  ${self} emit blueprint-removed terraria user true
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
  local event_name="$1"
  shift
  local params=("$@")

  if [[ -z "$event_name" ]]; then
    __print_error "Event type is required"
    usage_emit
    return $EC_MISSING_ARG
  fi

  if [[ "$event_name" == "-h" || "$event_name" == "--help" || "$event_name" == "help" ]]; then
    usage_emit
    return $EC_SUCCESS
  fi

  local _result=$EC_SUCCESS
  __logic_emit_event "$event_name" "${params[@]}" || _result=$?

  case $_result in
    $EC_SUCCESS)
      return $EC_SUCCESS
      ;;
    $EC_EVENT_TYPE_INVALID)
      __print_error "Invalid event type: $event_name"
      __print_info "Use '${self} help emit' to see all available event types"
      ;;
    $EC_EVENT_PARAMS_INVALID)
      local param_spec
      param_spec=$(__logic_get_event_param_spec \
        "$(__logic_event_name_to_type "$event_name")")
      __print_error "Invalid parameters for event '$event_name'"
      __print_info "Required parameters: $param_spec"
      ;;
    $EC_EVENT_JSON_FAILED)
      __print_error "Failed to generate event payload"
      ;;
    $EC_EVENT_JOURNAL_FAILED)
      __print_error "Failed to append the event to the journal at $(__logic_journal_dir)"
      ;;
    *)
      __print_error "Failed to emit event '$event_name'"
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
