# =============================================================================
# VERSION MANAGEMENT
# =============================================================================
#
# A container instance's "version" is the digest of the image (or images) its
# compose file resolves to. A tag is not a version: `latest` names a different
# image every time upstream pushes, which is exactly the question being asked.
#
# The installed version is what was recorded at the last pull; the latest
# version is what the registry serves for the same reference right now. Neither
# is ever guessed — a registry that cannot be reached returns an error, so the
# status surface reports "not checked" rather than a comparison that never
# happened.

# How long a registry query may take before it is treated as unreachable. A
# scheduled sweep walks every instance, so one unresponsive registry must not
# hold the whole host.
readonly _REGISTRY_TIMEOUT_SECONDS=30

# The image references this instance's compose file defines, one per line.
# Echoes nothing and fails when compose cannot resolve the file.
function _compose_images() {
  local images
  images=$(
    cd "$instance_working_dir" 2>/dev/null &&
      docker compose -f "$instance_compose_file" config --images 2>/dev/null
  ) || return $EC_ERROR

  [[ -n "$images" ]] || return $EC_ERROR
  echo "$images"
}

# Reduce a set of per-image digests to the one string that is this instance's
# version. A single-image instance — which is almost all of them — gets the bare
# digest, because that is the value a human pastes and compares. A multi-image
# instance gets the short forms joined, so the version still changes when any
# one of its images does and still reads as more than one thing.
function _fingerprint_digests() {
  local -a digests=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && digests+=("$line")
  done

  case ${#digests[@]} in
  0) return $EC_ERROR ;;
  1)
    echo "${digests[0]}"
    ;;
  *)
    local -a short=()
    local digest
    # Sorted, so the fingerprint depends on the set and not on the order
    # compose happened to list it in.
    while IFS= read -r digest; do
      short+=("${digest#sha256:}")
    done < <(printf '%s\n' "${digests[@]}" | sort)

    local joined="" part
    for part in "${short[@]}"; do
      joined+="${joined:+ +}${part:0:12}"
    done
    echo "${joined// /}"
    ;;
  esac
}

function _get_installed_version() {
  # What was recorded at the last pull. "Unknown" — not a tag, and not a
  # fabricated digest — when nothing has been recorded, which is what makes the
  # status surface report this instance as unchecked instead of comparing
  # against a placeholder.
  if [[ -s "$instance_version_file" ]]; then
    cat "$instance_version_file"
  else
    echo "Unknown"
  fi
}

function _get_latest_version() {
  # The digest the registry serves for each of this instance's images, right
  # now. Every image must answer: a partial reading is not a version, and
  # treating one as such would report "up to date" on the strength of the
  # images that did answer.
  local images
  if ! images=$(_compose_images); then
    __print_error "Could not resolve the images in $instance_compose_file"
    return $EC_ERROR
  fi

  local -a digests=()
  local image digest
  while IFS= read -r image; do
    [[ -n "$image" ]] || continue

    digest=$(
      timeout "$_REGISTRY_TIMEOUT_SECONDS" \
        docker buildx imagetools inspect "$image" \
        --format '{{.Manifest.Digest}}' 2>/dev/null
    )

    if [[ -z "$digest" || "$digest" != sha256:* ]]; then
      __print_error "The registry did not answer for image '${image}'"
      return $EC_ERROR
    fi

    digests+=("$digest")
  done <<< "$images"

  printf '%s\n' "${digests[@]}" | _fingerprint_digests
}

# The digest each of this instance's images resolves to LOCALLY — what is
# actually on this host, as opposed to what was recorded. Used to record the
# version after a pull, so the recorded value describes the images that were
# really fetched.
function _get_local_version() {
  local images
  if ! images=$(_compose_images); then
    return $EC_ERROR
  fi

  local -a digests=()
  local image repo_digest digest
  while IFS= read -r image; do
    [[ -n "$image" ]] || continue

    repo_digest=$(
      docker image inspect "$image" \
        --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' 2>/dev/null
    )

    digest="${repo_digest#*@}"
    if [[ -z "$digest" || "$digest" != sha256:* ]]; then
      # An image built locally, or one never pulled by digest, has no repo
      # digest to record. Saying so beats recording a tag.
      return $EC_ERROR
    fi

    digests+=("$digest")
  done <<< "$images"

  printf '%s\n' "${digests[@]}" | _fingerprint_digests
}

# The override-API contract, unchanged across every game and both runtimes:
# echo the latest version and return EC_SUCCESS when one is newer, return
# EC_ERROR otherwise. EC_ERROR therefore means "already current OR could not
# ask" — the two are not distinguishable here, which is why nothing that has to
# tell them apart may use this function. `check-update` and the status surface
# call `_get_latest_version` directly for that reason.
function _compare_versions() {
  local installed_version
  installed_version=$(_get_installed_version)

  local latest_version
  latest_version=$(_get_latest_version) || return $EC_ERROR

  if [[ -z "$latest_version" ]]; then
    __print_error "No version information was returned from the registry"
    return $EC_ERROR
  fi

  if [[ "$latest_version" == "$installed_version" ]]; then
    __print_info "Local version is the same as the registry version"
    return $EC_ERROR
  fi

  echo "$latest_version"
  return $EC_SUCCESS
}

function _save_version() {
  local version=$1

  __print_info "Saving version ${version}..."

  echo "$version" >"$instance_version_file"

  __print_success "Version saved"
  return $EC_SUCCESS
}
