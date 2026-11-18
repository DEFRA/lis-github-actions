#!/usr/bin/env bash
# Finds the newest unexpired ARTIFACT_NAME artifact uploaded by a prerelease push or release pull
# request run for the checked-out commit, and writes its artifact-id and run-id to GITHUB_OUTPUT.
set -euo pipefail

tagged_commit=$(git rev-parse HEAD)
artifacts=$(gh api --method GET "repos/$GITHUB_REPOSITORY/actions/artifacts" \
  -f name="$ARTIFACT_NAME" -f per_page=100 --paginate --slurp)
candidates=$(jq -r --arg name "$ARTIFACT_NAME" \
  '[.[].artifacts[] | select(.name == $name and .expired == false)]
   | sort_by(.created_at) | reverse | .[] | [.id, .workflow_run.id] | @tsv' \
  <<< "$artifacts")

while IFS=$'\t' read -r artifact_id run_id; do
  [[ -n "$artifact_id" ]] || continue
  run=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run_id")
  # PR validation also uploads packages; only publish release builds.
  if ! jq -e --arg commit "$tagged_commit" '
    .head_sha == $commit and
    (.status != "completed" or .conclusion == "success") and (
    (.path == ".github/workflows/prerelease.yml" and .event == "push") or
    (.path == ".github/workflows/release.yml" and .event == "pull_request"))
  ' <<< "$run" > /dev/null; then
    continue
  fi
  printf 'artifact-id=%s\nrun-id=%s\n' "$artifact_id" "$run_id" >> "$GITHUB_OUTPUT"
  {
    printf '### Package artifact source\n\n'
    printf "Artifact: \`%s\`\n\n" "$ARTIFACT_NAME"
    printf '[Build run](%s/%s/actions/runs/%s)\n' "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$run_id"
  } | tee -a "$GITHUB_STEP_SUMMARY"
  exit 0
done <<< "$candidates"

echo "No unexpired release artifact named $ARTIFACT_NAME was found. Rebuild the version before publishing." >&2
exit 1
