#!/usr/bin/env bash
# Source this file to populate lumen-panel environment variables:
#   source env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export LUMEN_RES_DIR="${SCRIPT_DIR}/lumen-panel/src/res/"
export LUMEN_KICKOFF_BIN="${SCRIPT_DIR}/build/kickoff"
export LUMEN_THEME_FILE="${SCRIPT_DIR}/default-theme.json"
