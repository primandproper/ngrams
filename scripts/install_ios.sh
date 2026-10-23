#!/usr/bin/env bash
set -euo pipefail

# Build a signed Debug app and install it on a paired iPhone
# Usage: install_ios.sh <ios_dir>
# IOS_DEVICE picks a device by name or identifier; otherwise the first available paired iPhone.

IOS_DIR="${1:-ios}"

cd "${IOS_DIR}"
xcodegen generate --quiet

devices_json="$(mktemp)"
trap 'rm -f "${devices_json}"' EXIT
xcrun devicectl list devices --quiet --json-output "${devices_json}"

device="$(jq -r --arg want "${IOS_DEVICE:-}" '
  [.result.devices[]
    | select(.hardwareProperties.reality == "physical" and .hardwareProperties.deviceType == "iPhone")
    | select(.connectionProperties.pairingState == "paired")
    | select($want == "" or .deviceProperties.name == $want or .identifier == $want
        or .hardwareProperties.udid == $want)]
  | first | .hardwareProperties.udid // empty' "${devices_json}")"
if [[ -z "${device}" ]]; then
  echo "no paired iPhone found${IOS_DEVICE:+ named ${IOS_DEVICE}}; is it connected and unlocked?" >&2
  exit 1
fi
echo "installing on ${device}"

xcodebuild \
  -project Ngrams.xcodeproj \
  -scheme Ngrams \
  -configuration Debug \
  -destination "id=${device}" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  -quiet \
  build

xcrun devicectl device install app --device "${device}" build/Build/Products/Debug-iphoneos/Ngrams.app
