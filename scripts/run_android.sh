#!/usr/bin/env bash
set -euo pipefail

# Boot a Pixel 8 emulator in a window if one isn't up, then install the Debug app on it and open it
# Usage: run_android.sh <android_dir>
# The emulator stays up afterward; close its window to shut it down.

ANDROID_DIR="${1:-android}"

# shellcheck source=scripts/gradle.sh
source "$(dirname "${BASH_SOURCE[0]}")/gradle.sh"

AVD="ngrams-pixel8"
DEVICE="pixel_8"
IMAGE="system-images;android-35;google_apis;arm64-v8a"
# Its own port, apart from the screenshot emulator's.
PORT=5580
SERIAL="emulator-${PORT}"
APP="software.primandproper.ngrams"

tool() { (cd "${ANDROID_DIR}" && mise exec -- "$@"); }
adb_run() { tool adb -s "${SERIAL}" "$@"; }

if ! tool sdkmanager --list_installed 2>/dev/null | grep -q "${IMAGE}"; then
  echo "installing ${IMAGE}"
  yes | tool sdkmanager --install "emulator" "${IMAGE}" >/dev/null
fi
if ! tool avdmanager list avd -c 2>/dev/null | grep -qx "${AVD}"; then
  echo "creating ${AVD}"
  echo no | tool avdmanager create avd -n "${AVD}" -k "${IMAGE}" -d "${DEVICE}" >/dev/null
fi

if ! tool adb devices | grep -q "^${SERIAL}"; then
  echo "booting ${AVD} (${SERIAL})"
  emulator="$(cd "${ANDROID_DIR}" && mise where android-sdk)/emulator/emulator"
  nohup "${emulator}" -avd "${AVD}" -port "${PORT}" -no-boot-anim >/dev/null 2>&1 &
  disown
fi
adb_run wait-for-device
until [[ "$(adb_run shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  sleep 2
done

gradle_android "${ANDROID_DIR}" :app:assembleDebug
adb_run install -r "$(pwd)/${ANDROID_DIR}/app/build/outputs/apk/debug/app-debug.apk" >/dev/null
adb_run shell am start -n "${APP}/.MainActivity" >/dev/null
echo "opened ${APP} on ${SERIAL}"
