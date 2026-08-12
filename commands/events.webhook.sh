#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}HTTP Webhook Event Transport for Krystal Game Server Manager${END}

Manages HTTP webhook event delivery for remote system integration and monitoring.

${UNDERLINE}Usage:${END}
  ${self} <command> [options]

${UNDERLINE}Commands:${END}
  enable                      Enable HTTP webhook event transport
  disable                     Disable HTTP webhook event transport
  configure                   Interactive webhook configuration wizard
  test                        Test webhook functionality
  status                      Show webhook transport status
  emit <payload>              Emit event to webhook (internal use)
  help [command]              Show help information

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  --debug                     Enable debug output

${UNDERLINE}Examples:${END}
  ${self} configure
  ${self} enable
  ${self} test
  ${self} status
  ${self} disable

${UNDERLINE}Notes:${END}
  • Webhook transport requires 'wget' for HTTP requests
  • Supports multiple webhook URLs for redundancy
  • Includes retry logic with exponential backoff
  • Optional HMAC-SHA256 signature verification
  • Use 'configure' for interactive setup
  • Use 'test' to verify connectivity
"
}

function usage_enable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Enable Webhook Transport${END}

Enables HTTP webhook event transport and validates dependencies.

${UNDERLINE}Usage:${END}
  ${self} enable

${UNDERLINE}Description:${END}
Activates webhook-based event delivery by:
  • Checking for required 'wget' dependency
  • Validating webhook URLs are configured
  • Updating KGSM configuration to enable webhook transport

Webhook URLs must be configured first using '${self} configure'.

${UNDERLINE}Examples:${END}
  ${self} enable
"
}

function usage_disable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Disable Webhook Transport${END}

Disables HTTP webhook event transport.

${UNDERLINE}Usage:${END}
  ${self} disable

${UNDERLINE}Description:${END}
Deactivates webhook-based event delivery by updating KGSM configuration.
Configuration settings (URLs, secrets) are preserved for future use.

${UNDERLINE}Examples:${END}
  ${self} disable
"
}

function usage_configure() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Configure Webhook Transport${END}

Interactive wizard for webhook configuration.

${UNDERLINE}Usage:${END}
  ${self} configure

${UNDERLINE}Description:${END}
Guides through webhook configuration including:
  • Webhook URLs (comma-separated for multiple endpoints)
  • Request timeout (1-300 seconds)
  • Retry count (0-5 attempts)
  • Authentication secret (optional HMAC-SHA256)

Configuration is saved to KGSM config file.

${UNDERLINE}Examples:${END}
  ${self} configure
"
}

function usage_test() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Test Webhook Transport${END}

Tests webhook functionality by sending a test event to configured endpoints.

${UNDERLINE}Usage:${END}
  ${self} test

${UNDERLINE}Description:${END}
Validates webhook transport by:
  • Sending test event to all configured URLs
  • Verifying HTTP responses
  • Testing retry logic if failures occur

Requires webhook transport to be enabled and URLs to be configured.

${UNDERLINE}Examples:${END}
  ${self} test
"
}

function usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Show Webhook Status${END}

Displays detailed webhook transport status information.

${UNDERLINE}Usage:${END}
  ${self} status

${UNDERLINE}Description:${END}
Shows webhook transport information including:
  • Configuration state (enabled/disabled)
  • Configured webhook URLs
  • Timeout and retry settings
  • Authentication status
  • Dependency status (wget availability)
  • Basic connectivity tests

${UNDERLINE}Examples:${END}
  ${self} status
"
}

