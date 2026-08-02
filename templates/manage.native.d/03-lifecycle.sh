# =============================================================================
# PROCESS MANAGEMENT
# =============================================================================

# This function checks if the server is active by checking the PID file
# and verifying if the process with that PID is still running
# Fixed to prevent race conditions using atomic file operations
function _is_active() {
  local server_pid

  # Atomic read operation: attempt to read PID file content directly
  # This eliminates the TOCTOU (Time of Check, Time of Use) vulnerability
  # where the file could be modified between checking existence and reading
  if ! server_pid=$(cat "$instance_pid_file" 2>/dev/null); then
    # File doesn't exist, is unreadable, or read failed
    echo "Inactive" && return $EC_ERROR
  fi

  # Check if PID file content is empty or contains only whitespace
  if [[ -z "${server_pid// /}" ]]; then
    __print_error "Instance PID file present but empty, removing"
    # Safe removal: only remove if file still exists and is empty
    if [[ -f "$instance_pid_file" ]] && [[ ! -s "$instance_pid_file" ]]; then
      rm -f "$instance_pid_file"
    fi
    echo "Inactive" && return $EC_ERROR
  fi

  # Validate that PID is numeric to prevent injection attacks
  if [[ ! "$server_pid" =~ ^[0-9]+$ ]]; then
    __print_error "Instance PID file contains invalid PID: '$server_pid', removing"
    rm -f "$instance_pid_file"
    echo "Inactive" && return $EC_ERROR
  fi

  # Check if the process with that PID is running
  # Using kill -0 which doesn't actually send a signal, just checks existence
  if kill -0 "$server_pid" 2>/dev/null; then
    echo "Active" && return $EC_SUCCESS
  else
    # Process is not running anymore, remove stale PID file
    __print_error "Instance PID file references non-existent process (PID: $server_pid), removing"
    rm -f "$instance_pid_file"
    echo "Inactive" && return $EC_ERROR
  fi
}

# Start the server in detachable mode (fake foreground)
# Server runs in background but terminal is attached to logs and input
function _start() {
  __print_info "Starting $instance_name in detachable mode"

  # Start server in background mode first
  if ! _start_background; then
    return $EC_ERROR
  fi

  # Small delay to ensure server process is fully initialized
  sleep 1

  # Attach to the running instance
  _attach_to_instance
}

# Start the server in the background
# This function will create a named pipe for communication with the server
# and redirect logs to a file. Fixed to eliminate race condition in PID tracking
function _start_background() {
  # Rotate the latest log file
  if ! _rotate_log_file "$instance_log_file"; then
    __print_error "Failed to rotate latest log file. Aborting to prevent data loss."
    return $EC_ERROR
  fi

  # Handle auto-update before changing directory. The instance is stopped by
  # definition here — this is the path that starts it — so the backup _update
  # takes first is told so rather than left to a probe.
  if [[ "$instance_auto_update" == "true" ]]; then
    if ! _update --run-state inactive; then
      __print_error "Failed to update $self, exiting"
      return $EC_ERROR
    fi
  fi

  cd "$instance_launch_dir" || {
    __print_error "Failed to move into $instance_launch_dir, exiting"
    return $EC_ERROR
  }

  # Clean up any existing socket file
  [[ -p "$instance_socket_file" ]] && rm "$instance_socket_file"

  # Create named pipe for command input
  mkfifo "$instance_socket_file"

  # stdin: redirected from socket for command input
  # stdout/stderr: redirected to logs
  # Validate executable arguments for dangerous command substitution patterns
  # SC2016: single quotes are intentional — we are matching literal '$(' and '`'
  # shellcheck disable=SC2016
  if [[ "$instance_executable_arguments" == *'$('* ]] || [[ "$instance_executable_arguments" == *'`'* ]]; then
    __print_error "instance_executable_arguments contains dangerous command substitution patterns"
    return $EC_ERROR
  fi
  # Safely expand variables within executable_arguments before execution
  local expanded_args
  expanded_args=$(echo "$instance_executable_arguments" | envsubst)
  # shellcheck disable=SC2086
  $instance_executable_file $expanded_args \
    <"$instance_socket_file" \
    &>"$instance_log_file" &

  # Capture the actual server process PID (not a subshell)
  local server_pid=$!

  # Validate that we got a valid PID
  if [[ -z "$server_pid" ]] || [[ ! "$server_pid" =~ ^[0-9]+$ ]]; then
    __print_error "Failed to start server process - invalid PID: '$server_pid'"
    [[ -p "$instance_socket_file" ]] && rm -f "$instance_socket_file"
    return $EC_ERROR
  fi

  # Verify the process actually started
  if ! kill -0 "$server_pid" 2>/dev/null; then
    __print_error "Server process failed to start or exited immediately"
    [[ -p "$instance_socket_file" ]] && rm -f "$instance_socket_file"
    return $EC_ERROR
  fi

  # Save the server PID to file
  echo "$server_pid" >"$instance_pid_file"
  __print_success "Instance $instance_name started with PID $server_pid, saved to $instance_pid_file"

  # Prevent EOF on fifo by keeping the named pipe open with a dummy writer
  # Using --pid ensures tail automatically exits when the server process dies
  # This eliminates the need to track and manually kill the tail process
  tail -f /dev/null --pid="$server_pid" >"$instance_socket_file" &

  # No need to save or track the tail PID anymore since it will auto-exit
  __print_success "Socket keepalive process started (auto-exit when server dies)"
}

