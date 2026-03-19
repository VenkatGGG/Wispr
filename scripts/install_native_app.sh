#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_OUTPUT_DIR="${WISPR_NATIVE_BUILD_OUTPUT_DIR:-${HOME}/Library/Caches/Flow}"
SOURCE_APP_DIR="${BUILD_OUTPUT_DIR}/Flow.app"
TARGET_APPS_DIR="${HOME}/Applications"
TARGET_APP_DIR="${TARGET_APPS_DIR}/Flow.app"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/Flow"
LEGACY_APP_SUPPORT_DIR="${HOME}/Library/Application Support/WisprMenuBar"
RUNTIME_CONFIG_PATH="${APP_SUPPORT_DIR}/runtime.json"

if [[ ! -d "${SOURCE_APP_DIR}" ]]; then
  echo "Build the app first with ./scripts/build_native_app.sh" >&2
  exit 1
fi

mkdir -p "${TARGET_APPS_DIR}"
pkill -x WisprMenuBar >/dev/null 2>&1 || true
pkill -x Flow >/dev/null 2>&1 || true
rm -rf "${TARGET_APPS_DIR}/WisprMenuBar.app"
rm -rf "${TARGET_APP_DIR}"
ditto "${SOURCE_APP_DIR}" "${TARGET_APP_DIR}"
mkdir -p "${APP_SUPPORT_DIR}"

for filename in history.json phrases.json; do
  if [[ -f "${LEGACY_APP_SUPPORT_DIR}/${filename}" && ! -f "${APP_SUPPORT_DIR}/${filename}" ]]; then
    cp "${LEGACY_APP_SUPPORT_DIR}/${filename}" "${APP_SUPPORT_DIR}/${filename}"
  fi
done

cat > "${RUNTIME_CONFIG_PATH}" <<EOF
{
  "repositoryRootPath": "${ROOT_DIR}"
}
EOF

codesign --verify --deep --verbose=2 "${TARGET_APP_DIR}" >/dev/null

echo "Installed ${TARGET_APP_DIR}"
