#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load events logic library
logic_library=$(__find_command_handler events.sh)

# shellcheck source=handlers/events.sh
source "$logic_library" || {
  __print_error "Failed to load events logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Event Journal for Krystal Game Server Manager${END}

The journal is KGSM's event transport and its audit record. KGSM appends one
JSON line per event to a date-named segment and knows nothing about who reads
it; consumers tail the segments holding their own cursor.

${UNDERLINE}Usage:${END}
  ${self} <command> [options]

${UNDERLINE}Commands:${END}
  status                      Show journal location, segments and size
  prune                       Delete segments past the retention window
  verify                      Check every segment is well-formed NDJSON
  help                        Show help information

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  --debug                     Enable debug output

${UNDERLINE}Examples:${END}
  ${self} status
  ${self} prune
  ${self} verify

${UNDERLINE}Notes:${END}
  • Emission is unconditional — there is no switch that disables the journal
  • Retention is time-based only and never consults a consumer
  • Configure with event_journal_dir and event_journal_retention_days
"
}

# Show journal location, segment inventory and total size
function _cmd_status() {
  local _dir
  _dir="$(__logic_journal_dir)"

  echo "Event journal:"
  echo "  Directory:  $_dir"
  echo "  Retention:  ${config_event_journal_retention_days:-90} days"

  if [[ ! -d "$_dir" ]]; then
    echo "  Segments:   0 (directory does not exist yet)"
    __print_info "The directory is created on the first emitted event"
    return $EC_SUCCESS
  fi

  if [[ ! -w "$_dir" ]]; then
    __print_warning "Directory is not writable — events cannot be journaled"
  fi

  local _segments=()
  mapfile -t _segments < <(find "$_dir" -maxdepth 1 -type f \
    -name '*.ndjson' -printf '%f\n' 2>/dev/null | sort)

  echo "  Segments:   ${#_segments[@]}"

  if [[ ${#_segments[@]} -eq 0 ]]; then
    return $EC_SUCCESS
  fi

  local _total_lines=0
  local _segment
  for _segment in "${_segments[@]}"; do
    local _lines
    _lines=$(wc -l < "$_dir/$_segment" 2>/dev/null || echo 0)
    _total_lines=$((_total_lines + _lines))
  done

  echo "  Events:     $_total_lines"
  echo "  Size:       $(du -sh "$_dir" 2>/dev/null | cut -f1)"
  echo "  Oldest:     ${_segments[0]}"
  echo "  Newest:     ${_segments[-1]}"

  return $EC_SUCCESS
}

# Delete segments older than the retention window.
#
# Time-based only: KGSM holds no knowledge of who reads the journal, so a
# segment is never retained on a consumer's behalf. A consumer absent longer
# than the window detects the gap and cold-starts.
function _cmd_prune() {
  local _dir
  _dir="$(__logic_journal_dir)"

  local _days="${config_event_journal_retention_days:-90}"

  if ! [[ "$_days" =~ ^[0-9]+$ ]] || [[ "$_days" -lt 1 ]]; then
    __print_error "Invalid event_journal_retention_days: '$_days'"
    __print_info "Expected a positive integer (days)"
    return $EC_INVALID_CONFIG
  fi

  if [[ ! -d "$_dir" ]]; then
    __print_info "No journal directory at $_dir, nothing to prune"
    return $EC_SUCCESS
  fi

  local _stale=()
  mapfile -t _stale < <(find "$_dir" -maxdepth 1 -type f \
    -name '*.ndjson' -mtime +"$_days" 2>/dev/null | sort)

  if [[ ${#_stale[@]} -eq 0 ]]; then
    __print_info "No segments older than $_days days"
    return $EC_SUCCESS
  fi

  local _segment
  local _failed=0
  for _segment in "${_stale[@]}"; do
    if rm -f "$_segment" 2>/dev/null; then
      __print_info "Pruned $(basename "$_segment")"
    else
      __print_error "Failed to prune $(basename "$_segment")"
      _failed=$((_failed + 1))
    fi
  done

  if [[ $_failed -gt 0 ]]; then
    return $EC_ERROR
  fi

  __print_success "Pruned ${#_stale[@]} segment(s) older than $_days days"
  return $EC_SUCCESS
}

# Check every segment parses as one JSON object per line.
#
# A consumer's cursor is a byte offset into a segment, so a malformed line is
# not a cosmetic problem: it desynchronizes every reader past that point.
function _cmd_verify() {
  local _dir
  _dir="$(__logic_journal_dir)"

  if [[ ! -d "$_dir" ]]; then
    __print_info "No journal directory at $_dir, nothing to verify"
    return $EC_SUCCESS
  fi

  if ! command -v jq > /dev/null 2>&1; then
    __print_error "jq is required to verify the journal but is not installed"
    return $EC_MISSING_DEPENDENCY
  fi

  local _segments=()
  mapfile -t _segments < <(find "$_dir" -maxdepth 1 -type f \
    -name '*.ndjson' -printf '%f\n' 2>/dev/null | sort)

  if [[ ${#_segments[@]} -eq 0 ]]; then
    __print_info "No segments to verify"
    return $EC_SUCCESS
  fi

  local _bad_total=0
  local _segment
  for _segment in "${_segments[@]}"; do
    local _line_no=0
    local _bad=0

    while IFS= read -r _line; do
      _line_no=$((_line_no + 1))

      if [[ -z "$_line" ]]; then
        __print_error "$_segment:$_line_no: empty line"
        _bad=$((_bad + 1))
        continue
      fi

      if ! printf '%s' "$_line" | jq -e . > /dev/null 2>&1; then
        __print_error "$_segment:$_line_no: not valid JSON"
        _bad=$((_bad + 1))
      fi
    done < "$_dir/$_segment"

    if [[ $_bad -eq 0 ]]; then
      __print_info "$_segment: $_line_no event(s) OK"
    fi

    _bad_total=$((_bad_total + _bad))
  done

  if [[ $_bad_total -gt 0 ]]; then
    __print_error "$_bad_total malformed line(s) found"
    return $EC_ERROR
  fi

  __print_success "All ${#_segments[@]} segment(s) well-formed"
  return $EC_SUCCESS
}

# Parse command
command="${1:-}"
shift 2> /dev/null || true

# Route to command handlers
case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  -h | --help | help)
    show_usage
    exit $EC_SUCCESS
    ;;
  status)
    _cmd_status "$@"
    exit $?
    ;;
  prune)
    _cmd_prune "$@"
    exit $?
    ;;
  verify)
    _cmd_verify "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
