#!/usr/bin/env bash
set -euo pipefail

# Run shellcheck on all shell scripts
# Usage: shellcheck.sh <container_runner> <shellcheck_image> <scripts_dir>

CONTAINER_RUNNER="${1:-docker}"
SHELLCHECK_IMAGE="${2:-koalaman/shellcheck:stable}"
SCRIPTS_DIR="${3:-scripts}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${CONTAINER_RUNNER}" pull --quiet "${SHELLCHECK_IMAGE}" > /dev/null

shell_scripts=()
while IFS= read -r file; do
  shell_scripts+=("${file#"${PROJECT_ROOT}"/}")
done < <(find "${PROJECT_ROOT}/${SCRIPTS_DIR}" -type f -name "*.sh" | sort)

if [ ${#shell_scripts[@]} -eq 0 ]; then
  echo "No shell scripts found in ${SCRIPTS_DIR}"
  exit 0
fi

"${CONTAINER_RUNNER}" run --rm \
  --volume "${PROJECT_ROOT}:/workdir" \
  --workdir /workdir \
  "${SHELLCHECK_IMAGE}" \
  "${shell_scripts[@]}"

echo "All shell scripts passed shellcheck!"
