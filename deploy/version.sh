#!/usr/bin/env bash
#
# version.sh — print this project's packaging version.
#
#   ./deploy/version.sh            # the version as declared
#   ./deploy/version.sh --pkgver   # the same, in a form pacman accepts
#
# The version is declared in exactly ONE place — core/bootstrap.sh's KGSM_VERSION — and read from there, so the package,
# the binary and the changelog can never disagree about what this is.
#
# The engine is bash, so the version lives in the code it ships rather than in a project file.

# A pacman pkgver may not contain a hyphen, so --pkgver strips it. That keeps prerelease ordering
# correct under vercmp: 3.16.0rc3 < 3.16.0rc4 < 3.16.0.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="${HERE}/../core/bootstrap.sh"

read_version() {
    grep -oP 'KGSM_VERSION="\K[^"]+' "$SOURCE_FILE" | head -1
}

raw="$(read_version || true)"
[[ -n "$raw" ]] || { printf 'version.sh: no version found in %s\n' "$SOURCE_FILE" >&2; exit 1; }

case "${1:-}" in
    "")       printf '%s\n' "$raw" ;;
    --pkgver) printf '%s\n' "${raw//-/}" ;;
    *)        printf 'usage: version.sh [--pkgver]\n' >&2; exit 1 ;;
esac
