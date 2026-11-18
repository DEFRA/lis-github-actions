#!/usr/bin/env bash
# Writes has-nuget=true to GITHUB_OUTPUT when any project outside bin/obj is packable.
set -euo pipefail

has_nuget=false
while IFS= read -r -d '' project; do
  is_packable=$(dotnet msbuild "$project" \
    -getProperty:IsPackable \
    -p:Configuration=Release \
    -nologo)
  if [[ "${is_packable,,}" == 'true' ]]; then
    echo "Packable project: $project"
    has_nuget=true
  fi
done < <(find . -type d \( -name .git -o -name bin -o -name obj \) -prune \
  -o -type f -name '*.csproj' -print0)
echo "has-nuget=$has_nuget" >> "$GITHUB_OUTPUT"
