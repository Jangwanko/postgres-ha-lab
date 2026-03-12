#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ha-common.sh"

replica="$(get_replicas | head -n 1)"
if [[ -z "${replica}" ]]; then
  echo "replica not found"
  exit 1
fi

echo "current replica: ${replica}"
docker kill "${replica}" >/dev/null
echo "simulated crash on ${replica}"

wait_for_replica_role "${replica}" 180 2 || {
  echo "replica did not return to recovery mode"
  exit 1
}

echo "replica recovered and rejoined"
