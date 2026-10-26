#!/usr/bin/env bash
set -euo pipefail

# Run the Android unit tests and build the debug app, so a change that breaks only the app's
# compile still fails
# Usage: test_android.sh <android_dir>

ANDROID_DIR="${1:-android}"

# shellcheck source=scripts/gradle.sh
source "$(dirname "${BASH_SOURCE[0]}")/gradle.sh"

echo "testing android"
gradle_android "${ANDROID_DIR}" test :app:assembleDebug