# Core function: Send webhook event with retry logic
function __webhook_send() {
  local url="$1"
  local payload="$2"
  local retry_count="${3:-0}"
  local is_secondary="${4:-false}"

  # Validate inputs
  if [[ -z "$url" ]]; then
    __print_error "Webhook URL is required"
    return 1
  fi

  if [[ -z "$payload" ]]; then
    __print_error "Webhook payload is required"
    return 1
  fi

  # Check if wget is available
  if ! command -v wget >/dev/null 2>&1; then
    __print_error "wget is required for webhook events but is not installed"
    return 1
  fi

  # Prepare wget options
  local wget_opts=(
    --quiet
    --timeout "${config_webhook_timeout_seconds:-10}"
    --header "Content-Type: application/json"
    --header "User-Agent: KGSM/$KGSM_VERSION"
    --post-data "$payload"
  )

  # Add signature header if webhook secret is configured
  if [[ -n "$config_webhook_secret" ]]; then
    local signature
    if command -v openssl >/dev/null 2>&1; then
      signature=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$config_webhook_secret" | cut -d' ' -f2)
      wget_opts+=(--header "X-KGSM-Signature: sha256=$signature")
    else
      __print_warning "openssl not available, skipping signature generation"
    fi
  fi

  # Add timestamp and attempt headers
  wget_opts+=(--header "X-KGSM-Timestamp: $(date -u +%s)")
  wget_opts+=(--header "X-KGSM-Retry-Count: $retry_count")

  # Attempt the webhook request
  local webhook_result
  webhook_result=$(wget "${wget_opts[@]}" -O - "$url" 2>&1)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    # Success - log if not secondary webhook or if in test mode
    if [[ "$is_secondary" != "true" ]] || [[ -n "$WEBHOOK_TEST_MODE" ]]; then
      __print_info "Webhook event sent successfully to $url"
    fi
    return 0
  else
    # Failure - determine if we should retry
    local max_retries="${config_webhook_retry_count:-2}"
    if [[ $retry_count -lt $max_retries ]]; then
      local next_retry=$((retry_count + 1))
      local backoff_seconds=$((2 ** retry_count))
      __print_warning "Webhook request failed, retrying in ${backoff_seconds}s (attempt $next_retry/$max_retries)"
      sleep "$backoff_seconds"
      __webhook_send "$url" "$payload" "$next_retry" "$is_secondary"
      return $?
    else
      __print_error "Webhook request failed after $max_retries retries: $url"
      return 1
    fi
  fi
}

export -f __webhook_send

