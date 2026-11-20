#!/usr/bin/env bash
set -euo pipefail

# Build the puzzle bank, passing any further arguments through as flags
# Usage: generate_bank.sh <module_dir> <raw_data_dir> <blocklist_dir> <exclusion_dir> <bank_file> <guess_dir> [flags...]

MODULE_DIR="${1:-generator}"
RAW_DIR="$(cd "${2:-data/raw}" && pwd)"
BLOCKLIST_DIR="$(cd "${3:-data/blocklists}" && pwd)"
EXCLUSION_DIR="$(cd "${4:-data/exclusions}" && pwd)"
BANK_FILE="$(cd "$(dirname "${5:-data/bank/puzzles.json}")" && pwd)/$(basename "${5:-data/bank/puzzles.json}")"
mkdir -p "${6:-data/bank/guesses}"
GUESS_DIR="$(cd "${6:-data/bank/guesses}" && pwd)"
shift 6

cd "${MODULE_DIR}"

go run ./cmd/generate -data "${RAW_DIR}" -blocklists "${BLOCKLIST_DIR}" -exclusions "${EXCLUSION_DIR}" -out "${BANK_FILE}" -guesses "${GUESS_DIR}" "$@"
