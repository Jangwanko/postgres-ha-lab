#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ha-common.sh"

echo "[TEST] waiting for Pgpool endpoint..."
wait_for_pgpool

old_primary="$(get_primary)"
if [[ -z "${old_primary}" ]]; then
  echo "[TEST] current primary not found"
  exit 1
fi

echo "[TEST] current primary: ${old_primary}"
echo "[TEST] simulating primary crash..."
docker kill "${old_primary}" >/dev/null

echo "[TEST] waiting for automatic failover..."
new_primary="$(wait_for_primary_change "${old_primary}" 120 2)" || {
  echo "[TEST] no new primary elected within timeout"
  exit 1
}

echo "[TEST] new primary elected: ${new_primary}"
echo "[TEST] running controlled rejoin for old primary..."
bash "${SCRIPT_DIR}/rejoin-node.sh" "${old_primary}" >/dev/null

echo "[TEST] waiting for old primary to rejoin as replica..."
wait_for_replica_role "${old_primary}" 240 2 || {
  echo "[TEST] old primary did not return as replica after rejoin"
  exit 1
}

wait_for_pgpool

echo "[TEST] cluster recovered successfully"
echo "[TEST] old primary: ${old_primary}"
echo "[TEST] new primary: ${new_primary}"
