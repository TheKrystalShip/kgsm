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

  # Write directly to the command FIFO on the shared /run/kgsm bind mount
  # (${instance_events_dir}/command.fifo on the host == /run/kgsm/command.fifo
  # in the container), mirroring how native's manage.native.d/04-io.sh writes
  # straight to its own host-visible FIFO. This replaces the previous
  # `docker exec -i ... "$management_file" --input` roundtrip, which appended
  # to $instance_socket_file -- a FIFO only _start_background() ever creates.
  # Containers always launch via the foreground _start(), so that FIFO never
  # existed for a container instance and every send silently failed.
  if [[ -z "$instance_events_dir" ]]; then
    __print_error "Input failed: instance_events_dir is not set for '$instance_name'."
    return $EC_ERROR
  fi

  local command_fifo="${instance_events_dir}/command.fifo"
  if [[ ! -p "$command_fifo" ]]; then
    __print_error "Input failed: No active server found (command FIFO missing at $command_fifo)."
    return $EC_ERROR
  fi

  # Open the FIFO read-write rather than appending to it. A plain append blocks
  # until something opens the read end, so a container that died leaving its
  # command FIFO behind would hang this call forever — and with it whatever is
  # waiting on it, from an unattended backup's flush to a console send.
  local _cmd_fd
  if ! exec {_cmd_fd}<>"$command_fifo"; then
    __print_error "Input failed: could not open $command_fifo"
    return $EC_ERROR
  fi
  if ! printf '%s\n' "$command" >&"${_cmd_fd}"; then
    exec {_cmd_fd}>&-
    __print_error "Failed to send command to container '$instance_name'"
    return $EC_ERROR
  fi
  exec {_cmd_fd}>&-

  __print_success "Command sent to container"
  return $EC_SUCCESS
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

  if ! _is_active &>/dev/null; then
    __print_error "Container '$instance_name' is not running"
    return $EC_ERROR
  fi

  if [[ -z "$instance_events_dir" ]]; then
    __print_error "Announcement failed: instance_events_dir is not set for '$instance_name'."
    return $EC_ERROR
  fi

  local command_fifo="${instance_events_dir}/command.fifo"
  if [[ ! -p "$command_fifo" ]]; then
    __print_error "Announcement failed: No active server found (command FIFO missing at $command_fifo)."
    return $EC_ERROR
  fi

  # Open the FIFO read-write rather than appending to it. A plain append blocks
  # until something opens the read end, so a container that died leaving its
  # command FIFO behind would hang this call forever.
  local _bcast_fd
  if ! exec {_bcast_fd}<>"$command_fifo"; then
    __print_error "Announcement failed: could not open $command_fifo"
    return $EC_ERROR
  fi
  if ! printf '%s\n' "$resolved" >&"${_bcast_fd}"; then
    exec {_bcast_fd}>&-
    __print_error "Failed to send announcement to container '$instance_name'"
    return $EC_ERROR
  fi
  exec {_bcast_fd}>&-

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

