#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Disabling SC2016:
# jq syntax uses single quotes intentionally for variable interpolation
# shellcheck disable=SC2016

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
  test <transport>            Test event transports (all, socket, webhook)
  socket <command>            Manage Unix Domain Socket transport
  webhook <command>           Manage HTTP webhook transport
  emit <event-type> [params]  Emit specific event with parameters
  help [command]              Show help information

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  --debug                     Enable debug output

${UNDERLINE}Examples:${END}
  ${self} status
  ${self} test all
  ${self} socket enable
  ${self} webhook configure
  ${self} emit instance-created myserver factorio
  ${self} emit instance-version-updated myserver 1.0.0 1.1.0
  ${self} help emit

${UNDERLINE}Notes:${END}
  • Multiple transports can be enabled simultaneously
  • Each transport has independent configuration and testing
  • Use 'status' to verify system health after configuration changes
  • Transport-specific help: ${self} socket help or ${self} webhook help
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
  • Socket transport: Configuration, socket file status, dependencies
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
                              Options: all, socket, webhook

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
The test command validates that configured event transports are functional:
  • Socket: Creates listener, sends test event, verifies reception
  • Webhook: Sends test event to configured URLs, checks responses
  • All: Tests all enabled transports sequentially

Only enabled transports are tested. If no transports are enabled, the command
will report an error.

${UNDERLINE}Examples:${END}
  ${self} test all
  ${self} test socket
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
  instance-installed <instance> [blueprint]

${UNDERLINE}Instance Updates:${END}
  instance-update-started <instance>
  instance-update-finished <instance>
  instance-updated <instance>
  instance-version-updated <instance> <old_version> <new_version>

${UNDERLINE}Instance Backups:${END}
  instance-backup-created <instance> <source> <version>
  instance-backup-restored <instance> <source> <version>

${UNDERLINE}Player Presence:${END}
  instance-player-joined <instance> [player_id] [player_name]
  instance-player-left <instance> [player_id] [player_name]

${UNDERLINE}Instance Removal:${END}
  instance-files-removed <instance>
  instance-directories-removed <instance>
  instance-uninstall-started <instance>
  instance-uninstall-finished <instance>
  instance-uninstalled <instance>

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
  ${self} emit instance-started myserver
  ${self} emit instance-version-updated myserver 1.0.0 1.1.1
  ${self} emit instance-backup-created myserver auto 1.2.3
  ${self} emit instance-stopped myserver manual
  ${self} emit instance-ports-opened myserver '34197/udp|27015:27020/tcp'
  ${self} emit instance-ports-closed myserver '34197/udp|27015:27020/tcp'
  ${self} emit instance-player-joined myserver 76561198000000000 Alice
  ${self} emit instance-player-left myserver '' Bob
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
  events.socket.sh status
  echo ""
  events.webhook.sh status

  return $EC_SUCCESS
}

# Test event transports
function _cmd_test() {
  local transport="$1"

  if [[ -z "$transport" ]]; then
    __print_error "Transport argument required: all, socket, or webhook"
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
      local socket_enabled="$config_enable_event_broadcasting"
      # shellcheck disable=SC2154
      local webhook_enabled="$config_enable_webhook_events"
      local overall_result=0

      __print_info "Testing all configured event transports..."
      echo ""

      if [[ "$socket_enabled" == "true" ]]; then
        if events.socket.sh test; then
          __print_success "Socket transport: PASSED"
        else
          __print_error "Socket transport: FAILED"
          overall_result=1
        fi
        echo ""
      fi

      if [[ "$webhook_enabled" == "true" ]]; then
        if events.webhook.sh test; then
          __print_success "Webhook transport: PASSED"
        else
          __print_error "Webhook transport: FAILED"
          overall_result=1
        fi
        echo ""
      fi

      if [[ "$socket_enabled" != "true" && "$webhook_enabled" != "true" ]]; then
        __print_error "No event transports are enabled"
        __print_info "Enable transports with: ${self} socket enable OR ${self} webhook enable"
        return $EC_ERROR
      fi

      if [[ $overall_result -eq 0 ]]; then
        __print_success "All active transports passed testing"
      else
        __print_error "One or more transport tests failed"
      fi

      return $overall_result
      ;;
    socket)
      events.socket.sh test
      return $?
      ;;
    webhook)
      events.webhook.sh test
      return $?
      ;;
    *)
      __print_error "Unknown transport: $transport"
      __print_info "Valid options: all, socket, webhook"
      return $EC_INVALID_ARG
      ;;
  esac
}

