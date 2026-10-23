#!/usr/bin/env bash
set -euo pipefail

# Run the iOS unit tests on a simulator
# Usage: test_ios.sh <ios_dir>

IOS_DIR="${1:-ios}"

# shellcheck source=scripts/simulator.sh
source "$(dirname "${BASH_SOURCE[0]}")/simulator.sh"

cd "${IOS_DIR}"
xcodegen generate --quiet

udid="$(resolve_simulator)"
echo "testing on ${IOS_SIM:-$default_simulator} (${udid})"
boot_simulator "${udid}"

# Signing is off so this runs on machines with no signing identity.
xcodebuild \
  -project Ngrams.xcodeproj \
  -scheme Ngrams \
  -destination "id=${udid}" \
  -derivedDataPath build \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  test
