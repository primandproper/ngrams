#!/usr/bin/env bash
set -euo pipefail

# Download source word lists and frequency data, pinned to fixed commits
# Usage: fetch_data.sh <raw_data_dir>

RAW_DIR="${1:-data/raw}"

LIBREOFFICE_DICTIONARIES_SHA="67032ee957631908098a72edf48dc81cac27e369"
FREQUENCY_WORDS_SHA="525f9b560de45753a5ea01069454e72e9aa541c6"
DOLPH_DICTIONARY_SHA="233d25a56b9ac8bef906916ccf091a976995cce0"

GITHUB_RAW="https://raw.githubusercontent.com"

fetch() {
  local url="${1}"
  local dest="${2}"

  if [ -s "${dest}" ]; then
    echo "have ${dest}"
    return
  fi

  echo "fetching ${dest}"
  mkdir -p "$(dirname "${dest}")"
  curl --silent --show-error --fail --location --output "${dest}.partial" "${url}"
  mv "${dest}.partial" "${dest}"
}

fetch "${GITHUB_RAW}/dolph/dictionary/${DOLPH_DICTIONARY_SHA}/enable1.txt" "${RAW_DIR}/en/enable1.txt"
fetch "${GITHUB_RAW}/hermitdave/FrequencyWords/${FREQUENCY_WORDS_SHA}/content/2018/en/en_50k.txt" "${RAW_DIR}/en/en_50k.txt"

fetch "${GITHUB_RAW}/LibreOffice/dictionaries/${LIBREOFFICE_DICTIONARIES_SHA}/es/es_MX.aff" "${RAW_DIR}/es/es_MX.aff"
fetch "${GITHUB_RAW}/LibreOffice/dictionaries/${LIBREOFFICE_DICTIONARIES_SHA}/es/es_MX.dic" "${RAW_DIR}/es/es_MX.dic"
fetch "${GITHUB_RAW}/hermitdave/FrequencyWords/${FREQUENCY_WORDS_SHA}/content/2018/es/es_50k.txt" "${RAW_DIR}/es/es_50k.txt"
