# Monitoring Infrastructure Deployment

This guide explains how to deploy MLflow, Prometheus, and Grafana monitoring services separately from the main application pipeline.

## Overview

- **Main app deployment** (`main.tf`): Runs on every push to main (CI/CD pipeline)
- **Monitoring deployment** (`monitoring.tf`): Deployed once per environment, then stable

## Why Separate?

Monitoring services store persistent data (logs, configurations, metrics) and shouldn't be recreated on every deployment. Doing so causes:
- CloudWatch log group conflicts
- Security group naming conflicts
- Load balancer target group conflicts

## Deployment Steps

### Prerequisites

```bash
cd infra/
terraform init -reconfigure \
  -backend-config="bucket=YOUR_TF_STATE_BUCKET" \
  -backend-config="region=us-east-1"
```

### Deploy Monitoring to Staging (One-Time)

```bash
# Option 1: Deploy all monitoring resources
TF_VAR_environment_name=staging \
TF_VAR_lab_role_arn=YOUR_LAB_ROLE_ARN \
TF_VAR_vpc_id=YOUR_VPC_ID \
terraform apply \
  -target=aws_s3_bucket.mlflow_artifacts \
  -target=aws_cloudwatch_log_group.mlflow_logs \
  -target=aws_security_group.mlflow_alb_sg \
  -target=aws_security_group.mlflow_ecs_sg \
  -target=aws_lb.mlflow \
  -target=aws_lb_target_group.mlflow_tg \
  -target=aws_lb_listener.mlflow_http \
  -target=aws_ecs_task_definition.mlflow \
  -target=aws_ecs_service.mlflow \
  -target=aws_cloudwatch_log_group.prometheus_logs \
  -target=aws_security_group.prometheus_alb_sg \
  -target=aws_security_group.prometheus_ecs_sg \
  -target=aws_lb.prometheus \
  -target=aws_lb_target_group.prometheus_tg \
  -target=aws_lb_listener.prometheus_http \
  -target=aws_ecs_task_definition.prometheus \
  -target=aws_ecs_service.prometheus \
  -target=aws_cloudwatch_log_group.grafana_logs \
  -target=aws_security_group.grafana_alb_sg \
  -target=aws_security_group.grafana_ecs_sg \
  -target=aws_lb.grafana \
  -target=aws_lb_target_group.grafana_tg \
  -target=aws_lb_listener.grafana_http \
  -target=aws_ecs_task_definition.grafana \
  -target=aws_ecs_service.grafana
```

Or simpler:

```bash
# Option 2: Deploy everything (simpler, includes main.tf resources too)
TF_VAR_environment_name=staging \
TF_VAR_lab_role_arn=YOUR_LAB_ROLE_ARN \
TF_VAR_vpc_id=YOUR_VPC_ID \
terraform apply
```

### Deploy Monitoring to Production (One-Time)

```bash
terraform init -reconfigure \
  -backend-config="bucket=YOUR_TF_STATE_BUCKET" \
  -backend-config="key=final-ci-cd/production/terraform.tfstate" \
  -backend-config="region=us-east-1"

TF_VAR_environment_name=production \
TF_VAR_lab_role_arn=YOUR_LAB_ROLE_ARN \
TF_VAR_vpc_id=YOUR_VPC_ID \
terraform apply
```

## Verify Deployment

After deployment, you can verify the services are running:

```bash
# Check Prometheus health
curl http://YOUR_PROMETHEUS_ALB_DNS/-/healthy

# Check Grafana health
curl http://YOUR_GRAFANA_ALB_DNS/api/health

# Check MLflow health
curl http://YOUR_MLFLOW_ALB_DNS/health
```

## Access the Dashboards

After deployment, access the monitoring services:

- **Prometheus:** `http://<prometheus-alb-dns>/`
- **Grafana:** `http://<grafana-alb-dns>/` (default: admin/admin)
- **MLflow:** `http://<mlflow-alb-dns>/`

## Grafana Dashboard Setup (Manual)

Currently, Grafana only has the Prometheus datasource configured. To add dashboards:

1. Login to Grafana with default credentials (admin/admin)
2. Go to Dashboards → Import
3. Search for Prometheus dashboard IDs (e.g., ID 3662 for Prometheus stats)
4. Import and customize as needed

Future enhancement: Add dashboard provisioning to `monitoring.tf` to auto-import dashboards.

## Important Notes

- **Once deployed, leave monitoring services alone** — don't re-run Terraform apply unless you're adding new resources
- **MLflow S3 bucket is per-environment** — data stored in staging won't appear in production
- **Grafana credentials are hardcoded** (`admin/admin`) — consider using secrets in production
- **Prometheus scrapes the main ALB** — metrics reflect app performance on the deployed cluster

## Cleanup

If you need to destroy monitoring services:

```bash
terraform destroy \
  -target=aws_ecs_service.grafana \
  -target=aws_ecs_service.prometheus \
  -target=aws_ecs_service.mlflow
# ... (continue for other resources, in reverse dependency order)
```

Or destroy everything:

```bash
terraform destroy
```
