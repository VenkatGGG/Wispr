#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${HOME}/Applications/Flow.app"
AGENT_ID="local.sri.Flow"
LEGACY_AGENT_ID="local.sri.WisprMenuBar"
AGENT_DIR="${HOME}/Library/LaunchAgents"
AGENT_PATH="${AGENT_DIR}/${AGENT_ID}.plist"
LEGACY_AGENT_PATH="${AGENT_DIR}/${LEGACY_AGENT_ID}.plist"
LOG_DIR="${HOME}/Library/Logs"
GUI_DOMAIN="gui/$(id -u)"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "Install the app first with ./scripts/install_native_app.sh" >&2
  exit 1
fi

mkdir -p "${AGENT_DIR}" "${LOG_DIR}"

cat > "${AGENT_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${AGENT_ID}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${APP_DIR}/Contents/MacOS/Flow</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/Flow.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/Flow.log</string>
</dict>
</plist>
PLIST

launchctl bootout "${GUI_DOMAIN}" "${AGENT_PATH}" >/dev/null 2>&1 || true
launchctl bootout "${GUI_DOMAIN}" "${LEGACY_AGENT_PATH}" >/dev/null 2>&1 || true
rm -f "${LEGACY_AGENT_PATH}"
launchctl bootstrap "${GUI_DOMAIN}" "${AGENT_PATH}"
launchctl kickstart -k "${GUI_DOMAIN}/${AGENT_ID}"

echo "Installed login LaunchAgent at ${AGENT_PATH}"
