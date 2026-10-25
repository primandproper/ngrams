#!/usr/bin/env bash
set -euo pipefail

# Lint Swift sources with the toolchain's swift-format
# Usage: lint_swift.sh <ios_dir>

IOS_DIR="${1:-ios}"

cd "${IOS_DIR}"
swift format lint --recursive --strict Ngrams NgramsTests Tools
