# postgres-ha-lab

Docker Compose와 Kubernetes(CloudNativePG) 기반으로 PostgreSQL 고가용성(HA)을 구현하고,
장애 감지-자동 승격-재조인 복구를 검증하는 포트폴리오 프로젝트입니다.

## 프로젝트 요약
- 목표: Primary 장애 시 서비스 중단을 최소화하고 자동 복구 가능한 PostgreSQL HA 구성
- 핵심 기능: 자동 Failover, 기존 Primary 자동 재기동/재조인, 지표 측정, 모니터링
- 기술 스택: Docker Compose, PostgreSQL, Prometheus, Grafana, Kubernetes(CNPG), Terraform, GitHub Actions

## 아키텍처 핵심
- `pg_primary`, `pg_replica`: PostgreSQL 노드
- `pg_failover_manager`: 장애 감지 및 승격/재기동 트리거
- `postgres_exporter`: DB 메트릭 수집
- `prometheus`, `grafana`: 관측/시각화
- `cluster-state/current_primary`: 현재 리더 상태 공유 파일

## 최근 성능 지표 (2026-03-13, Runs=5, FailoverWait=10s)
- RTO(Primary 장애 후 Replica 승격 완료 시간): **0.515초**
- 재조인 시간(기존 Primary가 Follower로 복구 완료되는 시간): **3.051초**
- 복구 성공률(반복 테스트 성공 비율): **100% (5/5)**

## 포트폴리오 사용법
면접관/리뷰어가 빠르게 검증하는 권장 순서입니다.

1. 프로젝트 목적과 아키텍처를 먼저 확인
2. 아래 Quick Start로 즉시 실행
3. 장애 테스트를 실행해 자동 승격/복구 확인
4. `reports/ha-metrics.json`, `reports/ha-metrics.md`로 수치 확인
5. Prometheus/Grafana에서 메트릭 화면 확인

5분 데모 시나리오:
1. `docker compose up -d`
2. `powershell -ExecutionPolicy Bypass -File .\scripts\failover-test.ps1`
3. `Get-Content .\cluster-state\current_primary`
4. `powershell -ExecutionPolicy Bypass -File .\scripts\measure-ha-metrics.ps1 -Runs 3`
5. Grafana/Prometheus 화면으로 상태 확인

## Quick Start

처음 보는 사람도 바로 실행할수 있는 사용방법입니다.
기본적으로 도커 설치후 실행이 되어있어야합니다.

1. 클러스터 기동

```powershell
docker compose up -d
docker compose ps
```

2. OS 자동 감지 통합 실행(권장)
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-tests.ps1 -Runs 3
```
```bash
bash scripts/run-tests.sh 3
```

3. 결과 확인
- 역할 상태: `cluster-state/current_primary`
- 지표 리포트: `reports/ha-metrics.json`, `reports/ha-metrics.md`
- `reports` 경로에 쓰기 권한이 없으면 `reports-fixed/`에 생성됨

4. 정리
```powershell
docker compose down -v
Remove-Item -Force .\cluster-state\current_primary -ErrorAction SilentlyContinue
```

## 장애 검증 절차
PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failover-test.ps1
```

또는

```bash
bash scripts/failover-test.sh
```

3. 운영 지표 측정

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\measure-ha-metrics.ps1 -Runs 5 -FailoverWaitSeconds 10
```

또는

```bash
bash scripts/measure-ha-metrics.sh 10
```

생성 파일:
- `reports/ha-metrics.json`
- `reports/ha-metrics.md`
- 권한 이슈 시: `reports-fixed/ha-metrics.json`, `reports-fixed/ha-metrics.md`

- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`
- Grafana 대시보드: `HA Metrics` (측정 스크립트 실행 시 `reports-fixed/ha-metrics.prom` 갱신)
- 컨테이너 로그 확인:
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
