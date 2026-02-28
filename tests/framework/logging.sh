#!/usr/bin/env bash

# KGSM Test Framework - Logging Module
#
# Author: The Krystal Ship Team
# Version: 2.0
#
# Provides simple logging helpers for tests and framework modules.
# Assertion logging is handled directly by assert.sh (writes to $KGSM_TEST_LOG).
# This module provides log_test_step() (used extensively in test files) and
# basic log_info/error/warning/debug for framework modules.

# shellcheck disable=SC2086

if [[ -n "${TEST_LOGGING_LOADED:-}" ]]; then
  return 0
fi

# Color codes (if not already set)
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${NC:=\033[0m}"

# =============================================================================
# CORE LOGGING
# =============================================================================

# Write a message to the test log file (if set)
function __log_to_file() {
  local level="$1"
  local message="$2"

  if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
    local clean_message
    clean_message=$(echo "$message" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date -Iseconds)] [$level] $clean_message" >> "$KGSM_TEST_LOG"
  fi
}

export -f __log_to_file

# =============================================================================
# PUBLIC API
# =============================================================================

# Log a test step — used extensively (~1300 calls) in test files for tracing
function log_test_step() {
  __log_to_file "STEP" "$1"
}

export -f log_test_step

function log_info() {
  __log_to_file "INFO" "$1"
}

export -f log_info

function log_debug() {
  __log_to_file "DEBUG" "$1"
}

export -f log_debug

function log_warning() {
  __log_to_file "WARN" "$1"
}

export -f log_warning

function log_error() {
  __log_to_file "ERROR" "$1"
}

export -f log_error

# =============================================================================
# INITIALIZATION
# =============================================================================

declare -g TEST_LOGGING_LOADED=1
export TEST_LOGGING_LOADED
