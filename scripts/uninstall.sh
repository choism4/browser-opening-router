#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-/Applications}"
DEST="${APP_DIR}/BrowserOpeningRouter.app"

if [ -e "${DEST}" ]; then
  rm -rf "${DEST}"
  echo "Removed: ${DEST}"
else
  echo "Not installed: ${DEST}"
fi
