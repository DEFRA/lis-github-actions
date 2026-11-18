#!/usr/bin/env bash
# Runs IMAGE with PORT set (published on the same host port) and waits for HEALTH_PATH to answer 2xx.
# SMOKE_ENV adds one KEY=VALUE per line. SMOKE_POSTGRES=true starts a PostgreSQL sidecar
# reachable as host "postgres" with database, user and password "smoke".
set -euo pipefail

case "$SMOKE_POSTGRES" in
  true|false) start_postgres="$SMOKE_POSTGRES" ;;
  *) echo "smoke-postgres must be true or false, not '$SMOKE_POSTGRES'" >&2; exit 1 ;;
esac

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

if [[ "$start_postgres" == 'true' ]]; then
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
  --env "PORT=$PORT" \
  "${env_args[@]}" \
  --publish "$PORT:$PORT" \
  "$IMAGE")

for _ in {1..30}; do
  if curl --fail --silent --show-error "http://localhost:$PORT$HEALTH_PATH" >/dev/null; then
    exit 0
  fi
  sleep 1
done

echo 'Container did not become healthy within 30 seconds.' >&2
exit 1
