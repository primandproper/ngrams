#!/usr/bin/env bash
set -euo pipefail

# Fail when the Android app has text with no Spanish translation (Android lint's
# MissingTranslation, the only rule the app's lint block turns on)
# Usage: lint_strings_android.sh <android_dir>

ANDROID_DIR="${1:-android}"

# shellcheck source=scripts/gradle.sh
source "$(dirname "${BASH_SOURCE[0]}")/gradle.sh"

gradle_android "${ANDROID_DIR}" :app:lintDebug
