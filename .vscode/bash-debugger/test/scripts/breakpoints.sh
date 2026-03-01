#!/bin/bash
# Script for testing breakpoints

counter=0
for i in 1 2 3 4 5; do
  counter=$((counter + i))
done

if [[ $counter -gt 10 ]]; then
  echo "Counter is large: $counter"
else
  echo "Counter is small: $counter"
fi

echo "Done: $counter"
