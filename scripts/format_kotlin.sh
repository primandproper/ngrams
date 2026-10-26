#!/usr/bin/env bash
set -euo pipefail

# Format Kotlin sources with ktlint
# Usage: format_kotlin.sh <android_dir>

ANDROID_DIR="${1:-android}"

# shellcheck source=scripts/gradle.sh
source "$(dirname "${BASH_SOURCE[0]}")/gradle.sh"

gradle_android "${ANDROID_DIR}" ktlintFormat
