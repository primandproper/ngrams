#!/usr/bin/env bash
set -euo pipefail

# Run the tiles generator prototype, passing any arguments through as flags
# Usage: tiles_prototype.sh <module_dir> <raw_data_dir> <blocklist_dir> [flags...]

MODULE_DIR="${1:-generator}"
RAW_DIR="$(cd "${2:-data/raw}" && pwd)"
BLOCKLIST_DIR="$(cd "${3:-data/blocklists}" && pwd)"
shift 3

cd "${MODULE_DIR}"

go run ./cmd/tiles-prototype -data "${RAW_DIR}" -blocklists "${BLOCKLIST_DIR}" "$@"
