# =============================================================================
# LOGGING
# =============================================================================

function _rotate_log_file() {
  local log_file="$1"

  # Do nothing if the log file doesn't exist or is empty
  if [[ ! -s "$log_file" ]]; then
    return
  fi

  # Create a timestamp for the new log file
  local timestamp
  timestamp=$(date +"%Y-%m-%dT%H:%M:%S")

  # Construct the new filename
  local rotated_log_file="${instance_logs_dir}/${instance_name}.${timestamp}.log"

  if mv "$log_file" "$rotated_log_file"; then
    __print_success "Rotated log file $log_file to $rotated_log_file"
  else
    __print_error "Failed to rotate log file $log_file to $rotated_log_file"
    return $EC_ERROR
  fi

  return $EC_SUCCESS
}

function _print_logs() {
  local follow=$1
  local line_count=${2:-10}

  if [[ "$follow" == "true" ]]; then
    (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" logs --tail="$line_count" -f) &
    tail_pid=$!
    wait "$tail_pid"
  else
    (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" logs --tail="$line_count")
  fi
}

