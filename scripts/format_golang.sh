#!/usr/bin/env bash
set -euo pipefail

# Format a Go module: go fix, goimports, field and tag alignment, gofmt
# Usage: format_golang.sh <module_dir>

MODULE_DIR="${1:-generator}"

cd "${MODULE_DIR}"

go fix ./...
go tool goimports -w .

until go tool fieldalignment -fix ./...; do
  true
done > /dev/null

until go tool tagalign -fix -sort -order "env,envDefault,envPrefix,json,mapstructure,toml,yaml" ./...; do
  true
done > /dev/null

while IFS= read -r -d '' file; do
  gofmt -s -w "${file}"
done < <(find . -type f -not -path '*/vendor/*' -name "*.go" -print0)
