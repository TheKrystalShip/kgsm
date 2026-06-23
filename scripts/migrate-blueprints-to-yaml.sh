#!/usr/bin/env bash

# One-time migration: legacy blueprints -> unified `.bp.yaml`.
#
# Converts the 23 native `blueprints/native/*.bp` (key=value INI) and the 6
# container `blueprints/container/*.docker-compose.yml` (raw Docker Compose)
# into the unified YAML format in a single flat `blueprints/` directory.
#
# This is NOT a runtime KGSM module — it is a developer tool run once during the
# format cutover, then kept for reference. It only READS the legacy files and
# WRITES new `.bp.yaml` files; it does not delete anything (the old dirs are
# removed by the cutover commit after the output is verified).
#
# Metadata is emitted as null skeletons (display_name, description, rawg_slug,
# max_players, min_ram_mb, recommended_ram_mb, base_disk_mb) — `null` means unknown, NEVER a
# fabricated 0. Real values are curated separately, file by file, afterwards.
#
# Requires: mikefarah/yq (go-yq).

set -euo pipefail

KGSM_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
readonly KGSM_ROOT
readonly NATIVE_DIR="$KGSM_ROOT/blueprints/native"
readonly CONTAINER_DIR="$KGSM_ROOT/blueprints/container"
readonly OUT_DIR="$KGSM_ROOT/blueprints"

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq (mikefarah/go-yq) is required." >&2
  exit 1
fi

export META_COMMENT="TODO: curate — advisory values researched per game; null = unknown/unbounded, NEVER 0"

# Parse a legacy native .bp into the global associative array `kv`.
# Splits on the first '=', strips one layer of surrounding matching quotes —
# equivalent to core/loader.sh __source_with_prefix.
function parse_native() {
  local file="$1"
  unset kv
  declare -gA kv=()
  local line k v
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]] || continue
    k="${BASH_REMATCH[1]}"
    v="${BASH_REMATCH[2]}"
    v="${v#\"}"; v="${v%\"}"
    v="${v#\'}"; v="${v%\'}"
    kv["$k"]="$v"
  done <"$file"
}

function convert_native() {
  local file="$1"
  parse_native "$file"

  local out="$OUT_DIR/${kv[name]}.bp.yaml"

  # Strings via strenv() (literal, no YAML interpolation of $ or quotes);
  # numbers/bools via env() so steam_app_id stays int and the bool stays bool.
  name="${kv[name]}" \
  ports="${kv[ports]:-}" \
  steam_app_id="${kv[steam_app_id]:-0}" \
  client_steam_app_id="${kv[client_steam_app_id]:-0}" \
  steamcmd_arguments="${kv[steamcmd_arguments]:-}" \
  is_steam_account_required="${kv[is_steam_account_required]:-false}" \
  platform="${kv[platform]:-linux}" \
  level_name="${kv[level_name]:-default}" \
  executable_subdirectory="${kv[executable_subdirectory]:-}" \
  executable_file="${kv[executable_file]:-}" \
  executable_arguments="${kv[executable_arguments]:-}" \
  stop_command="${kv[stop_command]:-}" \
  save_command="${kv[save_command]:-}" \
  startup_success_regex="${kv[startup_success_regex]:-}" \
  yq -n '
    .schema_version = 1
    | .name = strenv(name)
    | .runtime = "native"
    | .metadata.display_name = null
    | .metadata.description = null
    | .metadata.rawg_slug = null
    | .metadata.max_players = null
    | .metadata.min_ram_mb = null
    | .metadata.recommended_ram_mb = null
    | .metadata.base_disk_mb = null
    | .metadata head_comment = strenv(META_COMMENT)
    | .native.ports = strenv(ports)
    | .native.steam_app_id = env(steam_app_id)
    | .native.client_steam_app_id = env(client_steam_app_id)
    | .native.steamcmd_arguments = strenv(steamcmd_arguments)
    | .native.is_steam_account_required = env(is_steam_account_required)
    | .native.platform = strenv(platform)
    | .native.level_name = strenv(level_name)
    | .native.executable_subdirectory = strenv(executable_subdirectory)
    | .native.executable_file = strenv(executable_file)
    | .native.executable_arguments = strenv(executable_arguments)
    | .native.stop_command = strenv(stop_command)
    | .native.save_command = strenv(save_command)
    | .native.startup_success_regex = strenv(startup_success_regex)
  ' >"$out"

  echo "  native    -> $(basename "$out")"
}

function convert_container() {
  local file="$1"
  local name
  name="$(basename "$file" .docker-compose.yml)"

  local out="$OUT_DIR/${name}.bp.yaml"

  # Embed the compose verbatim from the first `services:` line onward (drops the
  # legacy KGSM boilerplate header, keeps every inline comment and ${instance_*}
  # placeholder). Forced to a literal block scalar so it round-trips unchanged.
  local compose
  compose="$(sed -n '/^services:/,$p' "$file")"

  name="$name" compose="$compose" \
  yq -n '
    .schema_version = 1
    | .name = strenv(name)
    | .runtime = "container"
    | .metadata.display_name = null
    | .metadata.description = null
    | .metadata.rawg_slug = null
    | .metadata.max_players = null
    | .metadata.min_ram_mb = null
    | .metadata.recommended_ram_mb = null
    | .metadata.base_disk_mb = null
    | .metadata head_comment = strenv(META_COMMENT)
    | .container.compose = strenv(compose)
    | .container.compose style="literal"
  ' >"$out"

  echo "  container -> $(basename "$out")"
}

echo "Converting native blueprints ($NATIVE_DIR):"
for f in "$NATIVE_DIR"/*.bp; do
  [[ -e "$f" ]] || continue
  convert_native "$f"
done

echo "Converting container blueprints ($CONTAINER_DIR):"
for f in "$CONTAINER_DIR"/*.docker-compose.yml; do
  [[ -e "$f" ]] || continue
  convert_container "$f"
done

echo "Done. Output in $OUT_DIR/*.bp.yaml (old dirs untouched)."
