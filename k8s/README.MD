# Kubernetes 적용 가이드 (CloudNativePG)

이 문서는 `k8s/cnpg-cluster.yaml`을 기준으로 Kubernetes에서 PostgreSQL HA를 구성하고,
Primary 장애 시 자동 승격이 동작하는지 검증하는 방법을 설명합니다.

## 0) 처음 실행(Quick Start)
처음 K8S를 실행하는 사용자는 아래 순서대로 진행하세요.

1. kind 클러스터 생성
```powershell
kind create cluster --name pg-ha-lab --wait 180s
kubectl config current-context
kubectl get nodes -o wide
```
2. CloudNativePG Operator 설치
```powershell
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.0.yaml
kubectl -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s
```
3. PostgreSQL 클러스터 배포
```powershell
kubectl apply -f .\k8s\cnpg-cluster.yaml
kubectl get cluster -n pg-ha
kubectl get pods -n pg-ha -o wide
```
4. Failover 검증
```powershell
kubectl get cluster pg-ha-cluster -n pg-ha -o jsonpath="{.status.currentPrimary}{'\n'}"
kubectl delete pod <현재-primary-pod-이름> -n pg-ha --wait=false
kubectl get cluster pg-ha-cluster -n pg-ha -o jsonpath="{.status.currentPrimary}{'\n'}{.status.phase}{'\n'}"
```
5. 정리
```powershell
kubectl delete -f .\k8s\cnpg-cluster.yaml
kubectl delete namespace cnpg-system
kind delete cluster --name pg-ha-lab
```

## 1) 준비 사항
- `kubectl` 설치
- `kind` 설치 (로컬 실습 환경)
- Docker Desktop 또는 Docker Engine 실행 상태

## 2) kind 클러스터 생성
```powershell
kind create cluster --name pg-ha-lab --wait 180s
kubectl config current-context
kubectl get nodes -o wide
```

## 3) CloudNativePG Operator 설치
```powershell
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.0.yaml
kubectl -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s
```

정상 확인:
```powershell
kubectl get pods -n cnpg-system -o wide
```

## 4) PostgreSQL 클러스터 배포
```powershell
kubectl apply -f .\k8s\cnpg-cluster.yaml
kubectl get cluster -n pg-ha
kubectl get pods -n pg-ha -o wide
```

정상 상태:
- `cluster`의 `READY` 값이 `2`
- Pod 2개가 `Running`

## 5) Failover 검증
현재 Primary 확인:
```powershell
kubectl get cluster pg-ha-cluster -n pg-ha -o jsonpath="{.status.currentPrimary}{'\n'}"
```

Primary Pod 강제 종료:
```powershell
kubectl delete pod <현재-primary-pod-이름> -n pg-ha --wait=false
```

전환 확인:
```powershell
kubectl get cluster pg-ha-cluster -n pg-ha -o jsonpath="{.status.currentPrimary}{'\n'}{.status.phase}{'\n'}"
kubectl get pods -n pg-ha -o wide
```

SQL 역할 확인:
```powershell
kubectl exec -n pg-ha pg-ha-cluster-1 -- psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
kubectl exec -n pg-ha pg-ha-cluster-2 -- psql -U postgres -d postgres -t -A -c "select pg_is_in_recovery();"
```

- `f` = Primary
- `t` = Replica

## 6) 이벤트 확인
```powershell
kubectl get events -n pg-ha --sort-by=.lastTimestamp
```

주요 확인 키워드:
- `FailingOver`
- `FailoverTarget`

## 7) 문제 해결 팁
1. Pod가 `Pending`이면 노드 자원(CPU/메모리) 부족 여부를 확인합니다.
2. `cnpg-system` Pod가 준비되지 않으면 Operator 설치 단계를 다시 수행합니다.
3. `kubectl describe pod <pod명> -n pg-ha`로 상세 이벤트를 확인합니다.

## 8) 정리
```powershell
kubectl delete -f .\k8s\cnpg-cluster.yaml
kubectl delete namespace cnpg-system
kind delete cluster --name pg-ha-lab
```
