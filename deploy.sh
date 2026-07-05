#!/usr/bin/env bash
set -euo pipefail

DEST="/opt/kgsm"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SRC}/kgsm.sh" ]]; then
  echo "Error: kgsm.sh not found in ${SRC}" >&2
  exit 1
fi

echo "Deploying KGSM from ${SRC} to ${DEST}..."

if [[ -d "${DEST}" ]]; then
  echo "Existing installation found at ${DEST}"
  read -rp "Overwrite? [y/N] " confirm
  if [[ "${confirm}" != [yY] ]]; then
    echo "Aborted."
    exit 0
  fi
  sudo rm -rf "${DEST}"
fi

sudo mkdir -p "${DEST}"
sudo rsync -a --exclude='.git' --exclude='node_modules' --exclude='.dev-instances' \
  "${SRC}/" "${DEST}/"
sudo chmod +x "${DEST}/kgsm.sh"
sudo find "${DEST}/scripts" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

echo "Installed to ${DEST}"
echo "Run: ${DEST}/kgsm.sh --help"
