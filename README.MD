# postgres-ha-lab

PostgreSQL 고가용성 구성을 직접 설계하고, 장애를 일으킨 뒤 복구까지 검증하는 포트폴리오 프로젝트입니다.  
단순히 DB 두 대를 띄우는 수준이 아니라, 자동 failover, 접속 엔드포인트 분리, 메트릭 수집, 장애 실험, 운영 문서까지 한 번에 보여주는 데 목적을 두었습니다.

## 이 저장소에서 보여주려는 것

- PostgreSQL 스트리밍 복제
- 자동 failover와 primary 재선출
- Pgpool 기반 단일 접속 엔드포인트와 읽기 분산
- Prometheus/Grafana 기반 상태 관측
- 장애 주입 스크립트를 통한 복구 검증
- DevOps/SRE 관점의 운영 런북

## 아키텍처

현재 Docker Compose 스택은 아래처럼 구성됩니다.

- `pg-node-1`, `pg-node-2`, `pg-node-3`
  : PostgreSQL + repmgr 노드다. 한 노드는 primary, 나머지는 replica 역할을 맡는다.
- `pgpool`
  : 애플리케이션이 붙는 단일 접속 지점이다. primary 쓰기 연결과 replica 읽기 분산을 담당한다.
- `postgres-exporter-node1/2/3`
  : 각 PostgreSQL 노드의 메트릭을 Prometheus 형식으로 노출한다.
- `prometheus`
  : PostgreSQL 상태, 역할, 복제 지연을 수집한다.
- `grafana`
  : 수집한 메트릭을 대시보드로 보여준다.

접속 포트:
- 애플리케이션 접속: `localhost:5432` (`pgpool`)
- 노드 직접 접속: `5433`, `5434`, `5435`
- Prometheus: `9090`
- Grafana: `3000`

## 복제 구성

이 프로젝트는 repmgr를 이용한 PostgreSQL 스트리밍 복제를 사용합니다.

- primary는 WAL을 생성한다.
- replica들은 primary의 WAL을 따라가며 비동기 복제를 수행한다.
- repmgr는 노드 상태와 역할 정보를 관리하고, primary 장애 시 승격 대상을 고른다.
- 승격 우선순위는 `docker-compose.yml`의 `REPMGR_NODE_PRIORITY`로 조정한다.

요약하면:
- 복제: PostgreSQL streaming replication
- 코디네이션: repmgr
- 클라이언트 라우팅: Pgpool

## failover는 어떻게 동작하나

1. 현재 primary가 장애로 내려간다.
2. 남아 있는 replica들이 repmgr 정보를 바탕으로 새 primary 후보를 정한다.
3. 우선순위가 높은 replica가 승격된다.
4. Pgpool이 새 primary를 기준으로 연결을 다시 정리한다.
5. 장애 노드는 `rejoin-node` 스크립트로 데이터 디렉터리를 다시 맞춘 뒤 replica로 재합류시킨다.

이 흐름을 코드로 확인하려면 [docker-compose.yml](C:\Users\rhwkd\VSC\postgres-ha-lab\docker-compose.yml), [scripts/failover-test.sh](C:\Users\rhwkd\VSC\postgres-ha-lab\scripts\failover-test.sh), [scripts/measure-ha-metrics.sh](C:\Users\rhwkd\VSC\postgres-ha-lab\scripts\measure-ha-metrics.sh)을 보면 된다.

## Quick Start

처음 보는 사람도 바로 실행할수 있는 사용방법입니다.
기본적으로 도커 설치후 실행이 되어있어야합니다.

1. 클러스터 기동

```powershell
docker compose up -d
docker compose ps
```

2. 자동 failover 테스트

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failover-test.ps1
```

또는

```bash
bash scripts/failover-test.sh
```

3. 운영 지표 측정

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\measure-ha-metrics.ps1 -Runs 10
```

또는

```bash
bash scripts/measure-ha-metrics.sh 10
```

4. 대시보드 확인

- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`

5. 종료

```powershell
docker compose down -v
```

## 장애 실험 시나리오

이 저장소는 “잘 된다”에서 끝나지 않고, 실제로 장애를 넣어 보고 복구를 확인하는 흐름을 포함합니다.

### 1. Primary 장애

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failure-primary.ps1
```

