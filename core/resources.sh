#!/usr/bin/env bash

# KGSM Core - node resource admission
#
# Whether the node has room to start an instance. The kernel's OOM killer does
# not choose politely: it picks by its own heuristic, which on a box full of game
# servers may well be a different server than the one that asked for the memory,
# or the watchdog supervising all of them. A refused start costs one operator a
# retry; an OOM costs whatever was running.
#
# THE GATE IS NOT ONLY HERE. The CLI is one of two things that start instances —
# kgsm-watchdog starts them at boot (autostart) and after a crash (restart),
# never passing through this code. Both read the same two config keys, so the
# host has one answer rather than two that can disagree:
#
#   config_enable_memory_gate        master switch (true|false)
#   config_memory_gate_headroom_mb   megabytes that must remain free after a start
#
# Config is flattened to config_* by core/config.sh.

# Disabling SC2086 globally: exit codes and numeric readings are safe unquoted.
# shellcheck disable=SC2086

# The node's available memory, in megabytes, or empty when it cannot be read.
#
# MemAvailable, deliberately, NOT MemFree. MemFree counts only pages nobody is
# using at all; it excludes page cache the kernel will hand back the moment
# something asks. On a host that has been up a while MemFree is a small number
# next to a large cache, and gating on it would refuse starts with many gigabytes
# genuinely available. MemAvailable is the kernel's own estimate of what a new
# allocation can have without swapping, which is the question being asked here.
function __memory_available_mb() {
  local kb
  kb=$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo 2> /dev/null)

  # No reading is not a reading of zero. An unreadable /proc/meminfo leaves the
  # gate unable to answer, and it says so rather than refusing every start.
  [[ -z "$kb" ]] && return 1

  echo $((kb / 1024))
  return 0
}

export -f __memory_available_mb

# What one instance is expected to need, in megabytes, or empty when unknown.
#
# Two sources, in order, and the order is the point:
#
#   1. The instance's own memory_cap_mb, when set. This is the cgroup ceiling the
#      watchdog writes to memory.max before the game is born, so the instance
#      CANNOT exceed it — it bounds exactly what the node stands to lose, and an
#      operator chose it deliberately.
#   2. The blueprint's metadata.min_ram_mb. Advisory, vendor-declared, and openly
#      uncurated for many games, which is why it is the fallback and not the
#      primary: an over-stated figure here refuses a start that would have worked.
#
# Neither known means the gate has nothing to compare and says so. A default is
# NOT invented to fill the hole — a fabricated requirement would refuse real
# starts on a number nobody measured.
#
# Usage: __instance_memory_requirement_mb <instance_config_file>
function __instance_memory_requirement_mb() {
  local _instance_config_file="$1"
  [[ -z "$_instance_config_file" || ! -f "$_instance_config_file" ]] && return 1

  local cap
  cap=$(__get_config_value "$_instance_config_file" "memory_cap_mb" 2> /dev/null)
  # 0 is kgsm's spelling of "uncapped" for this key, not a request for no memory.
  if [[ "$cap" =~ ^[0-9]+$ ]] && [[ "$cap" -gt 0 ]]; then
    echo "$cap"
    return 0
  fi

  local blueprint_file
  blueprint_file=$(__get_config_value "$_instance_config_file" "blueprint_file" 2> /dev/null)
  [[ -z "$blueprint_file" || ! -f "$blueprint_file" ]] && return 1

  # yq is an optional dependency elsewhere in kgsm, so its absence must leave the
  # gate unable to answer rather than failing the start.
  command -v yq > /dev/null 2>&1 || return 1

  local min_ram
  min_ram=$(yq -r '.metadata.min_ram_mb // ""' "$blueprint_file" 2> /dev/null)
  if [[ "$min_ram" =~ ^[0-9]+$ ]] && [[ "$min_ram" -gt 0 ]]; then
    echo "$min_ram"
    return 0
  fi

  return 1
}

export -f __instance_memory_requirement_mb

# Would starting this instance leave the node with less than the headroom floor?
#
# Returns 0 to allow, $EC_INSUFFICIENT_MEMORY to refuse. The refusal sentence goes
# to stderr and names all three figures, because "not enough memory" on its own
# tells an operator nothing about whether to stop something, lower a cap, or edit
# a blueprint.
#
# It allows — and says why — in every case where it cannot answer: gate disabled,
# no requirement declared, /proc/meminfo unreadable. A gate that refuses on its
# own ignorance is a gate that takes servers down for a missing yq.
#
# Usage: __memory_gate_check <instance_name> <instance_config_file>
function __memory_gate_check() {
  local _instance_name="$1"
  local _instance_config_file="$2"

  if [[ "${config_enable_memory_gate:-true}" != "true" ]]; then
    __print_debug "Memory gate disabled; starting $_instance_name without a capacity check"
    return 0
  fi

  local required
  if ! required=$(__instance_memory_requirement_mb "$_instance_config_file"); then
    __print_debug "No memory requirement declared for $_instance_name (no memory_cap_mb, no blueprint min_ram_mb); capacity not checked"
    return 0
  fi

  local available
  if ! available=$(__memory_available_mb); then
    __print_debug "Could not read MemAvailable from /proc/meminfo; capacity not checked for $_instance_name"
    return 0
  fi

  local headroom="${config_memory_gate_headroom_mb:-1024}"
  [[ "$headroom" =~ ^[0-9]+$ ]] || headroom=1024

  local remaining=$((available - required))
  if [[ $remaining -lt $headroom ]]; then
    __print_error "Not enough memory to start $_instance_name: it needs ${required}MB, the node has ${available}MB available, and starting it would leave ${remaining}MB against a required floor of ${headroom}MB."
    __print_error "Stop another instance to free memory, lower this instance's memory_cap_mb, or start it anyway with --force."
    return $EC_INSUFFICIENT_MEMORY
  fi

  __print_debug "Memory gate passed for $_instance_name: needs ${required}MB of ${available}MB available, leaving ${remaining}MB (floor ${headroom}MB)"
  return 0
}

export -f __memory_gate_check
