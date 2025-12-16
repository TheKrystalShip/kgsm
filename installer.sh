#!/usr/bin/env bash

# shellcheck disable=SC2199
if [[ $@ =~ "--debug" ]]; then
  export PS4='+(\033[0;33m${BASH_SOURCE}:${LINENO}\033[0m): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  set -x
  for a; do
    shift
    case $a in
    --debug) continue ;;
    *) set -- "$@" "$a" ;;
    esac
  done
fi

# Global variables for script behavior
SILENT_MODE=0

package="kgsm"
owner="TheKrystalShip"
head="${config_update_channel:-main}"
repo_archive_tag_url="https://github.com/${owner}/${package^^}/archive/refs/tags"
all_releases_api_url="https://api.github.com/repos/${owner}/${package^^}/releases"
stable_release_api_url="https://api.github.com/repos/${owner}/${package^^}/releases/latest"
compare_api_url="https://api.github.com/repos/${owner}/${package^^}/compare"
local_version_file=".${package}.version"
deprecated_version_file="version.txt"
deprecated_install_file="install.sh"

SELF_PATH="$(dirname "$(readlink -f "$0")")"

# Check if stdout is a tty
if test -t 1; then
  ncolors=0
  if command -v tput >/dev/null 2>&1; then
    ncolors="$(tput colors)"
  fi
  if [[ $ncolors ]] && [[ "$ncolors" -gt 8 ]]; then
    export COLOR_RED="\033[0;31m"
    export COLOR_GREEN="\033[0;32m"
    export COLOR_ORANGE="\033[0;33m"
    export COLOR_BLUE="\033[0;34m"
    export COLOR_END="\033[0m"
  fi
fi

function usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "${UNDERLINE}KGSM Installer${END}

Manages the installation, updates, and version control for Krystal Game Server Manager.

${UNDERLINE}Usage:${END}
  $(basename "$0") [OPTIONS]

${UNDERLINE}General Options:${END}
  -h, --help                 Display this help information
  -v, --version              Display the currently installed version of KGSM
  -s, --silent               Run in silent mode with minimal output
                             Useful for automated or scripted operations

${UNDERLINE}Version Management:${END}
  --version-list             Display all available released versions of KGSM
  --check-update             Check if a newer version of KGSM is available
  --update                   Update KGSM to the latest stable version

${UNDERLINE}Installation Options:${END}
  --install                  Download and install the latest version of KGSM
  --install [version]        Download and install a specific version of KGSM
  --verify                   Verify the current installation is valid and complete
  --repair                   Attempt to repair a damaged or incomplete installation
  --clean                    Remove temporary files from failed installations
  --diagnostics              Display diagnostic information about the environment
  --force                    Skip version verification and force operations
                             Can be used with --install or --update

${UNDERLINE}Examples:${END}
  $(basename "$0") --install
  $(basename "$0") --install v2.0.0
  $(basename "$0") --update --force
  $(basename "$0") --install 1.6.0
  $(basename "$0") --check-update
  $(basename "$0") --update
  $(basename "$0") --silent --update
  $(basename "$0") --diagnostics
  $(basename "$0") --repair
"
}

# Ensure required commands are available
function check_command() {
  local cmd=$1
  local pkg=$2
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} '$cmd' is required but not installed." >&2
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Please install '$pkg' before proceeding." >&2
    return 1
  fi
  return 0
}

function check_download_command() {
  # Try curl first, then wget as fallback
  if check_command wget wget; then
    DOWNLOAD_CMD="wget"
    return 0
  elif check_command curl curl; then
    DOWNLOAD_CMD="curl"
    return 0
  else
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Either 'curl' or 'wget' is required but neither is installed." >&2
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Please install one of them before proceeding." >&2
    exit 1
  fi
}

# Set up needed commands
check_download_command || exit 1
check_command jq jq || exit 1
check_command tar tar || exit 1

# Handle deprecated version file
if [[ -f "${SELF_PATH}/${deprecated_version_file}" ]]; then
  if [[ -f "${SELF_PATH}/${local_version_file}" ]]; then
    rm -rf "${SELF_PATH:?}/${deprecated_version_file:?}"
  else
    mv "${SELF_PATH}/${deprecated_version_file}" "${SELF_PATH}/${local_version_file}"
  fi
