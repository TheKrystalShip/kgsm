#!/usr/bin/env bash

# KGSM Core - cgroup v2 process supervision primitives
#
# These helpers let KGSM place a game-server process (and every child it ever
# spawns, including detached/double-forked ones) into a kernel-tracked cgroup
# that it cannot escape. This is the foundation that gives native instances the
# same supervision systemd gets for free: child-inclusive liveness
# (`cgroup.events`), atomic whole-tree teardown (`cgroup.kill`), and accurate
# per-instance accounting.
#
# All functions operate on KGSM's delegated base, resolved from config. Under
# systemd cgroup delegation that base is kgsm-watchdog's own service cgroup
# (kgsm.slice/kgsm-watchdog.service) — systemd creates + delegates it, so KGSM no
# longer prepares it (`kgsm system setup-cgroups` is legacy). KGSM mainly DERIVES
# the per-instance path here to surface it as each instance's `cgroup_path`; the
# watchdog is what actually creates/moves/kills the cgroups. They communicate via
# exit codes and print only on hard failure. Callers gate on `__cgroup_supported`.
#
# Config (flattened to config_* by core/config.sh):
#   config_enable_cgroups       master switch (true|false)
#   config_cgroup_mount_point   cgroup v2 mount (default /sys/fs/cgroup)
#   config_cgroup_base_name     delegated base, MUST match the watchdog's layout
#                               (default kgsm.slice/kgsm-watchdog.service)
#   config_cgroup_controllers   space-separated controllers (cpu memory io pids)

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# Controller lists are intentionally word-split.
# shellcheck disable=SC2086

if [[ -n "${KGSM_CGROUP_LOADED:-}" ]]; then
  return 0
fi

# Echo the absolute path of KGSM's delegated cgroup base.
# Returns: base path to stdout (e.g. /sys/fs/cgroup/kgsm.slice)
function __cgroup_base() {
  local mount_point="${config_cgroup_mount_point:-/sys/fs/cgroup}"
  local base_name="${config_cgroup_base_name:-kgsm.slice/kgsm-watchdog.service}"
  echo "${mount_point}/${base_name}"
}

export -f __cgroup_base

# Echo the per-instance cgroup path under the base.
# Args: $1 = instance name (a trailing .ini is stripped)
# Returns: path to stdout, EC_INVALID_ARG on missing name
function __cgroup_path() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  echo "$(__cgroup_base)/${instance_name%.ini}"
}

export -f __cgroup_path

# Echo the controllers to enable in '+x' subtree_control form.
# Returns: e.g. "+cpu +memory +io +pids" to stdout
function __cgroup_enable_string() {
  local controllers="${config_cgroup_controllers:-cpu memory io pids}"
  local out="" controller

  for controller in $controllers; do
    out+="+${controller} "
  done

  echo "${out% }"
}

export -f __cgroup_enable_string

# Enable the configured controllers in a cgroup's subtree_control so its
# children inherit them. Idempotent: controllers already enabled are skipped.
# Used at delegation/setup time on the mount root and on KGSM's base.
# Args: $1 = cgroup directory (containing cgroup.subtree_control)
# Returns: 0 on success, EC_INVALID_ARG / EC_CGROUP on failure
function __cgroup_enable_controllers() {
  local cg_dir="$1"

  if [[ -z "$cg_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  local sc="${cg_dir}/cgroup.subtree_control"
  if [[ ! -f "$sc" ]]; then
    return $EC_CGROUP
  fi

  local current token controller
  current="$(cat "$sc" 2> /dev/null)"

  for token in $(__cgroup_enable_string); do
    controller="${token#+}"
    # Skip controllers already enabled in this subtree.
    case " $current " in
      *" $controller "*) continue ;;
    esac
    # Brace group so a failed open of "$sc" is also silenced, not just echo.
    if ! { echo "$token" > "$sc"; } 2> /dev/null; then
      return $EC_CGROUP
    fi
  done

  return 0
}

export -f __cgroup_enable_controllers

# Return 0 if the running kernel is >= 5.14 (when cgroup.kill landed).
# Returns: 0 if new enough, EC_CGROUP_UNSUPPORTED otherwise
function __cgroup_kernel_has_kill() {
  local kver major minor
  kver="$(uname -r 2> /dev/null)"
  major="${kver%%.*}"
  minor="${kver#*.}"
  minor="${minor%%.*}"

  if [[ ! "$major" =~ ^[0-9]+$ ]] || [[ ! "$minor" =~ ^[0-9]+$ ]]; then
    return $EC_CGROUP_UNSUPPORTED
  fi

  if [[ "$major" -gt 5 ]] || { [[ "$major" -eq 5 ]] && [[ "$minor" -ge 14 ]]; }; then
    return 0
  fi

  return $EC_CGROUP_UNSUPPORTED
}

export -f __cgroup_kernel_has_kill

# Detect whether cgroup v2 supervision is usable on this host.
# Checks, in order: cgroup v2 unified mount, kernel >= 5.14, and that KGSM's
# base is present and writable (delegated via `kgsm system setup-cgroups`).
# Returns: 0 if usable, EC_CGROUP_UNSUPPORTED otherwise (no output)
function __cgroup_supported() {
  local mount_point="${config_cgroup_mount_point:-/sys/fs/cgroup}"
  local base
  base="$(__cgroup_base)"

  # 1. cgroup v2 unified hierarchy mounted? (v1/hybrid lack this file)
  if [[ ! -f "${mount_point}/cgroup.controllers" ]]; then
    return $EC_CGROUP_UNSUPPORTED
  fi

  # 2. Kernel new enough for atomic cgroup.kill.
  if ! __cgroup_kernel_has_kill; then
    return $EC_CGROUP_UNSUPPORTED
  fi

  # 3. Base delegated and writable (we can create children + move PIDs unpriv).
  if [[ ! -d "$base" ]] || [[ ! -w "$base" ]]; then
    return $EC_CGROUP_UNSUPPORTED
  fi

  return 0
}

export -f __cgroup_supported

# Create the per-instance cgroup (idempotent).
# Controllers are made available to children at delegation time (setup-cgroups
# writes the base's cgroup.subtree_control), so this only needs to mkdir.
# Args: $1 = instance name
# Returns: 0 on success, EC_INVALID_ARG / EC_CGROUP on failure
function __cgroup_create() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local cg
  cg="$(__cgroup_path "$instance_name")"

  if ! mkdir -p "$cg" 2> /dev/null; then
    __print_error "Failed to create cgroup: $cg"
    return $EC_CGROUP
  fi

  return 0
}

