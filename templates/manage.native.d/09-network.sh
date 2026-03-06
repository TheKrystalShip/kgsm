# =============================================================================
# NETWORK (UPnP)
# =============================================================================

function _enable_upnp() {
  local output

  __print_info "Enabling UPnP..."

  # Check if UPnP ports array is set and not empty
  # This prevents command failures when the array is unset or empty
  if [[ -z "${instance_upnp_ports[*]:-}" ]]; then
    __print_error "No UPnP ports configured (instance_upnp_ports is empty or unset)"
    return $EC_ERROR
  fi

  if ! output=$(upnpc -e "$instance_name" -r "${instance_upnp_ports[@]}" 2>&1); then
    __print_error "Failed to enable UPnP ports"
    __print_error "To stop these messages, set 'enable_port_forwarding' to 'false' in $CONFIG_FILE"
    __print_error "${output}"
    return $EC_ERROR
  fi

  # Mark UPnP as enabled
  touch "$instance_port_forwarding_state_file"
  __print_success "UPnP enabled"
}

function _disable_upnp() {
  local output

  if ! _is_upnp_enabled; then
    return $EC_SUCCESS
  fi

  __print_info "Disabling UPnP..."

  # Check if UPnP ports array is set and not empty
  # This prevents command failures when the array is unset or empty
  if [[ -z "${instance_upnp_ports[*]:-}" ]]; then
    __print_error "No UPnP ports configured (instance_upnp_ports is empty or unset)"
    return $EC_ERROR
  fi

  if ! output=$(upnpc -f "${instance_upnp_ports[@]}" 2>&1); then
    __print_error "Failed to disable UPnP ports"
    __print_error "To stop these messages, set 'enable_port_forwarding' to 'false' in $CONFIG_FILE"
    __print_error "${output}"
    return $EC_ERROR
  fi

  # Mark UPnP as disabled
  rm -f "$instance_port_forwarding_state_file"
  __print_success "UPnP disabled"
}

# Helper function to check if UPnP is currently enabled
function _is_upnp_enabled() {
  [[ -f "$instance_port_forwarding_state_file" ]]
}

