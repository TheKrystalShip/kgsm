#!/usr/bin/env bash

# This library provides shortcuts to modules for easier access within other scripts.
# Each function is a simple wrapper that delegates to the actual module file.

if [[ -n "${KGSM_DELEGATOR_LOADED:-}" ]]; then
  return 0
fi

# This function generates delegator functions dynamically for each module found
# in the modules directory.
# Each generated function will have the same name as the module file
function _init_delagator() {
  local module_file
  local module_name

  # Find all .sh files in modules directory
  while IFS= read -r -d '' module_file; do
    module_name="$(basename "$module_file")"

    # Create wrapper function dynamically
    # Using eval to define the function with the module name
    eval "
      function ${module_name}() {
        \"\$(__find_command ${module_name})\" \"\$@\"
      }
      export -f ${module_name}
    "
  done < <(find "$KGSM_COMMANDS_DIR" -maxdepth 1 -type f -name '*.sh' -print0)
}

_init_delagator

unset -f _init_delagator

declare -g KGSM_DELEGATOR_LOADED=1
export KGSM_DELEGATOR_LOADED
