#!/usr/bin/env bash
#
# deploy-common.sh — the shared parameter block + helpers for kgsm's deploy scripts.
#
# Sourced by BOTH deploy/setup.sh (the one-shot privileged host provisioning) and
# deploy/deploy.sh (the headless code delivery). Every path lives here exactly once, so the two
# entry points can never disagree about what this project installs.
#
# The canonical source of this pattern is tks/scripts/deploy-template/ — see its README for the
# contract. kgsm is the simplest case in the ecosystem: the engine is a bash tree with NO systemd
# unit and NO daemon, so there is no unit to link and no polkit grant to install. setup.sh only
# has to create the install prefix and put `kgsm` on PATH; after that deploy.sh is a plain rsync
# into a directory you own, with no privilege whatsoever.
#
# Not executable on its own.

# This file only DEFINES things; every variable below is consumed by the two scripts that
# source it, which shellcheck cannot see from here.
# shellcheck disable=SC2034

set -euo pipefail

# ── Identity ──────────────────────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEPLOY_USER="${KGSM_DEPLOY_USER:-$(id -un)}"
DEPLOY_GROUP="${KGSM_DEPLOY_GROUP:-$(id -gn)}"

# ── PROJECT BLOCK ─────────────────────────────────────────────────────────────
PROJECT="kgsm"

# The canonical install: a byte-identical copy of this checkout. The `kgsm` on PATH resolves here.
PREFIX="/opt/kgsm"
BIN_LINK="/usr/local/bin/kgsm"
ENTRYPOINT="kgsm.sh"

# Everything that is checkout-only and must never reach the deployed copy. Anything present in
# PREFIX but not in the checkout (and not excluded here) is pruned on deploy, so the deployed
# tree always matches the source exactly.
RSYNC_EXCLUDES=(--exclude='.git' --exclude='node_modules' --exclude='.dev-instances')
# ── END PROJECT BLOCK ─────────────────────────────────────────────────────────

SUDO="${SUDO:-sudo}"

# ── Output helpers ────────────────────────────────────────────────────────────
log()  { printf '\033[1;34m>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m** %s\033[0m\n' "$*" >&2; }
err()  { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; }

refuse_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        err "do NOT run this as root — run it as the KGSM (instance-owning) user."
        err "setup.sh sudo's the two steps that need it; deploy.sh needs no privilege at all."
        exit 1
    fi
}

# The contract deploy.sh enforces: this host has been provisioned. A missing piece means setup.sh
# has not run — say so and stop, rather than blocking on a password prompt.
require_setup() {
    local problem=0

    [[ -d "$PREFIX" && -w "$PREFIX" ]] || {
        err "install prefix ${PREFIX} is missing or not writable by $(id -un)."; problem=1; }

    if [[ "$problem" -ne 0 ]]; then
        err ""
        err "this host is not provisioned for headless deploys of ${PROJECT}."
        err "run ONCE (it will ask for your sudo password):   ${REPO_DIR}/deploy/setup.sh"
        exit 1
    fi
}
