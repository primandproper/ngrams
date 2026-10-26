#!/usr/bin/env bash
set -euo pipefail

# Draw the app icon: the iOS light, dark, and tinted variants into the asset catalog, and the
# Android adaptive icon's layers into the app's resources
# Usage: make_icon.sh <ios_dir> <android_dir>

IOS_DIR="${1:-ios}"
ANDROID_DIR="${2:-android}"
ICON_DIR="${IOS_DIR}/Ngrams/Assets.xcassets/AppIcon.appiconset"
RES_DIR="${ANDROID_DIR}/app/src/main/res"

mkdir -p "${ICON_DIR}" "${RES_DIR}"
swift "${IOS_DIR}/Tools/AppIcon.swift" "${ICON_DIR}" "${RES_DIR}"