# Attach to a running server instance
# Provides interactive console with log output and command input
function _attach_to_instance() {
  if ! _is_active &>/dev/null; then
    __print_error "Cannot attach: $instance_name is not running"
    return $EC_ERROR
  fi

  __print_info "Attaching to $instance_name console"
  __print_info "Type '.detach' to disconnect (server will continue running)"
  __print_info "Press Ctrl+C to stop the server"

  # Start log follower in background
  # Using --pid=$$ ensures tail exits when this shell exits
  _print_logs true 50 2>/dev/null &

  # Trap Ctrl+C to stop server (expected behavior when attached)
  trap '_stop_server && echo "" && return $EC_SUCCESS' INT

  # Read loop with prompt
  while IFS= read -r -e -p "[$instance_name]> " line; do
    # Check if server is still running before processing input
    if ! _is_active &>/dev/null; then
      __print_info "$instance_name has stopped, returning to shell"
      echo ""
      return $EC_SUCCESS
    fi

    # Check for detach command
    if [[ "$line" == ".detach" ]]; then
      __print_info "Detaching from $instance_name (server continues running)"
      __print_info "Use '${self} attach' to re-attach"
      break
    fi

    # Skip empty input
    [[ -z "$line" ]] && continue

    # Send to socket
    if [[ -p "$instance_socket_file" ]]; then
      if ! __sanitize_input_command "$line"; then
        __print_error "Input rejected due to unsafe characters"
        continue
      fi
      echo "$line" >>"$instance_socket_file"
    else
      __print_error "Socket not available, server may have stopped"
      break
    fi
  done
}

# Stop the server gracefully or forcefully
# This function will also save the game state if requested
# and remove the PID file and the named pipe
function _stop_server() {
  local no_save=0
  local no_graceful=0

  __print_info "Stopping $self"

  if ! _is_active &>/dev/null; then
    __print_error "Instance '$instance_name' is not running"
    return $EC_SUCCESS
  fi

  # Process arguments without destroying them
  local arg
  for arg in "$@"; do
    case "$arg" in
    --no-save) no_save=1 ;;
    --no-graceful) no_graceful=1 ;;
      # Skip the special argument passed in some cases
    "\@") continue ;;
    *) continue ;;
    esac
  done

  if [[ "$no_save" -eq 0 ]]; then
    _send_save_command
  fi

  if [[ "$no_graceful" -eq 0 ]]; then
    # Send stop command to socket
    if [[ -p "$instance_socket_file" ]]; then
      if [[ -n "$instance_stop_command" ]]; then
        echo "$instance_stop_command" >>"$instance_socket_file"
      fi
    fi
  fi

  _kill_all_processes

  [[ -f "$instance_pid_file" ]] && rm -f "$instance_pid_file"
  [[ -p "$instance_socket_file" ]] && rm -f "$instance_socket_file"

  __print_success "Instance '$instance_name' stopped"
}

# This function is used to stop the server gracefully with a timeout
# If the server does not stop within the timeout, it will be killed forcefully
function _timed_stop() {
  local no_save=$1
  local no_graceful=$2

  # Export functions needed by _stop_server in the timeout subshell
  export -f _stop_server _kill_all_processes _is_active _send_save_command
  export -f __print_info __print_error __print_success __print_warning

  if ! timeout "$instance_stop_command_timeout_seconds" bash -c '_stop_server "$@"' _ ${no_save:+--no-save} ${no_graceful:+--no-graceful}; then
    __print_error "Timeout reached, killing instance"
    _kill_all_processes
  fi
}

# Kill the server process and all its children
# This function will also remove the PID file and the named pipe
# Fixed to prevent race conditions and properly handle child process arrays
function _kill_all_processes() {
  local server_pid
  local output
  local child_pids_string
  local child_pids_array

  # Atomic read of PID file to avoid TOCTOU vulnerability
  if ! server_pid=$(cat "$instance_pid_file" 2>/dev/null); then
    __print_error "No PID file found for $instance_name."
    __print_error "If this is unexpected, check running processes to ensure the instance is not running uncontrolled"
    return $EC_ERROR
  fi

  # Validate that PID is numeric
  if [[ -z "${server_pid// /}" ]] || [[ ! "$server_pid" =~ ^[0-9]+$ ]]; then
    __print_error "Invalid PID in file: '$server_pid'"
    rm -f "$instance_pid_file"
    return $EC_ERROR
  fi

  # Find all child processes of the server PID
  child_pids_string=$(pgrep -P "$server_pid" 2>/dev/null)

  # Convert child PIDs string to proper array for safe processing
  if [[ -n "$child_pids_string" ]]; then
    # Read PIDs into array, one per line
    IFS=$'\n' read -d '' -ra child_pids_array <<<"$child_pids_string" || true

    # Kill child processes if any exist
    if [[ ${#child_pids_array[@]} -gt 0 ]]; then
      if ! output=$(kill -TERM "${child_pids_array[@]}" 2>&1); then
        __print_error "Failed to kill child PIDs: ${child_pids_array[*]}"
        __print_error "Output: ${output}"
        return $EC_ERROR
      fi
      __print_info "Killed ${#child_pids_array[@]} child processes"
    fi
  fi

  # Kill the main server process if it's still running
  if kill -0 "$server_pid" 2>/dev/null; then
    if ! output=$(kill -TERM "$server_pid" 2>&1); then
      __print_error "Failed to kill main process PID $server_pid."
      __print_error "Output: ${output}"
      return $EC_ERROR
    fi
    __print_info "Killed main process PID $server_pid"
  fi
}

# Cleanup function to run on script exit, removing the PID file
# This function is called on INT, TERM, and EXIT signals, don't call it directly
# shellcheck disable=SC2329
function _cleanup_on_exit() {
  __print_warning "Caught exit signal, performing cleanup..."

  # Clean up PID file if it exists (foreground mode)
  if [[ -f "$instance_pid_file" ]]; then
    __print_info "Removing instance PID file $instance_pid_file on exit"
    rm -f "$instance_pid_file"
  fi
}

trap _cleanup_on_exit INT TERM

