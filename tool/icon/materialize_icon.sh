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
python3 - <<'PY'
import base64, pathlib
b64 = pathlib.Path(r"""'"${BASE64_FILE}"'""").read_text().strip()
pathlib.Path(r"""'"${PNG_FILE}"'""").write_bytes(base64.b64decode(b64))
PY

(
  cd "${ROOT_DIR}"
  dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
)
