# Terraform IaC 가이드

이 디렉터리는 AWS 기준으로 아래 리소스를 자동화합니다.

- VPC (퍼블릭/프라이빗 서브넷, NAT)
- EKS 클러스터 (관리형 노드 그룹)
- RDS PostgreSQL 인스턴스
- CloudWatch 대시보드(운영 지표 시각화 기본 틀)

## 사용 방법

```bash
cd infra/terraform
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

## 주의사항

- 실제 배포 전 AWS 비용을 반드시 확인하세요.
- `terraform.tfvars`는 환경별로 분리해 관리하세요.
- 운영 환경에서는 상태 파일 원격 백엔드(S3+DynamoDB) 사용을 권장합니다.
