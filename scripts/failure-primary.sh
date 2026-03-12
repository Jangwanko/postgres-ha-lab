#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ha-common.sh"

primary="$(get_primary)"
if [[ -z "${primary}" ]]; then
  echo "primary not found"
  exit 1
fi

echo "current primary: ${primary}"
docker kill "${primary}" >/dev/null
echo "simulated crash on ${primary}"

new_primary="$(wait_for_primary_change "${primary}" 120 2)" || {
  echo "failover timeout"
  exit 1
}

echo "new primary: ${new_primary}"
wait_for_replica_role "${primary}" 180 2 || {
  echo "old primary did not rejoin"
  exit 1
}

echo "old primary rejoined as replica"
