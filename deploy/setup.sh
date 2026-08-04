#!/usr/bin/env bash
#
# setup.sh — one-shot host provisioning for the kgsm engine. Run it ONCE per host.
#
#   ./deploy/setup.sh
#
# This is the ONLY kgsm script that needs privilege. It asks for your sudo password, provisions
# the two things that live outside your ownership, and hands the host over to deploy/deploy.sh —
# which from then on deploys with NO password and NO prompt, forever.
#
# Idempotent: safe to re-run any time. A steady-state re-run changes nothing.
#
# What it provisions:
#   1. /opt/kgsm            — the canonical install, chowned to you so deploy.sh rsyncs into it
#                             with no privilege.
#   2. /usr/local/bin/kgsm  — the symlink that puts `kgsm` on PATH, pointing at /opt/kgsm/kgsm.sh.
#                             The link target is stable, so redeploying the tree behind it needs
#                             no privilege and no re-linking.
#
# No system unit and no polkit grant here: the engine is a bash tree, not a daemon. The only
# unit is a USER timer for event-journal retention, which needs no privilege.
# (Native game-server lifecycle is supervised by the resident kgsm-watchdog, which has its own
# setup.sh in its own repo.)
#
# Non-interactive (CI / an agent): no password ever lives in this script — point sudo at an
# askpass helper instead.
#   printf '#!/bin/sh\necho YOUR_PASS\n' > /tmp/ap && chmod 700 /tmp/ap
#   SUDO='sudo -A' SUDO_ASKPASS=/tmp/ap ./deploy/setup.sh
#
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/deploy-common.sh"

trap 'err "setup failed (line ${LINENO}). Re-run this script."; exit 1' ERR

refuse_root

[[ -f "$REPO_DIR/$ENTRYPOINT" ]] || { err "${ENTRYPOINT} not found in ${REPO_DIR} — is this a kgsm checkout?"; exit 1; }

log "provisioning ${PROJECT} for headless deploys by '${DEPLOY_USER}'"

$SUDO true || { err "sudo is not usable — setup needs it once."; exit 1; }

# ── 1. The install prefix (owned by the deploying user) ───────────────────────
if [[ ! -d "$PREFIX" ]]; then
    log "creating ${PREFIX} (owned by ${DEPLOY_USER})"
    $SUDO install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$PREFIX"
elif [[ "$(stat -c '%U' "$PREFIX")" != "$DEPLOY_USER" ]]; then
    log "chowning ${PREFIX} → ${DEPLOY_USER}:${DEPLOY_GROUP} (so deploys need no privilege)"
    $SUDO chown -R "${DEPLOY_USER}:${DEPLOY_GROUP}" "$PREFIX"
fi

# ── 2. `kgsm` on PATH ─────────────────────────────────────────────────────────
if [[ "$(readlink -f "$BIN_LINK" 2>/dev/null)" != "$PREFIX/$ENTRYPOINT" ]]; then
    log "symlinking ${BIN_LINK} → ${PREFIX}/${ENTRYPOINT}"
    $SUDO ln -sfn "$PREFIX/$ENTRYPOINT" "$BIN_LINK"
fi

# ── 3. The event journal directory ────────────────────────────────────────────
# kgsm appends every event here as an unprivileged process, and consumers read
# it, so it is owned by the deploying user and world-readable. /var/lib/kgsm is
# root-owned (it also holds the leaf descriptors), which is why creating the
# subdirectory needs the one privileged step rather than happening on first emit.
if [[ ! -d "$JOURNAL_DIR" ]]; then
    log "creating ${JOURNAL_DIR} (owned by ${DEPLOY_USER})"
    $SUDO install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$JOURNAL_DIR"
elif [[ "$(stat -c '%U' "$JOURNAL_DIR")" != "$DEPLOY_USER" ]]; then
    log "chowning ${JOURNAL_DIR} → ${DEPLOY_USER}:${DEPLOY_GROUP}"
    $SUDO chown -R "${DEPLOY_USER}:${DEPLOY_GROUP}" "$JOURNAL_DIR"
fi

# ── 4. Journal retention timer (a USER unit — no privilege, no system unit) ───
# The engine stays a bash tree with no system service. Retention is periodic
# maintenance, not a daemon, so it runs as a user timer: it needs no sudo, no
# polkit grant, and touches nothing outside the deploying user's own systemd.
if command -v systemctl > /dev/null 2>&1; then
    USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$USER_UNIT_DIR"
    install -m 0644 "$REPO_DIR/deploy/kgsm-journal-prune.service" "$USER_UNIT_DIR/"
    install -m 0644 "$REPO_DIR/deploy/kgsm-journal-prune.timer" "$USER_UNIT_DIR/"

    # A non-login shell (CI, an agent, `sudo` without the session) inherits no
    # XDG_RUNTIME_DIR, and `systemctl --user` cannot find the bus without it —
    # which would silently skip the timer on exactly the headless hosts this
    # script exists for. Point it at the running user manager when it exists.
    RUNTIME_DIR="/run/user/$(id -u)"
    if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "$RUNTIME_DIR" ]]; then
        export XDG_RUNTIME_DIR="$RUNTIME_DIR"
    fi

    if systemctl --user daemon-reload 2>/dev/null &&
        systemctl --user enable --now kgsm-journal-prune.timer 2>/dev/null; then
        log "journal retention timer enabled (systemctl --user)"
    else
        log "user systemd unreachable — run 'kgsm events journal prune' from cron instead"
    fi
else
    log "systemd absent — run 'kgsm events journal prune' from cron for retention"
fi

trap - ERR

# ── 5. Summary ────────────────────────────────────────────────────────────────
log "${PROJECT} is provisioned ✓  — deploys are now headless"
printf '   prefix : %s (owned by %s)\n' "$PREFIX" "$DEPLOY_USER"
printf '   on PATH: %s → %s/%s\n' "$BIN_LINK" "$PREFIX" "$ENTRYPOINT"
printf '\n   deploy from now on with:  %s/deploy/deploy.sh   (no sudo, no prompts)\n' "$REPO_DIR"
