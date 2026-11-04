#!/usr/bin/env bash
#
# Project Zomboid: the shipped launcher ends in an unconditional exit 0.
#
# shellcheck disable=SC2154,SC2329

# <install_dir>: replaces the shipped start-server.sh with one that reports the
# server's exit code as its own. The shipped script launches the JVM and then
# exits 0 whatever happened, so a JVM killed by the kernel's OOM killer reaches
# a supervisor as a clean exit and a crash loop reads as a series of clean ones.
# exec replaces the shell with the JVM, so the exit code is the server's by
# construction and signals reach the JVM directly. The launcher lands with the
# payload, so it is rewritten after every deploy.
kgsm_hook_post_deploy() {
  _hook_write_launcher "$1"
}

_hook_write_launcher() {
  local launcher="${1}/start-server.sh"

  cat >"$launcher" <<'LAUNCHER'
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
LAUNCHER

  chmod +x "$launcher"
}
