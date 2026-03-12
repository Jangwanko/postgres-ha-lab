# 저장소 분석 메모

## 리팩터링 전 상태

기존 저장소는 Docker Compose로 `primary`, `replica` 두 노드를 띄우고,
`scripts/failover-manager.sh`가 Docker 소켓을 통해 컨테이너 상태를 감시하는 구조였다.

핵심 특징:
- `cluster-state/current_primary` 파일에 현재 리더 상태를 기록
- `postgres-ha-node.sh`가 base backup으로 follower 초기화
- `failover-manager.sh`가 장애 감지 후 follower 승격
- Prometheus/Grafana는 있었지만 메트릭 범위가 제한적
- 로드 밸런서와 정식 클러스터 코디네이션 계층은 없었음

이 구조는 동작은 했지만 다음 한계가 있었다.
- 리더 선출 근거가 상태 파일 하나에 의존
- Docker 소켓 접근이 필요해 권한 경계가 약함
- 노드가 2개뿐이라 장애 내성이 낮음
- 클라이언트 접속 엔드포인트가 고정되어 있지 않음

## 리팩터링 후 목표

현재 저장소는 다음 기준으로 재구성했다.
- PostgreSQL 3노드
- repmgr 기반 자동 failover
- Pgpool 기반 단일 접속 엔드포인트와 읽기 분산
- Prometheus/Grafana 기반 운영 지표 관측
- 장애 주입 스크립트와 운영 런북 제공
