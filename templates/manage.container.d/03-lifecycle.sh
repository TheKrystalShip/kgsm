# =============================================================================
# PROCESS MANAGEMENT
# =============================================================================

# This function checks if the server is active by checking the PID file
# and verifying if the process with that PID is still running
# For containers, we also verify the container is actually running
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

  # For containers, the PID file may contain container ID instead of numeric PID
  # Validate that PID is either numeric (for process PID) or alphanumeric (for container ID)
  if [[ ! "$server_pid" =~ ^[a-zA-Z0-9]+$ ]]; then
    __print_error "Instance PID file contains invalid PID/Container ID: '$server_pid', removing"
    rm -f "$instance_pid_file"
    echo "Inactive" && return $EC_ERROR
  fi

  # For containers, check if it's a container ID (longer than typical PID)
  if [[ ${#server_pid} -gt 10 ]]; then
    # This looks like a container ID, check if container is running
    if ! docker ps --filter "id=$server_pid" --format "{{.ID}}" | grep -q "$server_pid"; then
      # Container is not running anymore, remove stale PID file
      __print_error "Instance PID file references non-existent container (ID: $server_pid), removing"
      rm -f "$instance_pid_file"
      echo "Inactive" && return $EC_ERROR
    fi
    echo "Active" && return $EC_SUCCESS
  fi

  # This looks like a numeric PID, check if process is running
  if [[ ! "$server_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$server_pid" 2>/dev/null; then
    # Process is not running anymore, remove stale PID file
    __print_error "Instance PID file references non-existent process (PID: $server_pid), removing"
    rm -f "$instance_pid_file"
    echo "Inactive" && return $EC_ERROR
  fi

  echo "Active" && return $EC_SUCCESS
}

# Start the server in the current terminal
function _start() {
  __print_info "Starting server in foreground..."

  # Rotate the log file before starting
  if ! _rotate_log_file "$instance_log_file"; then
    __print_warning "Failed to rotate log file, continuing"
  fi

  # The instance is stopped by definition here — this is the path that starts it
  # — so the backup _update takes first is told so rather than left to a probe.
  if [[ "$instance_auto_update" == "true" ]]; then
    _update --run-state inactive
  fi

  # Save the current shell PID to track the foreground process
  echo "$$" >"$instance_pid_file"
  __print_success "Instance $instance_name foreground PID saved to $instance_pid_file"

  # Use docker compose up to start the container with logs visible
  # Change to working directory first to ensure docker-compose.yml is found
  (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" up)

  # Clean up PID file when container stops
  [[ -f "$instance_pid_file" ]] && rm -f "$instance_pid_file"
}

# Start the server in the background
function _start_background() {
  __print_info "Starting server in background..."

  # Rotate the log file before starting
  if ! _rotate_log_file "$instance_log_file"; then
    __print_error "Failed to rotate latest log file. Aborting to prevent data loss."
    return $EC_ERROR
  fi

  # Use docker compose up -d to start the container in detached mode
  # Change to working directory first to ensure docker-compose.yml is found
  if ! (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" up -d); then
    __print_error "Failed to start container in background"
    return $EC_ERROR
  fi

  # Get the container ID for tracking
  local container_id
  container_id=$(cd "$instance_working_dir" && docker compose -f "$instance_compose_file" ps -q 2>/dev/null | head -1)

  if [[ -n "$container_id" ]]; then
    # Save the container ID to PID file for tracking
    echo "$container_id" >"$instance_pid_file"
    __print_success "Instance $instance_name started with container ID $container_id, saved to $instance_pid_file"
  else
    __print_error "Failed to get container ID after starting"
    return $EC_ERROR
  fi

  __print_success "Server started in background"
}

function _stop_server() {
  local no_save=$1
  local no_graceful=$2

  __print_info "Stopping server..."

  if ! _is_active &>/dev/null; then
    __print_warning "Instance $instance_name is not running"
    return $EC_SUCCESS
  fi

  # Save game if requested
  if [[ "$no_save" -eq 0 ]]; then
    _send_save_command
  fi

  # For graceful shutdown, try to send stop command if available
  if [[ "$no_graceful" -eq 0 ]]; then
    if [[ -n "$instance_stop_command" ]]; then
      __print_info "Sending graceful stop command to container..."
      if ! _send_input "$instance_stop_command" 2>/dev/null; then
        __print_warning "Failed to send graceful stop command, proceeding with normal shutdown"
      else
        # Wait a moment for graceful shutdown
        sleep "${instance_stop_command_timeout_seconds:-5}"
      fi
    fi
  fi

  # Emit instance_stopping on the host-visible lifecycle channel *before*
  # tearing the container down. This is the reliable half of the signal: the
  # in-container INT/TERM trap that emits the same event (see
  # kgsm-containers templates/container.manage.sh `_emit_lifecycle`) is
  # unreachable once `_start`'s final `exec` has replaced that bash process
  # with the game binary, so a `docker stop`/`down` never reaches any
  # in-container bash to run it. Host-side bash is always alive here, so we
  # emit it ourselves. Best-effort/guarded: a write failure must never fail
  # the stop, and a guard failure is skipped silently rather than emitting
  # bad data (honesty rule) -- never invent a malformed line. Shape/format
  # matches the in-container emitter byte-for-byte:
  # {"type":"instance_stopping","ts":"<ISO-8601-UTC>"}.
  if [[ -n "$instance_events_dir" ]] && mkdir -p "$instance_events_dir" 2>/dev/null; then
    local _lifecycle_stopping_ts
    if _lifecycle_stopping_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)"; then
      printf '{"type":"instance_stopping","ts":"%s"}\n' "$_lifecycle_stopping_ts" \
        >>"$instance_events_dir/lifecycle.ndjson" 2>/dev/null
    fi
  fi

  # Use docker compose down to stop the container
  # Run in the working directory where docker-compose.yml is located
  if ! (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" down); then
    __print_error "Failed to stop container using compose down"
    return $EC_ERROR
  fi

  # Clean up PID file
  [[ -f "$instance_pid_file" ]] && rm -f "$instance_pid_file"

  __print_success "Instance $instance_name stopped"
  return $EC_SUCCESS
}

function _timed_stop() {
  local no_save=$1
  local no_graceful=$2

  _stop_server "$no_save" "$no_graceful"
}

# Kill the container process and all its children
# This function will also remove the PID file and clean up resources
function _kill_all_processes() {
  local container_id
  local output

  __print_info "Force killing container..."

  # Atomic read of PID file to avoid TOCTOU vulnerability
  if ! container_id=$(cat "$instance_pid_file" 2>/dev/null); then
    __print_error "No PID file found for $instance_name."
    __print_error "If this is unexpected, check running containers to ensure the instance is not running uncontrolled"
    return $EC_ERROR
  fi

  # Validate that container_id is not empty
  if [[ -z "${container_id// /}" ]]; then
    __print_error "Invalid container ID in file: '$container_id'"
    rm -f "$instance_pid_file"
    return $EC_ERROR
  fi

  # For container IDs, validate they are alphanumeric
  if [[ ! "$container_id" =~ ^[a-zA-Z0-9]+$ ]]; then
    __print_error "Invalid container ID in file: '$container_id'"
    rm -f "$instance_pid_file"
    return $EC_ERROR
  fi

  # Check if this is a container ID (longer than typical PID) and handle accordingly
  if [[ ${#container_id} -gt 10 ]]; then
    # This looks like a container ID, try to kill it directly
    if ! docker ps --filter "id=$container_id" --format "{{.ID}}" | grep -q "$container_id"; then
      __print_warning "Container ID $container_id not found in running containers"
    else
      # Kill the container directly
      if ! output=$(docker kill "$container_id" 2>&1); then
        __print_error "Failed to kill container ID $container_id"
        __print_error "Output: ${output}"
        # Try compose kill as fallback
        if ! (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" kill 2>&1); then
          __print_error "Compose kill also failed"
          return $EC_ERROR
        fi
      else
        __print_info "Killed container ID $container_id"
      fi
    fi
  else
    # This looks like a numeric PID, try to kill it as a process
    if [[ ! "$container_id" =~ ^[0-9]+$ ]] || ! kill -0 "$container_id" 2>/dev/null; then
      __print_warning "Process PID $container_id not found"
    else
      if ! output=$(kill -TERM "$container_id" 2>&1); then
        __print_error "Failed to kill process PID $container_id"
        __print_error "Output: ${output}"
        return $EC_ERROR
      fi
      __print_info "Killed process PID $container_id"
    fi
  fi

  # Clean up any remaining container resources using compose
  if ! (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" down --remove-orphans 2>&1); then
    __print_warning "Failed to clean up container resources, but continuing"
  fi

  # Clean up PID file
  [[ -f "$instance_pid_file" ]] && rm -f "$instance_pid_file"

  __print_success "Container and processes killed"
  return $EC_SUCCESS
}

# Cleanup function for SIGINT, SIGTERM, and EXIT
function _cleanup_on_exit() {
  __print_warning "Caught exit signal, performing cleanup..."

  # Clean up PID file if it exists (foreground mode)
  if [[ -f "$instance_pid_file" ]]; then
    __print_info "Removing instance PID file $instance_pid_file on exit"
    rm -f "$instance_pid_file"
  fi
}

trap _cleanup_on_exit INT TERM

