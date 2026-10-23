#!/usr/bin/env bash
set -euo pipefail

# Lint a Go module using golangci-lint in a container
# Usage: golang_lint.sh <container_runner> <linter_image> <module_dir>

CONTAINER_RUNNER="${1:-docker}"
LINTER_IMAGE="${2:-golangci/golangci-lint:v2.14.0}"
MODULE_DIR="${3:-generator}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${CONTAINER_RUNNER}" pull --quiet "${LINTER_IMAGE}" > /dev/null
"${CONTAINER_RUNNER}" run --rm \
  --volume "${PROJECT_ROOT}:${PROJECT_ROOT}" \
  --workdir "${PROJECT_ROOT}/${MODULE_DIR}" \
  "${LINTER_IMAGE}" \
  golangci-lint run --config=.golangci.yml --timeout 30m ./...
