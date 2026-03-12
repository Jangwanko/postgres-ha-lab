#!/usr/bin/env bash
set -euo pipefail

RUNS="${1:-3}"

echo "[RUN] starting PostgreSQL HA stack"
docker compose up -d

echo "[RUN] failover test"
bash ./scripts/failover-test.sh

echo "[RUN] metric measurement"
bash ./scripts/measure-ha-metrics.sh "${RUNS}"

echo "[RUN] completed"
