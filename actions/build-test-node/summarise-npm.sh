#!/usr/bin/env bash
# Prints a Markdown summary of the npm packages in PACKAGE_DIR for the step summary.
# Reads PACKAGE_DIR, PACKAGE_VERSION, SOURCE_REF, ARTIFACT and ARTIFACT_URL from the environment.
set -euo pipefail

printf '### npm packages\n\n```text\n'
printf 'Requested version: %s\n' "$PACKAGE_VERSION"
printf 'Source ref: %s\n' "${SOURCE_REF:-(workspace checkout)}"
printf 'Commit: %s\n' "$(git rev-parse HEAD)"
printf 'Artifact: %s\n' "$ARTIFACT"
for package in "$PACKAGE_DIR"/*.tgz; do
  size=$(stat --format '%s' "$package")
  printf '\nPackage: %s (%s bytes)\n' "$(basename "$package")" "$size"
  tar -xOf "$package" package/package.json \
    | jq -r '"  name: \(.name)\n  version: \(.version)\n  keywords: \((.keywords // []) | if length == 0 then "(none)" else join(", ") end)"'
done
printf '```\n\n'
printf '[Download workflow artifact](%s)\n' "$ARTIFACT_URL"
