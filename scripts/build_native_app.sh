#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="${ROOT_DIR}/native"
BUILD_DIR="${PACKAGE_DIR}/.build/release"
APP_NAME="Flow"
BUILD_OUTPUT_DIR="${WISPR_NATIVE_BUILD_OUTPUT_DIR:-${HOME}/Library/Caches/Flow}"
APP_DIR="${BUILD_OUTPUT_DIR}/${APP_NAME}.app"
APP_CONTENTS="${APP_DIR}/Contents"
APP_BINARY="${BUILD_DIR}/${APP_NAME}"
SIGNING_IDENTITY_NAME="${WISPR_CODESIGN_IDENTITY:-Wispr Local Development}"

collect_signing_identity_hashes() {
  security find-identity -v -p codesigning \
    | awk -v name="${SIGNING_IDENTITY_NAME}" '$0 ~ "\"" name "\"" { print $2 }'
}

load_signing_identity_hashes() {
  SIGNING_IDENTITY_HASHES=()
  while IFS= read -r identity_hash; do
    [[ -n "${identity_hash}" ]] && SIGNING_IDENTITY_HASHES+=("${identity_hash}")
  done < <(collect_signing_identity_hashes || true)
}

try_sign_with_identity() {
  local identity_hash="$1"
  codesign --force --timestamp=none --sign "${identity_hash}" "${APP_CONTENTS}/MacOS/${APP_NAME}" \
    && codesign --force --timestamp=none --sign "${identity_hash}" "${APP_DIR}"
}

load_signing_identity_hashes
if [[ ${#SIGNING_IDENTITY_HASHES[@]} -eq 0 && -x "${ROOT_DIR}/scripts/setup_codesign_identity.sh" ]]; then
  "${ROOT_DIR}/scripts/setup_codesign_identity.sh" >/dev/null 2>&1 || true
  load_signing_identity_hashes
fi

swift build --package-path "${PACKAGE_DIR}" -c release --product "${APP_NAME}"

mkdir -p "${BUILD_OUTPUT_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_CONTENTS}"
mkdir -p "${APP_CONTENTS}/MacOS"

cp "${APP_BINARY}" "${APP_CONTENTS}/MacOS/${APP_NAME}"
/usr/bin/xattr -d com.apple.provenance "${APP_CONTENTS}/MacOS/${APP_NAME}" 2>/dev/null || true

cat > "${APP_CONTENTS}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Flow</string>
  <key>CFBundleIdentifier</key>
  <string>local.sri.Flow</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Flow</string>
  <key>CFBundleDisplayName</key>
  <string>Flow</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Flow needs microphone access to record held-to-dictate audio.</string>
</dict>
</plist>
PLIST

/usr/bin/xattr -d com.apple.provenance "${APP_CONTENTS}/Info.plist" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.provenance "${APP_DIR}" 2>/dev/null || true
/usr/bin/xattr -cr "${APP_DIR}"

SIGNED_WITH_IDENTITY=""
for identity_hash in "${SIGNING_IDENTITY_HASHES[@]}"; do
  if try_sign_with_identity "${identity_hash}"; then
    SIGNED_WITH_IDENTITY="${identity_hash}"
    break
  fi
done

if [[ -n "${SIGNED_WITH_IDENTITY}" ]]; then
  echo "Signed ${APP_DIR} with ${SIGNING_IDENTITY_NAME} (${SIGNED_WITH_IDENTITY})"
else
  if [[ ${#SIGNING_IDENTITY_HASHES[@]} -gt 0 ]]; then
    echo "Stable signing failed for all matching identities; using ad hoc signing." >&2
  else
    echo "No local signing identity available; using ad hoc signing." >&2
  fi
  codesign --force --timestamp=none --sign - "${APP_CONTENTS}/MacOS/${APP_NAME}"
  codesign --force --timestamp=none --sign - "${APP_DIR}"
fi

find "${APP_DIR}" -name '*.cstemp' -delete
codesign --verify --deep --strict --verbose=2 "${APP_DIR}" >/dev/null

echo "Built ${APP_DIR}"
