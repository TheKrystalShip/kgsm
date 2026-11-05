#!/usr/bin/env bash
#
# version.sh — print this project's packaging version.
#
#   ./deploy/version.sh            # the version as declared
#   ./deploy/version.sh --pkgver   # the same, in a form pacman accepts
#
# The version is declared in exactly ONE place, named in the PROJECT BLOCK below, and read from
# there, so the package, the binary and the changelog can never disagree about what this is.
#
# Vendored per repo from tks/scripts/deploy-template/. A repo's own lines are its PROJECT BLOCK;
# everything else is the template's, written by the template's vendor.sh and checked by
# `vendor.sh --check`.

# A pacman pkgver may not contain a hyphen, so --pkgver strips it. That keeps prerelease ordering
# correct under vercmp: 3.16.0rc3 < 3.16.0rc4 < 3.16.0.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ── PROJECT BLOCK — the one file that declares this project's version, and how it is read ──
SOURCE_FILE="${HERE}/../Directory.Build.props"

read_version() {
    grep -oP '<Version>\K[0-9][^<]*(?=</Version>)' "$SOURCE_FILE" | head -1
}
# ── END PROJECT BLOCK ───────────────────────────────────────────────────────────

raw="$(read_version || true)"
[[ -n "$raw" ]] || { printf 'version.sh: no version found in %s\n' "$SOURCE_FILE" >&2; exit 1; }

case "${1:-}" in
    "")       printf '%s\n' "$raw" ;;
    --pkgver) printf '%s\n' "${raw//-/}" ;;
    *)        printf 'usage: version.sh [--pkgver]\n' >&2; exit 1 ;;
esac
