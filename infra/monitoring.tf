# infra/monitoring.tf
# Monitoring infrastructure: MLflow, Prometheus, Grafana
# Deploy separately from app using: terraform apply -target=module.monitoring
# Run ONCE per environment (staging/production), then never again

locals {
  grafana_dashboard = file("${path.module}/../monitoring/grafana/dashboards/boston-house-app.json")
}

# ─────────────────────────────────────────────────────────────
# MLflow Tracking Server
# ─────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "mlflow_artifacts" {
  bucket = "mlflow-artifacts-${var.project_name}-${var.environment_name}"
  tags   = { Environment = var.environment_name }
}

resource "aws_cloudwatch_log_group" "mlflow_logs" {
  name              = "/ecs/${var.project_name}-${var.environment_name}-mlflow"
  retention_in_days = 7
  tags              = { Environment = var.environment_name }
}

resource "aws_security_group" "mlflow_alb_sg" {
  name        = "${var.project_name}-mlflow-alb-sg-${var.environment_name}"
  description = "HTTP access to MLflow UI"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment_name }
}

resource "aws_security_group" "mlflow_ecs_sg" {
  name        = "${var.project_name}-mlflow-ecs-sg-${var.environment_name}"
  description = "MLflow server container traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.mlflow_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb" "mlflow" {
  name               = "${var.project_name}-${var.environment_name}-mf-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mlflow_alb_sg.id]
  subnets            = var.subnet_ids
  tags               = { Environment = var.environment_name }
}

resource "aws_lb_target_group" "mlflow_tg" {
  name        = "${var.project_name}-mlflow-tg-${var.environment_name}"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "5000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb_listener" "mlflow_http" {
  load_balancer_arn = aws_lb.mlflow.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mlflow_tg.arn
  }
}

resource "aws_ecs_task_definition" "mlflow" {
  family                   = "${var.project_name}-${var.environment_name}-mlflow"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  task_role_arn            = var.lab_role_arn
  execution_role_arn       = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "mlflow-server"
      image = "ghcr.io/mlflow/mlflow:v3.11.1"

      command = [
        "mlflow", "server",
        "--host", "0.0.0.0",
        "--port", "5000",
        "--workers", "2",
        "--allowed-hosts", "*",
        "--default-artifact-root", "s3://${aws_s3_bucket.mlflow_artifacts.bucket}/artifacts",
        "--backend-store-uri", "sqlite:////tmp/mlflow.db"
      ]

      portMappings = [{ containerPort = 5000, protocol = "tcp" }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mlflow_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "mlflow"
        }
      }
    }
  ])

  tags = { Environment = var.environment_name }
}

resource "aws_ecs_service" "mlflow" {
  name            = "${var.project_name}-${var.environment_name}-mlflow-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mlflow.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.mlflow_ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mlflow_tg.arn
    container_name   = "mlflow-server"
    container_port   = 5000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 90

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.mlflow_http]
  tags       = { Environment = var.environment_name }
}

# ─────────────────────────────────────────────────────────────
# Prometheus Monitoring
# ─────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "prometheus_logs" {
  name              = "/ecs/${var.project_name}-${var.environment_name}-prometheus"
  retention_in_days = 7
  tags              = { Environment = var.environment_name }
}

resource "aws_security_group" "prometheus_alb_sg" {
  name        = "${var.project_name}-prom-alb-sg-${var.environment_name}"
  description = "HTTP access to Prometheus UI"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment_name }
}

resource "aws_security_group" "prometheus_ecs_sg" {
  name        = "${var.project_name}-prom-ecs-sg-${var.environment_name}"
  description = "Prometheus container traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.prometheus_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb" "prometheus" {
  name               = "${var.project_name}-${var.environment_name}-prom"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prometheus_alb_sg.id]
  subnets            = var.subnet_ids
  tags               = { Environment = var.environment_name }
}

