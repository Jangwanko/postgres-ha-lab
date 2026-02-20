#!/bin/bash
set -euo pipefail

# 두 노드(primary/replica)가 공통으로 사용하는 시작 스크립트.
# 실제 역할(leader/follower)은 cluster-state/current_primary 값을 기준으로 결정된다.
DATA_DIR="${PGDATA:-/var/lib/postgresql/data}"
STATE_FILE="${STATE_FILE:-/cluster-state/current_primary}"
NODE_NAME="${NODE_NAME:?NODE_NAME is required}"
PEER_NODE="${PEER_NODE:?PEER_NODE is required}"
POSTGRES_DB="${POSTGRES_DB:-appdb}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
REPL_USER="replicator"
REPL_PASS="replica_pass"
POSTGRES_ARGS="-c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf"

mkdir -p "$(dirname "$STATE_FILE")"
if [ ! -s "$STATE_FILE" ]; then
  # 초기 부트스트랩 시 기본 리더는 primary
  echo "primary" > "$STATE_FILE"
fi

leader="$(tr -d '\r\n' < "$STATE_FILE")"
if [ "$leader" != "primary" ] && [ "$leader" != "replica" ]; then
  echo "primary" > "$STATE_FILE"
  leader="primary"
fi

bootstrap_leader() {
  if [ -s "$DATA_DIR/PG_VERSION" ]; then
    # 이미 데이터 디렉터리가 초기화된 경우 재초기화하지 않는다.
    return 0
  fi

  echo "[$NODE_NAME] Initializing new PostgreSQL data directory"
  install -d -o postgres -g postgres "$DATA_DIR"
  gosu postgres initdb -D "$DATA_DIR" >/dev/null

  gosu postgres pg_ctl -D "$DATA_DIR" -o "-c listen_addresses=''" -w start
  # 초기 부트스트랩 시 필수 사용자/DB를 생성(또는 보정)한다.
  gosu postgres psql -v ON_ERROR_STOP=1 -d postgres <<SQL
ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWORD}';
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} WITH REPLICATION LOGIN PASSWORD '${REPL_PASS}';
  ELSE
    ALTER ROLE ${REPL_USER} WITH REPLICATION LOGIN PASSWORD '${REPL_PASS}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${POSTGRES_DB}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='${POSTGRES_DB}')\gexec
SQL
  gosu postgres pg_ctl -D "$DATA_DIR" -m fast -w stop
}

ensure_leader_roles() {
  # leader로 동작할 때 복제 계정을 항상 보정한다.
  until gosu postgres psql -v ON_ERROR_STOP=1 -d postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} WITH REPLICATION LOGIN PASSWORD '${REPL_PASS}';
  ELSE
    ALTER ROLE ${REPL_USER} WITH REPLICATION LOGIN PASSWORD '${REPL_PASS}';
  END IF;
END
\$\$;
SQL
  do
    sleep 1
  done
}

start_as_leader() {
  echo "[$NODE_NAME] Starting as leader"
  # standby 표식 파일 제거로 read-write(leader) 모드를 강제한다.
  rm -f "$DATA_DIR/standby.signal" "$DATA_DIR/recovery.signal"
  chown -R postgres:postgres "$DATA_DIR"
  chmod 700 "$DATA_DIR"

  gosu postgres postgres $POSTGRES_ARGS &
  pg_pid=$!

  until pg_isready -h 127.0.0.1 -p 5432 -U postgres >/dev/null 2>&1; do
    sleep 1
  done

  ensure_leader_roles
  wait "$pg_pid"
}

start_as_follower() {
  echo "[$NODE_NAME] Starting as follower (upstream: $leader)"
  # 현재 leader 접속 가능 시점까지 대기한다.
  until pg_isready -h "$leader" -p 5432 -U postgres >/dev/null 2>&1; do
    sleep 2
  done

  # follower로 시작할 때는 leader에서 base backup으로 재동기화한다.
  rm -rf "${DATA_DIR:?}"/*
  chown -R postgres:postgres "$DATA_DIR"

  until gosu postgres bash -lc "export PGPASSWORD='${REPL_PASS}'; pg_basebackup -h '${leader}' -D '${DATA_DIR}' -U '${REPL_USER}' -Fp -Xs -P -R"; do
    sleep 2
  done

  chown -R postgres:postgres "$DATA_DIR"
  chmod 700 "$DATA_DIR"
  exec gosu postgres postgres $POSTGRES_ARGS
}

if [ "$leader" = "$NODE_NAME" ]; then
  bootstrap_leader
  start_as_leader
else
  start_as_follower
fi