# Delegate to socket transport module
function _cmd_socket() {
  events.socket.sh "$@"
  return $?
}

# Delegate to webhook transport module
function _cmd_webhook() {
  events.webhook.sh "$@"
  return $?
}

# Build JSON event payload
# Args: $1 = event_type, $2... = parameters
# Returns: echoes JSON payload or returns error code
function _build_event_payload() {
  local event_type="$1"
  shift
  local params=("$@")

  # Get required parameters specification
  local required_params=(${EVENT_CONFIGS[$event_type]})
  local param_names=()

  # Build parameter arrays for jq
  for i in "${!required_params[@]}"; do
    local param_name="${required_params[$i]}"
    local param_value="${params[$i]:-}"

    param_names+=("--arg" "$param_name" "$param_value")
  done

  # Resolve the actor (who triggered this event) for audit/correlation downstream.
  # KGSM is a stateless, multi-entrypoint CLI: it cannot itself know the semantic
  # principal, so the caller (bot/assistant/watchdog) supplies it via KGSM_EVENT_ACTOR.
  # For a bare CLI invocation that sets nothing, fall back to the OS user — an honest
  # "who ran this", never a fabricated identity.
  local actor="${KGSM_EVENT_ACTOR:-}"
  if [[ -z "$actor" ]]; then
    actor="${SUDO_USER:-${USER:-}}"
  fi
  if [[ -z "$actor" ]]; then
    actor="$(id -un 2>/dev/null || echo "system")"
  fi

  # Resolve the origin: the surface that drove this event
  # (ui|assistant|discord|system|api), the companion to the actor for downstream
  # audit/correlation. The caller (bot/assistant/watchdog/API) supplies it via
  # KGSM_EVENT_ORIGIN. Unlike the actor there is NO honest fallback — a bare CLI
  # invocation has no product surface — so an unset origin stays empty and is
  # emitted as JSON null below, never a fabricated surface.
  local origin="${KGSM_EVENT_ORIGIN:-}"

  # Generate JSON payload
  local jq_args=("${param_names[@]}"
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    --arg actor "$actor"
    --arg origin "$origin"
    --arg hostname "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "${HOSTNAME:-localhost}")"
    --arg kgsm_version "$(${KGSM_ROOT}/installer.sh --version 2>/dev/null || echo 'unknown')")

  # Build data object based on event type
  local data_object=""
  case "$event_type" in
    "$EVENT_INSTANCE_CREATED" | "$EVENT_INSTANCE_INSTALLATION_STARTED" | "$EVENT_INSTANCE_INSTALLATION_FINISHED" | "$EVENT_INSTANCE_INSTALLED")
      data_object='{
        InstanceName: $instance,
        Blueprint: $blueprint
      }'
      ;;
    "$EVENT_INSTANCE_VERSION_UPDATED")
      data_object='{
        InstanceName: $instance,
        OldVersion: $old_version,
        NewVersion: $new_version
      }'
      ;;
    "$EVENT_INSTANCE_BACKUP_CREATED" | "$EVENT_INSTANCE_BACKUP_RESTORED")
      data_object='{
        InstanceName: $instance,
        Source: $source,
        Version: $version
      }'
      ;;
    "$EVENT_INSTANCE_STARTED" | "$EVENT_INSTANCE_STOPPED" | "$EVENT_INSTANCE_RESTARTED")
      data_object='{
        InstanceName: $instance
      }'
      ;;
    "$EVENT_INSTANCE_CRASHED" | "$EVENT_INSTANCE_FAILED")
      data_object='{
        InstanceName: $instance,
        ExitCode: $exit_code,
        Restarts: $restarts
      }'
      ;;
    "$EVENT_INSTANCE_PORTS_OPENED" | "$EVENT_INSTANCE_PORTS_CLOSED" | "$EVENT_INSTANCE_UPNP_OPENED" | "$EVENT_INSTANCE_UPNP_CLOSED")
      # The `ports` param is the UFW-format spec; surface it as the canonical
      # structured array [{start,end,protocol}] — the same shape `instances
      # info --json` emits — never the opaque UFW string. Converted here and
      # passed via --argjson (the one non-string Data field in this builder).
      # Shared by the firewall (instance_ports_*) and UPnP (instance_upnp_*)
      # events — both carry the same structured Ports payload; the event TYPE
      # distinguishes router NAT forward from host ufw rule downstream.
      local ports_json
      ports_json="$(__ufw_ports_to_json "${params[1]:-}")" || ports_json="[]"
      jq_args+=(--argjson ports_json "$ports_json")
      data_object='{
        InstanceName: $instance,
        Ports: $ports_json
      }'
      ;;
    "$EVENT_INSTANCE_PLAYER_JOINED" | "$EVENT_INSTANCE_PLAYER_LEFT")
      # player_id/player_name are NULLABLE and are NOT in the EVENT_CONFIGS spec
      # (only `instance` is required), so they are read positionally here rather
      # than through param_names. An absent/empty value renders as JSON null —
      # the same honest-null rule used for Origin — never an empty string posing
      # as a real id/name. The at-least-one-non-null guarantee belongs to the
      # emitting shim, not to KGSM (a faithful emitter).
      jq_args+=(--arg player_id "${params[1]:-}"
        --arg player_name "${params[2]:-}")
      data_object='{
        InstanceName: $instance,
        PlayerId: ($player_id | if . == "" then null else . end),
        PlayerName: ($player_name | if . == "" then null else . end)
      }'
      ;;
    *)
      data_object='{
        InstanceName: $instance
      }'
      ;;
  esac

  local payload
  if ! payload=$(jq -n "${jq_args[@]}" "{
    EventType: \"$event_type\",
    Data: $data_object,
    Timestamp: \$timestamp,
    Actor: \$actor,
    Origin: (\$origin | if . == \"\" then null else . end),
    Hostname: \$hostname,
    KGSMVersion: \$kgsm_version
  }"); then
    return $EC_EVENT_JSON_FAILED
  fi

  echo "$payload"
  return $EC_SUCCESS
}

