# =============================================================================
# BACKUP MANAGEMENT
# =============================================================================
#
# A backup is a DIRECTORY under $instance_backups_dir, named with an opaque id:
#
#   <instance>-<YYYYMMDDTHHMMSSZ>-<6 hex>/
#     manifest.json     what this backup is (the only source of that truth)
#     data.tar.gz       compress_backups=true
#     data/             compress_backups=false
#
# Nothing parses the id: everything a consumer needs is in manifest.json, so the
# id is free to be opaque and sortable (UTC, no colons, lexicographic order ==
# chronological order, unique within a second).
#
# The archive captures the instance's install AND saves subtrees, rooted at their
# own names ("install/…", "saves/…"), because for many games the world lives in
# saves/ while install/ holds only re-downloadable game files. manifest.sources
# records exactly which subtrees were captured; restore iterates that list and
# never assumes.
#
# A backup is built in $instance_temp_dir and moved into place only once it is
# complete, and _list_backups only reports directories that carry a readable
# manifest.json — so an interrupted build is invisible and can never be offered
# for restore.

# The instance subtrees a backup captures, in archive order.
readonly BACKUP_SOURCE_LABELS=(install saves)

# Emit the labels this instance actually has content for, one per line.
# A subtree that is missing or empty is not captured (and so is absent from
# manifest.sources); a subtree that exists somewhere other than
# $instance_working_dir/<label> cannot be rooted correctly in the archive and is
# a hard error rather than a silent omission.
function __backup_sources() {
  local label path
  for label in "${BACKUP_SOURCE_LABELS[@]}"; do
    case "$label" in
    install) path="$instance_install_dir" ;;
    saves) path="$instance_saves_dir" ;;
    *) continue ;;
    esac

    [[ -z "$path" ]] && continue
    [[ ! -d "$path" ]] && continue

    if [[ "$path" != "${instance_working_dir}/${label}" ]]; then
      __print_error "$label directory ($path) is not ${instance_working_dir}/${label}; cannot back it up"
      return $EC_ERROR
    fi

    # Skip an empty subtree: there is nothing to capture, and recording it in
    # manifest.sources would promise content the archive does not hold.
    [[ -z "$(ls -A "$path" 2>/dev/null)" ]] && continue

    echo "$label"
  done

  return $EC_SUCCESS
}

# Mint a backup id: <instance>-<UTC timestamp>-<6 hex>.
function __backup_new_id() {
  local datetime suffix
  datetime="$(date -u +"%Y%m%dT%H%M%SZ")"
  suffix="$(od -An -tx1 -N3 /dev/urandom 2>/dev/null | tr -d ' \n')"
  # /dev/urandom is always present on Linux; fall back rather than mint a
  # colliding id if it ever is not.
  [[ -z "$suffix" ]] && suffix="$(printf '%06x' $((RANDOM * RANDOM % 16777216)))"

  echo "${instance_name}-${datetime}-${suffix}"
}

# Print the path of a backup's manifest, or nothing when it has none.
function __backup_manifest_path() {
  local dir="$1"
  [[ -f "${dir}/manifest.json" ]] && echo "${dir}/manifest.json"
}

