#!/usr/bin/env bash
set -euo pipefail

# Format Swift sources with the toolchain's swift-format
# Usage: format_swift.sh <ios_dir>

IOS_DIR="${1:-ios}"

cd "${IOS_DIR}"
swift format --recursive --in-place Ngrams NgramsTests NgramsScreenshots Tools
