#!/usr/bin/env bash
set -euo pipefail

# Run tests for a Go module, skipping binaries under cmd/
# Usage: test.sh <module_dir>

MODULE_DIR="${1:-generator}"

cd "${MODULE_DIR}"

packages=()
while IFS= read -r pkg; do
  packages+=("${pkg}")
done < <(go list ./... | grep -Ev '/cmd/' || true)

if [ ${#packages[@]} -eq 0 ]; then
  echo "No testable packages in ${MODULE_DIR}"
  exit 0
fi

CGO_ENABLED=1 go test -shuffle=on -race -vet=all -failfast "${packages[@]}"