또는

```bash
bash scripts/failure-primary.sh
```

검증 포인트:
- 새로운 primary가 선출되는가
- `rejoin-node` 절차를 거친 기존 primary가 replica로 복귀하는가
- `pgpool` 접속이 계속 살아 있는가

### 2. Replica 장애

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failure-replica.ps1
```

검증 포인트:
- primary는 유지되는가
- 장애 난 replica가 자동으로 다시 합류하는가

### 3. 네트워크 분리

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failure-network-partition.ps1
```

검증 포인트:
- 격리된 primary 대신 새 primary가 선출되는가
- 네트워크 복구 후 필요하면 `rejoin-node` 절차로 격리 노드를 replica로 붙일 수 있는가

## 모니터링

Prometheus 설정은 [monitoring/prometheus.yml](C:\Users\rhwkd\VSC\postgres-ha-lab\monitoring\prometheus.yml)에, 경보 규칙은 [monitoring/alerts/postgres-ha-rules.yml](C:\Users\rhwkd\VSC\postgres-ha-lab\monitoring\alerts\postgres-ha-rules.yml)에 있다.

Grafana는 프로비저닝 방식으로 바로 사용할 수 있게 구성했습니다.

- 데이터소스: [monitoring/grafana/provisioning/datasources/prometheus.yml](C:\Users\rhwkd\VSC\postgres-ha-lab\monitoring\grafana\provisioning\datasources\prometheus.yml)
- 대시보드: [monitoring/grafana/dashboards/postgres-ha-overview.json](C:\Users\rhwkd\VSC\postgres-ha-lab\monitoring\grafana\dashboards\postgres-ha-overview.json)

주요 메트릭:
- `pg_up`
- `pg_is_in_recovery`
- `pg_replication_replay_lag_seconds`
- `rate(pg_stat_database_xact_commit[5m])`

## 운영 문서

실제 운영 관점에서 필요한 절차는 [docs/runbook.md](C:\Users\rhwkd\VSC\postgres-ha-lab\docs\runbook.md)에 따로 정리했습니다.

포함 내용:
- 클러스터 기동과 정상 상태 확인
- 현재 primary 판별
- primary / replica / 네트워크 분리 장애 대응
- 메트릭 확인 포인트
- 로그 확인 방법
- 정리 절차

## Kubernetes와 Terraform

Kubernetes와 IaC 경로도 실행해볼수 있도록 정리해 두었습니다.

- Kubernetes 참조: [k8s/cnpg-cluster.yaml](C:\Users\rhwkd\VSC\postgres-ha-lab\k8s\cnpg-cluster.yaml)
- Terraform 참조: [infra/terraform/main.tf](C:\Users\rhwkd\VSC\postgres-ha-lab\infra\terraform\main.tf)


## 이 프로젝트의 강점

- 단순한 복제 예제가 아니라 장애 실험과 복구 검증까지 포함하여 다양한 환경에 대처해볼수 있습니다.
- 메트릭과 운영 런북이 같이 있어서 SRE 관점 설명이 가능합니다.
- 로컬 실습용 경로와 클라우드 확장 경로를 함께 보여줍니다.

## 아직 남아 있는 한계

- 현재 Compose 경로는 운영형 참조 구조이지만, 진짜 운영에서는 관리형 스토리지와 네트워크 정책, 비밀 관리가 더 필요합니다.
- 공개 이미지 가용성 이슈 때문에 일부 컨테이너 이미지는 `latest` 계열을 사용한다. 운영 배포에서는 반드시 버전 또는 digest를 고정해야 합니다.
- Alertmanager, Loki 같은 알림/로그 스택은 아직 붙이지 않았습니다.
- Terraform 경로는 클라우드 기반 확장 예시이고, 지금 Compose 스택과 1:1 배포 파이프라인으로 연결된 상태는 아닙니다.

이걸 적어놓는 이유는, 포트폴리오에서는 “어디까지 했고 어디가 다음 단계인지”를 분명하게 보여주는 편이 더 낫다고 생각했기 때문입니다. 다음에 볼때 더 업그레이드 되어 있기를 바랍니다.
