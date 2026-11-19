#!/usr/bin/env bash
# Finds the projects that generate OpenAPI documents at build time (Microsoft.Extensions.ApiDescription.Server
# sets OpenApiGenerateDocuments) and copies the documents each one generated into OPENAPI_OUTPUT/<project>/.
# Run it after the build: the property comes from the package, so it is only defined once the project is
# restored, and the documents only exist once it is built. Writes has-openapi and count to GITHUB_OUTPUT.
set -euo pipefail

# The generator records the documents it wrote in <project>.OpenApiFiles.cache, so stale documents left in
# obj/ by earlier builds are never picked up.
count=0
while IFS= read -r -d '' project; do
  properties=$(dotnet msbuild "$project" \
    -p:Configuration=Release \
    -nologo \
    -getProperty:OpenApiGenerateDocuments \
    -getProperty:OpenApiDocumentsDirectory \
    -getProperty:_OpenApiDocumentsCache \
    -getProperty:MSBuildProjectName)

  if [[ $(jq -r '.Properties.OpenApiGenerateDocuments | ascii_downcase' <<< "$properties") != 'true' ]]; then
    continue
  fi

  project_dir=$(dirname "$project")
  name=$(jq -r '.Properties.MSBuildProjectName' <<< "$properties")
  # MSBuild reports these relative to the project, with Windows separators.
  documents_dir=$(jq -r '.Properties.OpenApiDocumentsDirectory | gsub("\\\\"; "/")' <<< "$properties")
  cache=$(jq -r '.Properties._OpenApiDocumentsCache | gsub("\\\\"; "/")' <<< "$properties")
  # _OpenApiDocumentsCache is internal to the package; fall back to its documented location.
  [[ -n "$cache" ]] || cache="${documents_dir%/}/$name.OpenApiFiles.cache"
  [[ "$cache" == /* ]] || cache="$project_dir/$cache"

  echo "OpenAPI project: $project"
  if [[ ! -s "$cache" ]]; then
    echo "$project generates OpenAPI documents, but $cache lists none. Was it built?" >&2
    exit 1
  fi

  destination="$OPENAPI_OUTPUT/$name"
  if [[ -e "$destination" ]]; then
    echo "More than one project is named $name; their OpenAPI documents would overwrite each other." >&2
    exit 1
  fi
  mkdir -p "$destination"

  while IFS= read -r document; do
    document=${document%$'\r'}
    [[ -n "$document" ]] || continue
    [[ "$document" == /* ]] || document="$project_dir/$document"
    if [[ ! -f "$document" ]]; then
      echo "OpenAPI document $document listed in $cache does not exist." >&2
      exit 1
    fi
    # Name each document after its OpenAPI document name, as the services' own CollectOpenApiDocuments targets
    # do: the generator writes the default document (v1) as <project>.json and the rest as <project>_<name>.json.
    file=$(basename "$document")
    case "$file" in
      "$name.json") target='v1.json' ;;
      "${name}_"*.json) target=${file#"${name}_"} ;;
      *) target=$file ;;
    esac
    if [[ -e "$destination/$target" ]]; then
      echo "$project generated more than one OpenAPI document named $target." >&2
      exit 1
    fi
    cp "$document" "$destination/$target"
    echo "  $file -> $name/$target"
    count=$((count + 1))
  done < "$cache"
done < <(find . -type d \( -name .git -o -name bin -o -name obj \) -prune \
  -o -type f -name '*.csproj' -print0)

if [[ $count -gt 0 ]]; then
  echo "has-openapi=true" >> "$GITHUB_OUTPUT"
else
  echo "has-openapi=false" >> "$GITHUB_OUTPUT"
fi
echo "count=$count" >> "$GITHUB_OUTPUT"
