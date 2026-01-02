#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE64_FILE="${SCRIPT_DIR}/source.png.b64"
PNG_FILE="${SCRIPT_DIR}/source.png"

if [[ ! -f "${BASE64_FILE}" ]]; then
  echo "Missing base64 icon source at ${BASE64_FILE}" >&2
  exit 1
fi

mkdir -p "${ICON_DIR}"
base64 -d "${BASE64_FILE}" > "${PNG_FILE}"

(
  cd "${ROOT_DIR}"
  dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
)
