# Kubernetes 적용 가이드 (CloudNativePG)

이 문서는 `k8s/cnpg-cluster.yaml`을 이용해 Kubernetes에서 PostgreSQL HA를 구성하고
Primary 장애 시 자동 승격을 검증하는 절차를 설명합니다.

## 1. 준비

- `kubectl` 설치
- `kind` 설치 (로컬 실습 기준)

## 2. kind 클러스터 생성

```powershell
kind create cluster --name pg-ha-lab --wait 180s
kubectl config current-context
kubectl get nodes
```

## 3. CloudNativePG Operator 설치

```powershell
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.0.yaml
kubectl -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s
```

## 4. PostgreSQL 클러스터 배포

```powershell
kubectl apply -f .\k8s\cnpg-cluster.yaml
kubectl get cluster -n pg-ha
kubectl get pods -n pg-ha -o wide
```

정상 상태:
- `cluster`의 `READY` 값이 `2`
- Pod 2개가 `Running`

## 5. Failover 검증

현재 Primary 확인:

```powershell
kubectl get cluster pg-ha-cluster -n pg-ha -o jsonpath="{.status.currentPrimary}"
```

Primary Pod 삭제:

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

## 6. 이벤트 확인

```powershell
kubectl get events -n pg-ha --sort-by=.lastTimestamp
```

확인 키워드:
- `FailingOver`
- `FailoverTarget`

## 7. 정리

```powershell
kubectl delete -f .\k8s\cnpg-cluster.yaml
kubectl delete namespace cnpg-system
kind delete cluster --name pg-ha-lab
```
