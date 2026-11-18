#!/usr/bin/env bash
# Builds and tests the solution with coverage between dotnet-sonarscanner begin and end.
# Reads SONAR_TOKEN, PROJECT_KEY, PROJECT_VERSION, BRANCH (empty for pull request analysis)
# and EXCLUSIONS.
set -euo pipefail

branch_args=()
if [[ -n "$BRANCH" ]]; then
  branch_args+=("/d:sonar.branch.name=$BRANCH")
fi

./.sonar/scanner/dotnet-sonarscanner begin \
  /k:"$PROJECT_KEY" \
  /o:"defra" \
  /v:"$PROJECT_VERSION" \
  /d:sonar.token="$SONAR_TOKEN" \
  /d:sonar.host.url="https://sonarcloud.io" \
  /d:sonar.cs.vscoveragexml.reportsPaths="coverage/**/coverage.xml" \
  /d:sonar.exclusions="$EXCLUSIONS" \
  "${branch_args[@]}"

dotnet build --no-incremental

dotnet test \
  --no-build \
  --coverage --coverage-output-format xml --coverage-output coverage.xml --report-trx \
  --results-directory coverage

./.sonar/scanner/dotnet-sonarscanner end /d:sonar.token="$SONAR_TOKEN"
