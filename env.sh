#!/usr/bin/env bash
# Source this file to populate lumen-panel environment variables:
#   source env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export LUMEN_RES_DIR="${SCRIPT_DIR}/lumen-panel/src/res/"
export LUMEN_KICKOFF_BIN="${SCRIPT_DIR}/build/kickoff"
export LUMEN_THEME_FILE="${SCRIPT_DIR}/default-theme.json"
export LUMEN_OSD_THEME_FILE="${SCRIPT_DIR}/lumen-osd/default-theme.json"
export LUMEN_NOTIFICATIONS_BIN="${SCRIPT_DIR}/build/lumen-notifications"
export LUMEN_NOTIFICATIONS_THEME_FILE="${SCRIPT_DIR}/lumen-notifications/default-notifications-theme.json"

# GTK4 panel port: fall back to the NGL renderer if Vulkan misbehaves on the
# host GPU. Remove this line to let GTK auto-select.
export GSK_RENDERER="${GSK_RENDERER:-ngl}"
