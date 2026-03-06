# =============================================================================
# SERVER I/O
# =============================================================================

# Security function to validate and sanitize input commands
# Prevents command injection attacks through user-provided input
function __sanitize_input_command() {
  local command="$1"

  # Check for empty command
  if [[ -z "$command" ]]; then
    echo "ERROR: Empty command provided"
    return $EC_ERROR
  fi

  # Check command length to prevent buffer overflow attempts
  if [[ ${#command} -gt 1000 ]]; then
    echo "ERROR: Command too long (${#command} characters, max 1000)"
    echo "Command: ${command:0:100}..."
    return $EC_ERROR
  fi

  # Check for dangerous characters that could be used for command injection
  # Using individual checks to avoid regex complexity issues
  if [[ "$command" != *";"* ]] && [[ "$command" != *"&"* ]] && [[ "$command" != *"|"* ]] &&
    [[ "$command" != *"\`"* ]] && [[ "$command" != *"\$("* ]] && [[ "$command" != *")"* ]] &&
    [[ "$command" != *"{"* ]] && [[ "$command" != *"}"* ]] && [[ "$command" != *"["* ]] &&
    [[ "$command" != *"]"* ]] && [[ "$command" != *"\\"* ]] && [[ "$command" != *"<"* ]] &&
    [[ "$command" != *">"* ]] && [[ "$command" != *"*"* ]] && [[ "$command" != *"?"* ]] &&
    [[ "$command" != *"~"* ]] && [[ "$command" != *"\$"* ]] && [[ "$command" != *"!"* ]]; then
    return $EC_SUCCESS
  fi

  echo "ERROR: Input command contains potentially dangerous characters"
  echo "Rejected characters: ; & | \` \$( ) { } [ ] \\ < > * ? ~ \$ !"
  echo "Command: $command"
  return $EC_ERROR
}

function _send_input() {
  local command=$1
  __print_info "Sending command: $command"

  # Security check: Sanitize input to prevent command injection
  if ! __sanitize_input_command "$command"; then
    __print_error "Command rejected for security reasons"
    return $EC_ERROR
  fi

  # Check if the container is running using the existing _is_active function
  if ! _is_active &>/dev/null; then
    __print_error "Container '$instance_name' is not running"
    return $EC_ERROR
  fi

  # Get the management file path from the container's environment
  local management_file
  management_file=$(docker exec "$instance_name" bash -c 'echo $MANAGEMENT_FILE' 2>/dev/null)

  if [[ -z "$management_file" ]]; then
    __print_error "Could not determine management script path in container. \$MANAGEMENT_FILE not set."
    return $EC_ERROR
  fi

  # Call the container's internal management script with the --input flag
  # Using printf to safely pass the command without shell interpretation
  if ! printf '%s\n' "$command" | docker exec -i "$instance_name" "$management_file" --input; then
    __print_error "Failed to send command to container '$instance_name'"
    return $EC_ERROR
  fi

  __print_success "Command sent to container"
  return $EC_SUCCESS
}

function _send_save_command() {
  __print_info "Saving game state..."

  # Check if save command is configured
  if [[ -z "${instance_save_command}" ]]; then
    __print_warning "No save command configured (instance_save_command is not set)"
    __print_info "Save command skipped - game may not support save commands or save command not configured"
    return $EC_SUCCESS
  fi

  # Check if the container is running
  if ! _is_active &>/dev/null; then
    __print_error "Container '$instance_name' is not running"
    return $EC_ERROR
  fi

  # Send the save command to the container using the existing input infrastructure
  if ! _send_input "${instance_save_command}"; then
    __print_error "Failed to send save command to container"
    return $EC_ERROR
  fi

  # Wait a moment for the save to complete (similar to native template)
  local save_timeout="${instance_save_command_timeout_seconds:-5}"
  __print_info "Waiting ${save_timeout} seconds for save to complete..."
  sleep "${save_timeout}"

  __print_success "Save command sent to container"
  return $EC_SUCCESS
}

