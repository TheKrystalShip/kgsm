#!/bin/bash
# Script for testing function calls and stack frames

add() {
  local a=$1
  local b=$2
  local sum=$((a + b))
  echo "$sum"
}

multiply() {
  local x=$1
  local y=$2
  local product=$((x * y))
  echo "$product"
}

result1=$(add 3 5)
result2=$(multiply 4 6)
echo "Add: $result1, Multiply: $result2"
