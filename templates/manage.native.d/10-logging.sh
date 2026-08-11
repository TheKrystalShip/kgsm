# =============================================================================
# LOGGING
# =============================================================================

function _rotate_log_file() {
  local log_file="$1"

  # Do nothing if the log file doesn't exist or is empty
  if [[ ! -s "$log_file" ]]; then
    return
  fi

  # Name the run by when it ENDED: the file's last write is the last line the
  # server printed. The rotation moment is a different quantity, off by however
  # long the instance stayed stopped. UTC, matching kgsm-watchdog, so both
  # rotators sort together in one logs directory.
  local timestamp
  timestamp=$(date -u -r "$log_file" +"%Y-%m-%dT%H:%M:%S")

  # Construct the new filename
  local rotated_log_file="${instance_logs_dir}/${instance_name}.${timestamp}.log"

  # Two runs can end inside the same second (a crash loop restarts after ~1s).
  # Fall back to a nanosecond suffix so a prior run is never overwritten.
  if [[ -e "$rotated_log_file" ]]; then
    rotated_log_file="${instance_logs_dir}/${instance_name}.${timestamp}.$(date -u +%s%N).log"
  fi

  if mv "$log_file" "$rotated_log_file"; then
    __print_success "Rotated log file $log_file to $rotated_log_file"
  else
    __print_error "Failed to rotate log file $log_file to $rotated_log_file"
    return $EC_ERROR
  fi

  return $EC_SUCCESS
}

function _print_logs() {
  local follow=${1:-false}
  local line_count=${2:-10}

  if [[ ! -f "$instance_log_file" ]]; then
    __print_info "No log file found at '$instance_log_file'"
    return $EC_SUCCESS
  fi

  if [[ "$follow" == "true" ]]; then
    exec tail --pid=$$ -n "$line_count" -F "$instance_log_file"
  else
    exec tail --pid=$$ -n "$line_count" "$instance_log_file"
  fi
}