# Delegate event payload to all enabled transports
# Args: $1 = payload (JSON string)
# Returns: EC_SUCCESS on success, EC_EVENT_TRANSPORT_FAILED if all fail
function _delegate_to_transports() {
  local payload="$1"
  local any_success=false

  # Delegate to transport modules in parallel
  # shellcheck disable=SC2154
  if [[ "$config_enable_socket_events" == "true" ]]; then
    events.socket.sh emit "$payload" &
    any_success=true
  fi

  # shellcheck disable=SC2154
  if [[ "$config_enable_webhook_events" == "true" ]]; then
    events.webhook.sh emit "$payload" &
    any_success=true
  fi

  # Wait for all background jobs
  wait

  if [[ "$any_success" != "true" ]]; then
    return $EC_EVENT_TRANSPORT_FAILED
  fi

  return $EC_SUCCESS
}

# Emit event
function _cmd_emit() {
  local event_name="$1"
  shift
  local params=("$@")

  # If event broadcasting is disabled, exit early
  if [[ "${config_enable_event_broadcasting:-false}" != "true" ]]; then
    return $EC_SUCCESS
  fi

  if [[ -z "$event_name" ]]; then
    __print_error "Event type is required"
    usage_emit
    return $EC_MISSING_ARG
  fi

  if [[ "$event_name" == "-h" || "$event_name" == "--help" || "$event_name" == "help" ]]; then
    usage_emit
    return $EC_SUCCESS
  fi

  # Convert dash-separated name to underscore type
  local event_type
  if ! event_type=$(__logic_event_name_to_type "$event_name"); then
    __print_error "Invalid event type: $event_name"
    __print_info "Use '${self} help emit' to see all available event types"
    return $EC_EVENT_TYPE_INVALID
  fi

  # Validate parameters
  if ! __logic_validate_event_params "$event_type" "${params[@]}"; then
    local param_spec
    param_spec=$(__logic_get_event_param_spec "$event_type")
    __print_error "Invalid parameters for event '$event_name'"
    __print_info "Required parameters: $param_spec"
    return $EC_EVENT_PARAMS_INVALID
  fi

  # Build payload
  local payload
  if ! payload=$(_build_event_payload "$event_type" "${params[@]}"); then
    __print_error "Failed to generate event payload"
    return $EC_EVENT_JSON_FAILED
  fi

  # Delegate to transports
  if ! _delegate_to_transports "$payload"; then
    __print_error "Failed to emit event to any transport"
    return $EC_EVENT_TRANSPORT_FAILED
  fi

  return $EC_SUCCESS
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
    socket)
      events.socket.sh help
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
  socket)
    _cmd_socket "$@"
    exit $?
    ;;
  webhook)
    _cmd_webhook "$@"
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
