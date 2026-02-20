# postgres-ha-lab

PostgreSQL 2노드 HA(고가용성) 실습 프로젝트입니다.  
이 프로젝트는 Docker Compose만으로 아래 흐름을 자동화합니다.

- Primary 장애 감지
- Replica 자동 승격(Promote)
- 중지된 Primary 자동 재기동
- 재기동된 Primary 자동 재동기화 후 Follower 복귀

## 1. 구성 개요

- `pg_primary`: PostgreSQL 노드 1 (고정 이름)
- `pg_replica`: PostgreSQL 노드 2 (고정 이름)
- `pg_failover_manager`: 헬스체크/승격/자동재기동 담당
- `cluster-state/current_primary`: 현재 리더 노드 이름(`primary` 또는 `replica`) 저장

핵심 스크립트:

- `scripts/postgres-ha-node.sh`
  - 노드 시작 시 리더/팔로워 역할 결정
  - 리더: DB/복제 계정 보정
  - 팔로워: `pg_basebackup`으로 리더 데이터 재동기화 후 standby 기동
- `scripts/failover-manager.sh`
  - 리더 상태 감시
  - 리더 장애 시 팔로워 승격
  - 기존 리더 자동 재기동(완전복구)
- `scripts/failover-test.ps1`
  - end-to-end 검증 스크립트

## 2. 사전 요구사항

- Docker Engine
- Docker Compose v2
- 사용 가능한 포트: `5432`, `5433`, `3000`, `9090`
- Windows PowerShell (테스트 스크립트 실행 시)

## 3. 실행 방법

```powershell
docker compose up -d
docker compose ps
```

## 4. 현재 역할 확인

```powershell
Get-Content .\cluster-state\current_primary
docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
```

판별 기준:

- `pg_is_in_recovery() = f` : 현재 Leader
- `pg_is_in_recovery() = t` : 현재 Follower

## 5. 자동 Failover/Fallback 검증

### 방법 A) 원커맨드 검증 (권장)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failover-test.ps1
```

검증 내용:

1. Primary 강제 중지
2. Replica 자동 승격 확인
3. Primary 자동 재기동 확인
4. Primary가 Follower로 재조인했는지 확인

### 방법 B) 수동 검증

1) Primary 중지

```powershell
docker stop pg_primary
Start-Sleep -Seconds 25
```

2) 결과 확인

```powershell
Get-Content .\cluster-state\current_primary
docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
docker logs --tail 120 pg_failover_manager
```

기대 결과:

- `current_primary = replica`
- `pg_replica = f` (승격 완료)
- `pg_primary = t` (자동 재기동 후 follower 복귀)
- 매니저 로그에 `Promoting replica`, `Starting container: pg_primary`

## 6. 트러블슈팅

### 포트 충돌

- `5432`, `5433`, `3000`, `9090` 사용 중인지 확인
- 충돌 시 `docker-compose.yml` 포트 변경

### 자동 재기동이 안 될 때

- `pg_failover_manager` 이미지가 `docker:27-cli`인지 확인
- `docker-compose.yml`에 Docker 소켓 마운트가 있는지 확인
  - `/var/run/docker.sock:/var/run/docker.sock`
- 로그 확인

```powershell
docker logs --tail 200 pg_failover_manager
```

### 역할이 꼬인 것 같을 때

```powershell
docker compose down -v
Remove-Item -Force .\cluster-state\current_primary -ErrorAction SilentlyContinue
docker compose up -d
```

## 7. 종료/정리

```powershell
docker compose down
Remove-Item -Force .\cluster-state\current_primary -ErrorAction SilentlyContinue
```

## 8. Prometheus / Grafana 확인

이 프로젝트에는 모니터링 컨테이너가 함께 올라옵니다.

- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`
- Exporter: `postgres-exporter-primary`, `postgres-exporter-replica` (내부 9187 포트)

### Prometheus에서 확인할 것

1. `Status > Targets` 메뉴 진입
2. `postgres_primary`, `postgres_replica` 잡(target)이 `UP` 상태인지 확인

참고:
- 이 프로젝트는 exporter를 이미 포함합니다.
- Prometheus는 `postgres-exporter-primary:9187`, `postgres-exporter-replica:9187`를 수집합니다.

### Grafana에서 확인할 것

1. `http://localhost:3000` 접속
2. 기본 계정으로 로그인 (초기값은 Grafana 기본값 사용)
3. Data Source에 Prometheus(`http://prometheus:9090`) 추가
4. PostgreSQL 대시보드(import) 후 패널 값 확인

권장:
- 기본 PostgreSQL 대시보드 JSON을 저장소에 함께 제공하면 포트폴리오 완성도가 더 높아집니다.
