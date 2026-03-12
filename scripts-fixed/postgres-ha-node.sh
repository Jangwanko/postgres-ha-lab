#!/bin/bash
set -euo pipefail

# Shared entrypoint for primary/replica nodes.
# Role is determined by the value in cluster-state/current_primary.
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
  echo "primary" > "$STATE_FILE"
fi

leader="$(tr -d '\r\n' < "$STATE_FILE")"
if [ "$leader" != "primary" ] && [ "$leader" != "replica" ]; then
  echo "primary" > "$STATE_FILE"
  leader="primary"
fi

bootstrap_leader() {
  if [ -s "$DATA_DIR/PG_VERSION" ]; then
    return 0
  fi

  echo "[$NODE_NAME] Initializing new PostgreSQL data directory"
  install -d -o postgres -g postgres "$DATA_DIR"
  gosu postgres initdb -D "$DATA_DIR" >/dev/null

  gosu postgres pg_ctl -D "$DATA_DIR" -o "-c listen_addresses=''" -w start
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
  until pg_isready -h "$leader" -p 5432 -U postgres >/dev/null 2>&1; do
    sleep 2
  done

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