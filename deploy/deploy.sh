#!/usr/bin/env bash
#
# deploy.sh — publish this checkout to the canonical install. Fully headless: no sudo, no prompts.
#
#   ./deploy/deploy.sh
#
# Assumes deploy/setup.sh has provisioned this host (/opt/kgsm owned by you, `kgsm` on PATH). If
# it has not, this script says so and stops.
#
# The deployed copy at /opt/kgsm is byte-identical to this checkout, minus the checkout-only
# paths (.git, node_modules, .dev-instances). The sync PRUNES: anything in /opt/kgsm that is no
# longer in the checkout is removed, so a deleted command or override never lingers on the
# deployed engine. Per-file writes are atomic (temp + rename).
#
# No confirmation prompt: this is a build artifact refresh, not a destructive act. /opt/kgsm holds
# only engine code — instances, config and logs live under XDG paths in your home directory and
# are never touched here.
#
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/deploy-common.sh"

trap 'err "deploy failed (line $LINENO)."; exit 1' ERR

# ── Preflight ─────────────────────────────────────────────────────────────────
refuse_root
require_setup
[[ -f "$REPO_DIR/$ENTRYPOINT" ]] || { err "${ENTRYPOINT} not found in ${REPO_DIR}"; exit 1; }

# ── 1. Sync the tree ──────────────────────────────────────────────────────────
log "deploying ${PROJECT} from ${REPO_DIR} → ${PREFIX}"
rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$REPO_DIR/" "$PREFIX/"

# ── 2. Executable bits ────────────────────────────────────────────────────────
# rsync preserves modes, so this only matters for a checkout where a script lost its +x.
chmod +x "$PREFIX/$ENTRYPOINT"
find "$PREFIX/scripts" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

# ── 3. Verify (the deployed entrypoint actually runs) ─────────────────────────
# Success is the deployed copy answering, not just files having landed.
if ! "$PREFIX/$ENTRYPOINT" --version >/dev/null 2>&1; then
    err "${PREFIX}/${ENTRYPOINT} did not run cleanly after the sync."
    err "try: ${PREFIX}/${ENTRYPOINT} --version"
    exit 1
fi

log "${PROJECT} deployed ✓  ($("$PREFIX/$ENTRYPOINT" --version 2>/dev/null | head -n1))"
printf '   installed: %s\n   on PATH  : %s\n' "$PREFIX" "$BIN_LINK"
