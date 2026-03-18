#!/usr/bin/env bash
set -euo pipefail

AGENT_ID="local.sri.Flow"
AGENT_PATH="${HOME}/Library/LaunchAgents/${AGENT_ID}.plist"
LEGACY_AGENT_ID="local.sri.WisprMenuBar"
LEGACY_AGENT_PATH="${HOME}/Library/LaunchAgents/${LEGACY_AGENT_ID}.plist"
GUI_DOMAIN="gui/$(id -u)"

if [[ -f "${AGENT_PATH}" ]]; then
  launchctl bootout "${GUI_DOMAIN}" "${AGENT_PATH}" >/dev/null 2>&1 || true
  rm -f "${AGENT_PATH}"
fi

if [[ -f "${LEGACY_AGENT_PATH}" ]]; then
  launchctl bootout "${GUI_DOMAIN}" "${LEGACY_AGENT_PATH}" >/dev/null 2>&1 || true
  rm -f "${LEGACY_AGENT_PATH}"
fi

echo "Removed login LaunchAgent at ${AGENT_PATH}"
