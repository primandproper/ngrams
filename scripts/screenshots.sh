#!/usr/bin/env bash
set -euo pipefail

# Capture the App Store screenshots on one simulator, from a seeded, pinned day. Each display
# size App Store Connect asks for is a run on a simulator of that size.
# Usage: screenshots.sh <ios_dir> <out_dir> <simulator> [language]
# language is the interface language the app runs in: en (the default) or es.

IOS_DIR="${1:-ios}"
OUT_DIR="${2:-ios/build/screenshots}"
IOS_SIM="${3:?simulator name}"
LANGUAGE="${4:-en}"

# shellcheck source=scripts/simulator.sh
source "$(dirname "${BASH_SOURCE[0]}")/simulator.sh"

udid="$(resolve_simulator)"
echo "capturing in ${LANGUAGE} on ${IOS_SIM} (${udid})"
boot_simulator "${udid}"

work_dir="$(mktemp -d)"
# The simulator can inherit a forced 24-hour clock from the Mac, which shows 09:41. Turn it off
# for the run, rebooting since the status bar only reads it at boot, and put back whatever was
# there; the clock returns to it at the next boot.
force_24h="$(xcrun simctl spawn "${udid}" defaults read -g AppleICUForce24HourTime 2>/dev/null || true)"
restore() {
  xcrun simctl status_bar "${udid}" clear
  if [[ -n "${force_24h}" ]]; then
    xcrun simctl spawn "${udid}" defaults write -g AppleICUForce24HourTime -int "${force_24h}"
  else
    xcrun simctl spawn "${udid}" defaults delete -g AppleICUForce24HourTime
  fi
  rm -rf "${work_dir}"
}
trap restore EXIT
xcrun simctl spawn "${udid}" defaults write -g AppleICUForce24HourTime -bool NO
xcrun simctl shutdown "${udid}"
boot_simulator "${udid}"
xcrun simctl ui "${udid}" appearance light
xcrun simctl status_bar "${udid}" override \
  --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --operatorName "" \
  --batteryState discharging --batteryLevel 100

mkdir -p "${OUT_DIR}"
out_dir="$(cd "${OUT_DIR}" && pwd)"

cd "${IOS_DIR}"
xcodegen generate --quiet

result="${work_dir}/screenshots.xcresult"
# xcodebuild hands TEST_RUNNER_-prefixed variables to the test runner, without the prefix.
TEST_RUNNER_SCREENSHOT_LANGUAGE="${LANGUAGE}" xcodebuild \
  -project Ngrams.xcodeproj \
  -scheme NgramsScreenshots \
  -destination "id=${udid}" \
  -derivedDataPath build \
  -resultBundlePath "${result}" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  test

attachments="${work_dir}/attachments"
xcrun xcresulttool export attachments --path "${result}" --output-path "${attachments}"
# Attachments export under UUIDs; the test named each one, plus a suffix xcresulttool adds.
jq -r '.[].attachments[]
  | [.exportedFileName, (.suggestedHumanReadableName | sub("_[0-9]+_[0-9A-F-]+\\.png$"; ".png"))]
  | @tsv' "${attachments}/manifest.json" |
  while IFS=$'\t' read -r exported name; do
    cp "${attachments}/${exported}" "${out_dir}/${name}"
    echo "${out_dir}/${name}"
  done