# Core function: Send event to webhook (used by commands/events.sh)
function __webhook_emit_event() {
  local payload="$1"

  if [[ -z "$payload" ]]; then
    __print_error "Event payload is required"
    return 1
  fi

  if [[ -z "$config_webhook_urls" ]]; then
    __print_error "Webhook URLs not configured"
    return 1
  fi

  # Convert comma-separated list to array
  IFS=',' read -ra webhook_list <<<"$config_webhook_urls"

  if [[ ${#webhook_list[@]} -eq 0 ]]; then
    __print_error "No webhook URLs configured"
    return 1
  fi

  local overall_result=0
  local pids=()

  # Send to all webhooks in parallel
  for webhook_url in "${webhook_list[@]}"; do
    webhook_url=$(echo "$webhook_url" | xargs)
    if [[ -n "$webhook_url" ]]; then
      __webhook_send "$webhook_url" "$payload" 0 false &
      pids+=($!)
    fi
  done

  # Wait for all webhooks to complete
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      overall_result=1
    fi
  done

  return $overall_result
}

export -f __webhook_emit_event

# Enable webhook transport
function _cmd_enable() {
  if [[ "$1" == "--help" ]]; then
    usage_enable
    return $EC_SUCCESS
  fi

  __print_info "Enabling HTTP webhook event transport..."

  # Check dependencies
  if ! command -v wget >/dev/null 2>&1; then
    __print_error "wget is required but not installed"
    __print_error "Install wget: sudo apt-get install wget (Ubuntu/Debian) or sudo yum install wget (RHEL/CentOS)"
    return $EC_MISSING_DEPENDENCY
  fi

  # Check if webhook URLs are configured
  if [[ -z "$config_webhook_urls" ]]; then
    __print_warning "No webhook URLs configured"
    __print_info "Run '${self} configure' to set up webhook endpoints"
    __print_info "Or manually set webhook_urls in configuration"
  fi

  # Enable in configuration
  __set_config_value "enable_webhook_events" "true"
  local result=$?
  if [[ $result -eq 0 ]]; then
    __print_success "HTTP webhook event transport enabled"

    if [[ -n "$config_webhook_urls" ]]; then
      IFS=',' read -ra webhook_list <<<"$config_webhook_urls"
      if [[ ${#webhook_list[@]} -eq 1 ]]; then
        __print_info "Webhook URL: ${webhook_list[0]// /}"
      else
        __print_info "Webhook URLs:"
        for url in "${webhook_list[@]}"; do
          url=$(echo "$url" | xargs)
          __print_info "  - $url"
        done
      fi
    fi

    __print_info "Use '${self} test' to verify functionality"
  fi

  return $result
}

# Disable webhook transport
function _cmd_disable() {
  if [[ "$1" == "--help" ]]; then
    usage_disable
    return $EC_SUCCESS
  fi

  __print_info "Disabling HTTP webhook event transport..."

  # Disable in configuration
  __set_config_value "enable_webhook_events" "false"
  local result=$?
  if [[ $result -eq 0 ]]; then
    __print_success "HTTP webhook event transport disabled"
  fi

  return $result
}

# Interactive webhook configuration
function _cmd_configure() {
  if [[ "$1" == "--help" ]]; then
    usage_configure
    return $EC_SUCCESS
  fi

  echo "Webhook Configuration Wizard"
  echo "============================"
  echo ""

  # Webhook URLs
  echo "Webhook URLs:"
  echo "Enter HTTP/HTTPS endpoints that will receive KGSM events"
  echo "You can enter multiple URLs separated by commas"
  echo "Examples: https://your-server.com/webhook"
  echo "          https://primary.com/webhook,https://backup.com/webhook"
  echo ""
  read -r -p "Webhook URLs: " webhook_urls

  if [[ -n "$webhook_urls" ]]; then
    __set_config_value "webhook_urls" "$webhook_urls" || return $?
    __print_success "Webhook URLs configured"
    echo ""
  fi

  # Timeout configuration
  echo "Request Timeout:"
  echo "How long should KGSM wait for webhook responses? (1-300 seconds)"
  echo "Current: ${config_webhook_timeout_seconds:-10} seconds"
  echo ""
  read -r -p "Timeout in seconds [${config_webhook_timeout_seconds:-10}]: " timeout

  if [[ -n "$timeout" ]]; then
    __set_config_value "webhook_timeout_seconds" "$timeout" || return $?
  fi
  echo ""

  # Retry configuration
  echo "Retry Count:"
  echo "How many times should failed requests be retried? (0-5)"
  echo "Current: ${config_webhook_retry_count:-2}"
  echo ""
  read -r -p "Retry count [${config_webhook_retry_count:-2}]: " retries

  if [[ -n "$retries" ]]; then
    __set_config_value "webhook_retry_count" "$retries" || return $?
  fi
  echo ""

  # Secret configuration
  echo "Authentication Secret (optional):"
  echo "Enter a secret key for HMAC-SHA256 signature verification"
  echo "Leave empty to disable authentication"
  echo ""
  read -r -s -p "Webhook secret: " secret
  echo ""

  if [[ -n "$secret" ]]; then
    __set_config_value "webhook_secret" "$secret" || return $?
    __print_success "Authentication enabled with HMAC-SHA256 signatures"
  else
    __set_config_value "webhook_secret" "" || return $?
    __print_info "Authentication disabled"
  fi
  echo ""

  __print_success "Webhook configuration completed!"
  __print_info "Use '${self} enable' to activate webhook transport"
  __print_info "Use '${self} test' to verify your configuration"

  return $EC_SUCCESS
}

# Test webhook functionality
function _cmd_test() {
  if [[ "$1" == "--help" ]]; then
    usage_test
    return $EC_SUCCESS
  fi

  export WEBHOOK_TEST_MODE=1
  __print_info "Testing HTTP webhook event transport..."

  # Check if enabled
  if [[ "$config_enable_webhook_events" != "true" ]]; then
    __print_error "Webhook transport is not enabled"
    __print_error "Use '${self} enable' to activate webhook transport first"
    return 1
  fi

  # Check if webhook URLs are configured
  if [[ -z "$config_webhook_urls" ]]; then
    __print_error "No webhook URLs configured"
    __print_error "Use '${self} configure' to set up webhook endpoints"
    return 1
  fi

  # Check dependencies
  if ! command -v wget >/dev/null 2>&1; then
    __print_error "wget is required but not installed"
    return $EC_MISSING_DEPENDENCY
  fi

  # Convert comma-separated list to array and display
  IFS=',' read -ra webhook_list <<<"$config_webhook_urls"

  if [[ ${#webhook_list[@]} -eq 1 ]]; then
    __print_info "Webhook URL: ${webhook_list[0]// /}"
  else
    __print_info "Webhook URLs:"
    for url in "${webhook_list[@]}"; do
      url=$(echo "$url" | xargs)
      __print_info "  - $url"
    done
  fi

  # Create test event payload
  local test_payload
  test_payload=$(
    jq -n \
      --arg event_type "test_event" \
      --arg test_data "Webhook transport test" \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
      --arg hostname "$(hostname 2>/dev/null || echo 'localhost')" \
      '{
        V: 1,
        EventType: $event_type,
        Data: { Test: $test_data },
        Timestamp: $timestamp,
        Hostname: $hostname,
        ProducerVersion: "test"
      }'
  )

  # Test all webhook URLs
  local overall_success=true

  for webhook_url in "${webhook_list[@]}"; do
    webhook_url=$(echo "$webhook_url" | xargs)
    if [[ -n "$webhook_url" ]]; then
      __print_info "Testing webhook: $webhook_url"
      if __webhook_send "$webhook_url" "$test_payload" 0 false; then
        __print_success "Webhook test PASSED: $webhook_url"
      else
        __print_error "Webhook test FAILED: $webhook_url"
        overall_success=false
      fi
    fi
  done

  if [[ "$overall_success" == "true" ]]; then
    __print_success "All webhook tests PASSED"
    return 0
  else
    __print_error "One or more webhook tests FAILED"
    return 1
  fi
}

# Show webhook status
function _cmd_status() {
  if [[ "$1" == "--help" ]]; then
    usage_status
    return $EC_SUCCESS
  fi

  local BOLD="\e[1m"
  local END="\e[0m"
  local GREEN="\e[32m"
  local RED="\e[31m"
  local YELLOW="\e[33m"

  echo -e "${BOLD}HTTP Webhook Transport Status${END}"
  echo "================================="
  echo ""

  # Configuration status
  echo -e "${BOLD}Configuration:${END}"
  if [[ "$config_enable_webhook_events" == "true" ]]; then
    echo -e "  Status: ${GREEN}Enabled${END}"
  else
    echo -e "  Status: ${RED}Disabled${END}"
  fi

  if [[ -n "$config_webhook_urls" ]]; then
    IFS=',' read -ra webhook_list <<<"$config_webhook_urls"
    if [[ ${#webhook_list[@]} -eq 1 ]]; then
      echo "  Webhook URL: ${webhook_list[0]// /}"
    else
      echo "  Webhook URLs:"
      for url in "${webhook_list[@]}"; do
        url=$(echo "$url" | xargs)
        echo "    - $url"
      done
    fi
  else
    echo -e "  Webhook URLs: ${RED}Not configured${END}"
  fi

  echo "  Timeout: ${config_webhook_timeout_seconds:-10} seconds"
  echo "  Retry count: ${config_webhook_retry_count:-2}"

  if [[ -n "$config_webhook_secret" ]]; then
    echo -e "  Authentication: ${GREEN}HMAC-SHA256 enabled${END}"
  else
    echo -e "  Authentication: ${YELLOW}Disabled${END}"
  fi
  echo ""

  # Dependencies
  echo -e "${BOLD}Dependencies:${END}"
  if command -v wget >/dev/null 2>&1; then
    echo -e "  wget: ${GREEN}Available${END} ($(wget --version 2>/dev/null | head -1 || echo 'version unknown'))"
  else
    echo -e "  wget: ${RED}Not installed${END}"
    echo "                 Install with: sudo apt-get install wget (Ubuntu/Debian)"
    echo "                 sudo yum install wget (RHEL/CentOS)"
  fi

  if [[ -n "$config_webhook_secret" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      echo -e "  openssl: ${GREEN}Available${END} (for HMAC signatures)"
    else
      echo -e "  openssl: ${YELLOW}Not installed${END} (signatures will be skipped)"
    fi
  fi
  echo ""

  # Connectivity status
  echo -e "${BOLD}Connectivity:${END}"
  if [[ -n "$config_webhook_urls" ]] && command -v wget >/dev/null 2>&1; then
    IFS=',' read -ra webhook_list <<<"$config_webhook_urls"
    for url in "${webhook_list[@]}"; do
      url=$(echo "$url" | xargs)
      if [[ -n "$url" ]]; then
        if timeout 3 wget --spider --quiet "$url" 2>/dev/null; then
          echo -e "  $url: ${GREEN}Reachable${END}"
        else
          echo -e "  $url: ${YELLOW}Unable to connect${END}"
        fi
      fi
    done
  else
    echo "  Cannot test connectivity (missing URLs or wget)"
  fi

  return $EC_SUCCESS
}

# Handle emit command (called by commands/events.sh)
function _cmd_emit() {
  local payload="$1"
  __webhook_emit_event "$payload"
  return $?
}

# Help command
function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return $EC_SUCCESS
  fi

  case "$command" in
    enable)
      usage_enable
      ;;
    disable)
      usage_disable
      ;;
    configure)
      usage_configure
      ;;
    test)
      usage_test
      ;;
    status)
      usage_status
      ;;
    *)
      __print_error "Unknown command: $command"
      show_usage
      return $EC_INVALID_ARG
      ;;
  esac

  return $EC_SUCCESS
}

# Main entry point
if [[ $# -eq 0 ]]; then
  show_usage
  exit $EC_ERROR
fi

# Parse global options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help | help)
      shift
      _cmd_help "$@"
      exit $?
      ;;
    --debug)
      export KGSM_DEBUG=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

# Parse command
command="${1:-}"
shift 2> /dev/null || true

# Route to command handlers
case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  enable)
    _cmd_enable "$@"
    exit $?
    ;;
  disable)
    _cmd_disable "$@"
    exit $?
    ;;
  configure)
    _cmd_configure "$@"
    exit $?
    ;;
  test)
    _cmd_test "$@"
    exit $?
    ;;
  status)
    _cmd_status "$@"
    exit $?
    ;;
  emit)
    _cmd_emit "$@"
    exit $?
    ;;
  help)
    _cmd_help "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
