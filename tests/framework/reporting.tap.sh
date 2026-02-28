#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - TAP Reporter Module
# ==============================================================================
# Version: 2.0
# Description: Provides TAP v14 failure detail extraction for VS Code integration.
#              The main TAP generation is handled by run.sh's
#              generate_tap_from_results(). This module provides the helper
#              that parses log files to extract per-assertion failure details.
# Dependencies: None (standalone parsing functions)
# ==============================================================================

# shellcheck disable=SC2086

if [[ -n "${TEST_REPORTING_TAP_LOADED:-}" ]]; then
  return 0
fi

# ------------------------------------------------------------------------------
# Emit failure detail entries from a test log file
# ------------------------------------------------------------------------------
# Parses the test log for FAIL assertion lines and emits them as a YAML
# array in the TAP diagnostic block. Each entry includes the source line
# number, function name, failure message, and expected/actual values.
#
# Log line format (written by assert.sh's print_assert_result):
#   [TIMESTAMP] [ERROR] [filename.sh:LINE in function()] FAIL: message
#   ASSERT_DETAIL: expected=X actual=Y
#
# Arguments:
#   $1 - log_path: Absolute path to the test log file
#   $2 - test_file: Relative path to test source file (for file: field)
# Returns:
#   Exit code: 0
# Output:
#   YAML array entries to stdout (indented for TAP diagnostic block)
# ------------------------------------------------------------------------------
function __tap_emit_failure_details() {
  local log_path="$1"
  local test_file="${2:-}"

  if [[ -z "$log_path" || ! -f "$log_path" ]]; then
    return 0
  fi

  # Read all lines into an array for look-ahead capability
  local -a log_lines
  mapfile -t log_lines < <(grep -n '' "$log_path" 2>/dev/null || true)

  # Find indices of FAIL lines
  local -a fail_indices=()
  local i
  for i in "${!log_lines[@]}"; do
    if [[ "${log_lines[$i]}" == *'] FAIL: '* ]]; then
      fail_indices+=("$i")
    fi
  done

  if [[ ${#fail_indices[@]} -eq 0 ]]; then
    return 0
  fi

  echo "  failures:"

  for i in "${fail_indices[@]}"; do
    local line="${log_lines[$i]}"
    local source_info fail_message line_num func_name

    # Extract the source bracket: [filename.sh:LINE in function()]
    source_info=$(echo "$line" | grep -oP '\[\K[^]]+\.sh:\d+ in [^]]+' || true)

    # Extract the FAIL message after "FAIL: "
    fail_message=$(echo "$line" | sed -n 's/.*FAIL: //p' || true)

    if [[ -n "$source_info" && -n "$fail_message" ]]; then
      # Parse line number from "filename.sh:LINE in function()"
      line_num=$(echo "$source_info" | grep -oP ':\K\d+' || echo "0")
      # Parse function name
      func_name=$(echo "$source_info" | grep -oP 'in \K[^()]+' || echo "unknown")

      # Escape quotes in the message for YAML
      fail_message="${fail_message//\"/\\\"}"

      echo "    - line: ${line_num}"
      echo "      function: \"${func_name}\""
      echo "      message: \"${fail_message}\""

      # Check if the next line contains ASSERT_DETAIL
      local next_idx=$((i + 1))
      if [[ $next_idx -lt ${#log_lines[@]} ]]; then
        local next_line="${log_lines[$next_idx]}"
        if [[ "$next_line" == *'ASSERT_DETAIL: expected='* ]]; then
          local detail_part="${next_line##*ASSERT_DETAIL: }"
          local exp_val act_val
          exp_val=$(echo "$detail_part" | sed -n 's/^expected=\(.*\) actual=.*$/\1/p')
          act_val=$(echo "$detail_part" | sed -n 's/^.*actual=\(.*\)$/\1/p')
          if [[ -n "$exp_val" || -n "$act_val" ]]; then
            echo "      expected: \"${exp_val//\"/\\\"}\""
            echo "      actual: \"${act_val//\"/\\\"}\""
          fi
        fi
      fi

      if [[ -n "$test_file" ]]; then
        echo "      file: \"${test_file}\""
      fi
    fi
  done

  return 0
}
export -f __tap_emit_failure_details

# ==============================================================================
# Module Initialization
# ==============================================================================

declare -g TEST_REPORTING_TAP_LOADED=1
export TEST_REPORTING_TAP_LOADED
