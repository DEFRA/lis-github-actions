#!/usr/bin/env bash
# Runs IMAGE with ASPNETCORE_URLS on PORT (published on 3101) and waits for /health to answer.
# SMOKE_ENV adds one KEY=VALUE per line; SMOKE_POSTGRES=true starts a PostgreSQL sidecar
# reachable as host "postgres" with database, user and password "smoke".
set -euo pipefail

network="$(uuidgen)"
database=''
container=''

# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap
cleanup() {
  if [[ -n "$container" ]]; then
    docker logs "$container" || true
    docker rm --force "$container" || true
  fi
  if [[ -n "$database" ]]; then
    docker logs "$database" || true
    docker rm --force "$database" || true
  fi
  docker network rm "$network" || true
}
trap cleanup EXIT

docker network create "$network"

if [[ "$SMOKE_POSTGRES" == 'true' ]]; then
  database=$(docker run \
    --detach \
    --network "$network" \
    --network-alias postgres \
    --env POSTGRES_DB=smoke \
    --env POSTGRES_USER=smoke \
    --env POSTGRES_PASSWORD=smoke \
    postgres:16-alpine)

  for attempt in {1..30}; do
    if docker exec "$database" pg_isready --username smoke --dbname smoke >/dev/null; then
      break
    fi
    if [[ "$attempt" -eq 30 ]]; then
      echo 'PostgreSQL did not become ready within 30 seconds.' >&2
      exit 1
    fi
    sleep 1
  done
fi

env_args=()
while IFS= read -r line; do
  [[ -n "$line" ]] && env_args+=(--env "$line")
done <<< "$SMOKE_ENV"

container=$(docker run \
  --detach \
  --network "$network" \
  --env "ASPNETCORE_URLS=http://+:$PORT" \
  "${env_args[@]}" \
  --publish "3101:$PORT" \
  "$IMAGE")

for _ in {1..30}; do
  if curl --fail --silent --show-error "http://localhost:3101/health" >/dev/null; then
    exit 0
  fi
  sleep 1
done

echo 'Container did not become healthy within 30 seconds.' >&2
exit 1
