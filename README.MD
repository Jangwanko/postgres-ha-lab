# postgres-ha-lab

Docker Compose와 Kubernetes(CloudNativePG) 기반으로 PostgreSQL 고가용성(HA)을 실습하는 프로젝트입니다.

## 0) 처음 실행(Quick Start)
처음 클론한 사용자는 아래 순서만 따라하면 됩니다.

1. 저장소 클론 후 프로젝트 폴더로 이동
2. 컨테이너 기동
```powershell
docker compose up -d
docker compose ps
```
3. 자동 감지 단일 테스트 실행(권장)
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-tests.ps1 -Runs 3
```
```bash
bash scripts/run-tests.sh 3
```
4. 결과 확인
- 역할 상태: `cluster-state/current_primary`
- 지표 리포트: `reports/ha-metrics.json`, `reports/ha-metrics.md`
5. 종료/정리
```powershell
docker compose down -v
Remove-Item -Force .\cluster-state\current_primary -ErrorAction SilentlyContinue
```

## 주요 기능
- Primary 장애 감지
- Replica 자동 승격
- 기존 Primary 자동 재기동 및 Follower 재동기화
- Prometheus/Grafana 모니터링
- IaC(Terraform) 기본 구성
- CI/CD(GitHub Actions) 자동 검증
- 운영 지표(RTO, failover 시간, 복구 성공률) 자동 측정

## 디렉토리 구조
- `docker-compose.yml`: Compose 기반 HA 실행
- `scripts/`
  - `postgres-ha-node.sh`: 노드 시작/역할 결정/재동기화
  - `failover-manager.sh`: 장애 감지/승격/재기동 트리거
  - `failover-test.ps1`, `failover-test.sh`: E2E failover 테스트
  - `measure-ha-metrics.ps1`, `measure-ha-metrics.sh`: 운영 지표 측정
  - `run-tests.ps1`, `run-tests.sh`: OS 자동 감지 통합 실행
- `monitoring/`: Prometheus 설정
- `k8s/`: CloudNativePG 매니페스트 및 K8S 가이드
- `infra/terraform/`: AWS IaC(VPC/EKS/RDS/CloudWatch Dashboard)
- `.github/workflows/ha-ci.yml`: CI 파이프라인
- `reports/`: 지표 결과 산출물

## 1) Compose 실행
```powershell
docker compose up -d
docker compose ps
```

역할 확인:
```powershell
Get-Content .\cluster-state\current_primary
docker exec pg_primary psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
docker exec pg_replica psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
```
- `f` = Leader
- `t` = Follower

## 2) Failover 자동 검증
PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\failover-test.ps1
```

Linux/macOS/CI:
```bash
bash scripts/failover-test.sh
```

## 2-1) OS 자동 감지 단일 실행
PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-tests.ps1 -Runs 3
```

bash:
```bash
bash scripts/run-tests.sh 3
```

동작:
- Windows 감지 시 `failover-test.ps1`, `measure-ha-metrics.ps1` 실행
- Linux/macOS 감지 시 `failover-test.sh`, `measure-ha-metrics.sh` 실행

## 3) 운영 지표 측정
PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\measure-ha-metrics.ps1 -Runs 5
```

Linux/macOS/CI:
```bash
bash scripts/measure-ha-metrics.sh 5
```

생성 파일:
- `reports/ha-metrics.json`
- `reports/ha-metrics.md`

지표 항목:
- RTO(Primary 장애 후 Replica 승격 완료 시간)
- 재조인 시간(기존 Primary가 Follower로 복구 완료되는 시간)
- 복구 성공률(반복 테스트 성공 비율)

## 4) CI/CD 파이프라인
파일: `.github/workflows/ha-ci.yml`

동작:
1. 코드 체크아웃
2. `docker compose up -d`
3. `scripts/failover-test.sh` 실행
4. `scripts/measure-ha-metrics.sh 3` 실행
5. 리포트/로그 아티팩트 업로드
6. `docker compose down -v` 정리

## 5) IaC (Terraform)
경로: `infra/terraform/`

자동화 리소스:
- VPC
- EKS
- RDS(PostgreSQL)
- CloudWatch Dashboard(운영 지표 확인용)

사용 예시:
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

주의:
- AWS 비용이 발생할 수 있습니다.
- 운영 환경은 Terraform 원격 상태 백엔드(S3 + DynamoDB) 사용을 권장합니다.

## 6) Kubernetes 경로
K8S 적용/검증 절차는 `k8s/README.MD`를 참고하세요.

## 7) 모니터링
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`

Prometheus `Status > Targets`에서 아래가 `UP`인지 확인:
- `postgres_primary`
- `postgres_replica`

## 8) 주의사항
1. 계정/비밀번호는 실습용 기본값입니다.
2. `pg_failover_manager`는 Docker 소켓(`/var/run/docker.sock`)에 접근합니다.
3. 운영 반영 시 비밀정보 관리, 최소권한, TLS, 백업/복구 정책을 별도로 설계해야 합니다.

## 9) 정리
Compose 정리:
```powershell
docker compose down -v
Remove-Item -Force .\cluster-state\current_primary -ErrorAction SilentlyContinue
```

K8S 정리:
```powershell
kubectl delete -f .\k8s\cnpg-cluster.yaml
kubectl delete namespace cnpg-system
```
