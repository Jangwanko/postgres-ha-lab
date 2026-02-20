#!/bin/sh
set -eu

# 이 매니저는 무한 루프로 동작하며 failover/failback을 제어한다.
# Docker 소켓을 통해 노드 컨테이너 상태 조회/재기동을 수행한다.
STATE_FILE="/cluster-state/current_primary"
CHECK_INTERVAL=5
FAIL_THRESHOLD=3

PRIMARY_CONTAINER="pg_primary"
REPLICA_CONTAINER="pg_replica"

mkdir -p "$(dirname "$STATE_FILE")"
[ -s "$STATE_FILE" ] || echo "primary" > "$STATE_FILE"

read_leader() {
  leader="$(tr -d '\r\n' < "$STATE_FILE")"
  if [ "$leader" != "primary" ] && [ "$leader" != "replica" ]; then
    echo "primary" > "$STATE_FILE"
    leader="primary"
  fi
  echo "$leader"
}

write_leader() {
  # 현재 리더 선택값을 상태 파일에 저장한다.
  echo "$1" > "$STATE_FILE"
}

container_for_node() {
  if [ "$1" = "primary" ]; then
    echo "$PRIMARY_CONTAINER"
  else
    echo "$REPLICA_CONTAINER"
  fi
}

other_node() {
  if [ "$1" = "primary" ]; then
    echo "replica"
  else
    echo "primary"
  fi
}

is_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" = "true" ]
}

ensure_started() {
  # 자동 복구: 중지된 컨테이너를 다시 기동한다.
  if ! is_running "$1"; then
    echo "Starting container: $1"
    docker start "$1" >/dev/null 2>&1 || true
  fi
}

check_ready() {
  # 컨테이너 실행 + Postgres 연결 가능 상태를 함께 확인한다.
  is_running "$1" && docker exec "$1" pg_isready -h 127.0.0.1 -p 5432 -U postgres >/dev/null 2>&1
}

in_recovery() {
  docker exec "$1" psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();" 2>/dev/null | tr -d '\r\n' || true
}

promote() {
  docker exec "$1" psql -U postgres -d postgres -t -A -c "select pg_promote(true, 60);" >/dev/null 2>&1 || true
}

echo "Failover manager started."
failure_count=0

while true; do
  leader_node="$(read_leader)"
  follower_node="$(other_node "$leader_node")"
  leader_container="$(container_for_node "$leader_node")"
  follower_container="$(container_for_node "$follower_node")"

  # 완전 자동 복구를 위해 follower 프로세스가 항상 살아있게 유지한다.
  ensure_started "$follower_container"

  if check_ready "$leader_container"; then
    failure_count=0
    sleep "$CHECK_INTERVAL"
    continue
  fi

  failure_count=$((failure_count + 1))
  echo "Leader $leader_node health check failed ($failure_count/$FAIL_THRESHOLD)"

  if [ "$failure_count" -lt "$FAIL_THRESHOLD" ]; then
    sleep "$CHECK_INTERVAL"
    continue
  fi

  ensure_started "$follower_container"
  if ! check_ready "$follower_container"; then
    echo "Follower $follower_node is unavailable. Waiting."
    sleep "$CHECK_INTERVAL"
    continue
  fi

  follower_state="$(in_recovery "$follower_container")"
  if [ "$follower_state" = "t" ]; then
    # standby follower를 leader로 승격한다.
    echo "Promoting $follower_node"
    promote "$follower_container"
    sleep 2
    follower_state="$(in_recovery "$follower_container")"
  fi

  if [ "$follower_state" = "f" ]; then
    write_leader "$follower_node"
    failure_count=0
    echo "Failover complete. New leader: $follower_node"

    # 이전 leader를 자동 재기동하여 follower로 재조인시킨다.
    ensure_started "$leader_container"
  else
    echo "Could not determine follower state. Retrying."
  fi

  sleep "$CHECK_INTERVAL"
done
