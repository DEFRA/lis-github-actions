#!/usr/bin/env bash
# Checks artifacts/provenance.json matches the checked-out commit, PACKAGE_VERSION and BUILD_RUN_ID,
# then waits for the run attempt that uploaded the packages to finish successfully.
set -euo pipefail

tagged_commit=$(git rev-parse HEAD)
jq -e --arg commit "$tagged_commit" \
  --arg version "$PACKAGE_VERSION" --arg run_id "$BUILD_RUN_ID" '
  .commit == $commit and .version == $version and .run_id == $run_id and
  (.run_attempt | test("^[1-9][0-9]*$"))
' artifacts/provenance.json > /dev/null
attempt=$(jq -r '.run_attempt' artifacts/provenance.json)

# Pushing the tag starts this workflow before the tagging run finishes.
# Check the exact attempt that uploaded the artifact, including on reruns.
for _ in {1..60}; do
  run=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$BUILD_RUN_ID/attempts/$attempt")
  if [[ $(jq -r '.status' <<< "$run") == completed ]]; then
    if jq -e '.conclusion == "success"' <<< "$run" > /dev/null; then
      exit 0
    fi
    echo 'The package build workflow did not succeed.' >&2
    exit 1
  fi
  sleep 10
done
echo 'Timed out waiting for package validation to complete.' >&2
exit 1
