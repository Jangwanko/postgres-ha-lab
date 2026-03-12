#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ha-common.sh"

TARGET_NODE="${1:?usage: rejoin-node.sh <pg_node1|pg_node2|pg_node3>}"
SERVICE_NAME="$(service_for_node "${TARGET_NODE}")"
VOLUME_NAME="$(volume_for_node "${TARGET_NODE}")"

current_primary="$(get_primary || true)"
if [[ -n "${current_primary}" && "${current_primary}" == "${TARGET_NODE}" ]]; then
  echo "target node is current primary"
  exit 1
fi

echo "[REJOIN] target node: ${TARGET_NODE}"
echo "[REJOIN] service: ${SERVICE_NAME}"
echo "[REJOIN] removing old data volume: ${VOLUME_NAME}"

docker stop "${TARGET_NODE}" >/dev/null 2>&1 || true
docker rm -f "${TARGET_NODE}" >/dev/null 2>&1 || true
docker volume rm "${VOLUME_NAME}" >/dev/null 2>&1 || true

override_var=""
case "${TARGET_NODE}" in
  pg_node1) override_var="REPMGR_PRIMARY_HOST_NODE1" ;;
  pg_node2) override_var="REPMGR_PRIMARY_HOST_NODE2" ;;
  pg_node3) override_var="REPMGR_PRIMARY_HOST_NODE3" ;;
esac

if [[ -n "${current_primary}" && -n "${override_var}" ]]; then
  env "${override_var}=$(service_for_node "${current_primary}")" docker compose up -d "${SERVICE_NAME}" >/dev/null
else
  docker compose up -d "${SERVICE_NAME}" >/dev/null
fi

wait_for_replica_role "${TARGET_NODE}" 240 2 || {
  echo "[REJOIN] node did not return as replica"
  exit 1
}

echo "[REJOIN] node rejoined as replica"