resource "aws_lb_target_group" "prometheus_tg" {
  name        = "${var.project_name}-prom-tg-${var.environment_name}"
  port        = 9090
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/-/healthy"
    port                = "9090"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb_listener" "prometheus_http" {
  load_balancer_arn = aws_lb.prometheus.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus_tg.arn
  }
}

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.project_name}-${var.environment_name}-prometheus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = var.lab_role_arn
  execution_role_arn       = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "prometheus"
      image = "prom/prometheus:v2.55.1"

      entryPoint = ["sh", "-c"]
      command = [
        <<EOT
cat > /tmp/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: boston-house-app
    metrics_path: /metrics
    static_configs:
      - targets:
          - ${aws_lb.main.dns_name}:80
EOF
/bin/prometheus --config.file=/tmp/prometheus.yml --storage.tsdb.path=/prometheus --web.listen-address=0.0.0.0:9090
EOT
      ]

      portMappings = [{ containerPort = 9090, protocol = "tcp" }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.prometheus_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "prometheus"
        }
      }
    }
  ])

  tags = { Environment = var.environment_name }
}

resource "aws_ecs_service" "prometheus" {
  name            = "${var.project_name}-${var.environment_name}-prometheus-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.prometheus_ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.prometheus_tg.arn
    container_name   = "prometheus"
    container_port   = 9090
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.prometheus_http, aws_ecs_service.main]
  tags       = { Environment = var.environment_name }
}

# ─────────────────────────────────────────────────────────────
# Grafana Dashboard
# ─────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "grafana_logs" {
  name              = "/ecs/${var.project_name}-${var.environment_name}-grafana"
  retention_in_days = 7
  tags              = { Environment = var.environment_name }
}

resource "aws_security_group" "grafana_alb_sg" {
  name        = "${var.project_name}-grafana-alb-sg-${var.environment_name}"
  description = "HTTP access to Grafana UI"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment_name }
}

resource "aws_security_group" "grafana_ecs_sg" {
  name        = "${var.project_name}-grafana-ecs-sg-${var.environment_name}"
  description = "Grafana container traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb" "grafana" {
  name               = "${var.project_name}-${var.environment_name}-graf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.grafana_alb_sg.id]
  subnets            = var.subnet_ids
  tags               = { Environment = var.environment_name }
}

resource "aws_lb_target_group" "grafana_tg" {
  name        = "${var.project_name}-graf-tg-${var.environment_name}"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/api/health"
    port                = "3000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb_listener" "grafana_http" {
  load_balancer_arn = aws_lb.grafana.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana_tg.arn
  }
}

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project_name}-${var.environment_name}-grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = var.lab_role_arn
  execution_role_arn       = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "grafana"
      image = "grafana/grafana:11.4.0"

      entryPoint = ["sh", "-c"]
      command = [
        <<-EOT
mkdir -p /tmp/grafana-provisioning/datasources /tmp/grafana-provisioning/dashboards
cat > /tmp/grafana-provisioning/datasources/prometheus.yml <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://${aws_lb.prometheus.dns_name}
    isDefault: true
    editable: true
EOF
cat > /tmp/grafana-provisioning/dashboards/dashboards.yml <<'EOF'
apiVersion: 1

providers:
  - name: Boston House Dashboards
    orgId: 1
    folder: Boston House
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /tmp/grafana-provisioning/dashboards
EOF
cat > /tmp/grafana-provisioning/dashboards/boston-house-app.json <<'EOF'
${local.grafana_dashboard}
EOF
/run.sh
        EOT
      ]

      portMappings = [{ containerPort = 3000, protocol = "tcp" }]

      environment = [
        { name = "GF_SECURITY_ADMIN_USER", value = "admin" },
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = "admin" },
        { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
        { name = "GF_PATHS_PROVISIONING", value = "/tmp/grafana-provisioning" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.grafana_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])

  tags = { Environment = var.environment_name }
}

resource "aws_ecs_service" "grafana" {
  name            = "${var.project_name}-${var.environment_name}-grafana-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.grafana_ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana_tg.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 90

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.grafana_http, aws_ecs_service.prometheus]
  tags       = { Environment = var.environment_name }
}

# ─────────────────────────────────────────────────────────────
# Monitoring Outputs
# ─────────────────────────────────────────────────────────────

output "mlflow_url" {
  description = "URL del MLflow Tracking Server"
  value       = "http://${aws_lb.mlflow.dns_name}/"
}

output "prometheus_url" {
  description = "URL del servidor Prometheus"
  value       = "http://${aws_lb.prometheus.dns_name}/"
}

output "grafana_url" {
  description = "URL del dashboard Grafana"
  value       = "http://${aws_lb.grafana.dns_name}/"
}
