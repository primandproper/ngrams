#!/usr/bin/env bash
# Shared helper for scripts that run the Android build. Source this file; don't run it.

# Runs the Gradle wrapper in the Android project with the toolchain its mise.toml pins (Java, the
# Android SDK), which also sets JAVA_HOME and ANDROID_HOME. -q keeps output to warnings and errors.
gradle_android() {
  local android_dir="$1"
  shift
  (cd "${android_dir}" && mise exec -- ./gradlew -q "$@")
}
