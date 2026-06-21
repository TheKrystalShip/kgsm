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
  local disk_usage=""
  local backup_count=""
  local recent_logs=""

  # Check if instance is active
  if _is_active >/dev/null 2>&1; then
    is_active="true"

    # Get process information if active (optimized)
    if [[ -f "$instance_pid_file" ]]; then
      pid=$(cat "$instance_pid_file" 2>/dev/null)
      if [[ -n "$pid" ]] && ps -p "$pid" &>/dev/null; then
        # Get process info in one ps call instead of two
        local ps_output
        ps_output=$(ps -p "$pid" -o state,lstart --no-headers 2>/dev/null)
        if [[ -n "$ps_output" ]]; then
          process_status=$(echo "$ps_output" | awk '{print $1}' | tr -d ' ')
          local _lstart
          _lstart=$(echo "$ps_output" | awk '{$1=""; print substr($0,2)}')
          start_time=$(_to_iso_utc "$_lstart")
        fi
      fi
    fi
  fi

  # Get version information (optimized)
  current_version=$(_get_installed_version 2>/dev/null || echo "Unknown")

  if [[ -n "$fast_mode" ]]; then
    # Fast mode skips the (networked) update check. Do NOT fabricate a result:
    # report 'unchecked' (updates_checked=false) rather than claiming "up to date".
    latest_version=""
    updates_available=""
    updates_checked="false"
  else
    # Only a known current version allows a real comparison.
    if [[ "$current_version" != "Unknown" ]]; then
      updates_checked="true"
      if _compare_versions >/dev/null 2>&1; then
        latest_version=$(_get_latest_version 2>/dev/null || echo "Unknown")
        updates_available="true"
      else
        latest_version="$current_version"
        updates_available="false"
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

  # Fast logs (minimal processing)
  if [[ -d "$instance_logs_dir" ]]; then
    local latest_log
    latest_log=$(ls -t "$instance_logs_dir" 2>/dev/null | head -1)
    if [[ -n "$latest_log" ]]; then
      recent_logs=$(tail -3 "$instance_logs_dir/$latest_log" 2>/dev/null | jq -R -s . 2>/dev/null || echo '[]')
    else
      recent_logs='[]'
    fi
  else
    recent_logs='[]'
  fi

  if [[ -n "$json_format" ]]; then
    # Output JSON format
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
          updates_available: (if $updates_checked == "true" then ($updates_available == "true") else null end)
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
        echo "Process ID: $pid"
        if [[ -n "$process_status" ]]; then
          echo "Process Status: $process_status"
        fi
        if [[ -n "$start_time" ]]; then
          echo "Start Time: $start_time"
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

