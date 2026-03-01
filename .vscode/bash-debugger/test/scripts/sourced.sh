#!/bin/bash
# Script that sources another file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/sourced_helper.sh"

main_var="from main"
helper_result=$(helper_function "test input")
echo "Main: $main_var, Helper: $helper_result"
