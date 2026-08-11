function _deploy() {
  local source=$instance_temp_dir
  local dest=$instance_install_dir

  __print_info "Deploying..."

  # Check if $source is empty
  if [[ -z "$(ls -A "$source")" ]]; then
    __print_error "$source is empty, nothing to deploy. Exiting"
    return $EC_ERROR
  fi

  # Copy everything from $source into $dest
  if ! cp -rf "$source"/* "$dest"; then
    __print_error "Failed to copy contents from $source into $dest"
    return $EC_ERROR
  fi

  if ! rm -rf "${source:?}"/*; then
    __print_error "Failed to clear $source"
    return $EC_ERROR
  fi

  # The launcher lands with the payload, so it is rewritten after every copy —
  # install and update alike — and can never drift from the shipped one.
  if ! __override_write_launcher "$dest"; then
    __print_error "Failed to write the launch script into $dest"
    return $EC_ERROR
  fi

  __print_success "Deploy complete"
  return $EC_SUCCESS
}

# Replace the shipped `start-server.sh` with one that reports the server's exit
# code as its own.
#
# The shipped script launches the JVM and then ends in an unconditional `exit 0`,
# so whatever happens to the server, the script succeeds. A JVM killed by the
# kernel's OOM killer reaches kgsm-watchdog as "exited cleanly (exit 0)", and a
# crash loop reads as a series of clean exits — which is the one thing a
# supervisor must not be told, because it is what distinguishes a server that
# stopped from a server that died.
#
# `exec` is what fixes it: the shell is replaced by the JVM, so the exit code is
# the server's by construction rather than by remembering to propagate it, and
# signals reach the JVM directly instead of its parent shell.
#
# Everything else is the shipped script's behaviour, deliberately unchanged —
# including `jre64/lib/amd64` on LD_LIBRARY_PATH, which does not exist in the
# current payload, so the `libjsig.so` preload fails and is ignored exactly as it
# is today. Correcting that would switch on JVM signal chaining, which changes
# how the server handles the SIGTERM that stops it; that is a separate change
# from repairing an exit code, and is not smuggled in here.
#
# Args: $1 = install directory
# Returns: 0 on success, 1 on failure
function __override_write_launcher() {
  local install_dir="$1"
  local launcher="${install_dir}/start-server.sh"

  cat >"$launcher" <<'EOF' || return 1
#!/bin/bash
#
# Written by KGSM on every deploy and update; edits here do not survive either.
#
# This is the shipped Project Zomboid launcher with one change: it `exec`s the
# server so the exit code reported to the supervisor is the server's own. The
# shipped script ends in an unconditional `exit 0`, which reports an OOM kill or
# a crash as a clean exit.
#
# Memory options (-Xmx) live in ProjectZomboid64.json, as they always have.

INSTDIR="$(dirname "$0")" ; cd "${INSTDIR}" || exit 1 ; INSTDIR="$(pwd)"

if ! "${INSTDIR}/jre64/bin/java" -version > /dev/null 2>&1; then
	echo "Only 64bit is supported" >&2
	exit 1
fi

export PATH="${INSTDIR}/jre64/bin:$PATH"
export LD_LIBRARY_PATH="${INSTDIR}/linux64:${INSTDIR}:${INSTDIR}/jre64/lib/amd64:${LD_LIBRARY_PATH}"
JSIG="libjsig.so"
export LD_PRELOAD="${LD_PRELOAD}:${JSIG}"

exec ./ProjectZomboid64 "$@"
EOF

  chmod +x "$launcher" || return 1
  return 0
}

export -f __override_write_launcher
