#!/usr/bin/env bash
# Shared helpers for scripts that drive the iOS simulator. Source this file; don't run it.

default_simulator="iPhone 18 Pro"

# Prints the UDID of an available simulator named exactly $1 on the newest iOS runtime that has
# one, since older runtimes can't run the app's deployment target.
simulator_udid() {
  local name="$1"
  xcrun simctl list devices available --json |
    jq -r --arg name "$name" '
      [.devices | to_entries[]
        | select(.key | test("SimRuntime\\.iOS-"))
        | (.key | capture("iOS-(?<major>[0-9]+)-(?<minor>[0-9]+)")) as $v
        | .value[] | select(.name == $name)
        | {udid, major: ($v.major | tonumber), minor: ($v.minor | tonumber)}]
      | sort_by(.major, .minor) | last | .udid // empty'
}

# Prints the UDID to run on. IOS_SIM, when set, must name an available simulator exactly.
resolve_simulator() {
  local name="${IOS_SIM:-$default_simulator}"
  local udid
  udid="$(simulator_udid "$name")"
  if [[ -z "$udid" ]]; then
    echo "no available simulator named '$name' (set IOS_SIM to pick one)" >&2
    return 1
  fi
  echo "$udid"
}

# Boots the simulator if it isn't already running, then waits for it to finish booting. Testing
# against a simulator that's still booting can hang xcodebuild until its 10-minute timeout.
boot_simulator() {
  local udid="$1"
  xcrun simctl bootstatus "$udid" -b >/dev/null
}
