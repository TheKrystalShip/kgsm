# =============================================================================
# STATUS
# =============================================================================

# Convert a date string (ps `lstart` local-time, or an RFC3339 docker timestamp) to
# ISO-8601 UTC second-precision (YYYY-MM-DDTHH:MM:SSZ). Empty input -> empty output;
# an unparseable input -> empty output. Never fabricates a time (a missing/bad value
# stays empty -> JSON null downstream); converting the host's own clock to UTC is not
# fabrication. One defined outcome per input (behavioral certainty, CLAUDE.md).
function _to_iso_utc() {
  local _raw="$1"
  [[ -n "$_raw" ]] || return 0
  date -d "$_raw" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || return 0
}

# Get detailed container process information
# This function provides container-specific process monitoring equivalent to native template
function _get_container_process_info() {
  local container_id="$1"
  local process_info=""

  if [[ -z "$container_id" ]]; then
    return $EC_ERROR
  fi

  # Check if this is a container ID (longer than typical PID)
  if [[ ${#container_id} -gt 10 ]]; then
    # Get container process information
    if ! docker ps --filter "id=$container_id" --format "table {{.ID}}\t{{.Status}}\t{{.Names}}" | grep -q "$container_id"; then
      return $EC_ERROR
    fi
    # Get detailed container stats
    process_info=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}" "$container_id" 2>/dev/null)
    echo "$process_info"
    return $EC_SUCCESS
  fi

  # This looks like a numeric PID, get process info
  if [[ ! "$container_id" =~ ^[0-9]+$ ]] || ! kill -0 "$container_id" 2>/dev/null; then
    return $EC_ERROR
  fi

  process_info=$(ps -p "$container_id" -o pid,ppid,state,pcpu,pmem,cmd --no-headers 2>/dev/null)
  echo "$process_info"
  return $EC_SUCCESS
}

# Enhanced container monitoring function
# Provides detailed container state and resource usage information
function _monitor_container_state() {
  local container_id="$1"

  if [[ -z "$container_id" ]]; then
    return $EC_ERROR
  fi

  # Check if this is a container ID
  if [[ ${#container_id} -le 10 ]]; then
    return $EC_ERROR
  fi

  # Get container state details
  local container_state
  container_state=$(docker inspect "$container_id" --format '{{.State.Status}}' 2>/dev/null)

  if [[ -z "$container_state" ]]; then
    return $EC_ERROR
  fi

  echo "Container State: $container_state"

  # Get additional details if container is running
  if [[ "$container_state" != "running" ]]; then
    return $EC_SUCCESS
  fi

  local start_time
  start_time=$(docker inspect "$container_id" --format '{{.State.StartedAt}}' 2>/dev/null)
  echo "Started At: $start_time"

  # Get resource usage
  local resources
  resources=$(docker stats --no-stream --format "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}} ({{.MemPerc}}), PIDs: {{.PIDs}}" "$container_id" 2>/dev/null)
  echo "Resources: $resources"

  return $EC_SUCCESS
}

function _get_status() {
  local json_format="$1"
  local fast_mode="$2"

  # Gather all status information
  local is_active="false"
  local pid=""
  local process_status=""
  local start_time=""
  local current_version=""
  local latest_version=""
  local updates_available=""
  local updates_checked="false"
  local updates_checked_at=""
  local disk_usage=""
  local backup_count=""
  local recent_logs=""

  # Check if instance is active
  if ! _is_active >/dev/null 2>&1; then
    is_active="false"
  else
    is_active="true"

    # Get process information if active (enhanced with container monitoring)
    if [[ ! -f "$instance_pid_file" ]]; then
      # No PID file available, skip process info
      :
    else
      local container_id
      container_id=$(cat "$instance_pid_file" 2>/dev/null)

      if [[ -z "$container_id" ]]; then
        # Empty container ID, skip process info
        :
      elif [[ ${#container_id} -gt 10 ]]; then
        # This looks like a container ID, get container information
        if ! docker ps --filter "id=$container_id" --format "{{.ID}}" | grep -q "$container_id"; then
          # Container not found, skip process info
          :
        else
          # For JSON compatibility, we need a numeric PID - use a hash of container ID
          # This ensures consistency while maintaining the numeric requirement
          pid=$(echo "$container_id" | sha256sum | cut -c1-8)
          pid=$((16#$pid)) # Convert hex to decimal for proper numeric PID

          # Get container state and timing info using enhanced monitoring
          local container_state_info
          container_state_info=$(docker inspect "$container_id" --format '{{.State.Status}} {{.State.StartedAt}}' 2>/dev/null)
          if [[ -n "$container_state_info" ]]; then
            process_status=$(echo "$container_state_info" | awk '{print $1}')
            local _started_at
            _started_at=$(echo "$container_state_info" | awk '{$1=""; print substr($0,2)}')
            start_time=$(_to_iso_utc "$_started_at")

            # Additional container state validation using monitoring functions
            local state_details
            state_details=$(_monitor_container_state "$container_id" 2>/dev/null)
            if [[ -n "$state_details" ]] && [[ "$process_status" == "running" ]]; then
              # Container is confirmed running with detailed monitoring
              process_status="running"
            fi
          fi
        fi
      else
        # This looks like a numeric PID, treat it as such
        if [[ "$container_id" =~ ^[0-9]+$ ]] && kill -0 "$container_id" 2>/dev/null; then
          pid="$container_id"
          # Get process info similar to native template
          local ps_output
          ps_output=$(ps -p "$container_id" -o state,lstart --no-headers 2>/dev/null)
          if [[ -n "$ps_output" ]]; then
            process_status=$(echo "$ps_output" | awk '{print $1}' | tr -d ' ')
            local _lstart
            _lstart=$(echo "$ps_output" | awk '{$1=""; print substr($0,2)}')
            start_time=$(_to_iso_utc "$_lstart")
          fi
        fi
      fi
    fi
  fi

  # Get version information (optimized with enhanced error handling)
  current_version=$(_get_installed_version 2>/dev/null || echo "Unknown")

  if [[ -n "$fast_mode" ]]; then
    # Fast mode does no network at all. It answers from what the last real check
    # recorded, which is a genuine reading — and it carries updates_checked_at so
    # a consumer can see how old that reading is instead of assuming it is fresh.
    # Nothing recorded means nothing to report: unchecked, never "up to date".
    latest_version="$(_get_stored_latest_version)"
    updates_checked_at="$(_get_stored_latest_checked_at)"

    if [[ -n "$latest_version" && "$current_version" != "Unknown" ]]; then
      updates_checked="true"
      if [[ "$latest_version" == "$current_version" ]]; then
        updates_available="false"
      else
        updates_available="true"
      fi
    else
      latest_version=""
      updates_available=""
      updates_checked="false"
      updates_checked_at=""
    fi
  else
    # Only a known current version allows a real comparison.
    if [[ "$current_version" != "Unknown" ]]; then
      # _get_latest_version directly, never _compare_versions: that function
      # returns the same error for "already current" as for "the registry did
      # not answer", and reporting the second as the first claims a server is up
      # to date on the strength of a check that never completed.
      latest_version=$(_get_latest_version 2>/dev/null)

      if [[ -n "$latest_version" ]]; then
        updates_checked="true"
        # The fetch just happened, so this moment is measured, not assumed.
        updates_checked_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        if [[ "$latest_version" == "$current_version" ]]; then
          updates_available="false"
        else
          updates_available="true"
        fi
      else
        # The registry could not be reached or gave nothing back. Unchecked.
        latest_version=""
        updates_available=""
        updates_checked="false"
      fi
    else
      # Version unknown -> no real check possible; report 'unchecked'.
      latest_version=""
      updates_available=""
      updates_checked="false"
    fi
  fi

  # Ultra-fast sequential operations (minimal overhead)
  if [[ -d "$instance_working_dir" ]]; then
    if [[ -n "$fast_mode" ]]; then
      # Use du with --max-depth=0 for fastest accurate size check
      # This avoids recursive traversal and gives actual disk usage
      disk_usage=$(du -sh --max-depth=0 "$instance_working_dir" 2>/dev/null | cut -f1)
    else
      disk_usage=$(du -sh "$instance_working_dir" 2>/dev/null | cut -f1)
    fi
  fi

  # Get backup list using existing function
  local backup_list
  backup_list=$(_list_backups 2>/dev/null)

  # Convert backup list to JSON array
  local backup_json_array="[]"
  if [[ -n "$backup_list" ]]; then
    # Convert space-separated list to JSON array
    backup_json_array=$(printf '%s\n' $backup_list | jq -R . | jq -s .)
  fi

  # Recent logs: read the LIVE container logs (docker compose) when active. The logs
  # dir ($instance_logs_dir) holds only ROTATED logs, so reading it first returns
  # nothing between rotations even while the container is actively logging — a false
  # "no logs" that consumers (e.g. the assistant health check) must not mistake for
  # "logs are clean". Prefer live logs; fall back to the newest rotated log; only then
  # an empty array (genuinely nothing to show, never a fabricated ok).
  local _latest_rotated=""
  if [[ -d "$instance_logs_dir" ]]; then
    local latest_log
    latest_log=$(find "$instance_logs_dir" -maxdepth 1 -type f \
      -printf '%T@ %P\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    [[ -n "$latest_log" ]] && _latest_rotated="$instance_logs_dir/$latest_log"
  fi
  if _is_active >/dev/null 2>&1; then
    recent_logs=$(cd "$instance_working_dir" && docker compose -f "$instance_compose_file" logs --tail=3 2>/dev/null | jq -R -s . 2>/dev/null || echo '[]')
  elif [[ -n "$_latest_rotated" ]]; then
    recent_logs=$(tail -3 "$_latest_rotated" 2>/dev/null | jq -R -s . 2>/dev/null || echo '[]')
  else
    recent_logs='[]'
  fi

  if [[ -n "$json_format" ]]; then
    jq -n \
      --arg instance_name "$instance_name" \
      --arg status "$is_active" \
      --arg pid "$pid" \
      --arg process_status "$process_status" \
      --arg start_time "$start_time" \
      --arg current_version "$current_version" \
      --arg latest_version "$latest_version" \
      --arg updates_available "$updates_available" \
      --arg updates_checked "$updates_checked" \
      --arg updates_checked_at "$updates_checked_at" \
      --arg blueprint "$(basename "$instance_blueprint_file")" \
      --arg runtime "$instance_runtime" \
      --arg directory "$instance_working_dir" \
      --arg ports "${instance_ports:-}" \
      --arg disk_usage "$disk_usage" \
      --argjson backup_list "$backup_json_array" \
      --argjson recent_logs "$recent_logs" \
      '{
        instance_name: $instance_name,
        status: ($status == "true"),
        process: {
          pid: (if $pid != "" then ($pid | tonumber) else null end),
          status: (if $process_status != "" then $process_status else null end),
          start_time: (if $start_time != "" then $start_time else null end)
        },
        version: {
          current: $current_version,
          latest: (if $latest_version != "" then $latest_version else null end),
          checked: ($updates_checked == "true"),
          updates_available: (if $updates_checked == "true" then ($updates_available == "true") else null end),
          checked_at: (if $updates_checked_at != "" then $updates_checked_at else null end)
        },
        configuration: {
          blueprint: $blueprint,
          runtime: $runtime,
          directory: $directory,
          ports: (if $ports != "" then $ports else null end)
        },
        resources: {
          disk_usage: (if $disk_usage != "" then $disk_usage else null end)
        },
        backups: $backup_list,
        recent_logs: $recent_logs
      }'
  else
    # Output human-readable format
    echo "=== Instance Status: $instance_name ==="
    echo -n "Status: "
    if [[ "$is_active" == "true" ]]; then
      echo "✓ Active"
      if [[ -n "$pid" ]]; then
        # For human-readable output, show both PID and container info if available
        if [[ -f "$instance_pid_file" ]]; then
          local container_id_display
          container_id_display=$(cat "$instance_pid_file" 2>/dev/null)
          if [[ -n "$container_id_display" ]] && [[ ${#container_id_display} -gt 10 ]]; then
            echo "Container ID: $container_id_display"
            echo "Process ID: $pid"
          else
            echo "Process ID: $pid"
          fi
        else
          echo "Process ID: $pid"
        fi
        if [[ -n "$process_status" ]]; then
          echo "Process Status: $process_status"
        fi
        if [[ -n "$start_time" ]]; then
          echo "Start Time: $start_time"
        fi

        # Show additional container resource info if available
        if [[ -f "$instance_pid_file" ]]; then
          local container_id_for_stats
          container_id_for_stats=$(cat "$instance_pid_file" 2>/dev/null)
          if [[ -n "$container_id_for_stats" ]] && [[ ${#container_id_for_stats} -gt 10 ]]; then
            local resource_info
            resource_info=$(_get_container_process_info "$container_id_for_stats" 2>/dev/null)
            if [[ -n "$resource_info" ]]; then
              echo "Resources: $resource_info"
            fi
          fi
        fi
      fi
    else
      echo "✗ Inactive"
    fi

    echo -n "Version: "
    echo "$current_version"

    echo -n "Updates: "
    if [[ "$updates_checked" != "true" ]]; then
      if [[ -n "$fast_mode" ]]; then
        echo "Not checked (fast mode)"
      else
        echo "Not checked"
      fi
    elif [[ "$updates_available" == "true" ]]; then
      echo "Available (Latest: $latest_version)"
    else
      echo "Up to date"
    fi

    echo "Blueprint: $(basename "$instance_blueprint_file")"
    echo "Runtime: $instance_runtime"
    echo "Directory: $instance_working_dir"

    if [[ -n "$instance_ports" ]]; then
      echo "Ports: $instance_ports"
    fi

    if [[ -n "$disk_usage" ]]; then
      echo "Disk Usage: $disk_usage"
    fi

    echo "Backups:"
    if [[ -n "$backup_list" ]]; then
      printf '%s\n' $backup_list | sed 's/^/  /'
    else
      echo "  No backups available"
    fi

    echo ""
    echo "Recent Activity:"
    if [[ "$recent_logs" != "[]" ]]; then
      echo "$recent_logs" | jq -r '.[]' | sed 's/^/  /'
    else
      echo "  No recent logs available"
    fi
  fi
}