export -f __cgroup_create

# Move a process (and its future children) into the instance cgroup.
# Args: $1 = instance name, $2 = pid
# Returns: 0 on success, EC_INVALID_ARG / EC_CGROUP on failure
function __cgroup_attach() {
  local instance_name="$1"
  local pid="$2"

  if [[ -z "$instance_name" ]] || [[ -z "$pid" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    return $EC_INVALID_ARG
  fi

  local cg
  cg="$(__cgroup_path "$instance_name")"

  if ! { echo "$pid" > "${cg}/cgroup.procs"; } 2> /dev/null; then
    __print_error "Failed to attach PID $pid to cgroup $cg"
    return $EC_CGROUP
  fi

  return 0
}

export -f __cgroup_attach

# Liveness: return 0 if the instance cgroup still has live processes, 1 if it is
# empty or absent. Reads cgroup.events 'populated' — child-inclusive and
# race-free, unlike a PID check.
# Args: $1 = instance name
# Returns: 0 = populated (alive), 1 = empty/gone, EC_INVALID_ARG on bad args
function __cgroup_is_populated() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local cg events_line
  cg="$(__cgroup_path "$instance_name")"

  if [[ ! -f "${cg}/cgroup.events" ]]; then
    return 1
  fi

  events_line="$(grep '^populated ' "${cg}/cgroup.events" 2> /dev/null)"
  [[ "$events_line" == "populated 1" ]] && return 0
  return 1
}

export -f __cgroup_is_populated

# Atomically SIGKILL every process in the instance cgroup (whole subtree).
# Args: $1 = instance name
# Returns: 0 on success, EC_CGROUP_UNSUPPORTED if cgroup.kill missing, EC_CGROUP
function __cgroup_kill() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local cg
  cg="$(__cgroup_path "$instance_name")"

  if [[ ! -f "${cg}/cgroup.kill" ]]; then
    return $EC_CGROUP_UNSUPPORTED
  fi

  if ! { echo 1 > "${cg}/cgroup.kill"; } 2> /dev/null; then
    __print_error "Failed to kill cgroup: $cg"
    return $EC_CGROUP
  fi

  return 0
}

export -f __cgroup_kill

# Remove the (now-empty) instance cgroup. Best-effort: a populated cgroup cannot
# be removed, so callers should kill + wait for it to drain first.
# Args: $1 = instance name
# Returns: 0 on success or already-gone, EC_CGROUP if still populated
function __cgroup_remove() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local cg
  cg="$(__cgroup_path "$instance_name")"

  if [[ ! -d "$cg" ]]; then
    return 0
  fi

  if ! rmdir "$cg" 2> /dev/null; then
    __print_warning "Failed to remove cgroup (still populated?): $cg"
    return $EC_CGROUP
  fi

  return 0
}

export -f __cgroup_remove

# Mark module as loaded
declare -g KGSM_CGROUP_LOADED=1
export KGSM_CGROUP_LOADED
