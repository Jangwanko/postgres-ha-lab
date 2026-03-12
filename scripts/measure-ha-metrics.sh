#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ha-common.sh"

RUNS="${1:-5}"
REPORT_DIR="reports"

mkdir -p "${REPORT_DIR}"

total_rto_ms=0
total_rejoin_ms=0
success=0
results_json="["

for i in $(seq 1 "${RUNS}"); do
  echo "[METRIC] run ${i}/${RUNS}"

  docker compose up -d >/dev/null
  wait_for_pgpool

  old_primary="$(get_primary)"
  if [[ -z "${old_primary}" ]]; then
    echo "[METRIC] primary detection failed"
    exit 1
  fi

  start_ms="$(date +%s%3N)"
  docker kill "${old_primary}" >/dev/null

  promoted=false
  rejoined=false
  promo_ms=0
  end_ms=0

  if new_primary="$(wait_for_primary_change "${old_primary}" 120 1)"; then
    promoted=true
    promo_ms="$(date +%s%3N)"
  else
    new_primary=""
  fi

  if [[ "${promoted}" == true ]]; then
    bash "${SCRIPT_DIR}/rejoin-node.sh" "${old_primary}" >/dev/null
    if wait_for_replica_role "${old_primary}" 240 1; then
      rejoined=true
      end_ms="$(date +%s%3N)"
    fi
  fi

  rto_ms=-1
  rejoin_ms=-1
  ok=false
  if [[ "${promoted}" == true ]]; then
    rto_ms=$((promo_ms - start_ms))
  fi
  if [[ "${rejoined}" == true ]]; then
    rejoin_ms=$((end_ms - promo_ms))
    ok=true
    success=$((success + 1))
    total_rto_ms=$((total_rto_ms + rto_ms))
    total_rejoin_ms=$((total_rejoin_ms + rejoin_ms))
  fi

  results_json+="{\"run\":${i},\"failed_node\":\"${old_primary}\",\"promoted_node\":\"${new_primary}\",\"rto_ms\":${rto_ms},\"rejoin_ms\":${rejoin_ms},\"success\":${ok}},"
done

results_json="${results_json%,}]"

success_rate="$(awk "BEGIN { printf \"%.2f\", (${success}/${RUNS})*100 }")"
avg_rto_ms=0
avg_rejoin_ms=0
avg_rto_sec=0
avg_rejoin_sec=0
if [[ "${success}" -gt 0 ]]; then
  avg_rto_ms="$(awk "BEGIN { printf \"%.2f\", ${total_rto_ms}/${success} }")"
  avg_rejoin_ms="$(awk "BEGIN { printf \"%.2f\", ${total_rejoin_ms}/${success} }")"
  avg_rto_sec="$(awk "BEGIN { printf \"%.3f\", ${avg_rto_ms}/1000 }")"
  avg_rejoin_sec="$(awk "BEGIN { printf \"%.3f\", ${avg_rejoin_ms}/1000 }")"
fi

cat > "${REPORT_DIR}/ha-metrics.json" <<JSON
{
  "runs": ${RUNS},
  "success_count": ${success},
  "success_rate_percent": ${success_rate},
  "avg_rto_ms": ${avg_rto_ms},
  "avg_rto_seconds": ${avg_rto_sec},
  "avg_rejoin_ms": ${avg_rejoin_ms},
  "avg_rejoin_seconds": ${avg_rejoin_sec},
  "results": ${results_json}
}
JSON

cat > "${REPORT_DIR}/ha-metrics.md" <<MD
# PostgreSQL HA 측정 결과

- 측정 횟수: ${RUNS}
- 성공 횟수: ${success}
- 복구 성공률: ${success_rate}%
- 평균 RTO: ${avg_rto_ms}ms (${avg_rto_sec}초)
- 평균 재조인 시간: ${avg_rejoin_ms}ms (${avg_rejoin_sec}초)

상세 결과는 \`reports/ha-metrics.json\`에 저장됩니다.
MD

echo "[METRIC] done: reports/ha-metrics.json, reports/ha-metrics.md"
