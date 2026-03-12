#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ha-common.sh"

primary="$(get_primary)"
if [[ -z "${primary}" ]]; then
  echo "primary not found"
  exit 1
fi

echo "disconnecting ${primary} from ${CLUSTER_NETWORK}"
docker network disconnect "${CLUSTER_NETWORK}" "${primary}" >/dev/null

new_primary=""
cleanup() {
  docker network connect "${CLUSTER_NETWORK}" "${primary}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

new_primary="$(wait_for_primary_change "${primary}" 120 2)" || {
  echo "failover timeout during network partition"
  exit 1
}

echo "new primary after partition: ${new_primary}"
cleanup
trap - EXIT

wait_for_replica_role "${primary}" 180 2 || {
  echo "isolated node did not rejoin as replica"
  exit 1
}

echo "network partition recovered"
