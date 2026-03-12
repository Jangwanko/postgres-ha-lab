#!/usr/bin/env bash
set -euo pipefail

DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_NAME="${DB_NAME:-postgres}"
PGPOOL_CONTAINER="${PGPOOL_CONTAINER:-pgpool}"
CLUSTER_NETWORK="${CLUSTER_NETWORK:-pg_ha_net}"
DB_NODES=(pg_node1 pg_node2 pg_node3)
PSQL_BIN="${PSQL_BIN:-/opt/bitnami/postgresql/bin/psql}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-postgres-ha-lab}"

docker_psql() {
  local container="$1"
  local sql="$2"
  docker exec -e "PGPASSWORD=${DB_PASSWORD}" "$container" "${PSQL_BIN}" -h 127.0.0.1 -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "${sql}" 2>/dev/null | tr -d '\r\n'
}

docker_running() {
  local container="$1"
  [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || echo false)" == "true" ]]
}

get_primary() {
  local node
  for node in "${DB_NODES[@]}"; do
    if docker_running "$node"; then
      if [[ "$(docker_psql "$node" "select pg_is_in_recovery();")" == "f" ]]; then
        echo "$node"
        return 0
      fi
    fi
  done
  return 1
}

get_replicas() {
  local node
  for node in "${DB_NODES[@]}"; do
    if docker_running "$node"; then
      if [[ "$(docker_psql "$node" "select pg_is_in_recovery();")" == "t" ]]; then
        echo "$node"
      fi
    fi
  done
}

wait_for_primary_change() {
  local old_primary="$1"
  local timeout="${2:-120}"
  local interval="${3:-2}"
  local elapsed=0
  local candidate=""

  while (( elapsed < timeout )); do
    if candidate="$(get_primary 2>/dev/null)" && [[ -n "$candidate" && "$candidate" != "$old_primary" ]]; then
      echo "$candidate"
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  return 1
}

wait_for_replica_role() {
  local node="$1"
  local timeout="${2:-180}"
  local interval="${3:-2}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if docker_running "$node"; then
      if [[ "$(docker_psql "$node" "select pg_is_in_recovery();")" == "t" ]]; then
        return 0
      fi
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  return 1
}

wait_for_pgpool() {
  local timeout="${1:-120}"
  local interval="${2:-2}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if docker exec "$PGPOOL_CONTAINER" bash -lc ": > /dev/tcp/127.0.0.1/5432" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  return 1
}

service_for_node() {
  case "$1" in
    pg_node1) echo "pg-node-1" ;;
    pg_node2) echo "pg-node-2" ;;
    pg_node3) echo "pg-node-3" ;;
    *) return 1 ;;
  esac
}

volume_for_node() {
  case "$1" in
    pg_node1) echo "${COMPOSE_PROJECT_NAME}_node1_data" ;;
    pg_node2) echo "${COMPOSE_PROJECT_NAME}_node2_data" ;;
    pg_node3) echo "${COMPOSE_PROJECT_NAME}_node3_data" ;;
    *) return 1 ;;
  esac
}
