# infra/main.tf

terraform {
  required_version = ">= 1.6.0"
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.project_name}-${var.environment_name}-task"
  retention_in_days = 7
  tags              = { Environment = var.environment_name }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment_name}-cluster"
  tags = { Environment = var.environment_name }
}

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg-${var.environment_name}"
  description = "Permite trafico HTTP al ALB"
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

resource "aws_security_group" "ecs_sg" {
  name        = "${var.project_name}-ecs-sg-${var.environment_name}"
  description = "Permite trafico desde el ALB al contenedor"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.subnet_ids
  tags               = { Environment = var.environment_name }
}

resource "aws_lb_target_group" "ecs_tg" {
  name        = "${var.project_name}-tg-${var.environment_name}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "8000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = var.lab_role_arn
  execution_role_arn       = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-${var.environment_name}-container"
      image = var.docker_image_uri

      portMappings = [
        { containerPort = 8000, protocol = "tcp" }
      ]

      environment = [
        { name = "FLASK_SECRET_KEY",    value = var.secret_key },
        { name = "MLFLOW_TRACKING_URI", value = "http://${aws_lb.mlflow.dns_name}/" },
        { name = "ENVIRONMENT",         value = var.environment_name }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = { Environment = var.environment_name }
}

resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-${var.environment_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "${var.project_name}-${var.environment_name}-container"
    container_port   = 8000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]
  tags       = { Environment = var.environment_name }
}

# ─── MLflow Tracking Server ───────────────────────────────────────────────────

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
  cpu                      = "256"
  memory                   = "512"
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
