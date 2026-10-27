#!/usr/bin/env bash
set -euo pipefail

# Fail when the iOS app has text with no Spanish translation. Exports the strings the compiler
# finds in the code, merged with Localizable.xcstrings, and lists any left untranslated.
# Usage: lint_strings_ios.sh <ios_dir>

IOS_DIR="${1:-ios}"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

cd "${IOS_DIR}"
xcodegen generate --quiet
xcodebuild -exportLocalizations \
  -project Ngrams.xcodeproj \
  -scheme Ngrams \
  -sdk iphonesimulator \
  -exportLanguage es \
  -localizationPath "${work_dir}" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO >"${work_dir}/export.log" 2>&1 || {
  cat "${work_dir}/export.log"
  exit 1
}

# InfoPlist.xcstrings is generated on export and holds only the app's name, which stays as is.
python3 - "${work_dir}/es.xcloc/Localized Contents/es.xliff" <<'PY'
import sys
import xml.etree.ElementTree as ET

ns = "{urn:oasis:names:tc:xliff:document:1.2}"
missing = []
for file in ET.parse(sys.argv[1]).getroot().iter(ns + "file"):
    if "InfoPlist" in file.get("original", ""):
        continue
    for unit in file.iter(ns + "trans-unit"):
        target = unit.find(ns + "target")
        if unit.get("translate") != "no" and (target is None or not (target.text or "").strip()):
            missing.append(unit.get("id"))
if missing:
    print("strings with no Spanish in ios/Ngrams/Localizable.xcstrings:")
    for key in missing:
        print(f"  {key}")
    sys.exit(1)
PY
