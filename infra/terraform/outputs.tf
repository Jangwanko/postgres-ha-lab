output "vpc_id" {
  description = "생성된 VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "생성된 EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  description = "RDS 접속 엔드포인트"
  value       = aws_db_instance.postgres.address
}

output "cloudwatch_dashboard_name" {
  description = "생성된 CloudWatch 대시보드 이름"
  value       = aws_cloudwatch_dashboard.ops.dashboard_name
}