# A backup records the state it was captured in, because that is what a restore
# decision hinges on. The value is measured per backup, never assumed:
#
#   cold     the instance was stopped; nothing could write mid-archive
#   flushed  running, and the game wrote its world out before the archive
#   hot      running with no usable save command; the archive may be torn
#   null     the run state could not be determined, so nothing is claimed
#
# A native instance is spawned by the watchdog, which owns the process and writes
# no pid file, so _is_active cannot see it. The caller passes the state in with
# --run-state; a container is probed here, where docker is the authority.
function _create_backup() {
  local run_state=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-state)
      run_state="${2:-}"
      shift 2
      ;;
    *) shift ;;
    esac
  done

  __print_info "Creating backup..."

  if [[ ! -d "${instance_install_dir}" ]]; then
    __print_error "Install directory ${instance_install_dir} does not exist"
    return $EC_ERROR
  fi

  if [[ -z "$run_state" ]]; then
    if _is_active &>/dev/null; then
      run_state="active"
    else
      run_state="inactive"
    fi
  fi

  # Tell the game to write its world to disk before archiving it. Some blueprints
  # declare the same token for save_command and stop_command ("exit"), which would
  # shut the server down to back it up — that is not a usable save command.
  local flushed=0
  if [[ "$run_state" == "active" ]] &&
    [[ -n "${instance_save_command:-}" ]] &&
    [[ "${instance_save_command}" != "${instance_stop_command:-}" ]]; then
    if _send_save_command; then
      flushed=1
    else
      __print_warning "Save command failed; archiving without a flush"
    fi
  fi

  local consistency
  case "$run_state" in
  inactive) consistency='"cold"' ;;
  active)
    if [[ $flushed -eq 1 ]]; then
      consistency='"flushed"'
    else
      consistency='"hot"'
    fi
    ;;
  *) consistency='null' ;;
  esac

  local -a sources
  mapfile -t sources < <(__backup_sources) || return $EC_ERROR

  # A running instance rewrites saves/ but not install/, and install/ is both the
  # bulk of a game and re-downloadable — capturing saves/ alone is what keeps a
  # frequent cadence affordable. That shortcut only holds while saves/ has
  # content: several games keep their world inside install/, and there capturing
  # saves/ alone would back up nothing of value, so the whole tree is taken.
  if [[ "$run_state" == "active" ]]; then
    local label
    for label in "${sources[@]}"; do
      if [[ "$label" == "saves" ]]; then
        sources=(saves)
        break
      fi
    done
  fi

  if [[ ${#sources[@]} -eq 0 ]]; then
    __print_error "Nothing to back up for ${instance_name} (install and saves are empty)"
    return $EC_ERROR
  fi

  if [[ ! -d "${instance_backups_dir}" ]]; then
    mkdir -p "${instance_backups_dir}" || {
      __print_error "Failed to create backup directory ${instance_backups_dir}"
      return $EC_ERROR
    }
  fi

  local backup_id staging
  backup_id="$(__backup_new_id)"
  staging="${instance_temp_dir}/${backup_id}.partial"

  if ! mkdir -p "$staging"; then
    __print_error "Failed to create staging directory $staging"
    return $EC_ERROR
  fi

  local compressed="false"
  local size_bytes=0
  local sha256="null"

  if [[ "$instance_compress_backups" == "true" ]]; then
    compressed="true"

    if ! tar -czf "${staging}/data.tar.gz" -C "$instance_working_dir" "${sources[@]}"; then
      __print_error "Failed to archive ${sources[*]}"
      rm -rf "${staging:?}"
      return $EC_ERROR
    fi

    size_bytes="$(stat -c %s "${staging}/data.tar.gz" 2>/dev/null || echo 0)"
    sha256="\"$(sha256sum "${staging}/data.tar.gz" | cut -d' ' -f1)\""
  else
    if ! mkdir -p "${staging}/data"; then
      __print_error "Failed to create staging data directory"
      rm -rf "${staging:?}"
      return $EC_ERROR
    fi

    local label
    for label in "${sources[@]}"; do
      if ! cp -a "${instance_working_dir}/${label}" "${staging}/data/${label}"; then
        __print_error "Failed to copy ${label}"
        rm -rf "${staging:?}"
        return $EC_ERROR
      fi
    done

    size_bytes="$(du -sb "${staging}/data" 2>/dev/null | cut -f1)"
    [[ -z "$size_bytes" ]] && size_bytes=0
    # An uncompressed backup is a tree, not a single artifact, so there is no one
    # digest to record. Left null rather than filled with a meaningless value;
    # restore skips verification when it is absent.
  fi

  # Count the captured files from the sources themselves — cheaper than walking
  # the finished archive, and identical in result.
  local file_count=0
  local label count
  for label in "${sources[@]}"; do
    count="$(find "${instance_working_dir}/${label}" -type f 2>/dev/null | wc -l)"
    file_count=$((file_count + count))
  done

  local installed_version blueprint_name
  installed_version="$(_get_installed_version)"
  blueprint_name="$(basename "${instance_blueprint_file:-}" .bp.yaml)"

  if ! jq -n \
    --arg id "$backup_id" \
    --arg instance "$instance_name" \
    --arg blueprint "$blueprint_name" \
    --arg version "${installed_version:-}" \
    --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson compressed "$compressed" \
    --argjson consistency "$consistency" \
    --argjson sha256 "$sha256" \
    --argjson size_bytes "${size_bytes:-0}" \
    --argjson file_count "$file_count" \
    '{
      schema_version: 1,
      id: $id,
      instance: $instance,
      blueprint: (if $blueprint == "" then null else $blueprint end),
      version: (if $version == "" then null else $version end),
      created_at: $created_at,
      compressed: $compressed,
      consistency: $consistency,
      sources: $ARGS.positional,
      size_bytes: $size_bytes,
      file_count: $file_count,
      sha256: $sha256
    }' --args "${sources[@]}" >"${staging}/manifest.json"; then
    __print_error "Failed to write backup manifest"
    rm -rf "${staging:?}"
    return $EC_ERROR
  fi

  # Publish atomically: until this rename the backup does not exist as far as
  # _list_backups and every consumer above it are concerned.
  if ! mv "$staging" "${instance_backups_dir}/${backup_id}"; then
    __print_error "Failed to publish backup to ${instance_backups_dir}/${backup_id}"
    rm -rf "${staging:?}"
    return $EC_ERROR
  fi

  __print_success "Backup created: ${backup_id}"
  # The id on stdout is the command's machine-readable result: callers (the kgsm
  # CLI's event payload, the scheduler) use it instead of re-deriving "the newest
  # entry", which races with a concurrent backup.
  echo "$backup_id"
  return $EC_SUCCESS
}

function _restore_backup() {
  local backup_id="$1"
  shift

  # Carried straight through to the safety backup below, so that archive records
  # what it was taken against instead of falling back to a probe this script
  # cannot answer for a native instance.
  local run_state=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-state)
      run_state="${2:-}"
      shift 2
      ;;
    *) shift ;;
    esac
  done

  local source="${instance_backups_dir}/${backup_id}"

  __print_info "Restoring ${backup_id}..."

  local manifest
  manifest="$(__backup_manifest_path "$source")"
  if [[ -z "$manifest" ]]; then
    __print_error "Not a backup: ${source} (no manifest.json)"
    return $EC_ERROR
  fi

  local backup_version compressed
  backup_version="$(jq -r '.version // ""' "$manifest" 2>/dev/null)"
  compressed="$(jq -r '.compressed' "$manifest" 2>/dev/null)"

  local -a sources
  mapfile -t sources < <(jq -r '.sources[]' "$manifest" 2>/dev/null)
  if [[ ${#sources[@]} -eq 0 ]]; then
    __print_error "Backup ${backup_id} records no sources; refusing to restore"
    return $EC_ERROR
  fi

  # Verify the archive BEFORE touching the instance: a corrupt backup must fail
  # while the current state is still intact.
  local expected_sha
  expected_sha="$(jq -r '.sha256 // ""' "$manifest" 2>/dev/null)"
  if [[ "$compressed" == "true" ]]; then
    if [[ ! -f "${source}/data.tar.gz" ]]; then
      __print_error "Backup ${backup_id} is marked compressed but has no data.tar.gz"
      return $EC_ERROR
    fi
    if [[ -n "$expected_sha" ]]; then
      __print_info "Verifying backup integrity..."
      local actual_sha
      actual_sha="$(sha256sum "${source}/data.tar.gz" | cut -d' ' -f1)"
      if [[ "$actual_sha" != "$expected_sha" ]]; then
        __print_error "Checksum mismatch for ${backup_id}; refusing to restore"
        return $EC_ERROR
      fi
    fi
  elif [[ ! -d "${source}/data" ]]; then
    __print_error "Backup ${backup_id} is marked uncompressed but has no data directory"
    return $EC_ERROR
  fi

  # Take a safety backup of the current state before overwriting it, and abort
  # if that fails — a restore must never be the reason data is lost.
  local label has_content="false"
  for label in "${sources[@]}"; do
    if [[ -d "${instance_working_dir}/${label}" ]] &&
      [[ -n "$(ls -A "${instance_working_dir}/${label}" 2>/dev/null)" ]]; then
      has_content="true"
      break
    fi
  done

  if [[ "$has_content" == "true" ]]; then
    __print_warning "Current instance data is not empty, creating a backup first..."

    local -a safety_args=()
    [[ -n "$run_state" ]] && safety_args+=(--run-state "$run_state")

    local safety_id
    safety_id="$(_create_backup "${safety_args[@]}" | tail -n1)"
    if [[ -z "$safety_id" ]] || [[ ! -d "${instance_backups_dir}/${safety_id}" ]]; then
      __print_error "Failed to create backup before restore. Aborting to prevent data loss."
      return $EC_ERROR
    fi
    __print_info "Backup created successfully: $safety_id"

    for label in "${sources[@]}"; do
      if ! rm -rf "${instance_working_dir:?}/${label:?}"/*; then
        __print_error "Failed to clear ${instance_working_dir}/${label}, exiting"
        return $EC_ERROR
      fi
    done
  fi

  for label in "${sources[@]}"; do
    mkdir -p "${instance_working_dir}/${label}" || {
      __print_error "Failed to create ${instance_working_dir}/${label}"
      return $EC_ERROR
    }
  done

  if [[ "$compressed" == "true" ]]; then
    if ! tar -xzf "${source}/data.tar.gz" -C "$instance_working_dir" "${sources[@]}"; then
      __print_error "Failed to extract ${backup_id}"
      return $EC_ERROR
    fi
  else
    for label in "${sources[@]}"; do
      if ! cp -a "${source}/data/${label}/." "${instance_working_dir}/${label}/"; then
        __print_error "Failed to restore ${label} from ${backup_id}"
        return $EC_ERROR
      fi
    done
  fi

  # The version comes from the manifest — the id is opaque and carries none.
  _save_version "${backup_version:-unknown}" || {
    __print_error "Failed to save restored version ${backup_version:-unknown} to file."
    return $EC_ERROR
  }

  __print_success "Restore complete"
  return $EC_SUCCESS
}

function _list_backups() {
  _backup_manifest_json | jq -r '.[].id'
}

# Every backup's manifest as a JSON array, newest first. This is the complete
# machine-readable listing; _list_backups is the id-only projection of it.
# Directories without a readable manifest are not backups and are skipped — that
# is what makes a half-built or foreign directory invisible rather than
# restorable.
function _backup_manifest_json() {
  if [[ -z "$instance_backups_dir" ]] || [[ ! -d "$instance_backups_dir" ]]; then
    echo "[]"
    return $EC_SUCCESS
  fi

  local -a manifests
  mapfile -t manifests < <(find "$instance_backups_dir" -mindepth 2 -maxdepth 2 \
    -name manifest.json -type f 2>/dev/null | sort)

  if [[ ${#manifests[@]} -eq 0 ]]; then
    echo "[]"
    return $EC_SUCCESS
  fi

  # Order by the recorded creation time, not by mtime: mtime changes whenever
  # anything touches the directory, which would silently reorder the history.
  jq -s 'map(select(type == "object")) | sort_by(.created_at) | reverse' \
    "${manifests[@]}" 2>/dev/null || echo "[]"
}
