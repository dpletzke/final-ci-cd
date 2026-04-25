variable "environment_name" {
  description = "Environment name (staging or production)"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "final-ci-cd"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "lab_role_arn" {
  description = "ARN of the Lab Role for ECS task execution"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ALBs and ECS tasks"
  type        = list(string)
}
