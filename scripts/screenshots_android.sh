#!/usr/bin/env bash
set -euo pipefail

# Capture the Play Store screenshots on an emulator, from a seeded, pinned day, in one interface
# language
# Usage: screenshots_android.sh <android_dir> <out_dir> [en|es]

ANDROID_DIR="${1:-android}"
OUT_DIR="${2:-android/build/play/screenshots/en}"
LANGUAGE="${3:-en}"

# shellcheck source=scripts/gradle.sh
source "$(dirname "${BASH_SOURCE[0]}")/gradle.sh"

# Play wants a phone screenshot's long side no more than twice its short side, which rules out
# modern 20:9 phones; the Pixel profile is 1080x1920, the 9:16 Play recommends.
AVD="ngrams-play"
DEVICE="pixel"
IMAGE="system-images;android-35;google_apis;arm64-v8a"
# Its own port, so it never collides with an emulator already running.
PORT=5590
SERIAL="emulator-${PORT}"
APP="software.primandproper.ngrams"

# The per-app language each interface language runs in: the locales the store listings target.
case "${LANGUAGE}" in
  en) LOCALE="en-US" ;;
  es) LOCALE="es-MX" ;;
  *)
    echo "unknown language ${LANGUAGE}: expected en or es" >&2
    exit 1
    ;;
esac

tool() { (cd "${ANDROID_DIR}" && mise exec -- "$@"); }
adb_play() { tool adb -s "${SERIAL}" "$@"; }

if ! tool sdkmanager --list_installed 2>/dev/null | grep -q "${IMAGE}"; then
  echo "installing ${IMAGE}"
  yes | tool sdkmanager --install "emulator" "${IMAGE}" >/dev/null
fi
if ! tool avdmanager list avd -c 2>/dev/null | grep -qx "${AVD}"; then
  echo "creating ${AVD}"
  echo no | tool avdmanager create avd -n "${AVD}" -k "${IMAGE}" -d "${DEVICE}" >/dev/null
fi

mkdir -p "${OUT_DIR}"
out_dir="$(cd "${OUT_DIR}" && pwd)"
work_dir="$(mktemp -d)"
emulator="$(cd "${ANDROID_DIR}" && mise where android-sdk)/emulator/emulator"
"${emulator}" -avd "${AVD}" -port "${PORT}" -no-window -no-audio -no-boot-anim -no-snapshot \
  >"${work_dir}/emulator.log" 2>&1 &
trap 'adb_play emu kill >/dev/null 2>&1 || true; rm -rf "${work_dir}"' EXIT

echo "capturing ${LANGUAGE} on ${AVD} (${SERIAL})"
adb_play wait-for-device
until [[ "$(adb_play shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  sleep 2
done

# A clean status bar: 9:41, full Wi-Fi and battery, no cellular or notifications.
demo() { adb_play shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
adb_play shell settings put global sysui_demo_allowed 1
demo enter
demo clock -e hhmm 0941
demo battery -e level 100 -e plugged false -e powersave false
demo network -e wifi show -e level 4 -e fully true
demo network -e mobile hide
demo notifications -e visible false

gradle_android "${ANDROID_DIR}" :app:assembleDebug :app:assembleDebugAndroidTest
outputs="${ANDROID_DIR}/app/build/outputs/apk"
adb_play install -r "$(pwd)/${outputs}/debug/app-debug.apk" >/dev/null
adb_play install -r "$(pwd)/${outputs}/androidTest/debug/app-debug-androidTest.apk" >/dev/null
adb_play shell pm clear "${APP}" >/dev/null
# After the clear, which resets the app's language along with its data.
adb_play shell cmd locale set-app-locales "${APP}" --locales "${LOCALE}"

# am instrument exits 0 whatever happens, so success is read from its report.
adb_play shell am instrument -w -e class "${APP}.ScreenshotTest" \
  "${APP}.test/androidx.test.runner.AndroidJUnitRunner" | tee "${work_dir}/instrument.log"
grep -q "^OK (1 test)" "${work_dir}/instrument.log"

adb_play pull "/sdcard/Android/data/${APP}/files/screenshots/." "${out_dir}" >/dev/null 2>&1
for png in "${out_dir}"/*.png; do
  echo "${png}"
done
