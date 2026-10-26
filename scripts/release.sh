#!/usr/bin/env bash
set -euo pipefail

# Archive a Release build, upload it to App Store Connect, and tag the commit it came from.
# Submitting the build for review and releasing it stay manual, in App Store Connect.
# Usage: release.sh <ios_dir> <bank_file> <key_id> <issuer_id> <op_key_item> [min_bank_days]

IOS_DIR="${1:-ios}"
BANK_FILE="${2:-data/bank/puzzles.json}"
KEY_ID="${3:?App Store Connect API key ID}"
ISSUER_ID="${4:?App Store Connect issuer ID}"
OP_KEY_ITEM="${5:?1Password item holding the API key}"
MIN_BANK_DAYS="${6:-60}"

fail() {
  echo "release: $*" >&2
  exit 1
}

# Preflight: ship only what's on origin/main, with enough puzzles left to outlast review.
[[ -z "$(git status --porcelain)" ]] || fail "working tree isn't clean"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "not on main"
git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "HEAD isn't origin/main; push or pull first"

bank_end="$(jq -r '.days[-1].date' "${BANK_FILE}")"
runway_end="$(date -v+"${MIN_BANK_DAYS}"d +%F)"
[[ "${bank_end}" > "${runway_end}" ]] || fail "the bank ends ${bank_end}, within ${MIN_BANK_DAYS} days; extend it with make bank"

make lint test

version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' "${IOS_DIR}/project.yml")"
[[ -n "${version}" ]] || fail "no MARKETING_VERSION in ${IOS_DIR}/project.yml"
build="$(git rev-list --count HEAD)"
tag="v${version}+${build}"
echo "releasing ${version} (${build})"

# xcodebuild wants the key as a file; keep it only as long as this script runs.
key_dir="$(mktemp -d)"
trap 'rm -rf "${key_dir}"' EXIT
key_file="${key_dir}/AuthKey_${KEY_ID}.p8"
category="$(op item get "${OP_KEY_ITEM}" --format json | jq -r '.category')"
case "${category}" in
  DOCUMENT) op document get "${OP_KEY_ITEM}" --out-file "${key_file}" --force >/dev/null ;;
  API_CREDENTIAL) op item get "${OP_KEY_ITEM}" --fields label=credential --reveal >"${key_file}" ;;
  *) fail "1Password item ${OP_KEY_ITEM} is a ${category}; expected a Document or API Credential" ;;
esac
chmod 600 "${key_file}"

auth=(
  -allowProvisioningUpdates
  -authenticationKeyPath "${key_file}"
  -authenticationKeyID "${KEY_ID}"
  -authenticationKeyIssuerID "${ISSUER_ID}"
)

cd "${IOS_DIR}"
xcodegen generate --quiet

archive="build/release/Ngrams-${version}-${build}.xcarchive"
xcodebuild \
  -project Ngrams.xcodeproj \
  -scheme Ngrams \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath build \
  -archivePath "${archive}" \
  "${auth[@]}" \
  -quiet \
  CURRENT_PROJECT_VERSION="${build}" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "${archive}" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "build/release/export-${build}" \
  "${auth[@]}" \
  -quiet

cd - >/dev/null
git tag "${tag}"
git push --quiet origin "${tag}"
echo "uploaded ${version} (${build}) and tagged ${tag}; it shows up in TestFlight once App Store Connect processes it"
