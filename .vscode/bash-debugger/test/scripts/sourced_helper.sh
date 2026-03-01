#!/bin/bash
# Helper script sourced by sourced.sh

helper_var="from helper"

helper_function() {
  local input=$1
  echo "processed: $input"
}
