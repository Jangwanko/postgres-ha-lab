# postgres-ha-lab

Docker Compose와 Kubernetes(CloudNativePG) 두 가지 방식으로 PostgreSQL 고가용성(HA)을 실습하는 프로젝트입니다.

## 프로젝트 목적

- Primary 장애 감지
- Replica 자동 승격
- 장애 노드 자동 복구 및 재조인
- Prometheus/Grafana 모니터링

## 현재 구성

### 1) Docker Compose 기반 HA

- `pg_primary`: PostgreSQL 노드 1
- `pg_replica`: PostgreSQL 노드 2
- `pg_failover_manager`: 장애 감지/승격/자동 재기동 담당
- `postgres-exporter-primary`, `postgres-exporter-replica`: 메트릭 수집
- `prometheus`, `grafana`: 모니터링

핵심 스크립트:
- `scripts/postgres-ha-node.sh`
- `scripts/failover-manager.sh`
- `scripts/failover-test.ps1`

### 2) Kubernetes 기반 HA (CloudNativePG)

- 매니페스트: `k8s/cnpg-cluster.yaml`
- Namespace: `pg-ha`
- Cluster 이름: `pg-ha-cluster`
- 인스턴스 수: 2 (Primary 1 + Replica 1)

## 사전 요구사항

### Compose 경로
- Docker Engine
- Docker Compose v2
- PowerShell

### Kubernetes 경로
- `kubectl`
- `kind` (로컬 클러스터용)

## Compose 실행 및 검증

### 실행

```powershell
docker compose up -d
docker compose ps
```

### 역할 확인

```powershell
Get-Content .\cluster-state\current_primary
docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
```

- `pg_is_in_recovery() = f` : Leader
- `pg_is_in_recovery() = t` : Follower

### 자동 Failover/Fallback 검증

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failover-test.ps1
```

이 스크립트는 다음을 검증합니다.
1. Primary 강제 중지
2. Replica 자동 승격
3. Primary 자동 재기동
4. Primary follower 재조인

## Kubernetes 적용 및 검증

자세한 절차는 `k8s/README.MD`를 참고하세요.

요약 절차:

1. kind 클러스터 생성
2. CloudNativePG Operator 설치
3. `k8s/cnpg-cluster.yaml` 적용
4. Primary Pod 삭제 후 자동 승격 확인

검증 예시:

```powershell
kubectl get cluster -n pg-ha
kubectl get pods -n pg-ha -o wide
kubectl get cluster pg-ha-cluster -n pg-ha -o jsonpath="{.status.currentPrimary}"
```

## 모니터링

- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`

Prometheus 타깃 확인:
- `Status > Targets`
- `postgres_primary`, `postgres_replica` 상태가 `UP`인지 확인

## 사용자가 알아야 할 주의사항

1. 본 프로젝트의 계정/비밀번호는 실습용 기본값입니다.
2. `pg_failover_manager`는 Docker 소켓(`/var/run/docker.sock`)을 사용하므로 높은 권한을 가집니다.
3. 운영 환경에서는 비밀정보 관리, 권한 분리, TLS, 백업 정책을 별도로 설계해야 합니다.

## 정리

### Compose 정리

```powershell
docker compose down
Remove-Item -Force .\cluster-state\current_primary -ErrorAction SilentlyContinue
```

### Kubernetes 정리

```powershell
kubectl delete -f .\k8s\cnpg-cluster.yaml
kubectl delete namespace cnpg-system
```