fi

# Handle deprecated install file
if [[ -f "${SELF_PATH}/${deprecated_install_file}" ]]; then
  rm "$deprecated_install_file"
fi

# Read version from the local file
function get_current_version() {
  if [[ ! -f "${SELF_PATH}/${local_version_file}" ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Version file is missing. Reinstallation is recommended." >&2
    exit 1
  fi

  local version
  version=$(<"${SELF_PATH}/${local_version_file}")

  # Validate version format
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Invalid version format in ${local_version_file}: $version" >&2
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Expected format: X.Y.Z (e.g., 1.7.3)" >&2
    exit 1
  fi

  echo "$version"
  return 0
}

# Fetch versions from GitHub
function fetch_version_data() {
  local url=$1
  local data

  if [[ "$DOWNLOAD_CMD" == "wget" ]]; then
    data=$(wget -qO - "$url") || {
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to fetch data from $url." >&2
      return 1
    }
  else
    data=$(curl -sSfL "$url") || {
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to fetch data from $url." >&2
      return 1
    }
  fi

  echo "$data"
}

function get_latest_stable_version() {
  local version_data
  version_data=$(fetch_version_data "$stable_release_api_url")
  local status=$?

  if [[ $status -ne 0 || -z "$version_data" ]]; then
    return 1
  fi

  jq -r '.tag_name' <<<"$version_data"
  return $?
}

function get_all_versions() {
  local version_data
  version_data=$(fetch_version_data "$all_releases_api_url")
  local status=$?

  if [[ $status -ne 0 || -z "$version_data" ]]; then
    return 1
  fi

  jq -r '.[] | .tag_name' <<<"$version_data" | sort -Vr
  return $?
}

# Compare two semantic versions
function compare_versions() {
  local version1=$1
  local version2=$2

  # Validate version strings
  if ! [[ "$version1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Invalid version format: $version1" >&2
    return 3
  fi

  if ! [[ "$version2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Invalid version format: $version2" >&2
    return 3
  fi

  # Split versions into components
  local -a v1_parts v2_parts
  IFS='.' read -ra v1_parts <<<"$version1"
  IFS='.' read -ra v2_parts <<<"$version2"

  # Compare major version
  if ((v1_parts[0] > v2_parts[0])); then
    return 1 # version1 is greater
  elif ((v1_parts[0] < v2_parts[0])); then
    return 2 # version1 is smaller
  fi

  # Compare minor version
  if ((v1_parts[1] > v2_parts[1])); then
    return 1 # version1 is greater
  elif ((v1_parts[1] < v2_parts[1])); then
    return 2 # version1 is smaller
  fi

  # Compare patch version
  if ((v1_parts[2] > v2_parts[2])); then
    return 1 # version1 is greater
  elif ((v1_parts[2] < v2_parts[2])); then
    return 2 # version1 is smaller
  fi

  # Versions are equal
  return 0
}

# Fetch changelog for a specific version
function fetch_changelog() {
  local version1=$1
  local version2=$2
  local compare_data

  compare_data=$(fetch_version_data "$compare_api_url/${version1}...${version2}")
  local status=$?

  if [[ $status -ne 0 || -z "$compare_data" ]]; then
    return 1
  fi

  jq -r '.commits[] | select(.commit.message | test("^Bumped version to [0-9]+\\.[0-9]+\\.[0-9]+") | not) | "\(.sha[0:7]): \(.commit.message)"' <<<"$compare_data"
  return $?
}

# Download and extract a specific version
function download_kgsm() {
  local version=$1
  local tarball="$package-$head-$version.tar.gz"
  local download_url="$repo_archive_tag_url/$version.tar.gz"
  local tempdir

  # Create a temp directory for cleanup in case of failure
  tempdir=$(mktemp -d)

  # Validate version format
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Invalid version format: $version" >&2
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Expected format: X.Y.Z (e.g., 1.7.3)" >&2
    return 1
  fi

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Downloading version $version..."

  # Download using the detected command
  if [[ "$DOWNLOAD_CMD" == "wget" ]]; then
    if [[ $SILENT_MODE -eq 0 ]]; then
      wget --show-progress --progress=bar:force:noscroll -O "$tempdir/$tarball" "$download_url" || {
        echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to download $tarball." >&2
        rm -rf "$tempdir"
        return 1
      }
    else
      wget -q -O "$tempdir/$tarball" "$download_url" || {
        echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to download $tarball." >&2
        rm -rf "$tempdir"
        return 1
      }
    fi
  else
    if [[ $SILENT_MODE -eq 0 ]]; then
      curl -SL --progress-bar "$download_url" -o "$tempdir/$tarball" || {
        echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to download $tarball." >&2
        rm -rf "$tempdir"
        return 1
      }
    else
      curl -sSL "$download_url" -o "$tempdir/$tarball" || {
        echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to download $tarball." >&2
        rm -rf "$tempdir"
        return 1
      }
    fi
  fi

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Extracting files..."

  # Extract to temp directory first
  if ! tar -xzf "$tempdir/$tarball" -C "$tempdir"; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Extraction failed for $tarball." >&2
    rm -rf "$tempdir"
    return 1
  fi

  # Verify extraction was successful by checking for key files
  if [[ ! -f "$tempdir/${package^^}-$version/kgsm.sh" ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Verification failed: Invalid archive or corrupted download." >&2
    rm -rf "$tempdir"
    return 1
  fi

  # Move extracted files to destination
  mv "$tempdir/${package^^}-$version" "$SELF_PATH/${package^^}-$version" || {
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to move extracted files to destination." >&2
    rm -rf "$tempdir"
    return 1
  }

  # Clean up
  rm -rf "$tempdir"

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_GREEN}SUCCESS${COLOR_END} Version $version downloaded and extracted."
  return 0
}

function install_kgsm() {
  local version=${1:-}
  local installed_version=""
  local skip_download=0

  # If we have a local version file, get the current version
  if [[ -f "${SELF_PATH}/${local_version_file}" ]]; then
    installed_version="$(<"${SELF_PATH}/${local_version_file}")"
  fi

  # Get latest version if no specific version requested
  if [[ -z "$version" ]]; then
    version=$(get_latest_stable_version) || {
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to get latest version information." >&2
      return 1
    }
  fi

  # Check if requested version is already installed
  if [[ "$version" == "$installed_version" ]]; then
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Version $version is already installed."
    skip_download=1
  else
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Installing KGSM version $version..."
  fi

  # Download and extract if needed
  if [[ $skip_download -eq 0 ]]; then
    download_kgsm "$version" || {
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Installation failed." >&2
      return 1
    }

    # Update version file within the downloaded package
    local local_version_file_abs_path="${SELF_PATH}/${package^^}-${version}/${local_version_file}"
    if ! printf "%s\n" "$version" >"${local_version_file_abs_path}.tmp"; then
      echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to create temporary version file." >&2
      return 1
    else
      if ! mv "${local_version_file_abs_path}.tmp" "${local_version_file_abs_path}"; then
        echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to update version file." >&2
        rm -f "${local_version_file_abs_path}.tmp"
        return 1
      fi
    fi
  fi

  [[ $SILENT_MODE -eq 0 && $skip_download -eq 0 ]] && echo -e "${0##*/} ${COLOR_GREEN}SUCCESS${COLOR_END} KGSM version $version installed."
  return 0
}

function check_for_update() {
  local latest_version
  latest_version=$(get_latest_stable_version)
  if [[ $? -ne 0 || -z "$latest_version" ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to get latest version information." >&2
    return 1
  fi

  local current_version
  current_version=$(get_current_version)
  if [[ $? -ne 0 || -z "$current_version" ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to get current version information." >&2
    return 1
  fi

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Current version: $current_version"
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Latest version: $latest_version"

  local compare_result
  compare_versions "$current_version" "$latest_version"
  compare_result=$?

  case $compare_result in
  0)
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Current version is up-to-date."
    ;;
  1)
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Current version ($current_version) is newer than latest stable ($latest_version)."
    ;;
  2)
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} A newer version is available: $latest_version."
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Run '$(basename "$0") --update' to update."
    ;;
  3)
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Invalid version format detected." >&2
    return 1
    ;;
  esac

  return 0
}

function update_kgsm() {
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Updating KGSM..."

  local latest_version
  latest_version=$(get_latest_stable_version) || {
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to get latest version information." >&2
    return 1
  }

  local current_version
  current_version=$(get_current_version) || {
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to get current version information." >&2
    return 1
  }

  # Skip update if already on latest version (unless force mode is enabled)
  if [[ "$current_version" == "$latest_version" && $FORCE_MODE -eq 0 ]]; then
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Already on latest version $latest_version."
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Use --force to reinstall this version if needed."
    return 0
  fi

  # Compare versions using semver logic (unless force mode is enabled)
  if [[ $FORCE_MODE -eq 0 ]]; then
    compare_versions "$current_version" "$latest_version"
    local compare_result=$?
    if [[ $compare_result -eq 0 ]]; then
      [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Already on latest version $latest_version."
      [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Use --force to reinstall this version if needed."
      return 0
    elif [[ $compare_result -eq 1 ]]; then
      [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Current version ($current_version) is newer than latest stable ($latest_version)."
      [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Skipping downgrade. Use --force --update to override."
      return 0
    fi
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Proceeding with update to $latest_version (current: $current_version)"
  else
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Force mode enabled. Proceeding with update regardless of version check."
  fi

  # Create backup before updating
  local backup_dir="${SELF_PATH}/backup_${current_version}_$(date +%Y%m%d%H%M%S)"
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Creating backup in $backup_dir..."

  local mkdir_result
  mkdir -p "$backup_dir"
  mkdir_result=$?
  if [[ $mkdir_result -ne 0 ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to create backup directory." >&2
    return 1
  fi

  # Back up important files and folders
  for item in kgsm.sh modules templates config.ini instances; do
    if [[ -e "${SELF_PATH}/$item" ]]; then
      if ! cp -r "${SELF_PATH}/$item" "$backup_dir/"; then
        echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to back up ${item}." >&2
      fi
    fi
  done

  # Install the new version
  local install_result
  install_kgsm "$latest_version"
  install_result=$?
  if [[ $install_result -ne 0 ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to download and install new version." >&2
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Backup is available at $backup_dir if needed." >&2
    return 1
  fi

  # Copy the files to the main directory
  local copy_result
  cp -rT "${SELF_PATH}/${package^^}-${latest_version}"/. "$SELF_PATH"
  copy_result=$?
  if [[ $copy_result -ne 0 ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to copy new files to main directory." >&2
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Backup is available at $backup_dir if needed." >&2
    return 1
  fi

  # Update the version file in the main directory as well
  if ! printf "%s\n" "$latest_version" >"${SELF_PATH}/${local_version_file}.tmp"; then
    echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to create temporary version file." >&2
  else
    if ! mv "${SELF_PATH}/${local_version_file}.tmp" "${SELF_PATH}/${local_version_file}"; then
      echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to update version file." >&2
      rm -f "${SELF_PATH}/${local_version_file}.tmp"
    fi
  fi

  # Clean up the extracted directory
  local cleanup_result
  rm -rf "${SELF_PATH}/${package^^}-${latest_version}"
  cleanup_result=$?
  if [[ $cleanup_result -ne 0 ]]; then
    echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to clean up temporary files." >&2
  fi

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_GREEN}SUCCESS${COLOR_END} KGSM updated to version $latest_version."

  # Merge config with updated defaults after successful update
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Merging configuration with updated defaults..."

  # Source required modules for config merge
  if [[ -f "${SELF_PATH}/core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SELF_PATH}/core/bootstrap.sh"

    # shellcheck disable=SC1091
    source "${SELF_PATH}/core/config.sh"

    # Perform merge
    if __merge_user_config_with_default 2>/dev/null; then
      [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_GREEN}SUCCESS${COLOR_END} Configuration merged successfully."
      [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Config backup saved as ${CONFIG_FILE}.0"
    else
      echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Config merge failed. Run './kgsm.sh config merge' manually." >&2
    fi
  else
    echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Could not source config modules. Run './kgsm.sh config merge' manually." >&2
  fi

  # Display changelog after update if not in silent mode
  if [[ $SILENT_MODE -eq 0 ]]; then
    local changelog
    changelog=$(fetch_changelog "$current_version" "$latest_version") || {
      echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to fetch changelog." >&2
    }

    if [[ -n "$changelog" ]]; then
      echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Changelog between version ${current_version} and ${latest_version}:"
      echo -e "$changelog"
    else
      echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} No changelog available for version $latest_version."
    fi
  fi

  return 0
}

# Add new functions for verifying and cleaning

function verify_installation() {
  local essential_files=(
    "kgsm.sh"
    "modules/include/common.sh"
    "modules/include/loader.sh"
    "modules/include/errors.sh"
    "modules/include/logging.sh"
    "installer.sh"
    "config.default.ini"
  )

  local optional_files=(
    "config.ini"
    "templates/blueprint.tp"
    "templates/instance.tp"
    "templates/manage.docker.tp"
    "templates/manage.native.tp"
    "templates/service.tp"
  )

  local files_missing=0
  local permissions_issues=0

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Verifying KGSM installation..."

  # Check if version file exists
  if [[ ! -f "${SELF_PATH}/${local_version_file}" ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Version file is missing." >&2
    files_missing=$((files_missing + 1))
  else
    # Read current version
    local current_version
    current_version=$(<"${SELF_PATH}/${local_version_file}")

    # Check version format
    if ! [[ "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Invalid version format in ${local_version_file}: $current_version" >&2
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Expected format: X.Y.Z (e.g., 1.7.3)" >&2
      files_missing=$((files_missing + 1))
    else
      [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Current version: $current_version"
    fi
  fi

  # Check essential files
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Checking essential files..."
  for file in "${essential_files[@]}"; do
    if [[ ! -f "${SELF_PATH}/${file}" ]]; then
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Essential file missing: ${file}" >&2
      files_missing=$((files_missing + 1))
    fi
  done

  # Check optional files
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Checking optional files..."
  for file in "${optional_files[@]}"; do
    if [[ ! -f "${SELF_PATH}/${file}" ]]; then
      echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Optional file missing: ${file}" >&2
    fi
  done

  # Check directory structure
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Checking directory structure..."
  for dir in modules templates blueprints; do
    if [[ ! -d "${SELF_PATH}/${dir}" ]]; then
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Required directory missing: ${dir}" >&2
      files_missing=$((files_missing + 1))
    fi
  done

  # Check execution permissions for critical scripts
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Checking file permissions..."

  local executable_scripts=(
    "kgsm.sh"
    "installer.sh"
    "modules/blueprints.sh"
    "modules/directories.sh"
    "modules/files.management.sh"
    "modules/files.sh"
    "modules/files.symlink.sh"
    "modules/files.ufw.sh"
    "modules/instances.sh"
    "modules/lifecycle.sh"
    "modules/lifecycle.standalone.sh"
    "modules/lifecycle.systemd.sh"
  )

  for script in "${executable_scripts[@]}"; do
    if [[ -f "${SELF_PATH}/${script}" ]]; then
      if [[ ! -x "${SELF_PATH}/${script}" ]]; then
        echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} ${script} is not executable." >&2
        [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Fixing permissions for ${script}..."
        if chmod +x "${SELF_PATH}/${script}"; then
          [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Fixed permissions for ${script}"
        else
          echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to fix permissions for ${script}" >&2
          permissions_issues=$((permissions_issues + 1))
        fi
      fi
    fi
  done

  # Final report
  if [[ $files_missing -gt 0 ]]; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Installation is incomplete: $files_missing essential files missing" >&2
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Please reinstall KGSM using: ${0##*/} --install" >&2
    return 1
  elif [[ $permissions_issues -gt 0 ]]; then
    echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Found $permissions_issues permission issues that couldn't be fixed" >&2
    echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} You may need to run 'chmod +x' manually on these files" >&2
    return 2
  else
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_GREEN}SUCCESS${COLOR_END} KGSM installation verified successfully."
    return 0
  fi
}

function clean_temp_files() {
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Cleaning up temporary files..."

  # Find and remove any extraction directories
  local extraction_dirs
  extraction_dirs=$(find "${SELF_PATH}" -maxdepth 1 -type d -name "${package^^}-*" 2>/dev/null)

  if [[ -n "$extraction_dirs" ]]; then
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Found temporary directories to clean up."
    # shellcheck disable=SC2086
    rm -rf $extraction_dirs
  fi

  # Find and remove any tarball files
  local tarballs
  tarballs=$(find "${SELF_PATH}" -maxdepth 1 -type f -name "${package}-*.tar.gz" 2>/dev/null)

  if [[ -n "$tarballs" ]]; then
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Found temporary tarballs to clean up."
    # shellcheck disable=SC2086
    rm -f $tarballs
  fi

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_GREEN}SUCCESS${COLOR_END} Cleanup completed."
  return 0
}

# Print diagnostic information about the environment
function show_diagnostics() {
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} KGSM Installer Diagnostics"
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} =========================="

  # System information
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} System Information:"
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - OS: $(uname -s)"
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - Kernel: $(uname -r)"
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - Architecture: $(uname -m)"

  # Bash version
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - Bash version: ${BASH_VERSION}"

  # Installation path
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - Installation directory: ${SELF_PATH}"

  # Check for required commands
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Required Commands:"

  local commands=("wget" "jq" "tar" "chmod" "mkdir" "cp" "mv" "find" "unzip" "grep" "sed")
  for cmd in "${commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      local cmd_path
      cmd_path=$(command -v "$cmd")
      echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - $cmd: Available ($cmd_path)"
    else
      echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - $cmd: ${COLOR_RED}Not available${COLOR_END}"
    fi
  done

  # Network accessibility check
  echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Network Connectivity:"
  if ping -c 1 -W 5 github.com >/dev/null 2>&1; then
    echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - GitHub connectivity: ${COLOR_GREEN}OK${COLOR_END}"
  else
    echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - GitHub connectivity: ${COLOR_RED}Failed${COLOR_END}"
  fi

  # Version information
  if [[ -f "${SELF_PATH}/${local_version_file}" ]]; then
    local current_version
    current_version=$(<"${SELF_PATH}/${local_version_file}")
    echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - Current version: $current_version"

    # Try to get latest version (non-fatal if it fails)
    local latest_version
    latest_version=$(get_latest_stable_version 2>/dev/null) || latest_version="Unknown (network error)"
    echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - Latest version: $latest_version"
  else
    echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} - Version file: ${COLOR_RED}Not found${COLOR_END}"
  fi

  return 0
}

# Process command line arguments
# Variables for options
FORCE_MODE=0

# Check for global options first (silent, force)
for arg in "$@"; do
  if [[ "$arg" == "-s" || "$arg" == "--silent" ]]; then
    SILENT_MODE=1
  elif [[ "$arg" == "--force" ]]; then
    FORCE_MODE=1
  fi
done

if [[ $# -eq 0 ]]; then
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} No arguments provided. Defaulting to '--install'."
  install_kgsm
  exit $?
fi

# Generate a self-repair script
function repair_installation() {
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Running KGSM repair procedure..."

  # Constants for remote resources
  local installer_url="https://raw.githubusercontent.com/${owner}/${package^^}/main/installer.sh"
  local config_url="https://raw.githubusercontent.com/${owner}/${package^^}/main/config.default.ini"

  # Check for curl availability first
  local download_cmd="wget"
  if command -v curl >/dev/null 2>&1; then
    download_cmd="curl"
  elif ! command -v wget >/dev/null 2>&1; then
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Neither curl nor wget is available. Cannot proceed with repair." >&2
    return 1
  fi

  # Create backup directory
  local backup_dir="${SELF_PATH}/backup_repair_$(date +%Y%m%d%H%M%S)"
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Creating backup in $backup_dir..."

  mkdir -p "$backup_dir" || {
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to create backup directory." >&2
    return 1
  }

  # Backup important files
  for item in kgsm.sh installer.sh modules templates config.ini instances; do
    if [[ -e "${SELF_PATH}/$item" ]]; then
      [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Backing up $item..."
      cp -r "${SELF_PATH}/$item" "$backup_dir/" || {
        echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to back up $item." >&2
      }
    fi
  done

  # Download fresh installer script
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Downloading latest installer script..."
  local temp_installer="${SELF_PATH}/installer.sh.new"

  if [[ $download_cmd == "wget" ]]; then
    wget -q -O "$temp_installer" "$installer_url" || {
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to download installer script." >&2
      echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Your backup is available at $backup_dir" >&2
      return 1
    }
  else
    curl -sSfL "$installer_url" -o "$temp_installer" || {
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to download installer script." >&2
      echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Your backup is available at $backup_dir" >&2
      return 1
    }
  fi

  # Make it executable and replace the current one
  chmod +x "$temp_installer" || {
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to set permissions on new installer." >&2
    return 1
  }

  mv "$temp_installer" "$SELF_PATH/installer.sh" || {
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Failed to replace installer script." >&2
    return 1
  }

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_GREEN}SUCCESS${COLOR_END} Installer script updated."

  # Download default config if missing
  if [[ ! -f "$SELF_PATH/config.default.ini" ]]; then
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Default config missing. Downloading..."

    if [[ $download_cmd == "curl" ]]; then
      curl -sSfL "$config_url" -o "$SELF_PATH/config.default.ini" || {
        echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to download default config." >&2
      }
    else
      wget -q -O "$SELF_PATH/config.default.ini" "$config_url" || {
        echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to download default config." >&2
      }
    fi
  fi

  # Run verification
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Verifying installation..."

  if ! verify_installation; then
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Verification failed. Performing full reinstallation..."

    # Force reinstallation with the new installer
    if ! update_kgsm; then
      echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Reinstallation failed." >&2
      echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Your backup is available at $backup_dir" >&2
      return 1
    fi

    # If the update succeeded, restore user-specific files that may have been overwritten
    [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} Restoring user configuration..."

    # Restore user config if it exists in backup
    if [[ -f "$backup_dir/config.ini" ]]; then
      cp "$backup_dir/config.ini" "$SELF_PATH/config.ini" || {
        echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to restore user config." >&2
      }
    fi

    # Restore instances directory if it exists in backup
    if [[ -d "$backup_dir/instances" ]] && [[ -d "$SELF_PATH/instances" ]]; then
      cp -r "$backup_dir/instances/." "$SELF_PATH/instances/" || {
        echo -e "${0##*/} ${COLOR_ORANGE}WARNING${COLOR_END} Failed to restore instances." >&2
      }
    fi
  fi

  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_GREEN}SUCCESS${COLOR_END} Repair completed successfully."
  [[ $SILENT_MODE -eq 0 ]] && echo -e "${0##*/} ${COLOR_BLUE}INFO${COLOR_END} A backup of your previous installation is available at $backup_dir"

  return 0
}

# Process main command
while [[ $# -gt 0 ]]; do
  case "$1" in
  -v | --version)
    get_current_version
    exit $?
    ;;
  -s | --silent | --force)
    # Already processed above
    ;;
  --version-list)
    get_all_versions
    exit $?
    ;;
  --install)
    shift
    install_kgsm "$1"
    exit $?
    ;;
  --check-update)
    check_for_update
    exit $?
    ;;
  --update)
    update_kgsm
    exit $?
    ;;
  --verify)
    verify_installation
    exit $?
    ;;
  --clean)
    clean_temp_files
    exit $?
    ;;
  --diagnostics)
    show_diagnostics
    exit $?
    ;;
  --repair)
    repair_installation
    exit $?
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo -e "${0##*/} ${COLOR_RED}ERROR${COLOR_END} Invalid argument $1" >&2
    exit 1
    ;;
  esac
  shift
done
