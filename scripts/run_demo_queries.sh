#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTAINER_NAME="${CONTAINER_NAME:-apache-age}"
DB_NAME="${DB_NAME:-hybrid_aml}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
WARM_CACHE="${WARM_CACHE:-1}"
CYCLE_GRAPH_VARIANT="${CYCLE_GRAPH_VARIANT:-baseline}"
EXPANDED_OUTPUT="${EXPANDED_OUTPUT:-1}"

log() {
    printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$1"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

ensure_docker_ready() {
    if ! docker info >/dev/null 2>&1; then
        echo "Docker Desktop does not appear to be running." >&2
        exit 1
    fi

    if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
        echo "Container '$CONTAINER_NAME' is not running." >&2
        echo "Run ./scripts/reset_pipeline.sh first." >&2
        exit 1
    fi
}

psql_exec_file() {
    local sql_file="$1"
    docker exec -i -w "$WORKSPACE_DIR" "$CONTAINER_NAME" \
        psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB_NAME" \
        < "$ROOT/$sql_file"
}

run_visible_query() {
    local label="$1"
    local sql_file="$2"
    local note="$3"
    local output
    local row_count
    local elapsed_ms

    log "$label"
    printf "SQL file: %s\n" "$sql_file"
    printf "Note: %s\n" "$note"

    if [[ "$WARM_CACHE" == "1" ]]; then
        printf "Warm-up: running once without printing results...\n"
        psql_exec_file "$sql_file" >/dev/null
    fi

    local expanded_cmd="\\x off"
    if [[ "$EXPANDED_OUTPUT" == "1" ]]; then
        expanded_cmd="\\x on"
    fi

    output="$(
        docker exec -i -w "$WORKSPACE_DIR" "$CONTAINER_NAME" \
            psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB_NAME" <<SQL
\pset pager off
\pset linestyle unicode
\pset border 2
\pset null '(null)'
\echo === Detection rows for: $label ===
$expanded_cmd
\timing on
\i $sql_file
SQL
    )"

    printf "%s\n" "$output"

    row_count="$(
        printf "%s\n" "$output" \
            | sed -nE 's/^[[:space:]]*\(([0-9]+) rows?\)[[:space:]]*$/\1/p' \
            | tail -1
    )"
    if [[ -z "$row_count" && "$EXPANDED_OUTPUT" == "1" ]]; then
        row_count="$(
            printf "%s\n" "$output" \
                | grep -c '\[ RECORD '
        )"
    fi
    elapsed_ms="$(
        printf "%s\n" "$output" \
            | sed -nE 's/^Time: ([0-9.]+) ms$/\1/p' \
            | tail -1
    )"

    printf "\nSummary: "
    if [[ -n "$row_count" ]]; then
        printf "%s detections" "$row_count"
    else
        printf "row count not parsed"
    fi

    if [[ -n "$elapsed_ms" ]]; then
        printf " | visible run time %s ms" "$elapsed_ms"
    else
        printf " | visible run time not parsed"
    fi
    printf "\n"
}

require_command docker
ensure_docker_ready

case "$CYCLE_GRAPH_VARIANT" in
    baseline)
        cycle_graph_sql="database/queries/circular_trading_cypher.sql"
        cycle_graph_note="Uses the baseline all-transfer graph on aml_graph."
        ;;
    tuned)
        cycle_graph_sql="database/queries/circular_trading_cypher_tuned.sql"
        cycle_graph_note="Uses the tuned transfer-only graph on aml_graph_tuned."
        ;;
    *)
        echo "Unsupported CYCLE_GRAPH_VARIANT: $CYCLE_GRAPH_VARIANT" >&2
        echo "Use CYCLE_GRAPH_VARIANT=baseline or CYCLE_GRAPH_VARIANT=tuned." >&2
        exit 1
        ;;
esac

cat <<EOF
Hybrid AML demo query runner
- WARM_CACHE=$WARM_CACHE
- CYCLE_GRAPH_VARIANT=$CYCLE_GRAPH_VARIANT
- EXPANDED_OUTPUT=$EXPANDED_OUTPUT

Slide alignment:
- Smurfing AGE uses baseline aml_graph via smurfing_detection_age.sql
- Circular AGE uses $cycle_graph_sql

Note:
- The slide medians come from 20 warm-cache EXPLAIN ANALYZE runs.
- This script shows the actual detected rows plus one warmed visible run time for live demo use.
EOF

run_visible_query \
    "1. Smurfing detection - PostgreSQL SQL" \
    "database/queries/smurfing_detection.sql" \
    "Typed relational path on public.transactions."

run_visible_query \
    "2. Smurfing detection - Apache AGE" \
    "database/queries/smurfing_detection_age.sql" \
    "Baseline graph path on aml_graph."

run_visible_query \
    "3. Circular trading detection - Recursive SQL" \
    "database/queries/circular_trading_recursive.sql" \
    "Bounded 3-hop recursive SQL path."

run_visible_query \
    "4. Circular trading detection - Apache AGE" \
    "$cycle_graph_sql" \
    "$cycle_graph_note"
