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

# Resolve a moderation template against a target and deliver it to the console.
# The template carries exactly one placeholder — {ip}, {name} or {id} — naming
# the identity token the game expects; that token is the contract a caller reads
# to know what to pass, so the substitution is a plain swap with no
# interpretation of what the target means.
# Args: $1 = template, $2 = target, $3 = action label (kick|ban|unban)
function _send_moderation_command() {
  local template="$1"
  local target="$2"
  local action="$3"

  # An absent template means the game declares no such command. Refuse: sending
  # a different command in its place would report an outcome that never
  # happened.
  if [[ -z "$template" ]]; then
    __print_error "$instance_name does not support '${action}'"
    __print_error "No ${action}_command is declared for this instance"
    return $EC_ERROR
  fi

  if [[ -z "$target" ]]; then
    __print_error "Missing target for '${action}'"
    return $EC_MISSING_ARG
  fi

  # The console reads one command per line, so a line break in the target would
  # deliver a second command nobody issued.
  if [[ "$target" == *$'\n'* ]] || [[ "$target" == *$'\r'* ]]; then
    __print_error "Invalid target: line breaks are not allowed"
    return $EC_INVALID_ARG
  fi

  local resolved="$template"
  resolved="${resolved//\{ip\}/$target}"
  resolved="${resolved//\{name\}/$target}"
  resolved="${resolved//\{id\}/$target}"

  # No substitution happened, so the target would never reach the server and the
  # bare verb would be sent instead — a different command than the one asked for.
  if [[ "$resolved" == "$template" ]]; then
    __print_error "Malformed ${action}_command: '${template}'"
    __print_error "Expected one {ip}, {name} or {id} placeholder"
    return $EC_ERROR
  fi

  _send_input "$resolved"
}

# Resolve the blueprint's broadcast template against a message and deliver it to
# the console.
#
# The template is authored in the blueprint and the message is prose, so the two
# are validated differently. The template must contain the placeholder; the
# message is checked only for a line break, because the console reads one command
# per line and a second line would be a command nobody issued. Nothing else in
# the text is restricted: an announcement that cannot say "5 minutes!" is not an
# announcement. There is no shell between here and the game — the bytes go into a
# FIFO with a plain write — so shell metacharacters carry no meaning.
# Args: $1 = message
function _send_broadcast() {
  local message="$1"

  # An absent template means the game declares no broadcast command. Refuse:
  # sending a different command in its place would report an announcement that
  # never happened.
  if [[ -z "${instance_broadcast_command:-}" ]]; then
    __print_error "$instance_name does not support announcements"
    __print_error "No broadcast_command is declared for this instance"
    return $EC_ERROR
  fi

  if [[ -z "$message" ]]; then
    __print_error "Missing message to announce"
    return $EC_MISSING_ARG
  fi

  if [[ "$message" == *$'\n'* ]] || [[ "$message" == *$'\r'* ]]; then
    __print_error "Invalid message: line breaks are not allowed"
    return $EC_INVALID_ARG
  fi

  if [[ ${#message} -gt 1000 ]]; then
    __print_error "Message too long (${#message} characters, max 1000)"
    return $EC_INVALID_ARG
  fi

  local resolved="${instance_broadcast_command//\{message\}/$message}"

  # No substitution happened, so the text would never reach the players and the
  # bare verb would be sent instead — a different command than the one asked for.
  if [[ "$resolved" == "${instance_broadcast_command}" ]]; then
    __print_error "Malformed broadcast_command: '${instance_broadcast_command}'"
    __print_error "Expected a {message} placeholder"
    return $EC_ERROR
  fi

  if [[ ! -p "${instance_socket_file}" ]]; then
    __print_error "Announcement failed: No active server found or socket file missing."
    return $EC_ERROR
  fi

  # Open the FIFO read-write rather than appending to it. A plain append blocks
  # until something opens the read end, so a server that died leaving its socket
  # behind would hang this call forever.
  local _bcast_fd
  if ! exec {_bcast_fd}<>"${instance_socket_file}"; then
    __print_error "Announcement failed: could not open ${instance_socket_file}"
    return $EC_ERROR
  fi
  printf '%s\n' "$resolved" >&"${_bcast_fd}"
  exec {_bcast_fd}>&-

  return $EC_SUCCESS
}

# This function is used to save the game state
# It will send the save command to the server through the named pipe
function _send_save_command() {
  # Check if socket file exists and is a named pipe
  if [[ -p "${instance_socket_file}" ]]; then
    # Check if save command is defined
    if [[ -n "${instance_save_command}" ]]; then
      # Open the FIFO read-write rather than appending to it. A plain append
      # blocks until something opens the read end, so a server that died leaving
      # its socket behind would hang this call forever — and with it any
      # unattended backup that asks for a flush first. Holding the read end
      # ourselves makes the write complete whether or not the game is listening.
      local _save_fd
      if ! exec {_save_fd}<>"${instance_socket_file}"; then
        __print_error "Save failed: could not open ${instance_socket_file}"
        return $EC_ERROR
      fi
      printf '%s\n' "${instance_save_command}" >&"${_save_fd}"
      exec {_save_fd}>&-
      # Sleep to give the server time to process the save command
      sleep "${instance_save_command_timeout_seconds:-5}"
      return $EC_SUCCESS
    fi
  else
    __print_error "Save failed: No active server found or socket file missing."
    return $EC_ERROR
  fi
}

