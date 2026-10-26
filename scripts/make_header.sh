#!/usr/bin/env bash
set -euo pipefail

# Draw the store banners: the App Store product page header and the Play Store feature graphic
# Usage: make_header.sh <ios_dir> <header_png> <feature_graphic_png>

IOS_DIR="${1:-ios}"
HEADER="${2:-ios/build/app-store/header.png}"
FEATURE_GRAPHIC="${3:-android/build/play/feature-graphic.png}"

mkdir -p "$(dirname "${HEADER}")" "$(dirname "${FEATURE_GRAPHIC}")"
swift "${IOS_DIR}/Tools/AppStoreHeader.swift" "${HEADER}" 3840 1646
swift "${IOS_DIR}/Tools/AppStoreHeader.swift" "${FEATURE_GRAPHIC}" 1024 500
echo "${HEADER}"
echo "${FEATURE_GRAPHIC}"
