#!/usr/bin/env bash
set -euo pipefail

# Draw the app icon's light, dark, and tinted variants into the asset catalog
# Usage: make_icon.sh <ios_dir>

IOS_DIR="${1:-ios}"
ICON_DIR="${IOS_DIR}/Ngrams/Assets.xcassets/AppIcon.appiconset"

mkdir -p "${ICON_DIR}"
swift "${IOS_DIR}/Tools/AppIcon.swift" "${ICON_DIR}"
