#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-apache-age}"
DB_NAME="${DB_NAME:-hybrid_aml}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"

fail() {
    echo "Smoke test failed: $1" >&2
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "missing required command: $1"
    fi
}

psql_scalar() {
    local sql="$1"
    docker exec -i "$CONTAINER_NAME" \
        psql -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB_NAME" \
        <<<"$sql"
}

query_file_row_count() {
    local sql_file="$1"
    local output

    output="$(
        docker exec -i -w "$WORKSPACE_DIR" "$CONTAINER_NAME" \
            psql -qAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB_NAME" \
            -f "$sql_file"
    )"

    printf "%s\n" "$output" \
        | sed '/^[[:space:]]*$/d;/^LOAD$/d;/^SET$/d' \
        | wc -l \
        | tr -d ' '
}

assert_equals() {
    local label="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" != "$expected" ]]; then
        fail "$label expected $expected, got $actual"
    fi

    printf "ok: %s = %s\n" "$label" "$actual"
}

require_command docker

if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    fail "container '$CONTAINER_NAME' is not running; run ./scripts/reset_pipeline.sh first"
fi

assert_equals "customers rows" "324" "$(psql_scalar "SELECT COUNT(*) FROM customers;")"
assert_equals "accounts rows" "369" "$(psql_scalar "SELECT COUNT(*) FROM accounts;")"
assert_equals "transactions rows" "1896" "$(psql_scalar "SELECT COUNT(*) FROM transactions;")"

assert_equals "smurfing SQL detections" "9" "$(query_file_row_count "database/queries/smurfing_detection.sql")"
assert_equals "smurfing AGE detections" "9" "$(query_file_row_count "database/queries/smurfing_detection_age.sql")"
assert_equals "cycle recursive SQL detections" "9" "$(query_file_row_count "database/queries/circular_trading_recursive.sql")"
assert_equals "cycle baseline AGE detections" "9" "$(query_file_row_count "database/queries/circular_trading_cypher.sql")"
assert_equals "cycle tuned AGE detections" "9" "$(query_file_row_count "database/queries/circular_trading_cypher_tuned.sql")"

echo "Smoke test passed."
