#!/usr/bin/env bash
set -euo pipefail

# Draw the App Store product page header image
# Usage: make_header.sh <ios_dir> <output_png>

IOS_DIR="${1:-ios}"
OUTPUT="${2:-ios/build/app-store/header.png}"

mkdir -p "$(dirname "${OUTPUT}")"
swift "${IOS_DIR}/Tools/AppStoreHeader.swift" "${OUTPUT}"
echo "${OUTPUT}"
