# PostgreSQL HA 운영 런북

## 1. 클러스터 기동

```powershell
docker compose up -d
docker compose ps
```

확인 포인트:
- `pg_node1`, `pg_node2`, `pg_node3`가 `healthy`
- `pgpool`, `prometheus`, `grafana`가 `running`
- 애플리케이션 접속 포트는 `localhost:5432`

## 2. 현재 Primary 확인

```powershell
docker exec -e PGPASSWORD=postgres pg_node1 /opt/bitnami/postgresql/bin/psql -h 127.0.0.1 -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
docker exec -e PGPASSWORD=postgres pg_node2 /opt/bitnami/postgresql/bin/psql -h 127.0.0.1 -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
docker exec -e PGPASSWORD=postgres pg_node3 /opt/bitnami/postgresql/bin/psql -h 127.0.0.1 -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
```

- `f`: Primary
- `t`: Replica

## 3. 장애 대응 절차

### Primary 장애

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failure-primary.ps1
```

기대 결과:
- 기존 Primary 컨테이너가 비정상 종료
- repmgr가 새 Primary를 선출
- Pgpool이 쓰기 연결 대상을 갱신
- old primary는 별도 재조인 절차로 replica로 복귀

재조인:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\rejoin-node.ps1 -Node pg_node1
```

또는

```bash
bash scripts/rejoin-node.sh pg_node1
```

### Replica 장애

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failure-replica.ps1
```

기대 결과:
- Primary는 유지
- 장애 Replica만 다시 기동
- 필요하면 `rejoin-node` 절차로 복구

### 네트워크 분리

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failure-network-partition.ps1
```

기대 결과:
- 분리된 Primary가 클러스터에서 이탈
- 남은 Replica 중 우선순위가 높은 노드가 Primary 승격
- 네트워크 복구 후 필요하면 `rejoin-node`로 old primary 재합류

## 4. 모니터링 확인

- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`
- 기본 계정: `admin / admin`

대시보드 확인 포인트:
- `pg_up`
- `pg_is_in_recovery`
- `pg_replication_replay_lag_seconds`
- 트랜잭션 처리량

## 5. 운영 지표 측정

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\measure-ha-metrics.ps1 -Runs 10
```

또는

```bash
bash scripts/measure-ha-metrics.sh 10
```

결과 파일:
- `reports/ha-metrics.json`
- `reports/ha-metrics.md`

## 6. 장애 시 로그 확인

```powershell
docker logs pg_node1
docker logs pg_node2
docker logs pg_node3
docker logs pgpool
docker compose logs -f
```

## 7. 정리

```powershell
docker compose down -v
```

주의:
- `down -v`는 데이터 볼륨까지 삭제한다.
- 재조인 스크립트는 대상 노드 볼륨을 삭제하고 다시 clone하는 방식이라, 운영 환경에서는 반드시 백업/복구 정책과 같이 써야 한다.
