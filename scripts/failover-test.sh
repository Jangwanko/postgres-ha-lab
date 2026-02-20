#!/usr/bin/env bash
set -euo pipefail

# 종단 간 HA 검증:
# 1) primary 중지
# 2) replica 승격 확인
# 3) primary 자동 재기동 + follower 재조인 확인

echo "[TEST] stopping pg_primary..."
docker stop pg_primary >/dev/null

echo "[TEST] waiting for replica promotion..."
ok=0
for _ in $(seq 1 60); do
  state="$(docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]' || true)"
  leader="$(tr -d '\r\n' < cluster-state/current_primary 2>/dev/null || true)"
  if [[ "$state" == "f" && "$leader" == "replica" ]]; then
    ok=1
    break
  fi
  sleep 2
done

if [[ "$ok" -ne 1 ]]; then
  echo "[TEST] failover did not complete in time"
  exit 1
fi

echo "[TEST] waiting for primary auto-restart and follower rejoin..."
ok=0
for _ in $(seq 1 90); do
  state="$(docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]' || true)"
  leader="$(tr -d '\r\n' < cluster-state/current_primary 2>/dev/null || true)"
  if [[ "$state" == "t" && "$leader" == "replica" ]]; then
    ok=1
    break
  fi
  sleep 2
done

if [[ "$ok" -ne 1 ]]; then
  echo "[TEST] failback did not complete in time"
  exit 1
fi

echo "[TEST] success"
