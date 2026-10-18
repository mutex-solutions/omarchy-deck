#!/usr/bin/env bash
# Validate this plugin without Omarchy installed. Same checks the CI workflow
# runs; run it locally with: bash scripts/validate.sh
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

test -f manifest.json || { echo "missing manifest.json" >&2; exit 1; }
jq -e '.schemaVersion == 1' manifest.json >/dev/null || { echo "schemaVersion must be 1" >&2; exit 1; }
for field in id name version kinds entryPoints; do
  jq -e "has(\"$field\")" manifest.json >/dev/null || { echo "manifest missing '$field'" >&2; exit 1; }
done
id=$(jq -r .id manifest.json)
case "$id" in omarchy.*) echo "id '$id' uses the reserved omarchy.* namespace" >&2; exit 1;; esac
test -f README.md || { echo "missing README.md" >&2; exit 1; }
test -f LICENSE || { echo "missing LICENSE" >&2; exit 1; }
while read -r ep; do
  test -f "$ep" || { echo "missing entry point: $ep" >&2; exit 1; }
done < <(jq -r '.entryPoints[]' manifest.json)

# Deck sections, when present, must provide the section and the page.
if [ -d deck ]; then
  test -f deck/Section.qml || { echo "deck/Section.qml missing" >&2; exit 1; }
  test -f deck/Page.qml || { echo "deck/Page.qml missing" >&2; exit 1; }
fi

echo "validate ok: $id"
