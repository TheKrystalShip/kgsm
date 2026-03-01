#!/bin/bash
# Script for testing error handling

good_function() {
  echo "This works"
  return 0
}

bad_function() {
  echo "About to fail"
  return 1
}

good_function
bad_function
echo "After bad function, exit code: $?"
