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

# This function is used to send input commands to the server through
# the named pipe
function _send_input() {
  if [[ -p "$instance_socket_file" ]]; then
    if ! __sanitize_input_command "$1"; then
      return $EC_ERROR
    fi
    echo "$1" >>"$instance_socket_file"
  else
    __print_error "Input failed: No active server found."
    return $EC_ERROR
  fi
}

# This function is used to save the game state
# It will send the save command to the server through the named pipe
function _send_save_command() {
  # Check if socket file exists and is a named pipe
  if [[ -p "${instance_socket_file}" ]]; then
    # Check if save command is defined
    if [[ -n "${instance_save_command}" ]]; then
      echo "${instance_save_command}" >>"${instance_socket_file}"
      # Sleep to give the server time to process the save command
      sleep "${instance_save_command_timeout_seconds:-5}"
      return $EC_SUCCESS
    fi
  else
    __print_error "Save failed: No active server found or socket file missing."
    return $EC_ERROR
  fi
}

