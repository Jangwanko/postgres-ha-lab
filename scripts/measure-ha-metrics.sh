#!/usr/bin/env bash
set -euo pipefail

# 운영 지표 측정 스크립트
# - RTO(승격 완료까지 시간)
# - 복구 시간(기존 primary follower 재조인)
# - 성공률

RUNS="${1:-5}"
REPORT_DIR="reports"
mkdir -p "$REPORT_DIR"

total_rto=0
total_rejoin=0
success=0

results_json="["

for i in $(seq 1 "$RUNS"); do
  echo "[METRIC] run $i/$RUNS"

  # 클린 시작
  docker compose up -d >/dev/null
  sleep 2

  start_ts="$(date +%s)"
  docker stop pg_primary >/dev/null

  # 승격 완료 대기
  promoted=0
  promo_end=0
  for _ in $(seq 1 90); do
    state="$(docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]' || true)"
    leader="$(tr -d '\r\n' < cluster-state/current_primary 2>/dev/null || true)"
    if [[ "$state" == "f" && "$leader" == "replica" ]]; then
      promoted=1
      promo_end="$(date +%s)"
      break
    fi
    sleep 1
  done

  # 기존 primary 재조인 대기
  rejoined=0
  rejoin_end=0
  if [[ "$promoted" -eq 1 ]]; then
    for _ in $(seq 1 180); do
      state="$(docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>/dev/null | tr -d '[:space:]' || true)"
      if [[ "$state" == "t" ]]; then
        rejoined=1
        rejoin_end="$(date +%s)"
        break
      fi
      sleep 1
    done
  fi

  rto=-1
  rejoin=-1
  ok=false
  if [[ "$promoted" -eq 1 ]]; then
    rto=$((promo_end - start_ts))
  fi
  if [[ "$rejoined" -eq 1 ]]; then
    rejoin=$((rejoin_end - promo_end))
    ok=true
    success=$((success + 1))
    total_rto=$((total_rto + rto))
    total_rejoin=$((total_rejoin + rejoin))
  fi

  results_json+="{\"run\":$i,\"rto_seconds\":$rto,\"rejoin_seconds\":$rejoin,\"success\":$ok},"
done

results_json="${results_json%,}]"

success_rate="$(awk "BEGIN { printf \"%.2f\", ($success/$RUNS)*100 }")"
avg_rto=0
avg_rejoin=0
if [[ "$success" -gt 0 ]]; then
  avg_rto="$(awk "BEGIN { printf \"%.2f\", $total_rto/$success }")"
  avg_rejoin="$(awk "BEGIN { printf \"%.2f\", $total_rejoin/$success }")"
fi

cat > "$REPORT_DIR/ha-metrics.json" <<JSON
{
  "runs": $RUNS,
  "success_count": $success,
  "success_rate_percent": $success_rate,
  "avg_rto_seconds": $avg_rto,
  "avg_rejoin_seconds": $avg_rejoin,
  "results": $results_json
}
JSON

cat > "$REPORT_DIR/ha-metrics.md" <<MD
# HA 운영 지표 측정 결과

- 측정 횟수: $RUNS
- 성공 횟수: $success
- 복구 성공률: ${success_rate}%
- 평균 RTO(승격 완료): ${avg_rto}초
- 평균 재조인 시간(old primary follower 복귀): ${avg_rejoin}초

원본 데이터: \`reports/ha-metrics.json\`
MD

echo "[METRIC] done: reports/ha-metrics.json, reports/ha-metrics.md"
