#!/usr/bin/env bash
set -euo pipefail

# Build the puzzle bank, passing any further arguments through as flags
# Usage: generate_bank.sh <module_dir> <raw_data_dir> <blocklist_dir> <bank_file> [flags...]

MODULE_DIR="${1:-generator}"
RAW_DIR="$(cd "${2:-data/raw}" && pwd)"
BLOCKLIST_DIR="$(cd "${3:-data/blocklists}" && pwd)"
BANK_FILE="$(cd "$(dirname "${4:-data/bank/puzzles.json}")" && pwd)/$(basename "${4:-data/bank/puzzles.json}")"
shift 4

cd "${MODULE_DIR}"

go run ./cmd/generate -data "${RAW_DIR}" -blocklists "${BLOCKLIST_DIR}" -out "${BANK_FILE}" "$@"
