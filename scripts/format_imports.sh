#!/usr/bin/env bash
set -euo pipefail

# Format Go imports using gci
# Usage: format_imports.sh <module_dir> <package_prefix>

MODULE_DIR="${1:-generator}"
PACKAGE_PREFIX="${2:-github.com/primandproper/ngrams/generator}"

cd "${MODULE_DIR}"

go_files=()
while IFS= read -r -d '' file; do
  go_files+=("${file}")
done < <(find . -type f -not -path '*/vendor/*' -name "*.go" -print0)

if [ ${#go_files[@]} -gt 0 ]; then
  go tool gci write \
    --section standard \
    --section "prefix(${PACKAGE_PREFIX})" \
    --section "prefix(github.com/primandproper)" \
    --section default \
    --custom-order \
    "${go_files[@]}"
fi
