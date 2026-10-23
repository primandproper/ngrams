#!/usr/bin/env bash
set -euo pipefail

# Run the tiles generator prototype, passing any arguments through as flags
# Usage: tiles_prototype.sh <module_dir> <raw_data_dir> [flags...]

MODULE_DIR="${1:-generator}"
RAW_DIR="$(cd "${2:-data/raw}" && pwd)"
shift 2

cd "${MODULE_DIR}"

go run ./cmd/tiles-prototype -data "${RAW_DIR}" "$@"
