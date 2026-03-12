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
처음 클론한 사용자는 아래 순서대로 진행하면 됩니다.

1. 컨테이너 기동
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

Linux/macOS/CI:
```bash
bash scripts/failover-test.sh
```

역할 확인:
```powershell
docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
```
- `f` = Leader
- `t` = Follower

## 운영 지표 측정
PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\measure-ha-metrics.ps1 -Runs 5 -FailoverWaitSeconds 10
```

Linux/macOS/CI:
```bash
bash scripts/measure-ha-metrics.sh 5
```

생성 파일:
- `reports/ha-metrics.json`
- `reports/ha-metrics.md`
- 권한 이슈 시: `reports-fixed/ha-metrics.json`, `reports-fixed/ha-metrics.md`

## 모니터링과 로그
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`
- Grafana 대시보드: `HA Metrics` (측정 스크립트 실행 시 `reports-fixed/ha-metrics.prom` 갱신)
- 컨테이너 로그 확인:
```powershell
docker compose logs -f
docker logs pg_failover_manager
```

## CI/CD
파일: `.github/workflows/ha-ci.yml`

동작:
1. Compose 기동
2. Failover 테스트
3. 지표 측정
4. 리포트/로그 아티팩트 업로드
5. 환경 정리

## IaC (Terraform)
경로: `infra/terraform/`

자동화 대상:
- VPC
- EKS
- RDS(PostgreSQL)
- CloudWatch Dashboard

## Kubernetes 확장
K8S 적용/검증 상세는 `k8s/README.MD` 참고.

## 한계와 개선 계획
- 현재는 Docker 소켓 접근 기반 매니저 구조이므로 운영 환경에서는 권한/보안 강화 필요
- 전용 로그 분석 스택(Loki/Promtail 또는 ELK) 추가 가능
- 다중 AZ/백업 정책/비밀관리(Secrets Manager, Vault) 고도화 필요

## 디렉토리
- `docker-compose.yml`: 로컬 HA 구성
- `scripts/`: failover/측정/통합 실행 스크립트
- `monitoring/`: Prometheus 설정
- `k8s/`: CloudNativePG 매니페스트 및 가이드
- `infra/terraform/`: AWS IaC

## 주의사항
1. 계정/비밀번호는 실습용 기본값입니다.
2. 운영 반영 시 TLS, 최소권한, 백업/복구 정책을 별도 설계해야 합니다.
