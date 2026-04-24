# infra/outputs.tf

output "alb_dns_name" {
  description = "DNS Name del Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL completa del ALB"
  value       = "http://${aws_lb.main.dns_name}/"
}

output "ecs_cluster_name" {
  description = "Nombre del ECS Cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Nombre del ECS Service"
  value       = aws_ecs_service.main.name
}

output "mlflow_url" {
  description = "URL del MLflow Tracking Server"
  value       = "http://${aws_lb.mlflow.dns_name}/"
}