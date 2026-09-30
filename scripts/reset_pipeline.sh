#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_NAME="${IMAGE_NAME:-apache/age:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-apache-age}"
DB_NAME="${DB_NAME:-hybrid_aml}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
HOST_PORT="${HOST_PORT:-5455}"
DB_VOLUME="${DB_VOLUME:-age_pg18data}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
RESET_DB_VOLUME="${RESET_DB_VOLUME:-0}"

log() {
    printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$1"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

run_psql_file() {
    local sql_file="$1"
    docker exec -i -w "$WORKSPACE_DIR" "$CONTAINER_NAME" \
        psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB_NAME" \
        < "$ROOT/$sql_file"
}

wait_for_postgres() {
    local retries=60
    local sleep_seconds=2

    for ((attempt = 1; attempt <= retries; attempt++)); do
        if docker exec "$CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$sleep_seconds"
    done

    echo "PostgreSQL inside container '$CONTAINER_NAME' did not become ready in time." >&2
    docker logs "$CONTAINER_NAME" >&2 || true
    exit 1
}

require_command docker
require_command python3

if ! docker info >/dev/null 2>&1; then
    echo "Docker Desktop does not appear to be running." >&2
    exit 1
fi

log "Using repo root: $ROOT"

log "Pulling Apache AGE image"
docker pull "$IMAGE_NAME"

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    log "Removing existing container: $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

if docker ps --format '{{.Ports}}' | grep -Eq "(0.0.0.0:|127.0.0.1:|\\[::\\]:)$HOST_PORT->"; then
    echo "Host port $HOST_PORT is already in use by a running Docker container." >&2
    echo "Set HOST_PORT to a free port, for example: HOST_PORT=5456 ./scripts/reset_pipeline.sh" >&2
    exit 1
fi

if [[ "$RESET_DB_VOLUME" == "1" ]] && docker volume inspect "$DB_VOLUME" >/dev/null 2>&1; then
    log "Removing existing database volume: $DB_VOLUME"
    docker volume rm -f "$DB_VOLUME" >/dev/null
fi

log "Starting AGE-enabled PostgreSQL container"
docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$HOST_PORT":5432 \
    -e POSTGRES_USER="$POSTGRES_USER" \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    -e POSTGRES_DB="$DB_NAME" \
    -v "$DB_VOLUME":/var/lib/postgresql \
    -v "$ROOT":"$WORKSPACE_DIR" \
    "$IMAGE_NAME" >/dev/null

log "Waiting for PostgreSQL to become ready"
wait_for_postgres

log "Generating synthetic CSV data"
python3 "$ROOT/src/data_generation/generate_synthetic_data.py"

log "Creating relational schema"
run_psql_file "database/migrations/001_schema.sql"

log "Loading CSV data into PostgreSQL"
run_psql_file "database/seeds/load_from_csv.sql"

log "Enabling Apache AGE extension"
run_psql_file "database/setup_age.sql"

log "Building baseline AGE graph"
run_psql_file "database/seeds/load_age_graph.sql"

log "Building tuned AGE graph"
run_psql_file "database/seeds/load_age_graph_tuned.sql"

log "Verifying row counts"
docker exec -i "$CONTAINER_NAME" \
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB_NAME" <<'SQL'
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'accounts' AS table_name, COUNT(*) AS row_count FROM accounts
UNION ALL
SELECT 'transactions' AS table_name, COUNT(*) AS row_count FROM transactions
ORDER BY table_name;
SQL

log "Pipeline complete"
echo "Container: $CONTAINER_NAME"
echo "Database:  $DB_NAME"
echo "Port:      $HOST_PORT"
echo
echo "Tip: for a fully clean DB cluster next time, run:"
echo "  RESET_DB_VOLUME=1 ./scripts/reset_pipeline.sh"
