#!/usr/bin/env bash
# Validates the Liquibase changelog and applies it to a throwaway PostgreSQL container.
# Reads LIQUIBASE_CHANGELOG (path of the changelog; liquibase.properties sits beside it),
# LIQUIBASE_DATABASE and LIQUIBASE_HOME (the Liquibase install).
set -euo pipefail

changelog_dir=$(dirname "$LIQUIBASE_CHANGELOG")
changelog_file=$(basename "$LIQUIBASE_CHANGELOG")
properties_file="$changelog_dir/liquibase.properties"

if [[ ! -f "$properties_file" ]]; then
  echo "Properties file not found: $properties_file" >&2
  exit 1
fi

# The database user must match the one the changelog's properties connect as.
username=$(sed -nE 's/^[[:space:]]*liquibase\.command\.username[[:space:]]*[:=][[:space:]]*//p' "$properties_file" \
  | head -n 1 | tr -d '\r' | sed -E 's/[[:space:]]+$//')
if [[ -z "$username" ]]; then
  echo "Property 'liquibase.command.username' not found in $properties_file" >&2
  exit 1
fi
echo "Found liquibase.command.username: $username"

# Throwaway credentials for a container that only lives for this step.
password=postgres
database=''

# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap
cleanup() {
  if [[ -n "$database" ]]; then
    docker logs "$database" || true
    docker rm --force "$database" || true
  fi
}
trap cleanup EXIT

# Publish on a free loopback port chosen by Docker; no volume, so every run starts empty.
database=$(docker run \
  --detach \
  --publish '127.0.0.1::5432' \
  --env "POSTGRES_USER=$username" \
  --env "POSTGRES_PASSWORD=$password" \
  --env "POSTGRES_DB=$LIQUIBASE_DATABASE" \
  postgres:16-alpine)
port=$(docker port "$database" 5432/tcp | head -n 1 | sed -E 's/.*:([0-9]+)$/\1/')
echo "PostgreSQL listening on 127.0.0.1:$port"

# The image restarts PostgreSQL after initialisation, so check over TCP rather than the socket.
for attempt in {1..30}; do
  if docker exec "$database" pg_isready --host 127.0.0.1 --username "$username" --dbname "$LIQUIBASE_DATABASE" >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    echo 'PostgreSQL did not become ready within 30 seconds.' >&2
    exit 1
  fi
  sleep 1
done

# Pass the password through the environment so it stays out of the process list.
export LIQUIBASE_COMMAND_PASSWORD="$password"
liquibase_args=(
  --defaults-file="$properties_file"
  --search-path="$changelog_dir"
  --changelog-file="$changelog_file"
  --url="jdbc:postgresql://127.0.0.1:$port/$LIQUIBASE_DATABASE"
)

echo 'Validating the changelog'
"$LIQUIBASE_HOME/liquibase" "${liquibase_args[@]}" validate

echo 'Applying the changelog'
"$LIQUIBASE_HOME/liquibase" "${liquibase_args[@]}" update
